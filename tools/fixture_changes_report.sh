#!/bin/bash
# Report, never block: which fixtures built a different character than the one
# the recorded base used (bead inc-10v7f, spec A10 and B8). tools/finish_bead.sh
# runs this after the gate, so no change to a built character is silent.
#
# For each fixture the pin record lists, compare the dump hash that
# logs/fixture-builds.tsv holds for the CURRENT key (tools/fixture_cache.sh
# --key, from the .char, options, binary and module as they are now) with the
# dump hash it holds for the key the pin record names. A pinned run never builds
# the current key, so a changed key with no logged hash is built here, unpinned. A different hash prints
# one "fixture changed:" line. The exit status is always 0.
#
# Usage: tools/fixture_changes_report.sh [pin-record [build-log]]
#   pin-record  default: nightly-verify-fixture-pins.txt beside the gate's base
#               record ($NIGHTLY_VERIFY_STATE, else logs/nightly-verify-base.txt)
#   build-log   default: logs/fixture-builds.tsv
# The pin record is written by tools/nightly_verify.sh --record: `<name><TAB><key>`.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 0

STATE="${NIGHTLY_VERIFY_STATE:-$ROOT/logs/nightly-verify-base.txt}"
PIN="${1:-$(dirname "$STATE")/nightly-verify-fixture-pins.txt}"
LOG="${2:-$ROOT/logs/fixture-builds.tsv}"

if [ ! -r "$PIN" ] || [ ! -r "$LOG" ]; then
    echo "fixtures: no pin record or no build log, so no fixture change is reported (pin record $PIN, build log $LOG)"
    exit 0
fi

hash_for() { # <name> <key> -> the last dump hash logged for that pair
    awk -F'\t' -v n="$1" -v k="$2" '$1 == n && $2 == k { h = $3 } END { print h }' "$LOG"
}

CHANGED=0
SEEN=0
while IFS=$'\t' read -r name pinkey; do
    [ -n "$name" ] || continue
    SEEN=$((SEEN + 1))
    cur="$(tools/fixture_cache.sh --key "$name" 2> /dev/null)" || {
        echo "fixtures: $name: could not compute its current key; not compared"
        continue
    }
    [ "$cur" = "$pinkey" ] && continue
    old="$(hash_for "$name" "$pinkey")"
    new="$(hash_for "$name" "$cur")"
    if [ -z "$new" ]; then
        # With the pin set, no run built the current key. Build it now, unpinned.
        env -u INCURSION_FIXTURE_PIN tools/fixture_cache.sh "$name" > /dev/null 2>&1
        new="$(hash_for "$name" "$cur")"
    fi
    if [ -z "$old" ] || [ -z "$new" ]; then
        echo "fixtures: $name: no dump hash logged for the pinned key or the current key; not compared"
        continue
    fi
    if [ "$old" != "$new" ]; then
        CHANGED=$((CHANGED + 1))
        echo "fixture changed: $name (dump ${old:0:12} -> ${new:0:12})"
    fi
done < "$PIN"
echo "fixtures: $SEEN pinned, $CHANGED changed"
exit 0
