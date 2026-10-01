#!/bin/bash
# Regression check for the Linux port: does a clean tree still build and play
# on Linux?
#
# This is the oracle for six changes made on 2026-08-26, and it is the only
# thing in tools/ that can see any of them. macOS cannot: every one of them is
# a place where the tree assumed Apple's toolchain or Apple's libc.
#
#   build_macos.sh      clang/clang++ were hardcoded; -framework OpenGL is a
#                       macOS link flag and Linux needs -ldl -lpthread instead
#   compat/malloc.h     the shim shadows glibc's <malloc.h>, and its guard
#                       admitted only Apple and FreeBSD, so Linux lost alloca()
#   inc/Map.h           offsetof with no <cstddef>; libc++ drags it in and
#                       libstdc++ does not
#   src/Registry.cpp    intptr_t with no <cstdint>, same cause
#   inc/Defines.h       __builtin_debugtrap is clang-only
#   src/cpp1.c          a double fclose that only a checking allocator sees
#                       (inc-0dyb)
#
# WHY IT USES DOCKER. There is no Linux machine attached to this project, and a
# check nobody can run is not a check. Docker is the only Linux this repository
# can reach from the machine the work happens on. That puts this script in a
# tier of its own: it is the one check in tools/ with a dependency the other
# 130 do not have. tools/README.md 7 says so.
#
# WHY IT USES CLANG. GCC -O2 miscompiles this engine -- object handles corrupt
# during character creation and the run segfaults before reaching a map, while
# -O0 is clean and clang is clean at every level. That is inc-nw0v, it is
# undefined behaviour in the game rather than a GCC defect, and it is NOT what
# this check defends. Do not "fix" a red run here by switching to gcc.
#
# HOW TO PROVE IT BITES. Undo any one of the six changes and run it again. The
# cheapest is src/cpp1.c: put fclose(fin) back beside fclose(fout) and the
# module compile aborts with "double free detected in tcache 2".
#
# Usage: tools/check_linux_build.sh    (exits 0 on pass, 1 on fail, 2 on
#                                       could-not-measure)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

. "$ROOT/tools/linux_docker.sh"

IMAGE="$(linux_image_tag debian11)"
SEED=7
KEYS="tools/keys/dive.keys"

# Debian 11 on purpose: glibc 2.31. A binary links versioned glibc symbols, so
# it runs on the release it was built against and everything newer, and refuses
# to start on anything older. Building on the oldest glibc we support is what
# sets the floor of who can run the release. x86_64 on purpose: the Steam Deck
# and the ROG Ally are both x86_64.
PLATFORM="linux/amd64"

linux_docker_preflight || exit 2

# The tree goes in as a clean export, never as a bind mount of the working
# directory. A bind mount would let the container's build write Linux objects
# and a Linux-built module into the developer's own build/ and mod/, and the
# next macOS build would link a mixture of the two.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build the image on first use, and export the tracked files at their
# WORKING-TREE content (see tools/linux_docker.sh). `git archive HEAD` would
# export the last commit and silently ignore the change being checked, which is
# the opposite of what a pre-commit check is for.
linux_ensure_image debian11 "$TMP" || exit 2
linux_export_tree "$TMP" || exit 2

# SDL_VIDEODRIVER=dummy because build_macos.sh finishes by running the binary
# it just built to compile the module, and the libtcod binary initialises SDL
# video even for -compile. A container has no display.
OUT="$(docker run --rm --platform "$PLATFORM" \
        -e SDL_VIDEODRIVER=dummy -e SDL_AUDIODRIVER=dummy \
        -v "$TMP:/src" "$IMAGE" sh -c '
    set -e
    CC=clang CXX=clang++ BACKEND=posix ./build_macos.sh >/dev/null 2>&1 \
        || { echo "POSIX-BUILD-FAILED"; exit 0; }
    CC=clang CXX=clang++ ./build_macos.sh >/dev/null 2>&1 \
        || { echo "LIBTCOD-BUILD-FAILED"; exit 0; }
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat tools/headless.sh '"$KEYS"' '"$SEED"' 2>&1 | tail -30
' 2>&1)"

fail() { echo "FAIL: $1"; echo "--- run output ---"; echo "$OUT"; exit 1; }

case "$OUT" in
    # Either arm covers two steps, because build_macos.sh finishes by running
    # the binary it just built to compile mod/Incursion.Mod. A compile error and
    # a -compile that aborts both land here. inc-0dyb was the second kind.
    *POSIX-BUILD-FAILED*)   fail "the headless build or its module compile broke on Linux" ;;
    *LIBTCOD-BUILD-FAILED*) fail "the SDL build or its module compile broke on Linux" ;;
esac

# "no gameplay is not a pass" -- docs/VERIFICATION.md. A run that never entered
# a map must not be read as a green build.
echo "$OUT" | grep -q "map audit:  armed" \
    || fail "the run never entered a map"

echo "$OUT" | grep -q "^errors:     none" \
    || fail "the Linux run logged errors that macOS does not"

echo "PASS: Linux builds both backends and plays seed $SEED with no errors"
exit 0
