#!/bin/bash
# gate: live
# Assert the sneak-attack-from-invisibility rules for bead inc-nkf2.
#
#   tools/check_sneak_invis.sh     exit 0 all pass, 1 a failed assertion,
#                                  2 a case measured nothing
#
# Bead inc-nkf2. Two defects fixed in src/Fight.cpp:
#
#   FIX 1  Creature::Hit's sneak gate did not read e.actUnseen, so an invisible
#          first blow the victim HEARD got no sneak dice.
#   FIX 2  Creature::PreStrike set e.actUnseen and e.isSurprise together; a
#          RANGED attack from an unperceived attacker must count as unseen
#          even when the victim has Blind-Fight (SRD: melee only).

# SEED-INDEPENDENT (bead inc-b4l3g.30). One run per case, loading the frozen
# rogue tools/fixtures/chars/orc-rogue-sneak-seed1.sav (knife in the pack, Move
# Silently ranks; made by tools/keys/sneak-invis-rogue-save.keys). Every run
# forces INCURSION_LOF_FORCE_ROLL=20 (every attack lands) and
# INCURSION_FORCE_DAMAGE_ROLL=1; the Move Silently vs Listen contest is forced
# by INCURSION_SNEAK_FORCE_LISTEN=heard|unheard. Counts are exact, so
# MIN_COUNT is 1.
#
# THE PROBE. src/Fight.cpp's SneakProbeNote writes logs/sneak.log: "pre" once
# per PreStrike, "hears-you" when the contest is lost, "attack" once per
# Creature::Hit after the sneak gate. This script sets INCURSION_SNEAK_PROBE=1.
# Each run gets a FRESH directory, because the probe appends.

# THE CASES, each read out of logs/sneak.log:
#   A   invisible MELEE first blow, victim HEARD (listen=heard), landed, not
#       flat-footed: sneak=1. FIX 1.
#   A2  same, victim did NOT hear (listen=unheard): sneak=1. Regression guard.
#   B   visible control blow at a non-flat-footed victim: sneak=0. Read from
#       both melee runs. No contest occurs: the rogue is visible.
#   C   invisible RANGED first blow at a Blind-Fight victim: actUnseen=1,
#       surprise=0. FIX 2. A visible melee setup blow clears the hag's
#       flat-footed state first; the landed throw then needs
#       sneak=1, and none landed exits 2. No contest occurs (Blind-Fight
#       keeps isSurprise off); switch unset. Only the first invisible blow
#       is read (the throw). True Seeing stops the 50% unseen-victim miss.
#   D   invisible MELEE first blow at a Blind-Fight victim: actUnseen=0 and
#       surprise=0. Guards that Blind-Fight still protects in melee. Same: no
#       contest, switch unset.
# A case with no probe line exits 2. A count below MIN_COUNT exits 1.

# fact: character, kit, skills (Move Silently ranks, orcish knife) -- fixture orc-rogue-sneak-seed1
# fact: settings (Auto Hide off, monster max hit points) -- INCURSION_OPTIONS options-sneak-invis-maxhp.dat, saved in the fixture
# fact: victim (brown bear, green hag) and its position -- wizard Monster Summoning
# fact: victim hit points (a kill ends the case) -- OPT_MON_MAX_HP DOUBLE, plus INCURSION_FORCE_DAMAGE_ROLL=1
# fact: victim flat-footed state (case C sneak half) -- visible setup blow in the key script
# fact: rogue sees the invisible hag (else a 50% wild miss, src/Fight.cpp vicUnseen) -- True Seeing cast in the ranged key script
# fact: lit arena for the visible control -- Call Light cast in the key script
# fact: hit or miss -- INCURSION_LOF_FORCE_ROLL=20
# fact: victim hears the rogue -- INCURSION_SNEAK_FORCE_LISTEN=heard|unheard
# fact: Blind-Fight, See Invisible, infravision of the victim -- species data (lib/mon1.irh, lib/mon2.irh)
# fact: Cheat Death, mana for Improved Invisibility -- wizard mode switches in the key script
# fact: killing blow -- excluded by the awk (vx=-1 vy=-1) and counted
# fact: the session seed -- not read; every run passes seed 1

# Commands:
#   BACKEND=posix ./build_macos.sh
#   tools/check_sneak_invis.sh
#   tools/seed_sweep.sh tools/check_sneak_invis.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }

# Exact counts: every forced case yields one blow, so one is enough.
MIN_COUNT=1
FIXTURE=tools/fixtures/chars/orc-rogue-sneak-seed1.sav
OPTIONS=tools/fixtures/options-sneak-invis-maxhp.dat
[ -f "$OPTIONS" ] || { echo "INCONCLUSIVE: settings file $OPTIONS is not there"; exit 2; }
[ -f "$FIXTURE" ] || { echo "INCONCLUSIVE: fixture $FIXTURE is not there"; exit 2; }

MELEE_KEY=tools/keys/sneak-invis-melee.keys
RANGED_KEY=tools/keys/sneak-invis-ranged.keys
BLINDFIGHT_KEY=tools/keys/sneak-invis-blindfight.keys
MELEE_VICTIM="${INCURSION_MELEE_VICTIM:-brown bear}"
RANGED_VICTIM="${INCURSION_RANGED_VICTIM:-green hag}"
BLINDFIGHT_VICTIM="${INCURSION_BLINDFIGHT_VICTIM:-green hag}"

# Counters, aggregated over every trial.
A_HIT=0; A_NFF=0; A_NFF_SN=0; A_SN=0
A2_HIT=0; A2_NFF=0; A2_NFF_SN=0; A2_SN=0
B_HIT=0; B_OK=0; B_BAD=0; SETUP_HIT=0
C_PRE=0; C_PRE_AU=0; C_PRE_SU=0; C_HIT=0; C_NFF=0; C_NFF_SN=0
D_PRE=0; D_PRE_AU=0; D_PRE_SU=0; D_HIT=0
MELEE_LINES=0; RANGED_LINES=0; BF_LINES=0; FAILED=0
# inc-kbws: blows whose victim was already removed from the map (the blow
# killed it). The engine adds sneak dice only while the victim is alive -- the
# src/Fight.cpp:7211 gate reads !e.EVictim->isDead() -- so these blows correctly
# get sneak=0 and must not be counted as a heard/landed blow that missed sneak
# dice. The probe samples the victim's position after the kill, so such a blow
# shows vx=-1 vy=-1 with a meaningless dist. Excluded per case, then reported.
A_KILLED=0; C_KILLED=0; D_KILLED=0

# Fresh directory per trial. The probe appends, so a reused directory would
# double the counts on a second invocation; the token makes two concurrent
# invocations distinct and the rm makes a repeated one fresh. (inc-nkf2)
TOKEN="${INCURSION_CHECK_TOKEN:-$$-$(date +%s)}"
RUN_SEQ=0
run_one() { # <keyscript> <listen: heard|unheard|-> <label> -> prints the run directory
    local keys="$1" listen="$2" label="$3" out run seed=1
    RUN_SEQ=$((RUN_SEQ+1))
    local RUN_DIR="$ROOT/logs/runs/check-sneak-$TOKEN-$(printf '%02d' "$RUN_SEQ")-$label"
    rm -rf "$RUN_DIR"
    export INCURSION_RUN_DIR="$RUN_DIR"
    local lv=(); [ "$listen" != "-" ] && lv=(INCURSION_SNEAK_FORCE_LISTEN="$listen")
    out="$(env INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$FIXTURE" \
            INCURSION_SNEAK_PROBE=1 INCURSION_LOF_FORCE_ROLL=20 \
            INCURSION_FORCE_DAMAGE_ROLL=1 ${lv[@]+"${lv[@]}"} \
            tools/headless.sh "$keys" "$seed" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if grep -qE 'NO GAMEPLAY|the key script looked for something|WATCHDOG|FATAL' <<< "$out"; then
        FAILED=$((FAILED+1))
    fi
    echo "$run"
}

echo "sneak-attack from invisibility (inc-nkf2), one forced run per case"
echo "options: $OPTIONS"
echo

# ---------------------------------------------------------------- cases A/B
for listen in heard unheard; do
    RUN="$(run_one "$MELEE_KEY" "$listen" melee-$listen)"
    LOG="$RUN/logs/sneak.log"
    [ -f "$LOG" ] || continue
    read -r ah ahnff ahnffsn ahsn au aunff aunffsn ausn setup bh bok bbad akilled lines < <(awk -v v="$MELEE_VICTIM" '
        $0 ~ ("victim=<" v ">") {
            if (/ pre /) { lines++; if (/invisVal=1/) { invisSeen=1; heard=0 } }
            if (/hears-you/) { if (invisSeen) heard=1 }
            if (/ attack /) {
                lines++
                # inc-kbws: a blow that killed the victim was probed after the
                # kill, with the victim off the map (vx=-1 vy=-1); the engine
                # adds no sneak dice once isDead() (src/Fight.cpp:7211). Exclude
                # it from the sneak expectation and tally it.
                if (/vx=-1 vy=-1/) { akilled++; if (invisSeen) { invisSeen=0; heard=0 }; next }
                ff=(/flatfoot=1/); sn=(/sneak=1/)
                if (invisSeen) {
                    if (heard) { ah++; if(!ff){ ahnff++; if(sn) ahnffsn++ } ; if(sn) ahsn++ }
                    else       { au++; if(!ff){ aunff++; if(sn) aunffsn++ } ; if(sn) ausn++ }
                    invisSeen=0; heard=0
                } else {
                    if (ff) setup++; else { bh++; if(sn) bbad++; else bok++ }
                }
            }
        }
        END { print ah+0, ahnff+0, ahnffsn+0, ahsn+0, au+0, aunff+0, aunffsn+0, ausn+0, setup+0, bh+0, bok+0, bbad+0, akilled+0, lines+0 }
    ' "$LOG")
    A_HIT=$((A_HIT+ah)); A_NFF=$((A_NFF+ahnff)); A_NFF_SN=$((A_NFF_SN+ahnffsn)); A_SN=$((A_SN+ahsn))
    A2_HIT=$((A2_HIT+au)); A2_NFF=$((A2_NFF+aunff)); A2_NFF_SN=$((A2_NFF_SN+aunffsn)); A2_SN=$((A2_SN+ausn))
    B_HIT=$((B_HIT+bh)); B_OK=$((B_OK+bok)); B_BAD=$((B_BAD+bbad)); SETUP_HIT=$((SETUP_HIT+setup))
    A_KILLED=$((A_KILLED+akilled))
    MELEE_LINES=$((MELEE_LINES+lines))
done

echo "A. invisible first blow (melee), victim HEARD the rogue:"
echo "     blows at a non-flat-footed victim that reached the gate:  $A_NFF"
echo "     ...of those, sneak=1 (must be all):                       $A_NFF_SN"
echo "     (all heard blows, any flatfoot state:                     $A_HIT; sneak=1: $A_SN)"
echo "     excluded killing blows (victim off map, vx=-1 vy=-1):     $A_KILLED"
echo
echo "A2. invisible first blow (melee), victim did NOT hear:"
echo "     blows at a non-flat-footed victim that reached the gate:  $A2_NFF"
echo "     ...of those, sneak=1 (must be all):                       $A2_NFF_SN"
echo
echo "B. control, visible blow at a non-flat-footed victim:"
echo "     blows that reached the gate (flatfoot=0):                 $B_HIT"
echo "     of those, sneak=0 (expected):                             $B_OK"
echo "     of those, sneak=1 (must be 0):                            $B_BAD"
echo "     (setup blows, flatfoot=1, not counted as control):        $SETUP_HIT"
echo

# ---------------------------------------------------------------- case C
for once in 1; do
    RUN="$(run_one "$RANGED_KEY" - ranged)"
    LOG="$RUN/logs/sneak.log"
    [ -f "$LOG" ] || continue
    read -r cp cpau cpsu ch cnff cnffsn ckilled lines < <(awk -v v="$RANGED_VICTIM" '
        $0 ~ ("victim=<" v ">") {
            if (/ pre /) { lines++; if (/invisVal=1/ && !first) { first=1; invisSeen=1; cp++; if (/actUnseen=1/) cpau++; if (/surprise=1/) cpsu++ } }
            if (/ attack /) {
                lines++
                # inc-kbws: exclude a killing blow (victim off map): the engine
                # adds no sneak dice once isDead() (src/Fight.cpp:7211).
                if (/vx=-1 vy=-1/) { ckilled++; if (invisSeen) invisSeen=0; next }
                if (invisSeen) { ch++; if (/flatfoot=0/) { cnff++; if (/sneak=1/) cnffsn++ } ; invisSeen=0 }
            }
        }
        END { print cp+0, cpau+0, cpsu+0, ch+0, cnff+0, cnffsn+0, ckilled+0, lines+0 }
    ' "$LOG")
    C_PRE=$((C_PRE+cp)); C_PRE_AU=$((C_PRE_AU+cpau)); C_PRE_SU=$((C_PRE_SU+cpsu))
    C_HIT=$((C_HIT+ch)); C_NFF=$((C_NFF+cnff)); C_NFF_SN=$((C_NFF_SN+cnffsn))
    C_KILLED=$((C_KILLED+ckilled))
    RANGED_LINES=$((RANGED_LINES+lines))
done

echo "C. invisible RANGED first blow at a Blind-Fight victim:"
echo "     invisVal=1 pre lines (first one only):                 $C_PRE"
echo "     ...of those, actUnseen=1 (must be all):                   $C_PRE_AU"
echo "     ...of those, surprise=1 (must be 0):                      $C_PRE_SU"
echo "     landed blows at a non-flat-footed victim:                 $C_NFF"
echo "     ...of those, sneak=1 (must be all):                       $C_NFF_SN"
echo "     excluded killing blows (victim off map, vx=-1 vy=-1):     $C_KILLED"
echo

# ---------------------------------------------------------------- case D
for once in 1; do
    RUN="$(run_one "$BLINDFIGHT_KEY" - blindfight)"
    LOG="$RUN/logs/sneak.log"
    [ -f "$LOG" ] || continue
    read -r dp dpau dpsu dh dkilled lines < <(awk -v v="$BLINDFIGHT_VICTIM" '
        $0 ~ ("victim=<" v ">") {
            if (/ pre /) { lines++; if (/invisVal=1/) { invisSeen=1; dp++; if (/actUnseen=1/) dpau++; if (/surprise=1/) dpsu++ } }
            if (/ attack /) {
                lines++
                # inc-kbws: exclude a killing blow (victim off map): the engine
                # adds no sneak dice once isDead() (src/Fight.cpp:7211).
                if (/vx=-1 vy=-1/) { dkilled++; if (invisSeen) invisSeen=0; next }
                if (invisSeen) { dh++; invisSeen=0 }
            }
        }
        END { print dp+0, dpau+0, dpsu+0, dh+0, dkilled+0, lines+0 }
    ' "$LOG")
    D_PRE=$((D_PRE+dp)); D_PRE_AU=$((D_PRE_AU+dpau)); D_PRE_SU=$((D_PRE_SU+dpsu)); D_HIT=$((D_HIT+dh))
    D_KILLED=$((D_KILLED+dkilled))
    BF_LINES=$((BF_LINES+lines))
done

echo "D. invisible MELEE first blow at a Blind-Fight victim:"
echo "     invisVal=1 pre lines:                                     $D_PRE"
echo "     ...of those, actUnseen=1 (must be 0):                     $D_PRE_AU"
echo "     ...of those, surprise=1 (must be 0):                      $D_PRE_SU"
echo "     first blows that reached the gate:                        $D_HIT"
echo "     excluded killing blows (victim off map, vx=-1 vy=-1):     $D_KILLED"
echo
echo "probe lines seen: melee=$MELEE_LINES ranged=$RANGED_LINES blindfight=$BF_LINES; failed runs=$FAILED"
echo

# ---------------------------------------------------------------- assertions
RC=0
fail() { echo "FAIL: $*"; RC=1; }

if [ "$MELEE_LINES" -eq 0 ]; then echo "FAIL: case A/B saw no probe line"; RC=2; fi
if [ "$RANGED_LINES" -eq 0 ]; then echo "FAIL: case C saw no probe line"; RC=2; fi
if [ "$BF_LINES" -eq 0 ]; then echo "FAIL: case D saw no probe line"; RC=2; fi
if [ "$RC" -eq 2 ]; then
    echo "FAIL: nothing was measured; a case produced no probe line at all"
    exit 2
fi

# A: every heard blow at a non-flat-footed victim must sneak.
if [ "$A_NFF" -lt "$MIN_COUNT" ]; then
    fail "case A measured only $A_NFF heard non-flat-footed blows (need >= $MIN_COUNT)"
elif [ "$A_NFF_SN" -ne "$A_NFF" ]; then
    fail "case A: $A_NFF heard non-flat-footed blows, only $A_NFF_SN got sneak dice"
fi
# A2: every unheard blow at a non-flat-footed victim must sneak.
if [ "$A2_NFF" -lt "$MIN_COUNT" ]; then
    fail "case A2 measured only $A2_NFF unheard non-flat-footed blows (need >= $MIN_COUNT)"
elif [ "$A2_NFF_SN" -ne "$A2_NFF" ]; then
    fail "case A2: $A2_NFF unheard non-flat-footed blows, only $A2_NFF_SN got sneak dice"
fi
# B: the visible control must never sneak.
if [ "$B_HIT" -lt "$MIN_COUNT" ]; then
    fail "case B measured only $B_HIT control blows (need >= $MIN_COUNT)"
fi
if [ "$B_BAD" -ne 0 ]; then
    fail "case B: the visible control awarded sneak dice $B_BAD time(s)"
fi
# C: actUnseen must hold and surprise must be off on every invisible ranged pre.
if [ "$C_PRE" -lt "$MIN_COUNT" ]; then
    fail "case C measured only $C_PRE invisible ranged pre lines (need >= $MIN_COUNT)"
fi
if [ "$C_PRE_AU" -ne "$C_PRE" ]; then
    fail "case C: $C_PRE invisible ranged pre lines, only $C_PRE_AU read actUnseen=1"
fi
if [ "$C_PRE_SU" -ne 0 ]; then
    fail "case C: $C_PRE_SU invisible ranged pre line(s) read surprise=1 (must be 0)"
fi
if [ "$C_NFF" -lt "$MIN_COUNT" ]; then
    echo "FAIL: case C measured only $C_NFF landed non-flat-footed invisible ranged blows (need >= $MIN_COUNT); nothing measured"
    exit 2
fi
if [ "$C_NFF_SN" -ne "$C_NFF" ]; then
    fail "case C: $C_NFF landed non-flat-footed blows, only $C_NFF_SN got sneak dice"
fi
# D: Blind-Fight must suppress both unseen flags in melee.
if [ "$D_PRE" -lt "$MIN_COUNT" ]; then
    fail "case D measured only $D_PRE invisible melee pre lines (need >= $MIN_COUNT)"
fi
if [ "$D_PRE_AU" -ne 0 ]; then
    fail "case D: $D_PRE_AU invisible melee pre line(s) read actUnseen=1 (must be 0)"
fi
if [ "$D_PRE_SU" -ne 0 ]; then
    fail "case D: $D_PRE_SU invisible melee pre line(s) read surprise=1 (must be 0)"
fi

if [ "$RC" -ne 0 ]; then
    echo
    echo "FAIL: one or more sneak-attack-from-invisibility assertions failed"
    exit 1
fi
echo "PASS: all sneak-attack-from-invisibility assertions hold"
exit 0
