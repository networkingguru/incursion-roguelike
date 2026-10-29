#!/bin/bash
# gate: live
# inc-nk27: whole-topic XPrint silently truncates Class Descriptions.
# fact: topic identity and BOOK contents -- static module text, title-menu
#   @choose and tools/gates/Options.Dat; seed-independent invariant (VERIFICATION).
# fact: final class text -- static Underdark Warrior Desc, lib/prestige.irh;
#   invariant on every seed: its final table ends "Zen Defense, Defensive Roll".
# fact: final race text -- static Wood Elf Desc, lib/subraces.irh;
#   invariant on every seed: its equipment ends "are thus twice as strong."
# fact: final domain text -- static sorted unique-domain spells, HelpDomains;
#   lib/domains.irh includes Wrack, lib/wspells.irh defines it as EA_NOTIMP;
#   invariant on every seed: Wrack ends with the default "(Resource Zero)".
# fact: final pantheon text -- static Zurvash Desc, lib/religion.irh;
#   invariant on every seed: it ends "more profusely than normal."
# fact: scrolling reached the end -- PGDN*512 exceeds MAX_SCROLL_LINES=8192
#   at the fixed headless height; another PGDN must leave screen cells unchanged.
# fact: run completed without errors -- harness status plus its assertion log;
#   status 5 is expected for title-menu help without a character or map.
# No character, world, roll, or seed-decided text is read. These are the
# every-seed invariants permitted after the controls catalog in VERIFICATION.md.
# Usage: tools/check_help_truncation.sh [seed]
# Exit 0: all pass; 1: missing ending; 2: any topic could not be measured.
# Specimens are retained under logs/; no build or source mutation here.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BIN="${INCURSION_BIN:-./incursion-headless}"
OPTS="$ROOT/tools/gates/Options.Dat"
SEED="${1:-1}"
if [ ! -x "$BIN" ] || [ ! -f "$OPTS" ] || ! command -v python3 >/dev/null; then
    echo 'INCONCLUSIVE: need python3, gate options and a headless build.'
    echo 'Build: BACKEND=posix ./build_macos.sh'
    exit 2
fi
for topic in class race domain pantheon; do
    [ -f "tools/keys/$topic-help-end.keys" ] || {
        echo "INCONCLUSIVE: missing $topic key script"; exit 2;
    }
done
mkdir -p "$ROOT/logs"
RUN="$(mktemp -d "$ROOT/logs/help-truncation.XXXXXX")" || exit 2
echo "Specimens: $RUN"
for topic in class race domain pantheon; do
    INCURSION_LOAD= INCURSION_BIN="$BIN" INCURSION_OPTIONS="$OPTS" \
        INCURSION_RUN_DIR="$RUN/$topic" \
        tools/headless.sh "tools/keys/$topic-help-end.keys" "$SEED" \
        > "$RUN/$topic.out" 2>&1
    echo "$?" > "$RUN/$topic.status"
done
python3 - "$RUN" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
cases = [
    ('class', 'CLASS DESCRIPTIONS', 'Zen Defense, Defensive Roll',
     'THE UNDERDARK WARRIOR'),
    ('race', 'RACE DESCRIPTIONS', 'are thus twice as strong.', 'WOOD ELF'),
    ('domain', 'DOMAIN ALLOCATIONS', '(Resource Zero)', 'Wrack (Special Ability)'),
    ('pantheon', 'THE THEYRAN PANTHEON', 'more profusely than normal.', 'Zurvash'),
]
failed = inconclusive = False

def cells(path):
    # Drop only the dump metadata, which contains a changing key count.
    return path.read_text().split('\n', 1)[1]

def lines(screen):
    return [line.split('|', 1)[1].rsplit('|', 1)[0].strip()
            for line in screen.splitlines() if line.count('|') >= 2]

for topic, identity, ending, entry in cases:
    screens = root / topic / 'logs/screens'
    start = screens / f'0001-{topic}-help-start.txt'
    end = screens / f'0002-{topic}-help-end.txt'
    confirm = screens / f'0003-{topic}-help-end-confirm.txt'
    status = int((root / f'{topic}.status').read_text())
    reason = None
    if not all(p.is_file() for p in (start, end, confirm)):
        reason = 'missing topic/start/end/confirmation dump'
    elif identity not in cells(start) or '-- HELP --' not in cells(start):
        reason = f'dump does not show the {identity} book topic'
    elif status not in (0, 5):
        reason = f'harness exited {status}; see {root / (topic + ".out")}'
    elif cells(end) != cells(confirm):
        reason = 'another page-down changed the final screen'
    # headless.sh can retain status 5 even when it logs a new assertion.
    assert_log = root / topic / 'logs/errors.log'
    if assert_log.exists() and 'ASSERT failed:' in assert_log.read_text():
        reason = f'engine assertion; see {assert_log}'
    if reason:
        print(f'INCONCLUSIVE {topic}: {reason}')
        inconclusive = True
        continue
    body = [line for line in lines(cells(end)) if line]
    text = re.sub(r'\s+', ' ', ' '.join(body))
    ok = entry in text and text.endswith(ending)
    print(f'{"GREEN/PASS" if ok else "RED/FAIL"} {topic}: {end}')
    print('  Last lines: ' + ' / '.join(body[-3:]))
    if not ok:
        print(f'  Expected final entry {entry!r}, ending {ending!r}')
        failed = True
sys.exit(2 if inconclusive else 1 if failed else 0)
PY
