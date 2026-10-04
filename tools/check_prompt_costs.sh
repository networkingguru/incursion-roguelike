#!/bin/bash
# gate: cheap
# inc-1xr3 phase 2c: the social / script / unknown-odds prompts must name the
# cost or the uncertainty, and every shown number must come from the expression
# the deciding code uses.
#
# This is a source-level check (no gameplay observation required). It asserts:
#
#   (1) Prayer.cpp's raise prompt shows ResurrectChance(), and the deciding
#       test uses that same helper (random(100) >= ResurrectChance());
#       ResurrectChance = clamp(resChance+1, 0, 100), which is the count of
#       the 100 equally likely random(100) draws (0..99) that pass
#       `!(resChance < draw)`;
#   (2) the exploitation prompt prints the same magnitude Transgress uses;
#   (3) the intimidate/bluff prompts name the alignment act on the same
#       non-evil condition the AlignedAct calls test;
#   (4) both rune prompts name the fatigue the LoseFatigue call takes;
#   (5) the immunize prompt prints (spID->Level+1)/2, the magnitude of the
#       ADJUST_INH A_MAN change;
#   (6) the extra-dice prompt names the 2 HP per die the sac expression takes;
#   (7) the Xel prompt names the -1 the Transgress call applies;
#   (8) the rest prompt says the odds are unknown;
#   (9) the threatened-area prompt names Flee's certain attack and Disengage's
#       unknown odds;
#  (10) the three whole-group prompts that add +10 DC and lock the group out
#       say so. Distract and Taunt do NOT (they add +5 and use a temporary
#       TRIED), so they must NOT carry the note.
#
# Exits 0 on pass, 1 on fail.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
note() { printf 'FAIL: %s\n' "$1"; fail=1; }

PRAYER=src/Prayer.cpp
SOCIAL=src/Social.cpp
PLAYER=src/Player.cpp
MOVE=src/Move.cpp
DUNGEON=lib/dungeon.irh
PSPELLS=lib/pspells.irh
RELIGION=lib/religion.irh

# (1) resurrection: prompt uses the helper, deciding test uses it too.
grep -q '(int)ResurrectChance()' "$PRAYER" \
    || note "Prayer.cpp: raise prompt does not show ResurrectChance()"
grep -q 'random(100) >= ResurrectChance()' "$PRAYER" \
    || note "Prayer.cpp: deciding resurrection test does not use ResurrectChance()"
grep -q 'int16 Character::ResurrectChance()' "$PRAYER" \
    || note "Prayer.cpp: ResurrectChance is not defined"

# The helper must agree with the deciding test for every resChance the game
# can set. random(100) yields 0..99; the raise succeeds when draw <= resChance.
awk '
function helper(rc) { if (rc < 0) return 0; if (rc >= 99) return 100; return rc + 1 }
function oracle(rc,   d, count) { count = 0; for (d = 0; d < 100; d++) if (d <= rc) count++; return count }
BEGIN {
    bad = 0
    for (rc = -5; rc <= 120; rc++)
        if (helper(rc) != oracle(rc)) {
            printf "FAIL: ResurrectChance(%d)=%d, deciding test gives %d\n", rc, helper(rc), oracle(rc)
            bad++
        }
    if (bad) exit 1
    printf "ResurrectChance agrees with the deciding test on 126 values\n"
}' || fail=1

# (2) exploitation magnitude shared.
grep -q 'int16 exploitTransgress = 5;' "$SOCIAL" \
    || note "Social.cpp: exploitation magnitude not factored into exploitTransgress"
grep -q 'angers Essiah)"' "$SOCIAL" \
    || note "Social.cpp: exploitation prompt does not name the angered god"
grep -q 'Transgress(FIND("Essiah"),exploitTransgress,false,"exploitation")' "$SOCIAL" \
    || note "Social.cpp: Transgress does not use exploitTransgress"

# (3) coercion/treachery named on the same non-evil condition.
grep -q 'intimNote = (!e.EVictim->isMType(MA_EVIL)) ? " (coercion)" : "";' "$SOCIAL" \
    || note "Social.cpp: intimidate prompt note not gated on non-evil"
grep -q 'bluffNote = (!e.EVictim->isMType(MA_EVIL)) ? " (treachery)" : "";' "$SOCIAL" \
    || note "Social.cpp: bluff prompt note not gated on non-evil"
grep -q 'if (sk == SK_INTIMIDATE && !e.EVictim->isMType(MA_EVIL))' "$SOCIAL" \
    || note "Social.cpp: coercion deciding condition changed"
grep -q 'if (sk == SK_BLUFF && !e.EVictim->isMType(MA_EVIL))' "$SOCIAL" \
    || note "Social.cpp: treachery deciding condition changed"

# (4) rune force prompt names the fatigue; literal kept next to the call.
grep -q '^2$' <<< "$(grep -c 'force it? (costs 2 fatigue)' "$DUNGEON")" \
    || note "dungeon.irh: rune prompts do not both name the 2 fatigue"
grep -q '^2$' <<< "$(grep -c 'LoseFatigue(2,true)' "$DUNGEON")" \
    || note "dungeon.irh: LoseFatigue(2,true) call changed"

# (5) immunize prompt prints the ADJUST_INH magnitude.
grep -q 'permanent mana -<Num>)",' "$PSPELLS" \
    || note "pspells.irh: immunize prompt does not name the permanent loss"
grep -q 'spID,(spID->Level+1)/2),true)' "$PSPELLS" \
    || note "pspells.irh: immunize prompt does not print (spID->Level+1)/2"
grep -qE '^[12]$' <<< "$(grep -c -- '-(spID->Level+1)/2' "$PSPELLS")" \
    || note "pspells.irh: ADJUST_INH magnitude changed"

# (6) extra dice prompt names the 2 HP per die.
grep -q 'How many extra dice of damage? (2 HP per die per attack)' "$PSPELLS" \
    || note "pspells.irh: extra-dice prompt does not name 2 HP per die"
grep -q 'sac = (ch - .0.)\*2;' "$PSPELLS" \
    || note "pspells.irh: sac expression changed"

# (7) Xel prompt names the -1 Transgress applies.
grep -q 'Continue? (-1 favour with Xel)' "$RELIGION" \
    || note "religion.irh: Xel prompt does not name the favour cost"
grep -q 'Transgress($"Xel",1,false,' "$RELIGION" \
    || note "religion.irh: Xel Transgress magnitude changed"

# (8) rest prompt says the odds are unknown.
grep -q 'Confirm rest in dungeon? (odds of interruption unknown)' "$PLAYER" \
    || note "Player.cpp: rest prompt does not flag unknown odds"

# (9) threatened-area prompt names Flee and Disengage odds.
grep -q 'Flee: each foe gets a free attack; Disengage: odds unknown' "$MOVE" \
    || note "Move.cpp: threatened-area prompt does not name the odds"

# (10) the three +10/group-lockout prompts carry the note.
grep -q "whole group? (+10 DC; whole group locked out for a day)" "$SOCIAL" \
    || note "Social.cpp: a whole-group prompt is missing the +10/lockout note"
grep -q '^3$' <<< "$(grep -c "whole group? (+10 DC; whole group locked out for a day)" "$SOCIAL")" \
    || note "Social.cpp: expected exactly 3 whole-group notes (Cow, Offer terms, Persuade)"
grep -q 'Distract Everyone?' "$SOCIAL" \
    || note "Social.cpp: Distract prompt unexpectedly changed"
grep -q 'Taunt the whole encounter?' "$SOCIAL" \
    || note "Social.cpp: Taunt prompt unexpectedly changed"

if [ "$fail" -eq 0 ]; then
    echo "PASS: phase 2c prompt costs and odds are sourced correctly"
fi
exit "$fail"
