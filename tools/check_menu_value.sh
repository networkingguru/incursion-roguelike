#!/bin/bash
# Regression check for inc-802: a script menu must give back the same object
# it was handed.
#
# WHAT THE DEFECT WAS. inc/Api.h declares the script side of every engine
# call, and the resource compiler turns those declarations into the virtual
# machine's dispatcher, lib/dispatch.h. The declaration for LOption -- the
# call every script uses to put one line into a menu -- said its value
# parameter was an int16, so the generated dispatcher truncated it:
#
#     T1->LOption(GETSTR(STACK(1)), (int16)STACK(2), GETSTR(STACK(3)));
#
# The value is the caller's own cookie, and every script that opens a menu
# over objects puts an object handle in it (lib/alchemy.irh:1062 and :1241,
# AutoDrop and AutoLoot) or a resource id (lib/abilities.irh:98-237, the
# undead-form menus). An hObj is a signed 32-bit handle; an rID runs past
# sixteen million. Neither fits. TextTerm::LOption itself takes an int32 and
# Option::Val is an int32 (inc/Term.h:236, :637), so only the declaration was
# ever narrow.
#
# WHY IT WAS INVISIBLE FOR SO LONG. Handles are handed out in order from 128,
# so for the first 32639 objects of a game the truncation changes nothing.
# Past that, every marked item comes back as a negative number that names no
# object, and AutoLoot's own first guard -- !isValidHandle -- drops it without
# a word. Brian's save reached that point after four character levels: the
# first chest of the game looted fine, the second looted nothing and said
# "You stop AutoLoot (finished looting)".
#
# HOW THIS CHECK GETS THERE IN ONE SECOND. INCURSION_HANDLE_BASE (see
# Registry::Registry, src/Registry.cpp) starts the handle counter at a number
# of the caller's choosing instead of at 128. This script sets it to 40000, so
# the orc barbarian of tools/keys/chargen.keys carries gear with handles past
# the sixteen-bit line before he has taken a single step. Nothing else about a
# handle changes with its size.
#
# The session then presses F9 (AutoDrop), marks the first row, and accepts.
# PASS is the game saying it dropped the knife. A build with the truncation
# back in place says nothing at all, because the macro is holding a number
# that names no object.
#
# The second assertion is the control: the SAME script with no handle base
# must also drop the knife. Without it a build that broke AutoDrop outright
# would fail this check for the wrong reason, and the failure would be read
# as the truncation coming back.
#
# Ends: 0 pass, 1 fail, 2 the check could not be run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${1:-1}"
BASE="${2:-40000}"
KEYS="tools/keys/menu-value.keys"
OPTS="$ROOT/tools/gates/Options.Dat"
BIN="${INCURSION_BIN:-./incursion-headless}"
WANT="dropped."

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$OPTS" ] || { echo "INCONCLUSIVE: no settings file at $OPTS"; exit 2; }
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: no key script at $KEYS"; exit 2; }

RUN="$(mktemp -d "${TMPDIR:-/tmp}/incursion-menuval.XXXXXX")"
trap 'rm -rf "$RUN"' EXIT

# $1 the handle base, or empty for the game's own 128. $2 where to put it.
# Prints the screen that follows the drop, or nothing if the run never got
# that far.
play() {
    local base="$1" dir="$2"

    if [ -n "$base" ]; then
        INCURSION_HANDLE_BASE="$base" INCURSION_RUN_DIR="$dir/game" \
            INCURSION_OPTIONS="$OPTS" INCURSION_BIN="$BIN" \
            tools/headless.sh "$KEYS" "$SEED" > "$dir/out" 2>&1
    else
        INCURSION_RUN_DIR="$dir/game" \
            INCURSION_OPTIONS="$OPTS" INCURSION_BIN="$BIN" \
            tools/headless.sh "$KEYS" "$SEED" > "$dir/out" 2>&1
    fi

    cat "$dir/game/logs/screens/"*after-drop* 2>/dev/null
}

FAIL=0

mkdir -p "$RUN/wide" "$RUN/narrow"
play "$BASE" "$RUN/wide"   > "$RUN/wide.screen"
play ""      "$RUN/narrow" > "$RUN/narrow.screen"

# The control first: if this fails, the check has nothing to say about
# truncation and must not pretend otherwise.
if [ ! -s "$RUN/narrow.screen" ]; then
    echo "INCONCLUSIVE: the control run never reached the AutoDrop screen."
    sed -n '/--- after the session ---/,$p' "$RUN/narrow/out"
    exit 2
fi
if ! grep -q "$WANT" "$RUN/narrow.screen"; then
    echo "INCONCLUSIVE: AutoDrop dropped nothing even with ordinary handles,"
    echo "              so this run cannot tell you anything about handle width."
    echo "              Fix AutoDrop, or the key script, first."
    head -4 "$RUN/narrow.screen"
    exit 2
fi

if [ ! -s "$RUN/wide.screen" ]; then
    echo "FAIL: with handles from $BASE the session never reached the AutoDrop"
    echo "      screen at all."
    sed -n '/--- after the session ---/,$p' "$RUN/wide/out"
    FAIL=1
elif ! grep -q "$WANT" "$RUN/wide.screen"; then
    echo "FAIL: with handles from $BASE, AutoDrop marked an item and dropped"
    echo "      nothing. The menu is not giving back the handle it was given."
    echo "      Check the LOption line in lib/dispatch.h: if it casts its value"
    echo "      to (int16), inc/Api.h has gone narrow again and the file needs"
    echo "      regenerating with: $BIN -compile main.irc"
    echo
    echo "      what the screen said:"
    sed -n '2,4p' "$RUN/wide.screen"
    FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
    echo "PASS: AutoDrop dropped the marked item with handles from 128 and"
    echo "      again with handles from $BASE, so the menu round-trip is not"
    echo "      losing the top half of a handle."
fi
exit "$FAIL"
