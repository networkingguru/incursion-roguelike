#!/bin/bash
# gate: cheap
# gate-fast: static, reads inc/Defines.h and the band table, under a second
#
# The fast set runs each check with NO arguments, but the number-band tree
# check needs "--tree". This wrapper is the one-argument bridge: it follows
# tools/fast_checks.sh's pattern (a tools/check_*.sh file carrying a
# "# gate-fast:" marker) and execs tools/check_number_bands.sh --tree.
#
# Exit codes: 0 pass, 1 refused (an in-scope duplicate), 2 could not measure.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SELF_DIR/check_number_bands.sh" --tree
