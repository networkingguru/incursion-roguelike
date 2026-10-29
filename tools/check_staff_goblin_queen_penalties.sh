#!/bin/bash
# gate: live
# Does the Staff of the Goblin Queen cost its wielder the -4 Spot, Listen and
# Concentration its page promises, on the character sheet? (bd inc-e7wp)
#
# THE DEFECT. Creature::SkillLevel (src/Create.cpp) collected an item's skill
# bonus with max(bucket,S->Mag) from zero, so a NEGATIVE item grant lost to the
# zero and never reached the sheet total. The wielder's stati held the -4; the
# number did not move. Now each bucket keeps its highest positive grant alone
# and adds every negative grant.
#
# THE ORACLE is read twice in one session (tools/keys/staff-goblin-queen-
# penalties.keys), before the staff and with it in the weapon hand:
#   1. the stati dump of wizard mode's "Examine Player Data": it proves the
#      grant FIRED (the staff gates every grant behind caster level 3 and
#      MA_GOBLINOID; a wielder it ignores reads INCONCLUSIVE, exit 2);
#   2. the sheet's Skill Ratings rows for Spot, Listen and Concentration, each
#      of which MUST read 4 lower with the staff than without it.
# A row whose total equals its attribute modifier is not printed (src/Sheet.cpp),
# so a missing "before" row is read as that modifier, taken from the "after" row's
# own attribute term.
#
# fact: character -- tools/keys/chargen-mage.keys (orc mage) + INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat; only a before/after DIFFERENCE is asserted
# fact: Spot/Listen/Concentration totals -- read twice in the one session; only the difference (-4) is asserted
# fact: Staff of the Goblin Queen row in the acquisition list -- walked to by name in the key script; name read back from the Weapon Hand line
# fact: the grant fired -- STAFF SPELLS and the three SKILL BONUS stati read from the same session's stati dump
#
# Usage: tools/check_staff_goblin_queen_penalties.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh tools/keys/staff-goblin-queen-penalties.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
if grep -q "the key script looked for something" <<< "$out"; then
    echo "INCONCLUSIVE: the key script could not find something on screen. Run: $run"
    exit 2
fi

scr="$run/logs/screens"
pick() {
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
# Spot and Listen sit on later pages of the sheet: join the pages (PGDN scrolls one line, so the key script steps 15 lines at a time)
for w in before after; do
    for pg in p2 p3 p4 p5; do
        f="$(pick sheet-$w-$pg)" || { echo "$f"; exit 2; }
        cat "$f" >> "$scr/joined-$w.txt"
    done
    cat "$(pick sheet-$w)" >> "$scr/joined-$w.txt"
done
before_all="$scr/joined-before.txt"; after_all="$scr/joined-after.txt"
ls "$scr"/*-stati-after-*.txt >/dev/null 2>&1 || {
    echo "INCONCLUSIVE: the session dumped no stati screens. Run: $run"
    exit 2
}

grep -qF "Class  Mage 3" "$after" || {
    echo "INCONCLUSIVE: the sheet does not say Mage 3. Screen: $after"
    exit 2
}
grep -q "b)Weapon Hand.*Staff of the Goblin Queen" "$wielded" || {
    echo "INCONCLUSIVE: no Staff of the Goblin Queen in the Weapon Hand. Screen: $wielded"
    exit 2
}
grep -qh "STAFF SPELLS from SS ITEM" "$scr"/*-stati-after-*.txt || {
    echo "INCONCLUSIVE: the staff granted no staff spells, so its goblinoid +"
    echo "              caster-level gate stayed shut and nothing was measured."
    echo "              Screens: $scr/*-stati-after-*.txt"
    exit 2
}
for pat in "SKILL BONUS from SS ITEM"; do
    if grep -qh "$pat" "$scr"/*-stati-before-*.txt; then
        echo "INCONCLUSIVE: '$pat' was on the character before the staff."
        exit 2
    fi
done
# the stati dump truncates the skill name to SK CONCENT
for sk in SPOT LISTEN CONCENT; do
    grep -qh "SKILL BONUS from SS ITEM (Val:SK $sk Mag:-4)" "$scr"/*-stati-after-*.txt || {
        echo "INCONCLUSIVE: no -4 $sk stati after the staff, so the grant did not fire."
        echo "              Screens: $scr/*-stati-after-*.txt"
        exit 2
    }
done

# total of a sheet row; when absent, the row equals its attribute modifier,
# which the "after" row carries as its own attribute term (or 0 when absent).
total() { # <skill label> <file> -> signed total or empty
    awk -v k="$1" '$1 == k {print $2; exit}' "$2"
}
attr_mod() { # <skill label> <file> -> the "+N ATTR" term of the row, 0 if none
    awk -v k="$1" '$1 == k {print}' "$2" | grep -oE '\(.*\)' |
        grep -oE '[-+][0-9]+ (STR|DEX|CON|INT|WIS|CHA)' | head -1 | awk '{print $1}'
}

rc=0
for sk in Spot Listen Concentration; do
    a="$(total "$sk" "$after_all")"
    b="$(total "$sk" "$before_all")"
    if [ -z "$a" ]; then
        # the after row is hidden: its total equals its attribute modifier,
        # so the staff changed nothing at all
        echo "FAIL: $sk shows no row after the staff: total equals its attribute modifier."
        echo "      before row: '$(grep -E "^ *$sk" "$before_all" | head -1 | tr -s ' ')'"
        rc=1
        continue
    fi
    if [ -z "$b" ]; then
        m="$(attr_mod "$sk" "$after_all")"
        b="${m:-0}"
    fi
    if [ "$((a - b))" != -4 ]; then
        echo "FAIL: $sk moved by $((a - b)) with the staff in hand; the page promises -4."
        echo "      before: $b   after: $a   row: $(grep -E "^ *$sk" "$after_all" | head -1 | tr -s ' ')"
        rc=1
    else
        echo "  ok: $sk $b -> $a"
    fi
done
[ "$rc" = 0 ] && echo "  ok: the Staff of the Goblin Queen lowers Spot, Listen and Concentration by 4 on the sheet."
exit $rc
