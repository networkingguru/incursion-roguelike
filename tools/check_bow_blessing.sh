#!/bin/bash
# gate: live
# An altar blessing gives the god's chosen weapon quality to BOWS and
# AMMUNITION, not only to T_WEAPON melee arms. (bd inc-rnp9)
#
# THE DEFECT. Character::IBlessing (src/Prayer.cpp) chose the quality with
# `if (e.EItem->isType(T_WEAPON))`. isType is an EXACT type match
# (inc/Base.h), so a bow, crossbow, sling or blowpipe (T_BOW) and an arrow,
# bolt, dart or sling stone (T_MISSILE) fell through with qual = 0 and were
# only blessed ("soft blue light"). Two live gods are hit: Maeve (short bow,
# WQ_CHAOTIC) and Xavias (arbalest, WQ_QUICK_LOADING); the isChosen*4
# allowance was likewise unreachable for a bow.
#
# THE FIX widens that one test to `isType(T_WEAPON) || isType(T_BOW) ||
# isType(T_MISSILE)` -- the same idiom src/Item.cpp's RemoveQuality already
# uses. It is deliberately NOT isWeapon(): T_STAFF is also built as class
# Weapon and staffs are ruled out. QualityOK still decides which quality is
# legal on which item, and nothing else in the function changed.
#
# THE ORACLE is INCURSION_IBLESSING_PROBE, which arms
# Character::IBlessingProbe() (src/Prayer.cpp), run once at the top of
# Game::Play() on the live loaded player (src/Main.cpp). It builds a +1 item
# of each weapon type, makes the player a follower of the named god with
# ample favour (FavourLev 9, so ItemLevel cannot block the quality), and
# calls Character::IBlessing exactly as the altar path does. Four cases:
#
#   arbalest      Xavias    must gain WQ_QUICK_LOADING (WT_CROSSBOW item)
#   short bow     Maeve     must gain WQ_CHAOTIC
#   long sword    Asherath  must gain WQ_ACCURACY  (the unchanged melee path)
#   crossbow bolt Maeve     must gain WQ_CHAOTIC  (a legal chosen quality on
#                           T_MISSILE: QualityOK rules out WQ_QUICK_LOADING
#                           because a bolt has no WT_CROSSBOW, and allows
#                           WQ_CHAOTIC, so the ammunition case uses Maeve)
#
# Each case is narrated through Error() as
# "IBLESSING_PROBE case=<item> god=<god> qual=<n> plus=<n> has=<0|1> PASS|FAIL",
# the same errors.log channel check_xp_drain.sh and check_mana_regen_floor.sh
# read. A run whose cases are missing, INCONCLUSIVE, or carry no has= field
# is a FAIL, never a pass: a green result from a session that never reached
# the state under test is the mistake this directory guards against
# (inc-loa.3).
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation
# below restores the base-code exact-type test; the arbalest, short bow and
# bolt cases then log has=0 and this check exits 1.
#
# Usage: tools/check_bow_blessing.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

SEED=1
KEYS=tools/keys/load-char-sheet.keys

# The mutation this check defends: the base-code test, read directly off
# Character::IBlessing before this fix. Declared before the run below so
# --prove-red intercepts here, before the (build-needing) measurement runs.
check_mutation src/Prayer.cpp \
'    if (e.EItem->isType(T_WEAPON) || e.EItem->isType(T_BOW) ||
        e.EItem->isType(T_MISSILE))' \
'    if (e.EItem->isType(T_WEAPON))'

export INCURSION_IBLESSING_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav

check_run "$KEYS" "$SEED"

LOG="$CHECK_RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 \
    "the run logged nothing at all. The probe reports through Error()," \
    "so an empty log means it never ran."

# Drop the indented backtrace blocks headless.sh attaches to a first
# occurrence; they quote the message text and would be counted twice.
CLEAN="$(grep -v '^    ' "$LOG")"

FAIL=0
declare -a CASES=(arbalest "short bow" "long sword" "crossbow bolt")
declare -a SUMMARIES=()

# Read one case's has= field, or empty when the line is absent or malformed.
_case_line() { # <item> -> the probe line, or nothing
    printf '%s\n' "$CLEAN" | grep "IBLESSING_PROBE case=$1 " | head -1
}

for item in "${CASES[@]}"; do
    line="$(_case_line "$item")"
    if [ -z "$line" ]; then
        echo "FAIL: no IBLESSING_PROBE line for case '$item'."
        echo "      Is Character::IBlessingProbe() still called from"
        echo "      Game::Play() (src/Main.cpp), and does this build contain it?"
        FAIL=1
        continue
    fi
    if printf '%s\n' "$line" | grep -q INCONCLUSIVE; then
        echo "FAIL: the '$item' case was INCONCLUSIVE:"
        echo "      $line"
        FAIL=1
        continue
    fi
    has="$(printf '%s\n' "$line" | grep -oE 'has=-?[0-9]+' | sed 's/has=//')"
    plus="$(printf '%s\n' "$line" | grep -oE 'plus=-?[0-9]+' | sed 's/plus=//')"
    if [ -z "$has" ] || [ -z "$plus" ]; then
        echo "FAIL: could not parse has/plus out of the '$item' line:"
        echo "      $line"
        FAIL=1
        continue
    fi
    SUMMARIES+=("$line")
    if [ "$has" -ne 1 ]; then
        echo "FAIL: the +$plus '$item' did not gain its god's chosen quality:"
        echo "      $line"
        FAIL=1
    fi
done

echo
echo "--- what the probe logged ---"
for line in "${SUMMARIES[@]}"; do echo "$line"; done
echo "specimen: $LOG"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi

# Belt and braces: every case above passed, so nothing may report FAIL.
if printf '%s\n' "${SUMMARIES[@]}" | grep -q ' FAIL$'; then
    echo "FAIL: a case line still ends in FAIL."
    exit 1
fi

echo
echo "PASS: seed $SEED -- Xavias's arbalest gained WQ_QUICK_LOADING, Maeve's"
echo "      short bow and a stack of crossbow bolts gained WQ_CHAOTIC, and"
echo "      Asherath's long sword kept WQ_ACCURACY (the unchanged melee path)."
exit 0
