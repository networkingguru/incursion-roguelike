#!/usr/bin/env bash
#
# resume_gc.sh -- garbage-collect old `resume-YYYY-MM-DD-*` session notes
# from bd memory. (bd inc-gs36)
#
# THE RULE. Delete a bd memory whose key matches `^resume-(\d{4}-\d{2}-\d{2})`
# and whose date parses as a real calendar date and is strictly older than
# TODAY - 7 days. Any other key, and any resume key without a valid date
# (e.g. resume-unified-light), is never deleted. TODAY is the local date, or
# RESUME_GC_TODAY=YYYY-MM-DD. Deletion happens only at the end of a session
# whose transcript's first "entrypoint" is "cli"; anything else (missing,
# unreadable, no entrypoint, sdk-cli) deletes nothing. Each delete is archived
# to logs/resume-gc-archive.jsonl first; a failed archive skips the forget.
#
#   --list          print the keys that would be deleted, one per line
#   --run           archive + forget them, and log a summary line
#   --hook-end      SessionEnd: read stdin JSON, rule 3, detach --run
#   --hook-prompt   UserPromptSubmit: read stdin JSON, warn when asked
#
# RESUME_GC_ROOT overrides the repository root (used by the check).

set -uo pipefail

ROOT="${RESUME_GC_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
LOG_DIR="$ROOT/logs"
ARCHIVE="$LOG_DIR/resume-gc-archive.jsonl"
RUN_LOG="$LOG_DIR/resume-gc.log"

TODAY="${RESUME_GC_TODAY:-$(date +%Y-%m-%d)}"

# --prove-red injection: RESUME_GC_FAULT names a deliberate break. The check
# runs the suite under it and requires a failure. Never set in normal use.
FAULT="${RESUME_GC_FAULT:-}"

# Read bd memories --json exactly once per invocation. One object {key: text}.
# Prints the JSON, or nothing when bd fails or returns an empty/odd payload.
read_memories() {
    local json
    json="$(bd -C "$ROOT" memories --json 2>/dev/null)" || return 0
    [ -n "$json" ] || return 0
    printf '%s' "$json"
}

# The one function that decides the keys; both the delete run and the prompt
# warning call it with the already-read JSON. Prints the keys to delete, one
# per line, and nothing else.
keys_from_json() {
    local json="$1"
    [ -n "$json" ] || return 0
    RESUME_GC_TODAY="$TODAY" RESUME_GC_FAULT="$FAULT" python3 -c '
import json, os, sys, datetime

raw = sys.stdin.read()
try:
    mem = json.loads(raw)
except Exception:
    sys.exit(0)
if not isinstance(mem, dict):
    sys.exit(0)

try:
    today = datetime.date.fromisoformat(sys.argv[1])
except Exception:
    sys.exit(0)
cutoff = today - datetime.timedelta(days=7)

import re
pat = re.compile(r"^resume-(\d{4}-\d{2}-\d{2})")
for key in mem:
    if not isinstance(key, str):
        continue
    m = pat.match(key)
    if not m:
        continue
    try:
        d = datetime.date.fromisoformat(m.group(1))
    except ValueError:
        continue
    if os.environ.get("RESUME_GC_FAULT") == "off-by-one":
        if d <= cutoff:
            print(key)
    elif d < cutoff:
        print(key)
' "$TODAY" <<< "$json"
}

# Full text for a key, straight from the already-read JSON. Under the
# --prove-red fault "per-key-read", this instead re-reads bd once per key, the
# pre-fix behaviour the call-count assertion must catch.
text_from_json() {
    local json="$1" key="$2"
    if [ "$FAULT" = "per-key-read" ]; then
        json="$(read_memories)"
    fi
    [ -n "$json" ] || return 0
    python3 -c '
import json, sys
try:
    mem = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
if isinstance(mem, dict):
    v = mem.get(sys.argv[1], "")
    if isinstance(v, str):
        sys.stdout.write(v)
' "$key" <<< "$json"
}

# Convenience for --list: read once, then decide keys.
list_keys() {
    local json
    json="$(read_memories)"
    keys_from_json "$json"
}

# Archive one key, then forget it. Returns 0 on success, 1 if the archive
# append failed (so the caller skips the forget), 2 if the forget failed (the
# caller records it and continues). $2 is the full text.
archive_and_forget() {
    local key="$1" value="$2" now
    now="$(date +%Y-%m-%dT%H:%M:%S%z)"
    mkdir -p "$LOG_DIR" 2>/dev/null || return 1
    if ! python3 -c '
import json, sys
row = {"key": sys.argv[1], "value": sys.argv[2],
       "deleted_at": sys.argv[3], "rule": "resume-gc 7d"}
with open(sys.argv[4], "a") as f:
    f.write(json.dumps(row) + "\n")
' "$key" "$value" "$now" "$ARCHIVE" 2>/dev/null; then
        return 1
    fi
    if ! bd -C "$ROOT" forget "$key" >/dev/null 2>&1; then
        printf '%s forget-failed %s\n' "$TODAY" "$key" >> "$RUN_LOG" 2>/dev/null
        return 2
    fi
    return 0
}

run() {
    local json listed deleted key value rc
    json="$(read_memories)"
    listed=0
    deleted=0
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        listed=$((listed + 1))
        value="$(text_from_json "$json" "$key")"
        archive_and_forget "$key" "$value"
        rc=$?
        [ "$rc" -eq 0 ] && deleted=$((deleted + 1))
    done < <(keys_from_json "$json")

    mkdir -p "$LOG_DIR" 2>/dev/null
    printf '%s listed=%d deleted=%d\n' "$TODAY" "$listed" "$deleted" \
        >> "$RUN_LOG" 2>/dev/null
}

# First "entrypoint" value anywhere in the transcript, or nothing.
transcript_entrypoint() {
    local path="$1"
    [ -n "$path" ] && [ -r "$path" ] || return 0
    python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if isinstance(d, dict) and "entrypoint" in d:
                v = d["entrypoint"]
                if isinstance(v, str):
                    print(v)
                    sys.exit(0)
except Exception:
    sys.exit(0)
sys.exit(0)
' "$path"
}

hook_end() {
    local input path ep
    input="$(cat)"
    path="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(d, dict):
    v = d.get("transcript_path")
    if isinstance(v, str):
        print(v)
' 2>/dev/null)"
    ep="$(transcript_entrypoint "$path")"
    if [ "$FAULT" != "ignore-entrypoint" ]; then
        [ "$ep" = "cli" ] || exit 0
    fi

    mkdir -p "$LOG_DIR" 2>/dev/null
    nohup "$SELF" --run >> "$LOG_DIR/resume-gc.log" 2>&1 &
    exit 0
}

# True when the prompt asks whether it is safe to clear the session. Matching
# phrasings only; a bare "clear" never matches.
prompt_asks_safe_to_clear() {
    python3 -c '
import re, sys
p = sys.argv[1].lower()
pats = [
    r"\bsafe to clear\b",
    r"\bok to clear\b",
    r"\bokay to clear\b",
    r"\bis it safe to\s*/\s*clear\b",
    r"\bcan i clear\b",
    r"\bgood to clear\b",
    r"\bfine to clear\b",
]
for pat in pats:
    if re.search(pat, p):
        sys.exit(0)
sys.exit(1)
' "$1"
}

hook_prompt() {
    local input prompt json keys_json
    input="$(cat)"
    prompt="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(d, dict):
    v = d.get("prompt")
    if isinstance(v, str):
        sys.stdout.write(v)
' 2>/dev/null)"

    [ -n "$prompt" ] || exit 0
    prompt_asks_safe_to_clear "$prompt" || exit 0

    json="$(read_memories)"
    keys_json="$(keys_from_json "$json" | python3 -c '
import json, sys
keys = [l.rstrip("\n") for l in sys.stdin if l.strip()]
print(json.dumps(keys))
')"

    python3 -c '
import json, sys

mem = json.loads(sys.argv[1]) if sys.argv[1] else {}
if not isinstance(mem, dict):
    mem = {}
keys = json.loads(sys.argv[2])

lines = []
if keys:
    lines.append("Ending this session will delete these resume notes, archiving each to logs/resume-gc-archive.jsonl:")
    for k in keys:
        text = mem.get(k, "")
        if not isinstance(text, str):
            text = ""
        lines.append("%s: %s" % (k, text[:100]))
else:
    lines.append("No resume notes will be deleted at the end of this session.")
lines.append("Show this list to the user in your answer.")

ctx = "\n".join(lines)
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": ctx,
}}))
' "$json" "$keys_json"
    exit 0
}

case "${1:-}" in
    --list)        list_keys ;;
    --run)         run ;;
    --hook-end)    hook_end ;;
    --hook-prompt) hook_prompt ;;
    *) echo "usage: $0 {--list|--run|--hook-end|--hook-prompt}" >&2; exit 2 ;;
esac
