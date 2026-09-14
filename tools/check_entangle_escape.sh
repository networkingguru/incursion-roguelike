#!/bin/bash
# Can a character in heavy armour tear out of glue? Bead inc-jwm0.
#
# THE DEFECT. src/Move.cpp's EV_MOVE branch was the ONLY exit from STUCK, for
# every entangling hazard in the game -- slime, grease, webbing, tanglefoot
# strands, entangling weapons and monster AD_STUK attacks. It rolled Escape
# Artist, which is keyed on Dexterity, carries the armour check penalty, and is
# a class skill for no armour-wearing class, so Character::MaxRanks
# (src/Create.cpp:3957) caps it at a hard zero forever. A paladin in full plate
# and a kite shield sits at -11 against a DC of 14: his ceiling of 9 is five
# below the floor and NO roll closes it. Measured before the fix: he stayed
# stuck through 673 turns of game time.
#
# The engine already knew better twenty lines away. Breaking a GRAPPLE
# (src/Fight.cpp:4806-4893) strips the Dex modifier back out of the skill --
# "ww: we'll be adding in your dex/str bonus later" -- and adds Strength. And
# the success branch in Move.cpp has always called Exercise(A_STR, ...) with a
# reason code named ESTR_UNSTUCK, so whoever wrote it thought of tearing free
# as a feat of Strength and then rolled it against Dexterity. The SRD frees a
# creature from a tanglefoot bag on a Strength check, and an ability check
# takes no armour penalty.
#
# THE ORACLE is the game's own printed check lines. Two of them now appear:
# the unchanged "Escape Artist Check:" from SkillCheck, and a new "Strength
# Check:" written to WIN_NUMBERS2, the row directly below it. The Strength line
# CANNOT appear on a tree without the fix, which is what makes this check red
# before and green after.
#
# WHY THE ESCAPE ALONE PROVES NOTHING, and why this script does not accept it:
# src/Skills.cpp:1600 already frees the character on a natural 20 for Escape
# Artist, provided no hostile is within sixteen squares. This fixture runs in
# an empty entry chamber, so that clause is live and would eventually free him
# on an unfixed tree too. The script therefore requires a Strength check that
# SUCCEEDED, not merely an escape.
#
# The fixture uses the WORST case rather than a flattering one: seed 4 rolls
# the paladin STR 10, so his Strength check is a bare d20 with no bonus. A real
# tank rolls better. Twenty attempts at 20% each (DC 17, R14's tanglefoot row).
#
# PHASE 4 (R14) gave every hazard its own difficulty and governing attribute,
# keyed on the STUCK stati's Val instead of one DC every hazard shared. This
# script also proves that table is being read: tanglefoot strands is the
# Strength hazard at DC 17, not the flat 15 + GetStatiMag(STUCK) that used to
# read DC 14 for every hazard because nothing ever set a Mag.
#
# Usage: tools/check_entangle_escape.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=4
KEYS=tools/keys/entangle-strength-escape.keys

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
       INCURSION_MAP_AUDIT=0 tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

if echo "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: the key script could not find something on screen."
    echo "              Menu letters move when a list changes. Run: $run"
    exit 2
fi
[ -n "$run" ] && [ -d "$run/logs/screens" ] || {
    echo "INCONCLUSIVE: no run directory. Output was:"; echo "$out"; exit 2; }

S="$run/logs/screens"
geared="$S/0001-geared.txt"

# --- preconditions. A run that measured the wrong character measures nothing.

[ -f "$geared" ] || { echo "INCONCLUSIVE: no character sheet dumped at $geared"; exit 2; }

grep -q "Escape Artist    -11 (0 ranks, +1 DEX, -12 armour)" "$geared" || {
    echo "INCONCLUSIVE: the subject is not in the case this check defends."
    echo "              Wanted Escape Artist -11 from full plate and a kite"
    echo "              shield; the sheet says:"
    grep -E "Escape Artist|Encumbrance " "$geared" | sed 's/^/              /'
    echo "              Screen: $geared"
    exit 2
}

grep -qh "You've become stuck" "$S"/* || {
    echo "INCONCLUSIVE: the character never became stuck, so nothing was"
    echo "              measured. He may have passed the DC 15 Reflex save on"
    echo "              every entry. Screens: $S"
    exit 2
}

rc=0

# --- the assertion that discriminates: the Strength exit exists and works.

if ! grep -qh "Strength Check:" "$S"/*; then
    echo "FAIL: no Strength check was ever rolled. The only exit from STUCK is"
    echo "      still the Escape Artist check at src/Move.cpp, which a"
    echo "      character in heavy armour cannot pass at any roll."
    rc=1
elif ! grep -qh "Strength Check:.*\[success\]" "$S"/*; then
    echo "FAIL: the Strength check is rolled but never succeeded in twenty"
    echo "      attempts against DC 17 on a bare d20. At STR 10 that is about"
    echo "      one run in ninety by chance, so read it as a real change in"
    echo "      the DC or the modifier rather than bad luck."
    grep -h "Strength Check:" "$S"/* | sed 's/ *|.*//' | sort -u | sed 's/^/      /'
    rc=1
fi

if ! grep -qh "You tear free" "$S"/*; then
    echo "FAIL: the character never got out of the tanglefoot strands."
    rc=1
fi

# --- R14: tanglefoot strands is the Strength hazard, at DC 17, not the flat
# DC 14 every hazard used to share (15 + GetStatiMag(STUCK), Mag defaulting
# to -1). A Strength check at DC 14 anywhere in this run means the per-hazard
# table in src/Move.cpp is not being read for this stati's Val.

if ! grep -qh "Strength Check:.*vs DC 17 " "$S"/*; then
    echo "FAIL: no Strength check was ever rolled against DC 17, tanglefoot"
    echo "      strands' own Strength escape DC (R14, STUCK_BONDED). The"
    echo "      per-hazard table is not being consulted for this hazard."
    grep -h "Strength Check:" "$S"/* | sed 's/ *|.*//' | sort -u | sed 's/^/      /'
    rc=1
fi

if grep -qh "Strength Check:.*vs DC 14 " "$S"/*; then
    echo "FAIL: a Strength check rolled against DC 14 -- the old flat"
    echo "      15 + GetStatiMag(STUCK) formula. R14's per-hazard table is"
    echo "      not in effect for tanglefoot strands."
    grep -h "Strength Check:.*vs DC 14 " "$S"/* | sed 's/ *|.*//' | sort -u | sed 's/^/      /'
    rc=1
fi

# --- the guard: the Escape Artist path itself must NOT have been weakened.
# Every roll below 20 must still fail at -11 against DC 22 (R14's tanglefoot
# Escape Artist DC). A "fix" that made this skill check passable would
# satisfy the assertions above for the wrong reason.

bad="$(grep -h "Escape Artist Check:" "$S"/* | sed 's/ *|.*//' \
       | grep "\[success\]" | grep -v "1d20 (20)" || true)"
if [ -n "$bad" ]; then
    echo "FAIL: an Escape Artist check passed on a roll below 20, so the skill"
    echo "      check itself has changed. This check defends the Strength exit,"
    echo "      not a cheaper Escape Artist:"
    echo "$bad" | sed 's/^/      /'
    rc=1
fi

if [ "$rc" = 0 ]; then
    echo "PASS: the Strength exit works where Escape Artist cannot."
    grep -h "Escape Artist Check:" "$S"/* | sed 's/ *|.*//' | sort -u | tail -1 | sed 's/^/      /'
    grep -h "Strength Check:.*\[success\]" "$S"/* | sed 's/ *|.*//' | sort -u | head -1 | sed 's/^/      /'
fi
echo "      run: $run"
exit $rc
