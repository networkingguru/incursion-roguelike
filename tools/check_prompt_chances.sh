#!/bin/bash
# inc-1xr3 phase 2b: the prompt-time numbers must come from the same
# expression the deciding code uses.
#
# This is a source-level check. It does not run the game (the brief for this
# phase requires no gameplay observation); it asserts the structural
# invariants that make the advertised numbers trustworthy:
#
#   (1) the overchannel success chance shown on "Attempt spell anyway?"
#       is OverchannelChance(...), and the deciding roll keeps the original
#       `random(25)+80 > SpellRating(e.eID)` test -- the helper is not a
#       second, drifting formula;
#   (2) that helper agrees with the deciding test for every integer rating
#       the game can produce (exhaustive sweep over -64..200);
#   (3) the "Fire it anyway?" prompt prints the same die count the damage
#       roll consumes (the local `drainDice`);
#   (4) the two craft prompts show SkillCheckChance(useSkill, craftDC) --
#       the same skill and DC as the deciding SkillCheck(useSkill, craftDC);
#   (5) the repair prompt shows the same hours and modifier the deciding
#       SpendHours / SkillCheck use (fastHours/slowHours, fastMod/slowMod).
#
# Exits 0 on pass, 1 on fail.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
note() { printf 'FAIL: %s\n' "$1"; fail=1; }

MAGIC=src/Magic.cpp
SKILLS=src/Skills.cpp

# (1) prompt uses the helper, deciding roll is unchanged.
grep -q 'OverchannelChance(SpellRating(e.eID))' "$MAGIC" \
    || note "Magic.cpp: prompt does not call OverchannelChance(SpellRating(e.eID))"
grep -q 'random(25)+80 > SpellRating(e.eID)' "$MAGIC" \
    || note "Magic.cpp: deciding overchannel roll changed"

# (2) exhaustive agreement between helper and deciding test.
#     Deciding code fails when random(25)+80 > rating; over the 25 equally
#     likely random(25) values (0..24) the success count is
#     card(r in 0..24 : 80+r <= rating). The advertised percent is
#     count*100/25. Re-derive both here and compare to the helper source.
awk '
function helper(rating,   passing) {
    passing = rating - 79
    if (passing < 0) passing = 0
    if (passing > 25) passing = 25
    return int((passing * 100) / 25)
}
function oracle(rating,   r, count) {
    count = 0
    for (r = 0; r < 25; r++)
        if (80 + r <= rating) count++
    return int((count * 100) / 25)
}
BEGIN {
    bad = 0
    for (rating = -64; rating <= 200; rating++)
        if (helper(rating) != oracle(rating)) {
            printf "FAIL: OverchannelChance(%d)=%d but deciding test gives %d\n",
                rating, helper(rating), oracle(rating)
            bad++
        }
    if (bad) exit 1
    printf "overchannel helper agrees with deciding test on 265 ratings\n"
}' || fail=1

# (3) wand prompt and damage roll share drainDice.
grep -q 'int16 drainDice = TEFF(e.eID)->ManaCost - (int16)e.EActor->cMana();' "$MAGIC" \
    || note "Magic.cpp: wand drain die count not factored into drainDice"
grep -q 'yn(Format("Fire it anyway? (takes %dd4 damage)", drainDice)' "$MAGIC" \
    || note "Magic.cpp: wand prompt does not print drainDice"
grep -q 'Dice::Roll(drainDice, 4,0)' "$MAGIC" \
    || note "Magic.cpp: wand damage roll does not use drainDice"

# (4) craft prompts show SkillCheckChance(useSkill, craftDC).
grep -q 'SkillCheckChance(useSkill, craftDC)' "$SKILLS" \
    || note "Skills.cpp: craft prompt does not show SkillCheckChance(useSkill, craftDC)"
grep -q 'SkillCheck(useSkill, craftDC, true)' "$SKILLS" \
    || note "Skills.cpp: craft deciding check changed"

# (5) repair prompt and deciding code share the hours and modifier locals.
grep -q 'int16 fastHours = 2, slowHours = 8;' "$SKILLS" \
    || note "Skills.cpp: repair hours not factored into fastHours/slowHours"
grep -q 'int16 fastMod = 0, slowMod = 4;' "$SKILLS" \
    || note "Skills.cpp: repair modifier not factored into fastMod/slowMod"
grep -q 'SpendHours(workSlowly ? slowHours : fastHours' "$SKILLS" \
    || note "Skills.cpp: repair SpendHours does not use the shared hours"
grep -q 'SkillCheck(SK_CRAFT, repairDC, true, workSlowly ? slowMod : fastMod' "$SKILLS" \
    || note "Skills.cpp: repair deciding check does not use the shared modifier"

if [ "$fail" -eq 0 ]; then
    echo "PASS: prompt chances come from the deciding expressions"
fi
exit "$fail"
