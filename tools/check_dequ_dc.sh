#!/bin/bash
# gate: cheap
# Only the four named SRD A_DEQU monsters retain DCs (inc-m2zi AC8).
# Static Tier 1: Python 3 only; no binary, compiler, build or game run.
# WHY: a quiet reversion of the equipment rules must fail independently of gameplay.
# Measures function-scoped code (or the named monster roster), not comments.
# Structural rewrites require oracle review; this is static evidence, not gameplay.
# Usage: tools/check_dequ_dc.sh [--root SCRATCH_ROOT]
# Exit: 0 pass, 1 rule violated, 2 could not measure.
# Measured before registration (2026-09-10):
# PASS: A_DEQU monsters=13/13; DC tokens=4/4; incorrect DC owners=none; roster=expected
# Scratch reversion: A_DEQU for 1d3 AD_FIRE, -> A_DEQU for 1d3 AD_FIRE (DC 15),
# RED exit 1, exact stdout:
# FAIL: A_DEQU monsters=13/13; DC tokens=5/4; incorrect DC owners=firebat; roster=expected
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2
command -v python3 >/dev/null || { echo "COULD NOT MEASURE: python3 missing"; exit 2; }
exec python3 tools/equipment_static.py dequ_dc "$@"
