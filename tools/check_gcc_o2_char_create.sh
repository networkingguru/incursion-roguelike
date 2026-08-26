#!/bin/bash
# Regression guard for inc-nw0v: the GCC -O2 character-creation miscompile.
#
# WHAT IT DEFENDS. Item::Item(rID,int16) in src/Item.cpp must assign every
# member it depends on before use -- eID and Plus before MaxHP() reads them,
# and Parent/homeID/Flavor/DmgType/swingCount instead of leaning on the
# zero-fill in Object::operator new (inc/Base.h). Reading an unassigned member
# is undefined. GCC -O2 does not preserve that zero-fill: a wild Parent handle
# is dereferenced during character creation and the run segfaults with
# "Registry::Get -- invalid object handle (1344285811)" before it reaches a
# map. clang and GCC -O0 keep the fill and hide the defect. This guard is the
# ONLY thing in tools/ that sees a regression of that fix, because it is the
# only check that builds at -O2 with GCC.
#
# WHY IT USES DOCKER + GCC. There is no Linux/GCC machine attached to this
# project; the developer builds with clang on macOS, which never exposes the
# bug. Docker on linux/amd64 with build-essential's gcc/g++ is the only way to
# reach a GCC -O2 build from the machine the work happens on. It reuses the
# same incursion-linux:bullseye image as tools/check_linux_build.sh.
#
# This is the CONVERSE of tools/check_linux_build.sh: that check builds with
# CLANG on purpose and tells you NOT to "fix" a red run by switching to gcc.
# This check builds with GCC on purpose, to prove the -O2 creation path is
# clean. Do not merge the two: they defend different things.
#
# HOW TO PROVE IT BITES. In src/Item.cpp's Item::Item(rID,int16), delete the
# line "Parent = 0; homeID = 0; Flavor = 0; DmgType = 0; swingCount = 0;" and
# run this again. The seed-7 run segfaults (exit 139), never enters a map, and
# logs "invalid object handle (1344285811)". This guard then FAILS.
#
# Usage: tools/check_gcc_o2_char_create.sh   (exits 0 on pass, 1 on fail,
#                                             2 on could-not-measure)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IMAGE="incursion-linux:bullseye"
SEED=7
KEYS="tools/keys/dive.keys"

# Debian 11 / glibc 2.31, x86_64: the same floor tools/check_linux_build.sh
# builds against. The bug is a GCC optimiser behaviour, not a glibc one, so any
# GCC -O2 build on amd64 reproduces it; we reuse the one image we already have.
PLATFORM="linux/amd64"

command -v docker >/dev/null || { echo "SKIP: docker not installed"; exit 2; }
docker info >/dev/null 2>&1 || { echo "SKIP: docker daemon not running"; exit 2; }

# Clean export of the WORKING TREE, never a bind mount of it: a bind mount would
# let the container write Linux/GCC objects into the developer's build/ and the
# next macOS build would link a mixture. build-essential in the image provides
# gcc/g++; build_macos.sh honours $CC/$CXX.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "FAIL: image $IMAGE is missing; run tools/check_linux_build.sh once to build it"
    exit 2
fi

# Working-tree content, not HEAD: a pre-commit check must see the change under
# test, so we export what git ls-files reports, at its on-disk content.
git ls-files -z | xargs -0 tar -cf - 2>/dev/null | tar -x -C "$TMP" || {
    echo "FAIL: could not export the working tree"; exit 2; }

# Only the headless (BACKEND=posix) build is needed: the crash is on the
# character-creation path and does not require the SDL backend. GCC -O2 is the
# whole point -- CC=gcc CXX=g++ selects the compiler that miscompiles the
# unfixed constructor. SDL_VIDEODRIVER=dummy because the -compile step that
# builds the module still initialises SDL video, and a container has no display.
OUT="$(docker run --rm --platform "$PLATFORM" \
        -e SDL_VIDEODRIVER=dummy -e SDL_AUDIODRIVER=dummy \
        -v "$TMP:/src" "$IMAGE" sh -c '
    set -e
    CC=gcc CXX=g++ BACKEND=posix ./build_macos.sh >/dev/null 2>&1 \
        || { echo "POSIX-BUILD-FAILED"; exit 0; }
    tools/headless.sh '"$KEYS"' '"$SEED"' 2>&1 | tail -40
' 2>&1)"

fail() { echo "FAIL: $1"; echo "--- run output ---"; echo "$OUT"; exit 1; }

case "$OUT" in
    *POSIX-BUILD-FAILED*) fail "the GCC -O2 headless build or its module compile broke" ;;
esac

# The exact fingerprint of inc-nw0v. Name it so a future red run is unambiguous.
echo "$OUT" | grep -q "invalid object handle" \
    && fail "inc-nw0v regressed: object handles corrupt on the GCC -O2 creation path"

# "no gameplay is not a pass" -- docs/VERIFICATION.md. The unfixed build
# segfaults before any map, so reaching a map is the load-bearing signal here.
echo "$OUT" | grep -q "map audit:  armed" \
    || fail "the GCC -O2 run never entered a map (creation-path crash?)"

echo "$OUT" | grep -q "^errors:     none" \
    || fail "the GCC -O2 run logged errors that a clean build does not"

echo "PASS: GCC -O2 builds the headless backend and plays seed $SEED into a map with no errors"
exit 0
