#!/bin/bash
# gate: live
# Does the law/chaos half of Character::AlignedAct behave like the good/evil
# half it is written beside? (bd inc-r6ae)  Round 2: each law/chaos case is
# asserted against its good/evil twin FROM THE SAME RUN, so the check reads
# the difference between the two halves rather than a hard-coded outcome.
#
# THE CLAIM UNDER TEST. In src/Prayer.cpp, the good/evil half sets the
# AL_GOOD/AL_EVIL flag when its score crosses the threshold:
#
#     if (alignGE > -20) nAlign &= (~AL_GOOD); else nAlign |= AL_GOOD;
#     if (alignGE <  20) nAlign &= (~AL_EVIL); else nAlign |= AL_EVIL;
#
# The law/chaos half does not. It only CLEARS AL_LAWFUL/AL_CHAOTIC:
#
#     if (alignLC > -20) nAlign &= (~AL_LAWFUL);
#     if (alignLC <  20) nAlign &= (~AL_CHAOTIC);
#
# There is no else branch, so no act can ever set either flag. The neutral
# law/chaos branches also differ from their twins: the chaotic branch does
# alignLC -= (the wrong direction), and the committed-chaotic branch clamps
# with max(30, alignLC) where the committed-evil branch uses min(30, ...).
#
# DESIGNED CLAMPS, NOT DEFECTS. Both halves clamp the score when the
# character does not desire the alignment ("if (!(dAlign & AL_...))"). The
# neutral-*-desired cases below therefore set a non-zero desiredAlign, so
# that clamp does not fire and what is read is the flag, not the clamp.
# This check does NOT touch or assert on those clamps.
#
# THE ORACLE is INCURSION_ALIGN_PROBE, arming Character::AlignLawChaosProbe()
# (src/Prayer.cpp), run once from Game::Play() (src/Main.cpp). It fires five
# acts of 10 points each on each of six cases and logs BOTH axes through
# Error() into logs/errors.log as
#
#   ALIGN_PROBE case=<name> acts=5 alignLC=.. alignGE=.. align=0x..
#                    lawful=.. chaotic=.. good=.. evil=..
#
#   law/chaos case        twin control
#   --------------------  --------------------
#   neutral-lawful-desired  neutral-good-desired
#   neutral-chaotic-desired neutral-evil-desired
#   chaotic-leaving         evil-leaving
#
# Five acts of 10 move a neutral score to 50 and a committed score (started
# at 60) to 10 or 0, all well past the 20-point threshold.
#
# WHAT IS ASSERTED, per case, matching the twin's outcome in the SAME run:
#   flags   the law/chaos flag (lawful=/chaotic=) is set exactly when the
#           twin's good/evil flag (good=/evil=) is set;
#   sign    the score moved in the same direction as the twin's (or both
#           stayed put);
#   leave   for the leaving cases, the score is not pinned (|score| >= 20)
#           when the twin's is not.
# A missing law/chaos line is a FAIL, never a pass. A twin that does not show
# its own expected designed behaviour is ALSO a FAIL, so a broken probe or a
# mutated good/evil half cannot let the check pass.
#
# On the current code the neutral-chaotic-desired twin (neutral-evil-desired)
# sets evil=1 while chaotic stays 0, and the leaving twin is not pinned while
# chaotic-leaving is, so this check is RED -- that is the reproduction.
#
# Usage: tools/check_align_lawchaos.sh   (0 pass, 1 fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${SEED:-1}"
KEYS=tools/keys/align-lawchaos-probe.keys
BIN="${INCURSION_BIN:-./incursion-headless}"
OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22.dat}"

[ -x "$BIN" ] || {
    echo "FAIL: $BIN not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

export INCURSION_ALIGN_PROBE=1
out="$(INCURSION_OPTIONS="$OPTIONS" tools/headless.sh "$KEYS" "$SEED" 2>&1 </dev/null)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

if [ -z "$run" ]; then
    echo "FAIL: the harness reported no run directory."
    echo "$out"
    exit 1
fi
LOG="$run/logs/errors.log"

# Drop the indented backtrace blocks headless.sh attaches; they quote the
# message text and would otherwise be read as extra probe lines.
line_for() { # <case> -> the probe line, or empty
    awk -v c="ALIGN_PROBE case=$1 " '!/^    / && index($0, c) { print; exit }' "$LOG" 2>/dev/null
}

field() { # <line> <name> -> value, or empty
    echo "$1" | grep -oE "$2=-?[0-9]+" | head -1 | sed "s/$2=//"
}

need_line() { # <case> -> echoes the line or fails
    local l
    l="$(line_for "$1")"
    if [ -z "$l" ]; then
        echo "FAIL: no probe line for case=$1 in $LOG. No line is a FAIL," >&2
        echo "      never a pass." >&2
        echo "$out" | tail -20 >&2
        exit 1
    fi
    echo "$l"
}

lc_line_law="$(need_line neutral-lawful-desired)"
lc_line_chaos="$(need_line neutral-chaotic-desired)"
lc_line_leave="$(need_line chaotic-leaving)"
ge_line_good="$(need_line neutral-good-desired)"
ge_line_evil="$(need_line neutral-evil-desired)"
ge_line_leave="$(need_line evil-leaving)"

for l in "$lc_line_law" "$lc_line_chaos" "$lc_line_leave" \
         "$ge_line_good" "$ge_line_evil" "$ge_line_leave"; do
    echo "  probe: $l"
done

fail=0

check_field() { # <line> <name> <case> -> echoes value or records fail
    local v
    v="$(field "$1" "$2")"
    if [ -z "$v" ]; then
        echo "FAIL: case=$3 carried no $2= field to read." >&2
        echo "  $1" >&2
        fail=1
    fi
    echo "$v"
}

# --- Twin sanity: the good/evil half must show its own designed behaviour,
# --- so a broken probe or a mutated G/E half cannot let the check pass.

ne_good="$(check_field "$ge_line_good" good neutral-good-desired)"
ne_good_ge="$(check_field "$ge_line_good" alignGE neutral-good-desired)"
ne_evil="$(check_field "$ge_line_evil" evil neutral-evil-desired)"
ne_evil_ge="$(check_field "$ge_line_evil" alignGE neutral-evil-desired)"
ne_leave="$(check_field "$ge_line_leave" evil evil-leaving)"
ne_leave_ge="$(check_field "$ge_line_leave" alignGE evil-leaving)"

if [ "$ne_good" != 1 ] || [ "$ne_evil" != 1 ]; then
    echo "FAIL: the good/evil twin controls did not show their designed"
    echo "      behaviour (neutral-good-desired good=$ne_good,"
    echo "      neutral-evil-desired evil=$ne_evil). The twin is the",
    echo "      yardstick; a broken probe or a mutated good/evil half is a FAIL."
    fail=1
fi
if [ "$ne_good_ge" -ge 0 ] 2>/dev/null; then
    echo "FAIL: neutral-good-desired score did not go negative (alignGE=$ne_good_ge)."
    fail=1
fi
if [ "$ne_evil_ge" -le 0 ] 2>/dev/null; then
    echo "FAIL: neutral-evil-desired score did not go positive (alignGE=$ne_evil_ge)."
    fail=1
fi
if [ "$ne_leave" != 0 ]; then
    echo "FAIL: evil-leaving unexpectedly set evil=$ne_leave; the leaving twin"
    echo "      should leave the character not Evil."
    fail=1
fi
if [ "$ne_leave_ge" -le -20 ] 2>/dev/null; then
    echo "FAIL: evil-leaving twin is pinned at alignGE=$ne_leave_ge (<=-20);"
    echo "      the intended twin unpins to 0, so the yardstick is wrong."
    fail=1
fi

# --- neutral-lawful-desired  <=>  neutral-good-desired
lc_law="$(check_field "$lc_line_law" lawful neutral-lawful-desired)"
lc_law_lc="$(check_field "$lc_line_law" alignLC neutral-lawful-desired)"

if [ "$lc_law" != "$ne_good" ]; then
    echo "FAIL: neutral-lawful-desired left lawful=$lc_law but its twin"
    echo "      neutral-good-desired left good=$ne_good. A neutral character"
    echo "      can become Good through acts but not Lawful. (bd inc-r6ae)"
    fail=1
fi
# Lawful acts must drive alignLC down, the same way good acts drive alignGE
# down (both toward a lawful/good alignment). A positive result is wrong.
if [ "$lc_law_lc" -gt 0 ] 2>/dev/null && [ "$ne_good_ge" -gt 0 ] 2>/dev/null; then
    echo "FAIL: neutral-lawful-desired moved alignLC=$lc_law_lc (away from"
    echo "      law) while its twin moved toward good (alignGE=$ne_good_ge)."
    fail=1
fi

# --- neutral-chaotic-desired  <=>  neutral-evil-desired
lc_chaos="$(check_field "$lc_line_chaos" chaotic neutral-chaotic-desired)"
lc_chaos_lc="$(check_field "$lc_line_chaos" alignLC neutral-chaotic-desired)"
ge_evil_ge="${ne_evil_ge}"

if [ "$lc_chaos" != "$ne_evil" ]; then
    echo "FAIL: neutral-chaotic-desired left chaotic=$lc_chaos but its twin"
    echo "      neutral-evil-desired left evil=$ne_evil. A neutral character"
    echo "      can become Evil through acts but not Chaotic. (bd inc-r6ae)"
    fail=1
fi
# The evil twin's score goes UP (positive); the chaotic case must too.
if [ "$lc_chaos_lc" -le 0 ] 2>/dev/null && [ "$ge_evil_ge" -gt 0 ] 2>/dev/null; then
    echo "FAIL: neutral-chaotic-desired moved alignLC=$lc_chaos_lc (the wrong"
    echo "      way) while its twin moved toward evil (alignGE=$ge_evil_ge)."
    fail=1
fi

# --- chaotic-leaving  <=>  evil-leaving
lc_leave="$(check_field "$lc_line_leave" chaotic chaotic-leaving)"
lc_leave_lc="$(check_field "$lc_line_leave" alignLC chaotic-leaving)"

if [ "$lc_leave" != "$ne_leave" ]; then
    echo "FAIL: chaotic-leaving left chaotic=$lc_leave but its twin"
    echo "      evil-leaving left evil=$ne_leave. (bd inc-r6ae)"
    fail=1
fi
# The twin unpins to 0 (|GE|<20); the law/chaos half must not stay pinned.
if [ "$lc_leave_lc" -ge 20 ] 2>/dev/null && [ "$ne_leave_ge" -lt 20 ] 2>/dev/null; then
    echo "FAIL: chaotic-leaving is pinned at alignLC=$lc_leave_lc (>=20) while"
    echo "      its twin evil-leaving unpinned to alignGE=$ne_leave_ge. The"
    echo "      evil twin uses min(30,...); the chaos half uses max(30,...)."
    echo "      (bd inc-r6ae)"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: every law/chaos case matched its good/evil twin in the same"
    echo "      run (flag, score direction, and leaving-case pinning)."
fi
exit "$fail"
