#!/bin/bash
# gate: live
# inc-dwfc: wrought and orcish iron must have a finite hardness. MaterialHardness
# (src/Item.cpp) had no MAT_WROUGHT case, so it fell to `return -1`, the
# immunity sentinel: every orcish or wrought item was immune to acid, fire,
# sonic and slashing, and the combat-numbers line printed "vs. Immune".
# THE ORACLE. src/WroughtHardnessProbe.cpp builds a wrought long sword
# (IQ_WROUGHT), an orcish long sword (IQ_ORCISH), a plain long sword and a
# viewing lens. It checks Material, then Hardness for acid, fire, sonic and
# slash; damages the wrought sword with 14 acid as a non-owner and reads the
# WIN_NUMBERS row the game drew. Wrought wants 10, orcish wants 5 (Item::Hardness
# halves it), plain iron 10, glass -1 to acid. Lines are WROUGHT_HARD_PROBE in
# errors.log.
# fact: character -- fixture xsummon-priest-seed5-opt0822.sav (INCURSION_LOAD)
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: items -- probe creates all four with Item::Create/AddQuality; no map item read
# fact: damage amount and type -- constants in the probe (14, AD_ACID); EActor=player, item on the floor so Owner() is NULL
# fact: hardness and combat line -- MaterialHardness; the probe prints each and the WIN_NUMBERS row
# fact: key script -- bane-radius.keys only reaches Game::Play; the probe runs there
# RED (fix absent, probe built; exit 1):
#   role=wrought material=34 acid=-1 fire=-1 soni=-1 slash=-1 want=10
#   role=orcish material=34 acid=-1 fire=-1 soni=-1 slash=-1 want=5
#   role=damage vDmg=14 hp_before=15 hp_after=15 gone=0 lost=0 want_lost=4
#   line=[? long sword: Residual Acid = 14 vs. Immune (wrought iron) [unhu
#   WROUGHT_HARD_PROBE: ALL FAIL
# GREEN (case MAT_WROUGHT added; exit 0):
#   role=wrought material=34 acid=10 fire=10 soni=10 slash=10 want=10
#   role=orcish material=34 acid=5 fire=5 soni=5 slash=5 want=5
#   role=iron-control material=11 acid=10 fire=10 soni=10 slash=10 want=10
#   role=glass-control acid=-1 want=-1
#   role=damage vDmg=14 hp_before=15 hp_after=11 gone=0 lost=4 want_lost=4
#   line=[? long sword: Residual Acid = 14 vs. 10 (wrought iron) [4 damage]
#   WROUGHT_HARD_PROBE: ALL PASS
# Exit 0 pass, 1 fail, 2 could not measure.
# Usage: tools/check_wrought_hardness.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

SEED=1
KEYS=tools/keys/bane-radius.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "UNMEASURED: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-wrought-hard"
INCURSION_WROUGHT_HARDNESS_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" >/dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
lines=""
[ -s "$log" ] && lines="$(grep 'WROUGHT_HARD_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "UNMEASURED: no WROUGHT_HARD_PROBE lines in $log. Is WroughtHardnessProbe still called from Game::Play?"
    exit 2
fi

echo "$lines"
echo "Specimen: $log"

if grep -q 'INCONCLUSIVE' <<< "$lines"; then
    echo "UNMEASURED: the probe could not set up its items."
    exit 2
fi
if [ "$(grep -c 'role=' <<< "$lines")" -ne 5 ]; then
    echo "UNMEASURED: want five role= lines."
    exit 2
fi
if grep -q 'WROUGHT_HARD_PROBE: ALL FAIL' <<< "$lines"; then
    echo "FAIL: a wrought or orcish item has the wrong hardness or the combat line says Immune."
    exit 1
fi
if ! grep -q 'WROUGHT_HARD_PROBE: ALL PASS' <<< "$lines"; then
    echo "UNMEASURED: no ALL PASS line."
    exit 2
fi
echo "PASS: wrought and orcish iron have finite hardness; glass is still immune to acid."
exit 0
