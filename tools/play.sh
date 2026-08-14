#!/bin/bash
# Play with the diagnostics that are worth having on during a real session.
#
# ON by default:
#   INCURSION_MAP_AUDIT  Checks the map against itself -- every Thing must
#                        appear both in m->Things[] and in the Contents chain
#                        of the square it claims. Runs every tenth turn and
#                        the instant Thing::Remove fails to unlink. This is
#                        the one that can turn inc-6d5 from a code-reading
#                        into an observation. -> logs/mapaudit.log
#   INCURSION_SAVE_PROBE Records the player's position either side of every
#                        save and load. Cheap, and the bug it watches for
#                        destroyed a set of save files once already.
#                        -> logs/saveprobe.log
#
# OFF by default, because it writes a line per drawn frame and buries
# everything else. Turn it on only when chasing a display fault:
#   tools/play.sh --map-probe        -> logs/mapprobe.log
#
# Also off: INCURSION_ERROR_PROMPT, which restores the old blocking error
# dialog. A single error used to freeze the game, so leave it alone unless
# you specifically want to stop the world on the next one.
#
# logs/errors.log rotates on the first error of each run: the previous one
# becomes logs/errors-YYYYMMDD-HHMMSS.log, ten sessions are kept.
#
# Usage: tools/play.sh [--map-probe] [args passed to ./incursion]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion ] || { echo "./incursion not built. Run ./build_macos.sh"; exit 1; }

export INCURSION_MAP_AUDIT=1
export INCURSION_SAVE_PROBE=1

if [ "${1:-}" = "--map-probe" ]; then
    export INCURSION_MAP_PROBE=1
    shift
    echo "map probe ON -- expect logs/mapprobe.log to grow fast"
fi

echo "diagnostics: map audit, save probe"
echo "logs:        $ROOT/logs/"
echo

./incursion "$@"
STATUS=$?

echo
echo "--- after the session ---"

# The audit log always carries a header when armed, so its absence means the
# switch did not take -- which is worth saying out loud rather than reading as
# a clean run.
if [ ! -f logs/mapaudit.log ]; then
    echo "map audit:  NO LOG. The audit never ran; the build may predate it."
elif [ "$(grep -vc '^=== map audit armed' logs/mapaudit.log)" = "0" ]; then
    echo "map audit:  armed, no inconsistencies found"
else
    echo "map audit:  FOUND SOMETHING --"
    grep -v '^=== map audit armed' logs/mapaudit.log | tail -20 | sed 's/^/  /'
fi

if [ -f logs/errors.log ]; then
    echo "errors:     $(grep -c '^[0-9]' logs/errors.log) logged, distinct messages:"
    grep '^[0-9]' logs/errors.log | sed 's/^[0-9-]* [0-9:]*  //' | sort | uniq -c |
        sort -rn | head -10 | sed 's/^/  /'
else
    echo "errors:     none"
fi

if [ -f logs/saveprobe.log ]; then
    echo "save probe: last lines --"
    tail -4 logs/saveprobe.log | sed 's/^/  /'
fi

exit $STATUS
