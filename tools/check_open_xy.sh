#!/bin/bash
# inc-upw.3: measure refusal/disposal and a successful-placement control.
# Build with EXTRA_CXXFLAGS=-DINCURSION_OPENXY_PROBE BACKEND=posix
# ./build_macos.sh; select the binary with INCURSION_BIN.
# Exit 0 pass, 1 behavioural failure, 2 missing/incomplete measurement.
#
# The three greps are necessary and NOT sufficient: the previous version of this
# check was greps only, and passed a fix that tested the sentinel and then
# placed at (0,0) anyway. The probe totals below are the real oracle. Mutations
# confirmed RED here on 2026-09-09: PlaceAt(_m,0,0) behind the sentinel test,
# Remove(false) in place of Remove(true), a sentinel that decodes to a real
# square (0x4040), and a transposed decode PlaceAt(_m,xy/256,xy%256).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

# --- 1. the two halves of the sentinel --------------------------------------
grep -q 'define NO_OPEN_XY' inc/Map.h || \
    fail "inc/Map.h: NO_OPEN_XY is gone."
grep -q 'return NO_OPEN_XY;' src/MakeLev.cpp || \
    fail "src/MakeLev.cpp: Map::GetOpenXY no longer returns the sentinel."
grep -q 'if (xy == NO_OPEN_XY)' inc/Map.h || \
    fail "inc/Map.h: Thing::PlaceOpen no longer tests the sentinel."

[ "$FAILED" -eq 0 ] || exit 1
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: build a probe binary first"; exit 2; }
for seed in 1025 1000; do
    out="$(INCURSION_OPENXY_PROBE=1 INCURSION_BIN="$BIN" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        tools/headless.sh tools/keys/explore.keys "$seed" 2>&1)"
    status=$?
    RUN="$(echo "$out" | awk '/^run:/ {print $2}')"
    [ "$status" -eq 0 ] || {
        echo "INCONCLUSIVE: seed $seed exited $status; $RUN"
        exit 2
    }
    python3 - "$RUN/logs/openxyprobe.log" "$seed" <<'PYCODE'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
if not p.exists() or not p.stat().st_size:
    print("INCONCLUSIVE: no probe totals:", p)
    sys.exit(2)
try:
    rows = [dict((k, int(v)) for k, v in (s.split('=') for s in line.split()))
            for line in p.read_text().splitlines()]
    r = rows[-1]
    # corner/peak/stranded: nothing may ever be linked into the solid (0,0).
    # badsq: no placement may land off the map or in rock ANYWHERE -- this is
    #        what catches a decode that strands the Thing somewhere other than
    #        the corner, which the (0,0) oracle alone cannot see.
    # inband: NO_OPEN_XY must not decode to a real square on the map in play.
    #        A sentinel a genuine answer can equal is the defect, not the fix.
    # invalid: the corner's Contents list must stay walkable.
    bad = any(x['corner'] or x['peak'] or x['stranded'] or x['invalid']
              or x['badsq'] or x['inband'] for x in rows)
    # every refused query must dispose exactly one Thing, and no other query may
    bad |= r['disposed'] != r['empty']
    bad |= (r['empty'] < 1 if sys.argv[2] == '1025' else r['placed'] < 1)
except (ValueError, KeyError):
    print("INCONCLUSIVE: malformed probe totals:", p)
    sys.exit(2)
print(('FAIL' if bad else 'PASS') + ': seed ' + sys.argv[2], r, p)
sys.exit(1 if bad else 0)
PYCODE
    result=$?
    [ "$result" -eq 0 ] || exit "$result"
done
exit 0
