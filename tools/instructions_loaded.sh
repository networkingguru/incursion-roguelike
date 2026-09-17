#!/usr/bin/env bash
#
# InstructionsLoaded hook: prove which instruction files actually reached the
# model, instead of trusting that they did.
#
# WHY THIS EXISTS. Claude Code 2.1.271 truncates each SessionStart hook's
# output at 10,000 characters and injects only a 2,000-character preview, with
# the rest spilled to a file the model never reads. That is how the rule
# "commit-means-land-the-bead" went missing from a session on 2026-09-17 (bd
# inc-2e9w) even though it had been written earlier the same day. CLAUDE.md's
# `@AGENTS.md` import and `.claude/rules/*.md` load through a different,
# untruncated path instead (see `tools/check_rules_channel.sh` for the check
# that channel stays intact). This hook is the standing proof of what that
# untruncated path actually delivered: one line per instruction file the host
# reports through InstructionsLoaded, so a session can be checked after the
# fact instead of trusted on faith.
#
# CONTRACT. Claude Code calls this once per loaded instruction file, with a
# JSON object on stdin carrying:
#   file_path      the file that loaded
#   memory_type    what kind of memory file it is
#   load_reason    one of: session_start, nested_traversal, path_glob_match,
#                  include, compact. An `@path` import (CLAUDE.md's
#                  `@AGENTS.md`) reports "include".
#
# It prints NOTHING to stdout. A hook that reproduced its own findings on
# stdout would be the truncation bug again, just moved one hop over.
#
# FAIL SAFE. logs/ is gitignored and not guaranteed to exist. A missing or
# unwritable log directory exits 0 silently rather than blocking session
# start -- this is a record, not a gate.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 0
LOG_DIR="$ROOT/logs"
LOG_FILE="$LOG_DIR/instructions-loaded.log"

mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
[ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ] || exit 0

input="$(cat)"

line="$(printf '%s' "$input" | python3 -c '
import json, sys, datetime

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
print("%s file_path=%s memory_type=%s load_reason=%s" % (
    ts,
    d.get("file_path", "?"),
    d.get("memory_type", "?"),
    d.get("load_reason", "?"),
))
' 2>/dev/null)" || exit 0

[ -n "$line" ] || exit 0

printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null

exit 0
