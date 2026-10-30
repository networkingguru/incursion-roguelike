#!/bin/bash
# gate: live
# Do the five hard-coded favour awards pay the god? (bd inc-rgzr, instance 1)
#
# THE DEFECT. Creature declared gainFavour with an int16 amount and Character
# redeclared it with an int32 one (inc/Creature.h). A different parameter type
# is a different function, so Character's hid the base instead of overriding
# it, and every call made through a Creature* reached the base body, which is
# empty. Five awards are made from inside Creature:: methods, so all five wrote
# nothing:
#
#   src/Skills.cpp   Creature::SkillCheck      10 * (total - 15) to every god
#                                              whose FAVOURED_SKILLS lists the
#                                              skill, on a success a natural 1
#                                              would have failed
#   src/Skills.cpp   Creature::DevourMonster   Khasrach 10 * CR, sapient corpse
#   src/Skills.cpp   Creature::DevourMonster   Zurvash 5 * CR, any corpse
#   src/Feature.cpp  Trap::TriggerTrap         Semirath CR * 50 when a trap the
#                                              character reset kills a hostile
#   src/Feature.cpp  Trap::TriggerTrap         Semirath CR * 50, once per trap
#
# Every fact this check reads, and the control that fixes it
# (docs/VERIFICATION.md, "A check must not depend on the seed"):
#
# fact: monk character (Xavias, Khasrach, Zurvash sessions) -- fixture lizardfolk-monk-seed1.sav
# fact: kobold rogue character (Semirath session) -- fixture kobold-rogue-seed1.sav
# fact: settings -- CHECK_OPTIONS tools/fixtures/options-2026-08-22.dat
# fact: patron god of each session -- wizard Become Divine Champion
# fact: the trap, its level and its square -- wizard Create Trap (deathblade scythe, one square east)
# fact: the trap is found, disarmed and reset -- Searching and Handle Device skill rolls, INCURSION_RUNTO_SKILL_ROLL=20
# fact: Knowledge (Theology) insight check passes DC 15 -- INCURSION_RUNTO_SKILL_ROLL=20
# fact: each skill award amount -- computed from the roll, total and DC the session printed
# fact: the tabaxi in the devour sessions -- wizard Monster Summoning
# fact: other monsters on the level (the devour sessions) -- wizard Genocide Everything
# fact: the tabaxi does not fight back -- wizard Freeze Monsters
# fact: how many blows kill the tabaxi -- the key script repeats blows until the corpse is listed, so the count does not matter (INCURSION_LOF_FORCE_ROLL=20 is NOT used here: it makes a one-blow kill that the script's step onto the corpse mishandles on seed 303)
# fact: the tabaxi dies and leaves a corpse -- a kill always makes one (Creature::Die, src/Fight.cpp, "c = new Corpse(this)" under "if (m)"); no percent chance
# fact: each manes in the trap session -- wizard Monster Summoning, placed beside the trap
# fact: the manes does not walk -- wizard Freeze Monsters; Force Bolt knockback pushes it onto the trap
# fact: the bolt reaches the manes -- INCURSION_LOF_FORCE_ROLL=20
# fact: the manes' Reflex saves fail -- INCURSION_FORCE_SAVE_ROLL=1 (applies to every creature; no one else saves in these sessions)
# fact: the knockback distance (1d4) -- no control needed: the trap is the first square the manes enters
# fact: the manes' challenge rating -- read back from the game's own payout (MANES_CR check)
#
# THE ORACLE is the character sheet's own favour line for the patron god,
# "(Favour N, Lev L, Pen P%)" (src/Sheet.cpp), photographed either side of each
# event. The patron's line is the first one under "Spiritual State:". The
# amount each award should add is computed from what the same session printed:
# the skill check's roll, total and DC, and the dead creature's challenge
# rating -- which the check also reads back off a payout that never had this
# defect, so a changed monster cannot make the arithmetic quietly wrong.
#
# FOUR SESSIONS, each from a frozen character (tools/fixtures/README.md says
# why a seeded chargen would drift):
#
#   favour-insight.keys       lizardfolk monk, Xavias     seed 12
#   favour-devour-khasrach    lizardfolk monk, Khasrach   seed 5
#   favour-devour-zurvash     lizardfolk monk, Zurvash    seed 5
#   favour-trap.keys          kobold rogue,    Semirath   seed 1
#
# The seed is an argument only; every roll a session turns on is forced.
#
# The trap session measures the favoured-skill award a second time, for a
# second god: Semirath lists Handle Device, and a reset takes two Handle Device
# checks. It also kills twice on one trap, so the kill award is measured once
# with the once-per-trap award and once without it. The kobold casts Force Bolt
# at a frozen manes; the knockback pushes it onto the trap (Creature::Walk
# fires traps), so no monster walk decides whether the trap springs.
#
# A SESSION THAT DID NOT REACH ITS EVENT IS INCONCLUSIVE, never a failure: a
# skill check that failed or paid nothing, a reset that failed, a trap that did
# not kill. The rolls behind those are forced above, so on a healthy tree none
# of them happens; INCONCLUSIVE now means a key script or a game rule moved.
#
# PROVED RED on 2026-10-30 (bead inc-b4l3g.1) by putting int16 back in the base
# declaration and rebuilding the posix target. Every award assertion failed and
# both controls held, so the sessions still reached every event and only the
# favour was gone:
#
#   FAIL  Xavias, Knowledge (Theology) 24 vs DC 15     30000 -> 30000: rose 0, want +90
#   ok    the kill paid Khasrach +2 through his script, as always
#   FAIL  Khasrach, devour, 10 x CR 2                  30002 -> 30002: rose 0, want +20
#   FAIL  Zurvash, devour, 5 x CR 2                    30000 -> 30000: rose 0, want +10
#   FAIL  Semirath, Handle Device disarm + reset       30000 -> 30000: rose 0, want +520
#   ok    the once-per-trap branch paid +125 XP on kill 1 only, as always
#   FAIL  Semirath, first kill: kill + once-per-trap   30000 -> 30000: rose 0, want +100
#   FAIL  Semirath, Handle Device second reset         30000 -> 30000: rose 0, want +260
#   FAIL  Semirath, second kill: kill award alone      30000 -> 30000: rose 0, want +50
#
# The mutation is not declared with check_mutation, because that guard stops
# with exit 2 wherever the fixed text is absent -- including the unfixed tree
# this check was first run on, where it has to FAIL.
#
# Usage: tools/check_favour_awards.sh    (0 pass, 1 fail, 2 could not measure)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
# Every skill check rolls a natural 20. A 20 still meets the award rule "a
# natural 1 would have failed" (1 + 4 < 15), so skill_award() pays, and it
# computes the amount from the screen.
export INCURSION_RUNTO_SKILL_ROLL=20
MONK=tools/fixtures/chars/lizardfolk-monk-seed1.sav
KOBOLD=tools/fixtures/chars/kobold-rogue-seed1.sav

# The two monsters' challenge ratings, as lib/ writes them. Each is checked
# against the game's own CR-dependent payout before it is trusted.
TABAXI_CR=2     # lib/mon2.irh, Monster "tabaxi"
MANES_CR=1      # lib/mon4.irh, Monster "manes"

inconclusive() { # <line>...
    echo "INCONCLUSIVE: $1"; shift
    local l; for l in "$@"; do echo "      $l"; done
    exit 2
}

# One session from a fixture. check_run stops the whole check on a session
# that died or measured nothing.
session() { # <fixture> <keys> <seed>
    export INCURSION_LOAD="$1"
    check_run "$2" "$3"
    unset INCURSION_LOAD
}

# The helpers below set a variable rather than print, so that a dump that is
# missing stops the check here instead of inside a $( ) subshell, where an
# exit would stop nothing.
screen() { # <label> -> SCREEN, the dump's path
    SCREEN="$(ls "$CHECK_RUN"/logs/screens/*-"$1".txt 2>/dev/null | head -1)"
    [ -n "$SCREEN" ] || inconclusive "no '$1' screen in $CHECK_RUN." \
        "The key script did not get that far."
}

# "<god> <favour>" for the patron, read off a sheet dump. The sheet is two
# 40-column flows, so the left column is read top to bottom and then the right;
# the patron's block is the first under "Spiritual State:" (src/Sheet.cpp).
patron_favour() { # <sheet dump>
    awk 'NR > 1 { l[++n] = substr($0, 1, 40); r[n] = substr($0, 41) }
         END { for (i = 1; i <= n; i++) print l[i]; for (i = 1; i <= n; i++) print r[i] }' "$1" |
    awk '/Spiritual State:/ { s = 1; next }
         s && god == "" && match($0, /You are devoted to [A-Za-z]+\./) {
             god = substr($0, RSTART + 19, RLENGTH - 20) }
         s && match($0, /\(Favour -?[0-9]+,/) {
             print god, substr($0, RSTART + 8, RLENGTH - 9); exit }'
}

# FAV, the patron's favour, after proving the sheet names the god we expect.
favour() { # <label> <god>
    local got
    screen "$1"
    got="$(patron_favour "$SCREEN")"
    [ "${got% *}" = "$2" ] || inconclusive \
        "the '$1' sheet does not show $2 as the patron (read: '${got:-nothing}')." \
        "Become Divine Champion did not take, or the sheet scrolled differently."
    FAV="${got#* }"
}

# CL, "<roll> <total> <dc> <success|failure>", from a skill-check line.
#
# An unthreatened check on Escape Artist, Climb, Handle Device, Search or
# Balance "takes 20" instead of rolling (src/Skills.cpp, commit 0d65181): the
# line reads "... Check: took 20 +7 = 27 vs DC 20 [success]" rather than
# "... Check: 1d20 (14) +7 = 21 vs DC 20 [success]". Match either form; a
# "took 20" line has no die roll to report, so its roll value is the 20 it
# took.
check_line() { # <label> <skill name as printed>
    screen "$1"
    local line
    line="$(grep -ho -- "$2 Check: .*= [0-9-]* vs DC [0-9]* \[[a-z]*\]" "$SCREEN" | head -1)"
    case "$line" in
    *"took 20"*)
        CL="$(sed -E 's/.*took 20[^=]*= ([0-9-]+) vs DC ([0-9]+) \[([a-z]+)\].*/20 \1 \2 \3/' <<<"$line")"
        ;;
    *)
        CL="$(sed -E 's/.*1d20 \(([0-9]+)[^=]*= ([0-9-]+) vs DC ([0-9]+) \[([a-z]+)\].*/\1 \2 \3 \4/' <<<"$line")"
        ;;
    esac
}

# What Creature::SkillCheck pays a god that lists the skill.
skill_award() { # <roll> <total> <dc> <result>
    local roll="$1" total="$2" dc="$3" res="$4"
    if [ "$res" = success ] && [ $((total - roll + 1)) -lt "$dc" ] && [ "$total" -gt 15 ]; then
        echo $((10 * (total - 15)))
    else
        echo 0
    fi
}

xp_on() { # <label> -> XP, the sidebar's experience total
    screen "$1"
    XP="$(grep -o '[0-9]*/[0-9]* XP' "$SCREEN" | head -1 | cut -d/ -f1)"
    [ -n "$XP" ] || inconclusive "no experience total on the sidebar of '$1'."
}

turn_on() { # <label> -> TURN, from the dump's header
    screen "$1"
    TURN="$(sed -n '1s/.* turn \([0-9]*\).*/\1/p' "$SCREEN")"
}

rises() { # <what> <before> <after> <want>
    local got=$(($3 - $2))
    if [ "$got" -eq "$4" ]; then
        CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
        printf '  ok    %-44s %s -> %s (+%s)\n' "$1" "$2" "$3" "$4"
    else
        CHECK_FAIL=1
        printf '  FAIL  %-44s %s -> %s: rose %s, want +%s\n' "$1" "$2" "$3" "$got" "$4"
    fi
}

# --- 1. A favoured skill: Knowledge (Theology), which Xavias lists ---------
#
# The check is forced to a natural 20 (INCURSION_RUNTO_SKILL_ROLL, exported
# above), so the roll no longer depends on the seed. A 20 still pays: the award
# needs "a natural 1 would have failed", and 1 + 4 < 15. The seed (12) is kept
# only because the sweep records it; any seed gives the same award.
echo "Xavias, a Knowledge (Theology) success"
session "$MONK" tools/keys/favour-insight.keys 12
check_line insight "Knowledge (Theology)"
set -- $CL
[ $# -eq 4 ] || inconclusive "no Knowledge (Theology) check line on the insight screen."
want="$(skill_award "$@")"
[ "$want" -gt 0 ] || inconclusive \
    "the insight roll pays nothing on this seed: roll $1, total $2 vs DC $3, $4."
favour favour-before Xavias; x0="$FAV"
favour favour-after Xavias;  x1="$FAV"
rises "Xavias, Knowledge (Theology) $2 vs DC $3" "$x0" "$x1" "$want"

# --- 2 and 3. Devouring a sapient corpse -----------------------------------
echo "Khasrach, a sapient corpse eaten"
session "$MONK" tools/keys/favour-devour-khasrach.keys 5
screen messages
grep -qF "You finish eating the tabaxi corpse" "$SCREEN" ||
    inconclusive "the message log never says the tabaxi corpse was finished."
favour favour-champion Khasrach; k0="$FAV"
favour favour-killed Khasrach;   k1="$FAV"
favour favour-ate Khasrach;      k2="$FAV"
# The control. Khasrach's script pays max(1, CR) for the kill through the
# dispatcher, which reaches Character::gainFavour and always did. It proves
# the sheet moves when favour is paid, and it reads the tabaxi's CR back.
[ $((k1 - k0)) -eq "$TABAXI_CR" ] || inconclusive \
    "the kill paid Khasrach $((k1 - k0)) through his script, not $TABAXI_CR." \
    "Either the tabaxi's CR has changed or that script has; fix TABAXI_CR."
echo "  ok    the kill paid Khasrach +$TABAXI_CR through his script, as always"
rises "Khasrach, devour, 10 x CR $TABAXI_CR" "$k1" "$k2" $((10 * TABAXI_CR))

echo "Zurvash, a corpse eaten"
session "$MONK" tools/keys/favour-devour-zurvash.keys 5
screen messages
grep -qF "You finish eating the tabaxi corpse" "$SCREEN" ||
    inconclusive "the message log never says the tabaxi corpse was finished."
favour favour-killed Zurvash; z1="$FAV"
favour favour-ate Zurvash;    z2="$FAV"
rises "Zurvash, devour, 5 x CR $TABAXI_CR" "$z1" "$z2" $((5 * TABAXI_CR))

# --- 4 and 5. A trap the character reset, killing twice --------------------
echo "Semirath, Handle Device and a reset trap"
# The manes fails every Reflex save, and the bolt that pushes it hits. Both are
# forced for this session only (header, "fact:" lines).
export INCURSION_FORCE_SAVE_ROLL=1 INCURSION_LOF_FORCE_ROLL=20
session "$KOBOLD" tools/keys/favour-trap.keys 1
unset INCURSION_FORCE_SAVE_ROLL INCURSION_LOF_FORCE_ROLL
hd=0
for label in disarm reset; do
    check_line "$label" "Handle Device"
    set -- $CL
    [ $# -eq 4 ] && [ "$4" = success ] || inconclusive \
        "the $label check did not succeed on this seed (${*:-no check line})."
    hd=$((hd + $(skill_award "$@")))
done
[ "$hd" -gt 0 ] || inconclusive "the two Handle Device checks pay nothing on this seed."
favour favour-champion Semirath; s0="$FAV"
favour favour-armed Semirath;    s1="$FAV"
rises "Semirath, Handle Device disarm + reset" "$s0" "$s1" "$hd"

# The trap killed both manes. Force Bolt pushes the manes onto the trap, and
# the game credits the death to the pusher ("Your force bolt kills a manes"),
# so that line does not show the trap sprang. The trap's own Reflex save does:
# the trap is level 8, so its save is DC 23, where the bolt's own save is DC 19.
# Each kill therefore prints one "vs DC 23 [failure]" line, and the favour
# assertions below pay only when the trap's code saw the creature dead.
screen messages
n="$(grep -c "Reflex Save: .* vs DC 23 \[failure\]" "$SCREEN")"
[ "$n" -eq 2 ] || inconclusive \
    "the message log shows $n failed trap saves (DC 23), not 2: the trap did not kill both manes."
n="$(grep -c "force bolt kills a manes" "$SCREEN")"
[ "$n" -eq 2 ] || inconclusive "the message log shows $n manes killed, not 2."
# kill 2's evidence is not kill 1's: it came later in game time.
turn_on kill1; t0="$TURN"
turn_on armed2; t1="$TURN"
turn_on kill2;  t2="$TURN"
[ "$t1" -ge "$t0" ] && [ "$t2" -gt "$t1" ] || inconclusive \
    "the second kill took no turns after its manes was placed (turns $t0, $t1, $t2)."
# The once-per-trap branch also pays 100 + 25 * CR experience, through
# GainXP, which works. It must be in the first kill's experience and not in
# the second's; the difference is that branch alone, and it reads the CR back.
xp_on armed;  a1="$XP"
xp_on kill1;  b1="$XP"
xp_on armed2; a2="$XP"
xp_on kill2;  b2="$XP"
d1=$((b1 - a1)); d2=$((b2 - a2))
[ $((d1 - d2)) -eq $((100 + 25 * MANES_CR)) ] || inconclusive \
    "the kills paid $d1 and $d2 experience; their difference should be" \
    "100 + 25 x CR $MANES_CR = $((100 + 25 * MANES_CR)). Fix MANES_CR, or read the screens."
echo "  ok    the once-per-trap branch paid +$((d1 - d2)) XP on kill 1 only, as always"
favour favour-kill1 Semirath; s2="$FAV"
rises "Semirath, first kill: kill + once-per-trap" "$s1" "$s2" $((2 * 50 * MANES_CR))

check_line reset2 "Handle Device"
set -- $CL
[ $# -eq 4 ] && [ "$4" = success ] || inconclusive \
    "the second reset did not succeed on this seed (${*:-no check line})."
want="$(skill_award "$@")"
[ "$want" -gt 0 ] || inconclusive "the second reset pays nothing on this seed: $*."
favour favour-armed2 Semirath; s3="$FAV"
rises "Semirath, Handle Device second reset" "$s2" "$s3" "$want"
favour favour-kill2 Semirath; s4="$FAV"
rises "Semirath, second kill: kill award alone" "$s3" "$s4" $((50 * MANES_CR))

check_done "the five favour awards reach Character::gainFavour"
