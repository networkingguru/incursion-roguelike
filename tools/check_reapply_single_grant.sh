#!/bin/bash
# gate: live
# inc-7wmu: Item::ReApply must replace a worn item's standing grants, not add
# a second copy. Oracles: the character sheet (Will-line save annotations, CON,
# Hit Dice Rolls), the HP status line and the wizard stati screen.
# S1 Magic Weapon on the Bloodspear (orc barbarian, seed 4): Will "vs. spells"
#    reads +4 before, during and after the boost; item text proves start/end.
# S2 Storycraft on a worn Periapt of Proof against Poisons (orc bard, seed 1):
#    +1 -> +2 must take Will "vs. poison" from +2 to +4. The key script's
#    header traces Storycraft -> SetInherentPlus -> ReApply by file:line.
# S3 the Nine Lives Stealer SS_ENCH activation row (seed 4) is not a standing
#    grant and must survive a Magic Weapon re-apply.
# S4 Dispel Magic on the Bloodspear wielder (seed 1): Will "vs. spells"
#    4 -> 0 -> 4; aura and fade messages prove both transitions. Wizard stati
#    dumps before and after the dispel must lose no row Dispel cannot remove:
#    a re-apply that strips while Dispel walks the wearer miscounts one.
# S5 Storycraft on a worn Girdle of Tenacity +2 at 7 HP (orc bard, seed 1):
#    current HP must not move and the character must live. Losing the girdle's
#    CON would cost more HP than the character has; that arithmetic prints,
#    and the section measures nothing when it does not hold. S5 passes on the
#    unfixed engine and guards a fix that strips rows without guarding HP.
# All measured values print even when an assertion fails. Missing gameplay,
# routes, expected text or measurement screens fail as "measured nothing".
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || {
    echo 'FAIL: measured nothing; build with BACKEND=posix ./build_macos.sh'
    exit 1
}
run_keys() { # run_keys <keys> <seed> [allow-death]; S5 judges death itself
    local keys="$1" seed="$2" allow_death="${3:-}" out run rc
    out="$(INCURSION_BIN=./incursion-headless INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh "$keys" "$seed" 2>&1)"
    rc=$?
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if echo "$out" | grep -q 'NO GAMEPLAY'; then
        echo "FAIL: $keys measured nothing: NO GAMEPLAY" >&2
        echo "$out" >&2
        return 1
    fi
    if echo "$out" | grep -q 'the key script looked for something\|gave up after'; then
        echo "FAIL: $keys measured nothing: expected screen not reached" >&2
        echo "$out" >&2
        return 1
    fi
    if [ "$rc" != 0 ] || [ ! -d "$run/logs/screens" ] || { [ -z "$allow_death" ] &&
        ! echo "$out" | grep -q '^death:      none$'; }; then
        echo "FAIL: $keys measured nothing: unsuccessful gameplay run" >&2
        echo "$out" >&2
        return 1
    fi
    echo "$run"
}
need_screen() {
    [ -f "$1" ] || { echo "FAIL: measured nothing: no screen $1" >&2; return 1; }
}
status=0
for section in S1 S2 S3 S4 S5; do
    allow_death=
    case "$section" in
        S1) keys=magic-weapon; seed=4 ;;
        S2) keys=enchant; seed=1 ;;
        S3) keys=activation; seed=4 ;;
        S4) keys=dispel; seed=1 ;;
        S5) keys=hp; seed=1; allow_death=1 ;;
    esac
    echo "$section seed=$seed"
    run="$(run_keys "tools/keys/reapply-$keys.keys" "$seed" "$allow_death")" || { status=1; continue; }
    echo "screens: $run/logs/screens"
    need_screen "$run/logs/screens/0001-"*.txt || { status=1; continue; }
    python3 - "$section" "$run/logs/screens" <<'PY'
import collections
import pathlib
import re
import sys
section, directory = sys.argv[1:]
root = pathlib.Path(directory)
failures = []

def screen(label):
    paths = list(root.glob('*-' + label + '.txt'))
    if len(paths) != 1:
        failures.append('measured nothing: missing/ambiguous screen ' + label)
        return ''
    return paths[0].read_text()

def require(ok, reason):
    if not ok:
        failures.append('measured nothing: ' + reason)

def value(label, actual, expected):
    print(f'{section} {label}: {actual} (expected {expected})')
    if actual != expected:
        failures.append(f'{label}: got {actual}, expected {expected}')

def will(label, expected, against='spells'):
    text = screen(label)
    # The annotation wraps onto the line following Will. Stop at Melee so an
    # item description or another save cannot be mistaken for this oracle.
    match = re.search(r'^ Will\s+.*?(?=^ Melee\s)', text, re.M | re.S)
    require(match is not None, label + ' has no complete Will block')
    block = match[0] if match else ''
    bonuses = re.findall(r'([+-]\d+) vs\. ' + against, block)
    require(len(bonuses) <= 1, label + ' has ambiguous ' + against + ' bonuses')
    actual = int(bonuses[0]) if bonuses else (0 if match else None)
    value(label + ' Will vs. ' + against, actual, expected)

def number(label, pattern, what):
    found = re.search(pattern, screen(label), re.M)
    require(found is not None, label + ' shows no ' + what)
    return int(found[1]) if found else None

def selected(label, name):
    text = screen(label)
    rows = [line.strip() for line in text.splitlines() if '[a]' in line]
    print(f'{section} {label} selected [a]: ' + ' '.join(rows))
    require(len(rows) == 1 and name in rows[0], label + ' did not target ' + name)

def evidence(label, pattern, description):
    text = screen(label)
    found = re.search(pattern, text, re.I | re.S)
    print(f'{section} {description}: {bool(found)}')
    require(found is not None, description)
    return text

def stati(label):
    # The wizard dump's left pane is 63 columns; a longer line wraps.
    lines = [line[:63].ljust(63) for line in screen(label).splitlines()]
    heads = [i for i, line in enumerate(lines) if re.match(r'Stati \(\d+\):', line)]
    ends = [i for i, line in enumerate(lines) if line.startswith('Inventory:')]
    whole = len(heads) == 1 and len(ends) == 1 and heads[0] < ends[0]
    require(whole, label + ' does not show the whole stati list')
    if not whole:
        return []
    # A row opens "  NATURE from SS ..."; its handle line opens with twelve
    # spaces and "(h:" or "(eID:". Any other line continues a wrapped one.
    logical, entries = [], []
    for line in lines[heads[0] + 1:ends[0]]:
        if re.match(r'  [A-Z]| {12}\(', line) or not logical:
            logical.append(line)
        else:
            logical[-1] += line
    for line in logical:
        if re.match(r'  [A-Z]', line):
            entries.append([line.strip(), ''])
        elif entries and not entries[-1][1]:
            entries[-1][1] = line.strip()
        else:
            require(False, label + ' has an unreadable stati line: ' + line.strip())
    rows = []
    for row, detail in entries:
        head = re.match(r'(.+?) from (SS \w+)', row)
        owner = re.match(r'\(h:(.*?)\)(?: \(eID:.*\))?$', detail)
        require(head is not None, label + ' has an unreadable stati row: ' + row)
        if head:
            rows.append((head[1], head[2], owner[1] if owner else '-'))
    total = int(re.match(r'Stati \((\d+)\):', lines[heads[0]])[1])
    print(f'{section} {label}: {len(rows)} stati rows read, header says {total}')
    require(len(rows) == total, label + ' stati rows do not match the header count')
    return rows

if section == 'S1':
    will('orc-sheet-without-bloodspear', 0)
    will('orc-sheet-with-bloodspear', 4)
    will('boosted-sheet', 4)
    will('expired-sheet', 4)
    selected('read-target', 'Bloodspear')
    evidence('orc-wielded', r'b\)Weapon Hand.*Bloodspear', 'Bloodspear wielded')
    evidence('cast', r"longspear 'Bloodspear'.*soft silvery glow", 'Magic Weapon cast took')
    for label, expected in [('boosted-item', 1), ('expired-item', 0)]:
        text = screen(label)
        require('Cost: It has a base value' in text, label + ' description footer not reached')
        value(label + ' Magic Weapon description count', text.count('Magic Weapon:'), expected)
    evidence('rested', r'You awaken feeling well.*rested and recovered', 'rest completed')
elif section == 'S2':
    will('sheet-without-periapt', 0, 'poison')
    will('sheet-with-periapt', 2, 'poison')
    will('sheet-enchanted', 4, 'poison')
    evidence('periapt-worn', r'o\)Neck\s*:Periapt of Proof against Poisons \+1', 'Periapt +1 worn')
    evidence('augment-menu', r'\[\w\] a Periapt of Proof against Poisons \+1', 'Storycraft offered the Periapt')
    evidence('augmented', r'mythic grandeur about your Periapt of Proof', 'Storycraft took')
    evidence('equipment-enchanted', r'o\)Neck\s*:Periapt of Proof against Poisons \+2', 'Periapt worn at +2')
elif section == 'S3':
    selected('activate-target', 'Nine Lives Stealer')
    selected('read-target', 'Nine Lives Stealer')
    evidence('orc-wielded', r'b\)Weapon Hand[^\n]*Long Sword, Nine Lives\.\.\.', 'Nine Lives Stealer wielded')
    evidence('activated', r'Nine Lives Stealer.*glows a malignant.*crimson', 'activation took')
    evidence('cast', r'Nine Lives Stealer.*soft silvery.*glow', 'Magic Weapon cast took')
    for label in ['activation-before', 'activation-after']:
        text = screen(label)
        rows = re.findall(r'EFF FLAG1 from SS ENCH[^\n]*\n[^\n]*', text)
        own = [row for row in rows if '(h:Long Sword, Nine Lives Stealer' in row]
        require('Stati (' in text or 'Inventory:' in text, label + ' stati view not reached')
        value(label + ' sword-keyed SS_ENCH EFF_FLAG1 rows', len(own), 1)
        for row in own:
            print('  ' + ' '.join(row.split()))
elif section == 'S4':
    will('orc-sheet-without-bloodspear', 0)
    will('orc-sheet-with-bloodspear', 4)
    will('dispelled-sheet', 0)
    will('restored-sheet', 4)
    evidence('orc-wielded', r'b\)Weapon Hand.*Bloodspear', 'Bloodspear wielded')
    evidence('dispel-target', r"wielding a longspear 'Bloodspear'", 'Dispel targeted wielder')
    evidence('dispelled', r"Your longspear.*'Bloodspear'.*surrounded with a dull grey.*aura", 'Bloodspear suppression took')
    evidence('dispel-ended', r"The grey glow fades from your longspear 'Bloodspear'", 'Bloodspear suppression expired')
    # Dispel may remove only these sources (src/Effects.cpp:1082); any other
    # row that goes missing was lost to a miscounted removal. Durations tick.
    before = collections.Counter(stati('stati-before'))
    gone = sorted((before - collections.Counter(stati('stati-after'))).elements())
    for nature, source, owner in gone:
        print(f'  gone: {nature} from {source} (h:{owner})')
    require(any(n == 'SAVE BONUS' and 'Bloodspear' in h for n, s, h in gone),
            'the stati dumps do not bracket the Bloodspear dispel')
    lost = [' '.join(row) for row in gone
            if row[1] not in ('SS ENCH', 'SS ITEM', 'SS ONCE', 'SS ATTK')]
    value('undispellable rows lost in the dispel', lost, [])
else:
    evidence('girdle-worn', r'g\)Belt\s*:Girdle \+2 of Tenacity', 'Girdle +2 worn')
    evidence('sheet-with-girdle', r'CON: 14/\d+.*\(base 12, \+2 magic\)', 'girdle grants CON 14')
    evidence('learned', r'Learned\.', 'Divine Sacrifice learned')
    evidence('augmented', r'mythic grandeur about your Girdle \+2 of', 'Storycraft took')
    evidence('sheet-enchanted', r'CON: 15/\d+.*\(base 12, \+3 magic\)', 'girdle now grants CON 15')
    bare = number('sheet-without-girdle', r'^ Hit Dice Rolls\s+(\d+)', 'max HP')
    worn = number('sheet-with-girdle', r'^ Hit Dice Rolls\s+(\d+)', 'max HP')
    before = number('hp-before', r'^HP:(-?\d+)/', 'current HP')
    after = number('hp-after', r'^HP:(-?\d+)/', 'current HP')
    if None not in (bare, worn, before):
        cost = worn - bare
        print(f'S5 sheet max HP {bare} without the girdle, {worn} with it: its CON is worth {cost} HP')
        print(f'S5 losing it at {before} HP would leave {before} - {cost} = {before - cost}')
        require(cost > 0 and before - cost <= 0, 'current HP is not low enough to be at risk')
    deaths = root.parent / 'death.log'
    died = deaths.exists() and '=== character died' in deaths.read_text()
    shown = ' '.join(screen(label) for label in ('augmented', 'hp-after', 'sheet-enchanted'))
    signs = [s for s in ('Die? [yn]', 'drop dead', 'renewed seriousness') if s in shown]
    print(f'S5 death logged: {died}; death text on screen: {signs or "none"}')
    value('alive after enchant', not died and not signs, True)
    value('current HP after enchant', after, before)
for failure in failures:
    print(f'{section} FAIL: {failure}')
if not failures:
    print(section + ' PASS')
sys.exit(bool(failures))
PY
    [ "$?" = 0 ] || status=1
done
exit "$status"
