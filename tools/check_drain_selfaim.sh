#!/bin/bash
# Regression check for inc-aocw: a monster's drain spell must not hit itself.
#
# Minor Drain and Major Drain are the only two effects in lib/ that carry
# EP_ATTACK and EP_FIX_TROUBLE (TROUBLE_INJURY) together. Each heals the
# caster for the damage it deals, so draining an ENEMY is a real remedy for an
# injury -- but the trouble code sits in the high word of Purpose, the plain
# attack slot's high word is zero, and the selector at src/Monster.cpp:1216
# demands the high words be equal. So a monster could reach either spell ONLY
# through the injury-remedy action, that action carries no target, and
# MagicEvent's "no victim and no coordinates" fallback aimed it at the caster.
# Every monster cast of either drain landed on the caster: it took the damage,
# healed the same amount, and spent a turn and its mana. The player was never
# the target, at any range.
#
# Measured 2026-09-09 on seed 4 with tools/keys/drain-selfaim.keys. One feyr,
# hurt once and then left alone out of sight, self-drained 120 times in thirty
# turns of waiting. After the fix it self-drains zero times.
#
# WHAT THE PROBE RECORDS, and why the last two fields decide it.
#
# INCURSION_SELFAIM_PROBE=1 writes one line per cast that reaches the fallback
# in src/Magic.cpp. The fallback itself is NOT the defect and MUST stay: it is
# how the AI cures itself, because Cure Light Wounds and its kin are Q_TAR
# with no AIM_AT_SELF bit and reach self-healing by exactly this route. The
# player trips it too, and his bolt still flies. What separates the harmless
# from the broken is isDir and isLoc: ABallBeamBolt takes its self-hit
# shortcut only when NEITHER is set. So the failing signature is the whole of
#
#     kind=monster ... attack=1 dir=0 loc=0
#
# and a line with attack=0, or with dir=1, is a healthy monster healing itself
# or a player aiming a spell.
#
# THE RUN CAN FAIL TO MEASURE ANYTHING, and that is INCONCLUSIVE rather than
# FAIL. A session that never summoned the feyr, or never landed the control
# cast, says nothing about the bug -- the mistake of inc-loa.3. The control
# cast is checked for that reason: the player's own Minor Drain must appear in
# the probe log, and must strike the feyr on screen.
#
# Usage: tools/check_drain_selfaim.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=4

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_SELFAIM_PROBE=1 INCURSION_OPTIONS=tools/gates/Options.Dat \
       tools/headless.sh tools/keys/drain-selfaim.keys "$SEED" 2>&1)"
status=$?
run="$(echo "$out" | awk '/^run:/ {print $2}')"
log="$run/logs/selfaimprobe.log"

# HOW THE SESSION ENDED IS PART OF THE MEASUREMENT. tools/headless.sh exits 0
# for a clean finish and 3 when the key script runs out, which is how this one
# ends. Every other code says the session stopped being a game: 1 FATAL, 4 the
# watchdog, 5 NO GAMEPLAY, 6 an @expect that found nothing, 7 an assertion the
# tree does not list. Without this test a session that crashed after the
# control cast still printed PASS, because the two lines the verdict reads
# were already in the probe log. That is inc-loa.3 again. See inc-mpw8.
if [ "$status" -ne 0 ] && [ "$status" -ne 3 ]; then
    echo "INCONCLUSIVE: the session ended badly (tools/headless.sh exit $status),"
    echo "              so nothing after that point is gameplay and the probe"
    echo "              log is not evidence about the fix."
    echo "$out" | sed -n '/^--- after the session ---/,$p' | sed 's/^/  /'
    exit 2
fi

[ -n "$run" ] && [ -f "$log" ] || {
    echo "INCONCLUSIVE: the session wrote no probe log, so no cast reached the"
    echo "              fallback at all. Run dir: ${run:-unknown}"
    exit 2
}

# The control: the player's own cast of the same spell.
control="$(grep -c 'kind=other .*effect=Minor Drain' "$log")"
[ "$control" -ge 1 ] || {
    echo "INCONCLUSIVE: the player never cast Minor Drain, so the fixture did"
    echo "              not reach the part of the session that matters."
    echo "              Run dir: $run"
    exit 2
}

# The defect: a monster casting an attack effect with neither a direction nor
# a location, which is the one combination ABallBeamBolt reads as "hit me".
bad="$(grep -c 'kind=monster .*attack=1 dir=0 loc=0' "$log")"

if [ "$bad" -gt 0 ]; then
    echo "FAIL: $bad monster cast(s) of an attack effect aimed at the caster."
    grep 'kind=monster .*attack=1 dir=0 loc=0' "$log" | sort | uniq -c | head
    echo "Run dir: $run"
    exit 1
fi

# Self-healing must still work. If the fallback stopped carrying benign
# traffic, something removed it rather than fixing the aim, and the AI can no
# longer cure itself.
benign="$(grep -F -- 'kind=monster ' "$log" | grep -cF -- ' attack=0 ')"
[ "$benign" -ge 1 ] || {
    echo "INCONCLUSIVE: no benign self-aimed cast was recorded either, so this"
    echo "              run cannot tell a fixed aim from a removed fallback."
    echo "              Run dir: $run"
    exit 2
}

echo "PASS: no monster aimed an attack effect at itself."
echo "      control casts by the player: $control; benign self-aims: $benign"
exit 0
