#!/bin/bash
# Regression check for the Skill Manager that threw away every rank, inc-0o0r.
#
# TWO RUNS, BECAUSE THE DEFECT HAS TWO FACES. One arm of one switch produced
# both, and which one you see depends only on whether the rank pool is empty:
#
#   PART A, character generation (SkillManager(true), pool not empty). The arm
#           ran Reset and threw every allocation away.
#   PART B, level-up (SkillManager(false), pool empty). The same arm fell
#           through to the return and shut the manager without a word.
#
# Part B is reached through the character sheet's [S], which calls
# SkillManager() with its default argument of false (src/Managers.cpp:2318,
# inc/Term.h:731) -- the same call a level-up makes. That needs no experience
# points, where the wizard 'Generate 50 XP Ticks' route would need 1000 of
# them for a Barbarian's second level and would prove nothing extra.
#
# TextTerm::SkillManager (src/Managers.cpp:1529) ran one switch over the key.
# Its default: arm was also its exit path, because KY_ENTER fell through into
# it, so a key the switch did not list did what ENTER does -- and during
# character generation, with ranks still unspent, that is `goto Reset`, which
# memsets Alloc[], Ranks[], MRanks[], Show[] and Spent[] and re-reads the pool
# from the player. Every allocation made in the visit was gone, with no prompt
# and no message. At level-up, where the pool is already empty, the same arm
# closed the manager instead. Same defect, two faces.
#
# THE KEYS ARE NOT AN ODD KEYBOARD CHOICE. poll_gamepad maps the left stick's
# eight octants onto the numeric keypad (src/Wlibtcod.cpp:729-731). UP-LEFT is
# KP7 -> KY_HOME -> KY_CMD_NORTHWEST, DOWN-LEFT is KP1 -> KY_END ->
# KY_CMD_SOUTHWEST (src/Tables.cpp:4683 and :4685). Both are inside the arrow
# range GetCharCmd filters on, so both reach the switch, and the switch listed
# neither. KY_CMD_NORTHEAST and KY_CMD_SOUTHEAST -- the right-hand diagonals --
# do have cases, which is why Brian reported the two LEFT diagonals firing and
# the right ones behaving. Reported from a Steam Deck on 2026-09-07.
#
# Measured 2026-09-07, seed 5, src/Managers.cpp the only file different
# between the two builds:
#
#                       before the fix        after the fix
#   Unspent pool        *  ->  *******        *  ->  *
#   Athletics           ** ->  (empty)        ** ->  **
#   Climb               ** ->  (empty)        ** ->  **
#   Craft               ** ->  (empty)        ** ->  **
#   Cursor              Craft -> Athletics    Craft -> Craft
#
# The oracle is stricter than that table, and deliberately so: an unlisted key
# must do NOTHING, so the screen after it must be byte-identical to the screen
# before it. Anything else is a change the player did not ask for.
#
# ESC IS THE OTHER HALF, and it is checked differently. The footer has always
# called it Abort and it used to abort by wiping without asking; it asks now,
# so declining must leave every rank alone. A declined ESC returns through
# Recount, which redraws the page from the top and legitimately moves the
# cursor there, so that dump is checked on its ranks and its pool rather than
# byte-for-byte.
#
# THE RUN CAN FAIL TO MEASURE ANYTHING, and that is INCONCLUSIVE rather than
# FAIL: a session that never reached the Skill Manager, or that reached it
# with no ranks placed, says nothing about the bug. Sending somebody hunting a
# regression that a dead session invented is the mistake of inc-loa.3.
#
# KEEP THIS SCRIPT BASH 3.2 CLEAN. /bin/bash on macOS is 3.2, where a bash 4
# expansion such as ${name^^} is a fatal "bad substitution" that abandons the
# enclosing loop -- and this script then reached its summary with the failure
# flag still 0 and printed PASS over a run that had just measured the bug.
# Found by red-proofing this script against the unfixed build, 2026-09-07.
#
# Usage: tools/check_skill_manager_reset.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=5
OPTS=tools/fixtures/options-2026-08-22.dat
fail=0

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# tools/headless.sh exits 0 only when the script finished or asked to quit,
# and both of these scripts end with @quit. Every other status -- 3 out of
# keys, 4 watchdog, 5 no gameplay, 6 a screen that never appeared, 7 an
# unlisted assertion -- means the session diverged from what this check thinks
# it measured, so nothing it left behind can be trusted. That is INCONCLUSIVE
# and not FAIL: a broken session says nothing about the bug either way, which
# is the distinction inc-loa.3 was filed over.
#
# WHY THIS IS NOT COVERED BY THE DUMP-EXISTENCE GUARDS BELOW. They fire on a
# run that never REACHED the screen. A run that reached it, dumped all four
# screens and THEN died -- in Part A's UP*40 tail, which empties the pool --
# satisfies every one of them. Found in review, 2026-09-07.
session_ended_well() {
    local status=$1 output=$2 dir=$3 part=$4
    [ "$status" -eq 0 ] && return 0
    echo "INCONCLUSIVE: the $part session did not end cleanly (exit $status), so"
    echo "              whatever it left behind cannot be read as a measurement."
    printf '%s\n' "$output" | sed -n '/^ended:/,/^[a-z]/p' | sed 's/^/              /'
    echo "              Run dir: $dir"
    return 1
}

echo "--- Part A: character generation, pool not empty ---"
out="$(INCURSION_OPTIONS="$OPTS" tools/headless.sh tools/keys/skill-manager-reset.keys "$SEED" 2>&1)"
rc=$?
run="$(echo "$out" | awk '/^run:/ {print $2}')"
S="$run/logs/screens"
session_ended_well "$rc" "$out" "$run" "Part A" || exit 2

for f in 0001-before 0002-after-end 0003-after-home 0004-after-esc-no; do
    [ -f "$S/$f.txt" ] || {
        echo "INCONCLUSIVE: the session produced no $f screen. Run dir: $run"
        exit 2
    }
done

# Did the run reach the Skill Manager, and did the RIGHT keys reach it? Without
# both, a screen that never changes proves nothing: an empty allocation column
# survives an unlisted key as happily as a full one does.
grep -q "Skill Manager" "$S/0001-before.txt" || {
    echo "INCONCLUSIVE: the run never reached the Skill Manager. Run dir: $run"
    exit 2
}
allocated=$(grep -cE '\|(  |> )(Athletics|Climb|Craft) +[0-9]+ .*\*\*' "$S/0001-before.txt")
if [ "$allocated" -ne 3 ]; then
    echo "INCONCLUSIVE: the run placed ranks in $allocated of the 3 expected skills,"
    echo "              so there was nothing for the unlisted key to destroy."
    echo "              Run dir: $run"
    exit 2
fi

# The first line of a dump names the key number, which differs between the
# three screens by design. Everything below it must not.
for f in 0002-after-end 0003-after-home; do
    key=$(echo "$f" | sed 's/^[0-9]*-after-//' | tr '[:lower:]' '[:upper:]')
    if ! diff -q <(tail -n +2 "$S/0001-before.txt") <(tail -n +2 "$S/$f.txt") >/dev/null; then
        echo "FAIL: $key changed the Skill Manager screen. It is not a key this"
        echo "      screen knows, so it must do nothing. Diff (before -> after):"
        diff <(tail -n +2 "$S/0001-before.txt") <(tail -n +2 "$S/$f.txt") | sed 's/^/      /'
        fail=1
    fi
done

esc_alloc=$(grep -cE '\|(  |> )(Athletics|Climb|Craft) +[0-9]+ .*\*\*' "$S/0004-after-esc-no.txt")
if [ "$esc_alloc" -ne 3 ]; then
    echo "FAIL: a DECLINED ESC left ranks in only $esc_alloc of the 3 skills."
    echo "      Answering 'n' to \"Abort, and discard the ranks placed here?\""
    echo "      must change nothing at all."
    fail=1
fi
if ! grep -qE '\|  \* +\|' "$S/0004-after-esc-no.txt"; then
    echo "FAIL: a DECLINED ESC did not leave the unspent pool at one rank."
    echo "      Pool line after the decline:"
    sed -n '10p' "$S/0004-after-esc-no.txt" | sed 's/^/      /'
    fail=1
fi

# --------------------------------------------------------------- Part B ------
echo
echo "--- Part B: level-up, pool empty ---"
outB="$(INCURSION_OPTIONS="$OPTS" tools/headless.sh tools/keys/skill-manager-levelup.keys "$SEED" 2>&1)"
rcB=$?
runB="$(echo "$outB" | awk '/^run:/ {print $2}')"
B="$runB/logs/screens"
session_ended_well "$rcB" "$outB" "$runB" "Part B" || exit 2

for f in 0001-open 0002-after-end 0003-after-home 0004-after-esc; do
    [ -f "$B/$f.txt" ] || {
        echo "INCONCLUSIVE: the level-up session produced no $f screen. Run dir: $runB"
        exit 2
    }
done

# The manager must have opened at all, and it must have opened on the level-up
# path. An empty pool line is what tells the two apart: character generation
# never reaches this screen with nothing left to spend.
grep -q "Skill Manager" "$B/0001-open.txt" || {
    echo "INCONCLUSIVE: [S] on the character sheet did not open the Skill Manager."
    echo "              Run dir: $runB"
    exit 2
}
if grep -qE '\|  \*+ +\|' "$B/0001-open.txt"; then
    echo "INCONCLUSIVE: the level-up run opened the manager with ranks still in the"
    echo "              pool, so it measured Part A over again, not Part B."
    echo "              Run dir: $runB"
    exit 2
fi

for f in 0002-after-end 0003-after-home; do
    key=$(echo "$f" | sed 's/^[0-9]*-after-//' | tr '[:lower:]' '[:upper:]')
    if ! grep -q "Skill Manager" "$B/$f.txt"; then
        echo "FAIL: $key closed the Skill Manager at level-up. It is not a key this"
        echo "      screen knows, so it must not be an exit. The screen it left behind:"
        sed -n '2,12p' "$B/$f.txt" | sed 's/^/      /'
        fail=1
    elif ! diff -q <(tail -n +2 "$B/0001-open.txt") <(tail -n +2 "$B/$f.txt") >/dev/null; then
        echo "FAIL: $key changed the level-up Skill Manager screen."
        diff <(tail -n +2 "$B/0001-open.txt") <(tail -n +2 "$B/$f.txt") | sed 's/^/      /'
        fail=1
    fi
done

# ESC is the one key that MAY leave this screen, and the run answered its
# question with 'y'. If the manager is still up, ESC stopped working; if it
# never asked, the confirmation is not there and the run would have hung on
# the 'y' instead.
if grep -q "Skill Manager" "$B/0004-after-esc.txt"; then
    echo "FAIL: ESC answered 'y' did not leave the level-up Skill Manager."
    fail=1
fi

echo
if [ "$fail" -ne 0 ]; then
    echo "SKILL MANAGER RESET: FAIL. Runs: $run"
    echo "                                 $runB"
    exit 1
fi
echo "PASS: both halves. At chargen END and HOME left the screen untouched and a"
echo "      declined ESC kept all three allocations and the pool; at level-up"
echo "      neither key closed the manager and ESC still did."
echo "      Runs: $run"
echo "            $runB"
exit 0
