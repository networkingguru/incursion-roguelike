#!/bin/bash
# Regression check for inc-qhux: walls that pass light.
#
# WHAT WAS WRONG. Level generation restored a cell's .Solid from terrain when it
# removed a door but never its .Opaque (src/MakeLev.cpp:2076, 2083-2084, 2153),
# and Door::SetImage clears .Opaque for an open/broken door (src/Feature.cpp:570).
# A wall reconstituted from a removed door therefore stayed solid but
# see-through -- 3 such cells per level on Brian's real save, one on each of two
# levels' Dungeon-Wall terrain (1573 opaque, 3 transparent). It stayed invisible
# until the light-map port made a light ray stop only at an Opaque cell
# (CARE_ABOUT_LIGHT, src/Vision.cpp), and then those cells leaked the lit passage
# on the far side of the wall.
#
# THE FIX. src/MakeLev.cpp now restores .Opaque from terrain beside .Solid, and
# Map::FixWallOpacity (src/Display.cpp), called on load (src/Registry.cpp) and on
# level entry (Game::GetDungeonMap), heals levels already stored in a save.
#
# WHAT THIS ASSERTS. A freshly generated level must contain no WALL terrain that
# is in the majority opaque yet has a see-through cell -- that combination is the
# bug's signature and nothing else's. A by-design transparent wall (ice, fence,
# portcullis) is uniformly non-opaque and is not flagged; a feature cell sits on
# a non-wall terrain and is not flagged. The analyser is tools/wall_opacity_check.py.
#
#   tools/check_wall_opacity.sh              exit 0 pass, 1 fail, 2 inconclusive
#   tools/check_wall_opacity.sh --selftest   prove the analyser detects the bug
#
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=7
KEYS=tools/keys/dive.keys
ANALYSER=tools/wall_opacity_check.py
BIN=incursion

if [ ! -x "$BIN" ]; then
    echo "no $BIN built; run BACKEND=posix ./build_macos.sh first" >&2
    exit 2
fi

RUN="$(mktemp -d)"
trap 'rm -rf "$RUN"' EXIT
mkdir -p "$RUN/save"

# Generate a level with the current binary; the harness sandboxes save/.
INCURSION_RUN_DIR="$RUN" INCURSION_MAP_AUDIT=0 \
    tools/headless.sh "$KEYS" "$SEED" >"$RUN/run.log" 2>&1
SAVE="$(ls "$RUN"/save/*.sav 2>/dev/null | head -1)"
if [ -z "$SAVE" ]; then
    echo "the generated session produced no save; see $RUN/run.log" >&2
    sed -n '1,40p' "$RUN/run.log" >&2
    exit 2
fi

if [ "${1:-}" = "--selftest" ]; then
    # Inject the bug into the clean save and require the analyser to catch it.
    BUG="$RUN/bug.sav"
    python3 "$ANALYSER" inject "$SAVE" "$BUG" || { echo "inject failed" >&2; exit 2; }
    if python3 "$ANALYSER" analyse "$BUG"; then
        echo "SELFTEST FAIL: analyser passed a save it should have flagged" >&2
        exit 1
    fi
    echo "selftest ok: analyser detects the injected bug"
    exit 0
fi

python3 "$ANALYSER" analyse "$SAVE"
