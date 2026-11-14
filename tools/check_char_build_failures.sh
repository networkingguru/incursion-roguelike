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
# fact: the save-perk text -- the first perk slot of that same recorded .char, rewritten to `perk_resist [n]: save confusion` (its other lines and its item's charges removed); the text states the perk, so the seed decides nothing about it (inc-10v7f)
# fact: the spell list -- the three spell_learn lines of tools/fixtures/chars/orc-mage-seed1-opt0822.char (a committed .char), the last one deleted; the text states the spells, so no seed decides them (inc-xgs1x)
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

# A build that loops grows about 650 MB a second (inc-xgs1x), so the one case
# that can loop runs under a cap: killed at CAP_MB of resident memory or CAP_S
# seconds, whichever comes first. The case then FAILS instead of hanging.
# CAP_S allows a slow build on a loaded machine (a normal build takes about 15 s;
# the landing gate runs many checks at once).
CAP_MB=1024
CAP_S=120
capped_build() {   # <char> -> as build(); RC 99 and $HUNG set when the cap killed it
    HUNG=""
    INCURSION_BIN="$BIN" tools/build_fixture.sh "$1" "$W/out$n" > "$W/stdout.txt" 2> "$W/stderr.txt" &
    local pid=$! t0=$SECONDS peak=0 mb
    while kill -0 "$pid" 2> /dev/null; do
        local pl
        pl="$(ps -A -o pid=,ppid=,rss= 2> /dev/null)"
        if [ -z "$pl" ]; then   # the cap would run blind
            kill -9 "$pid" 2> /dev/null
            HUNG="cannot read process memory"
            break
        fi
        mb="$(printf '%s\n' "$pl" | awk -v root="$pid" '
            { ppid[$1] = $2; rss[$1] = $3 }
            END { for (p in rss) { q = p; while (q != "" && q != 0) { if (q == root) { sum += rss[p]; break } q = ppid[q] } } print int(sum / 1024) }')"
        [ "${mb:-0}" -gt "$peak" ] && peak="$mb"
        if [ "${mb:-0}" -ge "$CAP_MB" ] || [ $((SECONDS - t0)) -ge "$CAP_S" ]; then
            HUNG="the build hung: killed at ${mb} MB / $((SECONDS - t0)) s"
            printf '%s\n' "$pl" | awk -v root="$pid" '
                { ppid[$1] = $2 }
                END { for (p in ppid) { q = p; while (q != "" && q != 0) { if (q == root) { print p; break } q = ppid[q] } } }' \
                | while read -r k; do kill -9 "$k" 2> /dev/null; done
            break
        fi
        sleep 1
    done
    wait "$pid" 2> /dev/null
    RC=$?
    [ -n "$HUNG" ] && RC=99
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

# A caster whose file states one spell too few. The build used to ask for the
# missing spell forever: nothing was learned, the slot stayed free, and nothing
# was read or drawn, so no tripwire fired (inc-xgs1x). It must fail at once.
MAGE=tools/fixtures/chars/orc-mage-seed1-opt0822.char
LAST="$(grep -n '^spell_learn:' "$MAGE" | tail -1 | cut -d: -f1)"
[ -n "$LAST" ] || { echo "INCONCLUSIVE: $MAGE has no spell_learn line"; exit 2; }
sed "${LAST}d" "$MAGE" > "$W/nospell.char"
if ! ps -A -o pid=,rss= > /dev/null 2>&1 || [ -z "$(ps -o rss= -p $$ 2> /dev/null)" ]; then
    echo "UNMEASURED: cannot read process memory (ps), so the build cannot be capped; not running the spell_learn case"
    exit 2
fi
n=$((n + 1))
capped_build "$W/nospell.char"
if [ -n "$HUNG" ]; then
    echo "FAIL a free spell slot with no spell_learn line left: $HUNG"; fail=1
elif [ "$RC" -ne 10 ]; then
    echo "FAIL a free spell slot with no spell_learn line left: exit $RC, want 10"; fail=1
else
    line="$(grep -m1 '^BUILD FAILED:' "$W/stderr.txt")"
    if grep -qF 'spell_learn' <<< "$line"; then
        echo "ok   a free spell slot with no spell_learn line left"
        echo "       $line" | cut -c1-230
    else
        echo "FAIL a free spell slot with no spell_learn line left: wanted spell_learn in: $line"; fail=1
    fi
fi

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

# A "save confusion" perk builds (the reader once rejected
# `perk_resist: save confusion`: SaveBonusNames names "confusion" twice). The
# text states the perk: the first perk slot of the recorded file is rewritten to
# `perk_resist [n]: save confusion`, whatever that slot held (and the charges of
# its item, if it held one), so no seed decides what is built.
python3 - "$W/good.char" "$W/save.char" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().split("\n")
out, slot, item = [], None, None
for l in lines:
    m = re.match(r"^perk_type \[(\d+)\]: (\S+)", l)
    if m and slot is None:
        slot = m.group(1)
        out += ["perk_type [%s]: PERK_RESIST" % slot, "perk_resist [%s]: save confusion" % slot]
        continue
    if slot is not None and re.match(r"^perk_[a-z]+ \[%s\]: " % slot, l):
        im = re.match(r"^perk_item \[%s\]: ([^,]*)" % slot, l)
        if im:
            item = im.group(1).split(";")[0].strip()
        continue
    out.append(l)
if slot is None:
    sys.exit(3)
if item is not None:   # the charges line of the item that is no longer there
    for i, l in enumerate(out):
        if re.match(r"^perk_charges \[%s\]: " % re.escape(item), l):
            del out[i]
            break
open(sys.argv[2], "w").write("\n".join(out))
PY
[ $? -eq 0 ] || { echo "INCONCLUSIVE: the recorded .char has no perk slot to rewrite"; exit 2; }
grep -qx 'perk_resist \[[0-9]*\]: save confusion' "$W/save.char" \
    || { echo "INCONCLUSIVE: the rewritten .char does not state the save perk"; exit 2; }
n=$((n + 1))
build "$W/save.char"
if [ "$RC" -eq 0 ]; then
    echo "ok   a stated '$(grep -m1 '^perk_resist' "$W/save.char")' perk builds"
else
    echo "FAIL save perk: exit $RC: $ERR" | cut -c1-230; fail=1
fi

[ $fail -eq 0 ] && { echo "PASS: every bad .char failed as stated"; exit 0; }
exit 1
