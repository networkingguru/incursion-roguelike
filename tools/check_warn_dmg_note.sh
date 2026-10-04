#!/bin/bash
# inc-1xr3 phase 2i reproduction: damage warnings name their per-step damage.
#
# Source-level check (no gameplay observation). It asserts:
#   (1) each terrain that deals damage on a warning declares WARN_DMG_* in its
#       own Constants block, and its handler rolls/uses those same values;
#   (2) TerrainRiskNote reads WARN_DMG_NUM/SIDES/BONUS/TYPE;
#   (3) magma is 6d6 fire; acid fog is 1d6 acid; bed of spikes is 1d8 piercing;
#       thorn wall is a flat 25 slashing bonus.
#
# Exits 0 on pass, 1 on fail, 2 if it cannot measure.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

D=lib/dungeon.irh
C=src/Creature.cpp
[ -f "$D" ] && [ -f "$C" ] || { echo "COULD NOT MEASURE: missing $D or $C"; exit 2; }

fail=0
note() { printf 'FAIL: %s\n' "$1"; fail=1; }

# (2) the note reads every damage constant.
grep -q 'res->GetConst(WARN_DMG_NUM)' "$C"   || note "Creature.cpp: note omits WARN_DMG_NUM"
grep -q 'res->GetConst(WARN_DMG_SIDES)' "$C" || note "Creature.cpp: note omits WARN_DMG_SIDES"
grep -q 'res->GetConst(WARN_DMG_BONUS)' "$C" || note "Creature.cpp: note omits WARN_DMG_BONUS"
grep -q 'res->GetConst(WARN_DMG_TYPE)' "$C"  || note "Creature.cpp: note omits WARN_DMG_TYPE"

# (2b) the note must show the map square's dice, never one random sample:
# it must call GetTerraDice and must never call GetTerraDmg.
grep -q 'map->GetTerraDice(x, y)' "$C" || note "Creature.cpp: note does not call Map::GetTerraDice"
grep -q 'GetTerraDmg' "$C" && note "Creature.cpp: note still calls Map::GetTerraDmg (must use GetTerraDice)"

# (1)+(3) magma: 6d6 fire, handler rolls from the constants.
magma_consts=$(awk '/^Terrain "magma"/,/Desc:/' "$D")
echo "$magma_consts" | grep -q 'WARN_DMG_NUM 6'   || note "magma: no WARN_DMG_NUM 6"
echo "$magma_consts" | grep -q 'WARN_DMG_SIDES 6' || note "magma: no WARN_DMG_SIDES 6"
echo "$magma_consts" | grep -q 'WARN_DMG_TYPE AD_FIRE' || note "magma: no AD_FIRE type"
grep -q 'dn = $"magma"->GetConst(WARN_DMG_NUM)' "$D" || note "magma: handler does not read WARN_DMG_NUM"
grep -q 'dmg = (dn)d(ds) - r;' "$D" || note "magma: handler does not roll from the constants"

# acid fog: 1d6 acid, handler rolls from the constants.
acid_consts=$(awk '/^Terrain "acid fog"/,/On Event EV_MON_CONSIDER/' "$D")
echo "$acid_consts" | grep -q 'WARN_DMG_NUM 1'    || note "acid fog: no WARN_DMG_NUM 1"
echo "$acid_consts" | grep -q 'WARN_DMG_SIDES 6'  || note "acid fog: no WARN_DMG_SIDES 6"
echo "$acid_consts" | grep -q 'WARN_DMG_TYPE AD_ACID' || note "acid fog: no AD_ACID type"
grep -q 'dn = $"acid fog"->GetConst(WARN_DMG_NUM)' "$D" || note "acid fog: handler does not read WARN_DMG_NUM"
grep -q '(dn)d(ds),"acid fog"' "$D" || note "acid fog: handler does not roll from the constants"

# bed of spikes: 1d8 piercing, handler rolls from the constants.
spikes_consts=$(awk '/^Terrain "bed of spikes"/,/EV_MON_CONSIDER/' "$D")
echo "$spikes_consts" | grep -q 'WARN_DMG_NUM 1'    || note "bed of spikes: no WARN_DMG_NUM 1"
echo "$spikes_consts" | grep -q 'WARN_DMG_SIDES 8'  || note "bed of spikes: no WARN_DMG_SIDES 8"
echo "$spikes_consts" | grep -q 'WARN_DMG_TYPE AD_PIERCE' || note "bed of spikes: no AD_PIERCE type"
grep -q '(dn)d(ds),"a bed of spikes"' "$D" || note "bed of spikes: handler does not roll from the constants"

# thorn wall: flat 25 slashing, handler uses the constant.
thorn_consts=$(awk '/^Terrain "thorn wall"/,/WARN_DMG_TYPE/' "$D")
echo "$thorn_consts" | grep -q 'WARN_DMG_BONUS 25'   || note "thorn wall: no WARN_DMG_BONUS 25"
echo "$thorn_consts" | grep -q 'WARN_DMG_TYPE AD_SLASH' || note "thorn wall: no AD_SLASH type"
grep -q 'dmg = $"thorn wall"->GetConst(WARN_DMG_BONUS);' "$D" || note "thorn wall: handler does not read WARN_DMG_BONUS"
grep -q 'AD_SLASH,dmg,"a wall of thorns"' "$D" || note "thorn wall: handler does not use the constant"

# (3) the terrains that must NOT have changed keep their literal/runtime shape.
grep -q 'EMap->GetTerraDmg(e.EXVal,e.EYVal)' lib/wspells.irh \
    || note "curtains: damage no longer from GetTerraDmg (unexpected change)"
# guardian runes (both terrains): inc-1xr3 declares the damage; no WARN_SAVE
# because the save type is random per effect; handlers read the damage constants.
for g in "guardian runes" "guardian runes;2"; do
    gc=$(awk -v t="Terrain \"$g\"" 'index($0,t)==1{f=1} f&&/EV_MON_CONSIDER/{exit} f' "$D")
    for c in 'WARN_DMG_NUM 1' 'WARN_DMG_SIDES 6' 'WARN_DMG_BONUS 5'; do
        echo "$gc" | grep -q "$c" || note "$g: no $c"
    done
    echo "$gc" | grep -q '^ *\* WARN_SAVE ' && note "$g: declares WARN_SAVE (save type is random)"
    grep -qF "\$\"$g\"->GetConst(WARN_DMG_BONUS)" "$D" || note "$g: handler does not read WARN_DMG_BONUS"
done
grep -q 'EMap->GetTerraDmg(e.EXVal,e.EYVal)' lib/wspells.irh \
    || note "strange rune: GetTerraDmg shape changed"

if [ "$fail" -eq 0 ]; then
    echo "PASS: warning damage is declared by each terrain and read by its handler and note"
fi
exit "$fail"
