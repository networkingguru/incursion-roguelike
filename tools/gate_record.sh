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
# inc-nch.5: with SOAK_CHAR the key script starts in play (dive-depth-<d>-play.keys)
# but the committed baseline keeps the name dive-depth-<d>.baseline.
[ -n "${SOAK_CHAR:-}" ] && NAME="${NAME%-play}"
OUT="$ROOT/tools/gates/$NAME.baseline"
SOAK="$ROOT/logs/gate/record-$NAME-$$"

mkdir -p "$ROOT/tools/gates" "$(dirname "$SOAK")"

echo "recording a baseline from the build in this tree"
echo "  keys:     $KEYS"
echo "  seeds:    $FIRST..$((FIRST + SESSIONS - 1))"
echo "  options:  $GATE_OPTIONS"
echo "  into:     $OUT"
[ -n "${SOAK_CHAR:-}" ] && echo "  char:     $SOAK_CHAR"
echo

SOAK_DIR="$SOAK" SOAK_CHAR="${SOAK_CHAR:-}" ./tools/soak.sh "$SESSIONS" "$FIRST" "$KEYS" > "$SOAK.log" 2>&1
tail -5 "$SOAK.log"

BODY="$(gate_collect "$SOAK")" || exit 2
PLAYED="$(printf '%s\n' "$BODY" | gate_field /dev/stdin played)"
TMED="$(printf '%s\n' "$BODY" | gate_field /dev/stdin turns_median)"
[ -n "$TMED" ] || { echo "REFUSED: no session carries a turn stamp; cannot record turns_median."; exit 2; }

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

# inc-nch.5: when a baseline is about to be replaced, say in the new header how
# the new run differs per seed. Comment lines start with "#", and gate_field
# matches a first field exactly, so none of them reads as a field.
gate_old_new_comment() { # <old baseline> <new body file>
    local old="$1" new="$2" f
    echo "# Replaces a baseline recorded with keys $(gate_field "$old" keys), char $(gate_field "$old" char | grep . || echo chargen.keys)."
    for f in played died lines findings turns_median; do
        echo "# summary $f: old $(gate_field "$old" $f | grep . || echo absent) new $(gate_field "$new" $f | grep . || echo absent)"
    done
    awk -F'\t' '
        FNR==NR { if ($1=="turns_seed") ot[$2]=$3; if ($1=="prompt_stop_seed") op[$2]=$3; if ($1=="turns_seed" || $1=="prompt_stop_seed") seen[$2]=1; next }
        { if ($1=="turns_seed") nt[$2]=$3; if ($1=="prompt_stop_seed") np[$2]=$3; if ($1=="turns_seed" || $1=="prompt_stop_seed") seen[$2]=1 }
        END {
            for (s in seen) {
                o = (s in ot) ? ot[s] : "absent"; n = (s in nt) ? nt[s] : "absent"
                po = (s in op) ? op[s] : "none"; pn = (s in np) ? np[s] : "none"
                printf "# %s: turns old %s new %s; prompt_stop old [%s] new [%s]\n", s, o, n, po, pn
            }
        }' "$old" "$new" | sort -t- -k2,2n
}

OLDCOPY=""
if [ -f "$OUT" ]; then
    OLDCOPY="$(mktemp "${TMPDIR:-/tmp}/gate-old.XXXXXX")"
    cp -f "$OUT" "$OLDCOPY"
    printf '%s\n' "$BODY" > "$OLDCOPY.new"
fi

{
    echo "# Incursion regression baseline -- see tools/gate_compare.sh."
    echo "# Recorded $(date '+%Y-%m-%d %H:%M') from $(git rev-parse --short HEAD 2>/dev/null || echo 'no git')."
    echo "# Metric: error volume and message-set membership. A message that is"
    echo "# not in this file is a regression; a message that has left it is a fix."
    if [ -n "$OLDCOPY" ]; then gate_old_new_comment "$OLDCOPY" "$OLDCOPY.new"; fi
    printf 'keys\t%s\n' "$KEYS"
    [ -n "${SOAK_CHAR:-}" ] && printf 'char\t%s\n' "$SOAK_CHAR"
    printf 'first\t%s\n' "$FIRST"
    printf 'options\t%s\n' "$(gate_options_sum "$GATE_OPTIONS")"
    printf '%s\n' "$BODY"
} > "$OUT"

[ -n "$OLDCOPY" ] && rm -f "$OLDCOPY" "$OLDCOPY.new"
echo
echo "wrote $OUT"
grep -v '^#' "$OUT" | head -12
echo
echo "commit that file. The soak it came from is in $SOAK"
