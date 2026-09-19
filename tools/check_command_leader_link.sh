#!/bin/bash
# Reproduction for inc-6ax7. Expected RED on the unfixed CHARMED path.
# Uses only captured wizard Examine screens, never a probe or source grep.
# A: hostile control; B: retained summoner; C: mutual non-hostility.
# Exit 0 = all pass, 1 = measured failure, 2 = INCONCLUSIVE.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SEED=5
KEYS=tools/keys/command-leader-link.keys

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: build first with BACKEND=posix ./build_macos.sh"
    exit 2
}

# A loaded save or alternate binary would invalidate the pinned control.
OUT="$(unset INCURSION_LOAD INCURSION_BIN; INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
STATUS=$?
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCR="$RUN/logs/screens"
echo "screens: $SCR"
if [ "$STATUS" != 0 ]; then
    echo "A CONTROL: INCONCLUSIVE -- headless session exited $STATUS."
    echo "B SUMMONER: INCONCLUSIVE -- incomplete session."
    echo "C MUTUAL HOSTILITY: INCONCLUSIVE -- incomplete session."
    echo "$OUT" | tail -20
    exit 2
fi

python3 - "$SCR" <<'PY'
from pathlib import Path
import re
import sys

screens = Path(sys.argv[1])

def screen(label):
    matches = list(screens.glob('*-' + label + '.txt'))
    if len(matches) != 1:
        raise ValueError('missing or ambiguous screen: ' + label)
    return matches[0].read_text().splitlines()[1:]

def debug(label):
    # WIN_DEBUG occupies rows 4..45. Strip the sidebar and scroll arrows;
    # never search the stale messages above it or the Things in View list.
    return '\n'.join(line[:63].rstrip() for line in screen(label)[4:46])

def identity(label):
    text = debug(label)
    match = re.search(r"kobold \(class T_MONSTER, hObj (\d+)\)", text)
    if not match:
        raise ValueError(label + ': not a kobold Examine dump')
    return match[1]

def sections(label):
    text = '\n'.join(debug(label + '-page' + str(i)) for i in range(1, 5))
    # Require both boundaries: absence on an incomplete page is not evidence.
    match = re.search(r'---------- Target System:(.*?)---------- Hostility:'
                      r'(.*?)---------- tmID:', text, re.S)
    if not match:
        raise ValueError(label + ': complete Target System/Hostility not captured')
    return match.groups()

def inconclusive(reason, control_passed=False):
    if not control_passed:
        print('A CONTROL: INCONCLUSIVE -- ' + reason)
    print('B SUMMONER: INCONCLUSIVE -- ' + reason)
    print('C MUTUAL HOSTILITY: INCONCLUSIVE -- ' + reason)
    sys.exit(2)

try:
    switches = '\n'.join(screen('measurement-switches'))
    for name in ('Freeze Monsters', 'Know All Spells', 'Infinite Mana',
                 'Ignore Spell Failure', 'Wizard Sight'):
        if not re.search(re.escape(name) + r' +YES\b', switches):
            raise ValueError(name + ' not verified ON')
    if not re.search(r'Class +Mage 9\b', '\n'.join(screen('level'))):
        raise ValueError('Mage 9 not verified')
    control_id = identity('control-top')
    control, _ = sections('control')
    # Target::Dump names this player Volgar, not "you" on this build.
    enemy = re.search(r'With priority \d+ it views Volgar as an enemy\b', control)
    if not enemy:
        raise ValueError('control does not name Volgar as an enemy; key script has rotted')
except ValueError as exc:
    inconclusive(str(exc))

print('A CONTROL: PASS -- creature 1 views Volgar as an enemy before domination.')
print('  ' + enemy.group(0))

try:
    if identity('one-after-top') != control_id:
        raise ValueError('creature 1 identity changed')
    if identity('two-after-top') == control_id:
        raise ValueError('both readings are the same creature')
    for label in ('one', 'two'):
        status = debug(label + '-after-status')
        if not (re.search(r'CHARMED from SS_ENCH \(Val:CH_DOMINATE', status)
                and '(h:Volgar) (eID:Dominate Monster)' in status):
            raise ValueError(label + ': player-sourced Dominate Monster status missing')
    targets1, hostility1 = sections('one-after')
    _, hostility2 = sections('two-after')
    peers = []
    for text in (hostility1, hostility2):
        entries = re.findall(r'^kobold:.*(?:\n(?!\w+:|$).*)*', text, re.M)
        if len(entries) != 1:
            raise ValueError('missing or ambiguous peer in Hostility section')
        # SWrite hard-wraps at column 63, even in the middle of a word.
        lines = entries[0].splitlines()
        reading = lines[0]
        for previous, line in zip(lines, lines[1:]):
            reading += ('' if len(previous) == 63 else ' ') + line
        reading = ' '.join(reading.removeprefix('kobold: ').split())
        if not re.search(r'\b(enmity|enemy|allegiance|neutrality)\b', reading):
            raise ValueError('unrecognized peer Hostility reading')
        peers.append(reading)
except ValueError as exc:
    inconclusive(str(exc), control_passed=True)

summoner = re.search(r'views\s+Volgar\s+as\s+its\s+summoner\b', targets1)
if summoner:
    print('B SUMMONER: PASS -- creature 1 retains Volgar as its summoner.')
else:
    print('B SUMMONER: FAIL -- creature 1 has no "its summoner" entry naming Volgar after both dominations.')

# Hostility::Dump calls Enemy "enmity" (Target::Dump calls it "an enemy").
# Checking only the latter word here would pass while measuring hostility.
hostile = [bool(re.search(r'\b(enemy|enmity)\b', entry)) for entry in peers]
for direction, entry in zip(('1 -> 2', '2 -> 1'), peers):
    print('  ' + direction + ': ' + entry)
if any(hostile):
    print('C MUTUAL HOSTILITY: FAIL -- at least one dominated creature regards the other as an enemy (enmity).')
else:
    print('C MUTUAL HOSTILITY: PASS -- neither dominated creature regards the other as an enemy.')

# D: the player's reported symptom was an actual fight, not a reading of
# internal state. The Entry Chamber was genocided before either test kobold
# was summoned (see the key script), so the only two kobolds that can ever
# be named in a message are creature 1 and creature 2 -- any sentence that
# names "kobold" twice is necessarily one of them acting on the other, and
# any such sentence naming a strike (bite, claw, hit, miss, stab, slash,
# shoot, throw) is the fight the player described.
def logtext(label):
    # WIN_DEBUG's message-log box draws over the map, so every line of it
    # has the map to the left of a '|' and the sidebar to the right of
    # another; keep only what is between them. Same technique as
    # tools/check_grounded_stance_live.sh's logtext(), which reads the same
    # box.
    parts = []
    for line in screen(label):
        fields = line.split('|')
        if len(fields) >= 3:
            parts.append(''.join(fields[1:-1]))
    return ' '.join(' '.join(parts).split())

STRIKE = r'\b(bit(?:es|e)|claws?|hits?|misses?|strikes?|stabs?|slash(?:es)?' \
    r'|shoots?|throws?)\b'
try:
    flat = logtext('fight-log')
    if not flat:
        raise ValueError('fight-log dump is empty or unparsed')
    # Split on every sentence-ending mark the engine uses ('.' and '!'), not
    # '.' alone: an unsplit '!' glued an earlier, unrelated kobold-vs-player
    # message ("...gooey strands!" "This must be a ? tanglefoot bag!"
    # "Kobold's Attack: ...") into one fake two-kobold "sentence" the first
    # time this ran, and it read as D failing on the fixed build.
    fights = [s.strip() for s in re.split(r'[.!]', flat)
              if len(re.findall(r'\bkobold\b', s, re.I)) >= 2
              and re.search(STRIKE, s, re.I)]
except ValueError as exc:
    print('D FIGHT: INCONCLUSIVE -- ' + str(exc))
    d_inconclusive = True
    fights = []
else:
    d_inconclusive = False

if d_inconclusive:
    pass
elif fights:
    print('D FIGHT: FAIL -- a message shows one dominated kobold striking the other.')
    for line in fights:
        print('  ' + line + '.')
else:
    print('D FIGHT: PASS -- no message shows one dominated kobold striking the other,')
    print('  40 turns after Freeze Monsters came off with the two adjacent.')

if d_inconclusive:
    sys.exit(2)
sys.exit(1 if not summoner or any(hostile) or fights else 0)
PY
