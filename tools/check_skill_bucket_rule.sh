#!/bin/bash
# gate: live
# The skill-bucket rule of Creature::SkillLevel (src/Create.cpp), on the sheet:
# in one bucket (class feat, racial, domain, item, focus, enhancement) the
# highest POSITIVE grant counts alone, and EVERY negative grant adds. (bd inc-e7wp)
#
# Two live sessions, each reading the character sheet at two points:
#
#   A. tools/keys/skill-bucket-positives.keys -- a Mage 3 wields the Staff of
#      Winter (+4 Intimidate, item bucket), then wears Lenses of Terror (+5
#      Intimidate, item bucket). Rule: the bucket is 5, not 9, so Intimidate
#      rises by exactly 1 (8 -> 9) and the sheet says "+5 magic".
#      This half is green on the unfixed build too: it guards the half of the
#      rule the fix leaves unchanged. Mutation: make the positives sum and it
#      goes red (+9 magic).
#   B. tools/keys/skill-bucket-mixed.keys -- a goblinoid Mage 3 wears a
#      Headband +3 of Magical Aptitude (+6 Concentration, item bucket), then
#      wields the Staff of the Goblin Queen (-4 Concentration, item bucket).
#      Rule: positives and negatives meet in one bucket as 6 + (-4), so
#      Concentration FALLS by 4 when the staff arrives and the sheet says
#      "+2 magic". The unfixed build keeps max(6,-4) = 6 and shows no change.
#
# Gates, so that a measurement of nothing is never reported as the rule:
# the wielded/worn items are read back by name from the equipment screen, the
# staff's own STAFF_SPELLS stati proves its caster-level and goblinoid gate
# opened, and the headband's +6 must show on the sheet before the staff.
#
# fact: character -- tools/keys/chargen-mage.keys (orc mage) + INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat; only differences between reads of one session are asserted
# fact: Intimidate / Concentration totals -- read twice-three times in one session; only their differences (+1, +6, -4) and the magic term (+5, +2) are asserted
# fact: item pluses (+2 staff of Winter, +3 headband) -- typed by the key scripts at the acquisition prompt
# fact: acquisition rows (Winter, Lenses of Terror, Magical Aptitude, Goblin Queen) -- walked to by name in the key scripts; names read back from the equipment screens
# fact: item bucket contents -- SS_ITEM stati read from the same sessions
#
# Usage: tools/check_skill_bucket_rule.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

run_session() { # <keys> -> sets $run, $scr; exit 2 when the script stalls
    local out
    out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh "$1" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if grep -q "the key script looked for something" <<< "$out"; then
        echo "INCONCLUSIVE: $1 could not find something on screen. Run: $run"
        exit 2
    fi
    scr="$run/logs/screens"
}
pick() { # <label> -> the one screen dumped under that label
    local f
    f="$(ls "$scr"/*-"$1".txt 2>/dev/null | head -1)"
    [ -n "$f" ] || { echo "INCONCLUSIVE: no screen dumped for '$1'. Run: $run"; exit 2; }
    echo "$f"
}
total() { awk -v k="$1" '$1 == k {print $2; exit}' "$2"; }
magic() { awk -v k="$1" '$1 == k {print}' "$2" | grep -oE '[-+][0-9]+ magic' | head -1 | awk '{print $1}'; }

rc=0

# ---------------------------------------------------------------- session A
run_session tools/keys/skill-bucket-positives.keys
wielded="$(pick staff-wielded)"; staff_sheet="$(pick sheet-after)"
lens_worn="$(pick lenses-worn)"; lens_sheet="$(pick sheet-lenses)"
grep -qF "Class  Mage 3" "$staff_sheet" || { echo "INCONCLUSIVE: A: not Mage 3. $staff_sheet"; exit 2; }
grep -q "b)Weapon Hand.*Staff +2 of Winter" "$wielded" || { echo "INCONCLUSIVE: A: no Staff of Winter in hand. $wielded"; exit 2; }
grep -qh "STAFF SPELLS from SS ITEM" "$scr"/*-stati-after-*.txt || { echo "INCONCLUSIVE: A: Winter's gate stayed shut. $scr"; exit 2; }
grep -q "h)On Eyes.*Lenses of Terror" "$lens_worn" || { echo "INCONCLUSIVE: A: Lenses of Terror not worn. $lens_worn"; exit 2; }
i_staff="$(total Intimidate "$staff_sheet")"; i_lens="$(total Intimidate "$lens_sheet")"
m_staff="$(magic Intimidate "$staff_sheet")"; m_lens="$(magic Intimidate "$lens_sheet")"
[ "$m_staff" = "+4" ] || { echo "INCONCLUSIVE: A: staff alone gave '$m_staff' magic Intimidate, not +4."; exit 2; }
if [ "$((i_lens - i_staff))" != 1 ] || [ "$m_lens" != "+5" ]; then
    echo "FAIL: A: +4 and +5 in one bucket must count as 5 (Intimidate +1, '+5 magic')."
    echo "      staff alone: $i_staff ($m_staff magic)   staff + lenses: $i_lens ($m_lens magic)"
    rc=1
else
    echo "  ok: A: two positive grants do not stack: Intimidate $i_staff -> $i_lens, $m_lens magic"
fi

# ---------------------------------------------------------------- session B
run_session tools/keys/skill-bucket-mixed.keys
hb_worn="$(pick headband-worn)"; wielded="$(pick staff-wielded)"
before="$(pick sheet-before)"; hb_sheet="$(pick sheet-headband)"; after="$(pick sheet-after)"
grep -qF "Class  Mage 3" "$after" || { echo "INCONCLUSIVE: B: not Mage 3. $after"; exit 2; }
grep -q "q)Helmet.*Headband +3 of Magical Aptitude" "$hb_worn" || { echo "INCONCLUSIVE: B: headband not worn. $hb_worn"; exit 2; }
grep -q "b)Weapon Hand.*Staff of the Goblin Queen" "$wielded" || { echo "INCONCLUSIVE: B: no Goblin Queen staff in hand. $wielded"; exit 2; }
grep -qh "STAFF SPELLS from SS ITEM" "$scr"/*-stati-after-*.txt || { echo "INCONCLUSIVE: B: staff gate stayed shut. $scr"; exit 2; }
grep -qh "SKILL BONUS from SS ITEM (Val:SK CONCENT Mag:-4)" "$scr"/*-stati-after-*.txt || { echo "INCONCLUSIVE: B: no -4 Concentration stati. $scr"; exit 2; }
c0="$(total Concentration "$before")"; c1="$(total Concentration "$hb_sheet")"; c2="$(total Concentration "$after")"
m1="$(magic Concentration "$hb_sheet")"; m2="$(magic Concentration "$after")"
[ "$((c1 - c0))" = 6 ] && [ "$m1" = "+6" ] || { echo "INCONCLUSIVE: B: headband alone moved Concentration $c0 -> $c1 ('$m1' magic), not +6."; exit 2; }
if [ "$((c2 - c1))" != -4 ] || [ "$m2" != "+2" ]; then
    echo "FAIL: B: a -4 grant must add to a bucket holding +6 (Concentration -4, '+2 magic')."
    echo "      headband: $c1 ($m1 magic)   headband + staff: $c2 ($m2 magic)"
    rc=1
else
    echo "  ok: B: a negative grant adds to a positive one: Concentration $c1 -> $c2, $m2 magic"
fi
exit $rc
