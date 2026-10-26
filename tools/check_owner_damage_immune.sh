#!/bin/bash
# gate: live
# inc-nm59: an item immune to a damage type must stay unhurt when its OWNER
# damages it. Item::Hardness returns -1 as an immunity sentinel; Item::Damage's
# "attacking your own items" block (src/Item.cpp) used to set hard = 0 before
# the immunity test, so an immune item took full damage from its owner. An
# ordinary item must still lose the FULL vDmg from its owner (hardness ignored).
# THE ORACLE. src/OwnerDamageProbe.cpp gives the loaded player a viewing lens
# (glass: MaterialHardness(MAT_GLASS, AD_ACID) is -1) and a long sword (iron:
# acid hardness above 0), then calls ThrowDmg(EV_DAMAGE, AD_ACID, 5, ..., player,
# item) on each. It writes OWNER_DMG_PROBE lines to errors.log.
# fact: character -- fixture xsummon-priest-seed5-opt0822.sav (INCURSION_LOAD)
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: items -- probe creates both itself with Item::Create; no map item read
# fact: damage amount and type -- constants in the probe (5, AD_ACID); EActor=owner
# fact: hardness of lens and sword -- MaterialHardness; the probe prints each
# fact: key script -- bane-radius.keys only reaches Game::Play; the probe runs there
# RED (fix reverted, `&& hard >= 0` removed from the owner block, rebuilt):
#   role=immune item=viewing lens hardness=-1 vDmg=5 hp_before=1 hp_after=0 gone=1 lost=1
#   OWNER_DMG_PROBE: FAIL immune item HP unchanged   (exit 1)
# GREEN (fix in place):
#   role=immune item=viewing lens hardness=-1 vDmg=5 hp_before=1 hp_after=1 gone=0 lost=0
#   OWNER_DMG_PROBE: PASS immune item HP unchanged
#   role=ordinary item=long sword hardness=10 vDmg=5 hp_before=15 hp_after=10 gone=0 lost=5
#   OWNER_DMG_PROBE: ALL PASS   (exit 0)
# Exit 0 pass, 1 fail, 2 could not measure.
# Usage: tools/check_owner_damage_immune.sh
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

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-owner-dmg"
INCURSION_OWNER_DAMAGE_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" >/dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
lines=""
[ -s "$log" ] && lines="$(grep 'OWNER_DMG_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "UNMEASURED: no OWNER_DMG_PROBE lines in $log. Is OwnerDamageProbe still called from Game::Play?"
    exit 2
fi

echo "$lines"
echo "Specimen: $log"

if grep -q 'INCONCLUSIVE' <<< "$lines"; then
    echo "UNMEASURED: the probe could not set up its items."
    exit 2
fi
if [ "$(grep -c 'role=' <<< "$lines")" -ne 2 ]; then
    echo "UNMEASURED: want two role= lines."
    exit 2
fi
if grep -q 'OWNER_DMG_PROBE: FAIL' <<< "$lines"; then
    echo "FAIL: an owner-damage case failed."
    exit 1
fi
if ! grep -q 'OWNER_DMG_PROBE: ALL PASS' <<< "$lines"; then
    echo "UNMEASURED: no ALL PASS line."
    exit 2
fi
echo "PASS: immune item unhurt by its owner; ordinary item lost the full vDmg."
exit 0
