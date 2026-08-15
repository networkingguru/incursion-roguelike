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

SOAK="$ROOT/logs/soak/$(date +%Y%m%d-%H%M%S)"
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
# 0 clean, 1 Fatal(), 2 bad script, 3 out of keys/budget, 4 watchdog.
sort -n "$SOAK/exits" | awk '{print $2}' | sort | uniq -c | while read -r n code; do
    case "$code" in
        0) what="clean" ;;
        1) what="FATAL" ;;
        2) what="could not start" ;;
        3) what="out of keys" ;;
        4) what="WATCHDOG -- the game stopped asking for keystrokes" ;;
        *) what="exit $code" ;;
    esac
    printf '  %4d  %s\n' "$n" "$what"
done

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
AUDIT=0
for log in "$SOAK"/seed-*/logs/mapaudit.log; do
    [ -f "$log" ] || continue
    if [ "$(grep -vc '^=== map audit armed' "$log")" != "0" ]; then
        AUDIT=$((AUDIT + 1))
        echo "  $(dirname "$(dirname "$log")" | xargs basename):"
        grep -v '^=== map audit armed' "$log" | head -3 | sed 's/^/    /'
    fi
done
[ "$AUDIT" -eq 0 ] && echo "  armed in every session, no inconsistencies found"

echo
echo "report kept in $SOAK"
