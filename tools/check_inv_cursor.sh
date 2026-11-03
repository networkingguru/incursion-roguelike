#!/bin/bash
# gate: live
# inc-y2fkq: FirstInv()/NextInv() keep their cursor in a function-local static
# (Character::GetInv, Monster::GetInv, src/Inv.cpp), one cursor for every
# Character and one for every Monster. A walk begun inside another walk of the
# same class moves the outer cursor: an inner walk that runs to the end stops
# the outer walk early; an inner walk that breaks leaves the cursor mid-pack, so
# the outer walk revisits items and can loop forever. Measured live by
# InvCursorProbe (src/InvCursorProbe.cpp). Each case runs an outer walk, calls
# code that walks the same pack, and compares the outer visit count with an
# unnested walk of the same pack (containers and their contents included). An
# outer walk that passes 4x the true count is stopped and reported BAD.
#   1 player pack, CalcValues() in the body (hub: ConcentBuffer -> SkillKitMod)
#   2 player pack, SkillLevel(SK_INTUITION) in the body
#   3 player pack, event handler that walks the pack: the "Sticks to Snakes"
#     EV_ISTARGET handler (lib/abilities.irh), reached by
#     TEFF(id)->PEvent(EV_ISTARGET, ...), the call Creature.cpp:1324 makes. It
#     only sets a local; it changes no game state.
#   4 player pack with two copies of one book kind, LucubrationPickable() in the
#     body (src/Create.cpp)
#   5 monster pack, CalcValues() in the body
#   6 rest: Player::Rest intuition loop must attempt every unidentified item
#   7 the outer walk's next item is destroyed (Remove(true)) inside a function
#     that holds InvCursorGuard: the walk ends or goes on, never returns it
#   7b the next two items are dropped to the floor (a medium backpack already
#     there) inside a guarded function: the walk must not follow the floor chain
#   8 a walk with CalcValues() in the body visits the same items in the same
#     order as an unnested walk
#   9 same, with LucubrationPickable() (its inner walk breaks early) in the body
#   10 the god identify aid: the probe calls Character::GiveAid with
#     EParam=AID_IDENTIFY, EParam2=T_ITEM and the first god of the module; 3
#     loose pack items and 3 items in a pack container, all SetKnown(0), must
#     all read fully known afterwards. Expected green on master, where
#     MakeKnown starts no nested walk; it exists to go red on the pantheon epic,
#     where MakeKnown raises a god pulse.
#   11 a walk abandoned on a monster (two of its items visited), then the monster
#     is removed with Remove(true); a guarded call (CalcValues) and a fresh full
#     walk of the player's pack follow. errors.log between the case's two
#     mark=11 lines must hold no "invalid object handle" and no "ASSERT failed";
#     the fresh walk visits the whole pack. No second Character can be made, so
#     the Character cursor has no removed-owner case.
# The fix (src/Inv.cpp InvCursorGuard) saves both cursors on entry to
# CalcValues, SkillKitMod, HasSkillKit, LucubrationPickable, RealThrow and
# VMachine::Execute, and restores them on every exit.
# Not covered: ChooseLucubrationBook (src/Create.cpp) and the feat check
# (src/Create.cpp:5011) are not called; the first opens an interactive menu that
# no probe can bound, and its item loop is case 4's loop.
# fact: character -- fixture xsummon-priest-seed5-opt0822 (INCURSION_LOAD)
# fact: settings -- tools/fixtures/options-2026-08-22.dat (INCURSION_OPTIONS)
# fact: pack contents -- the probe builds them with Item::Create and XInsert; the true count is an unnested walk, cross-checked by a structural count
# fact: a spare open square for the monster -- the probe checks and reports INCONCLUSIVE, never FAIL
# fact: the monster -- the probe creates a goblin; its own gear only moves the true count, which the probe measures
# fact: the monster's gear for 11 -- fixed names (dagger, silk rope, sling stone) on a goblin; the walk is abandoned after 2 visits, whatever else it holds
# fact: fatigue >= 0 for the case 3 handler -- the probe checks and reports INCONCLUSIVE
# fact: the rest roll -- the probe throws EV_REST with REST_PLOT|REST_SAFE|REST_INSTANT: no encounter roll, no clock
# fact: intuition dice -- case 6 reads IF_INTUITED, which IntuitItem sets before any roll; inscription only when Intuition skill >= 4 guarantees precision >= 5
# fact: which items the removal cases remove -- the first consecutive loose test items in the measured unnested order; the probe reports INCONCLUSIVE when none
# fact: the floor chain for 7b -- the probe puts a medium backpack on the player's square first, then the two items; a prepend or append placement both leave the first dropped item a Next
# fact: visit order for 8 and 9 -- compared with an unnested walk measured in the same run
# fact: favor, prayer timeout and god standing -- not read: GiveAid is called directly, so the aid's gate in EV_PRAYER is skipped; the god is the module's first (GodIDList[0])
# fact: the staged item kinds for 10 -- fixed names (dagger, flask, torch, silk rope, sling stone, crossbow bolt), same on any seed
# fact: message text -- not matched (GiveAid silences its own identify loop; no prompt is reachable)
# FAIL, INCONCLUSIVE, an endless walk or missing results exit nonzero.
# Usage: tools/check_inv_cursor.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/bane-radius.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-inv-cursor"
INCURSION_INV_CURSOR_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" >/dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. Is InvCursorProbe still called from Game::Play()?"
    exit 1
fi

lines="$(grep 'INV_CURSOR_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "FAIL: $log has no INV_CURSOR_PROBE lines."
    exit 1
fi

echo "$lines"
echo "Specimen: $log"

if grep -qE 'INV_CURSOR_PROBE:.*INCONCLUSIVE' <<< "$lines"; then
    echo "FAIL: at least one probe case was inconclusive."
    exit 1
fi
n="$(grep -c 'INV_CURSOR_PROBE: case=' <<< "$lines")"
if [ "$n" -ne 12 ]; then
    echo "FAIL: measured $n case lines, want 12."
    exit 1
fi
between="$(sed -n '/INV_CURSOR_PROBE: mark=11-begin/,/INV_CURSOR_PROBE: mark=11-end/p' "$log")"
if ! grep -q 'mark=11-end' <<< "$between"; then
    echo "FAIL: case 11 markers missing from $log."
    exit 1
fi
if grep -qE 'invalid object handle|ASSERT failed' <<< "$between"; then
    echo "FAIL: case 11 logged an invalid handle or a failed assert:"
    grep -E 'invalid object handle|ASSERT failed' <<< "$between"
    exit 1
fi
if grep -q 'INV_CURSOR_PROBE: case=[0-9a-z]* .* BAD ' <<< "$lines"; then
    echo "FAIL: a case line is BAD (early stop, revisit, or endless walk)."
    exit 1
fi
if ! grep -q 'INV_CURSOR_PROBE: PASS' <<< "$lines"; then
    echo "FAIL: missing PASS result."
    exit 1
fi

echo "PASS: a nested inventory walk no longer moves the outer walk (inc-y2fkq)."
