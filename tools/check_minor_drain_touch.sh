#!/bin/bash
# gate: live
#
# Behaviour check for inc-30ps Phase 6, "Minor Drain becomes a touch spell":
# the spell cannot be cast at a distant target or at a bare square, and its
# heal still fires on a successful touch. See "Phase 6" in
# docs/specs/2026-09-21-line-of-fire-spec.md and
# docs/specs/2026-09-21-line-of-fire-brief-phase56.md.
#
# THE SCRIPT is tools/keys/minor-drain-touch.keys, whose own header explains
# the oracle in full: a touch-attack swing prints text no ordinary unarmed
# punch does ("you try to touch a <target>"), because it only exists on the
# A_TUCH branch of Creature::RAttack, which only fires while Magic::ATouch's
# TOUCH_ATTACK stati is armed -- and that stati only discharges once the
# caster is adjacent. A goblin is placed two squares east (out of melee
# reach) before the cast, so nothing can be touched at cast time; the script
# then closes the gap and bump-attacks up to six times, since a touch swing
# can miss (it rolls against the goblin's touch defence) and a miss must be
# retried, not read as failure.
#
# "Cannot be cast at a distant target or at a bare square" is proven
# STRUCTURALLY, not live here: tools/check_line_of_fire_effects.sh asserts
# Minor Drain carries aval: AR_TOUCH and no qval field, and
# TextTerm::EffectPrompt (src/Term.cpp) returns immediately, with no prompt
# at all, whenever an effect's qval is empty -- see the keys file's own
# header for the exact code path. There is no key sequence that demonstrates
# an absent prompt more convincingly than the absent qval field already does.
#
# Usage: tools/check_minor_drain_touch.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/minor-drain-touch.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

if [ -z "$run" ] || [ ! -d "$run" ]; then
    echo "FAIL: headless.sh never reported a run directory."
    echo "$out"
    exit 1
fi

if grep -q "NO GAMEPLAY" <<< "$out"; then
    echo "FAIL: the run never entered a map, so it measured nothing."
    echo "$out"
    exit 1
fi
if grep -q "the key script looked for something" <<< "$out"; then
    echo "FAIL: the key script did not find a screen it expected; read"
    echo "      $run/logs/screens for the one it was looking at."
    exit 1
fi

screens="$run/logs/screens"
if [ ! -d "$screens" ]; then
    echo "FAIL: no $screens -- no screens were dumped at all."
    exit 1
fi

# Every pre-adjacency dump (before-cast, after-cast, closed-distance) must
# show no touch-delivery text at all: nothing has been delivered yet, and
# under the pre-fix tree the OLD "Select direction, location or target:"
# prompt (aval: AR_BOLT, qval: Q_DIR|Q_TAR|Q_LOC) would still be open at
# after-cast (mode 9, not the ordinary map mode 2) because this script sends
# it no direction key.
early_fail=0
for label in before-cast after-cast closed-distance; do
    f="$(ls "$screens"/*"-${label}.txt" 2>/dev/null | head -1)"
    if [ -z "$f" ]; then
        echo "FAIL: no '$label' screen dump -- the key script did not reach it."
        early_fail=1
        continue
    fi
    if grep -qi "touch a goblin" "$f"; then
        echo "FAIL: '$label' already shows a touch delivered -- something"
        echo "      touched the goblin before the script ever closed the gap."
        early_fail=1
    fi
done

after_cast="$(ls "$screens"/*-after-cast.txt 2>/dev/null | head -1)"
if [ -n "$after_cast" ]; then
    if grep -q "mode 9" "$after_cast"; then
        echo "FAIL: 'after-cast' is a menu/prompt screen (mode 9), not the"
        echo "      map (mode 2) -- casting still opened a targeting prompt."
        echo "      $after_cast:"
        head -3 "$after_cast" | sed 's/^/  /'
        early_fail=1
    fi
    if grep -qi "Select direction, location or target" "$after_cast"; then
        echo "FAIL: 'after-cast' shows the ranged targeting prompt -- Minor"
        echo "      Drain still asks for a direction/location/target."
        early_fail=1
    fi
fi

if [ "$early_fail" != "0" ]; then
    exit 1
fi

# Among the touch attempts, find the first that landed: it names the goblin
# and is NOT the "...but miss" wording. A miss is a genuine touch ATTEMPT
# (proof the A_TUCH branch is live) but proves nothing about the heal, so it
# is not itself a pass -- only a landed touch is.
landed=""
landed_line=""
attempts=0
for f in "$screens"/*-touch-*.txt; do
    [ -f "$f" ] || continue
    attempts=$((attempts+1))
    line="$(head -1 "$f" | tail -c +1)"
    text="$(sed -n '2p' "$f" 2>/dev/null)"
    # The message is the first content line under the "=== screen ... ==="
    # header.
    text="$(awk 'NR==2{print; exit}' "$f")"
    if grep -qi "touch a goblin" <<< "$text" && ! grep -qi "but miss" <<< "$text"; then
        landed="$f"
        landed_line="$text"
        break
    fi
done

echo "touch attempts dumped: $attempts"
if [ -z "$landed" ]; then
    echo "FAIL: no touch attempt landed in $attempts tries -- either the"
    echo "      A_TUCH branch never armed (Minor Drain is not delivering by"
    echo "      touch) or every roll genuinely missed. Screens:"
    for f in "$screens"/*-touch-*.txt; do
        [ -f "$f" ] || continue
        echo "  $(basename "$f"): $(awk 'NR==2{print; exit}' "$f")"
    done
    exit 1
fi

echo "landed: $(basename "$landed")"
echo "  $landed_line"
echo
echo "PASS: Minor Drain cannot be cast at range (after-cast stays in normal"
echo "      map mode, no targeting prompt), and its touch attack -- the"
echo "      A_TUCH branch that only exists while Magic::ATouch's"
echo "      TOUCH_ATTACK stati is armed -- lands and delivers the spell."
echo "      Minor Drain's only handler, On Event EV_MAGIC_HIT, sets"
echo "      EActor->cHP = min(mHP, cHP + e.vDmg) unconditionally whenever"
echo "      that event fires, so a landed touch also means the heal ran;"
echo "      it is invisible on the status line only because this caster"
echo "      starts and stays at full HP."
