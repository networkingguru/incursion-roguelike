#!/bin/bash
# gate: live
# The player mana-regen floor must START high and FALL with Concentration,
# not start low and rise. (bd inc-41kg)
#
# THE DEFECT. Creature::DoTurn (src/Creature.cpp) only lets per-tick mana
# regen run once cMana() is at or above a floor percentage of nhMana(). The
# base code read that floor as 35 + SkillLevel(SK_CONCENT)*2, capped at 80:
# a player with NO Concentration regenerates at 35% and up, and training the
# skill RAISES the floor toward 80%, which punishes practice. The owner
# ruled the intended shape is the opposite: floor = max(80 -
# SkillLevel(SK_CONCENT)*2, 35) -- it STARTS at 80% and FALLS toward 35% as
# Concentration rises, so training the skill makes regen easier to reach,
# not harder. Creature::ManaRegenFloor() (inc/Creature.h) now computes the
# corrected formula; Creature::DoTurn calls it and nothing inside the
# ManaPulse block below the condition changed.
#
# THE ORACLE is INCURSION_MANA_FLOOR_PROBE, which arms
# Character::ManaFloorProbe() (src/Create.cpp), run once at the top of
# Game::Play() on the live loaded player (src/Main.cpp). For LOW
# Concentration (0 ranks) and then HIGH Concentration (30 ranks, so
# SkillLevel(SK_CONCENT) >= 23), it: zeroes held mana, sets spent mana so
# current mana is 40% of the pool, clears ManaPulse, and drives 50 real
# ticks through Creature::DoTurn() -- the same per-tick code the live game
# runs, not a reimplementation of the formula. Each case is narrated through
# Error() as "MANA_FLOOR_PROBE case=<low|high> skill=<n> before=<n>
# after=<n>", the same errors.log channel check_xp_drain.sh and
# check_quiet_lookup.sh read.
#
# THE PROPERTY, read off the two lines. At 40% of the pool:
#   LOW  (floor 80%, since 80-2*0=80):  40 < 80, so 50 ticks change nothing.
#   HIGH (floor 35%, since 80-2*30 clamps to 35): 40 >= 35, so regen runs and
#        after > before.
# The un-fixed formula gives the opposite: LOW floor is 35 (regen runs) and
# HIGH floor is 80 (blocked). So this check goes red on the old formula and
# green on the new one.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation
# below restores the exact base-code condition this check defends against.
#
# Usage: tools/check_mana_regen_floor.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/gates/Options.Dat

SEED=4
KEYS=tools/keys/load-char-sheet.keys

# The mutation this check defends: the base-code condition, read directly off
# Creature::DoTurn before this fix. Declared before the run below so
# --prove-red intercepts here, before the (build-needing) measurement runs.
check_mutation src/Creature.cpp \
'        if (!isPlayer() || cMana() >= ((nhMana()*ManaRegenFloor())/100)) {' \
'        if (!isPlayer() || cMana() >= ((nhMana()*min(35+SkillLevel(SK_CONCENT)*2,80))/100)) {'

export INCURSION_MANA_FLOOR_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav

check_run "$KEYS" "$SEED"

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 \
    "the run logged nothing at all. The probe reports through Error()," \
    "so an empty log means it never ran."

# Drop the indented backtrace blocks headless.sh attaches to a first
# occurrence; they quote the message text and would be counted twice.
CLEAN="$(grep -v '^    ' "$LOG")"

LOW_LINE="$(printf '%s\n' "$CLEAN" | grep 'MANA_FLOOR_PROBE case=low ' | head -1)"
HIGH_LINE="$(printf '%s\n' "$CLEAN" | grep 'MANA_FLOOR_PROBE case=high ' | head -1)"

[ -n "$LOW_LINE" ] && [ -n "$HIGH_LINE" ] || _check_die 2 \
    "the probe never logged both cases. Is Character::ManaFloorProbe() still" \
    "called from Game::Play() (src/Main.cpp), and does this build contain it?"

LOW_SKILL="$(echo "$LOW_LINE" | grep -oE 'skill=-?[0-9]+' | sed 's/skill=//')"
LOW_BEFORE="$(echo "$LOW_LINE" | grep -oE 'before=-?[0-9]+' | sed 's/before=//')"
LOW_AFTER="$(echo "$LOW_LINE" | grep -oE 'after=-?[0-9]+' | sed 's/after=//')"

HIGH_SKILL="$(echo "$HIGH_LINE" | grep -oE 'skill=-?[0-9]+' | sed 's/skill=//')"
HIGH_BEFORE="$(echo "$HIGH_LINE" | grep -oE 'before=-?[0-9]+' | sed 's/before=//')"
HIGH_AFTER="$(echo "$HIGH_LINE" | grep -oE 'after=-?[0-9]+' | sed 's/after=//')"

for v in LOW_SKILL LOW_BEFORE LOW_AFTER HIGH_SKILL HIGH_BEFORE HIGH_AFTER; do
    [ -n "${!v}" ] || _check_die 2 \
        "could not parse $v out of the probe lines:" \
        "  $LOW_LINE" "  $HIGH_LINE"
done

FAIL=0

if [ "$LOW_SKILL" -gt 5 ]; then
    echo "FAIL: the LOW case did not measure a low SkillLevel(SK_CONCENT)."
    echo "      skill=$LOW_SKILL (wanted a low value, close to 0)"
    FAIL=1
fi

if [ "$HIGH_SKILL" -lt 23 ]; then
    echo "FAIL: the HIGH case did not measure SkillLevel(SK_CONCENT) >= 23."
    echo "      skill=$HIGH_SKILL (wanted >= 23)"
    FAIL=1
fi

if [ "$LOW_AFTER" -ne "$LOW_BEFORE" ]; then
    echo "FAIL: low Concentration gained mana over 50 ticks; the floor should"
    echo "      block regen at 40% when SkillLevel is low."
    echo "      skill=$LOW_SKILL before=$LOW_BEFORE after=$LOW_AFTER"
    FAIL=1
fi

if [ "$HIGH_AFTER" -le "$HIGH_BEFORE" ]; then
    echo "FAIL: high Concentration did not gain mana over 50 ticks; the floor"
    echo "      should drop to 35% and let regen through at 40%."
    echo "      skill=$HIGH_SKILL before=$HIGH_BEFORE after=$HIGH_AFTER"
    FAIL=1
fi

echo
echo "--- what the probe logged ---"
echo "$LOW_LINE"
echo "$HIGH_LINE"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi

echo
echo "PASS: seed $SEED -- low Concentration (skill=$LOW_SKILL) held mana at"
echo "      $LOW_BEFORE for 50 ticks (floor above 40%); high Concentration"
echo "      (skill=$HIGH_SKILL) rose from $HIGH_BEFORE to $HIGH_AFTER"
echo "      (floor at or below 40%)."
exit 0
