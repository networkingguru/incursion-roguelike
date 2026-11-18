#!/bin/bash
# Play the game many times over, with a different dungeon each time, and
# collect what it complained about.
#
# Usage: tools/soak.sh [sessions] [first-seed] [keyscript]
#        tools/soak.sh 40 1 tools/keys/explore.keys
#        SOAK_CHAR=orc-barbarian-seed1-opt0822 tools/soak.sh 40 1 tools/keys/explore-play.keys
#
# Settings: INCURSION_OPTIONS (required, as for tools/headless.sh), SOAK_JOBS
# (sessions at a time, default 4), SOAK_DIR (where the report goes) and
# SOAK_CHAR (below).
#
# SOAK_CHAR=<fixture name | path to a .char> (bead inc-nch.1). Without it, each
# session makes its character by keystrokes (tools/keys/chargen.keys), and on
# some seeds an extra prompt appears there and the session dies in creation
# (measured: seeds 68 and 79 of explore.keys). With it, each session builds its
# character from the .char file instead and runs NO creation keys, so the key
# script MUST start in play (tools/keys/explore-play.keys, dive-play.keys); the
# soak refuses, exit 2, a script that includes chargen.keys.
# A fixture builds ONE level: the one its own `seed:` line names, so the same
# .char under every session seed would give every session the same level-1 map.
# The soak therefore writes a per-seed copy of the .char, <name>-s<seed>.char in
# the soak directory, with its `seed:` line set to the session seed, builds that
# copy once per session into a cache inside the soak directory (the shared
# logs/fixture-cache is never touched), and loads the result. Only the `seed:`
# line changes, so the character is the same in every session; the dungeon is
# not.
#
# Why this exists. logs/errors.log is the best defect finder this project has,
# and it fills up in proportion to how many different game states somebody
# walks through. One session is one dungeon, one character and one set of
# monsters. The seed changes all three, so forty sessions are forty dungeons,
# and they can run while nobody is awake.
#
# Each session is sandboxed by tools/headless.sh, so none of them can touch
# the save files in the game folder. Sessions run several at a time; the game
# is single-threaded and spends its time in the CPU, so the parallelism is
# just the core count.
#
# The report at the end groups errors by message rather than by session,
# because the same defect usually fires in many sessions at once and the
# question worth answering first is "how many distinct things went wrong".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SESSIONS="${1:-20}"
FIRST="${2:-1}"
KEYS="${3:-tools/keys/explore.keys}"
JOBS="${SOAK_JOBS:-4}"

[ -f "$KEYS" ] || { echo "no such key script: $KEYS"; exit 2; }

# includes_chargen <script>: does this script, or a script it @includes (named
# next to the file that names it, as the key reader resolves it), include
# chargen.keys? A fixture session that ran creation keys would drive the
# character-creation screens on top of an already-created character.
includes_chargen() {
    local f="$1" inc
    [ -f "$f" ] || return 1
    while read -r inc; do
        [ "$(basename "$inc")" = "chargen.keys" ] && return 0
        includes_chargen "$(dirname "$f")/$inc" && return 0
    done < <(sed -n 's/^[[:space:]]*@include[[:space:]][[:space:]]*\([^[:space:]]*\).*/\1/p' "$f")
    return 1
}

CHARSRC=""
CHARNAME=""
if [ -n "${SOAK_CHAR:-}" ]; then
    case "$SOAK_CHAR" in
        */*|*.char) CHARSRC="$SOAK_CHAR" ;;
        *)          CHARSRC="tools/fixtures/chars/$SOAK_CHAR.char" ;;
    esac
    [ -f "$CHARSRC" ] || { echo "SOAK_CHAR: no such fixture: $SOAK_CHAR (looked for $CHARSRC)"; exit 2; }
    CHARNAME="$(basename "$CHARSRC" .char)"
    [ "$(grep -c '^seed:' "$CHARSRC")" -eq 1 ] || {
        echo "SOAK_CHAR: $CHARSRC must hold exactly one 'seed:' line; the per-session seed replaces it"
        exit 2
    }
    if includes_chargen "$KEYS"; then
        echo "SOAK_CHAR: $KEYS includes chargen.keys. A fixture session must not run"
        echo "creation keys; use a script that starts in play, such as tools/keys/explore-play.keys."
        exit 2
    fi
fi
[ -x ./incursion-headless ] || {
    echo "./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# The process id is part of the name because the timestamp alone is only good
# to the second. Two soaks started in the same second used to land in one
# directory and append to one `exits` file, silently merging two experiments
# into one set of numbers -- and an A/B is exactly two soaks started back to
# back. Observed on 2026-08-15: a 4-session run and a 4-session run reported
# eight sessions, four of them from the wrong experiment.
#
# SOAK_DIR overrides the name, so a caller that has to read `exits` and
# `messages` afterwards -- the regression gate does -- can say where they go
# instead of parsing this script's output for the path.
SOAK="${SOAK_DIR:-$ROOT/logs/soak/$(date +%Y%m%d-%H%M%S)-$$}"
mkdir -p "$SOAK"

echo "sessions:  $SESSIONS  (seeds $FIRST..$((FIRST + SESSIONS - 1)))"
echo "script:    $KEYS"
echo "at a time: $JOBS"
[ -n "$CHARSRC" ] && echo "character: fixture $CHARNAME, rebuilt per session with the session seed"
echo "into:      $SOAK"
echo

# live_count <pid...>: how many of these pids are still running.
live_count() {
    local p n=0
    for p in "$@"; do kill -0 "$p" 2>/dev/null && n=$((n + 1)); done
    printf '%s' "$n"
}

run_one() {
    local seed="$1" cf sav rc
    if [ -n "$CHARSRC" ]; then
        # Exit 9 is this script's own: the fixture would not build, so the
        # session never started. seed-N.out holds the build's complaint.
        cf="$SOAK/$CHARNAME-s$seed.char"
        sed "s/^seed:.*/seed: $seed/" "$CHARSRC" > "$cf"
        if ! sav="$(INCURSION_FIXTURE_CACHE="$SOAK/fixture-cache" \
                ./tools/fixture_cache.sh "$cf" 2> "$SOAK/seed-$seed.out")"; then
            echo "$seed 9" >> "$SOAK/exits"
            return
        fi
        INCURSION_LOAD="$sav" INCURSION_RUN_DIR="$SOAK/seed-$seed" \
            ./tools/headless.sh "$KEYS" "$seed" >> "$SOAK/seed-$seed.out" 2>&1
        rc=$?
    else
        INCURSION_RUN_DIR="$SOAK/seed-$seed" \
            ./tools/headless.sh "$KEYS" "$seed" > "$SOAK/seed-$seed.out" 2>&1
        rc=$?
    fi
    echo "$seed $rc" >> "$SOAK/exits"
}

# bash 3.2 (macOS /bin/bash) has no `wait -n`, so poll the pids instead.
pids=""
for seed in $(seq "$FIRST" $((FIRST + SESSIONS - 1))); do
    while [ "$(live_count $pids)" -ge "$JOBS" ]; do sleep 0.2; done
    run_one "$seed" &
    pids="$pids $!"
done
wait

echo "--- how the sessions ended ---"
# 0 clean, 1 Fatal(), 2 bad script, 3 out of keys/budget, 4 watchdog,
# 5 no gameplay.
sort -n "$SOAK/exits" | awk '{print $2}' | sort | uniq -c | while read -r n code; do
    case "$code" in
        0) what="clean" ;;
        1) what="FATAL" ;;
        2) what="could not start" ;;
        3) what="out of keys" ;;
        4) what="WATCHDOG -- the game stopped asking for keystrokes" ;;
        5) what="NO GAMEPLAY -- never entered a map, measured nothing" ;;
        7) what="ASSERT -- an assertion not in tools/known_asserts.txt" ;;
        8) what="FIXTURE LOAD FAILED -- the cached character did not load" ;;
        9) what="FIXTURE BUILD FAILED -- the character could not be built" ;;
        *) what="exit $code" ;;
    esac
    printf '  %4d  %s\n' "$n" "$what"
done

# A soak whose sessions never played is worthless, and it is worth saying so at
# the top rather than leaving it to be inferred from a code in a table. This is
# the check that would have caught the false A/B result of 2026-08-14.
VOID="$(awk '$2==5' "$SOAK/exits" | wc -l | tr -d ' ')"
if [ "$VOID" -gt 0 ]; then
    echo
    echo "  WARNING: $VOID of $SESSIONS sessions produced NO GAMEPLAY."
    echo "  Those sessions measure nothing. Any total below is drawn from the"
    echo "  remaining $((SESSIONS - VOID)). If this number is large, fix the run"
    echo "  before drawing any conclusion from it -- and check that Options.Dat"
    echo "  in this tree is the one you meant to test with."
fi

# What the sessions did, counted from each session's own report (seed-N.out)
# and its logs/session.log, which the game writes on the first completed turn
# and so exists if and only if the session reached play (tools/headless.sh).
# Exit 5 is only one way to miss play: a session that died in character
# creation with exit 6 never played either.
NOPLAY=0
DIED=0
DEATHS=0
DSTUCK=0
TSTUCK=0
for seed in $(seq "$FIRST" $((FIRST + SESSIONS - 1))); do
    [ -f "$SOAK/seed-$seed/logs/session.log" ] || NOPLAY=$((NOPLAY + 1))
    d="$(sed -n 's/^death: *\([0-9][0-9]*\) confirmed.*/\1/p' "$SOAK/seed-$seed.out" 2>/dev/null | head -1)"
    if [ -n "$d" ]; then DIED=$((DIED + 1)); DEATHS=$((DEATHS + d)); fi
    grep -q '^death: *STUCK' "$SOAK/seed-$seed.out" 2>/dev/null && DSTUCK=$((DSTUCK + 1))
    grep -q '^stuck-prompt: *threat-disengage' "$SOAK/seed-$seed.out" 2>/dev/null && TSTUCK=$((TSTUCK + 1))
done
echo
echo "--- what the sessions did (of $SESSIONS) ---"
printf '  %4d  never reached play (no turn completed; includes NO GAMEPLAY and creation failures)\n' "$NOPLAY"
printf '  %4d  died (confirmed deaths, %d in all)\n' "$DIED" "$DEATHS"
printf '  %4d  stalled at the death prompt (Die? [yn] left unanswered)\n' "$DSTUCK"
printf '  %4d  stalled at the threat prompt (Abort, Flee or Disengage? left unanswered)\n' "$TSTUCK"

echo
echo "--- prompt stops (inc-tre9h: the session ended at the first prompt, unanswered) ---"
PSTOPS=0
for log in "$SOAK"/seed-*/logs/prompt-stop.log; do
    [ -f "$log" ] || continue
    PSTOPS=$((PSTOPS + 1))
    echo "  $(basename "$(dirname "$(dirname "$log")")"): $(head -1 "$log")"
done
[ "$PSTOPS" -eq 0 ] && echo "  none"

echo
echo "--- distinct errors, and how many sessions hit each ---"
# One line per (session, message), deduplicated inside a session first: a
# message that fires 300 times in one dungeon and once in 40 dungeons are very
# different findings, and only the second is likely to be systemic.
: > "$SOAK/messages"
for log in "$SOAK"/seed-*/logs/errors.log; do
    [ -f "$log" ] || continue
    seed="$(basename "$(dirname "$(dirname "$log")")")"
    grep '^[0-9]' "$log" | sed 's/^[0-9-]* [0-9:]*  //' | sort -u |
        sed "s|^|$seed\t|" >> "$SOAK/messages"
done

if [ -s "$SOAK/messages" ]; then
    cut -f2- "$SOAK/messages" | sort | uniq -c | sort -rn |
        awk '{ n=$1; $1=""; printf "  %3d session(s): %s\n", n, substr($0,2) }'
    echo
    echo "  total error lines: $(cat "$SOAK"/seed-*/logs/errors.log 2>/dev/null | grep -c '^[0-9]')"
    echo "  call stacks are in $SOAK/seed-*/logs/errors.log"
else
    echo "  none -- no session logged an error"
fi

echo
echo "--- map audit ---"
# ARMED counts the sessions that actually produced an audit log. Sessions that
# never entered a map produce none, and skipping them silently is how "no
# findings" gets reported as "armed in every session, nothing wrong" -- a clean
# bill of health from a run that never looked at anything.
AUDIT=0
ARMED=0
for log in "$SOAK"/seed-*/logs/mapaudit.log; do
    [ -f "$log" ] || continue
    ARMED=$((ARMED + 1))
    if [ "$(grep -vc '^=== map audit armed' "$log")" != "0" ]; then
        AUDIT=$((AUDIT + 1))
        echo "  $(dirname "$(dirname "$log")" | xargs basename):"
        grep -v '^=== map audit armed' "$log" | head -3 | sed 's/^/    /'
    fi
done
if [ "$ARMED" -eq 0 ]; then
    echo "  NEVER RAN -- no session entered a map, so nothing was audited"
elif [ "$AUDIT" -eq 0 ]; then
    echo "  armed in $ARMED of $SESSIONS sessions, no inconsistencies found"
fi

echo
echo "report kept in $SOAK"
