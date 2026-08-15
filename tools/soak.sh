#!/bin/bash
# Play the game many times over, with a different dungeon each time, and
# collect what it complained about.
#
# Usage: tools/soak.sh [sessions] [first-seed] [keyscript]
#        tools/soak.sh 40 1 tools/keys/explore.keys
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
echo "into:      $SOAK"
echo

run_one() {
    local seed="$1"
    INCURSION_RUN_DIR="$SOAK/seed-$seed" \
        ./tools/headless.sh "$KEYS" "$seed" > "$SOAK/seed-$seed.out" 2>&1
    echo "$seed $?" >> "$SOAK/exits"
}

running=0
for seed in $(seq "$FIRST" $((FIRST + SESSIONS - 1))); do
    run_one "$seed" &
    running=$((running + 1))
    if [ "$running" -ge "$JOBS" ]; then
        wait -n 2>/dev/null || wait
        running=$((running - 1))
    fi
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
