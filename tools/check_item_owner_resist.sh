#!/bin/bash
# Gear inherits blanket soak/rust defences and otherwise only flagged grants.
# Static Tier 1 (inc-w26h): clean(), function-scoped Python measurements.
# Item::Damage uses its own hardness, one GearResistLevel call, an immunity
# return, and nonnegative-hardness-guarded addition; no bare ResistLevel calls.
# GearResistLevel admits exactly AD_SOAK/AD_RUST and flag-tests both loops.
# Usage: tools/check_item_owner_resist.sh [--root SCRATCH_ROOT]
#        tools/check_item_owner_resist.sh --prove-red [--mutation flag]
# Exit: 0 pass, 1 rule violated, 2 could not measure.
# Measured before registration (2026-09-10):
# PASS: Item::Damage hardness initialization=1/1; ResistLevel calls=0/0; GearResistLevel calls=1/1; immunity return and guarded addition=1/1
# PASS: GearResistLevel blanket types=AD_RUST,AD_SOAK; expected=AD_RUST,AD_SOAK
# PASS: GearResistLevel flag-guarded status loops=2/2
# PROVED RED (2026-09-10), delete AD_RUST from blanket test:
#   | FAIL: GearResistLevel blanket types=AD_SOAK; expected=AD_RUST,AD_SOAK
# PROVED RED: with src/Values.cpp mutated, this check exits 1.
# PROVED RED (2026-09-10), delete the IMMUNITY loop flag test:
#   | FAIL: GearResistLevel flag-guarded status loops=1/2
# PROVED RED: with src/Values.cpp mutated, this check exits 1.
. "$(dirname "$0")/check_lib.sh"
# Pure source oracle: neither mutation needs a binary rebuild.
CHECK_TARGETS=""
mutation=blanket
args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --prove-red) shift ;;
        --mutation)
            [ "$#" -ge 2 ] || _check_die 2 "--mutation needs blanket or flag"
            mutation="$2"; shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
case "$mutation" in
    blanket)
        check_mutation src/Values.cpp \
            'if (DType == AD_SOAK || DType == AD_RUST)' \
            'if (DType == AD_SOAK)' ;;
    flag)
        check_mutation src/Values.cpp \
'RES(S->eID)->Type == T_TEFFECT &&
          TEFF(S->eID)->HasFlag(EF_PROTECTS_ITEMS))
        immune = true;' \
'RES(S->eID)->Type == T_TEFFECT)
        immune = true;' ;;
    *) _check_die 2 "unknown mutation: $mutation" ;;
esac
command -v python3 >/dev/null || { echo "COULD NOT MEASURE: python3 missing"; exit 2; }
exec python3 tools/equipment_static.py item_owner_resist "${args[@]+"${args[@]}"}"
