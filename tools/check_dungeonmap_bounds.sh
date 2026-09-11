#!/bin/bash
# gate: live
# Does a levitating character on the bottom level still stay on it? (bd inc-tos)
#
# THE DEFECT. Game::GetDungeonMap allocates min(MAX_DUNGEON_LEVELS, DUN_DEPTH+1)
# handles, so the last valid index is DUN_DEPTH -- but its generation loop ran
# i <= Depth and its return read DungeonLevels[n][Depth]. A caller asking for
# DUN_DEPTH+1 read one element past the end of that block, wrote it when the
# read yielded zero, and got it back. The value it got back is what let the
# caller proceed.
#
# THE CALLER, and it needs no wizard mode to reach: the levitation branch of
# Creature::Descend asks GetDungeonMap for m->Depth + 1 and descends only if it
# gets a map back. On the bottom level that request is DUN_DEPTH + 1. The
# Goblin Caves declares DUN_DEPTH 10 (lib/dungeon.irh), so a character who
# levitates over a chasm on depth 10 and presses '>' floated down to a level
# that the dungeon does not have.
#
# THE ROUTE. tools/keys/levitate-bottom.keys walks the nine wizard depth jumps
# that docs/evidence/inc-x9i/observed-routes/to-bottom-level.keys walked on
# 2026-08-18, then presses '>'. The walk is not decoration: map content is NOT a
# property of the seed alone, because generation consumes the RNG stream, so a
# session that jumps straight to depth 10 gets a different depth 10 from one
# that walked the nine above it. INCURSION_LEVITATE_CHASM grants LEVITATION and
# stands the character on a chasm square on arrival at the deepest level. It
# manufactures no terrain and it is the SETUP, not the oracle.
#
# THE ORACLE is the three screens, and it is gameplay rather than a probe:
#
#   on-bottom       "Flying" on the status pane and "100m" on the depth line --
#                   the character levitates, on the bottom level of the dungeon.
#   after-descend   "Climb down the chasm?" -- GetDungeonMap refused depth 11,
#                   so Descend skipped the levitation branch and fell through to
#                   the adjacent-chasm search, which found one and asked. And NO
#                   "You float downwards.", which is the levitation branch's own
#                   line and the thing the overread used to buy.
#   settled         "100m" after the climb is declined -- he is still on depth
#                   10. The descent did not happen.
#
# On seed 5 the adjacent-chasm search DOES find a square, so the prompt is what
# appears; "You can't go down here." is the other outcome of that same search
# and is not what this seed produces. Do not copy the message without re-running.
#
# WHICH ASSERTION CARRIES THE CHECK, because the obvious one does not. The
# depth reading is the same on both sides: with the overread restored the
# character is told "You float downwards." and then stays at 100m anyway,
# because Player::MoveDepth now refuses the null BELOW_DUNGEON resource that
# inc-x9i fixed. So "100m" proves the session reached the state and nothing
# more. The two assertions that separate the builds are the climb prompt, which
# only appears when the levitation branch was skipped, and the absence of the
# levitation branch's own line.
#
# PROVED RED on 2026-09-11 by putting the unbounded index back -- the refusal
# in Game::GetDungeonMap becomes `if (0)`, so depth 11 is read past the end of
# the allocation again and handed back. The inner run printed:
#
#   |   FAIL  0/1 screens carry: Climb down the chasm?
#   |         it should prove: GetDungeonMap refused depth 11, so Descend fell through to the adjacent-chasm search
#   |   FAIL  1/1 screens still carry: You float downwards.
#   |         it should prove: the levitation branch did not run
#   |         first: You float downwards.
#   | FAIL: a levitating character on the bottom level stays on it
#   PROVED RED: with src/Feature.cpp mutated, this check exits 1.
#
# Usage: tools/check_dungeonmap_bounds.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

check_mutation src/Feature.cpp \
'    if (Depth < 0 || (uint32)Depth >= allocated) {' \
'    if (0) {'

export INCURSION_LEVITATE_CHASM=1
check_run tools/keys/levitate-bottom.keys 5

check_screens '*-on-bottom'
check_expect "Flying" \
    "the character is levitating"
check_expect "100m" \
    "and he stands on depth 10, the bottom level of The Goblin Caves"

check_screens '*-after-descend'
check_expect "Climb down the chasm?" \
    "GetDungeonMap refused depth 11, so Descend fell through to the adjacent-chasm search"
check_reject "You float downwards." \
    "the levitation branch did not run"

check_screens '*-settled'
check_expect "100m" \
    "he is still on the bottom level after the attempt"

check_done "a levitating character on the bottom level stays on it"
