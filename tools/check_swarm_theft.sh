#!/bin/bash
# gate: live
# inc-67gh: plague of monkeys CR, one theft per turn, and opposed defense.
# fact: Warrior stats/kit/world -- alignment-drain-warrior frozen fixture and sheet
# fact: positive Pick Pockets defense -- skill-by-name-seed1-opt0818, the built fixture (INCURSION_LOAD path form, served from the fixture cache) and its sheet (tools/fixture_sheet.sh, read by tools/swarm_theft_results.py)
# fact: swarm position and identity -- wizard Monster Summoning after Genocide Everything
# fact: CR and resolver kind -- INCURSION_SWARM_THEFT_PROBE observes live code
# fact: eligible adjacent enemies -- probe count; fewer than 3 two-enemy turns is exit 2
# fact: second enemy stays adjacent -- caryatid column (Mov 0%) summoned beside the swarm; probe count is the control
# fact: attempts per turn -- invariant for every roll; d20 values never asserted
# fact: damage/AI cannot invalidate an assertion -- survival/adjacency controls, exit 2
# fact: bonus components -- independently parsed frozen sheet; no random total asserted
# fact: names/text -- wizard resource choices and literal probe fields
# fact: ordinary thief hit/save/damage -- INCURSION_LOF_FORCE_ROLL=20, INCURSION_FORCE_SAVE_ROLL=20, INCURSION_FORCE_DAMAGE_ROLL=1
# fact: recovery acquisition -- INCURSION_FORCE_SAVE_ROLL=1; missing transfer is exit 2
# fact: recovery skill roll -- INCURSION_RUNTO_SKILL_ROLL=20
# fact: recovery item -- observed theft transfer handle, never random item identity
# fact: warrior victim (warrior, crowd, mundane) -- the base character quality-item-magic-seed5-opt0822 (built from its .char) under tools/keys/setup-alignment-drain-warrior.keys (Warrior 5, 10000 XP, level cleared); its sheet is the one the setup run `sheet` writes (INCURSION_CHAR_PROBE), read by tools/swarm_theft_results.py
# Each scenario owns a run directory. No build and no seed-dependent verdict.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
base="logs/swarm-theft/check-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$base"
# The warrior's sheet after the derivation: one run of the setup alone, saved, so INCURSION_CHAR_PROBE writes its sheet.
INCURSION_CHAR_PROBE=1 INCURSION_LOAD=quality-item-magic-seed5-opt0822 INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
  INCURSION_RUN_DIR="$base/sheet" tools/headless.sh tools/keys/swarm-theft-sheet.keys 1 > "$base/sheet.out" 2>&1
for scenario in warrior crowd defense mundane recovery; do
    fixture=quality-item-magic-seed5-opt0822   # the base character; the key scripts include setup-alignment-drain-warrior.keys
    keys=tools/keys/swarm-theft.keys
    save_roll=0
    hit_roll=0
    case "$scenario" in
      warrior) keys=tools/keys/swarm-theft-warrior.keys ;;
      crowd) keys=tools/keys/swarm-theft-crowd.keys ;;
      defense) fixture=skill-by-name-seed1-opt0818 ;;
      mundane) keys=tools/keys/swarm-theft-mundane.keys; save_roll=20; hit_roll=20 ;;
      recovery) save_roll=1; fixture=skill-by-name-seed1-opt0818; keys=tools/keys/swarm-theft-recovery.keys ;;
    esac
    load="$fixture"
    [ -f "tools/fixtures/chars/$fixture.char" ] || { echo "INCONCLUSIVE: no tools/fixtures/chars/$fixture.char"; exit 2; }
    if [ ! -f "$keys" ]; then
        echo "INCONCLUSIVE: missing $keys"; exit 2
    fi
    INCURSION_FORCE_SAVE_ROLL="$save_roll" INCURSION_LOF_FORCE_ROLL="$hit_roll" \
      INCURSION_FORCE_DAMAGE_ROLL=1 INCURSION_SWARM_THEFT_PROBE=1 INCURSION_RUNTO_SKILL_ROLL=20 \
      INCURSION_CHAR_PROBE=1 INCURSION_LOAD="$load" \
      INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
      INCURSION_RUN_DIR="$base/$scenario" tools/headless.sh "$keys" 1 \
      > "$base/$scenario.out" 2>&1
    echo "$?" > "$base/$scenario.exit"
done
python3 tools/swarm_theft_results.py "$base"
