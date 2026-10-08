#!/bin/bash
# gate: live
# gate-serial: writes a fixed scratch module dir logs/kxc6-error-module and rm -rf's it
# Does ThrowEvent's e.EMap ERROR arm (src/Event.cpp:315-319) read e.p[i]
# with i left over from the god-watch loops above it, an out-of-bounds read
# of EvParam p[5] (inc/Events.h:207)? (bd inc-kxc6)
#
# THE DEFECT. src/Event.cpp's ThrowEvent uses `i` as the loop variable of
# two god loops (lines 263-302: "if (e.EActor && e.EActor->isCharacter())
# for (i=0;i!=nGods;i++) ..." and the same for e.EVictim). When no god
# returns early, i == nGods afterwards (17 gods on master,
# InitGodArrays()/theGame->LastGod(), src/Event.cpp:137-147). The very next
# stretch of the SAME function, line 304, dispatches e.EMap and its ERROR
# arm (line 315-319) formats
# `e.p[i].o ? e.p[i].o->Name(0) : "(null)"` -- an out-of-bounds read of
# EvParam p[5] (inc/Events.h:207), followed by a call through whatever
# bytes it finds there.
#
# THE PATH. Map::thEnGenSummXY (src/Encounter.cpp:230-248) sets e.EMap,
# e.enID and e.EActor, then ReThrow(EV_ENGEN,e). With the PLAYER as crea,
# the actor god loop runs (EActor->isCharacter() is true) and leaves
# i == nGods; e.EVictim is unset so the second loop never touches i again.
# Map::Event (src/MakeLev.cpp:107-122) sends EV_ENGEN to the encounter
# resource's own handler FIRST (SEND_TO(enID)); if that handler returns
# ERROR, Map::Event returns ERROR immediately, back through ThrowTo's
# T_MAP case (src/Event.cpp:380) to ThrowEvent's own e.EMap ERROR arm,
# which reads e.p[nGods].
#
# THE FIXTURE. tools/fixtures/kxc6-error-encounter.irh adds one test god
# ("kxc6 error god") whose EV_BLESSING handler calls EMap->thEnGenSummXY
# with the PLAYER as crea, targeting one test Encounter ("kxc6 error
# encounter") whose own PRE(EV_ENGEN) handler returns ERROR. Two Error()
# controls (KXC6-TRIGGER, KXC6-HANDLER) are logged -- and fflush()ed,
# src/ErrorLog.cpp:163 -- before the OOB read, so this check can tell
# "the trigger/handler never fired" from "fired, and the session then
# (maybe) crashed". This check builds a SCRATCH module for it: lib/ copied
# under logs/, the fixture APPENDED to the END of the COPY's main.irc --
# never inserted mid-file (a v1 save records each resource array's length
# and each entry's name in POSITION order, so a mid-file insert would slide
# every later resource one place) -- compiled with the current
# ./incursion-headless via INCURSIONPATH, and run through
# INCURSION_RUN_DIR, the same shape tools/check_periodic_interval.sh uses
# for tools/fixtures/periodic-interval-gods.irh. No tracked file is ever
# touched by this half, so it needs no trap and no restore.
#
# THE ORACLE. Reads the session's logs/errors.log (src/ErrorLog.cpp:124,
# via src/Wposix.cpp's Error()). PASS (exit 0) only when the
# "Event <name>::<event> routine returned ERROR!" line is present AND
# names the map -- Map::Name(0) (src/Message.cpp:839-844) returns
# NAME(dID) when dID is set, and the starting dungeon is
# $"The Goblin Caves" (lib/dungeon.irh:7), the name the FIX makes it
# print. FAIL (exit 1) when that line names anything else, or the session
# crashed (check_run's own _check_session_verdict already treats a signal
# exit as FAIL and quotes errors.log). INCONCLUSIVE (exit 2) when the
# trigger or the handler never fired, or the ERROR line never appeared at
# all -- each measures nothing about the OOB read.
#
# THE FIX. src/Event.cpp's map ERROR arm now names e.EMap instead of the
# out-of-bounds e.p[i]. The check_mutation below reverts that one
# expression to e.p[i].o so --prove-red rebuilds the broken arm and shows
# this check going red, naming e.p[nGods] instead of the map.
#
# Usage: tools/check_throwevent_error.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# The mutation this check defends: name the map (the fix) vs. read the
# stale e.p[i] (the upstream OOB). --prove-red puts the old expression
# back in the map ERROR arm's NAME argument, rebuilds, and re-runs.
check_mutation src/Event.cpp \
'                e.EMap ? (const char*) e.EMap->Name(0) : "(null)",' \
'                e.p[i].o ? (const char*) e.p[i].o->Name(0) : "(null)",'

# The scratch module: lib/ copied, inc/ symlinked, the fixture appended to
# the COPY's main.irc, compiled with the CURRENT ./incursion-headless. Lives
# under logs/, not a mktemp dir a trap would delete, so the evidence survives
# this script's own exit.
MODULE="$CHECK_ROOT/logs/kxc6-error-module"
rm -rf "$MODULE"
mkdir -p "$MODULE/mod" "$MODULE/save" "$MODULE/logs"
cp -Rf "$CHECK_ROOT/lib" "$MODULE/lib" || _check_die 2 "could not copy lib/"
ln -sfn "$CHECK_ROOT/inc" "$MODULE/inc"
cat "$CHECK_ROOT/tools/fixtures/kxc6-error-encounter.irh" >> "$MODULE/lib/main.irc"

[ -x ./incursion-headless ] || _check_die 2 \
    "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"

COMPILE_LOG="$MODULE/compile.log"
INCURSIONPATH="$MODULE/" ./incursion-headless -compile main.irc \
    < /dev/null > "$COMPILE_LOG" 2>&1
if [ ! -f "$MODULE/mod/Incursion.Mod" ]; then
    echo "--- compile output ---"
    tail -30 "$COMPILE_LOG"
    _check_die 2 "the scratch module with kxc6-error-encounter.irh appended did not compile"
fi

export INCURSION_RUN_DIR="$MODULE"

check_run tools/keys/throwevent-error.keys 1

ERRLOG="$CHECK_RUN/logs/errors.log"
[ -f "$ERRLOG" ] || _check_die 2 "no errors.log at $ERRLOG"

TRIGGER_N="$(grep -c 'KXC6-TRIGGER:' "$ERRLOG")"
HANDLER_N="$(grep -c 'KXC6-HANDLER:' "$ERRLOG")"
echo "  control: KXC6-TRIGGER logged $TRIGGER_N time(s), KXC6-HANDLER logged $HANDLER_N time(s)"

if [ "$TRIGGER_N" -eq 0 ] || [ "$HANDLER_N" -eq 0 ]; then
    _check_die 2 \
        "the trigger or the handler never fired" \
        "(KXC6-TRIGGER=$TRIGGER_N, KXC6-HANDLER=$HANDLER_N), so this run" \
        "measured nothing about the OOB read. See $ERRLOG."
fi

ERRLINE="$(grep 'routine returned ERROR!' "$ERRLOG" | head -1)"
if [ -z "$ERRLINE" ]; then
    _check_die 2 \
        "the handler ran and returned ERROR (both controls logged), but no" \
        "'... routine returned ERROR!' line ever appeared in $ERRLOG." \
        "This run measured nothing about ThrowEvent's own ERROR arm."
fi
echo "  ERROR line: $ERRLINE"

NAMED="$(printf '%s\n' "$ERRLINE" | sed -n 's/^.*Event \(.*\)::[^:]*routine returned ERROR!.*$/\1/p')"
echo "  named: '$NAMED'"

WANT="The Goblin Caves"

if [ "$NAMED" = "$WANT" ]; then
    echo
    echo "PASS: the ERROR line names the map ('$WANT'), as Map::Name(0) gives"
    echo "      for the starting dungeon. ($CHECK_RUN)"
    exit 0
fi

echo
echo "FAIL: the ERROR line names '$NAMED', not the map ('$WANT')."
echo "      e.p[i] is read out of bounds (i == nGods at this call site)."
echo "      session: $CHECK_RUN"
exit 1
