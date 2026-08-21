#!/bin/bash
# Regression check for Character::XPPenalty (src/Create.cpp), bd inc-5y8.
#
# WHAT WAS WRONG. XPPenalty asks, for each of a character's three class slots,
# whether that class is a favoured class of his race. The last clause of each
# test reads
#
#     TCLASS(ClassID[n])->HasFlag(CF_FAVOURED)
#
# and TCLASS is a cast of Game::Get, which returns NULL for a zero id
# (src/Res.cpp:312). A character who holds fewer than three classes has a zero
# in the unused slots, so the test dereferenced NULL and the process died with
# SIGSEGV, exit 139, at EXC_BAD_ACCESS 0x4d.
#
# It needed no wizard mode and no unusual play. Two classes were enough,
# provided neither of the first two blocks returned first, and the sheet is
# drawn by pressing 'd' (src/Sheet.cpp:62). XPPenalty is also called on every
# XP gain (src/Create.cpp:2008), so the same character could not have earned
# experience either. Brian met it on an Elf Rogue 3 / Twilight Huntsman 1.
#
# THE ORACLE is the run itself, and it is a hard one: the pre-fix build could
# not reach the end of this key script at all. The assertion is in two parts,
# and both are needed.
#
#   THE EXIT STATUS. 139 is the shell's report of SIGSEGV. Any 139 from this
#   script means the crash is back. This is the half that catches a regression.
#
#   THE SHEET. A run can exit 0 and still have measured nothing -- the key
#   script may have stopped building the character long before the sheet was
#   ever asked for. So the dump must exist and must carry the two-class sheet.
#   Without this half, deleting the key script's contents would make the check
#   pass. See tools/check_headless.sh for the same trap in its original form.
#
# THE CHARACTER, and why this one. tools/keys/xp-penalty-crash.keys builds a
# Wood Elf Rogue 2 / Warrior 1 on seed 7 and then asks for his sheet. He is the
# smallest character that reaches the third block:
#
#   - Wood elves favour Barbarian, Ranger and Druid (lib/subraces.irh:498), so
#     the rogue matches none of the three favoured ids and does not carry
#     CF_FAVOURED. The first block does not return.
#   - The warrior does not carry CF_FAVOURED either. The second block does not
#     return.
#   - The third block then reads class slot 2, which is empty, and the old
#     build died there.
#
# A single-classed character proves nothing here: the early return at
# src/Create.cpp:2184 catches him before any of the three blocks runs. Two
# classes are the minimum, and the first of them must not be favoured.
#
# Measured on builds differing only in src/Create.cpp:
#                                    before          after
#   exit status                      139 (SIGSEGV)   0
#   dump written                     none            "Class  Rogue 2 / Warrior 1"
#
# Usage: tools/check_xp_penalty.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=7
KEYS=tools/keys/xp-penalty-crash.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}
[ -f "$KEYS" ] || {
    echo "FAIL: $KEYS is missing, so nothing can be measured."
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
STATUS=$?
RUN="$(printf '%s\n' "$OUT" | awk '/^run:/ {print $2}')"

if [ "$STATUS" -eq 139 ]; then
    echo "FAIL: the session died of SIGSEGV (exit 139). inc-5y8 is back:"
    echo "      Character::XPPenalty dereferenced an empty class slot."
    echo "      run: $RUN"
    exit 1
fi

# Guard. A key script that has stopped producing the character must read as
# rotted, not as a passing test -- a clean exit on its own measures nothing.
DUMP="$(ls "$RUN"/logs/screens/*-crashed.txt 2>/dev/null | head -1)"
if [ -z "$DUMP" ]; then
    echo "INCONCLUSIVE: no character dump was written under $RUN/logs/screens,"
    echo "              so $KEYS has rotted. Nothing was measured."
    echo "FAIL: tools/check_xp_penalty.sh"
    exit 1
fi
if ! grep -q "Rogue 2" "$DUMP" || ! grep -q "Warrior 1" "$DUMP"; then
    echo "INCONCLUSIVE: the dump is not a Rogue 2 / Warrior 1 sheet, so $KEYS"
    echo "              no longer builds the two-class character this checks."
    echo "              Nothing was measured. dump: $DUMP"
    echo "FAIL: tools/check_xp_penalty.sh"
    exit 1
fi

if [ "$STATUS" -ne 0 ]; then
    echo "FAIL: the session ended with exit $STATUS, not 0. run: $RUN"
    exit 1
fi

echo "PASS: a two-class character reads his own sheet without a segfault"
exit 0
