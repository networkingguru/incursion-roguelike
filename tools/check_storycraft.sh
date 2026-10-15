#!/bin/bash
# gate: live
# inc-1brg: Storycraft (bard CA_STORYCRAFT, Character::CraftItem Augment:,
# src/Skills.cpp) must offer a +0 weapon, armor or shield for a first plus, and
# must ask for confirmation before it spends a charge. Frozen fixture: the orc
# bard tools/fixtures/chars/orc-bard-reapply-seed1.sav (5 unspent charges,
# plain orcish studded leather). Two runs: tools/keys/storycraft-menu.keys (A, D)
# and tools/keys/storycraft-confirm.keys (B, C).
# A  the +0 studded leather is in the "Augment which item?" menu (red on the
#    old code, which listed only items that already had a plus).
# B  choosing it shows the message "Raising the orcish studded leather to +1
#    spends one Storycraft charge and is permanent." plus the prompt "Spend the charge?", all words visible. 'n'
#    leaves the sheet at (+5 unallocated) and the item at +0.
# E  the longest name the fixture can reach ("the 40 orcish sheaf arrows"): the
#    message wraps, every word shows, 'n' leaves (+5 unallocated). Lenses +3 of
#    the Scholar (+3 -> +4, level 8) is refused: the bard's limit is level 6.
# C  'y' raises it to +1 and the sheet reads (+4 unallocated).
# D  the worn +0 noble attire (clothing, not armor) is not offered, and the
#    inventory shows it is worn. The fixture holds no +0 ring or amulet; wizard
#    Item Acquisition cannot make one (its "Item Level" sets the plus), so D
#    uses the clothing. Caveat: other filters (identification) could also hide
#    it; D passes on the old code too and only guards the new filter's reach.
# Every value prints. Missing menu, prompt, sheet line or inventory fails as
# "measured nothing".
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || {
    echo 'FAIL: measured nothing; build with BACKEND=posix ./build_macos.sh'
    exit 1
}
run_keys() { # run_keys <keys>; prints the run directory
    local keys="$1" out run rc
    out="$(INCURSION_BIN=./incursion-headless INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
           INCURSION_LOAD=tools/fixtures/chars/orc-bard-reapply-seed1.sav \
           tools/headless.sh "$keys" 1 2>&1)"
    rc=$?
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if grep -q 'NO GAMEPLAY\|the key script looked for something\|gave up after' <<< "$out" ||
       [ "$rc" != 0 ] || [ ! -d "$run/logs/screens" ]; then
        echo "FAIL: $keys measured nothing: unsuccessful gameplay run" >&2
        echo "$out" | tail -25 >&2
        return 1
    fi
    echo "$run"
}
status=0
menu_run="$(run_keys tools/keys/storycraft-menu.keys)" || { status=1; menu_run=; }
confirm_run="$(run_keys tools/keys/storycraft-confirm.keys)" || { status=1; confirm_run=; }
echo "screens: menu=$menu_run/logs/screens confirm=$confirm_run/logs/screens"
python3 - "$menu_run" "$confirm_run" <<'PY'
import pathlib
import re
import sys
roots = [pathlib.Path(a + "/logs/screens") if a else None for a in sys.argv[1:3]]
failures = []

def screen(label, root=None):
    root = root or roots[1]
    if root is None:
        failures.append('measured nothing: run for ' + label + ' failed')
        return ''
    paths = [q for q in root.glob('*.txt') if re.fullmatch(r'\d{4}-' + re.escape(label) + r'\.txt', q.name)]
    if len(paths) != 1:
        failures.append('measured nothing: missing/ambiguous screen ' + label)
        return ''
    return paths[0].read_text()

def value(label, actual, expected):
    print(f'{label}: {actual} (expected {expected})')
    if actual != expected:
        failures.append(f'{label}: got {actual}, expected {expected}')

def menu_rows(label):
    text = screen(label, roots[0])
    rows = re.findall(r'\[[a-z]\] ([^|]*?)\s*\|', text)
    if 'Augment which item?' not in text or not rows:
        failures.append('measured nothing: no Augment menu in ' + label)
    print(f'{label} rows: {rows}')
    return rows

def unallocated(label):
    found = re.findall(r'Storycraft \(\+(\d+) unallocated\)', screen(label))
    if len(found) != 1:
        failures.append('measured nothing: no Storycraft sheet line in ' + label)
        return None
    return int(found[0])

def armor(label):
    found = re.findall(r'Armour\s*:(orcish studded leather[^\n]*?)\s{2,}', screen(label))
    if len(found) != 1:
        failures.append('measured nothing: no armor row in ' + label)
        return None
    return found[0].strip()

ARMOR = 'a suit of orcish studded leather'
inv = screen('inventory-before', roots[0])
carried = [n for n in ("noble attire",) if n in inv]
value('A +0 armor carried before', armor('inventory-after-no') is not None, True)
rows = menu_rows('augment-menu')
value('A +0 studded leather offered', ARMOR in rows, True)
value('A control: Lenses +3 offered', any('Lenses +3' in r for r in rows), True)

def flat(label):
    # Join the message window's lines (and drop the right-hand sidebar) so a
    # wrapped message matches as words; every word must be present.
    lines = [l.split('|')[0] if '|' in l else l for l in screen(label).splitlines()[1:]]
    return ' '.join(' '.join(lines).split())

def message(label, item, plus):
    text = flat(label)
    want = f'Raising {item} to +{plus} spends one Storycraft charge and is permanent.'
    print(f'{label} text: {text[:230]!r}')
    value(label + ' full message', want in text, True)
    value(label + ' yn prompt', 'Spend the charge?' in text, True)

message('prompt-arrows', 'the 40 orcish sheaf arrows', 1)
value('E sheet after n', unallocated('sheet-after-arrows'), 5)
message('prompt-no', 'the orcish studded leather', 1)
value('B sheet before', unallocated('sheet-before'), 5)
value('B sheet after n', unallocated('sheet-after-no'), 5)
value('B armor after n', armor('inventory-after-no'), 'orcish studded leather')

message('prompt-yes', 'the orcish studded leather', 1)
value('C mythic message', 'mythic grandeur about your orcish studded' in screen('after-yes'), True)
value('C sheet after y', unallocated('sheet-after-yes'), 4)
value('C armor after y', armor('inventory-after-yes'), 'orcish studded leather +1')

value('D +0 non-weapons carried', carried, ["noble attire"])
offered = [n for n in carried if any(n in r for r in rows)]
value('D +0 non-weapons offered', offered, [])
for failure in failures:
    print('FAIL: ' + failure)
if not failures:
    print('PASS')
sys.exit(bool(failures))
PY
[ "$?" = 0 ] || status=1
exit "$status"
