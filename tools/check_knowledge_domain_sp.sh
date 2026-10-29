#!/bin/bash
# gate: live
# inc-iwix: does the Knowledge domain's extra skill point come only on a PRIEST level?
#
# THE DEFECT. lib/domains.irh Knowledge's EV_ADVANCE called
# GainBonusSkills($"priest",1) with no class test. Player::AdvanceLevel
# (src/Create.cpp) sends EV_ADVANCE to every HAS_DOMAIN domain on a level in ANY
# class, with eID = the class that gained the level. A Priest/Mage got the
# priest point on mage levels too. The Desc says "at every priest level".
#
# REQUIRED. A mage level adds 0 to the Priest rank pool; a priest level adds
# exactly 1 from Knowledge.
#
# THE ORACLE is the Skill Manager's "Unspent Skill Ranks (Priest):" line, one
# '*' per unspent rank, read before and after one level. Only the DELTA is read:
# the fixture starts with one unspent rank. Fixture: Human Priest 1 / Mage 1,
# Domains Night, Fate, Knowledge (human-priest-mage-seed4-gate.sheet.txt).
# A priest level adds class points 4 + Human racial 2 + Knowledge 1 = 7.
#
# fact: the Priest rank pool at the start -- only the delta is read
# fact: Priest skill points per level, 4 -- lib/classes.irh Priest Desc "Skills: 4", INT 11 gives +0 (frozen fixture)
# fact: Human racial bonus, 2 on the advanced class -- lib/races.irh EV_ADVANCE GainBonusSkills(e.eID,2)
# fact: the fixture's domains and class levels -- frozen .sav (INCURSION_LOAD)
# fact: the feat menu offers an 'a' entry at the new level -- @until answers it, not seed-dependent
# fact: dungeon, rolls, monsters -- none read; only the sheet and Skill Manager
#
# Usage: tools/check_knowledge_domain_sp.sh [--prove-red]
#   0 pass   1 fail   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/human-priest-mage-seed4-gate.sav
[ -f "$FIXTURE" ] || _check_die 2 "no $FIXTURE."

check_mutation lib/domains.irh \
    'if (e.eID != $"priest") return NOTHING;' \
    'if (0) return NOTHING;'

export INCURSION_LOAD="$FIXTURE"

# pool <screen> -- the '*' count on the line under "Unspent Skill Ranks (Priest):".
pool() {
    awk '/Unspent Skill Ranks \(Priest\):/ { getline; s = $0; sub(/^[^|]*\|/, "", s)
           sub(/\|[^|]*$/, "", s); gsub(/[^*]/, "", s); print length(s); found = 1; exit }
         END { if (!found) exit 1 }' "$1"
}

# measure <keyscript> <label> -- sets DELTA to the Priest pool change.
measure() {
    check_run "$1" 4
    check_screens '*-before'
    check_expect "Unspent Skill Ranks (Priest):" "precondition: the Skill Manager showed the Priest pool before" ||
        _check_die 2 "precondition failed: no Priest pool before the level."
    check_screens '*-after'
    check_expect "Unspent Skill Ranks (Priest):" "precondition: the Skill Manager showed the Priest pool after" ||
        _check_die 2 "precondition failed: no Priest pool after the level."
    local b a
    b="$(pool "$CHECK_RUN"/logs/screens/*-before.txt)" || _check_die 2 "cannot read the pool before."
    a="$(pool "$CHECK_RUN"/logs/screens/*-after.txt)" || _check_die 2 "cannot read the pool after."
    DELTA=$((a - b))
    echo "  $2: Priest pool $b -> $a (delta $DELTA)"
}

measure tools/keys/knowledge-sp-mage.keys "mage level"
check_screens '*-after'
check_expect "Mage 2" "precondition: the mage level happened" ||
    _check_die 2 "precondition failed: no Mage 2."
MAGE_DELTA=$DELTA
if [ "$MAGE_DELTA" -eq 0 ]; then
    echo "  ok    a mage level adds 0 to the Priest pool"
else
    echo "  FAIL  a mage level added $MAGE_DELTA to the Priest pool; required 0"
    CHECK_FAIL=1
fi

measure tools/keys/knowledge-sp-priest.keys "priest level"
check_screens '*-after'
check_expect "Priest 2" "precondition: the priest level happened" ||
    _check_die 2 "precondition failed: no Priest 2."
if [ "$DELTA" -eq 7 ]; then
    echo "  ok    a priest level adds 7 to the Priest pool (4 class + 2 Human + 1 Knowledge)"
else
    echo "  FAIL  a priest level added $DELTA to the Priest pool; required 7 (4 + 2 + 1)"
    CHECK_FAIL=1
fi

check_done "Knowledge's extra skill point comes only on a priest level"
