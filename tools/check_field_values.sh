#!/bin/bash
# gate: none builds two scratch trees (--selftest) and runs 148 dumps; run by hand
# fact: saves decoded -- every tools/fixtures/chars/*.sav, frozen bytes; the assertions are "a value file is non-empty" and "two runs on one binary are identical", which hold for any save
# fact: binary under test -- ./incursion-headless built from this tree (BACKEND=posix ./build_macos.sh); the check refuses when it is missing
# fact: unequal alignments -- fixture alignment-drain-lawful-neutral (alignGE 0, alignLC -50), frozen bytes; the red case needs two members that differ
# fact: scratch mutation -- inc/Creature.h in a copy of this working tree, edited by this script (names swapped; one member added); the copy is deleted on exit
# fact: nondeterministic fields -- none found; EXCLUDE_FIELDS below is the one place a name would go, never a pattern
#
# Does tools/pressure/field_values.sh see what each member HOLDS after load, and can it fail?
#   (default)   every fixture gives a non-empty value file; two runs give identical files;
#               a file compared with itself exits 0
#   --selftest  red: swap the FIELD names of alignGE and alignLC in a scratch build; the compare against this
#               build on a fixture with unequal alignments MUST exit 1 and name both fields.
#               added: a new member with its own FIELD line in a scratch build MUST show as "added" and exit 0.
#
# Exit: 0 pass, 1 fail, 2 could not measure.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FV=tools/pressure/field_values.sh
CMP=tools/pressure/compare_values.py
EXCLUDE_FIELDS=""   # "<scope> <field>" lines to drop before comparing; empty: every field was deterministic
UNEQUAL=tools/fixtures/chars/alignment-drain-lawful-neutral.sav
[ -x ./incursion-headless ] || { echo "no ./incursion-headless; run BACKEND=posix ./build_macos.sh" >&2; exit 2; }
W="$(mktemp -d "${TMPDIR:-/tmp}/incursion-fvcheck.XXXXXX")"
trap 'rm -rf "$W"' EXIT
FAIL=0
bad() { echo "FAIL: $*"; FAIL=1; }

filtered() {   # $1 in, $2 out
    if [ -n "$EXCLUDE_FIELDS" ]; then
        LC_ALL=C grep -vxF -f <(printf '%s\n' "$EXCLUDE_FIELDS") "$1" > "$2"
    else cp "$1" "$2"; fi
}

if [ "${1:-}" != "--selftest" ]; then
    n=0
    for s in tools/fixtures/chars/*.sav; do
        b="$(basename "$s" .sav)"
        $FV . "$s" "$W/$b.1" 2> "$W/$b.err" || { bad "$b: could not decode: $(head -c 200 "$W/$b.err")"; continue; }
        $FV . "$s" "$W/$b.2" 2>/dev/null || { bad "$b: second run failed"; continue; }
        [ -s "$W/$b.1" ] || bad "$b: empty value file"
        cmp -s "$W/$b.1" "$W/$b.2" || bad "$b: two runs differ"
        python3 $CMP "$W/$b.1" "$W/$b.2" > /dev/null || bad "$b: compare of two runs did not exit 0"
        n=$((n + 1))
    done
    [ "$n" -gt 0 ] || bad "no fixture decoded"
    echo "fixtures decoded, non-empty and identical across two runs: $n"
    [ $FAIL = 0 ] && echo "PASS check_field_values" || echo "FAIL check_field_values"
    exit $FAIL
fi

# ---- selftest: scratch copies of the working tree, built with a mutation
scratch() {   # $1 name; builds $W/$1
    local d="$W/$1"
    mkdir -p "$d"
    rsync -a --exclude=.git --exclude=logs --exclude=save --exclude=build --exclude=docs --exclude=website \
        --exclude='incursion*' ./ "$d/" || return 2
    mkdir -p "$d/logs" "$d/save"
    echo "$d"
}
build() { ( cd "$1" && BACKEND=posix ./build_macos.sh > build.log 2>&1 ) || { echo "scratch build failed: $1/build.log" >&2; tail -5 "$1/build.log" >&2; return 2; }; }

$FV . "$UNEQUAL" "$W/clean.txt" || { echo "could not decode $UNEQUAL" >&2; exit 2; }

D="$(scratch red)" || exit 2
python3 - "$D/inc/Creature.h" <<'PY' || exit 2
import sys
p = sys.argv[1]; s = open(p).read()
a = 'FIELD_I16("alignGE", alignGE);\n      FIELD_I16("alignLC", alignLC);'
assert s.count(a) == 1, "alignment FIELD lines not found"
open(p, "w").write(s.replace(a, 'FIELD_I16("alignGE", alignLC);\n      FIELD_I16("alignLC", alignGE);'))
PY
build "$D" || exit 2
$FV "$D" "$UNEQUAL" "$W/red.txt" || { echo "could not decode on the red build" >&2; exit 2; }
python3 $CMP "$W/clean.txt" "$W/red.txt" > "$W/red.cmp"; rc=$?
cat "$W/red.cmp"
[ $rc = 1 ] || bad "red: swap not caught (exit $rc, want 1)"
grep -q "alignGE" "$W/red.cmp" && grep -q "alignLC" "$W/red.cmp" || bad "red: output does not name both fields"
python3 $CMP "$W/clean.txt" "$W/clean.txt" > /dev/null || bad "clean against clean did not exit 0"

D="$(scratch added)" || exit 2
python3 - "$D/inc/Creature.h" <<'PY' || exit 2
import sys
p = sys.argv[1]; s = open(p).read()
a = '      int16 alignGE, alignLC; \n'
b = 'FIELD_I16("alignLC", alignLC);\n'
assert s.count(a) == 1 and s.count(b) == 1, "anchors not found"
s = s.replace(a, a + '      int16 fvProbeAdded;\n').replace(b, b + '      FIELD_I16("fvProbeAdded", fvProbeAdded);\n')
open(p, "w").write(s)
PY
build "$D" || exit 2
$FV "$D" "$UNEQUAL" "$W/added.txt" || { echo "could not decode on the added build" >&2; exit 2; }
python3 $CMP "$W/clean.txt" "$W/added.txt" > "$W/added.cmp"; rc=$?
cat "$W/added.cmp"
[ $rc = 0 ] || bad "added: exit $rc, want 0"
grep -q "^added .*fvProbeAdded" "$W/added.cmp" || bad "added: new field not reported as added"

[ $FAIL = 0 ] && echo "PASS check_field_values --selftest" || echo "FAIL check_field_values --selftest"
exit $FAIL
