#!/bin/bash
# gate: live
# inc-l8ws: Divine Sacrifice follows its source book, lasts 1 round per
# caster level, and its metamagic survives storage.
#
# THE SPELL. Effect "Divine Sacrifice" (lib/pspells.irh) is granted by the
# Good domain. The settled design: a cast-time menu of 1 to 5 dice (2 to 10
# HP) that does NOT depend on class level; nothing paid at cast; the chosen
# HP paid at the moment the caster makes an attack, at most once per game
# round; the payment skipped when it would bring the caster to 0 HP or
# below; the next successful attack deals +1d6 per 2 HP paid; a paid bonus
# that missed waits for the next hit and no more is paid until it lands; the
# buff lasts 1 round per caster level; and the spell can be ended from the
# cancel menu.
#
# WHAT IS DRIVEN. tools/keys/divine-sacrifice-after.keys (seeds 1-5) casts
# it with five dice, attacks a frozen froghemoth, takes a round with no
# attack, checks the cancel menu lists it and dropping it ends it, then
# casts it three more times (clearing and re-summoning the target between
# castings, so recasting cannot provoke an attack of opportunity) to drain
# the caster past the 10 HP sacrifice threshold, and finally checks the
# cancel menu no longer lists it once its duration has run out. See that
# key script's header for the measured HP trajectory and why four castings
# are needed.
#
# THE ORACLE IS THE SCREEN. Every @dump is a full screen: the five-choice
# menu ("[12345]"), the message log ("Damage: ... +N DSac ..."), the HUD
# line ("HP:x/y"), and the cancel menu ("[a] Drop Divine Sacrifice" or "You
# have nothing active to cancel."). The check reads the HP series across the
# attack dumps and the DSac tag per attack.
#
# MUTATION-TESTED. Each of the four mutations below was applied one at a
# time to a rebuilt lib/pspells.irh; each made this check FAIL on an
# assertion below (not a harness exit), confirming the assertion actually
# exercises the guard it names. Restored and rebuilt after each.
#   M1 (nd)d6 -> (nd)d10            : check 6 (DSac bonus bounds), fails --
#                                      seed 1 saw a 34 DSac bonus (fix caps
#                                      at 30 = 5 dice * 6).
#   M2 remove `cHP - chosen <= 0`   : check 3 (every HP step is a full
#                                      payment or a skip), fails -- seed 1
#                                      paid into a floor-clamped HP, an 8 HP
#                                      step instead of 10 or 0.
#   M3 remove the once-per-round    : check 3 (not every attack pays),
#      guard                          fails -- all 12 attacks in castings
#                                      2-4 paid.
#   M4 remove the waiting-bonus     : check 6 (DSac bonus bounds), fails --
#      guard (`if (nd <= 0) return`   a "+0 DSac" tag appeared on a hit with
#      in META(PRE(EV_HIT)))          nothing banked (0 is below 5d6's
#                                      minimum of 5).
#
# Proved RED against the pre-fix lib/pspells.irh too (old spell: level-sized
# menu, 1d10, HP paid at cast, no cancel flag, no once-per-round gate).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OPTIONS=tools/fixtures/options-2026-08-22.dat
KEYS=tools/keys/divine-sacrifice-after.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

fail() { echo "FAIL: $*"; exit 1; }

# hp_of <screen-file> -> the current HP from the HUD line, or empty.
hp_of() {
    grep -hoE '^HP:[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+' || true
}
# dmgline_of <screen-file> -> the top "Damage:" message line, or empty. This
# line only changes when a NEW hit resolves; a miss leaves the previous
# hit's line showing, so two dumps with the identical line are the same
# on-screen event, not two.
dmgline_of() {
    grep -h '^Damage:' "$1" 2>/dev/null | tail -1
}

for SEED in 1 2 3 4 5; do
    RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-ds-check-$SEED"
    INCURSION_OPTIONS="$OPTIONS" INCURSION_RUN_DIR="$RUN_DIR" \
        tools/headless.sh "$KEYS" "$SEED" >/dev/null 2>&1
    RUN_STATUS=$?
    SCR="$RUN_DIR/logs/screens"

    [ "$RUN_STATUS" -eq 0 ] || fail "seed $SEED: headless exited $RUN_STATUS (see $RUN_DIR)"

    menu="$SCR"/*-menu.txt
    cast="$SCR"/*-cast.txt
    summon="$SCR"/*-c1-summoned.txt
    xactive="$SCR"/*-c1-xmenu-active.txt
    cancmsg="$SCR"/*-c1-cancel-messages.txt
    xexpired="$SCR"/*-c4-xmenu-expired.txt

    # 1. The dice menu offers all five choices, independent of class level.
    v="$(grep -h 'How many extra dice' $menu 2>/dev/null)"
    grep -q '\[12345\]' <<< "$v" || fail "seed $SEED: cast menu is not five choices: '$v'"
    grep -q '\[1\]\s*$' <<< "$v" && fail "seed $SEED: cast menu still level-sized (one choice)"

    # 2. Nothing is paid at cast time: the cast screen and the summoned
    #    screen carry the same HP.
    CHP="$(hp_of $cast)"
    SHP="$(hp_of $summon)"
    [ -n "$CHP" ] || fail "seed $SEED: no HP line on the cast screen"
    [ "$CHP" = "$SHP" ] || fail "seed $SEED: HP paid at cast: $SHP -> $CHP"

    # 3. Build the combined HP trajectory across castings 2-4 (12 attacks,
    #    no rests): a payment is a -10 HP step, a skip is 0. Every attack
    #    that costs 30 Timeout falls in the same 60-tick round as the one
    #    before it unless a round boundary was crossed meanwhile, so at
    #    most every other attack should pay -- not all twelve. Checked
    #    before the cancel-menu assertions below: a guard failure that
    #    drives HP to 0 can disturb the later script steps as a side
    #    effect, and this is the direct diagnosis.
    declare -a HPS=()
    prev="$(hp_of $SCR/*-c1-rest.txt)"
    [ -n "$prev" ] || fail "seed $SEED: no HP line on the c1-rest screen"
    HPS+=("$prev")
    paid=0
    casting2_skips=0
    for f in c2-a1 c2-a2 c2-a3 c2-a4 c3-a1 c3-a2 c3-a3 c3-a4 c4-a1 c4-a2 c4-a3 c4-a4; do
        hp="$(hp_of $SCR/*-$f.txt)"
        [ -n "$hp" ] || fail "seed $SEED: no HP line on the $f screen"
        HPS+=("$hp")
        delta=$((hp - prev))
        [ "$delta" -eq 0 ] || [ "$delta" -eq -10 ] || \
            fail "seed $SEED: $f moved HP by $delta, neither a full payment (-10) nor a skip (0): $prev -> $hp"
        [ "$delta" -eq -10 ] && paid=$((paid+1))
        [ "$delta" -eq 0 ] && [[ "$f" == c2-* ]] && casting2_skips=$((casting2_skips+1))
        prev="$hp"
    done
    [ "$paid" -lt 12 ] || fail "seed $SEED: every one of the 12 attacks in castings 2-4 paid -- the once-per-round guard never fired"
    # Casting 2 starts at 48 HP, well clear of the 10 HP low-HP guard even
    # after two payments (48 -> 28), so a run of four back-to-back attacks
    # with no skip among them can only mean the once-per-round guard is
    # gone -- the low-HP guard cannot be masking it here.
    [ "$casting2_skips" -ge 1 ] || fail "seed $SEED: all four of casting 2's back-to-back attacks paid (48 -> 8) -- the once-per-round guard never fired"

    # 4. The sacrifice is skipped once it would bring the caster to 0 HP or
    #    below: HP must reach at or below the 10 HP sacrifice (the guard
    #    was actually exercised) and never below 1 (the guard held).
    min_hp=""
    for hp in "${HPS[@]}"; do
        if [ -z "$min_hp" ] || [ "$hp" -lt "$min_hp" ]; then min_hp="$hp"; fi
    done
    [ "$min_hp" -le 10 ] || fail "seed $SEED: HP never fell to the 10 HP sacrifice threshold (min $min_hp)"
    [ "$min_hp" -ge 1 ] || fail "seed $SEED: HP reached $min_hp -- the low-HP guard did not hold"

    # 5. The cancel menu lists the buff while it is active, and dropping it
    #    reports so. Once expired, the menu no longer lists it.
    grep -q 'Drop Divine Sacrifice' $xactive || fail "seed $SEED: no 'Drop Divine Sacrifice' while the buff was active"
    grep -q 'Dropping Divine Sacrifice\.' $cancmsg || fail "seed $SEED: cancel never reported 'Dropping Divine Sacrifice.'"
    grep -q 'nothing active to cancel' $xexpired || fail "seed $SEED: the X menu still lists something after the buff's full duration (caster level 3 rounds) should have elapsed"
    grep -q 'Drop Divine Sacrifice' $xexpired && fail "seed $SEED: 'Drop Divine Sacrifice' still listed after the buff should have expired"

    # 6. Walk every attack dump in order (c1-a1, then castings 2-4),
    #    de-duplicating a stale repeated Damage line (a miss leaves the
    #    prior hit's line on screen). Each fresh DSac bonus must be within
    #    5d6's bounds (5 dice, chosen = 10 HP, chosen/2 = 5), and the number
    #    of fresh DSac events must not exceed the number of payments (each
    #    payment can be consumed by at most one hit).
    dsac_events=0
    prevline=""
    for f in c1-a1 c2-a1 c2-a2 c2-a3 c2-a4 c3-a1 c3-a2 c3-a3 c3-a4 c4-a1 c4-a2 c4-a3 c4-a4; do
        line="$(dmgline_of $SCR/*-$f.txt)"
        if [ -n "$line" ] && [ "$line" != "$prevline" ] && grep -q 'DSac' <<< "$line"; then
            dsac_events=$((dsac_events+1))
            val="$(grep -oE '\+[0-9]+ DSac' <<< "$line" | grep -oE '[0-9]+')"
            [ -n "$val" ] || fail "seed $SEED: DSac tag with no numeric bonus: '$line'"
            [ "$val" -ge 5 ] || fail "seed $SEED: DSac bonus $val is below 5d6's minimum of 5: '$line'"
            [ "$val" -le 30 ] || fail "seed $SEED: DSac bonus $val exceeds 5d6's maximum of 30 (wrong dice?): '$line'"
        fi
        [ -n "$line" ] && prevline="$line"
    done
    total_paid=$((1 + paid))   # c1-a1's own payment, plus castings 2-4's.
    [ "$dsac_events" -le "$total_paid" ] || \
        fail "seed $SEED: $dsac_events DSac bonuses seen but only $total_paid payments -- a bonus applied with nothing banked"

    echo "seed $SEED: PASS (menu [12345]; cast HP $CHP unchanged; $((total_paid)) payments, $((13-total_paid)) skips; drained to $min_hp and held; $dsac_events DSac bonus(es) in [5,30]; cancel while active, gone after expiry)"
    echo "           specimen: $SCR"
done

echo "PASS: Divine Sacrifice casts with five choices, pays per attack round, skips at 0 HP or below, waits a missed bonus, expires after its duration, and cancels."
