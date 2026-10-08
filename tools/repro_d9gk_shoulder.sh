#!/bin/bash
# inc-d9gk guards bd inc-d9gk: a weapon on a shoulder is not a held weapon.
# With a bow or a thrown-only weapon (bolas) in the weapon hand, a melee weapon
# on the LEFT shoulder must give no primal (metal) term on the Call Light chance
# and no weapon term in Defense Class (src/Values.cpp:334-346 promotes it).
# Oracle = printed Call Light chance and printed Defense Class, five states:
# bow+sword-left, bow+sword-right, bow+neither, bolas+sword-left, bolas+neither.
# The fixture druid has Expertise and a Wood Elf is proficient with the long
# sword, so a promoted sword adds +3 to Defense Class; without that feat the
# Defense Class assertion could not fail. A javelin does not qualify as
# thrown-only (its group holds WG_SPEARS), so bolas stand in.
# On the unfixed tree it MUST exit 1: FAIL lines for left (primal AND Defense
# Class) and for thrownleft (primal AND Defense Class).
# Exit 0 = PASS; 1 = an assertion failed; 2 = a value or item not found.
# --read RUN parses existing specimens; missing values/equipment exit 2.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
if [ "${1:-}" = --read ]; then
    RUN="${2:?usage: --read RUN}"
else
    RUN="logs/d9gk/repro-$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$RUN"
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav \
    INCURSION_RUN_DIR="$RUN" \
        tools/headless.sh tools/keys/druid-shoulder-metal.keys 7 > "$RUN/harness.log" 2>&1 || {
        echo "UNMEASURED: see $RUN/harness.log" >&2; exit 2;
    }
fi
python3 - "$RUN" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
BOW = 'elven darkwood short bow'
# state, weapon hand, ready hand, L. Shoulder, R. Shoulder, Defense Class partner
STATES = [('left', BOW, BOW, 'long sword', 'Empty', 'neither'),
          ('right', BOW, BOW, 'Empty', 'long sword', 'neither'),
          ('neither', BOW, BOW, 'Empty', 'Empty', None),
          ('thrownleft', 'bolas', 'Empty', 'long sword', 'Empty', 'thrownnone'),
          ('thrownnone', 'bolas', 'Empty', 'Empty', 'Empty', None)]
try:
    rows = []
    dc = {}
    spells = {}
    for state, wep, ready, left, right, _ in STATES:
        def screen(kind):
            paths = list((root / 'logs/screens').glob(f'*-{state}-{kind}.txt'))
            if len(paths) != 1:
                raise ValueError(f'{state}: missing/ambiguous {kind} screen')
            return paths[0].read_text()
        gear, spell, sheet = screen('gear'), screen('spell'), screen('sheet')
        spells[state] = spell
        for label, value in [('Weapon Hand', wep), ('Ready Hand', ready),
                             ('L. Shoulder', left), ('R. Shoulder', right),
                             ('Armour', 'elven cord armour')]:
            if not re.search(re.escape(label) + r'\s*:' + re.escape(value) + r'\s', gear):
                raise ValueError(f'{state}: wrong or missing {label}')
        if not re.search(r"'In the Air':Empty\s", gear):
            raise ValueError(f'{state}: item left in air')
        chance = re.search(r'^\s*(Chance: .+? = (\d+)%)\s*$', spell, re.M)
        row = re.search(r'Call Light\s+\d+\s+\d+\s+(\d+)%', spell)
        if not chance or not row or chance[2] != row[1]:
            raise ValueError(f'{state}: missing/inconsistent Call Light chance')
        dc_line = re.search(r'^\s*Defense Class\s+(\d+)\s*\((.*)\)\s*$', sheet, re.M)
        if not dc_line:
            raise ValueError(f'{state}: missing Defense Class line')
        dc[state] = int(dc_line[1])
        primal = re.search(r'[+-]\d+% primal', chance[1])
        rows.append(f'{state}: {primal[0] if primal else "primal term absent"}; '
                    f'{chance[1]}; failure {100-int(row[1])}% (calculated); '
                    f'Defense Class {dc[state]} ({dc_line[2]})')
    print('\n'.join(rows))
    failed = False
    for state, _w, _r, _l, _rs, partner in STATES:
        primal = re.search(r'([+-]\d+% primal)', spells[state])
        if primal:
            print(f'FAIL: {state} state shows a primal term ({primal[1]})')
            failed = True
        if partner and dc[state] != dc[partner]:
            print(f'FAIL: {state} Defense Class {dc[state]} '
                  f'differs from {partner} Defense Class {dc[partner]}')
            failed = True
    print(f'Specimens: {root}/logs/screens; harness: {root}/harness.log')
    if failed:
        sys.exit(1)
    print('PASS')
    sys.exit(0)
except (OSError, ValueError) as exc:
    print(f'UNMEASURED: {exc}', file=sys.stderr)
    sys.exit(2)
PY
