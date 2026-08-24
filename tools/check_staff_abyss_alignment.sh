#!/bin/bash
# Is the Staff of the Abyss inert in a good character's hands, and still whole
# in a non-good one's? Finding PA-08-F8 of bd inc-tek.8.8.
#
# THE DEFECT. The staff's page says "A staff of the Abyss is an inert stick in
# the hands of any good character, or any character with less than five levels
# as an arcane or divine spellcaster". Its EV_MAGIC_HIT handler tested the
# caster level and nothing else, so a GOOD fifth-level caster got the whole
# item: the spell list, the +2 vampiric quarterstaff of terror, and the
# three-per-day vrock.
#
# WHY THE FIX DOES NOT COPY THE STAFF OF EXORCISM. The sibling entity holds
# what looks like the mechanism already:
#     if (!EActor->ItemPrereq(ALIGN_VAL + MA_GOOD,0,20))
#       return DONE;
# That call cannot work. Creature::ItemPrereq (src/Skills.cpp:5647-5728) has a
# branch for ABIL_VAL, FEAT_VAL, SKILL_VAL, MFLAG_VAL, MTYPE_VAL, ATTR_VAL and
# CLEV_VAL, and none at all for ALIGN_VAL. ALIGN_VAL is 9000
# (inc/Defines.h:2096), so ALIGN_VAL + MA_GOOD is 9106, which is below the
# 0xFFFF that sends an argument down the resource-id path, and the function
# falls through to its final "return false". The test is therefore false for
# everyone, so the Staff of Exorcism returns DONE for everyone and is inert in
# every hand -- a separate live defect, tracked as bd inc-tek.29. Copying it
# here would have changed nothing at all. This entity uses
# EActor->isMType(MA_GOOD) instead, which reads the ALIGNMENT stati directly
# (src/Values.cpp:2465-2468) and is how the rest of lib/ asks the question.
#
# THE ORACLE is wizard mode's "Examine Player Data", which prints every stati
# with its Val and its Mag (src/Debug.cpp:1524-1590). STAFF_SPELLS is the
# grant the entity has always made and the one the handler withholds, so its
# presence or absence IS the measurement. It renders with the underscore as a
# space: "STAFF SPELLS from SS ITEM (Val:0 Mag:0) [CL 5]".
#
# WHY TWO SESSIONS. An absence proves nothing on its own, and a gate written
# the wrong way round -- returning DONE for everyone who is NOT good -- would
# leave the good character exactly as empty-handed as a correct fix does,
# while locking out the evil characters the item exists for. So the check runs
# the same script twice over two characters who differ only in alignment, and
# demands the grant be ABSENT for the good one and PRESENT for the other.
# Nothing in wizard mode can change an alignment after generation
# (src/Debug.cpp:534-572 has no such option), which is why it is two sessions
# and not two readings of one character.
#
# Each session is also held to three preconditions before its reading counts:
# the sheet must say Mage 5, so the caster-level gate is open; the sheet must
# say the alignment the session was built for; and the staff must really be in
# the weapon hand. Without those, a run that failed during character
# generation would report "no staff spells" and look exactly like the fix.
#
# Usage: tools/check_staff_abyss_alignment.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
GRANT="STAFF SPELLS from SS ITEM"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# Run one half and print, on one line, the alignment the sheet showed and
# whether the staff granted its spells. Anything that makes the session
# unreadable exits the whole check as INCONCLUSIVE rather than returning a
# result that could be mistaken for a measurement.
measure() { # <keyscript> <alignment the sheet must show> -> "yes"|"no"
    local keys="$1" want_align="$2" out run scr sheet wielded align class
    out="$(tools/headless.sh "$keys" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if echo "$out" | grep -q "the key script looked for something"; then
        echo "INCONCLUSIVE: $keys could not find something on screen. Run: $run" >&2
        exit 2
    fi
    scr="$run/logs/screens"
    sheet="$scr/0001-sheet.txt"
    wielded="$scr/0002-staff-wielded.txt"
    for f in "$sheet" "$wielded"; do
        [ -f "$f" ] || {
            echo "INCONCLUSIVE: $keys dumped no screen at $f" >&2
            exit 2
        }
    done
    ls "$scr"/*-stati-*.txt >/dev/null 2>&1 || {
        echo "INCONCLUSIVE: $keys dumped no stati screens. Screens: $scr" >&2
        exit 2
    }

    # The sheet writes two columns on one row, so cut the attribute column off
    # before reading the field. Comparing the whole field and not a prefix is
    # deliberate: "Neutral" is a prefix of "Neutral Good", and confusing the
    # two would silently collapse the check's two halves into one.
    class="$(grep '^ Class ' "$sheet" | sed 's/CON:.*//; s/^ Class  *//; s/ *$//')"
    align="$(grep '^ Align ' "$sheet" | sed 's/LUC:.*//; s/^ Align  *//; s/ *$//')"
    [ "$class" = "Mage 5" ] || {
        echo "INCONCLUSIVE: $keys built a '$class', not a Mage 5, so the" >&2
        echo "              staff's caster-level-five gate was never open and" >&2
        echo "              this session measured nothing. Screen: $sheet" >&2
        exit 2
    }
    [ "$align" = "$want_align" ] || {
        echo "INCONCLUSIVE: $keys built a '$align' character and this half" >&2
        echo "              needs a '$want_align' one. Screen: $sheet" >&2
        exit 2
    }
    # A quarterstaff is two-handed, so the game shows the one staff on both
    # the Ready Hand and the Weapon Hand rows. Read the name back rather than
    # trusting the cursor-walked acquisition list to have stopped on it.
    grep -q "b)Weapon Hand.*Staff +2 of the Abyss" "$wielded" || {
        echo "INCONCLUSIVE: $keys put no Staff +2 of the Abyss in the Weapon" >&2
        echo "              Hand, so it measured the wrong item or none." >&2
        echo "              Screen: $wielded" >&2
        exit 2
    }

    if grep -qh "$GRANT" "$scr"/*-stati-*.txt; then echo yes; else echo no; fi
}

good="$(measure tools/keys/staff-abyss-alignment-good.keys "Neutral Good")"
nongood="$(measure tools/keys/staff-abyss-alignment-nongood.keys "Neutral")"

rc=0
if [ "$good" = yes ]; then
    echo "FAIL: a Neutral Good Mage 5 wielding the Staff of the Abyss still"
    echo "      holds the staff's spell grant, but its page calls the staff"
    echo "      'an inert stick in the hands of any good character'."
    rc=1
fi
if [ "$nongood" = no ]; then
    echo "FAIL: a Neutral Mage 5 wielding the Staff of the Abyss gets no spell"
    echo "      grant either. The gate is inverted: it is stopping the"
    echo "      non-good casters the item exists for."
    rc=1
fi

if [ "$rc" = 0 ]; then
    echo "  ok: the Staff of the Abyss is inert for a good fifth-level caster"
    echo "      and whole for a non-good one, as its page says."
    echo "      Neutral Good Mage 5: '$GRANT' present? $good"
    echo "      Neutral      Mage 5: '$GRANT' present? $nongood"
fi
exit $rc
