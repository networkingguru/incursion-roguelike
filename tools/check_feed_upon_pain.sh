#!/bin/bash
# gate: live
# Assert the Feed upon Pain running tally and level-stacking for bead inc-akac.
#
#   tools/check_feed_upon_pain.sh      exit 0 all pass, 1 a failed assertion,
#                                      2 a case measured nothing
#
# Bead inc-akac, made seed-independent by inc-b4l3g.2. src/Creature.cpp's
# POST(EV_STRIKE) handler for CA_FEED_UPON_PAIN keeps a running tally in the
# striker's PAIN_TALLY status: every landed, damaging strike adds dmg * level;
# every full 10 heals that many hit points; the 0-9 remainder carries.
# The old code judged each blow alone (needing MORE than 10), dropped the
# remainder and ignored the level.
#
# facts the check reads, and the control that fixes each (docs/VERIFICATION.md,
# "A check must not depend on the seed"):
# fact: priest race, class, domain, kit (empty weapon hand), HP 29 of 36, tally 6 -- fixture orc-priest-pain-seed1-sneakopts
# fact: priest settings -- INCURSION_OPTIONS=tools/fixtures/options-sneak-invis.dat
# fact: a shrieker beside the priest -- wizard Monster Summoning, RIGHT ENTER
# fact: the priest's blows hit -- INCURSION_LOF_FORCE_ROLL=20
# fact: the priest's punch damage -- INCURSION_FORCE_DAMAGE_ROLL=3
# fact: number of blows the shrieker survives -- not read; every assertion holds for any count of 1 or more
# fact: giant-case character (visible, so the giant attacks) -- fixture orc-priest-pain-seed1-sneakopts
# fact: giant-case settings -- INCURSION_OPTIONS=tools/fixtures/options-sneak-invis.dat
# fact: one frost giant beside the character -- wizard Monster Summoning, RIGHT ENTER
# fact: the giant's blows hit, and none is a critical -- INCURSION_LOF_FORCE_ROLL=19
# fact: the giant's damage dice -- INCURSION_FORCE_DAMAGE_ROLL=2
# fact: a giant's weapon and enchantment, so odd or even blow -- INCURSION_SUMMON_NO_GEAR=1 (src/Debug.cpp)
# fact: the giant notices the priest and attacks -- not read; every assertion holds for any count of 1 or more
#
# THE PROBE. src/Creature.cpp's PainProbeNote writes logs/pain.log (one line
# per landed, damaging strike by a creature with CA_FEED_UPON_PAIN: actor,
# level, damage, tally before and after, hit points healed). INCURSION_PAIN_PROBE=1.
#
# PRIEST (level 1). tools/keys/pain-experiment.keys loads the wounded priest,
# summons a shrieker next to him and punches it. A punch (1d3+3) never passes
# 10, so the old code logs NO line: any line is RED on the old code. Each line
# MUST show the tally rule, a heal of exactly (tally_before + dmg*level)/10
# (the priest is wounded, so max HP never caps it), and one heal at least.
#
# FROST GIANT (level 6). tools/keys/pain-giant.keys loads the priest, summons one
# giant with no gear (INCURSION_SUMMON_NO_GEAR=1) and waits. Each line MUST show level 6 and the tally rule, and EVERY blow MUST be
# of ODD damage: for even damage dmg*6 and dmg agree mod 10, so the "ignore the
# level" mutant would pass. The fixed damage is odd with 2 as the damage roll.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }

PRIEST_OPTIONS=tools/fixtures/options-sneak-invis.dat
PRIEST_SAVE=tools/fixtures/chars/orc-priest-pain-seed1-sneakopts.sav
PRIEST_KEY=tools/keys/pain-experiment.keys
GIANT_OPTIONS=$PRIEST_OPTIONS
GIANT_SAVE=$PRIEST_SAVE
GIANT_KEY=tools/keys/pain-giant.keys
PRIEST_DMG=3
GIANT_DMG=2
PRIEST_LOF=20
# not 20: a natural 20 is a critical hit and doubles every blow, so every blow is even.
# 18 keeps the Power Attack bonus (margin/3) the same for any defense the target shows
GIANT_LOF=18
for f in "$PRIEST_OPTIONS" "$PRIEST_SAVE" "$PRIEST_KEY" "$GIANT_OPTIONS" "$GIANT_SAVE" "$GIANT_KEY"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: $f is not there"; exit 2; }
done

TOKEN="${INCURSION_CHECK_TOKEN:-$$-$(date +%s)}"
RUN_SEQ=0
FAILED=0

# One run in its own directory; prints the run directory.
run_one() { # <keyscript> <options> <save> <damage roll> <attack roll> <label>
    local keys="$1" opts="$2" save="$3" dmg="$4" lof="$5" label="$6" out run
    RUN_SEQ=$((RUN_SEQ+1))
    local RUN_DIR="$ROOT/logs/runs/check-feed-pain-$TOKEN-$(printf '%02d' "$RUN_SEQ")-$label"
    rm -rf "$RUN_DIR"
    export INCURSION_RUN_DIR="$RUN_DIR"
    out="$(INCURSION_OPTIONS="$opts" INCURSION_LOAD="$save" INCURSION_PAIN_PROBE=1 INCURSION_SUMMON_NO_GEAR=1 \
            INCURSION_LOF_FORCE_ROLL="$lof" INCURSION_FORCE_DAMAGE_ROLL="$dmg" \
            tools/headless.sh "$keys" 1 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if grep -qE 'WATCHDOG|FATAL' <<< "$out"; then
        FAILED=$((FAILED+1))
    fi
    echo "$run"
}

echo "Feed upon Pain running tally + level stacking (inc-akac)"
echo

# ---------------------------------------------------------------- priest
RUN="$(run_one "$PRIEST_KEY" "$PRIEST_OPTIONS" "$PRIEST_SAVE" "$PRIEST_DMG" "$PRIEST_LOF" priest)"
LOG="$RUN/logs/pain.log"
PRIEST_LINES=""
[ -f "$LOG" ] && PRIEST_LINES="$(cat "$LOG")"

# The fixture must start wounded, or the heal cap would hide the heal.
START_HP="$(grep -h '^HP:' "$RUN"/logs/screens/*-start.txt 2>/dev/null | head -1 | sed 's/^HP:\([0-9]*\)\/\([0-9]*\).*/\1 \2/')"
read -r HP_NOW HP_MAX <<< "$START_HP"

read -r TOTAL LOW HEAL_POS MATH_BAD HEAL_BAD LVL_BAD < <(echo "$PRIEST_LINES" | awk '
    /^turn/ {
        for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
        total++
        dmg = v["dmg"] + 0; lvl = v["level"] + 0
        tb = v["tally_before"] + 0; ta = v["tally_after"] + 0
        healed = v["healed"] + 0
        if (ta != (tb + dmg * lvl) % 10) bad++
        if (healed != int((tb + dmg * lvl) / 10)) hbad++
        if (lvl != 1) lbad++
        if (dmg <= 10) low++
        if (healed > 0) healpos++
    }
    END { print total+0, low+0, healpos+0, bad+0, hbad+0, lbad+0 }
')

echo "PRIEST (level 1, brawling, every blow <= 10 damage):"
echo "     hit points at the start:                                  ${HP_NOW:-?}/${HP_MAX:-?}"
echo "     total probe lines:                                        $TOTAL"
echo "     of those, dmg <= 10 (the RED-vs-old-code subset):          $LOW"
echo "     of those, an actual heal (healed > 0) happened:            $HEAL_POS"
echo "     tally-arithmetic mismatches (must be 0):                   $MATH_BAD"
echo "     heal != (tally_before + dmg*level)/10 (must be 0):         $HEAL_BAD"
echo "     lines whose level field is not 1 (must be 0):              $LVL_BAD"
echo

# ---------------------------------------------------------------- giants
RUN="$(run_one "$GIANT_KEY" "$GIANT_OPTIONS" "$GIANT_SAVE" "$GIANT_DMG" "$GIANT_LOF" giant)"
LOG="$RUN/logs/pain.log"
GIANT_LINES=""
[ -f "$LOG" ] && GIANT_LINES="$(grep 'actor=<frost giant>' "$LOG" 2>/dev/null)"

read -r GTOTAL GBAD GLVLBAD GODD GEVEN < <(echo "$GIANT_LINES" | awk '
    /^turn/ {
        for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
        total++
        dmg = v["dmg"] + 0; lvl = v["level"] + 0
        tb = v["tally_before"] + 0; ta = v["tally_after"] + 0
        if (ta != (tb + dmg * lvl) % 10) bad++
        if (lvl != 6) lvlbad++
        if (dmg % 2 == 1) odd++; else even++
    }
    END { print total+0, bad+0, lvlbad+0, odd+0, even+0 }
')

echo "FROST GIANTS (level 6):"
echo "     total probe lines:                                        $GTOTAL"
echo "     tally-arithmetic mismatches (must be 0):                   $GBAD"
echo "     lines whose level field is not 6 (must be 0):              $GLVLBAD"
echo "     lines with odd damage (need all):                          $GODD"
echo "     lines with even damage (must be 0):                        $GEVEN"
echo
echo "failed runs (WATCHDOG/FATAL): $FAILED"
echo

# ---------------------------------------------------------------- assertions
if [ "$TOTAL" -eq 0 ] && [ "$GTOTAL" -eq 0 ]; then
    echo "FAIL: nothing was measured; neither case produced a probe line"
    exit 2
fi
if [ "$TOTAL" -eq 0 ]; then
    echo "FAIL: the priest case saw no probe line at all"
    exit 2
fi
if [ "$GTOTAL" -eq 0 ]; then
    echo "FAIL: the frost giant case saw no probe line at all"
    exit 2
fi
if [ -z "$HP_NOW" ] || [ -z "$HP_MAX" ]; then
    echo "FAIL: could not read the priest's starting hit points"
    exit 2
fi
if [ "$HP_NOW" -ge "$HP_MAX" ]; then
    echo "FAIL: the priest starts at full hit points, so max HP would cap every heal"
    exit 2
fi

RC=0
fail() { echo "FAIL: $*"; RC=1; }

[ "$LOW" -ne "$TOTAL" ] && fail "priest case: $((TOTAL-LOW)) strike(s) over 10 damage, so the old code would not be RED"
[ "$HEAL_POS" -lt 1 ] && fail "priest case saw no actual heal"
[ "$MATH_BAD" -ne 0 ] && fail "priest case: $MATH_BAD probe line(s) failed the tally-arithmetic check"
[ "$HEAL_BAD" -ne 0 ] && fail "priest case: $HEAL_BAD probe line(s) healed other than the rule's amount"
[ "$LVL_BAD" -ne 0 ] && fail "priest case: $LVL_BAD probe line(s) read a level other than 1"
[ "$GBAD" -ne 0 ] && fail "frost giant case: $GBAD probe line(s) failed the tally-arithmetic check"
[ "$GEVEN" -ne 0 ] && fail "frost giant case: $GEVEN blow(s) of even damage, so the level cannot be told from 1"
[ "$GLVLBAD" -ne 0 ] && fail "frost giant case: $GLVLBAD probe line(s) read a level other than 6"

if [ "$RC" -ne 0 ]; then
    echo
    echo "FAIL: one or more Feed upon Pain assertions failed"
    exit 1
fi
echo "PASS: Feed upon Pain running tally and level stacking both hold"
exit 0
