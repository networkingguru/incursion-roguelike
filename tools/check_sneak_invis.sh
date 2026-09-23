#!/bin/bash
# gate: live
# Assert the sneak-attack-from-invisibility rules for bead inc-nkf2.
#
#   tools/check_sneak_invis.sh [trials]      exit 0 all pass, 1 a failed
#                                            assertion, 2 a case measured
#                                            nothing
#
# Bead inc-nkf2. Two defects fixed in src/Fight.cpp:
#
#   FIX 1  Creature::Hit's sneak gate did not read e.actUnseen, so an invisible
#          first blow the victim HEARD (the Move Silently vs Listen contest at
#          src/Fight.cpp:4184 cleared isSurprise) got no sneak dice, even though
#          the defence block at :4270 already treats actUnseen as no-Dex.
#   FIX 2  Creature::PreStrike set e.actUnseen and e.isSurprise together behind
#          "!Perceives && !HasFeat(FT_BLIND_FIGHT)". Blind-Fight protects only
#          against a MELEE unseen attacker (SRD), so a RANGED attack from an
#          unperceived attacker must still count as unseen.
#
# INCURSION_OPTIONS overrides the settings fixture; the default is
# tools/fixtures/options-sneak-invis.dat, tools/gates/Options.Dat with
# Automatic Hide in Shadows (option 518) forced OFF. With auto-hide on, the
# rogue hides in the dark and every blow would be an unseen attack without a
# spell, spoiling the visible control.
#
# THE PROBE. src/Fight.cpp's SneakProbeNote writes logs/sneak.log in a run
# directory: "pre" once per PreStrike (the moment the sneak gate will read the
# fields, before the Listen contest and before damage) and "attack" once per
# Creature::Hit, after the sneak gate. Set INCURSION_SNEAK_PROBE=1; this script
# sets it. Each run gets a FRESH directory (the probe appends), so two
# invocations of this script tally the same counts.
#
# THE CASES, each read out of logs/sneak.log:
#
#   A   invisible MELEE first blow, victim HEARD the rogue, blow landed, victim
#       not flat-footed: sneak=1 on every such blow. FIX 1. RED before the fix.
#   A2  invisible MELEE first blow, victim did NOT hear: sneak=1. Green on the
#       old code too (isSurprise held); guards against a regression.
#   B   visible control blow at a non-flat-footed victim: sneak=0 always.
#   C   invisible RANGED first blow at a Blind-Fight victim: actUnseen=1 and
#       surprise=0 on every "pre". FIX 2. RED before the fix. Where a blow
#       lands on a non-flat-footed victim, sneak=1; if no such blow is measured
#       in the trial set the script says so and does not assert it.
#   D   invisible MELEE first blow at a Blind-Fight victim: actUnseen=0 and
#       surprise=0 on every "pre". Green on the old code too; guards that
#       Blind-Fight still protects in melee after FIX 2.
#
# A case that produces no probe line at all for its victim exits 2: nothing was
# measured. Every asserted denominator must reach MIN_COUNT, or exit 1 -- a
# count of 0 or 2 is not evidence.
#
# The victim is named in the log, so a player attack is one whose
# "victim=<name>"; the victim's own blows name the player and are ignored.
#
# Commands (Brian's brief, docs/VERIFICATION.md):
#   BACKEND=posix ./build_macos.sh
#   tools/check_sneak_invis.sh            # green on the fixed build
#   tools/check_sneak_invis.sh            # second run: identical counts
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }

TRIALS="${1:-25}"
MIN_COUNT=5
OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-sneak-invis.dat}"
[ -f "$OPTIONS" ] || { echo "INCONCLUSIVE: settings file $OPTIONS is not there"; exit 2; }

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

# Fresh directory per trial. The probe appends, so a reused directory would
# double the counts on a second invocation; the token makes two concurrent
# invocations distinct and the rm makes a repeated one fresh. (inc-nkf2)
TOKEN="${INCURSION_CHECK_TOKEN:-$$-$(date +%s)}"
RUN_SEQ=0
run_one() { # <keyscript> <seed> <label> -> prints the run directory
    local keys="$1" seed="$2" label="$3" out run
    RUN_SEQ=$((RUN_SEQ+1))
    local RUN_DIR="$ROOT/logs/runs/check-sneak-$TOKEN-$(printf '%02d' "$RUN_SEQ")-$label-seed$seed"
    rm -rf "$RUN_DIR"
    export INCURSION_RUN_DIR="$RUN_DIR"
    out="$(INCURSION_OPTIONS="$OPTIONS" INCURSION_SNEAK_PROBE=1 \
            tools/headless.sh "$keys" "$seed" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if grep -qE 'NO GAMEPLAY|the key script looked for something|WATCHDOG|FATAL' <<< "$out"; then
        FAILED=$((FAILED+1))
    fi
    echo "$run"
}

echo "sneak-attack from invisibility (inc-nkf2), $TRIALS trials each"
echo "options: $OPTIONS"
echo

# ---------------------------------------------------------------- cases A/B
for seed in $(seq 1 "$TRIALS"); do
    RUN="$(run_one "$MELEE_KEY" "$seed" melee)"
    LOG="$RUN/logs/sneak.log"
    [ -f "$LOG" ] || continue
    read -r ah ahnff ahnffsn ahsn au aunff aunffsn ausn setup bh bok bbad lines < <(awk -v v="$MELEE_VICTIM" '
        $0 ~ ("victim=<" v ">") {
            if (/ pre /) { lines++; if (/invisVal=1/) { invisSeen=1; heard=0 } }
            if (/hears-you/) { if (invisSeen) heard=1 }
            if (/ attack /) {
                lines++
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
        END { print ah+0, ahnff+0, ahnffsn+0, ahsn+0, au+0, aunff+0, aunffsn+0, ausn+0, setup+0, bh+0, bok+0, bbad+0, lines+0 }
    ' "$LOG")
    A_HIT=$((A_HIT+ah)); A_NFF=$((A_NFF+ahnff)); A_NFF_SN=$((A_NFF_SN+ahnffsn)); A_SN=$((A_SN+ahsn))
    A2_HIT=$((A2_HIT+au)); A2_NFF=$((A2_NFF+aunff)); A2_NFF_SN=$((A2_NFF_SN+aunffsn)); A2_SN=$((A2_SN+ausn))
    B_HIT=$((B_HIT+bh)); B_OK=$((B_OK+bok)); B_BAD=$((B_BAD+bbad)); SETUP_HIT=$((SETUP_HIT+setup))
    MELEE_LINES=$((MELEE_LINES+lines))
done

echo "A. invisible first blow (melee), victim HEARD the rogue:"
echo "     blows at a non-flat-footed victim that reached the gate:  $A_NFF"
echo "     ...of those, sneak=1 (must be all):                       $A_NFF_SN"
echo "     (all heard blows, any flatfoot state:                     $A_HIT; sneak=1: $A_SN)"
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
for seed in $(seq 1 "$TRIALS"); do
    RUN="$(run_one "$RANGED_KEY" "$seed" ranged)"
    LOG="$RUN/logs/sneak.log"
    [ -f "$LOG" ] || continue
    read -r cp cpau cpsu ch cnff cnffsn lines < <(awk -v v="$RANGED_VICTIM" '
        $0 ~ ("victim=<" v ">") {
            if (/ pre /) { lines++; if (/invisVal=1/ && /dist=[23]/) { invisSeen=1; cp++; if (/actUnseen=1/) cpau++; if (/surprise=1/) cpsu++ } }
            if (/ attack / && /dist=[23]/) { lines++; if (invisSeen) { ch++; if (/flatfoot=0/) { cnff++; if (/sneak=1/) cnffsn++ } ; invisSeen=0 } }
        }
        END { print cp+0, cpau+0, cpsu+0, ch+0, cnff+0, cnffsn+0, lines+0 }
    ' "$LOG")
    C_PRE=$((C_PRE+cp)); C_PRE_AU=$((C_PRE_AU+cpau)); C_PRE_SU=$((C_PRE_SU+cpsu))
    C_HIT=$((C_HIT+ch)); C_NFF=$((C_NFF+cnff)); C_NFF_SN=$((C_NFF_SN+cnffsn))
    RANGED_LINES=$((RANGED_LINES+lines))
done

C_SNEAK_MEASURED=0
[ "$C_NFF" -ge "$MIN_COUNT" ] && C_SNEAK_MEASURED=1

echo "C. invisible RANGED first blow at a Blind-Fight victim:"
echo "     invisVal=1 pre lines (distance 2-3):                      $C_PRE"
echo "     ...of those, actUnseen=1 (must be all):                   $C_PRE_AU"
echo "     ...of those, surprise=1 (must be 0):                      $C_PRE_SU"
if [ "$C_SNEAK_MEASURED" -eq 1 ]; then
    echo "     landed blows at a non-flat-footed victim:                 $C_NFF"
    echo "     ...of those, sneak=1 (must be all):                       $C_NFF_SN"
else
    echo "     landed blows at a non-flat-footed victim:                 $C_NFF"
    echo "     SNEAK HALF OF C UNMEASURED: fewer than $MIN_COUNT such blows; not asserted"
fi
echo

# ---------------------------------------------------------------- case D
for seed in $(seq 1 "$TRIALS"); do
    RUN="$(run_one "$BLINDFIGHT_KEY" "$seed" blindfight)"
    LOG="$RUN/logs/sneak.log"
    [ -f "$LOG" ] || continue
    read -r dp dpau dpsu dh lines < <(awk -v v="$BLINDFIGHT_VICTIM" '
        $0 ~ ("victim=<" v ">") {
            if (/ pre /) { lines++; if (/invisVal=1/) { invisSeen=1; dp++; if (/actUnseen=1/) dpau++; if (/surprise=1/) dpsu++ } }
            if (/ attack /) { lines++; if (invisSeen) { dh++; invisSeen=0 } }
        }
        END { print dp+0, dpau+0, dpsu+0, dh+0, lines+0 }
    ' "$LOG")
    D_PRE=$((D_PRE+dp)); D_PRE_AU=$((D_PRE_AU+dpau)); D_PRE_SU=$((D_PRE_SU+dpsu)); D_HIT=$((D_HIT+dh))
    BF_LINES=$((BF_LINES+lines))
done

echo "D. invisible MELEE first blow at a Blind-Fight victim:"
echo "     invisVal=1 pre lines:                                     $D_PRE"
echo "     ...of those, actUnseen=1 (must be 0):                     $D_PRE_AU"
echo "     ...of those, surprise=1 (must be 0):                      $D_PRE_SU"
echo "     first blows that reached the gate:                        $D_HIT"
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
if [ "$C_SNEAK_MEASURED" -eq 1 ] && [ "$C_NFF_SN" -ne "$C_NFF" ]; then
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
