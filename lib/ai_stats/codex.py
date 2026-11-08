"""Weekly token usage from Codex sessions.

Reads the rollouts under ~/.codex/sessions and ~/.codex/archived_sessions
(CODEX_HOME is honored). Codex writes one token_usage_record per model response
(observed in 0.160.0), counted once by its response_id; its input_tokens include
the cached and cache-write tokens. Each rollout (subagent threads have their
own) counts as a session in the week (local time, from Monday) it started; with
--window, each response counts in the request window of its timestamp.
"""
import json
import math
import os
from pathlib import Path

from . import parse_time, ratio

LEGEND = """\
weighted = uncached_input + 0.1*cached_input + 8*output [tokens]
weights  = legacy fixed comparison weights, not model pricing or actual spend
per req  = weighted / requests [tokens]
"""


TOKEN_FIELDS = {
    "input": "input_tokens", "cache_read": "cached_input_tokens",
    "cache_write": "cache_write_input_tokens", "output": "output_tokens",
    "reasoning": "reasoning_output_tokens", "total": "total_tokens",
}
METRICS = ["input", "uncached", "cache_read", "cache_write", "output", "reasoning", "total", "weighted"]

SPLIT_ROWS = [("requests", "requests")] + [(k, "tokens") for k in METRICS]
SPLIT_LEGEND = "values are per session; unknown means a measurement was not recorded\n" + LEGEND


def number(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= 0 else None


def total(values):
    values = list(values)
    return None if any(v is None for v in values) else sum(values)


def display(value):
    return "unknown" if value is None else f"{value:,.0f}"


def read_session(path):
    """Keep only usage/metadata, never conversation content."""
    row = {"path": str(path), "id": str(path), "start": None, "project": "",
           "parent_thread_id": None, "request_times": [], "events": []}
    model = context_window = None
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if not isinstance(record, dict):
                continue
            try:
                time = parse_time(record["timestamp"])
            except (KeyError, AttributeError, TypeError, ValueError):
                continue
            if row["start"] is None:
                row["start"] = time
            payload = record.get("payload")
            if not isinstance(payload, dict):
                continue
            kind = record.get("type")
            if kind == "session_meta":
                row.update(id=payload.get("id") or str(path),
                           project=payload.get("cwd") or "",
                           parent_thread_id=payload.get("parent_thread_id"))
                try:
                    row["start"] = parse_time(payload.get("timestamp") or record["timestamp"])
                except (AttributeError, TypeError, ValueError):
                    row["start"] = time
                # Forked history can contain earlier usage and cumulative counters.
                row["inherited"] = bool(payload.get("forked_from_id") or payload.get("history_base"))
            elif kind == "turn_context":
                model = payload.get("model")
            elif kind == "token_usage_record" and isinstance(payload.get("usage"), dict):
                row["request_times"].append({"time": time, "key": payload.get("response_id"),
                    "owner": payload.get("thread_id") or row["id"], "usage": payload["usage"],
                    "model": model, "context_window": context_window, "source": "response"})
            elif kind == "event_msg" and payload.get("type") == "token_count":
                info = payload.get("info")
                if not isinstance(info, dict):
                    continue
                context_window = number(info.get("model_context_window"))
                # The token_count following a response also supplies its window.
                if row["request_times"]:
                    row["request_times"][-1]["context_window"] = context_window
                row["events"].append({"time": time, "usage": info.get("last_token_usage"),
                    "cumulative": info.get("total_token_usage"), "model": model,
                    "context_window": context_window, "source": "token_count"})
    return row


def read_sessions():
    home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    rows = [read_session(path) for directory in ("sessions", "archived_sessions")
            for path in sorted((home / directory).glob("**/*.jsonl"))]
    sessions = {}
    for row in rows:
        if row["start"] is not None:
            sessions.setdefault(row["id"], {**row, "request_times": [], "events": []})
    seen = set()
    # Prefer records in the owning rollout, where model metadata is authoritative.
    responses = [(row, r) for row in rows for r in row["request_times"]]
    responses.sort(key=lambda pair: pair[1]["owner"] != pair[0]["id"])
    direct_ids = {row["id"] for row in rows if row["request_times"]}
    for row, request in responses:
        owner = request["owner"]
        target = sessions.get(owner, sessions.get(row["id"]))
        if target is None or request["time"] < target["start"]:
            continue
        key = request["key"]
        if key is None:
            # Missing IDs must not collapse all responses into one. Exact copies
            # can still be recognized by owner, timestamp and usage.
            key = (owner, request["time"], json.dumps(request["usage"], sort_keys=True))
        if key in seen:
            continue
        seen.add(key)
        if owner != row["id"]:
            request = {**request, "model": None, "context_window": None}
        target["request_times"].append(request)
        direct_ids.add(target["id"])
    # token_count records expose last usage plus cumulative usage. Never
    # sum the cumulative counters or combine this fallback with response records.
    for row in rows:
        target = sessions.get(row["id"])
        if target is None or row["id"] in direct_ids:
            continue
        previous = None
        for event in row["events"]:
            cumulative = event["cumulative"]
            if not isinstance(cumulative, dict) or not isinstance(event["usage"], dict):
                continue
            counter = number(cumulative.get("total_tokens"))
            old = number(previous.get("total_tokens")) if previous else None
            previous = cumulative
            if event["time"] < row["start"] or counter is None or counter == 0:
                continue
            if old is not None and counter <= old:
                continue
            if old is None and row.get("inherited"):
                continue
            key = (row["id"], json.dumps(cumulative, sort_keys=True))
            if key in seen:
                continue
            seen.add(key)
            target["request_times"].append(event)
    result = []
    for row in sessions.values():
        requests = row["request_times"]
        if not requests:
            continue
        for r in requests:
            r.update({name: number(r["usage"].get(field)) for name, field in TOKEN_FIELDS.items()})
            r["uncached"] = (max(0, r["input"] - r["cache_read"])
                             if r["input"] is not None and r["cache_read"] is not None else None)
            r["weighted"] = (r["uncached"] + .1 * r["cache_read"] + 8 * r["output"]
                             if all(r[k] is not None for k in ("uncached", "cache_read", "output")) else None)
        row.update({k: total(r[k] for r in requests) for k in METRICS})
        row["requests"] = len(requests)
        row["weighted"] = round(row["weighted"]) if row["weighted"] is not None else None
        row["total_per_request"] = row["total"] / len(requests) if row["total"] is not None else None
        row["context_max"] = (max(r["input"] for r in requests)
                              if all(r["input"] is not None for r in requests) else None)
        row["context_windows"] = sorted({r["context_window"] for r in requests if r["context_window"] is not None})
        row["models"] = sorted({r["model"] for r in requests if r["model"]})
        row["unknown_model_requests"] = sum(r["model"] is None for r in requests)
        row["usage_source"] = requests[0]["source"]
        row["request_count_basis"] = ("observed cumulative advances" if row["usage_source"] == "token_count"
                                      else "deduplicated responses")
        row["unknown_context_window_requests"] = sum(r["context_window"] is None for r in requests)
        row["cost"] = None
        row.pop("events", None)
        row.pop("inherited", None)
        result.append(row)
    return sorted(result, key=lambda s: s["start"])


def print_windows(sessions, windows):
    groups = {}
    details = {}
    for session, row in enumerate(sessions):
        entries = ([(row["start"], row["requests"], row["weighted"], row["request_times"])] if windows.weekly else
                   [(r["time"], 1, r["weighted"], [r]) for r in row["request_times"]])
        for time, requests, weighted, records in entries:
            key = windows.key(time)
            group = groups.setdefault(key, [set(), 0, 0])
            group[0].add(session)
            group[1] += requests
            group[2] = total([group[2], weighted])
            details.setdefault(key, []).extend(records)

    sums = {key: (len(ids), requests, round(weighted) if weighted is not None else None, weighted / requests if weighted is not None else None)
            for key, (ids, requests, weighted) in groups.items()}
    print("Token details: input includes cache read/write; reasoning is part of output.")
    print("Context uses input tokens as a proxy, not a measured live context size; cost is unknown.")
    print("unknown = missing measurement; token_count-only requests are observed cumulative advances.")
    for key, records in sorted(details.items()):
        if not windows.shown(key):
            continue
        print(f"details {windows.label(key).strip()}: " + ", ".join(
            f"{metric}={display(total(r[metric] for r in records))}" for metric in TOKEN_FIELDS))
        models = sorted({r["model"] for r in records if r["model"]})
        limits = sorted({r["context_window"] for r in records if r["context_window"] is not None})
        print("  models=" + (", ".join(models) or "unknown") +
              f"; unknown model requests={sum(r['model'] is None for r in records)}; " +
              "context windows=" + (", ".join(map(str, limits)) or "unknown") +
              f"; unknown window requests={sum(r['context_window'] is None for r in records)}; " +
              "input max=" + display(max(r["input"] for r in records)
                                     if all(r["input"] is not None for r in records) else None))

    print(LEGEND + windows.vs_prev() + windows.column("session"))
    print(f"{windows.heading:<{windows.width}}{'sessions':>10}{'requests':>10}{'weighted (tok)':>16}"
          f"{'per req (tok)':>15}{'weighted vs prev':>18}{'per req vs prev':>17}")
    for key, (n, requests, weighted, per_request) in sorted(sums.items()):
        if not windows.shown(key):
            continue
        previous = sums.get(key - windows.step)
        print(f"{windows.label(key)}{n:>10}{requests:>10,}{display(weighted):>16}{display(per_request):>15}"
              f"{ratio(previous and previous[2], weighted):>18}"
              f"{ratio(previous and previous[3], per_request):>17}")
