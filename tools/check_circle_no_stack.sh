#!/bin/bash
# Regression check for inc-fiiq: overlapping magic circles do not stack.
#
# A torch archon's circle carries two grants (lib/wspells.irh:3846-3851): a -3
# penalty against MA_EVIL and a +4 save bonus for MA_ALLIES.  Before the fix,
# a creature inside N circles held N rows and every reader summed them, so two
# archons inflicted -6 instead of -3.  Creature::CalcValues now skips the
# redundant rows, but it must NOT delete them: the leave path in inc-fiiq
# needs one row per granting field.
#
# The oracle is the "Hit:" line of the side panel with an evil player, which
# is the only place the summed value appears on screen.
#
# Usage: tools/check_circle_no_stack.sh (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

BIN="${INCURSION_BIN:-./incursion-headless}"
KEYS=tools/keys/circle-stack-adjust.keys
SEED=20260905

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_BIN="$BIN" INCURSION_OPTIONS=tools/gates/Options.Dat \
    tools/headless.sh "$KEYS" "$SEED" 2>&1)"
status=$?
run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
if [ "$status" -ne 0 ]; then
    echo "INCONCLUSIVE: fixture exited $status. Run dir: ${run:-unknown}"
    printf '%s\n' "$out"
    exit 2
fi

hit_of() {
    local f
    f="$(find "$run/logs/screens" -name "*-$1.txt" -print | head -1)"
    [ -n "$f" ] || return 1
    grep -o 'Hit:[^|]*' "$f" | head -1 | tr -d ' '
}

base="$(hit_of hit-base)" || { echo "INCONCLUSIVE: no baseline dump. Run dir: $run"; exit 2; }
one="$(hit_of hit-one)"   || { echo "INCONCLUSIVE: no one-circle dump. Run dir: $run"; exit 2; }
two="$(hit_of hit-two)"   || { echo "INCONCLUSIVE: no two-circle dump. Run dir: $run"; exit 2; }

stati="$(find "$run/logs/screens" -name '*-player-stati.txt' -print | head -1)"
[ -n "$stati" ] || { echo "INCONCLUSIVE: no player status dump. Run dir: $run"; exit 2; }
rows="$(cut -c1-64 "$stati" | grep -c 'eID:Magic Circle vs\.')"

echo "hit: base=$base one=$one two=$two   circle-rows-held=$rows"

fail=0
if [ "$base" = "$one" ]; then
    echo "FAIL: one circle changed nothing; the fixture never applied a penalty."
    fail=1
fi
if [ "$one" != "$two" ]; then
    echo "FAIL: the second circle stacked. One circle gave $one, two gave $two."
    fail=1
fi
if [ "$rows" -ne 2 ]; then
    echo "FAIL: expected both circle rows to be held (got $rows)."
    echo "      Suppression must happen at read time, not by deleting a row;"
    echo "      the inc-fiiq leave path needs one row per granting field."
    fail=1
fi

[ "$fail" -eq 0 ] || { echo "      Run dir: $run"; exit 1; }
echo "PASS: a second overlapping circle adds nothing, and both rows survive."
