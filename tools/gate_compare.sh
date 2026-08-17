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
#   More sessions died, or got stuck at the         regression, and see below.
#   OPT_NODEATH death prompt, than the baseline
#   More sessions frozen at the threat-disengage     regression, and see below.
#   prompt (inc-loa.5) than the baseline
#   A known message firing much more often          reported, not failed. A fix
#                                                   that keeps the character
#                                                   alive longer produces more
#                                                   turns and therefore more of
#                                                   everything.
#   A message gone, or firing less                  reported as an improvement,
#                                                   with a caveat if any session
#                                                   in this run died or got
#                                                   stuck (see below).
#
# THE OPT_NODEATH DEATH PROMPT (inc-loa.3). The pinned settings ask "You
# die... Die? [yn]" instead of ending a session outright, and the key script
# answers it with whatever token comes next because it cannot see the screen.
# A session that dies for real, or gets stuck at an unanswered prompt for the
# rest of its key budget, generates no more real gameplay from that point --
# so it logs fewer errors and fewer audit findings than a live session, and
# used to read as "quieter than the baseline" with nothing to say otherwise.
# tools/gate_lib.sh counts both shapes as one 'died' tally; this script fails
# the comparison when that count rises, and warns instead of guessing when the
# baseline predates the count entirely. See tools/headless.sh's "death:" line
# for what a single session sees.
#
# THE THREAT-DISENGAGE PROMPT (inc-loa.5). "You are in a threatened area.
# Abort, Flee or Disengage?" (src/Move.cpp:841) has no OPT_ gate at all, and
# tools/keys/dive.keys has no 'a'/'f'/'d'/'?'/ESC in its vocabulary, so a
# session that hits it freezes for the rest of its key budget -- same disease
# as the death prompt above, one prompt over. tools/gate_lib.sh counts it as
# 'threat_frozen'; this script fails the comparison when that count rises,
# the same way it does for 'died'. See tools/headless.sh's "stuck-prompt:"
# line for what a single session sees.
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
        # Refuse rather than report. A comparison across two sets of settings
        # measures the settings as much as the build, and it reaches a verdict
        # anyway -- which is worse than reaching none. Exit 2 is "could not be
        # run", not "failed": nothing here says the build is bad.
        if ! gate_options_check "$BASE" "$GATE_OPTIONS"; then
            echo
            echo "REFUSED: the settings this run would use are not the settings"
            echo "         the baseline was recorded with."
            exit 2
        fi
        echo "    options:  $GATE_OPTIONS"
        SOAK_DIR="$SOAK" INCURSION_OPTIONS="$GATE_OPTIONS" \
            ./tools/soak.sh "$SESSIONS" "$FIRST" "$KEYS" > "$SOAK.log" 2>&1
    fi
    gate_collect "$SOAK" > "$WORK/new" || exit 2

    B_PLAYED="$(gate_field "$BASE" played)"
    N_PLAYED="$(gate_field "$WORK/new" played)"
    B_LINES="$(gate_field "$BASE" lines)"
    N_LINES="$(gate_field "$WORK/new" lines)"
    B_FIND="$(gate_field "$BASE" findings)"
    N_FIND="$(gate_field "$WORK/new" findings)"
    B_DIED_RAW="$(gate_field "$BASE" died)"
    N_DIED="$(gate_field "$WORK/new" died)"
    N_DIED="${N_DIED:-0}"
    B_THREAT_RAW="$(gate_field "$BASE" threat_frozen)"
    N_THREAT="$(gate_field "$WORK/new" threat_frozen)"
    N_THREAT="${N_THREAT:-0}"

    echo "    reached a map:   $N_PLAYED of $SESSIONS   (baseline $B_PLAYED)"
    echo "    error lines:     $N_LINES   (baseline $B_LINES)"
    echo "    audit findings:  $N_FIND   (baseline $B_FIND)"
    if [ -z "$B_DIED_RAW" ]; then
        echo "    died or stuck:   $N_DIED of $SESSIONS   (baseline: not recorded)"
    else
        echo "    died or stuck:   $N_DIED of $SESSIONS   (baseline $B_DIED_RAW)"
    fi
    if [ -z "$B_THREAT_RAW" ]; then
        echo "    threat-frozen:   $N_THREAT of $SESSIONS   (baseline: not recorded)"
    else
        echo "    threat-frozen:   $N_THREAT of $SESSIONS   (baseline $B_THREAT_RAW)"
    fi
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

    # inc-loa.3: a session whose character died, or got stuck at the
    # OPT_NODEATH "You die... Die? [yn]" prompt, generates no more real
    # gameplay from that point on -- so it undercounts its own error and
    # audit-finding lines exactly the way a genuinely quieter build would.
    # Without this, MORE dead/stuck sessions than the baseline would read as
    # a plain improvement below (GONE/DOWN), which is the bug this exists to
    # close: a change that kills characters earlier must not look like a fix.
    if [ -z "$B_DIED_RAW" ]; then
        if [ "$N_DIED" -gt 0 ]; then
            echo "  NOTE: $N_DIED of $SESSIONS sessions died or got stuck at the death"
            echo "  prompt, and this baseline predates death-counting (inc-loa.3), so"
            echo "  there is nothing to compare that number against. Its lines and"
            echo "  findings figures may themselves be a mix of full sessions and"
            echo "  death-stumps in an unknown ratio. Re-record it to get a baseline"
            echo "  this comparison can actually reason about:"
            echo "    tools/gate_record.sh $KEYS $SESSIONS $FIRST"
            echo
        fi
    else
        B_DIED="${B_DIED_RAW:-0}"
        if [ "$N_DIED" -gt "$B_DIED" ]; then
            echo "  REGRESSION: $N_DIED sessions died or got stuck at the death prompt,"
            echo "  baseline had $B_DIED. Everything below is drawn from more stumps"
            echo "  than the baseline and a quieter reading is not an improvement."
            echo
            VERDICT=1
        fi
    fi

    # inc-loa.5: same rule, for the unguarded threat-disengage prompt. A
    # session frozen there generates no more real gameplay either, for the
    # same reason a dead/stuck session above does not.
    if [ -z "$B_THREAT_RAW" ]; then
        if [ "$N_THREAT" -gt 0 ]; then
            echo "  NOTE: $N_THREAT of $SESSIONS sessions froze at the threat-disengage"
            echo "  prompt (inc-loa.5), and this baseline predates that count, so there"
            echo "  is nothing to compare it against. Its lines and findings figures may"
            echo "  themselves be a mix of full sessions and threat-disengage stumps in"
            echo "  an unknown ratio. Re-record it to get a baseline this comparison can"
            echo "  actually reason about:"
            echo "    tools/gate_record.sh $KEYS $SESSIONS $FIRST"
            echo
        fi
    else
        B_THREAT="${B_THREAT_RAW:-0}"
        if [ "$N_THREAT" -gt "$B_THREAT" ]; then
            echo "  REGRESSION: $N_THREAT sessions froze at the threat-disengage prompt,"
            echo "  baseline had $B_THREAT. Everything below is drawn from more stumps"
            echo "  than the baseline and a quieter reading is not an improvement."
            echo
            VERDICT=1
        fi
    fi

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
        if [ "$N_DIED" -gt 0 ]; then
            echo "    NOTE: $N_DIED of $SESSIONS sessions in THIS run died or got stuck"
            echo "    at the death prompt (see 'died or stuck' above, and inc-loa.3)."
            echo "    A dead session logs less of everything, so quieter here does not"
            echo "    by itself mean healthier -- read the died/stuck count first."
        fi
        if [ "$N_THREAT" -gt 0 ]; then
            echo "    NOTE: $N_THREAT of $SESSIONS sessions in THIS run froze at the"
            echo "    threat-disengage prompt (see 'threat-frozen' above, and inc-loa.5)."
            echo "    A frozen session logs less of everything too -- read the"
            echo "    threat-frozen count before reading quieter as healthier."
        fi
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
