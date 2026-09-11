#!/bin/bash
# gate: cheap
# Ordinary combustible materials lose fire hardness; enchanted materials keep it (inc-m2zi AC8).
# Static Tier 1: Python 3 only; no binary, compiler, build or game run.
# WHY: a quiet reversion of the equipment rules must fail independently of gameplay.
# Measures function-scoped code (or the named monster roster), not comments.
# Structural rewrites require oracle review; this is static evidence, not gameplay.
# Usage: tools/check_fire_hardness.sh [--root SCRATCH_ROOT]
# Exit: 0 pass, 1 rule violated, 2 could not measure.
# Measured before registration (2026-09-10):
# PASS: MAT_WOOD fire hardness expected=0; rule=return(DType==AD_FIRE)?0:5;
# PASS: MAT_LEATHER fire hardness expected=0; rule=return(DType==AD_FIRE)?0:10;
# PASS: MAT_CLOTH fire hardness expected=0; rule=return(DType==AD_FIRE)?0:5;
# PASS: MAT_IRONWOOD fire hardness expected=10; rule=return10;
# PASS: MAT_DARKWOOD fire hardness expected=20; rule=return(DType==AD_FIRE)?20:15;
# PASS: MAT_DRAGON_HIDE fire hardness expected=15; rule=return15;
# Scratch reversion: return (DType == AD_FIRE) ? 0 : 5; -> return 5;
# RED exit 1, exact stdout:
# FAIL: MAT_WOOD fire hardness expected=0; rule=return5;
# PASS: MAT_LEATHER fire hardness expected=0; rule=return(DType==AD_FIRE)?0:10;
# FAIL: MAT_CLOTH fire hardness expected=0; rule=return5;
# PASS: MAT_IRONWOOD fire hardness expected=10; rule=return10;
# PASS: MAT_DARKWOOD fire hardness expected=20; rule=return(DType==AD_FIRE)?20:15;
# PASS: MAT_DRAGON_HIDE fire hardness expected=15; rule=return15;
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2
command -v python3 >/dev/null || { echo "COULD NOT MEASURE: python3 missing"; exit 2; }
exec python3 tools/equipment_static.py fire_hardness "$@"
