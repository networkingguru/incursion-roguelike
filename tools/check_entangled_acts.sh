#!/bin/bash
# inc-18q6, phase 2. Entanglement must cost -4 Dexterity and -2 to hit,
# without anchoring the creature or preventing movement and weapon attacks.
# The oracle is the game's sheets, live status line, position and attack roll.
# R3 compares one-square moves by the same character in the same run.
# Allow +/- 2 game ticks around twice the floor cost: integer timeout division
# and scheduling round each move, so a one-tick baseline error doubles.
# A passed save must print "You've become entangled!", not the STUCK message.
#
# THE SUBJECT is the orc rogue of tools/keys/chargen-rogue.keys, not the human
# paladin check_entangle_escape.sh keeps. Both this check and that one need a
# chain of independent DC 15 Reflex saves to line up (tanglefoot re-rolls that
# save on every move AND every strike from the square, lib/alchemy.irh), and
# the paladin's Reflex save is bad enough that seeds 1 to 10 all failed to
# ever get him moving-or-striking-while-merely-entangled at all -- a previous
# version of this check ran on him and never passed on any of ten seeds. A
# rogue's Reflex progression plus his Dexterity gives him a real bonus on
# this save (Reflex +5 on seed 4, a 55% chance per independent roll), so a
# bounded chain of retries has a real chance of finishing rather than
# measuring dice. check_entangle_escape.sh is untouched and keeps its
# paladin: it tests heavy-armour escape, which needs the bad Reflex save this
# check needed to get away from.
#
# The move and the attack are EACH a real roll (tanglefoot strands re-rolls
# its own Reflex DC 15 on every attempt to leave or strike from the square,
# lib/alchemy.irh), so tools/keys/entangled-acts.keys attempts each up to ten
# times, spending moves to clear a Stuck result before trying again. This
# script does not assert on a fixed attempt: it finds the FIRST attack
# attempt that landed a printed "Attack:" line while Entangled and not Stuck,
# and the FIRST move attempt that actually changed position under the same
# condition, and grades those two independently -- neither attempt number
# has to be the first, and they do not have to be adjacent to each other or
# in any particular order relative to one another. Ten attempts all sticking
# is a measurement failure, not a defect, so it exits INCONCLUSIVE rather
# than FAIL.
#
# THE PROBABILITY THIS RESTS ON. Each independent attempt (move-or-recover,
# attack-or-recover) needs one of two rolls to succeed: the DC 15 Reflex the
# terrain re-rolls (about 55% on this subject), or, once Stuck, a DC 17
# Strength check to escape (about 30% on this subject -- Escape Artist is
# not a viable second path for him, being DC 22 against a +0 modifier).
# Ten attempts is generous against either: the chance of ten independent DC
# 15 Reflex rolls ALL failing is 0.45^10, about 3 in 10,000; even in the
# worse case of needing to first tear free from Stuck at 30% a shot, the
# chance of exhausting all ten attempts is under 3%. Measured on seed 4: the
# attack succeeded on attempt 1 of 10; the move succeeded on attempt 9 of 10
# after eight rounds of Stuck-and-still-Stuck, both comfortably inside the
# budget this script allows.
#
# THE FLOOR BASELINE IS TAKEN LAST, AFTER THE FIGHT, NOT FIRST. A rogue
# starts Hiding, which is its own movement penalty ("50% hiding" on the
# Movement Rate line), and combat ends it -- measured while building this
# fixture, every status line from the attack loop onward carries no Hiding
# tag, where every one before combat still does. Comparing an ordinary move
# taken while Hiding against an entangled move taken after Hiding ended
# would be comparing two different subjects, not one subject with and
# without Entangled. So the fixture pays the entangled cost first (from the
# same, already fight-worn, no-longer-hiding subject) and measures the
# floor cost last, after the move loop has walked him back off both
# tanglefoot squares onto ordinary ground -- both halves of the R3
# comparison are the one post-combat subject.
#
# Wrong subject/setup exits 2; a measured violation exits 1. Prove red by
# temporarily reverting only the ENTANGLED bonus block in src/Values.cpp.
# Usage: tools/check_entangled_acts.sh (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
       INCURSION_MAP_AUDIT=0 tools/headless.sh tools/keys/entangled-acts.keys 4 2>&1)"
result=$?
run="$(echo "$out" | awk '/^run:/ {print $2}')"
if [ "$result" != 0 ] || [ ! -d "$run/logs/screens" ]; then
    echo "INCONCLUSIVE: the fixture did not finish its gameplay setup."
    echo "$out"
    exit 2
fi
python3 - "$run" <<'PY'
import pathlib
import re
import sys

run = pathlib.Path(sys.argv[1])
screens = run / 'logs/screens'

def inconclusive(message):
    print('INCONCLUSIVE: ' + message)
    print('      run: ' + str(run))
    sys.exit(2)

def screen(label):
    files = list(screens.glob('*-' + label + '.txt'))
    if len(files) != 1:
        inconclusive('missing or ambiguous ' + label + ' screen.')
    return files[0].read_text()

def screen_opt(label):
    files = list(screens.glob('*-' + label + '.txt'))
    return files[0].read_text() if files else None

def status(text):
    return next((line.split('|')[0] for line in text.splitlines()
                 if line.startswith('HP:')), '')

def entangled(text):
    return bool(re.search(r'\b(?:Entangled|Ent)\b', status(text)))

def stuck(text):
    return bool(re.search(r'\b(?:Stuck|Stk)\b', status(text)))

def position(text):
    # This fixture never lets the display scroll (it moves the subject
    # across a handful of squares in a room far wider than that), so the
    # player's own raw column is a stable position signal on its own --
    # no landmark glyph is needed, and none is guaranteed to be in view:
    # this room, generated after a different amount of chargen dice than
    # the paladin fixtures consume, never shows a '#' wall within range.
    rows = [line.split('|')[0] for line in text.splitlines() if '@' in line]
    if len(rows) != 1:
        inconclusive('cannot locate the player on the map row.')
    return rows[0].index('@')

def turn(text):
    return int(re.search(r'^=== screen .* turn (\d+) ===', text)[1])

MAX_ATTEMPTS = 10

def find_move_success():
    tried = 0
    for i in range(1, MAX_ATTEMPTS + 1):
        b = screen_opt(f'before{i}')
        m = screen_opt(f'moved{i}')
        if b is None or m is None:
            break
        tried = i
        if (position(m) == position(b) - 1 and turn(m) > turn(b)
                and entangled(m) and not stuck(m)):
            return i, b, m
    inconclusive(f'none of {tried} entangled-move attempts actually changed '
                 'position while Entangled and not Stuck -- every one Stuck '
                 'instead of moving.')

def find_attack_success():
    tried = 0
    for i in range(1, MAX_ATTEMPTS + 1):
        ba = screen_opt(f'before-attack{i}')
        a = screen_opt(f'attacked{i}')
        if ba is None or a is None:
            break
        tried = i
        if (entangled(a) and not stuck(a)
                and re.search(r'^Attack: 1d20 .*\[(?:hit|miss)\]', a, re.M)):
            return i, a
    inconclusive(f'none of {tried} attack attempts landed a printed '
                 'Attack: line while Entangled and not Stuck -- every one '
                 'Stuck instead of striking.')

base = screen('baseline')
entry = screen('entry')
sheet = screen('entangled-sheet')
attack_n, attacked = find_attack_success()
move_n, before, moved = find_move_success()
floor_before = screen('floor-before')
floor_after = screen('floor-after')

if not all(token in base for token in (
        'Race   Orc', 'Class  Rogue 1', 'DEX: 17/00', 'Melee   +toHit +2')):
    inconclusive('the subject is not the seed-4 orc rogue with DEX 17 and melee +2.')
if not re.search(r'Reflex Save:.*vs DC 15 \[success\]', entry):
    inconclusive('the entry did not measure a successful tanglefoot save.')
if not re.search(r'Strength Check:.*vs DC 17 ', entry):
    inconclusive("the painted hazard did not carry STUCK_BONDED (R14): no "
                 "Strength check was ever rolled against DC 17, tanglefoot "
                 "strands' own escape DC. The room's map name line does not "
                 "always print the terrain's feature name (observed: it did "
                 "for the paladin fixture's chamber and does not for this "
                 "seed's rogue chamber, a cosmetic difference in the "
                 "generated dungeon, not a mechanical one), so the DC is "
                 "read here instead of the name.")
if not entangled(entry) or stuck(entry):
    inconclusive('the entry did not produce an entangled, unanchored subject.')

if entangled(floor_before) or stuck(floor_before) or entangled(floor_after) or stuck(floor_after):
    inconclusive('the post-combat floor baseline was still entangled or stuck -- '
                 'the move loop did not walk the subject clear of both '
                 'tanglefoot squares before the baseline was measured.')
if position(floor_after) != position(floor_before) + 1 or turn(floor_after) <= turn(floor_before):
    inconclusive('the post-combat baseline did not move one square and spend game time.')
floor_cost = turn(floor_after) - turn(floor_before)
entangled_cost = turn(moved) - turn(before)

failures = []
def require(condition, message):
    if not condition:
        failures.append(message)

require("You've become entangled!" in entry and "You've become stuck!" not in entry,
        'the passed-save entry must announce entangled without announcing stuck.')
require('DEX: 13/00' in sheet and '(base 17, -4 status)' in sheet,
        'the entangled sheet must show Dexterity 17 -> 13 with -4 status.')
require(bool(re.search(r'Melee\s+\+toHit \+0\s+.*-2 status', sheet)),
        'the entangled sheet must show melee to-hit +2 -> +0 with -2 status.')
require(entangled(attacked) and not stuck(attacked),
        'the attack must land while entangled and unanchored.')
require(bool(re.search(r'^Attack: 1d20 .*\[(?:hit|miss)\]', attacked, re.M)),
        'the entangled creature did not execute a melee attack and print its roll.')
require(entangled(before) and not stuck(before),
        'the subject must still be entangled and unanchored immediately before moving.')
require(position(moved) == position(before) - 1 and turn(moved) > turn(before),
        'the entangled creature did not move one square and spend game time.')
require(entangled(moved) and not stuck(moved),
        'the move must finish entangled and unanchored.')
require(abs(entangled_cost - 2 * floor_cost) <= 2,
        f'half-speed move cost {entangled_cost} ticks; post-combat floor cost '
        f'{floor_cost}, expected {2 * floor_cost} +/- 2.')

for message in failures:
    print('FAIL: ' + message)
if not failures:
    print('PASS: entangled without anchoring: Dexterity 17 -> 13 (-4 status), melee +2 -> +0 (-2 status).')
    print(f'      Half-speed move: post-combat floor {floor_cost} ticks, entangled '
          f'{entangled_cost} ticks (expected {2 * floor_cost} +/- 2).')
    print(f'      Attack attempt {attack_n} of {MAX_ATTEMPTS} landed a melee attack; '
          f'move attempt {move_n} of {MAX_ATTEMPTS} moved one square, '
          'both while entangled and not stuck.')
    print('      ' + next(line.split('|')[0].rstrip() for line in attacked.splitlines()
                          if line.startswith('Attack:')))
print('      run: ' + str(run))
sys.exit(1 if failures else 0)
PY
