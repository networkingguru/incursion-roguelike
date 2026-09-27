#!/bin/bash
# gate: live
# inc-glnx revision-4 sandbox-module persistence oracle.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 tools/script_vars_survive.py "$@"
