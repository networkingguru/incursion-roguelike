#!/bin/bash
# Regression check for the Horn of Madness activation defect, inc-j4dy: its
# second component did not activate, so the promised stun never accompanied
# the Wisdom drain; inc-tek.8.8 also requires both halves to spare the blower.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "FAIL: build with BACKEND=posix ./build_macos.sh"; exit 1; }

OUT="$(INCURSION_OPTIONS=tools/gates/Options.Dat tools/headless.sh tools/keys/horn-madness.keys 1 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
if echo "$OUT" | grep -qE 'NO GAMEPLAY|the key script looked for something'; then
    echo "FAIL: the run did not complete its measurement"; echo "$OUT"; exit 1
fi

BEFORE="$RUN/logs/screens/0001-goblin-before.txt"
BLOWN="$RUN/logs/screens/0002-blown.txt"
AFTER="$RUN/logs/screens/0003-goblin-after-top.txt"
for f in "$BEFORE" "$BLOWN" "$AFTER"; do
    [ -f "$f" ] || { echo "FAIL: missing measurement screen $f"; exit 1; }
done

wisdom() { sed -n 's/^A_WIS  *\([0-9]*\).*/\1/p' "$1" | head -1; }
blower_wisdom() { sed 's/^.*|//' "$1" | sed -n 's/^WIS: *\([0-9]*\).*/\1/p' | head -1; }
GBEFORE="$(wisdom "$BEFORE")"; GAFTER="$(wisdom "$AFTER")"
BBEFORE="$(blower_wisdom "$BEFORE")"; BAFTER="$(blower_wisdom "$BLOWN")"
GSTUN=0; grep -q '^  STUNNED from ' "$AFTER" && GSTUN=1
BSTUN=0; sed 's/^.*|//' "$BLOWN" | grep -qi '^Stunned' && BSTUN=1

echo "Horn of Madness:"
echo "  goblin Wisdom: $GBEFORE -> $GAFTER; stunned: $GSTUN"
echo "  blower Wisdom: $BBEFORE -> $BAFTER; stunned: $BSTUN"
if [ "$GBEFORE" != 9 ] || [ "$GAFTER" != 8 ] || [ "$GSTUN" != 1 ]; then
    echo "FAIL: expected the bystander to take Wisdom drain and become stunned"; exit 1
fi
if [ "$BBEFORE" != 16 ] || [ "$BAFTER" != 16 ] || [ "$BSTUN" != 0 ]; then
    echo "FAIL: expected the blower to keep Wisdom 16 and avoid stun"; exit 1
fi
echo "PASS: Madness drains and stuns the bystander while sparing the blower"
