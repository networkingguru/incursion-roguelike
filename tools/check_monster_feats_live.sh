#!/bin/bash
# gate: live
# inc-4trf: the monster feat changes from phase A must hold in a live game.
# Runs src/MonsterFeatProbe.cpp (INCURSION_MONSTER_FEAT_PROBE) and asserts:
#   - each Dash monster (cheetah, juvenile arrowhawk, plague of rats, scarab
#     swarm) has dash=1 and a larger mov with Dash on than with Dash off;
#   - the cave tyrannosaurus has tracking=15, and hit_brawl with Weapon Focus
#     on is the Weapon Focus off value plus 1;
#   - the medium fire elemental has finesse=1;
#   - the water genasi template lists no FT_MASTER_THROW in its Feats: line;
#   - Persuasive (the vampire template) adds +2 Bluff and +2 Intimidate to a
#     human built under it, and sets persuasive=1 only with the feat on;
#   - Great Blow: Murgash and the malebranche are offered A_GREA only with the
#     feat on (offered=1), resolve it (resolved=1), and are never offered it off.
# Off-and-on pairs compare one creature with itself, so a value that varies
# between creatures cannot make the check fail.
#
# Facts and their controls (this check reads only what the header names):
#   # fact: character and the map under him -- fixture xsummon-priest-seed5-opt0822.sav
#   # fact: monster placement on open floor -- the loaded map (the probe finds the first open square)
#   # fact: the probe runs in a live map -- INCURSION_MONSTER_FEAT_PROBE hook in Game::Play
#   # fact: monster feats, tracking, finesse -- lib/ template data, no roll read
#   # fact: Dash and Weapon Focus toggles -- the probe edits the template feat list and restores it
#   # fact: water genasi Feats: line -- lib/mon2.irh source text
#   # fact: Persuasive Bluff and Intimidate -- lib/mon3.irh vampire template feat list, toggled by the probe
#   # fact: victim beside a huge malebranche -- the probe's own square search (a huge actor's footprint is not a blocker)
#   # fact: Great Blow 25% AI roll -- INCURSION_GREAT_BLOW_FORCE=1 (set on the run below)
# Known: the run exits 5 (NO GAMEPLAY) with tools/keys/monster-feats-live.keys,
# so exit 5 is accepted here when the probe's DONE line is present.
#
# Usage: tools/check_monster_feats_live.sh
# Specimens: logs/monster-feats/run-<timestamp>-<pid>/ and its .out file.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
mkdir -p logs/monster-feats
run="logs/monster-feats/run-$(date +%Y%m%d-%H%M%S)-$$"
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav \
INCURSION_MONSTER_FEAT_PROBE=1 \
INCURSION_GREAT_BLOW_FORCE=1 \
INCURSION_RUN_DIR="$run" tools/headless.sh tools/keys/monster-feats-live.keys 1 > "$run.out" 2>&1
status=$?
echo "headless exit: $status; specimens: $run (report: $run.out)"

log="$run/logs/errors.log"
[ -f "$log" ] || { echo "INCONCLUSIVE: no errors.log at $log"; exit 1; }
if [ "$status" -ne 0 ] && [ "$status" -ne 5 ]; then
  echo "FAIL: headless exited $status (not 0 or the known 5)."; exit 1
fi
grep -qF "MONSTER_FEAT DONE" "$log" || { echo "INCONCLUSIVE: the probe never reached DONE."; exit 1; }

# feat_line NAME TAG: the last MONSTER_FEAT line for that name and tag.
feat_line() { grep -F "MONSTER_FEAT name=$1 tag=$2 " "$log" | tail -1; }
# field LINE KEY: the integer value of KEY=n in LINE.
field() { echo "$1" | grep -oE " $2=-?[0-9]+" | head -1 | cut -d= -f2; }

fail=0
for name in "cheetah" "juvenile arrowhawk" "plague of rats" "scarab swarm"; do
  on="$(feat_line "$name" dash-on)"; off="$(feat_line "$name" dash-off)"
  if [ -z "$on" ] || [ -z "$off" ]; then
    echo "INCONCLUSIVE: no dash-on/dash-off line for $name."; fail=1; continue
  fi
  if [ "$(field "$on" dash)" != 1 ]; then
    echo "FAIL: $name has no Dash feat with Dash on: $on"; fail=1
  elif [ "$(field "$on" mov)" -le "$(field "$off" mov)" ]; then
    echo "FAIL: $name Dash on does not raise mov: on=$(field "$on" mov) off=$(field "$off" mov)"; fail=1
  else
    echo "PASS: $name Dash on mov $(field "$on" mov) > off $(field "$off" mov)"
  fi
done

tyr_off="$(feat_line "cave tyrannosaurus" focus-off)"
tyr_on="$(feat_line "cave tyrannosaurus" focus-on)"
tyr_base="$(feat_line "cave tyrannosaurus" base)"
if [ -z "$tyr_off" ] || [ -z "$tyr_on" ] || [ -z "$tyr_base" ]; then
  echo "INCONCLUSIVE: no cave tyrannosaurus focus lines."; fail=1
else
  if [ "$(field "$tyr_base" tracking)" != 15 ]; then
    echo "FAIL: cave tyrannosaurus tracking is $(field "$tyr_base" tracking), not 15"; fail=1
  fi
  if [ "$(field "$tyr_on" hit_brawl)" -ne $(( $(field "$tyr_off" hit_brawl) + 1 )) ]; then
    echo "FAIL: cave tyrannosaurus hit_brawl with Focus on is $(field "$tyr_on" hit_brawl), not off+1 ($(field "$tyr_off" hit_brawl)+1)"; fail=1
  else
    echo "PASS: cave tyrannosaurus Focus adds 1 to hit_brawl ($(field "$tyr_off" hit_brawl) -> $(field "$tyr_on" hit_brawl))"
  fi
fi

fire="$(feat_line "medium fire elemental" base)"
if [ -z "$fire" ]; then
  echo "INCONCLUSIVE: no medium fire elemental line."; fail=1
elif [ "$(field "$fire" finesse)" != 1 ]; then
  echo "FAIL: medium fire elemental finesse is $(field "$fire" finesse), not 1"; fail=1
else
  echo "PASS: medium fire elemental has Weapon Finesse"
fi

# The genasi block in lib/mon2.irh: its Feats: line must not name FT_MASTER_THROW.
genasi="$(awk '/^Monster "water genasi"/{on=1; next} on && /^Monster /{exit} on && /^ *Feats:/{print}' lib/mon2.irh)"
if [ -z "$genasi" ]; then
  echo "INCONCLUSIVE: no Feats: line found in the water genasi block."; fail=1
elif grep -q "FT_MASTER_THROW" <<< "$genasi"; then
  echo "FAIL: water genasi Feats: still lists FT_MASTER_THROW: $genasi"; fail=1
else
  echo "PASS: water genasi Feats: does not list FT_MASTER_THROW"
fi

pb_off="$(grep -F "MONSTER_FEAT_SKILL name=vampire human tag=persuasive-off " "$log" | tail -1)"
pb_on="$(grep -F "MONSTER_FEAT_SKILL name=vampire human tag=persuasive-on " "$log" | tail -1)"
if [ -z "$pb_off" ] || [ -z "$pb_on" ]; then
  echo "INCONCLUSIVE: no persuasive-off/on lines for vampire human."; fail=1
else
  if [ "$(field "$pb_off" persuasive)" != 0 ] || [ "$(field "$pb_on" persuasive)" != 1 ]; then
    echo "FAIL: vampire human (vampire template) Persuasive flag off/on is $(field "$pb_off" persuasive)/$(field "$pb_on" persuasive), not 0/1"; fail=1
  elif [ "$(field "$pb_on" bluff)" -ne $(( $(field "$pb_off" bluff) + 2 )) ] ||
       [ "$(field "$pb_on" intimidate)" -ne $(( $(field "$pb_off" intimidate) + 2 )) ]; then
    echo "FAIL: Persuasive does not add +2 Bluff and +2 Intimidate: $pb_off | $pb_on"; fail=1
  else
    echo "PASS: Persuasive adds +2 Bluff ($(field "$pb_off" bluff) -> $(field "$pb_on" bluff)) and +2 Intimidate ($(field "$pb_off" intimidate) -> $(field "$pb_on" intimidate))"
  fi
fi

# great_blow NAME: the greatblow-on line and greatblow-off line for NAME.
for name in "Murgash, the Goblin King" "malebranche"; do
  gon="$(grep -F "MONSTER_FEAT_GREATBLOW name=$name tag=greatblow-on " "$log" | tail -1)"
  goff="$(grep -F "MONSTER_FEAT_GREATBLOW name=$name tag=greatblow-off " "$log" | tail -1)"
  if [ -z "$gon" ] || [ -z "$goff" ]; then
    echo "INCONCLUSIVE: no greatblow-on/off lines for $name."; fail=1; continue
  fi
  if [ "$(field "$gon" offered)" != 1 ] || [ "$(field "$goff" offered)" != 0 ]; then
    echo "FAIL: $name Great Blow offered on/off is $(field "$gon" offered)/$(field "$goff" offered), not 1/0"; fail=1
  elif [ "$(field "$gon" resolved)" != 1 ]; then
    echo "FAIL: $name Great Blow does not resolve with the feat on: $gon"; fail=1
  else
    echo "PASS: $name Great Blow offered with the feat on, resolves"
  fi
done

[ "$fail" -eq 0 ] && echo "RESULT: PASS (inc-4trf)" || echo "RESULT: FAIL (inc-4trf)"
exit "$fail"
