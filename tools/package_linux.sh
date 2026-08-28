#!/bin/bash
# Produce a Linux/Steam-Deck tarball that someone else can download and run:
# dist/incursion-steamdeck-x86_64.tar.gz.
#
# This is the Linux sibling of tools/package_macos.sh. It ships the same payload
# (the game, its data module, its fonts) but for x86_64 Linux, and it builds that
# binary the only way this project can from a Mac: inside the Debian 11 container
# that tools/check_linux_build.sh already defines.
#
# WHY DOCKER, WHY DEBIAN 11, WHY CLANG. There is no Linux machine attached to
# this project, so the release binary is cross-built in a container -- the same
# incursion-linux:bullseye image the Linux regression check uses, so the two
# share one cached image. Debian 11 on purpose: its glibc 2.31 is the floor of
# who can run the release, because a binary links versioned glibc symbols and
# runs on that release and everything newer. Clang on purpose: GCC -O2
# miscompiles this engine (inc-nw0v), clang is clean; check_linux_build.sh says
# the same and for the same reason.
#
# WHY IT BUILDS TWICE, like package_macos.sh. The module is a memory image welded
# to the struct layout of the binary that wrote it, and only a DEVELOPER binary
# has the resource compiler (the GPLv2 ACCENT runtime that src/Art.cpp says must
# never ship). So: build the developer binary, let it write mod/Incursion.Mod,
# then build the shipping binary with COMPILER=no. A matching x86_64 developer
# binary must write the x86_64 module -- the macOS module will not do.
#
# WHY NO BUNDLED SDL2. On Linux, libSDL2 is a system library; SteamOS and the ROG
# Ally both ship it (as sdl2-compat over SDL3), and the alpha resolved every dep
# against system libs. So this tarball does not carry SDL2.
#   ponytail: a user on a minimal distro without libSDL2 installed must install
#   it themselves. The upgrade path is to bundle libSDL2.so.0 beside the binary
#   and set an rpath of $ORIGIN, the way package_macos.sh bundles the dylib.
#
# WHY A LAUNCHER. The game writes Options.Dat, save/ and logs/ beside itself and
# finds mod/ by argv[0], so it must run from its own directory. A Steam non-Steam
# shortcut can start it from any working directory, so incursion.sh fixes the cwd
# first. This is the wrapper a handheld install needs and package_macos.sh omits.
#
# Usage:
#     tools/package_linux.sh          build in Docker, assemble, tar, verify
#
# The AppleDouble hazard this guards against: tar on macOS can embed extended
# attributes as ._* sidecar files, and one such file (._Incursion.Mod) once
# crashed the module loader with "File Version Mismatch". The loader now skips
# dotfiles (src/Wposix.cpp), but this script also refuses to ship a tarball that
# contains any ._* entry, so the two defences are independent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IMAGE="incursion-linux:bullseye"        # same image as tools/check_linux_build.sh
PLATFORM="linux/amd64"
NAME="incursion-steamdeck-x86_64"
DIST="$ROOT/dist"
PKG="$DIST/$NAME"
TARBALL="$DIST/$NAME.tar.gz"

command -v docker >/dev/null || { echo "FAIL: docker is not installed"; exit 1; }
docker info >/dev/null 2>&1 || { echo "FAIL: the docker daemon is not running"; exit 1; }

# ------------------------------------------------------------------ image ----
# Build the Debian 11 image on first run only. Identical recipe to
# check_linux_build.sh, so a machine that has run the check already has it.
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "=== building $IMAGE (first run only) ==="
    IMGTMP="$(mktemp -d)"
    cat > "$IMGTMP/Dockerfile" <<'DOCKERFILE'
FROM --platform=linux/amd64 debian:11
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential clang pkg-config zlib1g-dev libncurses-dev \
        libsdl2-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
DOCKERFILE
    docker build --platform "$PLATFORM" -t "$IMAGE" -q -f "$IMGTMP/Dockerfile" "$IMGTMP" >/dev/null \
        || { echo "FAIL: could not build $IMAGE"; rm -rf "$IMGTMP"; exit 1; }
    rm -rf "$IMGTMP"
fi

# ------------------------------------------------------------------ build ----
# Export the WORKING TREE (tracked files at their working-tree content), never a
# bind mount of ROOT: a bind mount would let the container's Linux objects and a
# Linux-built module land in the developer's own build/ and mod/, and the next
# macOS build would then link a mixture. check_linux_build.sh takes the same care.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
echo "=== 1/5  exporting the working tree ==="
git ls-files -z | xargs -0 tar -cf - 2>/dev/null | tar -x -C "$STAGE" \
    || { echo "FAIL: could not export the working tree"; exit 1; }

echo "=== 2/5  building in $IMAGE (developer binary, module, shipping binary) ==="
# SDL_VIDEODRIVER=dummy because the libtcod binary initialises SDL video even to
# run -compile, and a container has no display.
docker run --rm --platform "$PLATFORM" \
        -e SDL_VIDEODRIVER=dummy -e SDL_AUDIODRIVER=dummy \
        -v "$STAGE:/src" "$IMAGE" sh -c '
    set -e
    # Developer binary. build_macos.sh auto-runs "-compile main.irc" for a dev
    # build, so this also writes mod/Incursion.Mod.
    CC=clang CXX=clang++ ./build_macos.sh >/dev/null 2>&1 || { echo "DEV-BUILD-FAILED"; exit 1; }
    [ -f mod/Incursion.Mod ] || { echo "NO-MODULE"; exit 1; }
    # Shipping binary: no compiler, no ACCENT runtime.
    CC=clang CXX=clang++ COMPILER=no OUT=incursion-ship ./build_macos.sh >/dev/null 2>&1 \
        || { echo "SHIP-BUILD-FAILED"; exit 1; }
    [ -f incursion-ship ] || { echo "NO-SHIP-BINARY"; exit 1; }
' || { echo "FAIL: the Linux build failed inside the container"; exit 1; }

[ -f "$STAGE/incursion-ship" ]    || { echo "FAIL: no shipping binary came out of the build"; exit 1; }
[ -f "$STAGE/mod/Incursion.Mod" ] || { echo "FAIL: no module came out of the build"; exit 1; }

# --------------------------------------------------------------- assemble ----
echo "=== 3/5  assembling $PKG ==="
rm -rf "$PKG"
mkdir -p "$PKG/mod" "$PKG/fonts" "$PKG/save" "$PKG/logs"

cp "$STAGE/incursion-ship"     "$PKG/incursion"
chmod +x "$PKG/incursion"
cp "$STAGE/mod/Incursion.Mod"  "$PKG/mod/"
cp "$ROOT"/fonts/*.png         "$PKG/fonts/"
cp "$ROOT/Options.Dat"         "$PKG/"
cp "$ROOT/LICENSE"             "$PKG/"
cp "$ROOT/Incursion.txt"       "$PKG/"

# The launcher. readlink -f resolves a symlinked shortcut target to the real
# install directory before cd, so the game always runs beside its own data.
cat > "$PKG/incursion.sh" <<'LAUNCH'
#!/bin/bash
# Incursion writes Options.Dat, save/ and logs/ next to the binary and finds
# mod/ by argv[0], so it must run from its own directory. Point a Steam shortcut
# or a launcher at THIS script, not at ./incursion directly.
cd "$(dirname "$(readlink -f "$0")")" || exit 1
exec ./incursion "$@"
LAUNCH
chmod +x "$PKG/incursion.sh"

# ---------------------------------------------------------- clean the tree ----
# Strip extended attributes that macOS or the Docker bind mount may have left on
# the staged files (com.apple.provenance, com.docker.grpcfuse.ownership). With no
# xattrs present, bsdtar has nothing to encode as ._* AppleDouble sidecars.
if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$PKG" 2>/dev/null || true
fi
# And remove any that already exist, belt to the xattr braces.
find "$PKG" -name '._*' -delete 2>/dev/null || true
find "$PKG" -name '.DS_Store' -delete 2>/dev/null || true

# ------------------------------------------------------------------- tar ----
echo "=== 4/5  writing $TARBALL ==="
# COPYFILE_DISABLE=1 stops Apple's tar from writing resource forks as ._* members;
# --exclude drops any that slipped through. The archive holds one top-level
# directory, so it extracts to ./incursion-steamdeck-x86_64/.
rm -f "$TARBALL"
COPYFILE_DISABLE=1 tar --exclude='._*' --exclude='.DS_Store' \
    -C "$DIST" -czf "$TARBALL" "$NAME"

# ----------------------------------------------------------------- verify ----
echo "=== 5/5  verifying the tarball ==="
# The whole point: no AppleDouble sidecar may reach a downloader. A single ._*
# entry is a hard failure, not a warning.
SIDECARS="$(tar -tzf "$TARBALL" | grep -E '(^|/)\._|(^|/)\.DS_Store' || true)"
if [ -n "$SIDECARS" ]; then
    echo "FAIL: the tarball still contains AppleDouble/junk entries:"
    echo "$SIDECARS"
    exit 1
fi
# The payload a run cannot start without.
for want in "$NAME/incursion" "$NAME/mod/Incursion.Mod" "$NAME/incursion.sh"; do
    tar -tzf "$TARBALL" | grep -qx "$want" \
        || { echo "FAIL: the tarball is missing $want"; exit 1; }
done

echo "PASS: $TARBALL is clean (no ._* entries) and carries the binary, module and launcher."
echo "Tarball: $TARBALL"
echo "Folder:  $PKG"
