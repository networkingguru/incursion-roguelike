#!/bin/bash
# gate: live
# Play the over-cap tome fix (inc-bsqm) instead of probing it: an orc
# barbarian fills his Constitution inherent bonus to the cap with a tome,
# goes above the cap by the only live route (a shambling mound's
# electricity handler, lib/mon3.irh:2100-2103, reached in mound form), and
# reads a second tome through the ordinary 'r' command.
#
# THE DEFECT. Creature::GainInherentBonus (src/Creature.cpp) tested
# `CurrBonus == MaxBonus` and returned "You feel a profound sense of
# wastefulness." only on an exact match, so a total already ABOVE the cap
# fell through and printed a false attribute-gain message instead.
#
# THE ORACLE is the game's own text, read off tools/keys/inh-wasteful-play.keys'
# screen dumps, not an internal probe:
#   *-after-bite.txt    the grid bug's electric bite must have HIT, or the
#                        character was never pushed above the cap and the
#                        run measured nothing.
#   *-read-result.txt    the second tome's read message. Fixed:
#                        "You feel a profound sense of wastefulness."
#                        Before the fix (confirmed by reverting the fix line
#                        and rebuilding): "You feel hardier." -- a false
#                        gain, because the tome's own EV_MAGIC_HIT handler
#                        (lib/m_items.irh) prints that line outside
#                        GainInherentBonus whenever the early return is not
#                        taken.
#   *-sheet-after-bite.txt / *-sheet-after-read.txt
#                        the character sheet's CON line, read before and
#                        after the second tome. It must not change (a wasted
#                        tome does nothing); see the key script's header for
#                        why this alone would not separate fixed from
#                        broken -- the message is what does.
#
# RED on the unfixed code (`==` restored by hand, per AGENTS.md's "revert
# only the fix lines" protocol): FAIL, "You feel hardier." GREEN on the
# fixed code: PASS, the wastefulness line, CON unchanged. Both were run by
# hand for bd inc-bsqm; this script re-checks the fixed side only, the side
# that should always be in the tree.
#
# Usage: tools/check_inh_wasteful_play.sh     (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

SEED=1
KEYS=tools/keys/inh-wasteful-play.keys
OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-18.dat}"
[ -f "$OPTIONS" ] || {
    echo "INCONCLUSIVE: settings file $OPTIONS is not there."
    exit 2
}

TOKEN="${INCURSION_CHECK_TOKEN:-$$-$(date +%s)}"
RUN="$ROOT/logs/runs/check-inh-wasteful-play-$TOKEN-seed$SEED"
rm -rf "$RUN"

OUT="$(env INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTIONS" \
       tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
if [ -z "$RUN" ] || [ ! -d "$RUN" ]; then
    echo "INCONCLUSIVE: the session never reported a run directory." >&2
    echo "$OUT" | tail -12 >&2
    exit 2
fi
if grep -q "the key script looked for something" <<< "$OUT"; then
    echo "INCONCLUSIVE: $KEYS could not find something on screen. Run: $RUN" >&2
    echo "$OUT" | tail -12 >&2
    exit 2
fi

# find_one <pattern> -- echoes the one matching screen on stdout, or prints
# why on stderr and returns 1. Never calls exit: it runs inside $(...), and
# exit there would only end the subshell, leaving the caller none the wiser.
find_one() {
    local matches=("$RUN"/logs/screens/$1)
    if [ ! -e "${matches[0]}" ]; then
        echo "INCONCLUSIVE: no $1 was dumped under $RUN/logs/screens." >&2
        return 1
    fi
    if [ "${#matches[@]}" -ne 1 ]; then
        echo "INCONCLUSIVE: $1 matched ${#matches[@]} screens, not one." >&2
        return 1
    fi
    printf '%s\n' "${matches[0]}"
}

BITE="$(find_one '*-elec-hit.txt')" || exit 2
READ="$(find_one '*-read-result.txt')" || exit 2
BEFORE_SHEET="$(find_one '*-sheet-over-cap.txt')" || exit 2
AFTER_SHEET="$(find_one '*-sheet-post-read.txt')" || exit 2

# Guard: the electric hit must actually have landed, or the character was
# never pushed above the cap and the read below proves nothing.
grep -q "\[hit\]" "$BITE" || {
    echo "INCONCLUSIVE: the grid bug's attack roll was not a hit in $BITE;" >&2
    echo "              the character was never pushed above the cap." >&2
    exit 2
}
grep -q "Lightning" "$BITE" || {
    echo "INCONCLUSIVE: the grid bug's hit in $BITE was not lightning" >&2
    echo "              (electric) damage, so the mound's handler never ran." >&2
    exit 2
}
echo "ok: the grid bug's electric bite hit ($BITE)"

RC=0
fail() { echo "FAIL: $*"; RC=1; }

if grep -q "profound sense of wastefulness" "$READ"; then
    echo "ok: the over-cap tome read printed the wastefulness line ($READ)"
elif grep -q "You feel hardier" "$READ"; then
    fail "the over-cap tome read printed 'You feel hardier.' in $READ --"
    echo "      GainInherentBonus's cap test missed an over-cap total."
else
    echo "INCONCLUSIVE: $READ held neither the wastefulness line nor the" >&2
    echo "              gain message; nothing was measured." >&2
    exit 2
fi

CON_BEFORE="$(awk '/^ Body/ {print; exit}' "$BEFORE_SHEET")"
CON_AFTER="$(awk '/^ Body/ {print; exit}' "$AFTER_SHEET")"
if [ -z "$CON_BEFORE" ] || [ -z "$CON_AFTER" ]; then
    echo "INCONCLUSIVE: could not read the CON line from the character sheet." >&2
    exit 2
fi
if [ "$CON_BEFORE" != "$CON_AFTER" ]; then
    fail "CON changed across the over-cap read:"
    echo "      before: $CON_BEFORE"
    echo "      after:  $CON_AFTER"
else
    echo "ok: CON is unchanged across the over-cap read ($CON_AFTER)"
fi

if [ "$RC" -ne 0 ]; then
    echo
    echo "FAIL: the over-cap tome was not wasted (inc-bsqm)"
    exit 1
fi
echo "PASS: the over-cap tome was wasted in play, CON unchanged"
exit 0
