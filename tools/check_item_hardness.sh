#!/bin/bash
# gate: cheap
# Every Item gets modifiers once, after preserving immunity (inc-m2zi AC8).
# Static Tier 1: Python 3 only; no binary, compiler, build or game run.
# WHY: a quiet reversion of the equipment rules must fail independently of gameplay.
# Measures function-scoped code (or the named monster roster), not comments.
# Structural rewrites require oracle review; this is static evidence, not gameplay.
# Usage: tools/check_item_hardness.sh [--root SCRATCH_ROOT]
# Exit: 0 pass, 1 rule violated, 2 could not measure.
# Measured before registration (2026-09-10):
# PASS: Item arithmetic and preceding immunity guard=intact; QItem single delegation=1/1
# Scratch reversion: return Item::Hardness(DType); -> return Item::Hardness(DType) + GetPlus()*5;
# RED exit 1, exact stdout:
# FAIL: Item arithmetic and preceding immunity guard=intact; QItem single delegation=0/1
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2
command -v python3 >/dev/null || { echo "COULD NOT MEASURE: python3 missing"; exit 2; }
exec python3 tools/equipment_static.py item_hardness "$@"
