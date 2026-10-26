#!/bin/bash
# gate: live
# inc-8c3k: tracking-only perception permits pursuit, never ranged/spell attempts.
# fact: character and options -- orc-barbarian-seed1-opt0822 fixture, options-2026-08-22.dat
# fact: monster speed -- scratch Mov: 50%, ordinary AI and scheduling
# fact: isolated hostile monster -- wizard genocide; scratch-module CreateMonster/TurnHostileTo
# fact: terrain, positions and clear line of fire -- scratch-module open-floor arena; measured LineOfFire
# fact: tracking mark and perception -- scratch-module TRACKING(125); measured Perceives, exactly PER_TRACK
# fact: spell/ranged loadout -- scratch narzugon, only unholy blight (or unarmed control)
# fact: monster mana -- scratch Initialize(true), mMana = 75; GainMana before each wait, measured cMana
# fact: player stands still and survives -- wait-only keys; scratch HP restoration before each wait
# fact: monster AI choice -- none; invariant check, exits 2 when the path is not exercised
# fact: approach distance -- measured invariant exercise; exits 2 if no tracking-only shrink
# fact: attempted attacks -- PRE cast/invoke/ranged/special event observer, actor and player target/location matched
# fact: telemetry text -- literal scratch-module labels; spell name read from event resource
# Twenty eligible samples demand repeated opportunities, not one lucky quiet turn.
. "$(dirname "$0")/check_lib.sh"
CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav
variant=${TRACK_ONLY_VARIANT:-armed}
run="$CHECK_ROOT/logs/track-only/$variant-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$run/mod" "$run/save" "$run/logs"
cp -Rf lib "$run/lib"
ln -s "$CHECK_ROOT/inc" "$run/inc"
python3 tools/track_only_stage.py "$run" "$variant" || exit 2
INCURSIONPATH="$run/" ./incursion-headless -compile main.irc < /dev/null > "$run/compile.log" 2>&1
[ -f "$run/mod/Incursion.Mod" ] || { tail -15 "$run/compile.log"; exit 2; }
export INCURSION_RUN_DIR="$run"
check_run tools/keys/track-only-no-cast.keys 1
python3 tools/track_only_trace.py "$run" "$variant"
