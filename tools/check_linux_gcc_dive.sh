#!/bin/bash
# gate: none needs Docker and minutes per distro; run it by hand
#
# Guard for inc-eikp.2: a constructor leaning on the operator-new zero-fill,
# seen on the MAP-GENERATION path that chargen-only checks never reach.
#
# WHAT IT GUARDS. `Map::Map()` in src/Display.cpp must assign `hObj pl[4]` and
# `int16 PlayerCount` before use. Base code left them to the zero-fill that
# `Object::operator new` does (inc/Base.h); reading such an indeterminate member
# is undefined, so an optimiser may delete the fill. On the unfixed tree,
# `Map::enBuildMon` builds a monster on the NEW map, `Creature::SetImage` reads
# `m->pl[0]` before any player is registered there, and a stale heap value makes
# `Registry::GetPlayer` raise "Illegal system object number" on the map path.
#
# WHY ARCH + RAW DSE. Debian 11's GCC 10 does not expose it and
# `-flifetime-dse=1` (build_macos.sh's mask, inc-eikp.3) hides it, so this guard
# builds with Arch GCC under INCURSION_GCC_RAW_DSE=1 -- exactly the combination
# that deletes the fill and shows the defect. tools/linux_run.sh owns the Docker
# logic and the raw-DSE flag; this script only supplies keys, seed and options.
#
# HOW TO PROVE IT BITES. Delete the `pl[0..3] = 0; PlayerCount = 0;` assignment
# in `Map::Map()` (src/Display.cpp), run this again: the seed-1 dive logs the
# "Illegal system object number (96)!" lines and exits 139 before entering a map,
# and this guard goes red. Revert exactly; `git diff -- src/` must be empty.
#
# Usage: tools/check_linux_gcc_dive.sh
# Exit 0 pass, 1 fail, 2 could not measure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS="tools/keys/dive.keys"
SEED=1
OPTIONS="tools/fixtures/options-2026-08-22.dat"
NAME="inc-eikp.2-gcc-dive-$(date +%Y%m%d-%H%M%S)-$$"

. "$ROOT/tools/linux_docker.sh"

for f in "$KEYS" "$OPTIONS"; do
    [ -f "$f" ] || { echo "FAIL: needed file is missing: $f"; exit 2; }
done

# Docker is the only way to reach an Arch GCC build from this arm64 Mac; without
# it there is nothing to measure, so exit 2 -- never a pass (docs/VERIFICATION.md).
linux_docker_preflight || exit 2

OUT="$(INCURSION_GCC_RAW_DSE=1 INCURSION_OPTIONS="$OPTIONS" \
        tools/linux_run.sh --distro arch --cc gcc --name "$NAME" "$KEYS" "$SEED" 2>&1)"
STATUS=$?

# No measurement is not a pass. tools/linux_run.sh exits 2 when it could not
# export, build, or start the container at all.
if [ "$STATUS" -eq 2 ]; then
    echo "UNMEASURED: tools/linux_run.sh could not measure (exit 2)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
    exit 2
fi

fail() { echo "FAIL: $1"; echo "--- run output ---"; printf '%s\n' "$OUT"; }
print_errors() {
    local log="$ROOT/logs/linux/runs/$NAME/logs/errors.log"
    if [ -f "$log" ]; then
        echo "--- logs/errors.log ---"
        sed 's/^/        /' "$log"
    fi
}

if [ "$STATUS" -ne 0 ]; then
    if [ "$STATUS" -eq 139 ]; then
        fail "the GCC raw-DSE dive segfaulted (exit 139) before entering a map"
    else
        fail "the GCC raw-DSE dive exited non-zero ($STATUS) before entering a map"
    fi
    print_errors
    exit 1
fi

if grep -q "NO GAMEPLAY" <<<"$OUT"; then
    fail "the GCC raw-DSE dive never entered a map (NO GAMEPLAY)"
    print_errors
    exit 1
fi

if ! grep -q '^errors:     none' <<<"$OUT"; then
    fail "the GCC raw-DSE dive logged errors that a clean build does not"
    print_errors
    exit 1
fi

echo "PASS: Arch GCC raw-DSE builds and plays seed $SEED into a map with no errors"
exit 0
