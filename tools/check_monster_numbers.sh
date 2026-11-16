#!/bin/bash
# gate: none heavy; builds nothing, runs `incursion-headless -schematest` once (inc-cjos0 phase 9c, G20)
# fact: engine output -- the MONNUMBERS lines of `incursion-headless -schematest <dir>` (IsRealMonType, MaIndex and MaByIndex called on fixed numbers, constants and the numMonOfType length printed from code); no seed, no key script, no options file, no module data enters
# fact: probe numbers -- the fixed list 0 1 73 74 75 130 131 132 255 256 in this script; no world, no roll
# fact: expected values -- computed in this script from the constants the engine prints, by the monster type rule (real types 1..MA_LAST_REAL-1 and MA_HIGH_FIRST..MA_HIGH_END-1; MaIndex maps the high block to MA_LAST_REAL up; 74..130 are never a real type); nothing is copied from the code under test
# fact: the build -- the posix DEBUG binary ./incursion-headless the caller built; this script builds nothing
#
# What it guards: a new real monster type takes a number from 131 up (u8, so 131-255) and its count
# lands in JournalInfo.numMonOfType at MaIndex(n). IsRealMonType, MaIndex and MaByIndex agree with
# the rule at every probe for the tree's MA_HIGH_END; MA_COUNT is MA_LAST_REAL plus the high block;
# numMonOfType has MA_COUNT elements; the walk over indexes 1..MA_COUNT-1 reaches every real type
# once and the last index holds the last real type, so a loop bound that stops at MA_LAST_REAL
# visits too few. MA_LAST_REAL stays 74 and MA_LAST stays 130 (frozen values).
#
# Usage: tools/check_monster_numbers.sh              (exit 0 pass, 1 fail, 2 could not measure)
#        tools/check_monster_numbers.sh --selftest   (proves red on planted wrong engine output; needs no binary)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# verify <file of MONNUMBERS lines>: prints one FAIL line per broken fact; returns 1 on any.
verify() {
    local f="$1" bad=0 line
    line="$(grep '^MONNUMBERS const ' "$f" | head -1)"
    [ -n "$line" ] || { echo "FAIL: no 'MONNUMBERS const' line"; return 1; }
    local R LA HF HE C v
    R=$(sed -n 's/.* MA_LAST_REAL=\([0-9-]*\).*/\1/p' <<<"$line")
    LA=$(sed -n 's/.* MA_LAST=\([0-9-]*\).*/\1/p' <<<"$line")
    HF=$(sed -n 's/.* MA_HIGH_FIRST=\([0-9-]*\).*/\1/p' <<<"$line")
    HE=$(sed -n 's/.* MA_HIGH_END=\([0-9-]*\).*/\1/p' <<<"$line")
    C=$(sed -n 's/.* MA_COUNT=\([0-9-]*\).*/\1/p' <<<"$line")
    for v in "$R" "$LA" "$HF" "$HE" "$C"; do
        [[ "$v" =~ ^[0-9]+$ ]] || { echo "FAIL: unreadable constants line: $line"; return 1; }
    done
    [ "$R" -eq 74 ] || { echo "FAIL: MA_LAST_REAL is $R, it is a frozen 74 (a new real type takes 131 up and raises MA_HIGH_END)"; bad=1; }
    [ "$LA" -eq 130 ] || { echo "FAIL: MA_LAST is $LA, it is a frozen 130"; bad=1; }
    [ "$HF" -eq 131 ] || { echo "FAIL: MA_HIGH_FIRST is $HF, the ruling says 131"; bad=1; }
    [ "$HE" -ge "$HF" ] && [ "$HE" -le 256 ] || { echo "FAIL: MA_HIGH_END $HE is outside $HF..256 (a type is a u8)"; bad=1; }
    [ "$C" -eq $((R + HE - HF)) ] || { echo "FAIL: MA_COUNT $C != MA_LAST_REAL $R + (MA_HIGH_END $HE - MA_HIGH_FIRST $HF)"; bad=1; }
    local nm
    nm=$(sed -n 's/^MONNUMBERS len numMonOfType=\([0-9]*\).*/\1/p' "$f" | head -1)
    [ -n "$nm" ] || { echo "FAIL: no readable 'MONNUMBERS len' line"; return 1; }
    [ "$nm" -eq "$C" ] || { echo "FAIL: numMonOfType has $nm elements, MA_COUNT is $C"; bad=1; }
    local n is ix by want_is want_ix want_by
    for n in 0 1 73 74 75 130 131 132 255 256; do
        line="$(grep "^MONNUMBERS n=$n " "$f" | head -1)"
        if [ -z "$line" ]; then echo "FAIL: no line for n=$n"; bad=1; continue; fi
        is=$(sed -n 's/.* IsRealMonType=\([0-9-]*\).*/\1/p' <<<"$line")
        ix=$(sed -n 's/.* MaIndex=\([0-9-]*\).*/\1/p' <<<"$line")
        by=$(sed -n 's/.* MaByIndex=\([0-9-]*\).*/\1/p' <<<"$line")
        want_is=0; want_ix=0; want_by=0
        if { [ "$n" -ge 1 ] && [ "$n" -lt "$R" ]; } || { [ "$n" -ge "$HF" ] && [ "$n" -lt "$HE" ]; }; then want_is=1; fi
        if [ "$n" -ge 1 ] && [ "$n" -lt "$R" ]; then want_ix=$n
        elif [ "$n" -ge "$HF" ] && [ "$n" -lt "$HE" ]; then want_ix=$((R + n - HF)); fi
        if [ "$n" -ge 1 ] && [ "$n" -lt "$R" ]; then want_by=$n
        elif [ "$n" -ge "$R" ] && [ "$n" -lt "$C" ]; then want_by=$((HF + n - R)); fi
        [ "$is" = "$want_is" ] || { echo "FAIL: IsRealMonType($n) is $is, want $want_is"; bad=1; }
        [ "$ix" = "$want_ix" ] || { echo "FAIL: MaIndex($n) is $ix, want $want_ix"; bad=1; }
        [ "$by" = "$want_by" ] || { echo "FAIL: MaByIndex($n) is $by, want $want_by"; bad=1; }
    done
    local walk vis last wl
    walk="$(grep '^MONNUMBERS walk ' "$f" | head -1)"
    vis=$(sed -n 's/.* visited=\([0-9]*\).*/\1/p' <<<"$walk")
    last=$(sed -n 's/.* last=\([0-9]*\).*/\1/p' <<<"$walk")
    [ -n "$vis" ] && [ -n "$last" ] || { echo "FAIL: no readable 'MONNUMBERS walk' line"; return 1; }
    [ "$vis" -eq $((C - 1)) ] || { echo "FAIL: the walk over indexes visited $vis types, want $((C - 1))"; bad=1; }
    wl=$((R - 1)); [ "$HE" -gt "$HF" ] && wl=$((HE - 1))
    [ "$last" -eq "$wl" ] || { echo "FAIL: the last type the walk reaches is $last, want $wl"; bad=1; }
    grep -q '^SCHEMATEST GROUP monnumbers PASS' "$f" || { echo "FAIL: the engine's own round trip and slot check did not pass"; bad=1; }
    return $bad
}

if [ "${1:-}" = "--selftest" ]; then
    T="$(mktemp -d "${TMPDIR:-/tmp}/monnumbers.XXXXXX")"
    trap 'rm -rf "$T"' EXIT
    cat > "$T/good" <<'GOOD'
MONNUMBERS const MA_LAST_REAL=74 MA_LAST=130 MA_HIGH_FIRST=131 MA_HIGH_END=131 MA_COUNT=74
MONNUMBERS len numMonOfType=74
MONNUMBERS n=0 IsRealMonType=0 MaIndex=0 MaByIndex=0
MONNUMBERS n=1 IsRealMonType=1 MaIndex=1 MaByIndex=1
MONNUMBERS n=73 IsRealMonType=1 MaIndex=73 MaByIndex=73
MONNUMBERS n=74 IsRealMonType=0 MaIndex=0 MaByIndex=0
MONNUMBERS n=75 IsRealMonType=0 MaIndex=0 MaByIndex=0
MONNUMBERS n=130 IsRealMonType=0 MaIndex=0 MaByIndex=0
MONNUMBERS n=131 IsRealMonType=0 MaIndex=0 MaByIndex=0
MONNUMBERS n=132 IsRealMonType=0 MaIndex=0 MaByIndex=0
MONNUMBERS n=255 IsRealMonType=0 MaIndex=0 MaByIndex=0
MONNUMBERS n=256 IsRealMonType=0 MaIndex=0 MaByIndex=0
MONNUMBERS walk visited=73 last=73
SCHEMATEST GROUP monnumbers PASS
GOOD
    verify "$T/good" >/dev/null || { echo "SELFTEST FAIL: the good output was refused"; verify "$T/good"; exit 1; }
    # one high type planted (MA_HIGH_END 132, MA_COUNT 75): type 131 is real and counts at slot 74
    sed -e 's/MA_HIGH_END=131 MA_COUNT=74/MA_HIGH_END=132 MA_COUNT=75/' -e 's/numMonOfType=74/numMonOfType=75/' \
        -e 's/^\(MONNUMBERS n=74 \).*/\1IsRealMonType=0 MaIndex=0 MaByIndex=131/' \
        -e 's/^\(MONNUMBERS n=131 \).*/\1IsRealMonType=1 MaIndex=74 MaByIndex=0/' \
        -e 's/visited=73 last=73/visited=74 last=131/' "$T/good" > "$T/high"
    verify "$T/high" >/dev/null || { echo "SELFTEST FAIL: the planted-high-type output was refused"; verify "$T/high"; exit 1; }
    mut() { # <name> <input> <sed expression>: the mutated output MUST be refused
        sed -e "$3" "$T/$2" > "$T/m"
        if verify "$T/m" >/dev/null; then echo "SELFTEST FAIL: '$1' was accepted"; exit 1; fi
        echo "  red ok  $1"
    }
    mut "MaIndex(73) wrong"            good 's/^\(MONNUMBERS n=73 .*MaIndex=\)73/\172/'
    mut "IsRealMonType(1) false"       good 's/^\(MONNUMBERS n=1 IsRealMonType=\)1/\10/'
    mut "IsRealMonType(74) true"       good 's/^\(MONNUMBERS n=74 IsRealMonType=\)0/\11/'
    mut "MaIndex(75) nonzero"          good 's/^\(MONNUMBERS n=75 .*MaIndex=\)0/\175/'
    mut "MaIndex(130) nonzero"         good 's/^\(MONNUMBERS n=130 .*MaIndex=\)0/\1130/'
    mut "MaByIndex(1) wrong"           good 's/^\(MONNUMBERS n=1 .*MaByIndex=\)1/\12/'
    mut "numMonOfType not MA_COUNT"    good 's/numMonOfType=74/numMonOfType=73/'
    mut "MA_LAST_REAL raised"          good 's/MA_LAST_REAL=74/MA_LAST_REAL=75/'
    mut "MA_LAST moved"                good 's/MA_LAST=130/MA_LAST=132/'
    mut "MA_HIGH_FIRST moved"          good 's/MA_HIGH_FIRST=131/MA_HIGH_FIRST=130/'
    mut "MA_COUNT not the sum"         good 's/MA_COUNT=74/MA_COUNT=75/'
    mut "MA_HIGH_END past a u8"        good 's/MA_HIGH_END=131 MA_COUNT=74/MA_HIGH_END=257 MA_COUNT=200/'
    mut "walk visits too few"          good 's/visited=73/visited=72/'
    mut "engine check failed"          good 's/GROUP monnumbers PASS/GROUP monnumbers FAIL/'
    mut "probe line missing"           good '/^MONNUMBERS n=75 /d'
    mut "high type not at slot 74"     high 's/^\(MONNUMBERS n=131 .*MaIndex=\)74/\10/'
    mut "high type missing from array" high 's/numMonOfType=75/numMonOfType=74/'
    mut "walk stops at MA_LAST_REAL"   high 's/visited=74 last=131/visited=73 last=73/'
    echo "SELFTEST PASS"
    exit 0
fi

BIN="$ROOT/incursion-headless"
[ -x "$BIN" ] || { echo "UNMEASURED: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
W="$(mktemp -d "${TMPDIR:-/tmp}/monnumbers.XXXXXX")"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/save"
"$BIN" -schematest "$W/save" -timeout 120 < /dev/null > "$W/out" 2> "$W/err"
rc=$?
verify "$W/out"; vrc=$?
if [ "$vrc" -eq 0 ] && [ "$rc" -eq 0 ]; then
    echo "PASS: IsRealMonType/MaIndex/MaByIndex, MA_COUNT and the numMonOfType length agree with the monster type rule"
    exit 0
fi
[ "$rc" -eq 0 ] || { cat "$W/err"; echo "FAIL: -schematest exited $rc"; }
exit 1
