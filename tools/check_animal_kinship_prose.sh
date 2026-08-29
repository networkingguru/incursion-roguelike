#!/bin/bash
# Regression check for PA-08-F65 / inc-tek.8.8: the Ring of Animal Kinship
# (AI_RING Effect "Animal Kinship" : EA_GRANT) description must state plainly
# that it lets you use Animal Empathy with no ranks in the skill, and must NOT
# claim a false "+3 or higher" threshold for that untrained use. The code wins:
# untrained use already works from +1. The ring's own SKILL_BONUS SK_ANIMAL_EMP
# (pval PLUS_2PER1) makes SkillLevel(SK_ANIMAL_EMP) nonzero, the Animal-Empathy
# use-gate (src/Skills.cpp:1111) tests SkillLevel not SkillRanks, and SkillLevel
# sums the item bonus with no trained-only gate zeroing an untrained total
# (src/Create.cpp:4198-4243). There is no +3 test and no INNATE_KIT grant in the
# entity, so the "+3 or higher" clause named a threshold the code never enforced.
# Red while the Desc still reads "At +3 or higher", green once it drops that
# threshold and keeps "no ranks in it".
#
# The Desc is line-wrapped, so the target phrases span line breaks; this test
# collapses the Desc's whitespace and newlines to single spaces before matching.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="${SOURCE:-lib/m_items.irh}"
# Anchor on the Animal Kinship block, from its header to the first block-closing
# brace, then test the Desc STRING itself, NOT the whole block.
block="$(sed -n '/AI_RING Effect "Animal Kinship" : EA_GRANT/,/^  }/p' "$SOURCE" | sed -n '1,/^  }/p')"
desc="$(printf "%s\n" "$block" | sed -n '/Desc: "/,/";/p')"
# Collapse newlines and runs of whitespace to single spaces so the line-wrapped
# phrases match as one string.
flat="$(printf "%s\n" "$desc" | tr '\n' ' ' | tr -s ' ')"

if printf "%s\n" "$flat" | grep -q "At +3 or higher"; then
    echo "FAIL: the Ring of Animal Kinship description still claims a \"At +3 or higher\" threshold for untrained Animal Empathy use; the entity has no +3 test and no INNATE_KIT grant, and untrained use already works from +1 via the ring's own skill bonus and the SkillLevel use-gate (src/Skills.cpp:1111)."
    exit 1
fi

if ! printf "%s\n" "$flat" | grep -q "no ranks in it"; then
    echo "FAIL: the Ring of Animal Kinship description does not state that it lets you use the skill even if you have \"no ranks in it\"; untrained use is exactly what its skill bonus and the SkillLevel use-gate permit from +1."
    exit 1
fi

echo "PASS: PA-08-F65 / inc-tek.8.8 the Ring of Animal Kinship description drops the false \"+3 or higher\" threshold and states plainly that it lets you use Animal Empathy with no ranks, matching the untrained use its skill bonus and the SkillLevel use-gate already permit from +1."
