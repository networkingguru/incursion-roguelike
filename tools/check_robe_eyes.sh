#!/bin/bash
# Regression check for the Robe of Eyes' infravision, bead inc-tek.8.8, finding
# PA-08-F12.
#
# The robe's own page promises that it "grants the wearer 60 feet of Infravison"
# (lib/m_items.irh, entity AI_WONDER Effect "Robe of Eyes"). The entity granted
# Spot +5, Search +5, See Invisible, Improved Initiative and a gaze-attack
# handler, and no infravision at all, so the sentence was false for every wearer.
#
# The oracle is the character dump written by [W]rite Dump, because its
# "Special Abilities" block prints "Infravision (%d ft)" from src/Sheet.cpp:538
# and that number is Creature::AbilityLevel(CA_INFRAVISION) * 10 -- the very
# function the missing grant feeds. The run dumps the sheet three times: before
# the robe exists, with it worn, and after it comes off.
#
# The character is an orc, who owns 60 feet already, so the three readings must
# be 60, 120, 60. A reading of 60 in the middle is the defect.
#
# Usage: tools/check_robe_eyes.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/robe-eyes.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"

# A session that measured nothing must never read as a pass -- that mistake is
# inc-loa.3.
if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing"
    exit 1
fi

for f in before worn off; do
    if [ ! -f "$RUN/logs/$f.txt" ]; then
        echo "FAIL: the $f dump was never written to $RUN/logs/$f.txt"
        exit 1
    fi
done

# Read one number out of the Special Abilities block of one dump. The block is
# bounded by its own heading and the blank line before "Feats:"; the inventory
# further down names potions and must not be searched.
infra() {
    sed -n '/^Special Abilities:$/,/^$/p' "$RUN/logs/$1.txt" |
        sed -n 's/^  Infravision (\([0-9]*\) ft)$/\1/p'
}

fail=0

# Guard 1. The character must be the orc the arithmetic assumes. If chargen.keys
# rots and builds a human, every number below moves and the assertion would
# pass or fail for the wrong reason.
if ! grep -q "^Race   Orc$" "$RUN/logs/before.txt"; then
    echo "FAIL: the character is not an orc, so the key script has rotted."
    grep -m1 "^Race " "$RUN/logs/before.txt"
    exit 1
fi

# Guard 2. The robe must actually be in the Clothing slot for the middle
# reading. The script picks it off a cursor list with no menu letters, so this
# reads the name back rather than trusting the walk.
WORNSCREEN="$(ls "$RUN"/logs/screens/*robe-worn.txt 2>/dev/null | head -1)"
if [ -z "$WORNSCREEN" ] || ! grep -q "Clothing *:Robe of Eyes" "$WORNSCREEN"; then
    echo "FAIL: the Robe of Eyes never reached the Clothing slot."
    [ -n "$WORNSCREEN" ] && grep -m1 "Clothing" "$WORNSCREEN"
    exit 1
fi

# Guard 3. The robe's OTHER grants must be live in the middle dump. See
# Invisible is one of them, and it appears in Special Abilities only while the
# robe is worn. Without this, a robe whose whole effect failed to apply would
# look the same as one missing a single grant.
if grep -q "^  See Invisibility$" <(sed -n '/^Special Abilities:$/,/^$/p' "$RUN/logs/before.txt"); then
    echo "FAIL: the character had See Invisibility before the robe existed"
    fail=1
fi
if ! grep -q "^  See Invisibility$" <(sed -n '/^Special Abilities:$/,/^$/p' "$RUN/logs/worn.txt"); then
    echo "FAIL: the worn robe granted no See Invisibility, so nothing applied"
    fail=1
fi

# The assertion. Three readings, in feet.
BEFORE="$(infra before)"
WORN="$(infra worn)"
OFF="$(infra off)"

check() {
    if [ "$2" = "$3" ]; then
        echo "  ok: $1 infravision $2 ft"
    else
        echo "FAIL: $1 infravision is ${2:-absent} ft, expected $3 ft"
        fail=1
    fi
}

check "without the robe" "$BEFORE" 60
check "with the robe worn" "$WORN" 120
check "after removing it" "$OFF" 60

if [ "$fail" = 0 ]; then
    echo "PASS: the Robe of Eyes adds the 60 ft of infravision its page promises"
    exit 0
fi
exit 1
