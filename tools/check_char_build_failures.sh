#!/usr/bin/env bash
# gate: live
#
# Does a bad .char file fail the build, loudly, with the one-line fix?
#
# WHAT IS BEING PROVED. Spec section 3 and amendments A5, B4 (bead inc-10v7f,
# phase 7a): a fixture must never change a character silently. Each case below
# edits a good .char in one way and asserts the build exits 10 with a stderr
# line beginning `BUILD FAILED:` that carries the stated text:
#   unknown key, malformed line, a key a build never asks (observed, not
#   stated), surplus value, missing line (with the exact line to add and its
#   default), a pick value that matches no candidate, a name not in the module,
#   an out-of-range skill rank, an out-of-range attribute.
# Two label rules need a candidate list the game does not offer twice, so they
# run through `incursion-headless -charpicktest`: an ambiguous label (two
# candidates with one name), and the repeated-request rule B4 (a request with
# a value left in its queue takes it; with the queue empty it fails as
# rejected). The same rule is shown at a real site -- a class pick the game
# refuses and asks again -- when the module has one.
#
# fact: the character -- a .char recorded now by tools/headless.sh from tools/keys/chargen-default-save.keys at seed 1 under tools/fixtures/options-2026-08-22.dat; every case is a text edit of that file, so no seed decides it (inc-10v7f)
# fact: the failure text -- the strings src/CharFile.cpp writes after `BUILD FAILED:`, matched here by fixed substrings
# fact: the label candidates -- the fixed list RunCharPickTest builds (two "Fire Bolt", "<5>Cold Bolt", "Ice Bolt"), not game data
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_char_build_failures.sh
# Exit: 0 every case failed (or passed) as stated; 1 a case did not; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
O22=tools/fixtures/options-2026-08-22.dat

W="$(mktemp -d "$ROOT/logs/char-failures.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT

INCURSION_RECORD_CHAR="$W/good.char" INCURSION_OPTIONS="$O22" INCURSION_BIN="$BIN" \
    INCURSION_RUN_DIR="$W/walk" tools/headless.sh tools/keys/chargen-default-save.keys 1 \
    > "$W/walk.log" 2>&1 < /dev/null
[ -f "$W/good.char" ] || { echo "INCONCLUSIVE: the recording run left no .char"; exit 2; }

fail=0
n=0
build() {   # <char> -> stderr text in $ERR, exit status in $RC
    INCURSION_BIN="$BIN" tools/build_fixture.sh "$1" "$W/out$n" > "$W/stdout.txt" 2> "$W/stderr.txt"
    RC=$?
    ERR="$(cat "$W/stderr.txt")"
}

expect_fail() {   # <label> <substring> <char file>
    n=$((n + 1))
    build "$3"
    local err="$ERR"
    if [ "$RC" -ne 10 ]; then
        echo "FAIL $1: exit $RC, want 10"; fail=1; return
    fi
    local line
    line="$(printf '%s\n' "$err" | grep -m1 '^BUILD FAILED:')"
    if [ -z "$line" ]; then echo "FAIL $1: no BUILD FAILED line"; fail=1; return; fi
    if grep -qF -- "$2" <<< "$line"; then
        echo "ok   $1"
        echo "       $line" | sed "s|$ROOT/||g" | cut -c1-230
    else
        echo "FAIL $1: wanted \"$2\" in: $line"; fail=1
    fi
}

edit() {   # <name> <sed script> -> $W/<name>.char from good.char
    sed "$2" "$W/good.char" > "$W/$1.char"
}

# The good file builds.
n=$((n + 1))
build "$W/good.char"
if [ "$RC" -ne 0 ]; then echo "INCONCLUSIVE: the unedited .char does not build: $ERR"; exit 2; fi
echo "ok   the recorded .char builds"

cp "$W/good.char" "$W/unknown.char"; echo 'bogus_key: 1' >> "$W/unknown.char"
expect_fail "unknown key" 'unknown key "bogus_key"' "$W/unknown.char"

cp "$W/good.char" "$W/malformed.char"; echo 'this is not a line' >> "$W/malformed.char"
expect_fail "malformed line" 'malformed line' "$W/malformed.char"

cp "$W/good.char" "$W/observed.char"; echo 'attr_set: a' >> "$W/observed.char"
expect_fail "a key the build never asks" 'is observed, not stated' "$W/observed.char"

cp "$W/good.char" "$W/surplus.char"; echo 'hp_roll [Barbarian]: 5' >> "$W/surplus.char"
expect_fail "surplus value" 'surplus: this stated value was never used: hp_roll [Barbarian]: 5' "$W/surplus.char"

grep -v '^hp_roll \[Barbarian\]:' "$W/good.char" > "$W/missing.char"
expect_fail "missing line (prints the line to add)" 'add: hp_roll [Barbarian]: 1' "$W/missing.char"

edit badpick 's/^race: Orc$/race: Klingon/'
expect_fail "pick value matches no candidate" '"Klingon" matches no candidate; candidates:' "$W/badpick.char"

edit badname 's/^\(kit_item \[Orc;a[0-9]*\]: \)[^,]*/\1no such thing/'
expect_fail "a name not in the module" 'no item named "no such thing" in the module' "$W/badname.char"

edit rank 's/^skill_ranks \[Climb\]: .*/skill_ranks [Climb]: 99/'
expect_fail "out-of-range skill rank" 'skill_ranks [Climb]: 99 is outside' "$W/rank.char"
expect_fail "out-of-range skill rank (range printed)" 'is outside 0 to' "$W/rank.char"

edit attr 's/^attr_str: .*/attr_str: 40/'
expect_fail "out-of-range attribute" 'attr_str: 40 is outside 3 to 18' "$W/attr.char"

# Label rules, on a list the game does not offer. The sandbox is an empty
# run directory: -charpicktest touches no game file.
mkdir -p "$W/pt/save" "$W/pt/logs"
picktest() {   # <name> <asks> <lines...> -> output in $PT, status in $RC
    local name="$1" asks="$2"; shift 2
    printf 'options: x\nseed: 1\n' > "$W/$name.char"
    printf '%s\n' "$@" >> "$W/$name.char"
    local a=()
    [ "$asks" -gt 0 ] && a=(-charasks "$asks")
    PT="$(env -u INCURSION_SEED INCURSIONPATH="$W/pt/" "$BIN" -headless -charpicktest "$W/$name.char" ${a[@]+"${a[@]}"} 2>&1 < /dev/null)"
    RC=$?
}
want_pt() {   # <label> <exit> <substring>
    if [ "$RC" -eq "$2" ] && grep -qF -- "$3" <<< "$PT"; then
        echo "ok   $1"; echo "       $(printf '%s' "$PT" | tail -1 | cut -c1-200)"
    else
        echo "FAIL $1: exit $RC, wanted $2 and \"$3\" in: $PT"; fail=1
    fi
}
picktest ambig 0 'race: Fire Bolt'
want_pt "ambiguous label" 10 '"Fire Bolt" is ambiguous, 2 candidates carry that name'
picktest norm 0 'race: Cold Bolt'
want_pt "a colour code is stripped, the label matches" 0 'is candidate 2'
picktest case 0 'race: cold bolt'
want_pt "case is kept: a different case matches nothing" 10 'matches no candidate'
picktest again1 2 'race: Ice Bolt'
want_pt "repeated request, queue empty: rejected (B4)" 10 'stated value rejected by the game'
picktest again2 2 'race: Ice Bolt' 'race: Ice Bolt'
want_pt "repeated request, value left in the queue: passes (B4)" 0 'is candidate 3'
picktest again3 3 'race: Ice Bolt' 'race: Ice Bolt'
want_pt "third request, queue empty again: rejected (B4)" 10 'stated value rejected by the game'

# The repeated-request rule at a real site (B4). In the Weapon Focus pick of
# the feats walk, a weapon too large for a human makes the game ask "Continue?"
# (weapon_unfit_confirm [size]); answering no sends it back to the same pick.
INCURSION_RECORD_CHAR="$W/feats.char" INCURSION_OPTIONS="$O22" INCURSION_BIN="$BIN" \
    INCURSION_RUN_DIR="$W/feats-walk" tools/headless.sh tools/keys/p6a-human-warrior-feats.keys 1 \
    > "$W/feats-walk.log" 2>&1 < /dev/null
[ -f "$W/feats.char" ] || { echo "INCONCLUSIVE: the feats walk left no .char"; exit 2; }
n=$((n + 1))
build "$W/feats.char"
[ "$RC" -eq 0 ] || { echo "INCONCLUSIVE: the recorded feats .char does not build: $ERR"; exit 2; }
awk '/^feat_weapon: battleaxe$/ { print "feat_weapon: huge club"; print "weapon_unfit_confirm [size]: no"; print "feat_weapon: battleaxe"; next } { print }' \
    "$W/feats.char" > "$W/again-left.char"
n=$((n + 1))
build "$W/again-left.char"
if [ "$RC" -eq 0 ]; then
    echo "ok   a refused weapon asked again, with a value left in the queue: the build passes (B4, real site)"
else
    echo "FAIL again-left: exit $RC: $ERR"; fail=1
fi
awk '/^feat_weapon: battleaxe$/ { print "feat_weapon: huge club"; print "weapon_unfit_confirm [size]: no"; next } { print }' \
    "$W/feats.char" > "$W/again-empty.char"
expect_fail "a refused weapon asked again, queue empty (B4, real site)" 'stated value rejected by the game' "$W/again-empty.char"

[ $fail -eq 0 ] && { echo "PASS: every bad .char failed as stated"; exit 0; }
exit 1
