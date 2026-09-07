#!/bin/bash
# File a bead and check it AT ONCE, instead of at the next commit.
#
#   tools/bead_new.sh "title" -d "description" --type bug
#   tools/bead_new.sh --help          bd create's own flags, unchanged
#
# Every argument is handed to `bd create` untouched. When the bead is filed
# this runs tools/check_bead_publish.py --bead <id> against it and fails if
# the bead is not described, not classified, or not fit to publish.
#
# WHY THIS EXISTS, given the pre-commit hook already blocks.
#
# Beads live in a Dolt database, not in git. A bead is therefore never part of
# a commit, and check_bead_publish.py cannot scope itself to "the beads in this
# commit" -- it can only ask "the beads created since HEAD" and gate every
# commit in the tree on all of them. On 2026-09-07 that stopped a commit of
# four screenshots because a DIFFERENT session, working in the same tree, had
# filed two beads it had not finished classifying. The author who could fix
# them was not the person being blocked, and the person being blocked could not
# fix them without touching another session's work.
#
# So this catches the same faults one step earlier, where the author still has
# the bead in their head and nobody else is waiting.
#
# IT DOES NOT REPLACE THE HOOK, and Brian's instruction on 2026-09-07 was
# explicit: keep the commit gate, add this. A wrapper only fires when somebody
# calls it, and `bd create` typed directly walks straight past. The hook is the
# backstop that cannot be walked past; this is the fast feedback in front of
# it. Neither alone is enough -- the hook alone blocks the wrong person, and
# this alone has a hole you can drive a session through.
#
# THE BEAD IS NOT DELETED WHEN IT FAILS. It stays, so `bd update <id>` can fix
# it; the checker prints the exact command for each fault. Deleting a bead
# somebody just wrote, because its description was empty, would lose the title
# and the type they had already chosen.
#
# Exit: 0 filed and fit, 1 filed but NOT fit (fix it before you commit),
#       2 the filing itself failed, or the bead could not be checked.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --help and --dry-run never create anything, so there is nothing to check.
# Pass them through and answer with bd's own exit code.
for a in "$@"; do
    if [ "$a" = "--help" ] || [ "$a" = "-h" ] || [ "$a" = "--dry-run" ]; then
        exec bd create "$@"
    fi
done

# --json is added rather than assumed. `bd create` prints a human summary by
# default, whose wording is not ours to depend on; the JSON form carries the id
# in a named field. A caller who passed --json themselves gets it once, because
# bd tolerates the repeat.
OUT=$(bd -C "$ROOT" create "$@" --json 2>&1)
RC=$?
if [ $RC -ne 0 ]; then
    printf '%s\n' "$OUT" >&2
    echo "bead_new: bd create failed (exit $RC); nothing was filed" >&2
    exit 2
fi

ID=$(printf '%s' "$OUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
print(d.get("id", "") if isinstance(d, dict) else "")
' 2>/dev/null)

if [ -z "$ID" ]; then
    printf '%s\n' "$OUT"
    echo "bead_new: filed, but the id could not be read from bd's output, so" >&2
    echo "the bead was NOT checked. The pre-commit hook will still catch it." >&2
    exit 2
fi

echo "bead_new: filed $ID"
"$ROOT/tools/check_bead_publish.py" --bead "$ID"
CHECK=$?
if [ $CHECK -eq 1 ]; then
    echo "" >&2
    echo "bead_new: $ID is filed but NOT fit to publish. Fix it above now --" >&2
    echo "left alone it will block the next commit in this tree, which may" >&2
    echo "well be somebody else's." >&2
    exit 1
fi
exit $CHECK
