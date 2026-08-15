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
[ -f "$ROOT/Options.Dat" ] && cp "$ROOT/Options.Dat" "$RUN/Options.Dat"

# The probes that cost nothing and have already caught real defects. The map
# audit is the one that can turn inc-6d5 from code-reading into observation.
export INCURSION_MAP_AUDIT=1
export INCURSION_SAVE_PROBE=1
export INCURSIONPATH="$RUN/"
[ -n "$SEED" ] && export INCURSION_SEED="$SEED"

echo "keys:  $KEYS"
echo "seed:  ${SEED:-<clock -- this run is not reproducible>}"
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

# Did the game ever actually play? MapAudit.cpp opens logs/mapaudit.log on the
# FIRST audit rather than at startup, and audits run only while turns pass on a
# map, so the file exists if and only if the session reached gameplay.
#
# This has to change the exit code, not just print a line. A session whose keys
# are all eaten by character generation exits 0, and every caller that reads the
# exit code -- soak.sh, and any A/B comparison -- counts it as a clean pass. On
# 2026-08-14 that turned 250 sessions that played nothing into the evidence for
# a fix, and the false result was written into a commit message. Two runs that
# both did nothing agree perfectly, which is what made it convincing.
#
# Only a normal ending is promoted. A FATAL or a watchdog stop says more about
# the run than "no gameplay" does, so those keep their own code.
PLAYED=1
[ -f "$RUN/logs/mapaudit.log" ] || PLAYED=0
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

# The audit log always carries a header when armed, so its absence means the
# switch did not take -- which is worth saying out loud rather than reading as
# a clean run.
if [ ! -f "$RUN/logs/mapaudit.log" ]; then
    echo "map audit:  no log (the run never entered a map)"
elif [ "$(grep -vc '^=== map audit armed' "$RUN/logs/mapaudit.log")" = "0" ]; then
    echo "map audit:  armed, no inconsistencies found"
else
    echo "map audit:  FOUND SOMETHING --"
    grep -v '^=== map audit armed' "$RUN/logs/mapaudit.log" | tail -10 | sed 's/^/  /'
fi

exit $STATUS
