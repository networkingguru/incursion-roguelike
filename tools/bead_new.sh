#!/bin/bash
# File a bead and check it AT ONCE, instead of at the next commit.
#
#   tools/bead_new.sh "title" -d "description" --type bug
#   tools/bead_new.sh --help          bd create's own flags, unchanged
#
# Every argument is handed to `bd create` untouched, except the wrapper-only
# --not-a-duplicate, which is removed before bd sees it. When the bead is filed
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
# and the type they had already chosen. The one exception is the duplicate
# check below, which refuses BEFORE bd create: nothing is filed, so there is
# nothing to delete.
#
# THE DUPLICATE CHECK. inc-zu0r: before bd create this hands the draft to
# tools/bead_dupes.py, which PRESELECTS candidates by word overlap and lets
# Jev judge them. The draft is extracted by the engine's `draft-args` mode, not
# re-parsed here; it also returns bd's argv with --not-a-duplicate removed and
# a stdin draft pointed at a temp file.
#
#   Exit 1 from the check, no --not-a-duplicate: print the candidates and
#   refuse -- exit 3, nothing filed. The message names the override and the
#   `bd duplicate` command.
#   Exit 1 with --not-a-duplicate: file, then append the candidates and their
#   probabilities to the bead's notes.
#   Exit 3 (Jev unavailable) or 2 (bad input): file, append
#   `duplicate check skipped: <reason>`, and print a directive to have a haiku
#   subagent check the bead by hand.
#   Bulk filing (-f/--file/--graph): no pre-check; the nightly sweep covers it.
#   No title or no description: today's pass-through behaviour, no check.
#
# Exit: 0 filed and fit, 1 filed but NOT fit (fix it before you commit),
#       2 the filing itself failed, or the bead could not be checked,
#       3 REFUSED as a likely duplicate; nothing was filed (re-run with
#         --not-a-duplicate to file it anyway).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/tools/bead_dupes.py"

# --help and --dry-run never create anything, so there is nothing to check.
# Pass them through and answer with bd's own exit code.
for a in "$@"; do
    if [ "$a" = "--help" ] || [ "$a" = "-h" ] || [ "$a" = "--dry-run" ]; then
        exec bd create "$@"
    fi
done

# Scratch space: the draft JSON, the stdin body, an inline description, and the
# check's --json-out. Removed on exit whatever happens.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bead-new.XXXXXX") || {
    echo "bead_new: could not create a scratch dir" >&2
    exit 2
}
trap 'rm -rf "$TMP"' EXIT

# The engine extracts the draft and returns bd's cleaned-up argv. It fails
# closed: a draft it cannot read stops the filing rather than handing bd an
# unknown flag or an unjudged draft.
DRAFT="$TMP/draft.json"
if ! python3 "$ENGINE" draft-args --stdin-temp "$TMP/body" -- "$@" \
        >"$DRAFT" 2>"$TMP/draft.err"; then
    cat "$TMP/draft.err" >&2
    echo "bead_new: could not extract the draft from these arguments; nothing was filed" >&2
    exit 2
fi

# One scalar field out of the draft JSON. Empty for null/absent.
draft_field() {
    python3 - "$DRAFT" "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(0)
v = d
for key in sys.argv[2].split("."):
    v = v.get(key) if isinstance(v, dict) else None
print("" if v is None else v)
PY
}

TITLE=$(draft_field title)
KIND=$(draft_field description_source.kind)
PARENT=$(draft_field parent)
NOT_A_DUPLICATE=$(draft_field not_a_duplicate)
BULK=$(draft_field bulk)

# bd's argv, NUL-separated, so titles and paths with spaces survive intact.
BD_ARGV=()
while IFS= read -r -d '' arg; do BD_ARGV+=("$arg"); done \
    < <(python3 - "$DRAFT" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(0)
for a in d.get("bd_argv") or []:
    sys.stdout.write(a)
    sys.stdout.write("\0")
PY
)

# The draft's description reaches the check as a file. A stdin draft was read
# into $TMP/body by draft-args, which also pointed bd's --body-file at it.
DESC_FILE=""
case "$KIND" in
    stdin)
        cat > "$TMP/body"
        DESC_FILE="$TMP/body"
        ;;
    file)
        DESC_FILE=$(draft_field description_source.path)
        ;;
    inline)
        draft_field description_source.text > "$TMP/inline"
        DESC_FILE="$TMP/inline"
        ;;
esac

# How the wrapper treats the check's verdict. NOTE is appended after filing;
# SKIP_REASON triggers the directive. Both empty means a clean check.
NOTE=""
SKIP_REASON=""
CHECK_JSON=""

if [ "$BULK" = "True" ]; then
    echo "bead_new: bulk filing is not checked for duplicates; the nightly sweep will check these beads"
elif [ -z "$TITLE" ] || [ -z "$DESC_FILE" ]; then
    : # no title or no description: keep today's pass-through behaviour
else
    CHECK_JSON="$TMP/check.json"
    CHECK_ARGS=(check-draft --title "$TITLE" --description-file "$DESC_FILE"
                --json-out "$CHECK_JSON")
    [ -n "$PARENT" ] && CHECK_ARGS+=(--parent "$PARENT")

    python3 "$ENGINE" "${CHECK_ARGS[@]}"
    CHECK=$?

    # The candidates and the reason come from the JSON the engine wrote, never
    # from its stdout.
    declared() {
        python3 - "$CHECK_JSON" "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    d = {}
if sys.argv[2] == "reason":
    print(d.get("unavailable") or "the check gave no reason")
else:
    parts = []
    for h in d.get("hits") or []:
        try:
            parts.append("%s %.2f" % (h.get("id"), float(h.get("probability"))))
        except (TypeError, ValueError):
            parts.append(str(h.get("id")))
    print(", ".join(parts))
PY
    }

    case $CHECK in
        0)
            : # no candidate reached the threshold
            ;;
        1)
            if [ "$NOT_A_DUPLICATE" = "True" ]; then
                NOTE="filed with --not-a-duplicate; candidates: $(declared candidates)"
            else
                echo "" >&2
                echo "bead_new: NOT filed — this looks like a duplicate. If it is, run:" >&2
                echo "  bd duplicate <new-or-existing> --of <canonical>" >&2
                echo "on the existing bead instead. If it is not, re-run with --not-a-duplicate." >&2
                exit 3
            fi
            ;;
        *)
            # 3 (Jev unavailable) or 2 (bad input): file, note the skip, and
            # hand the filing agent a directive for a haiku subagent.
            SKIP_REASON=$(declared reason)
            ;;
    esac
fi

# File the bead. Everything that is going to create anything goes through here
# exactly once.
OUT=$(bd -C "$ROOT" create "${BD_ARGV[@]}" --json 2>&1)
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

if [ -n "$NOTE" ]; then
    bd -C "$ROOT" update "$ID" --append-notes "$NOTE" >&2 \
        || echo "bead_new: could not append the candidate note to $ID" >&2
fi

if [ -n "$SKIP_REASON" ]; then
    bd -C "$ROOT" update "$ID" --append-notes \
        "duplicate check skipped: $SKIP_REASON" >&2 \
        || echo "bead_new: could not append the skip note to $ID" >&2
    echo ""
    echo "DIRECTIVE TO THE FILING AGENT: the duplicate check could not run ($SKIP_REASON)."
    echo "Spawn a subagent with model haiku. Give it bead $ID and the output of"
    echo "\`bd list --all --json\`, and have it name any bead that describes the same"
    echo "defect or work. Mark each one you confirm with"
    echo "\`bd duplicate $ID --of <canonical>\`."
fi

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
