#!/bin/bash
# Print the path of a fixture's cached .sheet.txt, building the fixture first
# on a cache miss (bead inc-10v7f, spec A10). The lookup is tools/fixture_cache.sh;
# this script adds nothing to it. The sheet's first three lines are the cache's
# provenance header (a "# " line naming the key).
#
# Usage: tools/fixture_sheet.sh <name>
# Exit: 0 printed; otherwise the lookup's own code.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

if [ -z "${1:-}" ]; then
    echo "usage: tools/fixture_sheet.sh <name>" >&2
    exit 2
fi
SAV="$(tools/fixture_cache.sh "$1")" || exit $?
printf '%s\n' "${SAV%.sav}.sheet.txt"
