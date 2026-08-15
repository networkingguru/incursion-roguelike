#!/bin/bash
# Run the recorded seeds again on the build in this tree, and say what changed
# against the baseline.
#
# Usage: tools/gate_compare.sh                       (every recorded baseline)
#        tools/gate_compare.sh tools/gates/dive.baseline
#
# Ends: 0 nothing got worse, 1 a regression, 2 the comparison could not be run.
#
# WHAT COUNTS AS A REGRESSION, and what does not:
#
#   A message the baseline has never seen, in       regression. This is the
#   several sessions at once                        one that matters. The
#                                                   healthy shape is for the
#                                                   new message set to be a
#                                                   SUBSET of the recorded one.
#   The same, in one or two sessions only           printed, not failed. See
#                                                   the note on noise below.
#
# THE ENGINE IS NOT FULLY DETERMINISTIC, and the gate has to live with it.
# Measured 2026-08-15 on eleven runs of one seed and four runs of an eight-seed
# set, same binary, same key script, same seed:
#
#   seed 3 logged "ASSERT failed: 'cHP == mHP + Attr[A_THP]'" in 2 runs of 11.
#   seed 8 produced 0 map-audit findings in one soak and 148 in another.
#
# So a message can appear or vanish with no change to the code at all. Failing
# on a single unseen message would make this gate cry wolf, and a gate that
# cries wolf gets switched off. What the noise cannot do is fire in many
# sessions at once: every observed flake touched ONE session. A real regression
# of the kind this exists to catch does the opposite -- the Target zero-init
# defect logged 89,545 assertions across almost every session. The threshold
# below sits in the gap between those two.
#   Fewer sessions reached a map                    regression. A change that
#                                                   breaks the run drives every
#                                                   other number down, and
#                                                   would otherwise read as an
#                                                   improvement.
#   More sessions ended in Fatal() or the watchdog  regression.
#   A known message firing much more often          reported, not failed. A fix
#                                                   that keeps the character
#                                                   alive longer produces more
#                                                   turns and therefore more of
#                                                   everything.
#   A message gone, or firing less                  reported as an improvement.
#
# The gate detects only what reaches a log. A defect that silently does the
# wrong thing and says nothing passes clean. It never replaces a play-test.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
. "$ROOT/tools/gate_lib.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-gate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --from reads a soak directory that already exists instead of running the
# seeds again. It is how tools/check_gate.sh feeds this script known-bad input
# in a second rather than in three minutes, and it also lets a kept run be
# re-read against a different baseline.
FROM=""
if [ "${1:-}" = "--from" ]; then
    FROM="${2:-}"
    [ -d "$FROM" ] || { echo "no such soak directory: $FROM"; exit 2; }
    shift 2
fi

BASELINES=("$@")
if [ "${#BASELINES[@]}" -eq 0 ]; then
    shopt -s nullglob
    BASELINES=("$ROOT"/tools/gates/*.baseline)
    shopt -u nullglob
fi
if [ "${#BASELINES[@]}" -eq 0 ]; then
    echo "no baseline to compare against. Record one first:"
    echo "  tools/gate_record.sh tools/keys/dive.keys 40 1"
    exit 2
fi

VERDICT=0

for BASE in "${BASELINES[@]}"; do
    [ -f "$BASE" ] || { echo "no such baseline: $BASE"; exit 2; }

    KEYS="$(gate_field "$BASE" keys)"
    FIRST="$(gate_field "$BASE" first)"
    SESSIONS="$(gate_field "$BASE" sessions)"
    [ -f "$KEYS" ] || { echo "$BASE names a key script that is gone: $KEYS"; exit 2; }

    NAME="$(basename "$BASE" .baseline)"
    SOAK="$ROOT/logs/gate/compare-$NAME-$$"
    mkdir -p "$(dirname "$SOAK")"

    echo "=== $NAME: $SESSIONS sessions of $KEYS, seeds $FIRST..$((FIRST + SESSIONS - 1))"
    echo "    baseline: $BASE"
    if [ -n "$FROM" ]; then
        SOAK="$FROM"
        echo "    reading the run in $SOAK instead of playing the seeds again"
    else
        SOAK_DIR="$SOAK" ./tools/soak.sh "$SESSIONS" "$FIRST" "$KEYS" > "$SOAK.log" 2>&1
    fi
    gate_collect "$SOAK" > "$WORK/new" || exit 2

    B_PLAYED="$(gate_field "$BASE" played)"
    N_PLAYED="$(gate_field "$WORK/new" played)"
    B_LINES="$(gate_field "$BASE" lines)"
    N_LINES="$(gate_field "$WORK/new" lines)"
    B_FIND="$(gate_field "$BASE" findings)"
    N_FIND="$(gate_field "$WORK/new" findings)"

    echo "    reached a map:   $N_PLAYED of $SESSIONS   (baseline $B_PLAYED)"
    echo "    error lines:     $N_LINES   (baseline $B_LINES)"
    echo "    audit findings:  $N_FIND   (baseline $B_FIND)"
    echo

    if [ "$N_PLAYED" -lt "$B_PLAYED" ]; then
        echo "  REGRESSION: $((B_PLAYED - N_PLAYED)) sessions that used to reach a map no longer do."
        echo "  Every other number below is drawn from fewer sessions and cannot be"
        echo "  read as an improvement. Check the run in $SOAK."
        echo
        VERDICT=1
    fi

    # A build that dies before it can log looks quiet. Read the exit tally too.
    for CODE in 1 4; do
        B_N="$(awk -F'\t' -v c="$CODE" '$1=="exits" { for (i=2;i<=NF;i++) { split($i,p,"="); if (p[1]==c) print p[2] } }' "$BASE")"
        N_N="$(awk -F'\t' -v c="$CODE" '$1=="exits" { for (i=2;i<=NF;i++) { split($i,p,"="); if (p[1]==c) print p[2] } }' "$WORK/new")"
        B_N="${B_N:-0}"; N_N="${N_N:-0}"
        [ "$N_N" -le "$B_N" ] && continue
        case "$CODE" in
            1) WHAT="ended in Fatal()" ;;
            4) WHAT="hit the watchdog -- the game stopped asking for keystrokes" ;;
        esac
        echo "  REGRESSION: $N_N sessions $WHAT, baseline had $B_N."
        echo
        VERDICT=1
    done

    awk -F'\t' '
        FNR==NR { if ($1=="message") { bs[$4]=$2; bc[$4]=$3 } ; next }
        $1=="message" { ns[$4]=$2; nc[$4]=$3 }
        END {
            for (m in nc) {
                if (!(m in bc)) { printf "NEW\t%s\t%s\t%s\n", ns[m], nc[m], m; continue }
                if (nc[m] > bc[m]) printf "UP\t%s\t%s\t%s\n", bc[m], nc[m], m
                else if (nc[m] < bc[m]) printf "DOWN\t%s\t%s\t%s\n", bc[m], nc[m], m
            }
            for (m in bc) if (!(m in nc)) printf "GONE\t%s\t%s\t%s\n", bs[m], bc[m], m
        }' "$BASE" "$WORK/new" | sort > "$WORK/delta"

    # How many sessions an unseen message must reach before it counts. Below
    # this it is indistinguishable from the engine's own nondeterminism, which
    # has never been observed to touch more than one session at a time.
    THRESHOLD=$((SESSIONS / 10))
    [ "$THRESHOLD" -lt 2 ] && THRESHOLD=2

    if awk -F'\t' -v t="$THRESHOLD" '$1=="NEW" && $2>=t' "$WORK/delta" | grep -q .; then
        echo "  REGRESSION: messages this baseline has never seen, in $THRESHOLD or more sessions --"
        awk -F'\t' -v t="$THRESHOLD" '$1=="NEW" && $2>=t { printf "    %6s times in %s session(s): %s\n", $3, $2, $4 }' "$WORK/delta"
        echo
        VERDICT=1
    fi

    if awk -F'\t' -v t="$THRESHOLD" '$1=="NEW" && $2<t' "$WORK/delta" | grep -q .; then
        echo "  not in the baseline, but in fewer than $THRESHOLD sessions (NOT failed) --"
        awk -F'\t' -v t="$THRESHOLD" '$1=="NEW" && $2<t { printf "    %6s times in %s session(s): %s\n", $3, $2, $4 }' "$WORK/delta"
        echo "    The engine produces messages like this with no code change at"
        echo "    all. Read them before trusting the pass; if one is real, it"
        echo "    will hold still when you run the gate again."
        echo
    fi

    # More of a message that was already there. Worth printing, not worth
    # failing on: a fix that keeps the character alive longer produces more
    # turns, and therefore more of everything the turns generate.
    if awk -F'\t' '$1=="UP"' "$WORK/delta" | grep -q .; then
        echo "  louder than the baseline (not a failure) --"
        awk -F'\t' '$1=="UP" { printf "    %s -> %s: %s\n", $2, $3, $4 }' "$WORK/delta"
        echo
    fi

    if awk -F'\t' '$1=="GONE" || $1=="DOWN"' "$WORK/delta" | grep -q .; then
        echo "  quieter than the baseline --"
        awk -F'\t' '$1=="GONE" { printf "    %s -> gone: %s\n", $3, $4 }
                    $1=="DOWN" { printf "    %s -> %s: %s\n", $2, $3, $4 }' "$WORK/delta"
        echo
    fi

    if [ ! -s "$WORK/delta" ]; then
        echo "  no change: the same messages, the same number of times."
        echo
    fi
    echo "  run kept in $SOAK"
    echo
done

if [ "$VERDICT" -eq 0 ]; then
    echo "PASS: nothing got worse. Remember what this cannot see -- a defect"
    echo "      that logs nothing passes here. Play the game as well."
else
    echo "FAIL: see the regressions above. If the change is meant to produce a"
    echo "      new message, record a new baseline and say so in the commit."
fi
exit "$VERDICT"
