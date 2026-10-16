#!/bin/bash
# gate: live
# inc-8chz: Legend Lore (bard CA_LEGEND_LORE) must (A) feed Knowledge (Magic) the
# FULL Legend Lore level and Intuition (a bard class skill) the full level, with
# every other Knowledge skill still getting half (Creature::SkillLevel,
# src/Create.cpp), and (B) identify a magic item through ONE silent Knowledge
# (Magic) roll per item (Character::LegendIdent, src/Skills.cpp), never a second
# roll when the item is seen or picked up again. Before inc-8chz LegendIdent used
# a fixed score with no roll, and Knowledge (Magic) got half the level.
#
# Both runs load the frozen orc bard tools/fixtures/chars/orc-bard-reapply-seed1.sav
# (Bard 6, Legend Lore 6th, wizard mode) under tools/fixtures/options-2026-08-22.dat.
#
# A  tools/keys/load-char-sheet.keys with INCURSION_CHAR_PROBE=1. The save the
#    run writes carries logs/charprobe.txt, the engine's own character sheet,
#    untruncated by the 80x48 terminal. Its "Skill Ratings" give, for L = the
#    Legend Lore level: Knowledge (Magic) "+L inherent", Knowledge (Mythology)
#    (any other) "+L/2 inherent", Intuition "+L inherent" and "+2 train" (class
#    skill; the base +2 is the class-skill bonus shown on every class skill).
# B  tools/keys/legend-lore-item.keys with INCURSION_LEGEND_LORE_PROBE=1. The key
#    script turns Auto-Identify OFF (it returns before Legend Lore runs), makes
#    an UNKNOWN Circlet of Blasting with wizard "Acquire Unknown Item", then picks
#    it up and passes turns. The probe (src/LegendLoreProbe.cpp, off unless the
#    variable is set) logs each LegendIdent pass over a magic item to
#    logs/legend-lore.log. Asserted: exactly one pass rolled; the same item was
#    passed again afterward with no roll (flag=1, rolled=0); and what the roll
#    revealed follows the margin (roll - item level): nature >0, curse >5, bless
#    >8, magic >10, plus >15, plus2 >20, artifact >30, added to what was known.
#    The probe's roll value is the only place the silent roll is visible.
#    A missing or empty probe log, or sheet, is a FAIL ("measured nothing").
# C  a text guard, no game run. Joins the wrapped lines/literals of the new
#    Legend Lore text in lib/classes.irh (the Bard help) and src/Tables.cpp
#    (the AbilInfo row) and requires a distinctive sentence of each; fails if
#    either is missing, or if the old phrases "not a skill check" (classes.irh)
#    or "Each item is checked against 10 plus your ability" (Tables.cpp) remain.
#
# PROVED RED, one mutation per run (the library declares the first only, so the
# variable picks it; each rebuilds, runs the check, restores, rebuilds):
#   tools/check_legend_lore.sh --prove-red                          # roll
#   CHECK_LEGEND_MUTATION=magic tools/check_legend_lore.sh --prove-red
#   CHECK_LEGEND_MUTATION=intuition tools/check_legend_lore.sh --prove-red
#   roll       removes the IF_LEGEND_ROLLED guard in LegendIdent: B goes red
#              (two rolls of one item).
#   magic      Knowledge (Magic) back to half the level: A goes red.
#   intuition  Intuition's inherent bonus removed: A goes red.
#
# Usage: tools/check_legend_lore.sh [--prove-red]   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/orc-bard-reapply-seed1.sav
[ -f "$FIXTURE" ] || _check_die 2 "the frozen subject $FIXTURE is missing."

case "${CHECK_LEGEND_MUTATION:-roll}" in
    roll)
        check_mutation src/Skills.cpp '!(it->IFlags & IF_LEGEND_ROLLED) &&' '1 &&' ;;
    magic)
        check_mutation src/Create.cpp \
            's_inh = (sk == SK_KNOW_MAGIC) ? AbilityLevel(CA_LEGEND_LORE)' \
            's_inh = (sk == SK_KNOW_MAGIC) ? AbilityLevel(CA_LEGEND_LORE) / 2' ;;
    intuition)
        check_mutation src/Create.cpp \
            $'Legend Lore. */\n    if (sk == SK_INTUITION)' \
            $'Legend Lore. */\n    if (0 && sk == SK_INTUITION)' ;;
    *) _check_die 2 "CHECK_LEGEND_MUTATION must be roll, magic or intuition." ;;
esac

export INCURSION_LOAD="$FIXTURE"

# ---- A: the character sheet ----
echo "A: skills on the sheet"
INCURSION_CHAR_PROBE=1 check_run tools/keys/load-char-sheet.keys 1
sheet="$CHECK_RUN/logs/charprobe.txt"
if [ ! -s "$sheet" ]; then
    echo "FAIL: measured nothing: $sheet is missing or empty."
    exit 1
fi
if python3 - "$sheet" <<'PY'
import re
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
fails = []
m = re.search(r'Legend Lore \((\d+)(?:st|nd|rd|th)\)', text)
if not m:
    print('FAIL: no "Legend Lore (Nth)" on the sheet: measured nothing')
    sys.exit(1)
L = int(m.group(1))

def row(name):
    r = re.search(r'^\s*' + re.escape(name) + r'\s+([+-]\d+)\s+\((.*)\)\s*$', text, re.M)
    return r.group(2) if r else None

def inherent(name):
    body = row(name)
    if body is None:
        return None, None
    i = re.search(r'([+-]\d+) inherent', body)
    return (int(i.group(1)) if i else 0), body

def want(label, got, expected, body):
    print(f'  {label}: inherent {got} (expected {expected})   [{body}]')
    if got != expected:
        fails.append(label)

print(f'  Legend Lore level L = {L}')
for label, name, expected in (
        ('Knowledge (Magic) is the full L', 'Knowledge (Magic)', L),
        ('Knowledge (Mythology) is L/2', 'Knowledge (Mythology)', L // 2),
        ('Intuition is the full L', 'Intuition', L)):
    got, body = inherent(name)
    if body is None:
        print(f'FAIL: no "{name}" row on the sheet: measured nothing')
        sys.exit(1)
    want(label, got, expected, body)
_, body = inherent('Intuition')
cls = '+2 train' in body
print(f'  Intuition is a class skill (+2 train): {cls}')
if not cls:
    fails.append('Intuition class skill')
sys.exit(1 if fails or L < 2 else 0)
PY
then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    echo "  ok    A: Knowledge (Magic) and Intuition carry the full Legend Lore level"
else
    CHECK_FAIL=1
    echo "  FAIL  A: the skill rows are wrong (see above)"
fi

# ---- B: one roll per item ----
echo "B: one Knowledge (Magic) roll per item"
INCURSION_LEGEND_LORE_PROBE=1 check_run tools/keys/legend-lore-item.keys 1
check_screens '*switches-after'
check_expect "Auto-Identify Items                        NO" \
    "Auto-Identify is off, so LegendIdent reaches Legend Lore"
log="$CHECK_RUN/logs/legend-lore.log"
if [ ! -s "$log" ]; then
    echo "FAIL: measured nothing: $log is missing or empty."
    exit 1
fi
echo "  probe log ($(wc -l < "$log" | tr -d ' ') lines):"
sed 's/^/    /' "$log" | head -12
if python3 - "$log" <<'PY'
import re
import sys
rows = []
for line in open(sys.argv[1]):
    m = re.match(r'(\w+) ' + ' '.join(k + r'=(\S+)' for k in
        ('item', 'level', 'rolled', 'check', 'margin', 'before', 'after', 'flag')) + r'\s*$', line)
    if not m:
        print('FAIL: unreadable probe line: ' + line.strip())
        sys.exit(1)
    rows.append(dict(zip(('stage', 'item', 'level', 'rolled', 'check', 'margin',
                          'before', 'after', 'flag'), m.groups())))
rolls = [r for r in rows if r['rolled'] == '1']
fails = []
print(f'  passes over magic items: {len(rows)}; passes that rolled: {len(rolls)} (expected 1)')
if len(rolls) != 1:
    fails.append('roll count')
if rolls:
    r = rolls[0]
    again = [x for x in rows if x['item'] == r['item'] and x is not r and x['rolled'] == '0'
             and x['flag'] == '1']
    print(f'  same item passed again without a roll: {len(again)} (expected >= 1)')
    if not again:
        fails.append('no later pass')
    check, level, margin = int(r['check']), int(r['level']), int(r['margin'])
    print(f'  roll {check}, item level {level}, margin {margin}')
    if margin != check - level:
        fails.append('margin is not roll minus level')
    expect = ''.join(
        '1' if (b == '1' or margin > t) else '0'
        for b, t in zip(r['before'], (0, 5, 8, 10, 15, 20, 30)))
    print(f'  known bits before {r["before"]}, after {r["after"]}, expected {expect}'
          ' (nature curse bless magic plus plus2 artifact)')
    if r['after'] != expect:
        fails.append('revealed bits do not follow the margin')
sys.exit(1 if fails else 0)
PY
then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    echo "  ok    B: one roll, no re-roll, reveal follows the margin"
else
    CHECK_FAIL=1
    echo "  FAIL  B: the item was not rolled once (see above)"
fi

# ---- C: the help and ability text ----
echo "C: Legend Lore help and ability text"
if python3 - <<'PY'
import re
import sys
fails = []

def joined(path, pat):
    text = open(path, encoding="utf-8", errors="replace").read()
    body = re.search(pat, text, re.S)
    if not body:
        return None
    return ' '.join(re.sub(r'"|\s+', ' ', body.group(1)).split())

bards = joined('lib/classes.irh', r'Legend Lore<2> -- (.*?)\\n')
want_help = ("The first time a bard sees or picks up an unidentified magic"
             " item, she makes one Knowledge (Magic) check against the item's level.")
if bards is None:
    print('FAIL: no Legend Lore paragraph in lib/classes.irh')
    fails.append('help missing')
elif want_help not in bards:
    print('FAIL: lib/classes.irh lacks the new Legend Lore sentence')
    fails.append('help text')
if bards is not None and 'not a skill check' in bards:
    print('FAIL: the old phrase "not a skill check" is still in lib/classes.irh')
    fails.append('old help phrase')

abil = joined('src/Tables.cpp', r'\{ CA_LEGEND_LORE, "Legend Lore",(.*?)\},')
want_abil = ("The first time you see or pick up an unidentified magic item,"
             " you make one Knowledge (Magic) check against the item's level.")
if abil is None:
    print('FAIL: no CA_LEGEND_LORE row in src/Tables.cpp')
    fails.append('ability missing')
elif want_abil not in abil:
    print('FAIL: src/Tables.cpp lacks the new Legend Lore sentence')
    fails.append('ability text')
if abil is not None and 'Each item is checked against 10 plus your ability' in abil:
    print('FAIL: the old phrase "Each item is checked against 10 plus your ability" is still in src/Tables.cpp')
    fails.append('old ability phrase')
sys.exit(1 if fails else 0)
PY
then
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    echo "  ok    C: the new help and ability text is in place"
else
    CHECK_FAIL=1
    echo "  FAIL  C: the help or ability text is wrong (see above)"
fi

check_done "Legend Lore feeds Knowledge (Magic) and Intuition in full and rolls once per item"
