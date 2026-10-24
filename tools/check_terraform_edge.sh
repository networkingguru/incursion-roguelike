#!/bin/bash
# gate: live
# inc-07y9: column zero is a valid globe terraform destination.
# fact: actor/target character and starting map -- INCURSION_LOAD frozen fixture
# fact: options -- fixed options-2026-08-22.dat fixture
# fact: floor at column zero and outside-circle target -- probe builds the map (Terrain control)
# fact: creature target outside circle -- loaded fixture player, explicitly placed by probe
# fact: no incidental creatures or turns/rolls -- probe clears map objects and fires synchronously
# fact: effect and result text -- named Grease resource and literal probe tags, no random text
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || {
    echo "FAIL: build with BACKEND=posix ./build_macos.sh"
    exit 1
}
RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-terraform-edge"
mkdir -p "$RUN_DIR"
INCURSION_TERRAFORM_EDGE_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav \
    tools/headless.sh tools/keys/area-radius.keys 1 > "$RUN_DIR/check-session.log" 2>&1
status=$?
log="$RUN_DIR/logs/errors.log"
grep 'TERRA_EDGE_PROBE:' "$log" 2>/dev/null || true
echo "Session exit: $status"
echo "Specimen: $log"
echo "Session output: $RUN_DIR/check-session.log"
if [ "$status" -ne 0 ]; then
    grep 'ended:' "$RUN_DIR/check-session.log" || true
    echo "FAIL: terraform edge session exited $status (crash or harness failure)."
    exit 1
fi
if ! grep -q 'TERRA_EDGE_PROBE: PASS$' "$log"; then
    echo "FAIL: no TERRA_EDGE_PROBE: PASS; probe failed or did not finish."
    exit 1
fi
echo "PASS: both column-zero squares terraformed; outside target square untouched."
