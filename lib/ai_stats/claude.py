"""Weekly token usage from Claude Code transcripts.

Reads ~/.claude/projects/**/*.jsonl (CLAUDE_CONFIG_DIR is honored), counts each
API request once (by requestId or message id), and prints per-week sums (or per
fixed-length window with --window), or the mean, standard deviation and median
per session split into before/after groups.
"""
import json
import os
from pathlib import Path

from . import parse_time, ratio

# Input-token equivalents per token, from the Anthropic price ratios:
# cache write 1.25x (5 min) or 2x (1 h), cache read 0.1x, output 5x input.
WEIGHTS = {"input": 1.0, "write_5m": 1.25, "write_1h": 2.0, "read": 0.1, "output": 5.0}
# Rows of the before/after comparison: metric, unit.
SPLIT_ROWS = [("requests", "requests"), ("input", "tokens"), ("cache_write", "tokens"),
              ("cache_read", "tokens"), ("output", "tokens"), ("weighted", "tokens"),
              ("total_per_request", "tokens")]
SPLIT_LEGEND = """\
values are per session
weighted          = input + 1.25*cache_write_5m + 2*cache_write_1h + 0.1*cache_read + 5*output
weights           = legacy fixed comparison weights, not model pricing or actual spend
total_per_request = (input + cache_write + cache_read + output) / requests"""
WEEKLY_LEGEND = """\
weighted = input + 1.25*cache_write_5m + 2*cache_write_1h + 0.1*cache_read + 5*output [tokens]
weights  = legacy fixed comparison weights, not model pricing or actual spend
per req  = weighted / requests [tokens]
read/req = cache_read / requests [tokens], roughly the context each request resends
read/wr  = cache_read / cache_write (-: no cache_write)
"""

def read_session(path):
    seen = set()
    start = None
    request_times = []  # (time, weighted, cache_write, cache_read) per request
    totals = dict.fromkeys(["requests", "input", "write_5m", "write_1h", "read", "output"], 0)
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = record.get("timestamp")
            if ts and start is None:
                start = parse_time(ts)
            message = record.get("message")
            usage = message.get("usage") if isinstance(message, dict) else None
            if not usage:
                continue
            key = record.get("requestId") or message.get("id")
            if key in seen:
                continue
            seen.add(key)
            creation = usage.get("cache_creation") or {}
            write_1h = creation.get("ephemeral_1h_input_tokens", 0) or 0
            write_all = usage.get("cache_creation_input_tokens", 0) or 0
            request = {"input": usage.get("input_tokens", 0) or 0, "write_5m": write_all - write_1h,
                       "write_1h": write_1h, "read": usage.get("cache_read_input_tokens", 0) or 0,
                       "output": usage.get("output_tokens", 0) or 0}
            totals["requests"] += 1
            for k, v in request.items():
                totals[k] += v
            request_times.append((parse_time(ts) if ts else None,
                                  sum(request[k] * w for k, w in WEIGHTS.items()),
                                  write_all, request["read"]))
    if not totals["requests"] or start is None:
        return None
    t = totals
    return {
        "path": str(path),
        "start": start,
        "requests": t["requests"],
        "input": t["input"],
        "cache_write": t["write_5m"] + t["write_1h"],
        "cache_read": t["read"],
        "output": t["output"],
        "total": t["input"] + t["write_5m"] + t["write_1h"] + t["read"] + t["output"],
        "weighted": round(sum(t[k] * w for k, w in WEIGHTS.items())),
        # Roughly the context size each request resends.
        "total_per_request": round((t["input"] + t["write_5m"] + t["write_1h"] + t["read"]
                                    + t["output"]) / t["requests"]),
        "request_times": request_times,
    }


def print_windows(sessions, windows):
    """Print per-window sums of the shown windows with the ratio to the window
    before. Weekly, whole sessions count in the week they started; otherwise
    each request counts in the window of its timestamp."""
    if windows.weekly:
        entries = [(s["start"], i, s["requests"], s["weighted"], s["cache_write"], s["cache_read"])
                   for i, s in enumerate(sessions)]
    else:
        entries = [(time or s["start"], i, 1, weighted, write, read)
                   for i, s in enumerate(sessions)
                   for time, weighted, write, read in s["request_times"]]
    groups = {}
    for time, session, *values in entries:
        group = groups.setdefault(windows.key(time), [set(), 0, 0, 0, 0])
        group[0].add(session)
        for i, value in enumerate(values, 1):
            group[i] += value
    sums = {key: (len(ids), requests, round(weighted), weighted / requests, read / requests,
                  f"{read / write:.1f}" if write else "-")
            for key, (ids, requests, weighted, write, read) in groups.items()}
    print(WEEKLY_LEGEND + windows.vs_prev() + windows.column("session"))
    print(f"{windows.heading:<{windows.width}}{'sessions':>10}{'requests':>10}{'weighted (tok)':>16}"
          f"{'per req (tok)':>15}{'weighted vs prev':>18}{'per req vs prev':>17}"
          f"{'read/req (tok)':>16}{'read/wr':>9}")
    for key, (n, requests, weighted, per_request, read_per_request, read_write) in sorted(sums.items()):
        if not windows.shown(key):
            continue
        previous = sums.get(key - windows.step)
        print(f"{windows.label(key)}{n:>10}{requests:>10,}{weighted:>16,}{per_request:>15,.0f}"
              f"{ratio(previous and previous[2], weighted):>18}"
              f"{ratio(previous and previous[3], per_request):>17}"
              f"{read_per_request:>16,.0f}{read_write:>9}")


def read_sessions():
    root = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")) / "projects"
    for path in sorted(root.glob("**/*.jsonl")):
        row = read_session(path)
        if row:
            row["_project"] = str(path.parent)
            yield row
