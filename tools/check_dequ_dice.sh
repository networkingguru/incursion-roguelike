#!/bin/bash
# gate: cheap
# Declared A_DEQU dice must roll without tripling (inc-m2zi AC8).
# Static Tier 1: Python 3 only; no binary, compiler, build or game run.
# WHY: a quiet reversion of the equipment rules must fail independently of gameplay.
# Measures function-scoped code (or the named monster roster), not comments.
# Structural rewrites require oracle review; this is static evidence, not gameplay.
# Usage: tools/check_dequ_dice.sh [--root SCRATCH_ROOT]
# Exit: 0 pass, 1 rule violated, 2 could not measure.
# Measured before registration (2026-09-10):
# PASS: A_DEQU declared-dice immediate rolls=2/2; dice writes=2/2
# Scratch reversion: e2.Dmg    = ta->u.a.Dmg; -> e2.Dmg    = ta->u.a.Dmg; e2.Dmg.Number *= 3; e2.Dmg.Bonus *= 3;
# RED exit 1, exact stdout:
# FAIL: A_DEQU declared-dice immediate rolls=0/2; dice writes=6/2
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2
command -v python3 >/dev/null || { echo "COULD NOT MEASURE: python3 missing"; exit 2; }
exec python3 tools/equipment_static.py dequ_dice "$@"
