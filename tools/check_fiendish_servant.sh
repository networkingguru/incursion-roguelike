#!/bin/bash
# Regression check for inc-1cq: the Blackguard's Fiendish Servant summons a
# creature when cast.
#
# WHY IT EXISTS. The class grants the ability as an innate spell
# (CA_INNATE_SPELL, lib/prestige.irh) but the effect it names carried
# EF_ACTIVATE, which marks segment 0 as activation-only. Magic::MagicEvent
# (src/Magic.cpp:701) skips any segment whose activation flag disagrees with how
# the effect was invoked, so a Spell-Manager cast (e.isActivation false) ran
# nothing and the game printed a generic no-op ("Nothing happens."). The effect
# reached no activate menu either, because CA_INNATE_SPELL grants no activation
# stati, so no character could ever use the servant. Dropping EF_ACTIVATE from
# the effect (lib/prestige.irh) lets the innate-spell cast reach it.
#
# HOW IT PROVES IT. tools/keys/prestige-blackguard5.keys builds a Human
# Warrior 6 / Blackguard 5, opens the Spell Manager, selects Fiendish Servant
# and presses ENTER. The 0002-servant.txt dump must announce the summoned
# creature and must NOT carry a no-op message. Measured red-before / green-after
# on 2026-09-04: the reverted module printed "Nothing happens." and summoned
# nothing (turn 198021, key 237), the fixed module printed "Your veteran true
# imp appears!" at the same point.
#
# The keys script sets no seed, so the dungeon layout varies run to run, but the
# scripted chargen makes the Blackguard 5 and the cast deterministic.
#
# Usage: tools/check_fiendish_servant.sh
# Ends:  0 pass, 1 fail, 2 the check could not be run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS="tools/keys/prestige-blackguard5.keys"
BIN="${INCURSION_BIN:-./incursion-headless}"

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: no key script at $KEYS"; exit 2; }

out="$(env INCURSION_BIN="$BIN" tools/headless.sh "$KEYS" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

if echo "$out" | grep -q "^ended: *ASSERT"; then
    echo "FAIL: the engine tripped an assertion during the run." >&2
    echo "$out" | grep -A3 "^ended:" >&2
    exit 1
fi
if ! echo "$out" | grep -q "^ended: *cleanly"; then
    echo "FAIL: the session did not end cleanly, so the servant was not cast as" >&2
    echo "      scripted. If the chargen questions moved, fix $KEYS." >&2
    echo "$out" | sed -n '/--- after the session ---/,$p' >&2
    exit 1
fi

dump="$run/logs/screens/0002-servant.txt"
[ -f "$dump" ] || { echo "INCONCLUSIVE: no servant dump at $dump" >&2; exit 2; }

# The assertion: the cast announced a summoned creature.
if ! grep -Eq "imp appears|quasit appears|call upon the Lower Planes" "$dump"; then
    echo "FAIL: casting Fiendish Servant summoned nothing. The dump does not"
    echo "      announce an imp or quasit. If EF_ACTIVATE is back on the effect"
    echo "      (lib/prestige.irh), Magic::MagicEvent (src/Magic.cpp:701) skips"
    echo "      the innate-spell cast. Dump: $dump"
    exit 1
fi
# And it did not fall through to a no-op message.
if grep -Eq "Nothing happens|no effect" "$dump"; then
    echo "FAIL: the cast printed a no-op message, so the summon segment ran but"
    echo "      then something aborted the effect. Dump: $dump"
    exit 1
fi

echo "PASS: the Blackguard's Fiendish Servant summons its creature when cast."
echo "      Dump: $dump"
exit 0
