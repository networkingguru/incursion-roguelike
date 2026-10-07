#!/bin/bash
# gate: none a measurement tool with no threshold, and one run takes minutes (inc-gst2)
# inc-gst2: how much wall time does one game turn cost on a level crowded with
# creatures? This is a MEASUREMENT tool, not a gate: it sets no threshold. It
# fails (exit 2) only when a scenario cannot prove its own crowd or its own
# turn count.
#
#   tools/check_crowd_turn_cost.sh                      # 3 scenarios, 1 run each
#   tools/check_crowd_turn_cost.sh --runs 3             # ... 3 runs each
#   tools/check_crowd_turn_cost.sh --census             # also count known squares
#   tools/check_crowd_turn_cost.sh --profile hostile    # one run + `sample` profile
#   tools/check_crowd_turn_cost.sh --bin ./other-headless --scenarios "hostile"
#
# Scenarios (all: frozen Lizardfolk monk, seed 1, 300 rests on the same level):
#   baseline  the level with every monster removed.
#   hostile   90 hostile giant rats on the level.
#   allies    the same 90 rats, each made the player's follower.
# tools/crowd_turn_cost.py (header) says how the crowd is made, why the player
# survives, and how the crowd is proven from the game's own wizard display.
#
# THE SETTINGS FILE matters twice. OPT_MON_DJIKSTRA must be 1 (every monster
# uses the path search; 2 = pets only; 0 = none), and this script refuses to run
# otherwise. OPT_DESC_ROOM must be 0, or the first room the sweep enters opens a
# box that eats keys. tools/fixtures/options-2026-08-22-noroomdesc.dat is the
# 2026-08-22 fixture with only that byte changed (tools/fixtures/README.md).
#
# Output: RESULT lines (one per run), a CENSUS line with --census, then a table
# of ms/turn per scenario. Run directories and key scripts are under
# logs/crowd-turn-cost/<stamp>/. Needs a BACKEND=posix build.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RUNS=1; REST=300; SCEN="baseline hostile allies"; BIN=""; CENSUS=0; PROFILE=""
OPTS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22-noroomdesc.dat}"
LOAD="tools/fixtures/chars/lizardfolk-monk-seed1.sav"
while [ $# -gt 0 ]; do
    case "$1" in
        --runs) RUNS="$2"; shift 2 ;;
        --rest) REST="$2"; shift 2 ;;
        --scenarios) SCEN="$2"; shift 2 ;;
        --bin) BIN="$2"; shift 2 ;;
        --census) CENSUS=1; shift ;;
        --profile) PROFILE="$2"; shift 2 ;;
        *) echo "usage: see the header of $0"; exit 2 ;;
    esac
done
[ -n "$BIN" ] && export INCURSION_BIN="$BIN"
BINPATH="${BIN:-./incursion-headless}"
[ -x "$BINPATH" ] || { echo "FAIL: $BINPATH is missing; build it with BACKEND=posix ./build_macos.sh"; exit 2; }

# OPT_MON_DJIKSTRA is option 114, OPT_DESC_ROOM is 407 (inc/Defines.h).
byte() { python3 -I -c 'import sys; print(open(sys.argv[1],"rb").read()[int(sys.argv[2])])' "$OPTS" "$1"; }
DJ="$(byte 114)"; DR="$(byte 407)"
echo "settings: $OPTS  OPT_MON_DJIKSTRA=$DJ  OPT_DESC_ROOM=$DR"
[ "$DJ" = "1" ] || { echo "FAIL: OPT_MON_DJIKSTRA is $DJ, not 1; the measurement would not use the path search"; exit 2; }
[ "$DR" = "0" ] || { echo "FAIL: OPT_DESC_ROOM is $DR, not 0; room boxes would eat the sweep's keys"; exit 2; }

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/logs/crowd-turn-cost/$STAMP"
mkdir -p "$OUT"
FAILED=0
declare -a TABLE

run_one() { # <scenario> <tag> <rest> [probe]
    local sc="$1" tag="$2" rest="$3" probe="${4:-}"
    local keys="$OUT/$tag.keys" run="$OUT/$tag"
    python3 -I tools/crowd_turn_cost.py keys "$sc" --rest "$rest" > "$keys" || return 2
    local extra=()
    [ -n "$probe" ] && extra=(INCURSION_MAP_PROBE=1)   # set-but-empty would still switch it on
    env INCURSION_MAX_KEYS=500000 INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$LOAD" \
        INCURSION_RUN_DIR="$run" ${extra[@]+"${extra[@]}"} \
        tools/headless.sh "$keys" 1 > "$OUT/$tag.out" 2>&1
    return 0
}

if [ "$CENSUS" = 1 ]; then
    run_one census census-1 1 probe
    python3 -I tools/crowd_turn_cost.py analyse census "$OUT/census-1" || FAILED=1
fi

if [ -n "$PROFILE" ]; then
    # A longer rest, and `sample` attached once the timed part has begun.
    tag="profile-$PROFILE"
    keys="$OUT/$tag.keys"
    python3 -I tools/crowd_turn_cost.py keys "$PROFILE" --rest 1500 > "$keys" || exit 2
    ( INCURSION_MAX_KEYS=500000 INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$LOAD" \
        INCURSION_RUN_DIR="$OUT/$tag" tools/headless.sh "$keys" 1 > "$OUT/$tag.out" 2>&1 ) &
    HPID=$!
    for _ in $(seq 1 600); do
        ls "$OUT/$tag/logs/screens/"*-start.txt >/dev/null 2>&1 && break
        sleep 0.2
    done
    GPID="$(pgrep -f "incursion-headless.*-keys $keys" | head -1)"
    if [ -z "$GPID" ]; then echo "FAIL: profile: no game process found"; FAILED=1; else
        SPEC="$ROOT/logs/crowd-turn-cost/$STAMP-sample-$PROFILE.txt"
        sample "$GPID" 10 -file "$SPEC" > /dev/null 2>&1
        echo "PROFILE $PROFILE specimen: $SPEC"
    fi
    wait "$HPID"
fi

[ -n "$PROFILE" ] && SCEN_RUN="" || SCEN_RUN="$SCEN"
for sc in $SCEN_RUN; do
    for n in $(seq 1 "$RUNS"); do
        run_one "$sc" "$sc-$n" "$REST"
        line="$(python3 -I tools/crowd_turn_cost.py analyse "$sc" "$OUT/$sc-$n" --rest "$REST")"
        rc=$?
        echo "$line"
        [ $rc -eq 0 ] || FAILED=1
        ms="$(echo "$line" | grep -o 'ms_per_turn=[0-9.]*' | cut -d= -f2)"
        TABLE+=("$sc $n ${ms:-FAILED}")
    done
done

echo
echo "ms per turn (wall time of $REST rests / $REST):"
for r in "${TABLE[@]}"; do echo "  $r"; done
echo "run directories: $OUT"
[ "$FAILED" = 0 ] || { echo "FAIL: at least one scenario did not prove its crowd or its turn count"; exit 2; }
exit 0
