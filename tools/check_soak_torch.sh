#!/bin/bash
# gate: live
# inc-b2wd: a soak that HITS never drains or destroys a lit light; a failed
# Reflex save (DC 10 + damage) moves it to the pack, or to the floor with no
# pack, Age unchanged. A TERRAIN soak (isHit false) still drains Age by
# dmg*400/Quantity and destroys the light at Age <= 1. Measured live by
# SoakTorchProbe (src/SoakTorchProbe.cpp), eight cases:
#   1 hit soak, save fails, pack     2 hit soak, save fails, no pack
#   3 hit soak, save passes          4 DC is 10 + damage (boundary rolls)
#   5 re-light costs one wield       6 35-point hit soak never destroys
#   7 terrain soak drains/destroys   8 real water elemental slam rider
# fact: character -- fixture xsummon-priest-seed5-opt0822 (INCURSION_LOAD)
# fact: settings -- tools/fixtures/options-2026-08-22.dat (INCURSION_OPTIONS)
# fact: pack on the player -- the probe makes a medium backpack when absent; case 2 takes it off
# fact: the torch and its Age -- the probe creates it with Item::Create and sets Age 2500
# fact: the attacker -- the probe creates a tiny water elemental on an open adjacent square
# fact: an open square beside the player -- the probe checks and reports INCONCLUSIVE, never FAIL
# fact: the slam lands -- LOFSetForcedRoll(20) in the probe (nat 20 always hits)
# fact: the Reflex save outcome -- LOFSetForcedSaveThrowRoll(1|20|boundary) in the probe
# fact: soak damage -- the probe passes vDmg (3, 35, or Reflex bonus based for case 4)
# fact: Reflex bonus -- read by the probe with SaveBonus(REF), so no number is baked in
# fact: Timeout cost of a wield -- case 5 measures the relight against a normal wield
# fact: message text -- not matched
# FAIL, INCONCLUSIVE or missing results exit nonzero.
# Usage: tools/check_soak_torch.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/bane-radius.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-soak-torch"
INCURSION_SOAK_TORCH_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" >/dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. Is SoakTorchProbe still called from Game::Play()?"
    exit 1
fi

lines="$(grep 'SOAK_TORCH_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no SOAK_TORCH_PROBE lines."
    exit 1
fi

echo "$lines"
echo "Specimen: $log"

if grep -qE 'SOAK_TORCH_PROBE:.*(FAIL|INCONCLUSIVE)' <<< "$lines"; then
    echo "FAIL: at least one probe case failed or was inconclusive."
    exit 1
fi
# Cases 1-8 where case 7 has two lines: nine fact lines.
n="$(grep -c 'SOAK_TORCH_PROBE: case=' <<< "$lines")"
if [ "$n" -ne 9 ]; then
    echo "FAIL: measured $n case lines, want 9."
    exit 1
fi
if grep -q 'SOAK_TORCH_PROBE: case=[0-9] .* BAD ' <<< "$lines"; then
    echo "FAIL: a case line is BAD."
    exit 1
fi
if ! grep -q 'SOAK_TORCH_PROBE: PASS' <<< "$lines"; then
    echo "FAIL: missing PASS result."
    exit 1
fi

echo "PASS: a hit soak moves the lit torch and never drains it; a terrain soak still drains and destroys it (inc-b2wd)."
