"""Weekly token usage and cost from Bob Shell tasks.

Reads ~/.bob/db/bob.db read-only. Bob stores, per model request, the cost and
the context tokens sent in the assistant message's _meta.spend; it records no
input/output/cache breakdown. Each task counts in the week (local time, from
Monday) it was created; with --window, each request (assistant message) counts
in the request window of its messages.created_at, and each task in every
window it has requests in.

A subagent task spends from its parent's session.maxCost budget, and Bob adds
its cost to the parent's tasks.costs, so it counts as part of the parent; a
subtask has a limit of its own and counts as a task (observed in Bob Shell
2.0.9). A task's cost is its tasks.costs.cost, the figure maxCost is compared
with.

Bob compacts a task's context once a request's context tokens reach
session.compactionThresholdPercent of the model's context window. The second
table shows how the requests' context compares with the cross-agent target of
about 100k tokens, and how often Bob compacted; the model lines show the window
the percentage applies to. Bob 2.0.9 keeps the "Compacted N messages" text only
in telemetry, but each compaction stores one assistant message marked
_meta.summary, which later compactions keep.
"""
import json
import math
import sqlite3
from datetime import datetime
from pathlib import Path

from . import ratio

DB_PATH = Path.home() / ".bob/db/bob.db"
COMPACT_TARGET = 100_000  # tokens; the context size every agent is set to compact at
LEGEND = """\
cost     = sum of spend.cost over requests [as recorded by Bob; not an invoice]
unknown  = measurement not recorded; input/output/cache/reasoning are unavailable
per req  = cost / requests
ctx/req  = sum of spend.contextTokens / requests [tokens]
{vs_prev}task p50, task p90, task max
         = median, 90th percentile and maximum of the {unit}'s task costs; a task's
           cost (subagents included) is what session.maxCost limits
ctx p50, ctx p90, ctx max
         = median, 90th percentile and maximum of spend.contextTokens per request [tokens]
>100k req, >100k ctx
         = requests with over 100,000 context tokens / requests, and their summed
           context tokens / all summed context tokens [%]
compacts = compactions (summary messages Bob stores when it compacts)
model    = tasks.env model id and contextWindow [tokens], with the tasks recording them
           (created in the windows shown); Bob compacts at compactionThresholdPercent
           of contextWindow
{column}"""

SPLIT_ROWS = [("requests", "requests"), ("cost", "recorded"),
              ("context", "tokens"), ("context_per_request", "tokens"),
              ("context_p50", "tokens"), ("context_p90", "tokens"), ("context_max", "tokens"),
              ("compactions", "count")]
SPLIT_LEGEND = ("values are per session (budget-owning task, subagents included); "
                "unknown means not recorded")


def local_time(ms):
    return datetime.fromtimestamp(ms / 1000).astimezone()


def percentile(values, fraction):
    """Linear interpolation between the closest ranks of the sorted values."""
    if not values or any(not math.isfinite(v) for v in values):
        return float("nan")
    position = (len(values) - 1) * fraction
    low = int(position)
    high = min(low + 1, len(values) - 1)
    return values[low] + (values[high] - values[low]) * (position - low)


def share(part, whole):
    return "-" if not whole or not math.isfinite(whole) or not math.isfinite(part) else f"{part / whole * 100:.1f}%"


def recorded_cost(costs):
    try:
        cost = json.loads(costs)["cost"]
    except (TypeError, ValueError, KeyError):
        return None
    return cost if isinstance(cost, (int, float)) and math.isfinite(cost) else None


def measured(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) else float("nan")


def known(value):
    return value if math.isfinite(value) else None


def fmt(value, spec=",.0f"):
    return format(value, spec) if math.isfinite(value) else "unknown"


def read_sessions():
    if not DB_PATH.is_file():
        raise SystemExit(f"aistats bob: database not found: {DB_PATH}")

    db = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    tasks = {task_id: (parent, task_type, created, costs, env) for task_id, parent, task_type, created, costs, env
             in db.execute("SELECT id, parent_id, task_type, created_at, costs, env FROM tasks")}

    def limited(task_id):
        """The task whose maxCost budget task_id spends from."""
        while tasks[task_id][1] == "subagent" and tasks[task_id][0] in tasks:
            task_id = tasks[task_id][0]
        return task_id

    projects = dict(db.execute("SELECT id, directory FROM tasks"))
    sessions = {}
    for task_id, data, created in db.execute(
            "SELECT task_id, data, created_at FROM messages WHERE role = 'assistant' "
            "AND task_id IN (SELECT id FROM tasks)"):
        try:
            meta = json.loads(data).get("_meta", {})
        except (ValueError, AttributeError):
            continue
        if not isinstance(meta, dict):
            continue
        owner = limited(task_id)
        row = sessions.setdefault(owner, {"id": owner, "start": local_time(tasks[owner][2]),
            "project": projects.get(owner) or "", "requests": 0, "cost": 0.0,
            "context": 0, "contexts": [], "compactions": 0, "models": [],
            "request_times": [], "_models": [],
            "input": None, "output": None, "cache_read": None, "cache_write": None,
            "reasoning": None, "task_cost": recorded_cost(tasks[owner][3])})
        if meta.get("summary") is True:
            row["compactions"] += 1
        spend = meta.get("spend")
        if isinstance(spend, dict):
            row["requests"] += 1
            row["cost"] += measured(spend.get("cost"))
            context = measured(spend.get("contextTokens"))
            row["context"] += context
            row["contexts"].append(context)
        row["request_times"].append((meta, created))
    for task_id, (_, _, _, _, env) in tasks.items():
        row = sessions.get(limited(task_id))
        if row is None:
            continue
        try:
            model = json.loads(env).get("model")
        except (ValueError, TypeError, AttributeError):
            model = None
        model = ({"id": model.get("id"), "contextWindow": model.get("contextWindow")}
                 if isinstance(model, dict) else {"id": None, "contextWindow": None})
        row["_models"].append(model)
        if model not in row["models"]:
            row["models"].append(model)
    for row in sessions.values():
        contexts = sorted(row.pop("contexts"))
        row["context_p50"] = known(percentile(contexts, .5))
        row["context_p90"] = known(percentile(contexts, .9))
        row["context_max"] = known(percentile(contexts, 1))
        row["cost"] = known(row["cost"])
        row["context"] = known(row["context"])
        row["context_per_request"] = (row["context"] / row["requests"]
                                      if row["context"] is not None and row["requests"] else None)
    db.close()
    return sessions.values()


def print_windows(sessions, windows):
    sessions = {row["id"]: row for row in sessions}
    weeks = {}
    compactions = {}
    messages = ((row["id"], meta, created) for row in sessions.values()
                for meta, created in row["request_times"])
    for task_id, meta, created in messages:
        week = windows.key(sessions[task_id]["start"] if windows.weekly else local_time(created))
        if meta.get("summary") is True:
            compactions[week] = compactions.get(week, 0) + 1
        if not isinstance(meta.get("spend"), dict):
            continue
        spend = meta["spend"]
        w = weeks.setdefault(week, {"tasks": {}, "requests": 0, "context": 0, "cost": 0.0, "contexts": []})
        cost = measured(spend.get("cost"))
        context = measured(spend.get("contextTokens"))
        w["tasks"][task_id] = w["tasks"].get(task_id, 0) + cost
        w["requests"] += 1
        w["context"] += context
        w["contexts"].append(context)
        w["cost"] += cost
    for w in weeks.values():
        # Summed message spend stands in when Bob recorded no task cost.
        w["task costs"] = sorted(c if (c := sessions[task_id]["task_cost"]) is not None else summed
                                 for task_id, summed in w["tasks"].items())

    print(LEGEND.format(unit=windows.unit, vs_prev=windows.vs_prev(), column=windows.column("task", "was created")))
    print(f"{windows.heading:<{windows.width}}{'tasks':>8}{'requests':>10}{'ctx/req (tok)':>15}{'cost':>10}{'per req':>10}"
          f"{'cost vs prev':>14}{'per req vs prev':>17}{'task p50':>10}{'task p90':>10}{'task max':>10}")
    for week, w in sorted(weeks.items()):
        if not windows.shown(week):
            continue
        previous = weeks.get(week - windows.step)
        per_request = w["cost"] / w["requests"]
        costs = w["task costs"]
        print(f"{windows.label(week)}{len(w['tasks']):>8}{w['requests']:>10,}"
              f"{fmt(w['context'] / w['requests']):>15}{fmt(w['cost'], '.2f'):>10}{fmt(per_request, '.3f'):>10}"
              f"{ratio(previous and previous['cost'], w['cost']):>14}"
              f"{ratio(previous and previous['cost'] / previous['requests'], per_request):>17}"
              f"{fmt(percentile(costs, 0.5), '.2f'):>10}{fmt(percentile(costs, 0.9), '.2f'):>10}{fmt(percentile(costs, 1), '.2f'):>10}")

    print()
    print(f"{windows.heading:<{windows.width}}{'ctx p50':>10}{'ctx p90':>10}{'ctx max':>10}{'>100k req':>11}{'>100k ctx':>11}{'compacts':>10}")
    for week, w in sorted(weeks.items()):
        if not windows.shown(week):
            continue
        contexts = sorted(w["contexts"])
        above = [c for c in contexts if c > COMPACT_TARGET]
        print(f"{windows.label(week)}{fmt(percentile(contexts, 0.5)):>10}{fmt(percentile(contexts, 0.9)):>10}"
              f"{fmt(percentile(contexts, 1)):>10}{(share(len(above), len(contexts)) if all(math.isfinite(c) for c in contexts) else '-'):>11}"
              f"{share(sum(above), w['context']):>11}{compactions.get(week, 0):>10}")

    # Bob picks the model; the compaction percentage only means something against its window.
    models = {}
    for row in sessions.values():
        if not windows.shown(windows.key(row["start"])):
            continue
        for model in row["_models"]:
            key = (str(model["id"]), model["contextWindow"]) if model["id"] is not None else None
            models[key] = models.get(key, 0) + 1
    print()
    for key, count in sorted(models.items(), key=lambda item: -item[1]):
        if key is None:
            print(f"model: not recorded (tasks: {count})")
        else:
            window = f"{key[1]:,}" if isinstance(key[1], int) else "-"
            print(f"model: {key[0]}, contextWindow {window} (tasks: {count})")
