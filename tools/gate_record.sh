#!/bin/bash
# Record what this build complains about, as the thing later builds are
# measured against.
#
# Usage: tools/gate_record.sh [keyscript] [sessions] [first-seed]
#        tools/gate_record.sh tools/keys/dive.keys 40 1
#
# It runs the seeds, reduces the session logs to a small set of numbers (see
# tools/gate_lib.sh for which, and why those), and writes them to
# tools/gates/<script>.baseline. That file is meant to be committed: it is the
# record of what the build did on the day somebody was satisfied with it.
#
# Record a baseline only from a build you believe in. A baseline taken from a
# broken build makes the gate defend the breakage.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
. "$ROOT/tools/gate_lib.sh"

KEYS="${1:-tools/keys/dive.keys}"
SESSIONS="${2:-40}"
FIRST="${3:-1}"

[ -f "$KEYS" ] || { echo "no such key script: $KEYS"; exit 2; }

# Every session plays with the pinned settings file rather than the live one,
# and its checksum goes into the baseline. See the note in tools/gate_lib.sh.
[ -f "$GATE_OPTIONS" ] || {
    echo "the pinned settings file is missing: $GATE_OPTIONS"
    echo "restore it from git -- it is committed so that a baseline and the"
    echo "runs measured against it share one set of options."
    exit 2
}
export INCURSION_OPTIONS="$GATE_OPTIONS"

NAME="$(basename "$KEYS" .keys)"
OUT="$ROOT/tools/gates/$NAME.baseline"
SOAK="$ROOT/logs/gate/record-$NAME-$$"

mkdir -p "$ROOT/tools/gates" "$(dirname "$SOAK")"

echo "recording a baseline from the build in this tree"
echo "  keys:     $KEYS"
echo "  seeds:    $FIRST..$((FIRST + SESSIONS - 1))"
echo "  options:  $GATE_OPTIONS"
echo "  into:     $OUT"
echo

SOAK_DIR="$SOAK" ./tools/soak.sh "$SESSIONS" "$FIRST" "$KEYS" > "$SOAK.log" 2>&1
tail -5 "$SOAK.log"

BODY="$(gate_collect "$SOAK")" || exit 2
PLAYED="$(printf '%s\n' "$BODY" | gate_field /dev/stdin played)"

# A baseline recorded from sessions that never entered a map says nothing, and
# it says nothing quietly: every later comparison against it passes. That is
# how 250 sessions which played nothing became the evidence for a fix on
# 2026-08-14. Refuse rather than write one.
if [ "$PLAYED" -lt $((SESSIONS * 3 / 4)) ]; then
    echo
    echo "REFUSED: only $PLAYED of $SESSIONS sessions reached a map."
    echo "A baseline drawn from sessions that never played would pass every"
    echo "later comparison without measuring anything. Check that Options.Dat"
    echo "in this tree is the one you meant to use, and that the key script"
    echo "still fits character generation. The run is kept in $SOAK."
    echo "Set GATE_ALLOW_VOID=1 to record it anyway."
    [ "${GATE_ALLOW_VOID:-0}" = "1" ] || exit 1
fi

{
    echo "# Incursion regression baseline -- see tools/gate_compare.sh."
    echo "# Recorded $(date '+%Y-%m-%d %H:%M') from $(git rev-parse --short HEAD 2>/dev/null || echo 'no git')."
    echo "# Metric: error volume and message-set membership. A message that is"
    echo "# not in this file is a regression; a message that has left it is a fix."
    printf 'keys\t%s\n' "$KEYS"
    printf 'first\t%s\n' "$FIRST"
    printf 'options\t%s\n' "$(gate_options_sum "$GATE_OPTIONS")"
    printf '%s\n' "$BODY"
} > "$OUT"

echo
echo "wrote $OUT"
grep -v '^#' "$OUT" | head -12
echo
echo "commit that file. The soak it came from is in $SOAK"
