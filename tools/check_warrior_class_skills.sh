#!/bin/bash
# gate: live
# inc-k2ws: the Warrior class alone must allow ranks in both named skills.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || {
    echo "FAIL: build with BACKEND=posix ./build_macos.sh"
    exit 1
}
mkdir -p "$ROOT/logs/runs"
RUN="$(mktemp -d "$ROOT/logs/runs/warrior-class-skills-XXXXXX")" || exit 1
INCURSION_BIN=./incursion-headless INCURSION_LOAD= INCURSION_LAUNCHER= \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-18.dat INCURSION_RUN_DIR="$RUN" \
    tools/headless.sh tools/keys/warrior-class-skills.keys 1 >"$RUN/headless.log" 2>&1
rc=$?
echo "run: $RUN"
fail=0
if [ "$rc" -ne 0 ]; then
    echo "FAIL: headless exited $rc (see $RUN/headless.log)"
    fail=1
fi
SHEET="$RUN/logs/sheet.txt"
if [ ! -f "$SHEET" ]; then
    echo "FAIL: missing dump $SHEET"
    exit 1
fi
for skill in Appraise Diplomacy; do
    line="$(grep -m1 "^  $skill  " "$SHEET")"
    echo "$line"
    if ! grep -Eq '\(2 ranks,' <<< "$line"; then
        echo "FAIL: $skill does not have exactly 2 ranks (or its line is missing)"
        fail=1
    fi
done
[ "$fail" -eq 0 ] || exit 1
echo "PASS: Warrior Appraise and Diplomacy both have exactly 2 ranks"
