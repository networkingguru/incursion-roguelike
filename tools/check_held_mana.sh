#!/bin/bash
# gate: live
# Three owner rulings about HELD mana, observed through real keystrokes. RED on
# the code before the fix; each property prints its own PASS or FAIL line.
# (bd inc-w6n5)
#
# A creature has spent mana (uMana, regenerates), held mana (hMana, does not)
# and current mana (what is left). A spell with EF_LOSEMANA holds its cost
# (Creature::Cast -> LoseMana(cost, true)). Nothing lowers held mana when the
# buff ends. The three rulings:
#   1. Drop a held buff from the Cancel Standing Ability menu: held mana falls
#      by the cost and spent mana rises by the same amount (no refund). Cast
#      the buff again after the drop: held mana equals ONE casting's cost.
#   2. A Cure Wounds spell on an injured character leaves held mana unchanged
#      and raises spent mana instead (today: src/Effects.cpp:2394 holds it).
#   3. Mana released by a dropped buff regenerates even while current mana is
#      below the regen floor (src/Creature.cpp:1798), up to the released amount.
#
# HOW IT READS. Screens show only current mana, so held and spent come from the
# session's own Save and Continue, read by tools/dump_save.sh ("spent S, held
# H"), exactly as tools/check_mana_regen_cast.sh does. One session per reading
# point: every session replays the same fixture, settings and seed, so a longer
# script passes through the shorter script's state.
#
# fact: priest-mage character, knows Shield and Cure Light Wounds -- fixture human-priest-mage-seed4-gate, INCURSION_LOAD
# fact: mage character, knows Shield and Burning Hands, Concentration +3 -- fixture orc-mage-seed4-gate, INCURSION_LOAD
# fact: settings -- CHECK_OPTIONS=tools/gates/Options.Dat (Freeze Monsters NO, so the goblin fights)
# fact: Shield's cost in mana -- derived: held after one casting minus held at baseline, both read from the save dump; INCONCLUSIVE when not positive
# fact: Cure Light Wounds' cost -- derived: spent after the cast minus spent before it; it varies with the wound, so it is never hard-coded
# fact: the wound -- wizard Monster Summoning (goblin) then waits until HP shows 20-29; INCONCLUSIVE if the pre and cast sessions disagree on HP before the cure, or HP is full
# fact: spent mana regenerating in the few turns between casts -- tolerated by 1 point on spent only (current mana is above the floor then); held mana is compared exactly
# fact: current mana below the floor for property 3 -- 30 casts of Burning Hands aimed RIGHT; the check computes the percentage and is INCONCLUSIVE unless it is under 74 (max(80-2*3,35))
# fact: wait without resting -- three searches ('s'), about 25 turns each
#
# --prove-red (mutation A): makes Status.cpp's ReleaseHeldMana return at once,
# which is the code before the fix (a dropped buff never gives its held mana
# back). Properties 1a, 1b and 3 then go red.
#
# Usage: tools/check_held_mana.sh [--prove-red]   (0 all pass, 1 any fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/gates/Options.Dat
SEED=4
PM=tools/fixtures/chars/human-priest-mage-seed4-gate.sav
OM=tools/fixtures/chars/orc-mage-seed4-gate.sav

# --prove-red performs the FIRST declared mutation only (tools/check_lib.sh), so
# HELD_MUT chooses which one is first: A (default) = no release, D = undo the
# released-credit floor, C = healing holds again. An ordinary run guards all three.
_mut_a() { check_mutation src/Status.cpp \
'    if (s.Nature == HELD_MANA || !s.eID || !s.h)' \
'    if (true)'; }
_mut_d() { check_mutation inc/Creature.h \
'        { return HasReleasedMana() ? 0 : max(80 - SkillLevel(SK_CONCENT)*2, 35); }' \
'        { return max(80 - SkillLevel(SK_CONCENT)*2, 35); }'; }
_mut_c() { check_mutation src/Effects.cpp \
'e.EActor->LoseMana((amt*10)/e.EMagic->yval,false);' \
'e.EActor->LoseMana((amt*10)/e.EMagic->yval,true);'; }
case "${HELD_MUT:-A}" in
    D) _mut_d ;; C) _mut_c ;; *) _mut_a ;;
esac
_mut_a; _mut_d; _mut_c

[ -f "$PM" ] && [ -f "$OM" ] || _check_die 2 "a fixture is missing: $PM or $OM"

# <run dir> -> "spent held" from the session's own save
_dump() {
    local save dump line spent held
    save="$(ls "$1"/save/*.sav 2>/dev/null | head -1)"
    [ -n "$save" ] || _check_die 2 "no .sav under $1/save. Did the key script reach its Save and Continue?"
    dump="$(tools/dump_save.sh "$save" 2>&1)" || _check_die 2 "tools/dump_save.sh failed on $save" "$dump"
    line="$(printf '%s\n' "$dump" | grep '^Mana:')"
    spent="$(echo "$line" | grep -oE 'spent [0-9]+' | grep -oE '[0-9]+')"
    held="$(echo "$line" | grep -oE 'held [0-9]+' | grep -oE '[0-9]+')"
    [ -n "$spent" ] && [ -n "$held" ] || _check_die 2 "cannot read spent and held from the dump of $save: $line"
    echo "$spent $held"
}

# <run dir> <screen label> -> "cur max" off the status line, or nothing
_screen_mana() {
    local f
    f="$(ls "$1"/logs/screens/*"$2".txt 2>/dev/null | head -1)"
    [ -n "$f" ] || return 0
    grep -oE 'Mana:[0-9]+/[0-9]+' "$f" | head -1 | sed -e 's/Mana://' -e 's#/# #'
}

_hp_of() { # <run dir> <label> -> current HP
    local f
    f="$(ls "$1"/logs/screens/*"$2".txt 2>/dev/null | head -1)"
    [ -n "$f" ] && grep -oE 'HP:[0-9]+/[0-9]+' "$f" | head -1 | sed -e 's/HP://' -e 's#/.*##'
}

_session() { # <load> <keys> -> sets CHECK_RUN
    export INCURSION_LOAD="$1"
    check_run "$2" "$SEED"
}

FAIL=0
echo "== property 1: drop releases, recast holds once =="
_session "$PM" tools/keys/held-mana-base.keys;   read -r B_SPENT B_HELD <<<"$(_dump "$CHECK_RUN")"
_session "$PM" tools/keys/held-mana-cast.keys;   read -r C_SPENT C_HELD <<<"$(_dump "$CHECK_RUN")"
_session "$PM" tools/keys/held-mana-drop.keys;   read -r D_SPENT D_HELD <<<"$(_dump "$CHECK_RUN")"
_session "$PM" tools/keys/held-mana-recast.keys; read -r R_SPENT R_HELD <<<"$(_dump "$CHECK_RUN")"

COST=$((C_HELD - B_HELD))
[ "$COST" -gt 0 ] || _check_die 2 "Shield was not cast: held mana went $B_HELD -> $C_HELD."

if [ "$D_HELD" -eq "$B_HELD" ] && [ "$D_SPENT" -ge $((B_SPENT + COST - 1)) ] && [ "$D_SPENT" -le $((B_SPENT + COST)) ]; then
    echo "PASS 1a: after dropping Shield (cost $COST), held $C_HELD -> $D_HELD, spent $C_SPENT -> $D_SPENT."
else
    echo "FAIL 1a: after dropping Shield (cost $COST), held $C_HELD -> $D_HELD (want $B_HELD), spent $C_SPENT -> $D_SPENT (want $((B_SPENT + COST)), or one less after regeneration). Baseline held $B_HELD spent $B_SPENT."
    FAIL=1
fi
if [ "$R_HELD" -eq $((B_HELD + COST)) ]; then
    echo "PASS 1b: Shield cast, dropped and cast again holds $R_HELD, one casting's cost ($COST) over baseline $B_HELD."
else
    echo "FAIL 1b: Shield cast, dropped and cast again holds $R_HELD (want $((B_HELD + COST)), one casting). Spent $R_SPENT. Baseline held $B_HELD."
    FAIL=1
fi

echo "== property 2: healing does not hold =="
_session "$PM" tools/keys/held-mana-heal-pre.keys;  PRE_RUN="$CHECK_RUN"; read -r P_SPENT P_HELD <<<"$(_dump "$CHECK_RUN")"
_session "$PM" tools/keys/held-mana-heal-cast.keys; CAST_RUN="$CHECK_RUN"; read -r H_SPENT H_HELD <<<"$(_dump "$CHECK_RUN")"
HP_PRE="$(_hp_of "$PRE_RUN" hurt)"; HP_CAST_BEFORE="$(_hp_of "$CAST_RUN" hurt)"; HP_AFTER="$(_hp_of "$CAST_RUN" healed)"
[ -n "$HP_PRE" ] && [ -n "$HP_CAST_BEFORE" ] && [ -n "$HP_AFTER" ] || _check_die 2 "cannot read HP off the hurt/healed screens."
[ "$HP_PRE" -eq "$HP_CAST_BEFORE" ] || _check_die 2 "the pre and cast sessions were wounded differently ($HP_PRE vs $HP_CAST_BEFORE HP)."
HP_MAX="$(grep -oE 'HP:[0-9]+/[0-9]+' "$CAST_RUN"/logs/screens/*hurt.txt | head -1 | sed 's#.*/##')"
[ "$HP_PRE" -lt "$HP_MAX" ] || _check_die 2 "the character is not wounded ($HP_PRE/$HP_MAX)."
[ "$H_SPENT" -gt "$P_SPENT" ] || [ "$H_HELD" -gt "$P_HELD" ] || _check_die 2 "Cure Light Wounds cost nothing (spent $P_SPENT -> $H_SPENT, held $P_HELD -> $H_HELD): not cast."
if [ "$H_HELD" -eq "$P_HELD" ] && [ "$H_SPENT" -gt "$P_SPENT" ]; then
    echo "PASS 2: Cure Light Wounds at HP $HP_PRE -> $HP_AFTER left held $P_HELD -> $H_HELD and raised spent $P_SPENT -> $H_SPENT."
else
    echo "FAIL 2: Cure Light Wounds at HP $HP_PRE -> $HP_AFTER: held $P_HELD -> $H_HELD (want unchanged), spent $P_SPENT -> $H_SPENT (want a rise)."
    FAIL=1
fi

echo "== property 3: released mana regenerates below the floor =="
_session "$OM" tools/keys/held-mana-floor.keys; F_RUN="$CHECK_RUN"; read -r F_SPENT F_HELD <<<"$(_dump "$CHECK_RUN")"
read -r A_CUR A_MAX <<<"$(_screen_mana "$F_RUN" arrival)"
read -r S_CUR S_MAX <<<"$(_screen_mana "$F_RUN" shield-cast)"
read -r X_CUR X_MAX <<<"$(_screen_mana "$F_RUN" after-drop)"
read -r W_CUR W_MAX <<<"$(_screen_mana "$F_RUN" after-wait)"
for v in A_CUR S_CUR X_CUR W_CUR; do
    [ -n "${!v}" ] || _check_die 2 "cannot read $v off its screen dump."
done
REL=$((A_CUR - S_CUR))
[ "$REL" -gt 0 ] || _check_die 2 "Shield was not cast on the mage: mana $A_CUR -> $S_CUR."
PCT=$((X_CUR * 100 / X_MAX))
[ "$PCT" -lt 74 ] || _check_die 2 "current mana after the drop is $X_CUR/$X_MAX = $PCT%, not under the 74% floor: the setup did not reach the case."
if [ "$W_CUR" -gt "$X_CUR" ] && [ "$W_CUR" -le $((X_CUR + REL)) ]; then
    echo "PASS 3: Shield (cost $REL) dropped at $X_CUR/$X_MAX ($PCT%, under the floor); about 75 turns of searching raised mana to $W_CUR. Save: spent $F_SPENT, held $F_HELD."
else
    echo "FAIL 3: Shield (cost $REL) dropped at $X_CUR/$X_MAX ($PCT%, under the floor); about 75 turns of searching left mana at $W_CUR (want a rise of 1 to $REL). Save: spent $F_SPENT, held $F_HELD (released mana should not stay held)."
    FAIL=1
fi

echo
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: held-mana rulings not met (see FAIL lines above)."
    exit 1
fi
echo "PASS: all three held-mana rulings hold."
exit 0
