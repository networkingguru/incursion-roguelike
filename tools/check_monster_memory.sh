#!/bin/bash
# gate: live
# Does the game record what the player has met, and show him only that?
# (bd inc-q98a)
#
#   tools/check_monster_memory.sh                     the whole check
#   tools/check_monster_memory.sh --prove-red seen    break one writer
#
# THE DEFECT. struct MonMem (inc/Res.h) records eleven things per player per
# monster kind, and until inc-q98a nothing in the game wrote any of them. The
# one place that read them, Monster::Describe (src/Help.cpp), was shortcut to
# a static record with every field at its maximum, so [R]ecall on the
# character sheet showed a creature's complete entry -- hit dice, attack
# bonus, defense class, saving throw numbers, every attribute -- to a
# character who had never seen one.
#
# WHAT IS MEASURED, and by what:
#
#   1  a kind never met reads nothing               the save has no row for it
#   2  seeing one sets Seen and nothing else        kobold: Seen=1 Fought=0
#   3  exchanging blows sets Fought                 ogre:   Fought=1 Kills=0
#   4  killing one counts the kill                  human:  Kills=10
#   5  the entry is sparse unmet and full at ten    the two recall boxes
#
# ONE, TWO AND THREE ARE READ FROM THE SAVE, not from the screen, because Seen
# and Fought reach no screen: Monster::Describe gates on Kills alone. `incursion
# -dump` prints them through the real MONMEM accessor (src/Dump.cpp), and
# tools/dump_save.sh is the sandboxed way to run it, so this check writes that
# report in beside the session's screen dumps and asserts on it with the same
# two functions it uses for a screen.
#
# FIVE IS THE PLAYER-FACING HALF and it is the one that must not be skipped.
# The three strings it turns on are chosen to survive the description box's
# word wrapping, which is why they are single words or short runs:
#
#   "hit points"   the sentence three kills opens
#   "dexterity"    the attribute sentence ten kills opens
#   "(+0)"         the saving throw numbers, which need more than fifty
#
# THE 255 CEILING IS NOT MEASURED HERE, AND THIS IS THE WHOLE REASON.
# MonMem::Kills is eight bits, so a 256th kill that wrapped would erase
# everything the player knew about that kind; MonMemNote (src/Res.cpp) stops
# at MONMEM_MAX_KILLS instead. Reaching the ceiling takes three hundred and
# twenty summon-and-kill blocks, every one of them on the same square, and by
# the end that square holds some fourteen hundred things. The harness's map
# audit then reports a Contents chain too long to walk and more than a
# thousand things not linked into their own square -- a real engine complaint
# that this script would be manufacturing rather than finding -- and the
# session itself became unreliable at that size: one run of it saved and one
# lost its closing menu. A check that manufactures an engine complaint, and
# does it flakily, does not belong in the nightly gate.
#
# So the ceiling was measured by hand, once, and the literal result is:
#
#   INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
#       tools/headless.sh tools/keys/monster-memory-saturate.keys 4
#   tools/dump_save.sh <that run>/save/Thokk.sav
#     human: Seen=1 Fought=1 Kills=255 ...
#
# Three hundred and nine kills landed and the row reads 255, not 53. What
# stays here is the guard below that the ceiling line is still in
# src/Res.cpp, so it cannot be dropped without this check saying so. That
# guard is not a measurement and is not offered to --prove-red.

. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# --------------------------------------------------------------------------
# Which mutation --prove-red performs. check_lib performs the FIRST mutation a
# check declares and no other, so the five writable ones are declared in an
# order this argument chooses. Every declaration is still asserted to be
# present, and present exactly once, on an ordinary run.
CHECK_FIRST=""
for _arg in ${CHECK_ARGS[@]+"${CHECK_ARGS[@]}"}; do
    case "$_arg" in
        seen|fought|kill|read|recall) CHECK_FIRST="$_arg" ;;
        *)
            echo "usage: $0 [seen|fought|kill|read|recall] [--prove-red]"
            exit 2 ;;
    esac
done
unset _arg

mutate_seen() {
    check_mutation src/Skills.cpp \
        'MonMemNote(this, cr->tmID, MONMEM_SEEN);' \
        'MonMemNote(this, cr->tmID, 0);'
}
mutate_fought() {
    check_mutation src/Fight.cpp \
        '  if (e.EActor && e.EVictim) {' \
        '  if (0) {'
}
mutate_kill() {
    check_mutation src/Fight.cpp \
        'MonMemNote(e.EPActor, tmID, MONMEM_KILL);' \
        'MonMemNote(e.EPActor, tmID, 0);'
}
# Not a measurement: the ordinary run asserts this line is still here and
# still unique, so the ceiling cannot be dropped in silence. It is declared
# last, so --prove-red never reaches it. See the header.
mutate_saturate() {
    check_mutation src/Res.cpp \
        '      if (mm->Kills < MONMEM_MAX_KILLS)' \
        '      if (1)'
}
# The read, put back the way the HACKFIX had it: a record with every field at
# its maximum, which is what 255 in every byte gives.
mutate_read() {
    check_mutation src/Help.cpp \
        '        mm = MONMEM(xID,p);' \
        '        { memset(&Unknown, 255, sizeof(Unknown)); mm = &Unknown; }'
}
# [R]ecall's filter: TextTerm::MonsterPrompt, called with the player so it can
# gate each menu on his own MonMem rows (src/Managers.cpp case 'R'). Passing
# NULL instead puts back the old unfiltered browse -- every kind regardless of
# what the player met -- so assertion B's "no Human entry" check is what goes
# red. The "no monsters at all" message above it in case 'R' is a separate
# guard this mutation does not touch, which is why assertion A still passes
# unmutated.
mutate_recall() {
    check_mutation src/Managers.cpp \
        '                rID rid = MonsterPrompt("Recall which monster?", p);' \
        '                rID rid = MonsterPrompt("Recall which monster?", NULL);'
}

_declared=""
for _m in $CHECK_FIRST seen fought kill read recall saturate; do
    case " $_declared " in *" $_m "*) continue ;; esac
    _declared="$_declared $_m"
    "mutate_$_m"
done
unset _m _declared

# --------------------------------------------------------------------------
# Put the save's resource-memory report where check_screens can read it.
#
# Through tools/dump_save.sh and never the binary: that wrapper points -dump
# at a throwaway directory of its own and fails if anything is written there.
# The number in the name keeps it after the session's own dumps, which matter
# to a person reading the directory in order.
read_memory() { # -> adds *-savedump to the session's screens
    local save out
    save="$(ls "$CHECK_RUN"/save/*.sav 2>/dev/null | head -1)"
    if [ -z "$save" ]; then
        echo "INCONCLUSIVE: the session wrote no save file, so its resource"
        echo "      memory cannot be read. The key script's Save and Continue"
        echo "      did not land. See $CHECK_RUN."
        exit 2
    fi
    out="$CHECK_RUN/logs/screens/9000-savedump.txt"
    if ! tools/dump_save.sh "$save" > "$out" 2>&1; then
        echo "INCONCLUSIVE: incursion -dump refused $save."
        sed 's/^/      /' "$out"
        exit 2
    fi
    echo "  memory:  $out"
}

# --------------------------------------------------------------------------
# 1 and 5: a character who has met nobody.
#
# ANSWER TO A (docs/VERIFICATION.md step 1, and this check's own header): this
# character's save carries no monster-memory row at all -- tools/dump_save.sh
# prints "(no monster memory)" -- so [R]ecall takes the "nothing met" branch
# in src/Managers.cpp case 'R' and never reaches TextTerm::MonsterPrompt. The
# message is itself a Box(), which is why this is the live screen to assert
# on rather than a screen the old "sparse human entry" checks read: that box
# cannot open here, because no entry at all is on offer.
echo "--- a kind the character has never met ---"
check_run tools/keys/monster-memory-unmet.keys 4
check_screens '*unmet-recall*'
check_expect "You recall no monsters." \
    "a character with no monster-memory row at all is told so, not shown a menu"

read_memory
check_screens '*savedump*'
check_expect "=== Monster Memory (Seen/Fought/Kills) ===" \
    "the save carries a resource-memory report at all"
check_reject "  human: Seen" \
    "the save holds no row for a kind he has never met"

# --------------------------------------------------------------------------
# 2 and 3: seeing is not fighting, and fighting is not killing.
echo
echo "--- one kind seen, another struck once ---"
check_run tools/keys/monster-memory-seen.keys 4
read_memory
check_screens '*savedump*'
check_expect "  kobold: Seen=1 Fought=0 Kills=0" \
    "a kobold he only looked at is seen and nothing more"
check_expect "  ogre: Seen=1 Fought=1 Kills=0" \
    "an ogre he struck once is fought and not killed"

# --------------------------------------------------------------------------
# B: met some, not humans. [R]ecall's type menu (TextTerm::MonsterTypePrompt)
# must offer only what this character has met -- kobolds and ogres, grouped
# under "Humanoids" and "Giants" -- and a kind menu must open the ogre's own
# box. "Humans" (the type entry, plural) and "Human (" (the kind-list and
# box header, singular-plus-paren) are the two literal shapes a human entry
# takes on these screens; bare "Human" is rejected nowhere, because it is
# also the first five letters of "Humanoids", which legitimately appears
# here since both met kinds are of that type.
check_screens '*met-recall-types*'
check_expect "Giants" \
    "the ogre's type is offered"
check_reject "Humans (" \
    "no Human type entry: the player has not met one"
check_reject "Human (" \
    "no Human kind entry in the side pane either"

check_screens '*met-recall-ogre*'
check_expect "The Ogre" \
    "picking the ogre's type and then the ogre opens its recall box"

# --------------------------------------------------------------------------
# 4 and 5: ten kills, and what they show him.
echo
echo "--- ten of one kind killed ---"
check_run tools/keys/monster-memory-kills.keys 4
read_memory
check_screens '*savedump*'
check_expect "  human: Seen=1 Fought=1 Kills=10" \
    "ten kills are counted, one per kill"

check_screens '*killed-recall*'
check_expect "hit points" \
    "three kills opened the hit dice, attack bonus and defense class"
check_expect "dexterity" \
    "ten kills opened the attribute sentence"
check_reject "(+0)" \
    "ten kills did NOT open the saving throw numbers"

check_done "the game records what the player met, and shows him only that"
