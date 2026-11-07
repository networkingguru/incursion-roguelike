#!/bin/bash
# gate: none heavy; builds nothing, runs `incursion-headless -schematest` once (inc-cjos0 phase 7f-2)
# fact: engine output -- the SKILLNUMBERS lines of `incursion-headless -schematest <dir>` (the helpers called on fixed numbers, constants and array lengths printed from code); no seed, no key script, no options file, no module data enters
# fact: probe numbers -- the fixed list 0 1 48 49 363 799 800 999 in this script; no world, no roll
# fact: expected values -- computed in this script from the constants the engine prints, by the rule of spec 6.2 (skills 1..SK_LASTSKILL-1 and SK_HIGH_FIRST..SK_HIGH_END-1; SkillIndex maps the high block to SK_LASTSKILL up); nothing is copied from the code under test
# fact: the build -- the posix DEBUG binary ./incursion-headless the caller built; this script builds nothing
#
# What it guards (spec docs/superpowers/specs/2026-11-07-names-in-the-file-design.md 6.2): IsSkill,
# SkillIndex and SkillByIndex agree with the rule at 0, 1, 48, 49, 363, 799, 800 and 999 for the
# tree's SK_HIGH_END; SK_COUNT is SK_LASTSKILL plus the high block; Character::Feats holds a bit for
# every number to 999 (125 elements); SkillRanks has SK_COUNT elements; SK_COUNT fits the gallery
# record's SkillRanks[100].
#
# Usage: tools/check_skill_numbers.sh              (exit 0 pass, 1 fail, 2 could not measure)
#        tools/check_skill_numbers.sh --selftest   (proves red on planted wrong engine output; needs no binary)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# verify <file of SKILLNUMBERS lines>: prints one FAIL line per broken fact; returns 1 on any.
verify() {
    local f="$1" bad=0 line
    line="$(grep '^SKILLNUMBERS const ' "$f" | head -1)"
    [ -n "$line" ] || { echo "FAIL: no 'SKILLNUMBERS const' line"; return 1; }
    local L HF HE C FB
    L=$(sed -n 's/.* SK_LASTSKILL=\([0-9-]*\).*/\1/p' <<<"$line")
    HF=$(sed -n 's/.* SK_HIGH_FIRST=\([0-9-]*\).*/\1/p' <<<"$line")
    HE=$(sed -n 's/.* SK_HIGH_END=\([0-9-]*\).*/\1/p' <<<"$line")
    C=$(sed -n 's/.* SK_COUNT=\([0-9-]*\).*/\1/p' <<<"$line")
    FB=$(sed -n 's/.* FEATBITS_LAST=\([0-9-]*\).*/\1/p' <<<"$line")
    local v
    for v in "$L" "$HF" "$HE" "$C" "$FB"; do
        [[ "$v" =~ ^[0-9]+$ ]] || { echo "FAIL: unreadable constants line: $line"; return 1; }
    done
    [ "$C" -eq $((L + HE - HF)) ] || { echo "FAIL: SK_COUNT $C != SK_LASTSKILL $L + (SK_HIGH_END $HE - SK_HIGH_FIRST $HF)"; bad=1; }
    [ "$HF" -eq 800 ] || { echo "FAIL: SK_HIGH_FIRST is $HF, the ruling says 800"; bad=1; }
    [ "$HE" -ge "$HF" ] && [ "$HE" -le 1000 ] || { echo "FAIL: SK_HIGH_END $HE is outside $HF..1000"; bad=1; }
    [ "$C" -le 100 ] || { echo "FAIL: SK_COUNT $C passes the gallery SkillRanks[100]"; bad=1; }
    local lens fl sr rr
    lens="$(grep '^SKILLNUMBERS len ' "$f" | head -1)"
    fl=$(sed -n 's/.* Feats=\([0-9]*\).*/\1/p' <<<"$lens")
    sr=$(sed -n 's/.* SkillRanks=\([0-9]*\).*/\1/p' <<<"$lens")
    rr=$(sed -n 's/.* RInfSkillRanks=\([0-9]*\).*/\1/p' <<<"$lens")
    [ -n "$fl" ] && [ -n "$sr" ] && [ -n "$rr" ] || { echo "FAIL: no readable 'SKILLNUMBERS len' line"; return 1; }
    [ "$fl" -ge 125 ] || { echo "FAIL: Feats has $fl elements, it needs at least 125 (a bit for every number to 999)"; bad=1; }
    [ "$fl" -ge $((FB / 8 + 1)) ] || { echo "FAIL: Feats has $fl elements, FEATBITS_LAST $FB needs $((FB / 8 + 1))"; bad=1; }
    [ "$sr" -eq "$C" ] || { echo "FAIL: SkillRanks has $sr elements, SK_COUNT is $C"; bad=1; }
    [ "$rr" -eq 100 ] || { echo "FAIL: gallery SkillRanks is $rr elements, the file format says 100"; bad=1; }
    local n is ix by want_is want_ix want_by seen=0
    for n in 0 1 48 49 363 799 800 999; do
        line="$(grep "^SKILLNUMBERS n=$n " "$f" | head -1)"
        if [ -z "$line" ]; then echo "FAIL: no line for n=$n"; bad=1; continue; fi
        seen=$((seen + 1))
        is=$(sed -n 's/.* IsSkill=\([0-9-]*\).*/\1/p' <<<"$line")
        ix=$(sed -n 's/.* SkillIndex=\([0-9-]*\).*/\1/p' <<<"$line")
        by=$(sed -n 's/.* SkillByIndex=\([0-9-]*\).*/\1/p' <<<"$line")
        want_is=0; want_ix=0; want_by=0
        if { [ "$n" -ge 1 ] && [ "$n" -lt "$L" ]; } || { [ "$n" -ge "$HF" ] && [ "$n" -lt "$HE" ]; }; then want_is=1; fi
        if [ "$n" -ge 1 ] && [ "$n" -lt "$L" ]; then want_ix=$n
        elif [ "$n" -ge "$HF" ] && [ "$n" -lt "$HE" ]; then want_ix=$((L + n - HF)); fi
        if [ "$n" -ge 1 ] && [ "$n" -lt "$L" ]; then want_by=$n
        elif [ "$n" -ge "$L" ] && [ "$n" -lt "$C" ]; then want_by=$((HF + n - L)); fi
        [ "$is" = "$want_is" ] || { echo "FAIL: IsSkill($n) is $is, want $want_is"; bad=1; }
        [ "$ix" = "$want_ix" ] || { echo "FAIL: SkillIndex($n) is $ix, want $want_ix"; bad=1; }
        [ "$by" = "$want_by" ] || { echo "FAIL: SkillByIndex($n) is $by, want $want_by"; bad=1; }
    done
    grep -q '^SCHEMATEST GROUP skillnumbers PASS' "$f" || { echo "FAIL: the engine's own round trip (SkillByIndex(SkillIndex(n)) == n) did not pass"; bad=1; }
    return $bad
}

if [ "${1:-}" = "--selftest" ]; then
    T="$(mktemp -d "${TMPDIR:-/tmp}/skillnumbers.XXXXXX")"
    trap 'rm -rf "$T"' EXIT
    cat > "$T/good" <<'GOOD'
SKILLNUMBERS const SK_LASTSKILL=49 SK_HIGH_FIRST=800 SK_HIGH_END=800 SK_COUNT=49 FEATBITS_LAST=999
SKILLNUMBERS len Feats=125 SkillRanks=49 RInfSkillRanks=100
SKILLNUMBERS n=0 IsSkill=0 SkillIndex=0 SkillByIndex=0
SKILLNUMBERS n=1 IsSkill=1 SkillIndex=1 SkillByIndex=1
SKILLNUMBERS n=48 IsSkill=1 SkillIndex=48 SkillByIndex=48
SKILLNUMBERS n=49 IsSkill=0 SkillIndex=0 SkillByIndex=0
SKILLNUMBERS n=363 IsSkill=0 SkillIndex=0 SkillByIndex=0
SKILLNUMBERS n=799 IsSkill=0 SkillIndex=0 SkillByIndex=0
SKILLNUMBERS n=800 IsSkill=0 SkillIndex=0 SkillByIndex=0
SKILLNUMBERS n=999 IsSkill=0 SkillIndex=0 SkillByIndex=0
SCHEMATEST GROUP skillnumbers PASS
GOOD
    verify "$T/good" >/dev/null || { echo "SELFTEST FAIL: the good output was refused"; exit 1; }
    # the same output with one high skill planted (SK_HIGH_END 801, SK_COUNT 50) must also pass
    sed -e 's/SK_HIGH_END=800 SK_COUNT=49/SK_HIGH_END=801 SK_COUNT=50/' -e 's/SkillRanks=49/SkillRanks=50/' \
        -e 's/^\(SKILLNUMBERS n=49 \).*/\1IsSkill=0 SkillIndex=0 SkillByIndex=800/' \
        -e 's/^\(SKILLNUMBERS n=800 \).*/\1IsSkill=1 SkillIndex=49 SkillByIndex=0/' "$T/good" > "$T/high"
    verify "$T/high" >/dev/null || { echo "SELFTEST FAIL: the planted-high-skill output was refused"; verify "$T/high"; exit 1; }
    mut() { # <name> <sed expression>: the mutated output MUST be refused
        sed -e "$2" "$T/good" > "$T/m"
        if verify "$T/m" >/dev/null; then echo "SELFTEST FAIL: '$1' was accepted"; exit 1; fi
        echo "  red ok  $1"
    }
    mut "SkillIndex(48) wrong"       's/^\(SKILLNUMBERS n=48 .*SkillIndex=\)48/\147/'
    mut "IsSkill(1) false"           's/^\(SKILLNUMBERS n=1 IsSkill=\)1/\10/'
    mut "IsSkill(49) true"           's/^\(SKILLNUMBERS n=49 IsSkill=\)0/\11/'
    mut "IsSkill(800) true"          's/^\(SKILLNUMBERS n=800 IsSkill=\)0/\11/'
    mut "SkillIndex(999) nonzero"    's/^\(SKILLNUMBERS n=999 .*SkillIndex=\)0/\11/'
    mut "SkillByIndex(1) wrong"      's/^\(SKILLNUMBERS n=1 .*SkillByIndex=\)1/\12/'
    mut "Feats too short"            's/Feats=125/Feats=124/'
    mut "SkillRanks not SK_COUNT"    's/SkillRanks=49/SkillRanks=48/'
    mut "SK_COUNT past gallery"      's/SK_COUNT=49/SK_COUNT=101/'
    mut "SK_COUNT not the sum"       's/SK_COUNT=49/SK_COUNT=50/'
    mut "SK_HIGH_FIRST moved"        's/SK_HIGH_FIRST=800/SK_HIGH_FIRST=700/'
    mut "engine round trip failed"   's/GROUP skillnumbers PASS/GROUP skillnumbers FAIL/'
    mut "probe line missing"         '/^SKILLNUMBERS n=363 /d'
    echo "SELFTEST PASS"
    exit 0
fi

BIN="$ROOT/incursion-headless"
[ -x "$BIN" ] || { echo "UNMEASURED: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
W="$(mktemp -d "${TMPDIR:-/tmp}/skillnumbers.XXXXXX")"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/save"
"$BIN" -schematest "$W/save" -timeout 120 < /dev/null > "$W/out" 2> "$W/err"
rc=$?
# verify first: a broken helper makes the engine's own round trip fail, and that
# exit code would otherwise hide which fact broke.
verify "$W/out"; vrc=$?
if [ "$vrc" -eq 0 ] && [ "$rc" -eq 0 ]; then
    echo "PASS: IsSkill/SkillIndex/SkillByIndex, SK_COUNT, Feats and SkillRanks lengths agree with spec 6.2"
    exit 0
fi
[ "$rc" -eq 0 ] || { cat "$W/err"; echo "FAIL: -schematest exited $rc"; }
exit 1
