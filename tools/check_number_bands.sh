#!/bin/bash
# gate: none static but needs a git repository and a band table; run via
#           .beads/hooks/pre-commit, not the gate
# Thin wrapper for the number-band check (inc-24cc). See
# tools/check_number_bands.py for the rules and docs/specs/2026-10-13-number-bands-brief.md
# for the spec.
#
#   tools/check_number_bands.sh [--staged|--tree] [--file <path>] [--selftest]
#
# Exit codes: 0 pass, 1 refused, 2 could not measure.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 -I "$SELF_DIR/check_number_bands.py" "$@"
