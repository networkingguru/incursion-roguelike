#!/bin/bash
# Regression check for the Springblade Bracers, bd inc-tek.8.8, finding
# PA-08-F14.
#
# THE DEFECT, in two halves, both in lib/m_items.irh.
#
#   1  The item's page has always said that snapping the blades out "does
#      require a Handle Device check (DC 15)". The activation handler
#      contained no SkillCheck call at all, so deployment never failed and
#      never cost anything.
#
#   2  Every deployment re-armed the COUNTER that makes the next springblade
#      blow treat the foe as off-guard (Item "springblade", PRE(EV_HIT)).
#      Nothing tied that to the opening of a fight, so a wielder who snapped
#      the blades out in the middle of a melee bought the same free off-guard
#      strike -- sneak attack damage, for a rogue -- that the page sells as the
#      reward for coming to the fight ready.
#
# WHAT "ONCE PER ENGAGEMENT" IS, in the engine's own terms. There is no
# engagement object to read, so the fix reads the thing the engine already
# keeps: Creature::isFlatFooted(), which is not the D&D condition but a
# per-creature out-of-combat counter, FFCount > min(5,10+Mod(A_WIS))
# (inc/Creature.h:571-572). Creature::DoTurn() raises it by one per turn out of
# combat (src/Creature.cpp:1590-1591) and any strike zeroes it for both
# fighters (src/Fight.cpp:3258-3259). The blades now arm only while that
# counter is still high. lib/prestige.irh reads the same field for the
# Assassin's Death Attack, so this is the codebase's existing answer to the
# same question.
#
# THE COST OF A FAILED CHECK is 50, which is the engine's own number: "a
# 'full round action', in the base system" (src/Fight.cpp:2531).
#
# THE THREE ORACLES, one run each, all on SEED 2.
#
#   jam    the turn stamp in the dump headers that posixTerm::DumpScreen
#          writes (src/Wposix.cpp). A jammed attempt must move it by at least a
#          full round; a successful one must not move it at all, because the
#          page says deployment takes no time and that half was never wrong.
#
#   cold   the item's own line, "Springblade effect!", after blades snapped out
#          while the sidebar still said "Exploring". This is the CONTROL and it
#          was green before the fix as well: it is what stops a "fix" that
#          merely deleted the effect from passing.
#
#   hot    the same line, absent, after blades snapped out while the sidebar
#          said "Fighting". Before the fix it was present.
#
# THE SIDEBAR WORD IS NOT THE CHECK'S OPINION. src/Term.cpp:388-392 prints
# "Exploring" when isFlatFooted() is true and "Fighting" when it is false, so
# each run's dump states the engine's own view of the one field the fix reads.
# The check reads it back rather than trusting what the key script arranged --
# a jammed attempt costs a round, and enough of them in a row would carry a
# wielder back out of combat and quietly void the hot measurement.
#
# THE HOT STRIKE MUST LAND. A miss never reaches PRE(EV_HIT), so it cannot
# print the springblade line either, and would read as a passing fix. The check
# requires the engine's own report that the blow connected.
#
# PROVED RED FIRST, on the same seed, with lib/m_items.irh reverted and the
# module rebuilt:
#   jam    8 attempts, no jam, turn 198046 -> 198046. Nothing failed, nothing
#          was paid for.
#   cold   "Springblade effect!" present.  (green before and after)
#   hot    "Springblade effect!" present.  (the defect)
# After the fix: the first jam cost 51 turns and the deployment that followed
# cost 0; cold still fires; hot does not, on a blow that killed the goblin.
#
# Usage: tools/check_springblade.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=2
fail=0

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

run_case() {    # run_case <keyscript> -> echoes the run's screens directory
    local out run
    out="$(tools/headless.sh "$1" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if echo "$out" | grep -q "the key script looked for something"; then
        echo "INCONCLUSIVE: $1 could not find something on screen. Run: $run" >&2
        exit 2
    fi
    if echo "$out" | grep -q "NO GAMEPLAY"; then
        echo "INCONCLUSIVE: $1 never entered a map. Run: $run" >&2
        exit 2
    fi
    echo "$run/logs/screens"
}

# The message area wraps mid-word against the sidebar, so every comparison is
# made on the text with all whitespace removed. That is wrap-proof; matching
# whole words is not.
messages() {    # messages <dump file> -> the message area, lowercased, unspaced
    sed -n '2,5p' "$1" | cut -c1-64 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'
}

turn_of() {     # turn_of <dump file> -> the turn stamp in its header
    sed -n '1p' "$1" | awk '{for (i=1;i<NF;i++) if ($i=="turn") print $(i+1)}'
}

# Find the first dump whose message area contains a phrase. Dumps sort by their
# four-digit prefix, which is the order they were written in.
first_dump_with() {     # first_dump_with <screens dir> <unspaced phrase>
    local f
    for f in "$1"/*.txt; do
        case "$(messages "$f")" in
            *"$2"*) echo "$f"; return 0 ;;
        esac
    done
    return 1
}

prev_dump() {   # prev_dump <screens dir> <dump file> -> the dump written before it
    local f last=""
    for f in "$1"/*.txt; do
        [ "$f" = "$2" ] && { echo "$last"; return 0; }
        last="$f"
    done
    return 1
}

# --------------------------------------------------------------- the clock
JAM="$(run_case tools/keys/springblade-jam.keys)"

JAMMED="$(first_dump_with "$JAM" "thespringsjam")" || {
    echo "FAIL: eight deployments in a row, and not one of them failed a Handle"
    echo "      Device check. The page promises DC 15 and the handler is not"
    echo "      asking for it. screens: $JAM"
    fail=1
}

if [ "$fail" = 0 ]; then
    BEFORE="$(prev_dump "$JAM" "$JAMMED")"
    COST=$(( $(turn_of "$JAMMED") - $(turn_of "$BEFORE") ))
    if [ "$COST" -ge 50 ]; then
        echo "  ok: a jammed deployment cost $COST turns (a full round is 50)"
    else
        echo "FAIL: a jammed deployment cost $COST turns. A failed check is"
        echo "      supposed to cost the round, which src/Fight.cpp:2531 values"
        echo "      at 50. dump: $JAMMED"
        fail=1
    fi

    # The other half of the page: a deployment that passes still takes no time.
    OUT="$(first_dump_with "$JAM" "snapsoutofoneofyourbracers")" ||
    OUT="$(first_dump_with "$JAM" "snapoutofyourbracers")" || {
        echo "INCONCLUSIVE: no attempt in the jam run ever deployed the blades."
        echo "              screens: $JAM"
        exit 2
    }
    FREE=$(( $(turn_of "$OUT") - $(turn_of "$(prev_dump "$JAM" "$OUT")") ))
    if [ "$FREE" = 0 ]; then
        echo "  ok: a successful deployment still cost no time"
    else
        echo "FAIL: a successful deployment cost $FREE turns. The page says it"
        echo "      takes no time, and that half was never wrong. dump: $OUT"
        fail=1
    fi
fi

# ------------------------------------------------- the control: cold blades
COLD="$(run_case tools/keys/springblade-cold.keys)"

COLDOUT="$(first_dump_with "$COLD" "snapsoutofoneofyourbracers")" ||
COLDOUT="$(first_dump_with "$COLD" "snapoutofyourbracers")" || {
    echo "INCONCLUSIVE: the cold run never deployed the blades in eight tries."
    echo "              screens: $COLD"
    exit 2
}
grep -q "|Exploring" "$COLDOUT" || {
    echo "INCONCLUSIVE: the cold run deployed while the sidebar said Fighting,"
    echo "              so it measured the hot case instead. dump: $COLDOUT"
    exit 2
}

COLDHIT="$COLD/0010-0010-strike.txt"
[ -f "$COLDHIT" ] || { echo "INCONCLUSIVE: no strike dump in $COLD"; exit 2; }
case "$(messages "$COLDHIT")" in
    *missingthegoblin*)
        echo "INCONCLUSIVE: the cold run's blow missed, so PRE(EV_HIT) never ran"
        echo "              and nothing was measured. dump: $COLDHIT"
        exit 2 ;;
esac
case "$(messages "$COLDHIT")" in
    *springbladeeffect*)
        echo "  ok: blades snapped out before the fight still bought the opening" ;;
    *)
        echo "FAIL: the CONTROL failed. Blades deployed while the wielder was"
        echo "      out of combat did NOT treat the foe as off-guard, so the"
        echo "      item's whole point is gone rather than merely limited."
        echo "      dump: $COLDHIT"
        fail=1 ;;
esac

# ---------------------------------------------------- the case: hot blades
HOT="$(run_case tools/keys/springblade-hot.keys)"

HOTOUT="$(first_dump_with "$HOT" "snapsoutofoneofyourbracers")" ||
HOTOUT="$(first_dump_with "$HOT" "snapoutofyourbracers")" || {
    echo "INCONCLUSIVE: the hot run never deployed the blades in eight tries."
    echo "              screens: $HOT"
    exit 2
}
grep -q "|Fighting" "$HOTOUT" || {
    echo "INCONCLUSIVE: the hot run deployed while the sidebar said Exploring."
    echo "              Enough jammed attempts in a row carry a wielder back"
    echo "              out of combat, and this run did that, so it measured"
    echo "              the cold case instead. dump: $HOTOUT"
    exit 2
}

HOTHIT="$HOT/0012-0012-strike.txt"
[ -f "$HOTHIT" ] || { echo "INCONCLUSIVE: no strike dump in $HOT"; exit 2; }
case "$(messages "$HOTHIT")" in
    *missingthegoblin*)
        echo "INCONCLUSIVE: the hot run's blow missed, so PRE(EV_HIT) never ran."
        echo "              Absence of the springblade line proves nothing here."
        echo "              dump: $HOTHIT"
        exit 2 ;;
esac
case "$(messages "$HOTHIT")" in
    *springbladeeffect*)
        echo "FAIL: blades deployed in the middle of a fight still bought a free"
        echo "      off-guard strike. That is the defect: the opening is payable"
        echo "      again and again inside one engagement."
        echo "      dump: $HOTHIT"
        fail=1 ;;
    *)
        echo "  ok: blades deployed mid-fight bought no second opening" ;;
esac

if [ "$fail" = 0 ]; then
    echo "PASS: the Handle Device check costs a round when it fails, and the"
    echo "      free off-guard strike is worth one opening per engagement."
    exit 0
fi
exit 1
