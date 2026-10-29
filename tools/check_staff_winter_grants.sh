#!/bin/bash
# Does the Staff of Winter hand over all four powers its own page promises?
# Finding PA-08-F5 of bd inc-tek.8.8.
#
# THE DEFECT. The staff's page (lib/m_items.irh) promises four things: six
# cold spells, "a +2 enhancement bonus to Charisma", "a +4 enhancement bonus
# to Intimidate", and "a -6 penalty to the Appraise skill". The entity held
# one effect block, the spell grant, and nothing else. The other three
# sentences described powers no script ever gave. The page is what the player
# reads, so the page wins: three EA_GRANT continuation blocks now carry the
# three missing numbers, and they are the literal numbers the page states,
# not numbers scaled on the item's plus.
#
# THE ORACLE is read twice in one session, once before the staff is picked up
# and once with it in the weapon hand:
#
#   1. Wizard mode's "Examine Player Data", which prints every stati with its
#      Val and its Mag (src/Debug.cpp:1524-1590). SKILL_BONUS names its skill
#      and ADJUST names its attribute. Underscores render as spaces on
#      screen, so the patterns below read "SKILL BONUS" and "SK APPRAISE".
#      This is the authority: it shows what the wielder actually holds.
#   2. The character sheet, which is what a player sees. Its Skill Ratings
#      block prints an item's share as ", +N magic" (src/Sheet.cpp:949-950)
#      and its Charisma line the same way (src/Sheet.cpp:93-101).
#
# THE SHEET IS ASKED ABOUT APPRAISE TOO. Creature::SkillLevel once collected a
# skill bonus per source with max(bucket,S->Mag) from a zero start
# (src/Create.cpp), so a NEGATIVE item bonus lost to the zero and never reached
# the total: the stati dump showed the -6, the sheet ignored it. That defect
# (inc-e7wp, shared with the Staff of the Goblin Queen) is fixed: negative
# grants in a bucket now add. The sheet's Appraise total with the staff in hand
# MUST be 6 lower than without it.
#
# Facts this check reads:
# fact: character -- fixture tools/keys/chargen-mage.keys plus INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat; asserts only a DIFFERENCE between two reads of one session
# fact: Appraise total before/after -- both read in the one session; only their difference (-6) is asserted
# fact: staff plus (+2) -- set by the key script's acquisition prompt, not by the seed
# fact: Staff of Winter row in the acquisition list -- the key script walks to it by name and the check reads the name back from the Weapon Hand
#
# THE GATE. The entity refuses everything to a wielder below caster level
# three -- its EV_MAGIC_HIT handler returns DONE, which swallows the event
# before Magic::Grant runs, and that handler belongs to the whole effect and
# not to one block of it. The three new grants sit behind the same door. So
# the session builds a Mage 3, and this check refuses to report anything at
# all unless the session's own STAFF_SPELLS stati proves the door opened. A
# run that measured a character the staff ignores would otherwise report "no
# bonus" and look exactly like the defect.
#
# Usage: tools/check_staff_winter_grants.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh tools/keys/staff-winter-grants.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
if echo "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: the key script could not find something on screen. Run: $run"
    exit 2
fi

scr="$run/logs/screens"
pick() { # <label> -> the one screen dumped under that label
    local f
    f="$(ls "$scr"/*-"$1".txt 2>/dev/null | head -1)"
    if [ -z "$f" ]; then
        echo "INCONCLUSIVE: no screen dumped for '$1'. Run: $run"
        return 2
    fi
    echo "$f"
}

wielded="$(pick staff-wielded)" || { echo "$wielded"; exit 2; }
before="$(pick sheet-before)"   || { echo "$before"; exit 2; }
after="$(pick sheet-after)"     || { echo "$after"; exit 2; }

ls "$scr"/*-stati-after-*.txt >/dev/null 2>&1 || {
    echo "INCONCLUSIVE: the session dumped no stati screens. Run: $run"
    exit 2
}

# --- the three things that must be true before any number below means anything

# 1. The character is a Mage 3, so the caster-level-three gate can open.
grep -qF "Class  Mage 3" "$after" || {
    echo "INCONCLUSIVE: the sheet does not say Mage 3, so the caster-level"
    echo "              gate on the staff was never satisfied. Screen: $after"
    exit 2
}

# 2. The staff really is in the weapon hand. The acquisition list is walked by
#    cursor and the container row by number, so read the name back rather than
#    trusting either.
grep -q "b)Weapon Hand.*Staff +2 of Winter" "$wielded" || {
    echo "INCONCLUSIVE: no Staff +2 of Winter in the Weapon Hand, so the"
    echo "              session wielded the wrong item or none."
    echo "              Screen: $wielded"
    exit 2
}

# 3. The gate actually opened. STAFF_SPELLS is the one grant the entity has
#    always made, so its arrival proves the handler let the effect through.
grep -qh "STAFF SPELLS from SS ITEM" "$scr"/*-stati-after-*.txt || {
    echo "INCONCLUSIVE: the staff granted no staff spells either, so the"
    echo "              caster-level gate stayed shut and this session"
    echo "              measured nothing. Screens: $scr/*-stati-after-*.txt"
    exit 2
}

# 4. Nothing of the kind was on the character before the staff, or a reading
#    after it proves nothing about the staff.
for pat in "SKILL BONUS from SS ITEM" "ADJUST from SS ITEM (Val:A CHA"; do
    if grep -qh "$pat" "$scr"/*-stati-before-*.txt; then
        echo "INCONCLUSIVE: '$pat' was already on the character before the"
        echo "              staff was picked up, so the reading after it does"
        echo "              not belong to the staff."
        exit 2
    fi
done

rc=0

# --- what the wielder actually holds

stati_has() { # <pattern> <what the page promises>
    grep -qh "$1" "$scr"/*-stati-after-*.txt || {
        echo "FAIL: the staff grants no $2."
        echo "      Wanted a stati line matching: $1"
        echo "      Screens: $scr/*-stati-after-*.txt"
        rc=1
    }
}
stati_has "SKILL BONUS from SS ITEM (Val:SK INTIMIDATE Mag:4)"  "+4 to Intimidate"
stati_has "SKILL BONUS from SS ITEM (Val:SK APPRAISE Mag:-6)"   "-6 to Appraise"
stati_has "ADJUST from SS ITEM (Val:A CHA Mag:2)"               "+2 to Charisma"

# --- what a player sees

sheet_says() { # <regex> <what the page promises>
    grep -qE "$1" "$after" || {
        echo "FAIL: the sheet does not show $2."
        echo "      Wanted a line matching: $1"
        echo "      Screen: $after"
        rc=1
    }
}
total_of() { # <skill> <file> -> the signed total on that skill's sheet row
    awk -v k="$1" '$1 == k {print $2; exit}' "$2"
}
a_before="$(total_of Appraise "$before")"
a_after="$(total_of Appraise "$after")"
if [ -z "$a_before" ] || [ -z "$a_after" ]; then
    echo "INCONCLUSIVE: no Appraise row on the sheet (before='$a_before' after='$a_after')."
    exit 2
fi
if [ "$((a_after - a_before))" != -6 ]; then
    echo "FAIL: Appraise on the sheet moved by $((a_after - a_before)) with the staff in hand; the page promises -6."
    echo "      before: $a_before   after: $a_after"
    rc=1
fi
sheet_says '^ *Intimidate +\+8 .*\+4 magic' \
    "Intimidate at +8 with +4 magic from the staff"
sheet_says 'CHA: 16/00 .*\+2 magic' \
    "Charisma raised to 16 with +2 magic from the staff"

if [ "$rc" = 0 ]; then
    echo "  ok: the Staff of Winter grants +2 Charisma, +4 Intimidate and -6"
    echo "      Appraise, as its page says."
    echo "      Appraise: $a_before before, $a_after after"
    echo "      before: $(grep -E '^ *Intimidate' "$before" | tr -s ' ')"
    echo "      after:  $(grep -E '^ *Intimidate' "$after"  | tr -s ' ')"
    echo "      before: $(grep -oE 'CHA: [0-9]+/[0-9]+ .*' "$before" | tr -s ' ')"
    echo "      after:  $(grep -oE 'CHA: [0-9]+/[0-9]+ .*' "$after"  | tr -s ' ')"
fi
exit $rc
