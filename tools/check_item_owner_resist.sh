#!/bin/bash
# gate: cheap
# Owner resistance and immunity cannot protect equipment (inc-w26h).
# Static Tier 1: Python 3 only; no binary, compiler, build or game run.
# WHY: a quiet reversion of the equipment rules must fail independently of gameplay.
# Measures function-scoped code (or the named monster roster), not comments.
# Structural rewrites require oracle review; this is static evidence, not gameplay.
# Usage: tools/check_item_owner_resist.sh [--root SCRATCH_ROOT]
# Exit: 0 pass, 1 rule violated, 2 could not measure.
# Measured before registration (2026-09-10):
# PASS: Item::Damage own hardness and immunity=1/1; ResistLevel calls=0/0
# Scratch reversion: hard = Hardness(e.DType); -> if (owner && owner->ResistLevel(e.DType) == -1) return DONE;     hard = Hardness(e.DType);     if (owner && owner->ResistLevel(e.DType) == -1) return DONE;     if (owner) hard += owner->ResistLevel(e.DType);
# RED exit 1, exact stdout:
# FAIL: Item::Damage own hardness and immunity=1/1; ResistLevel calls=3/0
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2
command -v python3 >/dev/null || { echo "COULD NOT MEASURE: python3 missing"; exit 2; }
exec python3 tools/equipment_static.py item_owner_resist "$@"
