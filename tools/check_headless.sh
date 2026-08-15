#!/bin/bash
# Regression check for the headless backend (src/Wposix.cpp, inc-73g).
#
# What it protects. Everything else in this project that runs without a person
# depends on three properties, and each of them is easy to lose by accident:
#
#   1. A scripted session runs to the end with no display and no keyboard,
#      and ends by itself. A backend that blocks waiting for a key would hang
#      a nightly run instead of failing it.
#   2. The screen dump is a real picture of the game. A dump of an empty
#      buffer would still be a file, would still be 48 lines long, and would
#      still tell you nothing.
#   3. The same seed plays the same game. Without that a dump cannot be
#      compared with an earlier one, so no regression can ever be detected --
#      and the failure is silent, because every individual run still passes.
#
# Each assertion below is exercised against known-bad input by --selftest, so
# a check that has quietly stopped testing anything says so.
#
# Usage: tools/check_headless.sh              (exits 0 on pass, 1 on fail)
#        tools/check_headless.sh --selftest   (proves the assertions bite)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

SEED=1
KEYS="tools/keys/smoke.keys"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --- the assertions, as functions, so --selftest can feed them bad input ----

# A dump is a picture of the game only if the player and the floor are both in
# it. '@' alone is not enough: a status line could carry one.
assert_shows_map() { # <dumpfile>
    grep -q '@' "$1" && grep -qE '\.\.\.\.' "$1"
}

assert_reproducible() { # <dirA> <dirB>
    diff -r "$1" "$2" > /dev/null 2>&1
}

if [ "${1:-}" = "--selftest" ]; then
    echo "--- selftest: each assertion must reject known-bad input ---"
    ok=0

    printf 'HP:42/42 Mana:14\nnothing here\n' > "$WORK/nomap.txt"
    if assert_shows_map "$WORK/nomap.txt"; then
        echo "SELFTEST FAIL: the map assertion accepted a screen with no map"
        ok=1
    else
        echo "  map assertion rejects a screen with no map: good"
    fi

    printf '=== screen ===\n....@....\n....\n' > "$WORK/map.txt"
    if assert_shows_map "$WORK/map.txt"; then
        echo "  map assertion accepts a screen with a map: good"
    else
        echo "SELFTEST FAIL: the map assertion rejected a real map"
        ok=1
    fi

    mkdir -p "$WORK/a" "$WORK/b"
    printf 'one\n' > "$WORK/a/s.txt"
    printf 'two\n' > "$WORK/b/s.txt"
    if assert_reproducible "$WORK/a" "$WORK/b"; then
        echo "SELFTEST FAIL: the reproducibility assertion accepted two different runs"
        ok=1
    else
        echo "  reproducibility assertion rejects two different runs: good"
    fi

    cp "$WORK/b/s.txt" "$WORK/a/s.txt"
    if assert_reproducible "$WORK/a" "$WORK/b"; then
        echo "  reproducibility assertion accepts two identical runs: good"
    else
        echo "SELFTEST FAIL: the reproducibility assertion rejected two identical runs"
        ok=1
    fi

    [ "$ok" -eq 0 ] && echo "PASS: the assertions bite" && exit 0
    exit 1
fi

# --- the check itself --------------------------------------------------------

if [ ! -x ./incursion-headless ]; then
    fail "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
fi

# 1. It runs to the end on its own, with no terminal of any kind.
INCURSION_RUN_DIR="$WORK/run1" ./tools/headless.sh "$KEYS" "$SEED" > "$WORK/out1" 2>&1 < /dev/null
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    echo "--- session output ---"
    tail -20 "$WORK/out1"
    case $STATUS in
        4) fail "the session hit the watchdog: the game stopped asking for keystrokes" ;;
        1) fail "the session ended in Fatal()" ;;
        *) fail "the session exited $STATUS, wanted 0" ;;
    esac
fi

# 2. It photographed the game, and the photograph has a map in it.
LAST="$(ls "$WORK/run1/logs/screens"/*walked* 2>/dev/null | tail -1)"
if [ -z "$LAST" ]; then
    fail "no screen was dumped; the run never reached the walk"
elif ! assert_shows_map "$LAST"; then
    echo "--- last screen ---"
    sed -n '1,20p' "$LAST"
    fail "the last screen has no map on it (no player, or no floor)"
fi

# 3. The same seed plays the same game.
INCURSION_RUN_DIR="$WORK/run2" ./tools/headless.sh "$KEYS" "$SEED" > "$WORK/out2" 2>&1 < /dev/null
if ! assert_reproducible "$WORK/run1/logs/screens" "$WORK/run2/logs/screens"; then
    echo "--- what differs ---"
    diff -r "$WORK/run1/logs/screens" "$WORK/run2/logs/screens" | head -20
    fail "two runs of the same script and seed drew different screens"
fi

# 4. A different seed must play a different game, or the seed is being ignored
#    and assertion 3 above would pass on a build that had lost it entirely.
INCURSION_RUN_DIR="$WORK/run3" ./tools/headless.sh "$KEYS" 99 > "$WORK/out3" 2>&1 < /dev/null
if assert_reproducible "$WORK/run1/logs/screens" "$WORK/run3/logs/screens"; then
    fail "two different seeds drew identical screens; the seed is being ignored"
fi

# 5. A session that never reaches gameplay must NOT report success. An empty
#    key script runs the game out of keys at the very first prompt, so it exits
#    having generated no character and entered no map -- and the game's own exit
#    code for that is 0. Before the harness promoted it, soak.sh counted such a
#    session as "clean", and 250 of them were once read as evidence that a fix
#    worked. This assertion is the reason that cannot happen again.
printf '# no keys at all: the session must not reach a map\n' > "$WORK/empty.keys"
INCURSION_RUN_DIR="$WORK/run4" ./tools/headless.sh "$WORK/empty.keys" "$SEED" \
    > "$WORK/out4" 2>&1 < /dev/null
STATUS=$?
if [ "$STATUS" -ne 5 ]; then
    echo "--- session output ---"
    tail -10 "$WORK/out4"
    fail "a session that never entered a map exited $STATUS, wanted 5 (NO GAMEPLAY)"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: a scripted session runs unattended, draws a map, repeats itself,"
    echo "      and a session that plays nothing is reported as playing nothing"
    exit 0
fi
exit 1
