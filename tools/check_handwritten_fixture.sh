#!/usr/bin/env bash
# gate: live
#
# Does the hand-written .char of an existing fixture build the character the
# old .sav holds?
#
# WHAT IS BEING PROVED. Spec B7 (bead inc-10v7f, phase 7a): the early proof of
# the conversion. tools/fixtures/chars/orc-barbarian-seed1-opt0822.char was
# written by hand from the canonical dump of orc-barbarian-seed1-opt0822.sav
# (the tracked file made by tools/keys/chargen-default-save.keys, seed 1). This
# builds it and compares the two canonical dumps.
#
# WHAT HOLDS, AND WHAT DOES NOT. The old .sav was written before later rules
# commits (the Cannibalism feat replaced the CA_DEVOURING ability; the starting
# kit's arrangement and the derived attributes moved), so a full dump of the new
# build is NOT equal to the old one outside the allowlist, and this check does
# not pretend it is. It asserts the part that stated decisions fix, and prints
# the rest:
#   - the build finishes with no missing, surplus or rejected line;
#   - the sections Identity, Level Rolls, Skill Ranks, Perk Block and Spells are
#     equal;
#   - the base attributes (BaseAttr) are equal;
#   - the set of carried items (item, effect, plus, charges, quantity) is equal;
# and writes the full difference to logs/fixture-build/<name>.diff.
#
# fact: the character -- fixture file tools/fixtures/chars/orc-barbarian-seed1-opt0822.char and the tracked .sav beside it; both are committed, neither is generated
# fact: the old dump -- tools/char_dump.sh of the tracked .sav, read by the binary under test (a binary that cannot read the old save format fails the check, which is the point of a dump)
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_handwritten_fixture.sh
# Exit: 0 pass; 1 fail; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
NAME=orc-barbarian-seed1-opt0822
CHAR=tools/fixtures/chars/$NAME.char
OLD=tools/fixtures/chars/$NAME.sav
KITOPTS=tools/fixtures/options-2026-08-22-kit.dat
[ -f "$CHAR" ] && [ -f "$OLD" ] || { echo "INCONCLUSIVE: $CHAR or $OLD is missing"; exit 2; }

OUT="logs/fixture-build/$NAME"
rm -rf "$OUT"
mkdir -p "logs/fixture-build"
if ! INCURSION_BIN="$BIN" tools/build_fixture.sh "$CHAR" "$OUT" > "$OUT.log" 2>&1; then
    echo "FAIL: the hand-written .char did not build: $(grep -m1 'BUILD FAILED' "$OUT.log" || tail -1 "$OUT.log")"; exit 1
fi
echo "ok   the build finished with no missing, surplus or rejected line"

INCURSION_OPTIONS="$KITOPTS" INCURSION_BIN="$BIN" tools/char_dump.sh "$OLD" "$OUT/old.canon" > /dev/null 2>&1 || { echo "INCONCLUSIVE: the old .sav did not dump"; exit 2; }
INCURSION_OPTIONS="$KITOPTS" INCURSION_BIN="$BIN" tools/char_dump.sh "$OUT/$NAME.sav" "$OUT/built.canon" > /dev/null 2>&1 || { echo "FAIL: the built .sav did not dump"; exit 1; }

python3 tools/canon_compare.py --all "$OUT/old.canon" "$OUT/built.canon" > "$OUT.diff" 2>&1
echo "     full difference outside the allowlist: $(grep -c '^[-+][^-+]' "$OUT.diff") lines in $OUT.diff (rule changes since the .sav was made)"

python3 - "$OUT/old.canon" "$OUT/built.canon" <<'PY'
import re, sys
def section(lines, name):
    out, on = [], False
    for l in lines:
        m = re.match(r"^=== (.*) ===$", l)
        if m:
            on = m.group(1).startswith(name)
            continue
        if on:
            out.append(l)
    return out
def items(lines):
    i = next(k for k, l in enumerate(lines) if l.startswith("=== Kit"))
    j = next(k for k, l in enumerate(lines) if l.startswith("=== Spells"))
    s, cur = set(), None
    for l in lines[i:j]:
        m = re.match(r"^\s*- Item iID=(.*?) eID=(.*?) Type=", l)
        if m: cur = (m.group(1), m.group(2))
        m = re.search(r"Plus=(\S+) Charges=(\S+) .*Quantity=(\S+) IFlags", l)
        if m and cur: s.add(cur + m.groups()[:3])
    return s
a = open(sys.argv[1], errors="replace").read().split("\n")
b = open(sys.argv[2], errors="replace").read().split("\n")
bad = 0
for name in ("Identity", "Level Rolls", "Skill Ranks", "Perk Block", "Spells"):
    if section(a, name) == section(b, name):
        print("ok   section %s equal" % name)
    else:
        print("FAIL section %s differs" % name); bad = 1
ba = [l for l in a if l.startswith("BaseAttr")]
bb = [l for l in b if l.startswith("BaseAttr")]
print("ok   base attributes equal" if ba == bb else "FAIL base attributes differ")
bad |= ba != bb
ia, ib = items(a), items(b)
if ia == ib:
    print("ok   the %d carried items (item, effect, plus, charges, quantity) are equal" % len(ia))
else:
    print("FAIL items differ: only old %s only built %s" % (sorted(ia - ib), sorted(ib - ia))); bad = 1
sys.exit(bad)
PY
rc=$?
[ $rc -eq 0 ] && { echo "PASS: the stated decisions build the old character; derived differences are in $OUT.diff"; exit 0; }
exit 1
