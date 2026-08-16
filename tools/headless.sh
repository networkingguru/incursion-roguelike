#!/bin/bash
# Run one scripted, unattended session of Incursion and report what it did.
#
# Usage: tools/headless.sh <keyscript> [seed]
#        tools/headless.sh tools/keys/smoke.keys 1
#
# The session runs in its own directory under logs/runs/, with its own save/
# and logs/, and with mod/ and lib/ symlinked in. Nothing it does can reach
# the save files in the game folder -- an unattended run must not be able to
# destroy a character that took somebody an evening to make.
#
# Determinism: the seed is passed as INCURSION_SEED, which replaces the two
# clock reads the game normally seeds itself from (src/Main.cpp). The same
# seed and the same key script play the same game, so a screen dump can be
# compared against a previous one. Without a seed the run is a smoke test
# only, because the attribute rolls -- and therefore the offered feats, and
# therefore which letter chooses what -- change on every run.
#
# Ends: 0 the script ran out or asked to quit, 1 Fatal(), 2 bad key script,
#       3 the key budget ran out, 4 the watchdog fired (the game stopped
#       asking for keys, which is the signature of a hang), 5 the run never
#       entered a map and so measured nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# --tty draws to a real terminal instead of to files, by giving the game a
# pseudo-terminal. Use this and never the binary directly: a session run from
# the game folder saves into the game folder, and a scripted character will
# land in save/ beside real ones. It has happened.
TTY=0
if [ "${1:-}" = "--tty" ]; then
    TTY=1
    shift
fi

KEYS="${1:-}"
SEED="${2:-}"

if [ -z "$KEYS" ] || [ ! -f "$KEYS" ]; then
    echo "usage: tools/headless.sh <keyscript> [seed]"
    echo "key scripts live in tools/keys/"
    exit 2
fi
# INCURSION_BIN picks a different build -- the DIVERGE_PROBE one, say -- and
# INCURSION_LAUNCHER puts something in front of it. Both exist for
# tools/check_layout.sh, which has to run the probe build under lldb to switch
# address randomisation off. They are deliberately thin: everything that keeps
# a session from touching the real save files stays in one place, here, and a
# caller that needed a different binary would otherwise have written its own
# copy of that sandbox. Note that a launcher swallows the exit code -- lldb
# reports its own -- so a caller that uses one must judge the run by what it
# left behind, not by $?.
BIN="${INCURSION_BIN:-./incursion-headless}"
LAUNCHER="${INCURSION_LAUNCHER:-}"

[ -x "$BIN" ] || {
    echo "$BIN not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

RUN="${INCURSION_RUN_DIR:-$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$(basename "$KEYS" .keys)}"
mkdir -p "$RUN/save" "$RUN/logs"
ln -sfn "$ROOT/mod" "$RUN/mod"
ln -sfn "$ROOT/lib" "$RUN/lib"
# Which settings the session plays with. The default is the live file, because
# a session with NO options file never finishes character generation and so
# measures nothing -- that produced two false passes on 2026-08-14.
#
# But the live file is whatever Brian last used, and the game rewrites it every
# time he plays. Settings change the game: on 2026-08-15 the same binary, seed
# and key script gave different screens either side of a rewrite at 17:49, and
# the regression tool's finding count moved 4386 -> 4416 with no code change.
# So anything that compares one run against another must pass
# INCURSION_OPTIONS and pin a file. The gate does; see tools/gate_lib.sh.
#
# A caller that asks for a file it cannot have gets an error, not the live one.
# Falling back would put the defect straight back, and quietly.
OPTIONS="${INCURSION_OPTIONS:-$ROOT/Options.Dat}"
if [ -n "${INCURSION_OPTIONS:-}" ] && [ ! -f "$OPTIONS" ]; then
    echo "INCURSION_OPTIONS names a file that is not there: $OPTIONS"
    exit 2
fi
[ -f "$OPTIONS" ] && cp "$OPTIONS" "$RUN/Options.Dat"

# The probes that have already caught real defects. They do NOT cost nothing,
# which is why they can be turned off: a sample of a headless run on 2026-08-15
# put 75% of it inside AuditMap, so a session with the audit on measures the
# audit and not the game. Anything timing the engine must set
# INCURSION_MAP_AUDIT=0, and anything hunting defects should leave it alone.
export INCURSION_MAP_AUDIT="${INCURSION_MAP_AUDIT:-1}"
export INCURSION_SAVE_PROBE="${INCURSION_SAVE_PROBE:-1}"
export INCURSIONPATH="$RUN/"
[ -n "$SEED" ] && export INCURSION_SEED="$SEED"

echo "keys:  $KEYS"
echo "seed:  ${SEED:-<clock -- this run is not reproducible>}"
# Printed because it is an input to the result. A run whose numbers surprise
# somebody later should say on its own face which settings produced them.
echo "opts:  $OPTIONS"
echo "run:   $RUN"
echo

if [ "$TTY" -eq 1 ]; then
    # The game needs 80x48. A pseudo-terminal created here has no size of its
    # own, and ncurses falls back to LINES and COLUMNS when the ioctl gives it
    # nothing. The drawing is captured rather than shown, so the run stays
    # unattended and the escape sequences can be read afterwards.
    LINES=48 COLUMNS=80 TERM="${TERM:-xterm}" \
        script -q "$RUN/logs/terminal.out" $LAUNCHER "$BIN" -keys "$KEYS" "${@:3}"
    STATUS=$?
    echo "terminal drawing captured in $RUN/logs/terminal.out"
else
    $LAUNCHER "$BIN" -keys "$KEYS" "${@:3}" < /dev/null
    STATUS=$?
fi

echo
echo "--- after the session ---"

# Did the game ever actually play? Game::Play writes logs/session.log on the
# first completed turn, unconditionally, so the file exists if and only if the
# session reached gameplay.
#
# It used to ask logs/mapaudit.log the same question. That was right only while
# the audit could not be switched off. Once it could, a disabled audit wrote no
# log and every session reported NO GAMEPLAY -- which hit hardest in the one
# case the switch exists for, timing, because a timing run MUST set
# INCURSION_MAP_AUDIT=0 and would then discard all of its own data. Proved on
# 2026-08-15 with one seed ten seconds apart: audit on reached turn 199900,
# audit off was called vacuous. See inc-duz.
#
# This has to change the exit code, not just print a line. A session whose keys
# are all eaten by character generation exits 0, and every caller that reads the
# exit code -- soak.sh, and any A/B comparison -- counts it as a clean pass. On
# 2026-08-14 that turned 250 sessions that played nothing into the evidence for
# a fix, and the false result was written into a commit message. Two runs that
# both did nothing agree perfectly, which is what made it convincing.
#
# Do NOT be tempted to count screens instead. Screens come from @dump lines in
# the key script, so a session that never entered a map still produces them --
# the vacuous run of 2026-08-15 left 11.
#
# Only a normal ending is promoted. A FATAL or a watchdog stop says more about
# the run than "no gameplay" does, so those keep their own code.
PLAYED=1
[ -f "$RUN/logs/session.log" ] || PLAYED=0
if [ "$PLAYED" -eq 0 ] && { [ "$STATUS" -eq 0 ] || [ "$STATUS" -eq 3 ]; }; then
    STATUS=5
fi

case $STATUS in
    0) echo "ended:      cleanly (script finished or asked to quit)" ;;
    1) echo "ended:      FATAL -- see the log below" ;;
    2) echo "ended:      the key script could not be read" ;;
    3) echo "ended:      out of keys or budget" ;;
    4) echo "ended:      WATCHDOG -- the game stopped asking for keystrokes" ;;
    5) echo "ended:      NO GAMEPLAY -- the run never entered a map, so it" ;
       echo "            measured nothing. Do not count it as a pass." ;;
    *) echo "ended:      exit $STATUS" ;;
esac

SCREENS="$(ls "$RUN/logs/screens" 2>/dev/null | wc -l | tr -d ' ')"
echo "screens:    $SCREENS in $RUN/logs/screens"

if [ -f "$RUN/logs/errors.log" ]; then
    echo "errors:     $(grep -c '^[0-9]' "$RUN/logs/errors.log") logged, distinct messages:"
    grep '^[0-9]' "$RUN/logs/errors.log" | sed 's/^[0-9-]* [0-9:]*  //' | sort | uniq -c |
        sort -rn | head -10 | sed 's/^/  /'
else
    echo "errors:     none"
fi

# The audit log always carries a header when armed, so its absence means either
# that the caller turned the audit off or that the switch did not take. Those
# are different things and the report must not merge them: reading "no log" as
# "never played" is the defect this file used to have (inc-duz).
if [ ! -f "$RUN/logs/mapaudit.log" ]; then
    if [ "$INCURSION_MAP_AUDIT" = "0" ]; then
        echo "map audit:  off (INCURSION_MAP_AUDIT=0), nothing was checked"
    elif [ "$PLAYED" -eq 0 ]; then
        echo "map audit:  no log, and the run never entered a map"
    else
        echo "map audit:  NO LOG despite gameplay -- the switch did not take"
    fi
elif [ "$(grep -vc '^=== map audit armed' "$RUN/logs/mapaudit.log")" = "0" ]; then
    echo "map audit:  armed, no inconsistencies found"
else
    echo "map audit:  FOUND SOMETHING --"
    grep -v '^=== map audit armed' "$RUN/logs/mapaudit.log" | tail -10 | sed 's/^/  /'
fi

exit $STATUS
