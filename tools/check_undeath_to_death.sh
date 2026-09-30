#!/bin/bash
# gate: live
# inc-kgzx phase 2b: does Undeath to Death spend its Hit Dice pool by the SRD
# rule -- a 4-square-radius burst at the aimed point, fewest Hit Dice first,
# a 9-HD cap, wasted remainder, and a Will save that does NOT refund the pool?
#
# THE SCENE, built by tools/keys/undeath-to-death-area.keys. An orc priest of
# Aiswin at character level 11 (caster level 11 through SP_INNATE) learns
# Undeath to Death and summons four undead down the Entry Chamber corridor:
#
#   D  (45,111)  a crawling claw, 1 HD -- beside the caster, 6 squares from
#                the aim point, OUTSIDE the burst. It must never be affected.
#   B  (48,111)  a crawling claw, 1 HD -- 3 squares from the aim point, the
#                outer edge of the burst. Inside.
#   T  (51,111)  a crawling claw, 1 HD -- THE AIMED TARGET and the centre.
#   K  (52,111)  a bodak, 9 HD -- inside the burst but at the cap, so it is
#                skipped without spending or wasting a single Hit Die.
#
# THE ORACLE is the game's own message log. The spell rolls one pool of
# (caster level)d4 = 11d4 >= 11 Hit Dice, enough for both 1-HD claws, so every
# eligible creature is affected. Each one rolls a Will save, printed as
# "<name>'s Will Save: ...", whether or not it is then destroyed. B and T are
# the only creatures in the burst that may be affected, so a correct cast prints
# EXACTLY TWO saves and at most two "returns to death!" lines, both for a
# crawling claw:
#
#   saves == 2            D is out of the area and K is over the cap, so neither
#                         ever rolls a save. A third save means one of them was
#                         wrongly drawn into the pool.
#   no bodak death line   K's 9 HD must leave it untouched.
#   <= 2 claw deaths      D is a claw too; a third claw death is D affected.
#   >= 1 claw death       on some seed across the ten, B (and T) must actually
#                         die, or the pool never reached the second creature.
#
# WHY A MISSING LINE IS A FAIL, NOT AN INCONCLUSIVE. The screen this reads is
# produced by the cast itself; if it is absent or holds no save at all, the run
# measured nothing and every assertion would pass vacuously. So a run that
# cannot produce the message screen, or shows zero saves, fails outright.
#
# PROVED RED against phase 2a (EF_DEATH removed, AR_BALL, per-creature hit-point
# test): only D -- the claw beside the caster, which the old ball stopped on --
# died; there was no save and no pool. Both the save count and the death count
# fail there.
#
# Usage: tools/check_undeath_to_death.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/undeath-to-death-area.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
# The scene's absolute map origin moves with the seed (the Entry Chamber lands
# elsewhere), so the aimed target is named RELATIVE to the caster: T is seven
# squares due east, and D/B/T/K sit at +1/+4/+7/+8 on the same row.
AIM_DX=7
AIM_DY=0

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

fail() { echo "FAIL: $*"; exit 1; }

TMP="$(mktemp -d -t undeath-check.XXXXXX)" || exit 2
trap "rm -rf '$TMP'" EXIT

PASS_SEEDS=""
B_DIED=0

for SEED in $(seq 1 10); do
    RUN="$TMP/seed-$SEED"
    OUT="$(INCURSION_TARGET_PROBE=1 INCURSION_OPTIONS="$OPTIONS" \
        INCURSION_RUN_DIR="$RUN" \
        tools/headless.sh "$KEYS" "$SEED" 2>&1)"
    STATUS=$?

    if grep -q "NO GAMEPLAY" <<< "$OUT"; then
        fail "seed $SEED never entered a map, so it measured nothing."
    fi
    if [ "$STATUS" -ne 0 ]; then
        echo "$OUT" | tail -20
        fail "seed $SEED: tools/headless.sh exited $STATUS."
    fi

    SCREENS="$RUN/logs/screens"
    MSG="$(ls "$SCREENS"/*-messages.txt 2>/dev/null | head -1)"
    [ -n "$MSG" ] || fail "seed $SEED: the cast left no *-messages.txt screen in $SCREENS."

    PROBE="$RUN/logs/targetprobe.log"
    [ -f "$PROBE" ] || fail "seed $SEED: no targetprobe.log, so the aim was never confirmed."

    PLAYER=$(grep -oE 'player=\( *[0-9]+, *[0-9]+\)' "$PROBE" | head -1 |
             grep -oE '[0-9]+, *[0-9]+' | tr -d ' ')
    [ -n "$PLAYER" ] || fail "seed $SEED: the probe never recorded the caster's square."
    PX="${PLAYER%,*}"; PY="${PLAYER#*,}"
    AIM_X=$((PX + AIM_DX)); AIM_Y=$((PY + AIM_DY))

    CHOSEN=$(grep -oE 'CHOSE \( *[0-9]+, *[0-9]+\)' "$PROBE" | tail -1 |
             grep -oE '[0-9]+, *[0-9]+' | tr -d ' ')
    [ -n "$CHOSEN" ] || fail "seed $SEED: the target cursor never chose a square."
    [ "$CHOSEN" = "$AIM_X,$AIM_Y" ] ||
        fail "seed $SEED: the burst was aimed at $CHOSEN, not the intended $AIM_X,$AIM_Y (caster $PX,$PY + $AIM_DX,$AIM_DY)."

    # The message box begins at its own header; the ticker above it repeats the
    # last few lines and must not be counted twice. Restrict to the box, drop
    # the sidebar, and collapse all whitespace so a wrapped save line still
    # matches.
    BOX="$(awk '/-- Messages --/{f=1;next} f' "$MSG" | cut -c1-64 |
           tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    [ -n "$BOX" ] || fail "seed $SEED: the messages screen held no message box."

    SAVES=$(grep -o 'willsave:' <<< "$BOX" | wc -l | tr -d ' ')
    CLAW_DEATHS=$(grep -o 'thecrawlingclawreturnstodeath' <<< "$BOX" | wc -l | tr -d ' ')
    BODAK_DEATHS=$(grep -o 'thebodakreturnstodeath' <<< "$BOX" | wc -l | tr -d ' ')

    [ "$SAVES" -ge 1 ] ||
        fail "seed $SEED: no Will save line at all. The spell never reached its save step; specimen $MSG."
    [ "$SAVES" -eq 2 ] ||
        fail "seed $SEED: $SAVES Will saves printed, expected exactly 2 (B and T). D is outside the burst and K is at the 9-HD cap, so neither may roll one. specimen $MSG."
    [ "$BODAK_DEATHS" -eq 0 ] ||
        fail "seed $SEED: the 9-HD bodak was destroyed; the cap did not hold. specimen $MSG."
    [ "$CLAW_DEATHS" -le 2 ] ||
        fail "seed $SEED: $CLAW_DEATHS crawling claws died, but only B and T are in the burst. D (beside the caster) was caught too. specimen $MSG."

    [ "$CLAW_DEATHS" -eq 2 ] && B_DIED=1
    PASS_SEEDS="$PASS_SEEDS $SEED"
done

[ "$B_DIED" -eq 1 ] ||
    fail "on none of the ten seeds did both in-area claws die, so B (3 squares from the aim point) was never destroyed. The pool did not reach the second creature."

echo "PASS: Undeath to Death pools its Hit Dice by the SRD rule."
echo "      seeds 1-10: burst centred on the aimed target (caster + $AIM_DX east);"
echo "      exactly two Will saves per cast; no bodak of 9 Hit Dice touched; D"
echo "      beside the caster never affected; both in-area claws (T and B)"
echo "      destroyed on at least one seed."
exit 0
