#!/bin/bash
# gate: cheap
# Literal __XPrint object tags must fit the supplied varargs (inc-upw.30).
# Static Tier 1: Python 3 only; no binary, compiler, build or game run.
# Usage: tools/check_xprint_tokens.sh [--root SCRATCH_ROOT] [--baseline|--prove-red]
# As with check_format_strings.sh, the known count lives in a baseline file:
# above it fails for new defects; below it fails until the baseline is lowered.
# Exit: 0 matches baseline, 1 new defects or stale baseline, 2 cannot measure.
# --prove-red lowers a scratch baseline by one and requires child exit 1.
# Runtime/macro formats and printf-inserted tags are outside this literal sweep.
# Measured --prove-red stdout (2026-09-11), outer exit 0, child exit 1:
# mutation: lower scratch baseline by 1
# xprint-token warnings: 18   baseline: 17
# FAIL: 1 xprint-token warning(s) above the baseline
# PASS: --prove-red observed exit 1
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2
command -v python3 >/dev/null || { echo "COULD NOT MEASURE: python3 missing"; exit 2; }
exec python3 tools/xprint_tokens.py "$@"
