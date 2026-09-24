#!/bin/bash
# gate: cheap --selftest
#
# Does tools/bead_dupes.py still bite, and does it spot the known duplicate?
#
#   tools/check_bead_dupes.sh          selftest + the live inc-056c acceptance
#   tools/check_bead_dupes.sh --selftest   the selftest step alone (no bd/network)
#
# THE CHECK THAT MUST GO RED. inc-zu0r measured Jev as the duplicate judge, and
# the fixture records inc-056c / inc-41kg as a known duplicate pair (label 1).
# This script proves the ENGINE still finds it: check-draft is run with
# inc-056c's OWN title and description, excluding inc-056c itself, and MUST
# exit 1 listing inc-41kg. A keyless or networkless run exits 2 ("could not
# measure") and is never reported as green.
#
# Step 1 is bead_dupes.py --selftest (tokeniser, ranking, link-skip, parser,
# extract_draft). Step 2 is the live acceptance test. A commit body must also
# record a red proof: BLOCK_AT set to 1.01 makes step 2 go red, and a broken
# parser path makes step 1 go red; both restored.
#
# Exit: 0 all green
#       1 a check failed
#       2 could not measure (no key, no network, no bd) -- says which
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2

SELFTEST_ONLY=0
[ "${1:-}" = "--selftest" ] && SELFTEST_ONLY=1

command -v python3 >/dev/null 2>&1 \
    || { echo "COULD NOT MEASURE: python3 missing"; exit 2; }

ENGINE="$ROOT/tools/bead_dupes.py"

# --- 1. the selftest ------------------------------------------------------
if python3 "$ENGINE" --selftest; then
    echo "OK    bead_dupes.py --selftest"
else
    echo "FAIL  bead_dupes.py --selftest"
    exit 1
fi

[ "$SELFTEST_ONLY" = "1" ] && exit 0

# --- 2. the live acceptance test -----------------------------------------
command -v bd >/dev/null 2>&1 \
    || { echo "COULD NOT MEASURE: bd not on PATH"; exit 2; }

# The subject: inc-056c's own title and description, straight from bd. A bead
# that cannot be read is a measurement failure, not a red check.
SUBJECT_JSON=$(bd -C "$ROOT" show inc-056c --json 2>/dev/null)
if [ -z "$SUBJECT_JSON" ]; then
    echo "COULD NOT MEASURE: could not read inc-056c from bd"
    exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/bead-dupes-check.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

python3 - "$SUBJECT_JSON" "$TMP/title" "$TMP/desc" <<'PY' || exit 2
import json, sys
raw, title_path, desc_path = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = json.loads(raw)
except ValueError as exc:
    print("COULD NOT MEASURE: inc-056c is not JSON: %s" % exc, file=sys.stderr)
    sys.exit(2)
if isinstance(data, list):
    data = data[0] if data else {}
if isinstance(data, dict) and isinstance(data.get("issues"), list):
    data = data["issues"][0] if data["issues"] else {}
if not isinstance(data, dict) or not data.get("title"):
    print("COULD NOT MEASURE: inc-056c has no title", file=sys.stderr)
    sys.exit(2)
# The description is also checked by the engine's own exit codes below; an
# empty one is still a measurement (check-draft would just rank on the title).
try:
    open(title_path, "w").write(data["title"])
    open(desc_path, "w").write(data.get("description") or "")
except OSError as exc:
    print("COULD NOT MEASURE: cannot write the draft: %s" % exc, file=sys.stderr)
    sys.exit(2)
PY
[ $? -eq 2 ] && exit 2

# The beads the engine judges come from the LIVE database (no --beads-json).
OUT=$(python3 "$ENGINE" check-draft \
        --title "$(cat "$TMP/title")" \
        --description-file "$TMP/desc" \
        --exclude inc-056c 2>"$TMP/err")
RC=$?

case $RC in
    0)
        echo "FAIL  check-draft on inc-056c found no duplicate; inc-41kg is known"
        cat "$TMP/err" >&2
        exit 1
        ;;
    1)
        if grep -q "inc-41kg" <<<"$OUT"; then
            echo "OK    check-draft on inc-056c lists inc-41kg"
        else
            echo "FAIL  check-draft exited 1 but did not list inc-41kg; got:"
            printf '%s\n' "$OUT"
            exit 1
        fi
        ;;
    2)
        echo "COULD NOT MEASURE: check-draft reported bad input"
        cat "$TMP/err" >&2
        exit 2
        ;;
    3)
        echo "COULD NOT MEASURE: Jev unavailable (no key or no network)"
        cat "$TMP/err" >&2
        exit 2
        ;;
    *)
        echo "FAIL  check-draft exited $RC, wanted 0/1/2/3"
        cat "$TMP/err" >&2
        exit 1
        ;;
esac

echo "PASS: selftest green and the engine still spots the inc-056c/inc-41kg duplicate"
exit 0
