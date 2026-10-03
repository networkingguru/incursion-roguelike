#!/bin/bash
# gate: live
# Do lock-picking and door-kicking follow the settled design? (bd inc-h22n)
#
# WHAT RUNS. One headless session loads a frozen orc barbarian (Str 18, Medium,
# no Lockpicking ranks) and, before the first key, Game::Play calls
# DoorPickProbe (src/DoorPickProbe.cpp, INCURSION_DOORPICK_PROBE=1). The probe
# places a door and a chest beside the player and drives the REAL event paths:
# Throw(EV_OPEN) for a door, Container::PickLock for a chest,
# ThrowVal(EV_SATTACK, A_KICK) for a kick. It sets Lockpicking ranks, Strength
# and size directly, so the character's own numbers do not matter. It writes
# one line per case to logs/doorpick.log. Creature::SkillCheck reports each
# Lockpicking check's DC and bonus to the probe, so a DC is read, not inferred.
#
# WHAT IT ASSERTS, by design point (tools/check_door_probe.py prints each line):
#   2  untrained creature cannot try (door and chest); trained: DC 20+2*depth
#      (door) and 25+2*depth (chest), +10 wizard locked; no retry bonus; three
#      attempts in a row with no rest; a full round (Timeout 30) per attempt;
#      out of combat a failure repeats by itself (ACTING) for >= 15 attempts;
#      in combat one attempt per command and the next command may retry.
#   3  kick = d20 + Str modifier + size modifier vs the Break DC (+10 wizard
#      locked, -2 at half HP or less), measured as a success rate over 400 kicks
#      per case, +/- 8 points; a failed kick never lowers the door's HP; a kick
#      costs one standard action (3000/max(100+Attr[A_SPD_MELEE]*5,10)); every
#      T_DOOR feature has a Break DC (each is kicked at Str 20 and Str 40 and a
#      feature outside the design table fails); 60 kicks in a row all run.
#
# RED on the unmodified code (measured; see the bead): untrained pick tried,
# TRIED blocks a retry, DC 14+depth / 19+depth, retry bonus grows, no repeat,
# kicks never break an oak door at Str 10, failed kicks cost HP, kick Timeout 10.
#
# LIMITS, stated so a pass is not over-read. The probe cannot read message text,
# so "a clear message for an untrained player" and "today's wizard-lock message"
# are not asserted. It stops the repeat at 15 attempts and never reaches the
# 20-attempt "keep trying?" prompt (a prompt needs a key). It covers sizes Small,
# Medium and Large (-4, 0, +4); Incursion has eight size steps where the SRD has
# nine, so how Fine/Diminutive/Tiny map is not asserted. Chest repeat is not
# asserted: the brief names the repeat for the door path.
#
# Usage: tools/check_door_pick_kick.sh [--selftest]   exit 0 pass, 1 fail, 2 inconclusive
case "${1:-}" in
    --selftest) exec python3 "$(dirname "$0")/check_door_probe.py" selftest ;;
esac
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_DOORPICK_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav

check_run tools/keys/door-pick-kick.keys 1 > /dev/null || exit $?
LOG="$CHECK_RUN/logs/doorpick.log"
[ -f "$LOG" ] || _check_die 2 \
    "the run wrote no $LOG, so the probe never ran." \
    "Is DoorPickProbe still called from Game::Play (src/Main.cpp)?"
python3 tools/check_door_probe.py pick "$LOG"
RC=$?
echo
case "$RC" in
    0) echo "PASS: lock-picking and kicking follow the settled design" ;;
    1) echo "FAIL: lock-picking or kicking departs from the settled design (inc-h22n points 2, 3)" ;;
    *) echo "INCONCLUSIVE: the probe could not measure everything; read the lines above" ;;
esac
exit "$RC"
