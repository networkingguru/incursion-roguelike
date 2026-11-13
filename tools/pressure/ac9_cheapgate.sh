#!/bin/bash
# land10's gate in the AC9 rehearsal (inc-cjos0 E2): the build, then the CHEAP TIER of the real landing gate
# (tools/nightly_verify.sh --landing). A red in the cheap tier stops the landing (the gate exits 1). When the cheap tier is green the
# gate is stopped as it starts the builds: inc-10v7f's real landing runs the whole gate, this rehearsal runs the part that
# can be measured against a base without recording one for master (AC9_GATE_BASE: the recorded epic base; a check red there
# and red now is pre-existing).
#   tools/pressure/ac9_cheapgate.sh      run from the repository to land into, with AC9_GATE_BASE set
# Exit: 0 cheap tier green, 1 a check broke, 2 could not run.
set -uo pipefail
[ -r "${AC9_GATE_BASE:-}" ] || { echo "ac9_cheapgate: AC9_GATE_BASE names no readable base" >&2; exit 2; }
BACKEND=posix ./build_macos.sh > /dev/null 2>&1 || { echo "ac9_cheapgate: the build failed" >&2; exit 1; }
out="$(mktemp "${TMPDIR:-/tmp}/ac9-cheapgate.XXXXXX")" || exit 2
NIGHTLY_VERIFY_STATE="$AC9_GATE_BASE" tools/nightly_verify.sh --landing > "$out" 2>&1 &
pid=$!
while kill -0 "$pid" 2> /dev/null; do
    if grep -q '^--- builds, macOS only' "$out"; then
        pkill -P "$pid" 2> /dev/null; kill "$pid" 2> /dev/null; wait "$pid" 2> /dev/null
        cat "$out"; rm -f "$out"
        echo "=== cheap tier green (rehearsal: the builds and the live tier were not run) ==="
        exit 0
    fi
    sleep 2
done
wait "$pid"; rc=$?
cat "$out"; rm -f "$out"
exit "$rc"
