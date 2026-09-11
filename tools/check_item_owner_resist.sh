#!/bin/bash
# gate: cheap
# Gear inherits the blanket gear-only defences and otherwise only flagged
# grants and the two divine feats.
# Static Tier 1 (inc-w26h): clean(), function-scoped Python measurements.
# Item::Damage uses its own hardness, one GearResistLevel call, an immunity
# return, and nonnegative-hardness-guarded addition; no bare ResistLevel calls.
# The ORDER is pinned too (inc-kapn): the grant is added AFTER e.ignoreHardness
# and e.halfHardness have acted, because those two speak about the MATERIAL and
# a magical protection must survive them. tools/check_gear_bypass_survives.sh
# is the same rule measured in play.
# GearResistLevel admits exactly the four gear-only types AD_SOAK/AD_RUST/
# AD_DCAY/AD_SHAT, flag-tests both status loops, and takes the max of the
# DivineFeatResist grant, whose body ResistLevel shares and still stacks.
# Usage: tools/check_item_owner_resist.sh [--root SCRATCH_ROOT]
#        tools/check_item_owner_resist.sh --prove-red [--mutation flag|divine|order]
# Exit: 0 pass, 1 rule violated, 2 could not measure.
# Measured after the four-type, divine-feat and bypass-order rulings (2026-09-11):
# PASS: Item::Damage hardness initialization=1/1; ResistLevel calls=0/0; GearResistLevel calls=1/1; immunity return, bypass order and guarded addition=1/1
# PASS: GearResistLevel blanket types=AD_DCAY,AD_RUST,AD_SHAT,AD_SOAK; expected=AD_DCAY,AD_RUST,AD_SHAT,AD_SOAK
# PASS: GearResistLevel flag-guarded status loops=2/2
# PASS: DivineFeatResist grants=intact; ResistLevel stacks it=1/1; GearResistLevel takes its max=1/1
# PROVED RED (2026-09-11), delete AD_RUST from blanket test:
#   | FAIL: GearResistLevel blanket types=AD_DCAY,AD_SHAT,AD_SOAK; expected=AD_DCAY,AD_RUST,AD_SHAT,AD_SOAK
# PROVED RED: with src/Values.cpp mutated, this check exits 1.
# PROVED RED (2026-09-11), delete the IMMUNITY loop flag test:
#   | FAIL: GearResistLevel flag-guarded status loops=1/2
# PROVED RED: with src/Values.cpp mutated, this check exits 1.
# PROVED RED (2026-09-11), delete the divine grant from GearResistLevel:
#   | FAIL: DivineFeatResist grants=intact; ResistLevel stacks it=1/1; GearResistLevel takes its max=0/1
# PROVED RED: with src/Values.cpp mutated, this check exits 1.
# PROVED RED (2026-09-11), --mutation order, the addition moved back above the
# ignoreHardness/halfHardness block:
#   | FAIL: Item::Damage hardness initialization=1/1; ResistLevel calls=0/0; GearResistLevel calls=1/1; immunity return, bypass order and guarded addition=0/1
# PROVED RED: with src/Item.cpp mutated, this check exits 1.
# Also measured 2026-09-11, each against a scratch copy of the tree: the rule
# still reports 0/1 when the GearResistLevel call, the immunity return, the
# nonnegative guard on the addition, or the zero initialiser of gear is deleted.
. "$(dirname "$0")/check_lib.sh"
# Pure source oracle: no mutation here needs a binary rebuild.
CHECK_TARGETS=""
mutation=blanket
args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --prove-red) shift ;;
        --mutation)
            [ "$#" -ge 2 ] || _check_die 2 "--mutation needs blanket, flag, divine or order"
            mutation="$2"; shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
case "$mutation" in
    blanket)
        check_mutation src/Values.cpp \
'if (DType == AD_SOAK || DType == AD_RUST ||
        DType == AD_DCAY || DType == AD_SHAT)' \
'if (DType == AD_SOAK ||
        DType == AD_DCAY || DType == AD_SHAT)' ;;
    flag)
        check_mutation src/Values.cpp \
'RES(S->eID)->Type == T_TEFFECT &&
          TEFF(S->eID)->HasFlag(EF_PROTECTS_ITEMS))
        immune = true;' \
'RES(S->eID)->Type == T_TEFFECT)
        immune = true;' ;;
    divine)
        check_mutation src/Values.cpp \
'    if (DivineFeatResist(this,DType,divine))
      best = max(best,divine);
' \
'' ;;
    order)
        # Restore the old ordering: perform the addition ABOVE the bypass
        # block, and empty gear so the statement below it becomes a no-op.
        # That is exactly what the tree did before inc-kapn, and it is what
        # threw a resistance away with the metal's own hardness.
        check_mutation src/Item.cpp \
'        if (hard >= 0) {
            if (e.ignoreHardness == true)' \
'        if (hard >= 0) {
            hard += gear; gear = 0;
            if (e.ignoreHardness == true)' ;;
    *) _check_die 2 "unknown mutation: $mutation" ;;
esac
command -v python3 >/dev/null || { echo "COULD NOT MEASURE: python3 missing"; exit 2; }
exec python3 tools/equipment_static.py item_owner_resist "${args[@]+"${args[@]}"}"
