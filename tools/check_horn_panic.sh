#!/bin/bash
# Regression check for the Horn of Panic activation defect, inc-j4dy: the horn
# had no activation flag, so its promised fear effect could never be blown.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "FAIL: build with BACKEND=posix ./build_macos.sh"; exit 1; }

OUT="$(INCURSION_OPTIONS=tools/gates/Options.Dat tools/headless.sh tools/keys/horn-panic.keys 4 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
if echo "$OUT" | grep -qE 'NO GAMEPLAY|the key script looked for something'; then
    echo "FAIL: the run did not complete its measurement"; echo "$OUT"; exit 1
fi

BLOWN="$RUN/logs/screens/0001-blown.txt"
GOBLIN="$RUN/logs/screens/0002-goblin-after-stati.txt"
for f in "$BLOWN" "$GOBLIN"; do
    [ -f "$f" ] || { echo "FAIL: missing measurement screen $f"; exit 1; }
done

FAILED_SAVE=0; grep -q 'Will Save:.*\[failure\]' "$BLOWN" && FAILED_SAVE=1
GAFRAID=0; grep -q '^  AFRAID from ' "$GOBLIN" && GAFRAID=1
BAFRAID=0; sed 's/^.*|//' "$BLOWN" | grep -qi '^Afraid' && BAFRAID=1
echo "Horn of Panic:"
echo "  goblin failed save: $FAILED_SAVE; afraid: $GAFRAID"
echo "  blower afraid: $BAFRAID"
if [ "$FAILED_SAVE" != 1 ] || [ "$GAFRAID" != 1 ]; then
    echo "FAIL: expected the bystander to fail its Will save and become afraid"; exit 1
fi
if [ "$BAFRAID" != 0 ]; then
    echo "FAIL: expected caster immunity to spare the blower"; exit 1
fi
echo "PASS: Panic frightens the failed-save bystander and spares the blower"
