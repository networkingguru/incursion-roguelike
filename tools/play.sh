#!/bin/bash
# Play with the diagnostics that are worth having on during a real session.
#
# ON by default:
#   INCURSION_SAVE_PROBE Records the player's position either side of every
#                        save and load. Cheap, and the bug it watches for
#                        destroyed a set of save files once already.
#                        -> logs/saveprobe.log
#   INCURSION_CHAR_PROBE Writes a full character sheet beside every save, so
#                        feats, weapon skills and gear can be read without
#                        ending the game. The save file itself is raw C++
#                        object bytes and cannot be read from outside.
#                        Overwrites, so it always describes the last save.
#                        -> logs/charprobe.txt and .html
#
# OFF by default, and it is the one that used to be on here unconditionally:
#   INCURSION_MAP_AUDIT  Checks the map against itself -- every Thing must
#                        appear both in m->Things[] and in the Contents chain
#                        of the square it claims. Runs every tenth turn and
#                        the instant Thing::Remove fails to unlink. This is
#                        the one that can turn inc-6d5 from a code-reading
#                        into an observation. -> logs/mapaudit.log
#
# It moved because it is not free, and this script runs the shape of session
# that pays for it. Measured in inc-loa.9: one 248,207-turn run took 17.16s
# with the audit and 3.92s without, so the audit was about 77% of the process.
# A check is short enough not to notice that -- tools/headless.sh still arms
# the audit by default, and anything hunting a defect should leave it armed
# there -- but a real session is long, so the bill is real. Arm it for one
# session when you want it:
#   INCURSION_MAP_AUDIT=1 tools/play.sh
#
# EXPECT THE LOG TO BE MISSING. logs/mapaudit.log is written only while the
# audit is armed, so an ordinary session now produces no such file. Its absence
# means "not armed", not "the switch broke" and not "the map was clean". The
# report after the session says which of those it was.
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

# Empty counts as off, exactly as src/MapAudit.cpp:41 reads it: that code takes
# the VALUE, so unset, empty and 0 all mean off and everything else means on.
# The same "${VAR:-default}" idiom as tools/headless.sh:169, with the opposite
# default, for the reason in the header.
export INCURSION_MAP_AUDIT="${INCURSION_MAP_AUDIT:-0}"
export INCURSION_SAVE_PROBE=1
export INCURSION_CHAR_PROBE=1

if [ "${1:-}" = "--map-probe" ]; then
    export INCURSION_MAP_PROBE=1
    shift
    echo "map probe ON -- expect logs/mapprobe.log to grow fast"
fi

# Said on the way in as well as on the way out, because the audit is the one
# diagnostic whose state changes what the session costs.
if [ "$INCURSION_MAP_AUDIT" = "0" ]; then
    echo "diagnostics: save probe (map audit OFF -- INCURSION_MAP_AUDIT=1 arms it)"
else
    echo "diagnostics: map audit, save probe"
fi
echo "logs:        $ROOT/logs/"
echo

./incursion "$@"
STATUS=$?

echo
echo "--- after the session ---"

# The audit log always carries a header when armed, so its absence means the
# switch did not take -- which is worth saying out loud rather than reading as
# a clean run. That reasoning holds only when the audit was asked for, so the
# unarmed case is answered first. Without that branch every ordinary session
# would cry "NO LOG" about a switch nobody threw, and a leftover log from an
# earlier armed session would be reported as this session's result.
if [ "$INCURSION_MAP_AUDIT" = "0" ]; then
    echo "map audit:  not armed. Nothing was checked; no log was written."
elif [ ! -f logs/mapaudit.log ]; then
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
