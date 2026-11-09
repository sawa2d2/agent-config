"""Shared command-line and time-window semantics for agent usage statistics."""
import argparse
import json
import math
from importlib import import_module
import re
import statistics
import subprocess
from datetime import datetime, timedelta


def parse_time(value):
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return dt if dt.tzinfo else dt.astimezone()


def commit_time(ref, repo):
    out = subprocess.run(["git", "-C", repo, "show", "-s", "--format=%cI", ref],
                         capture_output=True, text=True, check=True).stdout.strip()
    return parse_time(out)


def window_spec(value):
    """argparse type: 'week' or a length such as 5h, 1day, 2d or 1week."""
    if re.fullmatch(r"[1-9][0-9]*day", value):
        value = value[:-3] + "d"
    if re.fullmatch(r"[1-9][0-9]*week", value):
        value = value[:-4] + "w"
    if value != "week" and not re.fullmatch(r"[1-9][0-9]*[hdw]", value):
        raise argparse.ArgumentTypeError(f"expected week or a length such as 5h, 2d, 1w: {value!r}")
    return value


class Windows:
    """Local calendar days/weeks or rolling hours; count=0 shows all windows."""

    def __init__(self, spec, count):
        self.spec, self.count = spec, count
        self.weekly = spec == "week"
        self.calendar = self.weekly or spec.endswith(("d", "w"))
        now = datetime.now().astimezone()
        if self.weekly:
            self.step, self.unit, self.heading, self.width = timedelta(weeks=1), "week", "week", 12
            today = now.date()
            self.first = today - timedelta(days=today.weekday(), weeks=count - 1)
        else:
            units = {"h": "hours", "d": "days", "w": "weeks"}
            self.step = timedelta(**{units[spec[-1]]: int(spec[:-1])})
            self.unit, self.heading, self.width = "window", "start", 18
            if self.calendar:
                # Date arithmetic keeps midnight boundaries intact across DST.
                self.end = now.date() + timedelta(days=1)
                if spec.endswith("w"):
                    self.end = now.date() + timedelta(days=7 - now.weekday())
            else:
                self.end = now
            self.first = self.end - self.step * count

    def key(self, time):
        """The week's Monday, or the start time of the window containing `time`."""
        if self.weekly:
            day = time.astimezone().date()
            return day - timedelta(days=day.weekday())
        if self.calendar:
            day = time.astimezone().date()
            return self.first + self.step * ((day - self.first) // self.step)
        return self.end - self.step * ((self.end - time) // self.step + 1)

    def shown(self, key):
        return not self.count or key >= self.first

    def label(self, key):
        label = (key.isoformat() if self.weekly else
                 f"{key.isoformat()} 00:00" if self.calendar else
                 key.astimezone().strftime('%Y-%m-%d %H:%M'))
        return f"{label:<{self.width}}"

    def previous(self, groups):
        """Daily comparisons skip absent/zero days, including hidden history."""
        if self.spec == "1d":
            keys = sorted(groups)
            return {key: groups[prev] for prev, key in zip(keys, keys[1:])}
        return {key: groups.get(key - self.step) for key in groups}

    def vs_prev(self):
        if self.spec == "1d":
            return ("vs prev  = this day / previous retained day * 100 [%] "
                    "(-: missing, unknown or zero baseline)\n"
                    "           days with zero usage are omitted; unknown usage is retained\n")
        u = self.unit
        return f"vs prev  = this {u} / previous {u} * 100 [%] (-: no previous {u}, or it was 0)\n"

    def column(self, item, event="started"):
        """Legend line defining the first column and what counts in it."""
        if self.weekly:
            return f"week     = Monday (local time) of the week each {item} {event}\n"
        end = ("next Monday at 00:00" if self.spec.endswith("w") else
               "tomorrow at 00:00" if self.calendar else "now")
        return (f"start    = start (local time) of each {self.spec} window, the last ending {end}; each\n"
                f"           request counts in the window of its timestamp, and each {item} in\n"
                f"           every window it has requests in\n")


def arguments():
    example = "aistats codex"
    examples = f"""\
--since/--until select sessions by start time (Bob: budget-owning task).
TIME is an ISO 8601 date or date-time; without an offset it is local time.
--project matches Claude's transcript directory, Codex's cwd or Bob's directory.
--json emits JSON Lines per session; --window/-w and splits affect text only.

examples:
  {example}                                  last 10 calendar days
  {example} --since 2026-10-01 --until 2026-11-01
                                             sessions started in October
  {example} --window 5h -w 6                 last six 5-hour windows
  {example} --split 2026-11-01T00:00Z        before/after a UTC time
  {example} --split-commit HEAD~3 --repo .   before/after a commit
  {example} --project my-repo --min-requests 3 --json
"""
    parser = argparse.ArgumentParser(description="Token and cost usage from local agent sessions.", epilog=examples,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("agent", choices=("claude", "bob", "codex"),
                        help="agent whose local usage records to read")
    parser.add_argument("--since", metavar="TIME",
                        help="only sessions starting at or after this ISO time")
    parser.add_argument("--until", metavar="TIME",
                        help="only sessions starting before this ISO time")
    split = parser.add_mutually_exclusive_group()
    split.add_argument("--split", help="ISO time dividing sessions into before/after")
    split.add_argument("--split-commit", metavar="REF",
                       help="split at the committer time of this git commit")
    parser.add_argument("--repo", default=".", help="repository for --split-commit (default: .)")
    parser.add_argument("--project", help="only project paths containing this substring")
    parser.add_argument("--min-requests", type=int, default=1,
                        help="skip sessions with fewer API requests (default: 1)")
    parser.add_argument("--window", type=window_spec, default="1day",
                        help="aggregation window: week (local, from Monday) or a length such as "
                             "5h (ending now), 2d (ending tomorrow at local 00:00), "
                             "1w/1week (ending next Monday at local 00:00); default: 1day (1d)")
    parser.add_argument("-w", "--windows", "--weeks", type=int,
                        help="windows shown without a split, including the current one "
                             "(0: all; default: 10, or 0 with --since/--until)")
    parser.add_argument("--json", action="store_true", help="print per-session rows as JSON")
    args = parser.parse_args()
    if args.windows is not None and args.windows < 0:
        parser.error("--windows must be nonnegative")
    if args.min_requests < 1:
        parser.error("--min-requests must be positive")
    try:
        args.since = parse_time(args.since) if args.since else None
        args.until = parse_time(args.until) if args.until else None
        args.cut = (parse_time(args.split) if args.split else
                    commit_time(args.split_commit, args.repo) if args.split_commit else None)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        parser.error(str(exc))
    if args.since and args.until and args.since >= args.until:
        parser.error("--since must precede --until")
    args.windows = (args.windows if args.windows is not None else
                    0 if args.since or args.until else 10)
    return args


def selected(row, args):
    return (row["requests"] >= args.min_requests
            and (not args.since or row["start"] >= args.since)
            and (not args.until or row["start"] < args.until)
            and (not args.project or args.project in row.get("_project", row.get("project", ""))))


def print_json(sessions):
    # JSON Lines remain per-session data, independent of display windows/splits.
    for s in sessions:
        row = {k: v for k, v in s.items() if k != "request_times" and not k.startswith("_")}
        print(json.dumps({**row, "start": s["start"].isoformat()}))


def print_split(sessions, cut, metrics, legend):
    print(f"split at {cut.isoformat()}")
    print(legend)
    for name, rows in (("before", [s for s in sessions if s["start"] < cut]),
                       ("after", [s for s in sessions if s["start"] >= cut])):
        print(f"{name}: {len(rows)} sessions")
        if not rows:
            continue
        print(f"  {'metric':<19}{'unit':<10}{'mean':>12}{'stdev':>12}{'median':>12}")
        for metric, unit in metrics:
            values = [s.get(metric) for s in rows]
            if any(v is None for v in values):
                print(f"  {metric:<19}{unit:<10}{'unknown':>12}{'-':>12}{'-':>12}")
                continue
            mean = statistics.fmean(values)
            stdev = statistics.stdev(values) if len(values) > 1 else 0
            median = statistics.median(values)
            precision = 3 if unit == "recorded" else 0
            print(f"  {metric:<19}{unit:<10}{mean:>12,.{precision}f}"
                  f"{stdev:>12,.{precision}f}{median:>12,.{precision}f}")


def ratio(previous, current):
    """Current as a percentage of previous; unknown or zero baselines have no ratio."""
    if not previous or current is None or not math.isfinite(previous) or not math.isfinite(current):
        return "-"
    return f"{current / previous * 100:.1f}%"


def main():
    args = arguments()
    backend = import_module(f".{args.agent}", __package__)
    sessions = sorted((row for row in backend.read_sessions() if selected(row, args)),
                      key=lambda row: row["start"])
    if args.json:
        print_json(sessions)
    elif args.cut:
        print_split(sessions, args.cut, backend.SPLIT_ROWS, backend.SPLIT_LEGEND)
    else:
        backend.print_windows(sessions, Windows(args.window, args.windows))
