#!/bin/bash
# gate: live
# Does a y-menu verb tell the player what happened? bd inc-k8uw.
#
# THE DEFECT. Player::YuseMenu (src/Player.cpp, the DoYuse section) called
# ReThrow and discarded the result. RealThrow (src/Event.cpp) returns NOTHING
# when every handler declines, and the base code then printed no message at
# all: the player picked a verb, answered its prompts, and watched nothing
# happen with no line to say so. Pour (src/Tables.cpp) is the clearest case --
# it is implemented, and its only handler refills a brass lantern from a flask
# of oil (lib/mundane.irh), so pouring anything at anything else answers
# NOTHING silently.
#
# THE FIX prints "<Obj> cannot be <Str>." (or "Nothing happens.") when the
# verb returns NOTHING AND no handler spoke. THE TRAP the fix must avoid is a
# second line on top of a handler that already spoke: weapon oil
# (lib/m_items.irh), a poison vial (lib/mundane.irh:1027) and a potion or
# fountain whose effect returns NOTHING (src/Item.cpp:840, src/Magic.cpp:4311)
# all print their own sentence and then return NOTHING. Player::YuseMenu
# guards the fallback on a message counter (MessageCounter, inc/Globals.h)
# that TextTerm::Message and the queued branch of Player::__IPrint raise.
#
# CASE ONE, Pour, is the original defect. Its handler does NOT print, so the
# fallback still appears: the oracle is "cannot be" (or "Nothing happens.") on
# the after-pour screen. Unfixed this screen has neither and the case fails.
#
# CASE TWO, Apply a small glass vial, proves the guard. The vial's handler
# (lib/mundane.irh:1027) prints "You can only poison weapons and ammunition."
# and returns NOTHING. The oracle is that the handler's own line IS on the
# after-apply screen and "cannot be" is NOT. Without the message-counter test
# the fallback adds "The loincloth cannot be applied.", so "cannot be" appears
# and the case fails. The vial comes from wizard mode Item Acquisition,
# because no non-evil class kit carries one; see tools/keys/yuse-poison-vial.keys
# for the walk and why check_yuse_activate.sh's acquisition step is not reused.
#
# Usage: tools/check_yuse_no_effect.sh     (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
fail=0

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

run_case() { # <keyscript> -> echoes the run directory
    local out run
    out="$(INCURSION_OPTIONS=tools/gates/Options.Dat \
        tools/headless.sh "$1" "$SEED" 2>&1)" || true
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if grep -q "the key script looked for something" <<< "$out"; then
        echo "INCONCLUSIVE: $1 could not find something on screen. Run: $run" >&2
        exit 2
    fi
    echo "$run"
}

# --- case one: Pour, whose handler says nothing and the fallback must speak --
RUN1="$(run_case tools/keys/yuse-no-effect.keys)"
SCREEN1="$RUN1/logs/screens/0002-after-pour.txt"
[ -f "$SCREEN1" ] || {
    echo "INCONCLUSIVE: missing screen: $SCREEN1"
    exit 2
}

if grep -q "cannot be" "$SCREEN1" || grep -q "Nothing happens" "$SCREEN1"; then
    echo "  ok: Pour with no handler printed a fallback line"
    echo "      $(grep -m1 -hE "cannot be|Nothing happens" "$SCREEN1" | tr -s ' ')"
else
    echo "FAIL: Pour answered its prompts and printed no message at all"
    echo "      screen: $SCREEN1"
    fail=1
fi

# --- case two: Apply a poison vial, which speaks for itself and must not be --
# doubled up by the fallback.
RUN2="$(run_case tools/keys/yuse-poison-vial.keys)"
SCREEN2="$(ls "$RUN2"/logs/screens/*-after-apply.txt 2>/dev/null | head -1)"
[ -n "$SCREEN2" ] || {
    echo "INCONCLUSIVE: no after-apply screen dump in $RUN2"
    exit 2
}

if ! grep -q "You can only poison weapons and ammunition" "$SCREEN2"; then
    echo "INCONCLUSIVE: the vial handler never spoke, so the run measured"
    echo "              nothing. Screen: $SCREEN2"
    exit 2
fi
if grep -q "cannot be" "$SCREEN2"; then
    echo "FAIL: a handler that spoke was answered by a second fallback line"
    echo "      $(grep -m1 -h "cannot be" "$SCREEN2" | tr -s ' ')"
    echo "      screen: $SCREEN2"
    fail=1
else
    echo "  ok: the vial handler's own line stands alone"
    echo "      $(grep -m1 -h "You can only poison" "$SCREEN2" | tr -s ' ')"
fi

if [ "$fail" = 0 ]; then
    echo "PASS: a silent verb speaks up, a speaking verb is not doubled"
    exit 0
fi
exit 1
