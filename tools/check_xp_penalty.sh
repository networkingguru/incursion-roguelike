#!/bin/bash
# gate: live
# Regression check for Character::XPPenalty (src/Create.cpp), bd inc-5y8.
#
# WHAT WAS WRONG. XPPenalty walks a character's three class slots and asks
#
#     TCLASS(ClassID[n])->HasFlag(...)
#
# of each slot it does not skip. TCLASS is a cast of Game::Get, which returns
# NULL for a zero id (src/Res.cpp:320). A character who holds fewer than three
# classes has a zero id in each unused slot, so the original dereferenced NULL
# and the process died with SIGSEGV, exit 139, at EXC_BAD_ACCESS 0x4d. The fix
# is the guard at the top of the loop, which skips an empty slot.
#
# It needed no wizard mode and no unusual play. The sheet calls XPPenalty
# (src/Sheet.cpp:62), and so does every XP gain (src/Create.cpp:2095), so the
# same character could not have earned experience either. Brian met it on an
# Elf Rogue 3 / Twilight Huntsman 1.
#
# THE ORACLE is the run itself, and it is a hard one: the pre-fix build could
# not reach the end of this key script at all. The assertion is in two parts,
# and both are needed.
#
#   THE EXIT STATUS. 139 is the shell's report of SIGSEGV. Any 139 from this
#   script means the crash is back. This is the half that catches a regression.
#   Any other non-zero exit fails too, so the key script plays one turn after
#   the dump: tools/headless.sh exits 5, NO GAMEPLAY, for a run with none.
#
#   THE SHEET. A run can exit 0 and still have measured nothing -- the key
#   script may have stopped building the character long before the sheet was
#   ever asked for. So the dump must exist and must carry the two-class sheet.
#   Without this half, deleting the key script's contents would make the check
#   pass. See tools/check_headless.sh for the same trap in its original form.
#
# THE CHARACTER is the fixture wood-elf-rogue-seed7-opt0818, a Wood Elf Rogue 1
# that the check LOADS (INCURSION_LOAD); tools/keys/wood-elf-rogue-save.keys
# built it. tools/keys/xp-penalty-crash.keys then levels him to Rogue 2 /
# Warrior 1 by wizard switch and asks for his sheet. A built character was
# seed-dependent: the rolled Int set the skill-rank count, and on seeds 202
# and 303 the fixed spending desynced. Wood elves favour Barbarian, Ranger and
# Druid (lib/subraces.irh:498). All three ids are non-zero, so an empty slot
# matches none of them and, without the guard, reaches TCLASS. An orc has only
# two favoured classes, so it would hide the crash. His third slot is empty.
# One class is enough to reach it: in the proved-red run below, the build died
# at the key script's first sheet, while he was still Rogue 1. The second class
# stays because the sheet half of the assertion looks for it.
#
# fact: character (Wood Elf Rogue 1) -- fixture wood-elf-rogue-seed7-opt0818 (INCURSION_LOAD)
# fact: arrival map -- the same fixture (a save pins the dungeon)
# fact: settings, including OPT_FAVOURED_CLASS, which would return before the class loop -- tools/fixtures/options-2026-08-18.dat (INCURSION_OPTIONS)
# fact: Wood Elf has three non-zero favoured classes -- game data lib/subraces.irh:498
# fact: the level gains to Rogue 2 / Warrior 1 -- wizard switch and sheet [G], no dice
# fact: crash signal -- exit status 139
# fact: matched text "Rogue 2", "Warrior 1" -- fixed game strings
#
# PROVED RED on 2026-09-13 (bd inc-jnnp), on builds differing only in the
# guard at the top of the class loop in Character::XPPenalty,
# `if (!ClassID[n] || Level[n] <= 0) continue;`:
#                                    guard deleted   guard present
#   exit status                      139 (SIGSEGV)   0
#   dump written                     none            "Rogue 2", "Warrior 1"
#   this check                       exit 1          exit 0
#
# With the guard deleted, the check printed:
#
#   | FAIL: the session died of SIGSEGV (exit 139). inc-5y8 is back:
#   |       Character::XPPenalty dereferenced an empty class slot.
#
# The crash report put the fault at 0x4d in Character::XPPenalty under
# TextTerm::CreateCharSheet. Deleting only `!ClassID[n] ||` does NOT go red:
# the level test still skips an empty slot, because its level is zero.
#
# Usage: tools/check_xp_penalty.sh      (exits 0 on pass, 1 on fail,
#                                        2 when it could not measure)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=7
KEYS=tools/keys/xp-penalty-crash.keys
FIXTURE=tools/fixtures/chars/wood-elf-rogue-seed7-opt0818.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}
[ -f "$KEYS" ] || {
    echo "FAIL: $KEYS is missing, so nothing can be measured."
    exit 1
}

[ -f "$FIXTURE" ] || {
    echo "INCONCLUSIVE: the fixture $FIXTURE is missing. Nothing was measured."
    exit 2
}
export INCURSION_LOAD="$FIXTURE"

OUT="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-18.dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
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
    exit 2
fi
if ! grep -q "Rogue 2" "$DUMP" || ! grep -q "Warrior 1" "$DUMP"; then
    echo "INCONCLUSIVE: the dump is not a Rogue 2 / Warrior 1 sheet, so $KEYS"
    echo "              no longer builds the two-class character this checks."
    echo "              Nothing was measured. dump: $DUMP"
    exit 2
fi

if [ "$STATUS" -ne 0 ]; then
    echo "FAIL: the session ended with exit $STATUS, not 0. run: $RUN"
    exit 1
fi

echo "PASS: a two-class character reads his own sheet without a segfault"
exit 0
