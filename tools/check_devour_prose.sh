#!/usr/bin/env bash
# gate: cheap
# gate-fast: static, reads lib/races.irh and src/Skills.cpp only, under 1 s
#
# Guards bead inc-dq3: the orc Devouring paragraph in lib/races.irh pairs each
# ability score with a monster type, and Creature::DevourMonster
# (src/Skills.cpp, AttrMTypes[]) pairs them by array slot. The two must agree.
# The prose once said "elves to Dexterity" while the code uses MA_CAT.
#
# fact: the orc Devouring prose -- read from lib/races.irh; no game run, no seed
# fact: the AttrMTypes[] array -- read from src/Skills.cpp; no game run, no seed
# fact: character, options, map, monsters -- not read; this check starts no session
#
# Exit 0 pass, 1 fail, 2 could not measure.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
R=${RACES_FILE:-lib/races.irh}
S=${SKILLS_FILE:-src/Skills.cpp}
[ -r "$R" ] || { echo "UNMEASURED: cannot read $R"; exit 2; }
[ -r "$S" ] || { echo "UNMEASURED: cannot read $S"; exit 2; }

# Array entries in slot order, comments removed.
ARR=$(sed -n '/AttrMTypes\[\] *= *{/,/0 *};/p' "$S" | sed 's://.*$::')
[ -n "$ARR" ] || { echo "UNMEASURED: no AttrMTypes[] in $S"; exit 2; }
SLOTS=($(grep -o 'MA_[A-Z_]*' <<< "$ARR"))
[ "${#SLOTS[@]}" -eq 7 ] || { echo "UNMEASURED: AttrMTypes[] has ${#SLOTS[@]} entries, expected 7"; exit 2; }

# Paragraph: flattened, from "rare monsters" to "Dragons can convey".
ALL=$(tr '\n' ' ' < "$R" | tr -s ' \t' ' ')
rest=${ALL#*"certain rare monsters"}
[ "$rest" != "$ALL" ] || { echo "UNMEASURED: no Devouring attribute paragraph in $R"; exit 2; }
PARA=${rest%%"Dragons can convey"*}
[ "$PARA" != "$rest" ] || { echo "UNMEASURED: paragraph end not found in $R"; exit 2; }

# slot-order: prose phrase, attribute, expected type
PHRASES=("Giants are so tied to" "cats" "trolls" "mind flayers" "nagas" "faeries" "mythic hybrids")
ATTRS=(Strength Dexterity Constitution Intelligence Wisdom Charisma Luck)
TYPES=(MA_GIANT MA_CAT MA_TROLL MA_ILLITHID MA_NAGA MA_FAERIE MA_MYTHIC)

FAIL=0
for i in 0 1 2 3 4 5 6; do
    if [ "${SLOTS[$i]}" != "${TYPES[$i]}" ]; then
        echo "FAIL: AttrMTypes[$i] (${ATTRS[$i]}) is ${SLOTS[$i]}, expected ${TYPES[$i]}"
        FAIL=1
    fi
    if [ "$i" -eq 0 ]; then want="${PHRASES[$i]} ${ATTRS[$i]}"; else want="${PHRASES[$i]} to ${ATTRS[$i]}"; fi
    if ! grep -qF -- "$want" <<< "$PARA"; then
        echo "FAIL: Devouring prose lacks: $want"
        FAIL=1
    fi
done
[ "$FAIL" -eq 0 ] && echo "PASS: Devouring prose and AttrMTypes[] agree on all 7 pairings"
exit "$FAIL"
