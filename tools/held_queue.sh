#!/usr/bin/env bash
#
# Print the questions an unattended run held for Brian, or print nothing.
#
#   tools/held_queue.sh          # the queue, or silence when it is empty
#   tools/held_queue.sh --count  # just the number, for a script
#
# WHY THIS EXISTS. The overnight run is meant to need him for nothing. When it
# does hit something only he can decide -- a ruling, a tradeoff, anything
# outward-facing -- it MUST NOT stop and MUST NOT guess. It files a bead
# labelled `needs-brian` and carries on with the next item. This prints that
# queue at the start of the next session, so the answer arrives in time for the
# following night's run.
#
# THE ONE RULE THE QUEUE ENFORCES. Nothing outward-facing is ever sent by an
# unattended run: no pull request, no issue, no comment, no release. Those go in
# here with the literal text attached, and wait for him to read that text.
# See CLAUDE.md, "Publishing anything outward-facing".
#
# Answering one:  bd show <id>
#                 bd update <id> --remove-label needs-brian --append-notes "RULING: ..."
#
# Exit: always 0. This is a notice, not a gate -- a SessionStart hook that fails
#       is a session that starts with an error instead of a report.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 0

command -v bd > /dev/null 2>&1 || exit 0

# bd resolves its database from the working directory, so this must run from the
# repository root and nowhere else.
JSON="$(bd list --label needs-brian --status open --json 2>/dev/null)" || exit 0
[ -n "$JSON" ] || exit 0

python3 - "$JSON" <<'PY'
import json, sys

try:
    rows = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
if isinstance(rows, dict):
    rows = rows.get("issues", [])
rows = [r for r in rows if isinstance(r, dict)]
if not rows:
    sys.exit(0)

want_count = "--count" in sys.argv
if want_count:
    print(len(rows))
    sys.exit(0)

print()
print("=" * 72)
print("HELD FOR BRIAN -- %d question(s) the unattended run could not decide" % len(rows))
print("=" * 72)
for r in rows:
    rid = r.get("id", "?")
    pri = r.get("priority", "")
    pri = ("P%s" % pri) if str(pri).isdigit() else str(pri or "")
    print("  %-12s %-3s %s" % (rid, pri, r.get("title", "")))
print()
print("  bd show <id>                     read the question and its evidence")
print("  bd update <id> --remove-label needs-brian --append-notes \"RULING: ...\"")
print("Answer these and tonight's run acts on them.")
print("=" * 72)
print()
PY
exit 0
