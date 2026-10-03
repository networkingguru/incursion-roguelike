#!/usr/bin/env python3
"""PreToolUse gate for Agent/Task dispatches (bead inc-xiqb).

THE RULE. An Agent/Task dispatch that names the DeepSeek-led subagent models
(the ones this project pays for or inherits) must carry a label, unless it is
explicitly a haiku dispatch or the emergency bypass is set:

  * `model` haiku                 -> allowed, always. (Labelled if it has one.)
  * any other `model` value, or a
    dispatch with no `model` at
    all (it inherits the
    session's model, which is
    opus)                         -> allowed ONLY when `description`,
                                     with leading whitespace stripped and
                                     lowercased, starts with one of:
                                       research:
                                       repro-design:
                                       fallback: <run-id>

  `fallback: <run-id>` spends the DeepSeek retry budget a stopped run left
  behind, and it is only valid when TWO stopped DeepSeek runs exist for the
  SAME worktree: the run it names must be in the ledger, its `killed` must be
  `loop` or `context`, AND an EARLIER row with the same worktree must also
  have been stopped by `loop` or `context`. In other words a fallback needs
  two stopped DeepSeek runs for the same worktree -- the earlier one is the
  right to try again, the named one is what is being spent.

Every Agent/Task call is appended to the dispatch log as one JSON line, so a
human can see what was dispatched and why it was let through.

ENV VARS.
  INCURSION_DISPATCH_GATE_OFF=1  emergency bypass: allow every dispatch and
                                 record the decision as `bypass`.
  INCURSION_DISPATCH_LOG          override the dispatch log path.
                                  Default: ~/Scripts/Incursion/logs/dispatch-log.jsonl
  INCURSION_DEEPSEEK_LEDGER       override the ledger path (the same variable
                                  tools/deepseek.py uses).
                                  Default: ~/Scripts/Incursion/logs/deepseek-ledger.jsonl

Exit 0 lets the call through; exit 2 blocks it and the stderr text becomes the
reason shown to the calling agent. Standard library only.
"""

import datetime
import json
import os
import sys
from pathlib import Path

DEFAULT_LOG = "~/Scripts/Incursion/logs/dispatch-log.jsonl"
DEFAULT_LEDGER = "~/Scripts/Incursion/logs/deepseek-ledger.jsonl"

LABELS = ("research:", "repro-design:", "fallback:")
STOPPED = ("loop", "context")

BLOCK_MESSAGE = (
    "dispatch gate: this Agent/Task dispatch is unlabelled.\n"
    "An opus/sonnet/inherited dispatch must start its description with one of:\n"
    "  research: <...>\n"
    "  repro-design: <...>\n"
    "  fallback: <run-id>\n"
    "Only a haiku dispatch is exempt. A fallback needs two stopped DeepSeek\n"
    "runs for the same worktree: an earlier run stopped by `loop` or `context`\n"
    "and the named run also stopped by `loop` or `context`.\n"
)


def resolve_path(env_name, default):
    override = os.environ.get(env_name)
    return Path(override).expanduser() if override else Path(default).expanduser()


def parse_stdin():
    """Return the hook payload dict, or None if stdin is not a JSON object."""
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except Exception:
        return None
    if not isinstance(payload, dict):
        return None
    return payload


def classify_label(description):
    """Return (label, run): label is research/repro-design/fallback/none, and
    run is the fallback run id or None. The prefix is matched after stripping
    leading whitespace and lowercasing, but the run id is taken verbatim from
    the original text, because it must match a ledger `out` exactly."""
    original = (description or "").lstrip()
    lowered = original.lower()
    if lowered.startswith("research:"):
        return "research", None
    if lowered.startswith("repro-design:"):
        return "repro-design", None
    if lowered.startswith("fallback:"):
        rest = original[len("fallback:"):].strip()
        run = rest.split()[0] if rest.split() else ""
        return "fallback", (run or None)
    return "none", None


def worktree_of(out):
    """The part of a run's `out` path before /logs/opencode/, or the whole
    string when that marker is absent."""
    out = out or ""
    marker = "/logs/opencode/"
    idx = out.find(marker)
    return out[:idx] if idx != -1 else out


def load_ledger(path):
    """Every ledger row that is a JSON object with an `out`. Non-JSON lines
    are skipped silently."""
    rows = []
    if not path.exists():
        return rows
    try:
        text = path.read_text()
    except Exception:
        return rows
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows


def find_run(rows, run_id):
    """The ledger row whose `out` equals run_id or ends with `/`+run_id."""
    for row in rows:
        out = row.get("out") or ""
        if out == run_id or out.endswith("/" + run_id):
            return row
    return None


def has_earlier_stopped(rows, row):
    """Is there another row, stopped by loop/context, whose `ts` is earlier
    than `row`'s, in the same worktree?"""
    row_ts = row.get("ts")
    row_wt = worktree_of(row.get("out"))
    if not row_ts:
        return False
    for other in rows:
        if other is row:
            continue
        other_ts = other.get("ts")
        if not other_ts or other_ts >= row_ts:
            continue
        if other.get("killed") not in STOPPED:
            continue
        if worktree_of(other.get("out")) != row_wt:
            continue
        return True
    return False


def check_fallback(rows, run_id):
    """Return None when the fallback is valid, else the specific reason."""
    if not run_id:
        return "fallback names no run id"
    row = find_run(rows, run_id)
    if row is None:
        return f"fallback run not found: {run_id}"
    if row.get("killed") not in STOPPED:
        return f"fallback run {run_id} was not stopped by loop or context"
    if not has_earlier_stopped(rows, row):
        return (
            f"no earlier stopped run for worktree {worktree_of(row.get('out'))}"
        )
    return None


def append_log(path, entry):
    """Append one JSON line, creating the directory. Returns True on success."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as fh:
            fh.write(json.dumps(entry, separators=(",", ":")) + "\n")
        return True
    except Exception as exc:
        print(f"dispatch gate: could not write the dispatch log: {exc}",
              file=sys.stderr)
        return False


def make_entry(payload, model, subagent_type, description, label, run, decision,
               reason):
    return {
        "ts": datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"),
        "session_id": payload.get("session_id"),
        "cwd": payload.get("cwd"),
        "model": model,
        "subagent_type": subagent_type,
        "label": label,
        "run": run,
        "description": description,
        "decision": decision,
        "reason": reason,
    }


def main():
    log_path = resolve_path("INCURSION_DISPATCH_LOG", DEFAULT_LOG)
    ledger_path = resolve_path("INCURSION_DEEPSEEK_LEDGER", DEFAULT_LEDGER)

    payload = parse_stdin()
    if payload is None:
        print(
            "dispatch gate: the hook could not read its input (stdin was not "
            "a JSON object).",
            file=sys.stderr,
        )
        sys.exit(2)

    tool_name = payload.get("tool_name")
    if tool_name not in ("Agent", "Task"):
        sys.exit(0)

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        tool_input = {}

    model_raw = tool_input.get("model")
    model = model_raw if model_raw else "inherit"
    subagent_type = tool_input.get("subagent_type")
    description = tool_input.get("description")

    label, run = classify_label(description)

    # Emergency bypass: allow everything, record it as such.
    if os.environ.get("INCURSION_DISPATCH_GATE_OFF") == "1":
        entry = make_entry(payload, model, subagent_type, description, label,
                           run, "bypass", None)
        append_log(log_path, entry)
        sys.exit(0)

    reason = None
    decision = "allow"

    if model_raw == "haiku":
        pass
    elif label in ("research", "repro-design"):
        pass
    elif label == "fallback":
        rows = load_ledger(ledger_path)
        reason = check_fallback(rows, run)
        if reason is not None:
            decision = "block"
    else:
        decision = "block"
        reason = "no label"

    entry = make_entry(payload, model, subagent_type, description, label, run,
                       decision, reason)
    append_log(log_path, entry)

    if decision == "block":
        print(BLOCK_MESSAGE, file=sys.stderr)
        print(f"reason: {reason}", file=sys.stderr)
        sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    main()
