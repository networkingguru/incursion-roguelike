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
#      Nothing tied that to a fight at all, so the free strike was payable
#      again and again inside one melee -- sneak attack damage, for a rogue,
#      before every single blow.
#
# THE RULE, in Brian's words: "first attack after snapping out, IN OR OUT OF
# COMBAT = free sneak attack, but never again during that combat (if you SA
# out of combat, you start combat, hence no more free sneak atk)."
#
# HOW THAT IS WRITTEN WITHOUT INVENTING STATE. A COUNTER stati on the bracers
# marks a fight that has already yielded its opening. The engine's own
# out-of-combat counter does not GRANT the opening -- it CLEARS that mark.
# Creature::isFlatFooted() is FFCount > min(5,10+Mod(A_WIS))
# (inc/Creature.h:571-572); Creature::DoTurn() raises it one per quiet turn
# (src/Creature.cpp:1590-1591) and any strike zeroes it for both fighters
# (src/Fight.cpp:3258-3259). lib/prestige.irh reads the same field for the
# Assassin's Death Attack. The two walks:
#
#   deploy while quiet      the mark clears, the opening arms, and the blow
#                           that takes it starts the fight -- so a further
#                           deployment in that fight finds the mark set
#   deploy during a fight   the mark was cleared the last time the wielder was
#                           quiet, so the opening still arms; a further
#                           deployment in that same fight does not
#
# THE COST OF A FAILED CHECK is 50, which is the engine's own number: "a
# 'full round action', in the base system" (src/Fight.cpp:2531).
#
# THE THREE ORACLES, one run each, all on the seed pinned below.
#
#   jam    the turn stamp in the dump headers that posixTerm::DumpScreen
#          writes (src/Wposix.cpp). A jammed attempt must move it by at least a
#          full round; a successful one must not move it at all, because the
#          page says deployment takes no time and that half was never wrong.
#
#   cold   the item's own line, "Springblade effect!", after blades snapped out
#          while the sidebar still said "Exploring". This is the CONTROL and it
#          is green on every build: it is what stops a "fix" that merely
#          deleted the effect from passing.
#
#   hot    the same line, PRESENT, after blades snapped out for the first time
#          while the sidebar said "Fighting". This is the case the rule is
#          about, and it is red on both of the wrong rules -- the original,
#          which armed on every deployment and so cannot distinguish anything,
#          is caught by the jam half instead.
#
# WHAT THIS CHECK DOES NOT MEASURE, and why not. The rule's second half -- a
# SECOND deployment inside one fight arms nothing, and a deployment after the
# fight ends arms again -- has no oracle, because no second deployment is
# possible in a running game. Measured three ways: ALT_ITEM exists only to
# serve this item (inc/Defines.h:3056) and is granted with a negative
# duration, which the stati clock never decrements (src/Status.cpp:50-62);
# nothing in src/ removes it; Player::CancelMenu will not list the bracers,
# because it skips a stati whose item Owner() is not the wielder
# (src/Skills.cpp:312-315) and the blades belong to no inventory; and dropping
# the bracers after deploying leaves the deployment standing -- the next
# activation still answers "You're already loaded!". So the mark is written
# and cannot yet bind. That is stated here rather than guarded, because a
# passing assertion for an unreachable case would be a lie.
#
# THE SIDEBAR WORD IS NOT THE CHECK'S OPINION. src/Term.cpp:388-392 prints
# "Exploring" when isFlatFooted() is true and "Fighting" when it is false, so
# each run's dump states the engine's own view of the one field the fix reads.
# The check reads it back rather than trusting what the key script arranged --
# a jammed attempt costs a round, and enough of them in a row would carry a
# wielder back out of combat and quietly void the hot measurement.
#
# THE HOT STRIKE MUST LAND. A miss never reaches PRE(EV_HIT), so it cannot
# print the springblade line either, and would read as a failing fix. The check
# requires the engine's own report that the blow connected.
#
# PROVED RED FIRST, on the same seed, against the two earlier builds:
#   against the ORIGINAL, with no Handle Device check at all: 8 deployments,
#   none failed, turn 198046 -> 198046.
#   against the FIRST, WRONG rule, which armed the opening only while the
#   wielder was out of combat: the hot run's blow landed and printed no
#   springblade line.
# After this fix: the first jam costs 51 turns, the deployment that follows
# costs 0, cold fires, and hot fires on a blow that killed the goblin.
#
# Usage: tools/check_springblade.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# WHY SEED 19, and why not 2. The seed was 2 until 2026-08-24. The
# two-weapon run builds its rogue with `@choose "Two-Weapon Styl"`, and
# @choose reads only the screen in front of it (src/Wposix.cpp:940-999) --
# it does not press TAB. That day's item work added one more feat, Swarm
# Tactics, to the offered list. The seed-2 orc qualified for 56 feats, the
# menu holds 51 per page, and Two-Weapon Style moved to page 2, so chargen
# stopped and the whole check exited 2, INCONCLUSIVE.
#
# Seed 19 was chosen because all five assertions run and pass on it: the
# jam costs 51 turns, the deployment that follows costs 0, cold fires, hot
# fires on a landed blow, and both blades out read Hit:6 / 4.
#
# A REPLACEMENT SEED MUST MEET FOUR CONDITIONS, so do not repin blindly.
#   1  Its orc must reach Two-Weapon Style on page 1 of the feat menu.
#   2  A rogue must jam at least one of the jam run's eight attempts.
#   3  The hot run's blow must land, or PRE(EV_HIT) never runs.
#   4  Its orc must have the same STR and DEX modifiers as seed 2's, or
#      the hardcoded 6 / 4 and 4 / 2 below stop being the tagged and
#      untagged readings of the same character. Seed 19 rolls STR 21 and
#      DEX 15 against seed 2's STR 20 and DEX 14 -- different numbers, the
#      same modifiers, so the arithmetic those two pairs come from is
#      unchanged. Seeds 1, 3 and 5 all fail one of the four.
SEED=19
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
        echo "  ok: a first deployment made during a fight bought the opening" ;;
    *)
        echo "FAIL: blades snapped out for the first time in the middle of a"
        echo "      fight bought nothing. The opening is meant to be worth one"
        echo "      per fight, in combat or out of it -- see the Effect"
        echo "      \"Springblade Bracers\" EV_MAGIC_HIT handler in"
        echo "      lib/m_items.irh. A rule that reads the out-of-combat"
        echo "      counter to GRANT the opening rather than to CLEAR the mark"
        echo "      fails exactly here."
        echo "      dump: $HOTHIT"
        fail=1 ;;
esac

# ------------------------------------------- the tag: two blades, two hands
# Item "springblade" carried Group: WG_SBLADES and nothing else. The short
# sword it is otherwise a copy of carries WG_SBLADES | WG_LIGHT
# (lib/weapons.irh:401). Creature::CalcValues charges an extra -2 to the main
# hand and -2 to the off hand when the off-hand weapon is neither light nor
# smaller than the main-hand weapon (src/Values.cpp:1345-1352). Two springblades
# are the same size, so without the tag that clause fired on a pair of them.
LIGHT="$(run_case tools/keys/springblade-light.keys)"

# BOTH blades must be out. One blade leaves the off hand empty, the clause
# unexercised, and the Hit numbers meaningless. The plural line is the game's
# own report that two came out.
LIGHTOUT="$(first_dump_with "$LIGHT" "gleamingbladessnapoutofyourbracers")" || {
    echo "INCONCLUSIVE: the two-weapon run never got both blades out in six"
    echo "              tries, so the off hand was empty. screens: $LIGHT"
    exit 2
}

# "Hit:4 / 2" -- the main hand, then the off hand.
hit_pair() {    # hit_pair <dump file> -> "<main> <offhand>"
    sed -n 's/.*|Hit:\([-0-9]*\) *\/ *\([-0-9]*\).*/\1 \2/p' "$1" | head -1
}

PAIR="$(hit_pair "$LIGHTOUT")"
[ -n "$PAIR" ] || {
    echo "INCONCLUSIVE: the sidebar in $LIGHTOUT printed no two-handed Hit line,"
    echo "              so the character was not fighting with two weapons."
    exit 2
}

if [ "$PAIR" = "6 4" ]; then
    echo "  ok: two springblades cost no unwieldy-off-hand penalty (Hit:6 / 4)"
elif [ "$PAIR" = "4 2" ]; then
    echo "FAIL: two springblades were charged the unwieldy-off-hand penalty."
    echo "      Hit:$(echo "$PAIR" | tr ' ' '/' | sed 's|/| / |') -- two lower"
    echo "      in each hand than the 6 / 4 a light off-hand pays. Item"
    echo "      \"springblade\" in lib/m_items.irh is missing WG_LIGHT from its"
    echo "      Group, which src/Values.cpp:1348 reads to waive that clause."
    echo "      dump: $LIGHTOUT"
    fail=1
else
    echo "INCONCLUSIVE: the sidebar read Hit:$(echo "$PAIR" | tr ' ' '/')"
    echo "              , which is neither the tagged 6 / 4 nor the untagged"
    echo "              4 / 2. Something other than this tag moved the number;"
    echo "              re-derive both before trusting either. dump: $LIGHTOUT"
    exit 2
fi

if [ "$fail" = 0 ]; then
    echo "PASS: a failed Handle Device check costs the round, the free off-guard"
    echo "      strike is bought in or out of combat, and a springblade counts"
    echo "      as a light weapon in the off hand."
    exit 0
fi
exit 1
