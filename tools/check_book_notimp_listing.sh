#!/bin/bash
# gate: live
# Regression reproduction for unmarked stub spells in book descriptions,
# bd inc-lqc7.
#
# THE ORACLE IS THE GAME'S OWN ITEM DESCRIPTION. Wizard acquisition supplies
# Planar Bindings; Examine renders its "Spellbook:" sentence. Conjure Earth
# Elemental must carry "(not implemented yet)"; Protection from Evil must
# remain unmarked. Missing screens, incomplete listings and failed sessions
# fail explicitly, so a broken key script cannot pass without measuring.
# Whitespace is folded only after reading the rendered screen, allowing wraps
# inside a spell name or between that name and its marker.
#
# Usage: tools/check_book_notimp_listing.sh    (0 pass, 1 fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SEED=1
KEYS=tools/keys/book-notimp-listing.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUNBASE="${INCURSION_RUN_DIR:-$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-check-book-notimp-listing}"
# Refuse old dumps: a reused run directory must never supply the oracle.
if [ -e "$RUNBASE" ]; then
    echo "FAIL: run directory already exists; choose a fresh directory: $RUNBASE"
    exit 1
fi
OUT="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
       INCURSION_RUN_DIR="$RUNBASE" tools/headless.sh "$KEYS" "$SEED" 2>&1)"
STATUS=$?
RUN="$(echo "$OUT" | awk '/^run:/ {sub(/^run:[[:space:]]*/, ""); print; exit}')"
echo "Run dir: $RUN"
if [ "$STATUS" -ne 0 ]; then
    echo "FAIL: headless session exited $STATUS; no valid measurement."
    echo "$OUT"
    exit 1
fi

python3 - "$RUN/logs/screens" <<'PY'
from pathlib import Path
import re
import sys

dumps = list(Path(sys.argv[1]).glob('*-book-notimp-listing.txt'))
if len(dumps) != 1:
    sys.exit('FAIL: expected one book description screen; nothing was measured.')
dump = dumps[0]
print(f'Dump: {dump}')
screen = dump.read_text(errors='replace')
# The description box overlays the inventory. Crop to its rendered border
# before joining lines, otherwise slot labels interrupt wrapped spell names.
lines = screen.splitlines()
panel = []
for index, line in enumerate(lines):
    border = re.search(r'#-{10,}#', line)
    if not border:
        continue
    left, right = border.start(), border.end() - 1
    for row in lines[index + 1:]:
        if row[left:right + 1] == border.group(0):
            break
        if len(row) > right and row[left] == row[right] == '|':
            panel.append(row[left + 1:right])
    break
flat = ' '.join(' '.join(panel).split())
if 'spellbook [planar bindings]' not in flat.lower():
    sys.exit('FAIL: description does not identify spellbook [Planar Bindings].')
match = re.search(r'Spellbook: It holds the spells? (.*?)\.', flat)
if not match:
    sys.exit('FAIL: complete Spellbook: listing not found on screen; nothing was measured.')
listing = match.group(1)
print(match.group(0))
marker = '(not implemented yet)'
failed = False
for name, expected in [('Conjure Earth Elemental', True),
                       ('Protection from Evil', False)]:
    entry = re.search(r'(?<!\w)' + re.escape(name) +
                      r'(?P<marker>\s*\(not implemented yet\))?(?=,| and |$)', listing)
    if not entry:
        print(f'FAIL: {name} entry missing or incomplete in Spellbook: listing.')
        failed = True
        continue
    marked = entry.group('marker') is not None
    if marked != expected:
        print(f'FAIL: {name} ' + (f'is missing {marker} in the listing.' if expected
                                else f'is implemented but carries {marker}.'))
        failed = True
    else:
        print(f'OK: {name} is ' + ('marked.' if marked else 'unmarked.'))
if failed:
    sys.exit(1)
print('PASS: the stub is marked and the implemented control is unmarked.')
PY
