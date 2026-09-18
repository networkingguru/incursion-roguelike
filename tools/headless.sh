#!/bin/bash
# Run one scripted, unattended session of Incursion and report what it did.
#
# Usage: tools/headless.sh <keyscript> [seed]
#        tools/headless.sh tools/keys/smoke.keys 1
#
# INCURSION_OPTIONS is mandatory and names the settings file; INCURSION_LOAD is
# optional and names a save file to start from instead of the title menu. Both
# are environment variables rather than arguments, because the two positions
# are already spoken for in more than two hundred callers. A run that loads a
# save still has to name its settings.
#
# The session runs in its own directory under logs/runs/, with its own save/
# and logs/, and with mod/ and lib/ symlinked in. Nothing it does can reach
# the save files in the game folder -- an unattended run must not be able to
# destroy a character that took somebody an evening to make.
#
# Determinism: the seed is passed as INCURSION_SEED. Nothing is faked or
# intercepted -- the game asks NextSeed() (src/Main.cpp:47) for randomness, and
# that function returns time(NULL) when the variable is unset and the given
# number plus a counter when it is set. Six sites used to read the clock
# directly and all six now go through it. The same seed and the same key script
# play the same game, so a screen dump can be compared against a previous one.
# Without a seed the run is a smoke test only, because the attribute rolls --
# and therefore the offered feats, and therefore which letter chooses what --
# change on every run.
#
# Reproducible is NOT the same as representative. A run can repeat perfectly and
# still measure the wrong thing: see inc-loa.2 (most depth commands are refused).
# inc-loa.3 was the same trap in a sharper form -- a session whose character
# died, or got stuck at the death prompt, still exited 0 and looked exactly
# like a full session. See the "death:" line near the end of this script's
# report, which is how that stopped being invisible. inc-loa.5 is the same
# trap again at a different, unguarded prompt ("Abort, Flee or Disengage?");
# see the "stuck-prompt:" line beside it.
#
# Ends: 0 the script ran out or asked to quit, 1 Fatal(), 2 bad key script,
#       3 the key budget ran out, 4 the watchdog fired (the game stopped
#       asking for keys, which is the signature of a hang), 5 the run never
#       entered a map and so measured nothing, 6 a @choose, @cursorto or
#       @expect was told to find something the screen never showed, 7 the
#       engine logged an ASSERT that tools/known_asserts.txt does not list.
#
# A death, or a session stuck at the threat-disengage prompt, is deliberately
# NOT its own exit code: whether either should FAIL a run, versus merely be
# counted, is a product decision (inc-loa.3, inc-loa.5) that this script does
# not make. Both are always reported and always countable (logs/death.log or
# "Die? [yn]" on the last screen; "Abort, Flee or Disengage" on the last
# screen) so a caller that cares can decide for itself. See tools/gate_lib.sh,
# which does.
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

# The stamp resolves to the SECOND, so the process id is part of the name too.
# Without it, two sessions started inside one second shared a directory: one
# save/, one logs/, and any append-mode probe log holding the lines of both.
# The merged log then reads as a single long session, which is how the first
# inc-90u follower count came out wrong (five runs, one directory, four lines).
# soak.sh:48 and check_layout.sh:71 already named their directories this way.
# The id goes BEFORE the script name so that a "*-<script>" match still works.
RUN="${INCURSION_RUN_DIR:-$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-$(basename "$KEYS" .keys)}"
mkdir -p "$RUN/save" "$RUN/logs"
ln -sfn "$ROOT/mod" "$RUN/mod"
ln -sfn "$ROOT/lib" "$RUN/lib"
# Every scripted run must choose its settings explicitly. Settings change the
# game, and the repository-root Options.Dat belongs to the player and is
# rewritten during play. Stable choices live in tools/fixtures/; gates keep
# their purpose-built file in tools/gates/Options.Dat.
if [ -z "${INCURSION_OPTIONS:-}" ]; then
    echo "INCURSION_OPTIONS is required; choose a settings file from tools/fixtures/"
    exit 2
fi
OPTIONS="$INCURSION_OPTIONS"
if [ ! -f "$OPTIONS" ]; then
    echo "INCURSION_OPTIONS names a file that is not there: $OPTIONS"
    exit 2
fi
[ -f "$OPTIONS" ] && cp "$OPTIONS" "$RUN/Options.Dat"

# INCURSION_LOAD starts the session from a saved character instead of from the
# title menu. It is an environment variable and not a positional argument for
# the reason INCURSION_OPTIONS is one: over two hundred callers already pass
# "<keyscript> [seed]" by position, and a third position would have to be
# threaded through every one of them.
#
# WHY A SESSION WOULD WANT THIS. A character built by a key script is not
# reproducible across module changes: an rID in this engine is a POSITION, so
# one resource added to lib/ shifts every id above it. Measured 2026-09-12,
# commit bef32c3 added one Effect to lib/m_items.irh and the seed-1 Lizardfolk
# monk went from STR 18 holding a long sword +3 to STR 14 holding a
# quarterstaff, on byte-identical attribute dice. A character LOADED from a
# save does not move, because the v1 save schema converts every saved rID
# through that save's own per-module manifest (v1ConvertManifestRid,
# src/SaveV1.cpp). See bd inc-1fjk and tools/fixtures/chars/.
#
# THE COPY IS THE WHOLE POINT. A loaded session owns its save: Game::SaveGame
# (src/Registry.cpp:1114) writes back to SaveFile, having first renamed the old
# file to <name>.sav.backup, so a session pointed at a frozen fixture would
# rewrite the fixture and delete nothing but its own evidence. The copy lands
# in the run's own save/, which is the same directory this script hands every
# other session, so a loaded run can save as freely as any other and still
# reach nothing outside logs/runs/.
#
# The BARE FILE NAME is what goes on the command line, never the path.
# Game::LoadNamedGame (src/Registry.cpp:1322-1332) resolves a name with no '/'
# in it against the save subdirectory -- which INCURSIONPATH has already made
# the sandbox -- and treats anything else as a path to open where it stands.
# Passing the fixture's own path would therefore both read and later WRITE the
# original file, which is the trap the copy above exists to avoid.
LOAD="${INCURSION_LOAD:-}"
LOAD_ARGS=()
if [ -n "$LOAD" ]; then
    if [ ! -f "$LOAD" ]; then
        echo "INCURSION_LOAD names a file that is not there: $LOAD"
        exit 2
    fi
    LOAD_NAME="$(basename "$LOAD")"
    cp "$LOAD" "$RUN/save/$LOAD_NAME" || {
        echo "INCURSION_LOAD: could not copy $LOAD into $RUN/save/"
        exit 2
    }
    # A fixture kept read-only would copy read-only, and the game would then
    # fail its own save rather than the run failing here where it can be read.
    chmod u+w "$RUN/save/$LOAD_NAME"
    LOAD_ARGS=(-load "$LOAD_NAME")
fi

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
# Printed only when there is one, so the output a caller parses is unchanged
# for every run that does not load. A loaded run's character came from the
# file rather than from the seed, and saying so here is the only place a
# reader of the report would find that out.
[ -n "$LOAD" ] && echo "load:  $LOAD (copied to $RUN/save/$LOAD_NAME)"
echo "run:   $RUN"
echo

if [ "$TTY" -eq 1 ]; then
    # The game needs 80x48. A pseudo-terminal created here has no size of its
    # own, and ncurses falls back to LINES and COLUMNS when the ioctl gives it
    # nothing. The drawing is captured rather than shown, so the run stays
    # unattended and the escape sequences can be read afterwards.
    LINES=48 COLUMNS=80 TERM="${TERM:-xterm}" \
        script -q "$RUN/logs/terminal.out" $LAUNCHER "$BIN" -keys "$KEYS" \
        ${LOAD_ARGS[@]+"${LOAD_ARGS[@]}"} "${@:3}"
    STATUS=$?
    echo "terminal drawing captured in $RUN/logs/terminal.out"
else
    $LAUNCHER "$BIN" -keys "$KEYS" ${LOAD_ARGS[@]+"${LOAD_ARGS[@]}"} "${@:3}" < /dev/null
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

# An assert the engine logged is a defect the session found, and the check
# that drove the session must see it without reading the log. Only a normal
# ending is promoted, as with 5 above. Known asserts are listed in
# tools/known_asserts.txt so the checks do not all go red on upstream's
# standing ones; the pad-help crash of 2026-08-30 was logged here, and the
# check that ran the session read only the screen dump and passed.
NEW_ASSERTS=""
if [ -f "$RUN/logs/errors.log" ]; then
    NEW_ASSERTS="$(grep '^[0-9]' "$RUN/logs/errors.log" |
        sed -n "s/^[0-9-]* [0-9:]*  ASSERT failed: '\(.*\)' in file .*/\1/p" |
        sort -u |
        grep -vxF -f <(sed 's/ *#.*//' tools/known_asserts.txt | grep -v '^$') || true)"
fi
if [ -n "$NEW_ASSERTS" ] && { [ "$STATUS" -eq 0 ] || [ "$STATUS" -eq 3 ]; }; then
    STATUS=7
fi

case $STATUS in
    0) echo "ended:      cleanly (script finished or asked to quit)" ;;
    1) echo "ended:      FATAL -- see the log below" ;;
    2) echo "ended:      the key script could not be read" ;;
    3) echo "ended:      out of keys or budget" ;;
    4) echo "ended:      WATCHDOG -- the game stopped asking for keystrokes" ;;
    5) echo "ended:      NO GAMEPLAY -- the run never entered a map, so it" ;
       echo "            measured nothing. Do not count it as a pass." ;;
    6) echo "ended:      the key script looked for something the screen never" ;
       echo "            showed. The last screen dump is what it was reading." ;;
    7) echo "ended:      ASSERT -- the engine tripped an assertion that" ;
       echo "            tools/known_asserts.txt does not list:" ;
       echo "$NEW_ASSERTS" | sed 's/^/              /' ;;
    *) echo "ended:      exit $STATUS" ;;
esac

SCREENS="$(ls "$RUN/logs/screens" 2>/dev/null | wc -l | tr -d ' ')"
echo "screens:    $SCREENS in $RUN/logs/screens"

# Shared by both freeze checks below (inc-loa.3's death prompt and
# inc-loa.5's threat-disengage prompt): does the run's LAST screen dump still
# show the given text? Both are TextTerm::ChoicePrompt loops (src/Term.cpp)
# that block forever on a character tools/keys/dive.keys never sends, and
# @dump directives keep firing even while the game loop itself is stuck
# inside that call (they are read by the same key-consuming layer, not by
# the game loop the prompt has frozen) -- see inc-loa.5's bd note for the
# byte-identical-screens evidence. So the prompt's text sits unchanged on
# every screen dumped after it fires, and checking only the last one is
# enough to tell a session was still parked there when its key budget ran
# out.
_last_screen_shows() { # <text>
    local last
    last="$(ls "$RUN/logs/screens" 2>/dev/null | sort | tail -1)"
    [ -n "$last" ] && grep -q "$1" "$RUN/logs/screens/$last" 2>/dev/null
}

# Did the character die, or come within one accidentally-unanswered keystroke
# of it? See inc-loa.3. The pinned settings run with OPT_NODEATH on, so a
# killing blow does not end the game -- src/Fight.cpp asks "You die... Die?
# [yn]" instead, and the key script answers it with whatever token comes
# next, because the key script has no idea what is on screen. Two distinct
# things can happen from there, and a plain exit code cannot tell them apart
# from an ordinary clean run:
#
#   confirmed  the prompt got answered 'y' (for real, or OPT_ELUDE_DEATH ran
#              out of budgeted escapes): Player::Death() reached the real
#              death path (src/Fight.cpp) and logged it to logs/death.log.
#   stuck      the prompt never got answered at all before the run's key
#              budget ran out. The last screen still shows it. Measured with
#              tools/keys/dive.keys, seed 11 (logs/gate/compare-dive-87655):
#              once the prompt appears there is no further 'y' or 'n' left
#              anywhere in the rest of the script, so every remaining key --
#              hundreds of them -- is silently swallowed trying to answer it,
#              and the run reports "ended: cleanly" regardless.
#
# Either way the character generated no more real gameplay after the prompt
# appeared, so a session like this logs fewer errors and fewer audit findings
# than a live one -- exactly the shape that made 12 of 40 sessions in that
# baseline read as "quieter than the baseline" (an improvement) instead of
# as stumps. See tools/gate_lib.sh and tools/gate_compare.sh, which count
# this instead of letting it hide.
DEATHS=0
[ -f "$RUN/logs/death.log" ] && DEATHS="$(grep -c '^=== character died' "$RUN/logs/death.log")"
STUCK_AT_PROMPT=0
_last_screen_shows 'Die? \[yn\]' && STUCK_AT_PROMPT=1
if [ "$DEATHS" -gt 0 ]; then
    echo "death:      $DEATHS confirmed -- see $RUN/logs/death.log"
fi
if [ "$STUCK_AT_PROMPT" -eq 1 ]; then
    echo "death:      STUCK -- the run ended with 'Die? [yn]' still on screen,"
    echo "            unanswered. The character's fate was never settled, and"
    echo "            nothing after the prompt appeared is real gameplay."
fi
if [ "$DEATHS" -eq 0 ] && [ "$STUCK_AT_PROMPT" -eq 0 ]; then
    echo "death:      none"
fi

# inc-loa.5: "You are in a threatened area. Abort, Flee or Disengage? [afd?]"
# (src/Move.cpp:941) has no OPT_ gate at all -- it fires unconditionally
# whenever a player-controlled creature moves away from a hostile creature
# that perceives it and is not charging. Its ChoicePrompt only accepts
# 'a'/'f'/'d'/'?'/ESC, and tools/keys/dive.keys has none of those in its
# vocabulary (digits, w/p/s, HOME/END/PGUP/PGDN, arrows, ENTER), so once it
# fires every remaining scripted keystroke is silently swallowed trying to
# answer it -- unlike the death prompt above, there is no "confirmed" shape
# for this one, because dive.keys can never supply the key that would
# resolve it. Proved on 7 of 40 seeds under tools/gates/Options.Dat
# (1,15,16,31,32,37,38); see logs/gate/record-dive-89305 for the run that
# found them.
#
# Match the prompt's OWN words, "Abort, Flee or Disengage", not the bare
# words "threatened area" that used to be matched here. The prompt's '?'
# choice opens the in-game combat manual (src/Move.cpp:943,
# lib/help.irh:3320), and that manual page's own prose about attacks of
# opportunity says "threatened area" repeatedly. A session that answered
# '?' and landed in the manual instead of staying at the prompt matched the
# old pattern and was reported as still stuck AT the prompt, which it was
# not. Measured 2026-09-18: tools/keys/dive.keys, seed 11, ends in the
# manual (mode 5, MO_HELP) with "threatened area" on its last screen and no
# "Abort, Flee or Disengage" anywhere on it.
THREAT_STUCK=0
_last_screen_shows 'Abort, Flee or Disengage' && THREAT_STUCK=1
if [ "$THREAT_STUCK" -eq 1 ]; then
    echo "stuck-prompt: threat-disengage -- the run ended with 'Abort, Flee or"
    echo "              Disengage?' still on screen, unanswered (inc-loa.5)."
    echo "              Nothing after this point is real gameplay."
else
    echo "stuck-prompt: none"
fi

# GAME TIME. Every freeze check above matches one prompt's literal text, and
# each was written after that prompt had already wasted a soak: inc-loa.3 the
# death prompt, inc-loa.5 the threat-disengage prompt. The class kept coming
# back because a string match only ever catches the string it was given.
#
# This check is the general form. All of those failures, and the refused
# commands of inc-loa.2, share one signature -- the session reads keys and
# spends no game time. The turn counter in each screen dump's header
# (src/Wposix.cpp, posixTerm::DumpScreen) makes that directly measurable, so
# a new trap needs no new detector.
#
# It reports rather than fails. Some intervals are legitimately still: a walk
# that spends its keys inside a menu it then leaves has done nothing wrong.
# What is never right is a run whose LAST interval is frozen, because nothing
# after that point is gameplay -- that is the shape marathon.keys had when
# this was written (inc-2k3): 6,059 of its 10,621 keys parked in Inventory
# Mode, while the report above said "ended: cleanly".
_turn_series() { # -> "key turn" per screen, in order
    local f
    for f in $(ls "$RUN/logs/screens"/*.txt 2>/dev/null | sort); do
        sed -n '1s/.*key \([0-9]*\).*turn \([0-9]*\).*/\1 \2/p' "$f"
    done
}
GAMETIME="$(_turn_series)"
if [ -z "$GAMETIME" ]; then
    echo "game time:  unknown -- no screen dump carries a turn stamp. Either the"
    echo "            run made no dumps, or the binary predates the turn field"
    echo "            in the dump header (src/Wposix.cpp)."
else
    echo "$GAMETIME" | awk -f tools/gametime.awk
fi

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
