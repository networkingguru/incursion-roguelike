#!/bin/bash
# gate: live
# inc-nhgh: retries and nested encounters must roll parts with fresh skip marks.
# Build: BACKEND=posix ./build_macos.sh
# Oracle: Stage 4 starts with no skipped parts, including retries/nested calls.
# Exit 0 GREEN; 1 RED; 2 UNMEASURED.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
[ -x ./incursion-headless ] || {
    echo "UNMEASURED: build with BACKEND=posix ./build_macos.sh"
    exit 2
}
mkdir -p "$ROOT/logs/runs"
RUN="$(mktemp -d "$ROOT/logs/runs/encounter-skip-reset-XXXXXX")" || exit 2
echo "specimens: $RUN"
# Resolve the assertion line so unrelated additions to MakeLev.cpp do not
# silently disable the oracle. Refuse to measure if the site is ambiguous.
ASSERT_LINE="$(awk '/ASSERT\(c = GetEncounterCreature\(0\)\);/ { print NR }' src/MakeLev.cpp)"
if ! [[ "$ASSERT_LINE" =~ ^[0-9]+$ ]]; then
    echo "UNMEASURED: cannot identify PopulatePanel assertion"
    exit 2
fi
rc=0
INCURSION_OPTIONS=tools/gates/Options.Dat \
INCURSION_ENCSKIP_PROBE=1 \
INCURSION_RUN_DIR="$RUN" \
    tools/headless.sh tools/keys/dive.keys 7 > "$RUN/headless.log" 2>&1 || rc=$?
if grep -qE "src/MakeLev.cpp, line ${ASSERT_LINE}([^0-9]|$)" "$RUN/logs/errors.log" 2>/dev/null; then
    echo "RED: PopulatePanel assertion (src/MakeLev.cpp, line $ASSERT_LINE)"
    exit 1
fi
counts="$(awk '
    /ENCSKIP enID=[0-9]+ pass=[0-9]+ nested=[01] dirty=[0-9]+/ {
        pass = nested = dirty = 0
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^pass=/) { split($i, a, "="); pass = a[2] + 0 }
            if ($i ~ /^nested=/) { split($i, a, "="); nested = a[2] + 0 }
            if ($i ~ /^dirty=/) { split($i, a, "="); dirty = a[2] + 0 }
        }
        if (dirty > 0) bad++
        if (pass > 1 || nested == 1) exercised++
    }
    END { print bad + 0, exercised + 0 }
' "$RUN/logs/errors.log" 2>/dev/null)"
read -r dirty_count exercised <<< "$counts"
if [ "${dirty_count:-0}" -gt 0 ]; then
    echo "RED: $dirty_count ENCSKIP passes with dirty>0; $exercised retry/nested passes"
    exit 1
fi
if [ "${exercised:-0}" -eq 0 ]; then
    echo "UNMEASURED: no retry/nested ENCSKIP passes; harness exit $rc"
    exit 2
fi
echo "GREEN: $exercised retry/nested passes; all ENCSKIP dirty=0; no PopulatePanel assertion (harness exit $rc)"
