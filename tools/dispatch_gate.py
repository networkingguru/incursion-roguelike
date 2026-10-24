#!/usr/bin/env python3
"""PreToolUse gate for Agent/Task dispatches (bead inc-xiqb, bead inc-cfnm).

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
                                       budget:

  `fallback: <run-id>` spends the DeepSeek retry budget a stopped run left
  behind, and it is only valid when TWO stopped DeepSeek runs exist for the
  SAME worktree: the run it names must be in the ledger, its `killed` must be
  `loop`, `context` or `provider`, AND an EARLIER row with the same worktree
  must also have been stopped by `loop`, `context` or `provider`. In other
  words a fallback needs two stopped DeepSeek runs for the same worktree --
  the earlier one is the right to try again, the named one is what is being
  spent. (`provider` is a run the provider stopped with 429/5xx.)

  `budget: <...>` spends the coding-route budget (bead inc-cfnm) and is
  allowed ONLY when BOTH hold: the dispatch's `model` is exactly `sonnet`, and
  tools/claude_budget.py reports `sonnet-first` for the current week. Any other
  model (or no model) is blocked, and so is a `normal`/`unknown` budget state.

  `owner: <...>` lets the project owner authorize a dispatch himself (bead
  inc-vj6i). It is allowed ONLY when ALL hold: the dispatch's `model` is exactly
  `sonnet` or `opus`, the payload carries no truthy `agent_id` (a subagent
  cannot carry the owner's authorization), and the owner's LATEST real user
  message in the dispatch's `transcript_path` names that same model as a whole
  word, with no negation among the three words before it. A missing or
  unreadable transcript is blocked (fail closed).

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
import re
import sys
from pathlib import Path

DEFAULT_LOG = "~/Scripts/Incursion/logs/dispatch-log.jsonl"
DEFAULT_LEDGER = "~/Scripts/Incursion/logs/deepseek-ledger.jsonl"

LABELS = ("research:", "repro-design:", "fallback:", "budget:", "owner:")
STOPPED = ("loop", "context", "provider")

# Transcript reader (mirrors the reader in ~/.claude/hooks/commit-gate.py).
NEGATIONS = {"don't", "dont", "not", "never", "without"}
TAG_RE = re.compile(r"<[A-Za-z][A-Za-z0-9_-]*>.*?</[A-Za-z][A-Za-z0-9_-]*>",
                    re.DOTALL)

BLOCK_MESSAGE = (
    "dispatch gate: this Agent/Task dispatch is unlabelled.\n"
    "An opus/sonnet/inherited dispatch must start its description with one of:\n"
    "  research: <...>\n"
    "  repro-design: <...>\n"
    "  fallback: <run-id>\n"
    "  budget: <...>\n"
    "  owner: <...>\n"
    "Only a haiku dispatch is exempt. A fallback needs two stopped DeepSeek\n"
    "runs for the same worktree: an earlier run stopped by `loop`, `context` or\n"
    "`provider`, and the named run also stopped by one of those. A budget\n"
    "dispatch needs model sonnet and a `sonnet-first` weekly budget. An owner\n"
    "dispatch needs model sonnet or opus and the owner's latest message naming\n"
    "that model.\n"
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
    if lowered.startswith("budget:"):
        return "budget", None
    if lowered.startswith("owner:"):
        return "owner", None
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
        return f"fallback run {run_id} was not stopped by loop, context or provider"
    if not has_earlier_stopped(rows, row):
        return (
            f"no earlier stopped run for worktree {worktree_of(row.get('out'))}"
        )
    return None


def iter_tail_lines(path, cap=8 * 1024 * 1024, chunk=256 * 1024):
    """Yield complete, non-blank lines from the end of `path`, newest first."""
    with open(path, "rb") as fh:
        fh.seek(0, os.SEEK_END)
        size = fh.tell()
        pos = size
        floor = max(0, size - cap)
        held = b""
        while pos > floor:
            read = min(chunk, pos - floor)
            pos -= read
            fh.seek(pos)
            piece = fh.read(read)
            data = piece + held
            parts = data.split(b"\n")
            held = parts[0]
            for line in reversed(parts[1:]):
                line = line.strip()
                if line:
                    yield line.decode("utf-8", "replace")
        if held.strip():
            yield held.decode("utf-8", "replace")


def is_real_user(entry):
    """True only for a genuine human user message (mirrors the commit gate)."""
    if entry.get("type") != "user":
        return False
    if entry.get("isMeta"):
        return False
    if "toolUseResult" in entry:
        return False
    message = entry.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "tool_result":
                return False
    origin = entry.get("origin")
    if origin == "human":
        return True
    if isinstance(origin, dict) and origin.get("kind") == "human":
        return True
    return False


def entry_text(entry):
    """The plain text of an entry's message, with tags blanked."""
    message = entry.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        text = "".join(
            item.get("text", "")
            for item in content
            if isinstance(item, dict) and item.get("type") == "text")
    else:
        text = ""
    return TAG_RE.sub(" ", text)


def latest_owner_message(path):
    """The text of the owner's latest real user message, or None."""
    for line in iter_tail_lines(path):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if not isinstance(entry, dict):
            continue
        if is_real_user(entry):
            return entry_text(entry)
    return None


def check_owner(payload, model_raw):
    """None when an `owner:` dispatch is authorized, else the reason.

    The owner's authorization is the LATEST real user message in the dispatch's
    transcript naming the dispatched model as a whole word, with no negation in
    the three words before it."""
    if model_raw not in ("sonnet", "opus"):
        return "owner label needs model sonnet or opus"
    if payload.get("agent_id"):
        return "owner label refused in a subagent"
    transcript_path = payload.get("transcript_path")
    if not transcript_path:
        return "owner label: no transcript"
    try:
        text = latest_owner_message(transcript_path)
    except OSError as exc:
        return f"owner label: transcript unreadable: {exc}"
    if text is None:
        return "owner label: no owner message found"
    tokens = re.findall(r"[a-z']+", text.lower())
    for i, token in enumerate(tokens):
        if token != model_raw:
            continue
        preceding = tokens[max(0, i - 3):i]
        if any(tok in NEGATIONS for tok in preceding):
            continue
        return None
    return f"owner label: the owner's latest message does not name {model_raw}"


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
    elif label == "budget":
        if model_raw != "sonnet":
            decision = "block"
            reason = "budget label needs model sonnet"
        else:
            try:
                sys.path.insert(0, str(Path(__file__).resolve().parent))
                import claude_budget
                verdict = claude_budget.verdict()
            except Exception as exc:
                decision = "block"
                reason = f"budget verdict unavailable: {exc}"
            else:
                if verdict.get("state") == "sonnet-first":
                    pass
                else:
                    decision = "block"
                    state = verdict.get("state")
                    detail = verdict.get("reason") or (
                        f"day {verdict.get('day')}, used "
                        f"{verdict.get('used')}, threshold "
                        f"{verdict.get('threshold')}")
                    reason = f"budget is {state}: {detail}"
    elif label == "owner":
        reason = check_owner(payload, model_raw)
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
