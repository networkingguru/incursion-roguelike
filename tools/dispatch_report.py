#!/usr/bin/env python3
"""Report DeepSeek runs and agent dispatches over a date window (bead inc-xiqb).

USAGE
  tools/dispatch_report.py --since YYYY-MM-DD [--until YYYY-MM-DD]

`--since` is inclusive from 00:00 UTC. `--until` is exclusive at 00:00 UTC; when
it is omitted the window runs up to now. Requires `--since`.

INPUTS
  INCURSION_DEEPSEEK_LEDGER   ledger JSONL (default
                              ~/Scripts/Incursion/logs/deepseek-ledger.jsonl).
                              A row counts as a DeepSeek RUN only when its
                              `harness` is `opencode`; every other row (a
                              different harness, or none) is a single request.
  INCURSION_DISPATCH_LOG      dispatch log JSONL (default
                              ~/Scripts/Incursion/logs/dispatch-log.jsonl).

A missing file counts as empty and is named in a note. Lines that are not JSON
are skipped and counted in a note.

Exit: 0 reported, 2 bad usage or unreadable arguments. Standard library only.
"""

import argparse
import datetime
import json
import os
import sys
from pathlib import Path

DEFAULT_LEDGER = "~/Scripts/Incursion/logs/deepseek-ledger.jsonl"
DEFAULT_DISPATCH = "~/Scripts/Incursion/logs/dispatch-log.jsonl"

KILLED_REASONS = ("loop", "context", "idle", "startup")
SHARE_LABEL_EXCLUDE = ("research", "repro-design")


def parse_day(text):
    try:
        return datetime.datetime.strptime(text, "%Y-%m-%d").replace(
            tzinfo=datetime.timezone.utc)
    except ValueError:
        raise SystemExit(f"dispatch_report: bad date (want YYYY-MM-DD): {text}")


def parse_ts(text):
    if not isinstance(text, str):
        return None
    try:
        dt = datetime.datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    return dt.replace(tzinfo=datetime.timezone.utc)


def read_rows(path):
    """Return (rows, skipped_lines, missing)."""
    p = Path(path).expanduser()
    if not p.is_file():
        return [], 0, True
    rows, skipped = [], 0
    try:
        text = p.read_text()
    except OSError:
        return [], 0, True
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            skipped += 1
            continue
        if isinstance(obj, dict):
            rows.append(obj)
    return rows, skipped, False


def in_window(ts, since, until):
    if ts is None or ts < since:
        return False
    if until is not None and ts >= until:
        return False
    return True


def label_of(description):
    """Reduce a description to its label word: research, repro-design,
    fallback, or none."""
    if not isinstance(description, str):
        return "none"
    stripped = description.lstrip().lower()
    for word in ("research", "repro-design", "fallback"):
        if stripped.startswith(word + ":"):
            return word
    return "none"


def collect_ledger(rows, skipped, missing, since, until):
    runs = {"total": 0, "finished": 0}
    killed = {r: 0 for r in KILLED_REASONS}
    cost = 0.0
    null_cost = 0
    singles = 0
    for row in rows:
        ts = parse_ts(row.get("ts"))
        if not in_window(ts, since, until):
            continue
        if row.get("harness") != "opencode":
            singles += 1
            continue
        runs["total"] += 1
        reason = row.get("killed")
        if reason in killed:
            killed[reason] += 1
        else:
            runs["finished"] += 1
        c = row.get("cost")
        if c is None:
            null_cost += 1
            cost += 0.0
        else:
            try:
                cost += float(c)
            except (TypeError, ValueError):
                null_cost += 1
    return runs, killed, cost, null_cost, singles


def collect_dispatches(rows, since, until):
    by_decision = {"allow": 0, "block": 0, "bypass": 0}
    by_model_label = {}  # (model, label) -> count, allow/bypass only
    share_m = 0
    for row in rows:
        ts = parse_ts(row.get("ts"))
        if not in_window(ts, since, until):
            continue
        decision = row.get("decision")
        if decision not in by_decision:
            continue
        by_decision[decision] += 1
        if decision not in ("allow", "bypass"):
            continue
        model = row.get("model")
        if model is None:
            model = "inherit"
        model = str(model)
        label = label_of(row.get("description"))
        key = (model, label)
        by_model_label[key] = by_model_label.get(key, 0) + 1
        if model != "haiku" and label not in SHARE_LABEL_EXCLUDE:
            share_m += 1
    return by_decision, by_model_label, share_m


def main(argv):
    parser = argparse.ArgumentParser(
        prog="dispatch_report.py",
        description="Report DeepSeek runs and agent dispatches over a window.")
    parser.add_argument("--since", required=True,
                        help="inclusive from 00:00 UTC, YYYY-MM-DD")
    parser.add_argument("--until", default=None,
                        help="exclusive at 00:00 UTC, YYYY-MM-DD")
    args = parser.parse_args(argv)

    since = parse_day(args.since)
    until = parse_day(args.until) if args.until else datetime.datetime.now(
        datetime.timezone.utc)

    ledger_path = os.environ.get("INCURSION_DEEPSEEK_LEDGER", DEFAULT_LEDGER)
    dispatch_path = os.environ.get("INCURSION_DISPATCH_LOG", DEFAULT_DISPATCH)

    lrows, lskip, lmiss = read_rows(ledger_path)
    drows, dskip, dmiss = read_rows(dispatch_path)

    runs, killed, cost, null_cost, singles = collect_ledger(
        lrows, lskip, lmiss, since, until)
    by_decision, by_model_label, share_m = collect_dispatches(
        drows, since, until)

    out = []
    out.append(f"DeepSeek runs: {runs['total']} total, "
               f"{runs['finished']} finished")
    for reason in KILLED_REASONS:
        out.append(f"  stopped by {reason}: {killed[reason]}")
    cost_note = f" (null cost counts 0{'; ' + str(null_cost) + ' null' if null_cost else ''})"
    out.append(f"DeepSeek total cost: ${cost:.3f} USD{cost_note}")
    out.append(f"DeepSeek single requests: {singles}")

    out.append("dispatches: allow %d, block %d, bypass %d"
               % (by_decision["allow"], by_decision["block"],
                  by_decision["bypass"]))

    allowed_by = sorted(
        (k for k in by_model_label.items()),
        key=lambda kv: (kv[0][1] != "none", kv[0][1], kv[0][0]))
    lines = [f"{model} {label} {count}"
             for (model, label), count in allowed_by]
    if lines:
        out.append("  " + "; ".join(lines))

    n = runs["total"]
    if n == 0 and share_m == 0:
        pct = "n/a"
    else:
        pct = f"{100.0 * n / (n + share_m):.0f}%"
    out.append(
        f"implementation share: DeepSeek {n} runs, "
        f"sonnet/opus/inherit {share_m} (fallback + bypass + "
        f"unlabelled-allowed), DeepSeek {pct}")

    if lmiss:
        out.append(f"note: ledger file missing, counted as empty: {ledger_path}")
    if lskip:
        out.append(f"note: ledger skipped {lskip} non-JSON line(s)")
    if dmiss:
        out.append(f"note: dispatch log missing, counted as empty: "
                   f"{dispatch_path}")
    if dskip:
        out.append(f"note: dispatch log skipped {dskip} non-JSON line(s)")

    print("\n".join(out))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:
        sys.exit(0)
