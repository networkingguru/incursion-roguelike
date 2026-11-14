#!/usr/bin/env bash
# gate: live
#
# Does a fixture build that grows memory without bound stop at the memory cap?
#
# WHAT IS BEING PROVED. Bead inc-r10je: a build that loops grew about 650 MB a
# second (inc-xgs1x) and froze the Mac. tools/build_fixture.sh now kills the
# binary and its children at INCURSION_BUILD_MEM_CAP_MB (default 2048) and ends
# with exit 10 and a `BUILD FAILED:` line that names the cap. Cases:
#   red      a fake binary that grows real resident memory is stopped at a cap
#            of 256 MB: exit 10, the line says "memory cap of 256 MB", the run
#            takes under 10 s, and no fake process is left alive;
#   default  with the variable unset a fake that grows to about 300 MB and then
#            exits 0 ends as the "no .sav" failure, not a cap failure (the
#            default is above 300 MB), and the default literal in
#            tools/build_fixture.sh is 2048 (no check allocates 2 GB);
#   bad      a cap of "abc" exits 2;
#   green    a committed fixture builds under the default cap.
# The fake stops itself at about 1 GB, so a broken cap cannot hurt the machine.
#
# fact: the fake binary -- a script this check writes; it grows memory by a fixed step and rate and reads no game data, so no seed decides it (inc-r10je)
# fact: the green fixture -- tools/fixtures/chars/orc-barbarian-seed1-opt0822.char, a committed .char; the build reads its own seed: line, so no seed decides it (inc-10v7f)
# fact: the cap and the memory figures -- the variable this check sets, and the resident memory of the fake, which the fake's own step size fixes (inc-r10je)
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_build_mem_cap.sh
# Exit: 0 every case behaved as stated; 1 one did not; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
command -v python3 > /dev/null || { echo "INCONCLUSIVE: no python3"; exit 2; }
FIX=tools/fixtures/chars/orc-barbarian-seed1-opt0822.char
[ -f "$FIX" ] || { echo "INCONCLUSIVE: $FIX missing"; exit 2; }

W="$(mktemp -d "$ROOT/logs/build-mem-cap.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT

# make_fake <name> <stop-mb> <exit-code-after-stop>: a binary that adds 50 MB of
# touched memory every 0.1 s (about 500 MB/s) until <stop-mb>, then exits.
make_fake() {
    cat > "$W/$1" <<FAKE
#!/bin/bash
echo \$\$ > "$W/$1.pid"
exec python3 -c '
import sys, time
keep = []
while len(keep) * 50 < $2:
    keep.append(b"x" * 50_000_000)
    time.sleep(0.1)
sys.exit($3)
'
FAKE
    chmod +x "$W/$1"
}

fail=0
n=0
run() {   # <fake> <label> [VAR=value ...] -> RC, ELAPSED, ERR
    local fake="$1"; shift 2
    n=$((n + 1))
    local t0=$SECONDS
    env -u INCURSION_BUILD_MEM_CAP_MB "$@" INCURSION_BIN="$W/$fake" INCURSION_BUILD_RUN_DIR="$W/run$n" \
        tools/build_fixture.sh "$FIX" "$W/out$n" > "$W/stdout$n.txt" 2> "$W/stderr$n.txt"
    RC=$?
    ELAPSED=$((SECONDS - t0))
    ERR="$(grep -m1 '^BUILD FAILED:' "$W/stderr$n.txt")"
}

# red: the cap stops a growing build.
make_fake grow 1000 3
run grow red INCURSION_BUILD_MEM_CAP_MB=256
if [ "$RC" -ne 10 ]; then echo "FAIL red: exit $RC, want 10"; fail=1
elif ! grep -qF 'memory cap of 256 MB' <<< "$ERR"; then echo "FAIL red: no cap line: $ERR"; fail=1
elif [ "$ELAPSED" -ge 10 ]; then echo "FAIL red: took ${ELAPSED} s, want under 10"; fail=1
else echo "ok   a growing build is stopped at the cap"; echo "       $ERR" | cut -c1-200; fi
pid="$(cat "$W/grow.pid" 2> /dev/null)"
if [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null; then
    echo "FAIL red: the fake process $pid is still alive"; fail=1
    kill -9 "$pid" 2> /dev/null
else echo "ok   no fake process is left alive"; fi

# default: unset cap is above 300 MB, so a 300 MB build is not a cap failure.
make_fake mid 300 0
run mid default
if [ "$RC" -ne 10 ]; then echo "FAIL default: exit $RC, want 10"; fail=1
elif grep -qF 'memory cap' <<< "$ERR"; then echo "FAIL default: a 300 MB build hit the cap: $ERR"; fail=1
elif ! grep -qF 'no .sav' <<< "$ERR"; then echo "FAIL default: wanted the no .sav failure: $ERR"; fail=1
else echo "ok   with the cap unset a 300 MB build is not stopped"; fi
if grep -qE 'MEM_CAP_MB:-2048\}' tools/build_fixture.sh; then echo "ok   the default cap in build_fixture.sh is 2048 MB"
else echo "FAIL default: build_fixture.sh does not default the cap to 2048"; fail=1; fi

# bad value.
n=$((n + 1))
INCURSION_BUILD_MEM_CAP_MB=abc INCURSION_BIN="$W/mid" tools/build_fixture.sh "$FIX" "$W/outbad" > /dev/null 2>&1
RC=$?
if [ "$RC" -eq 2 ]; then echo "ok   a cap of abc exits 2"; else echo "FAIL bad value: exit $RC, want 2"; fail=1; fi

# green: a real fixture builds under the default cap.
n=$((n + 1))
INCURSION_BIN="$BIN" tools/build_fixture.sh "$FIX" "$W/outgreen" > "$W/green.out" 2> "$W/green.err"
RC=$?
if [ "$RC" -eq 0 ] && [ -f "$W/outgreen/$(basename "$FIX" .char).sav" ]; then echo "ok   a committed fixture builds under the default cap"
else echo "FAIL green: exit $RC: $(tail -2 "$W/green.err" | cut -c1-200)"; fail=1; fi

[ $fail -eq 0 ] && { echo "PASS: the build memory cap behaves as stated"; exit 0; }
exit 1
