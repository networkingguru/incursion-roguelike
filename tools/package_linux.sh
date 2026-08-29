#!/bin/bash
# Produce the two Linux/Steam-Deck tarballs the rolling `alpha` release ships:
#   dist/incursion-steamdeck-x86_64.tar.gz  -> extracts to incursion-deck/
#   dist/incursion-linux-x86_64.tar.gz      -> extracts to incursion-linux/
#
# This is the Linux sibling of tools/package_macos.sh. It ships the same payload
# (the game, its data module, its fonts) but for x86_64 Linux, built the only way
# this project can from a Mac: inside the Debian 11 container that
# tools/check_linux_build.sh already defines.
#
# TWO BUNDLES, ONE BUILD.
#   incursion-deck/   The Steam Deck bundle. SteamOS ships its own libSDL2, so
#                     this one carries no SDL2. Run with ./incursion, or point a
#                     Steam non-Steam shortcut at incursion.sh (it fixes the cwd).
#   incursion-linux/  The generic-distro bundle. It carries libSDL2-2.0.so.0 in
#                     libs/ and a run.sh that sets LD_LIBRARY_PATH, so it runs on
#                     a machine that has no SDL2 installed.
# The same shipping binary and module go into both; only SDL2 and the launcher
# differ. Keeping both in one script means one Docker build feeds both, and the
# ._* / xattr defences below cover both the same way.
#
# WHY DOCKER, WHY DEBIAN 11, WHY CLANG. There is no Linux machine attached to
# this project, so the release binary is cross-built in a container -- the same
# incursion-linux:bullseye image the Linux regression check uses, so the two
# share one cached image. Debian 11 on purpose: its glibc is the floor of who
# can run the release (a binary links versioned glibc symbols and runs on that
# release and everything newer), and it is the Steam Runtime "sniper" ABI floor.
# Clang on purpose: GCC -O2 miscompiles this engine (inc-nw0v), clang is clean;
# check_linux_build.sh says the same and for the same reason.
#
# WHY IT BUILDS TWICE, like package_macos.sh. The module is a memory image welded
# to the struct layout of the binary that wrote it, and only a DEVELOPER binary
# has the resource compiler (the GPLv2 ACCENT runtime that src/Art.cpp says must
# never ship). So: build the developer binary, let it write mod/Incursion.Mod,
# then build the shipping binary with COMPILER=no. A matching x86_64 developer
# binary must write the x86_64 module -- the macOS module will not do.
#
# WHY A LAUNCHER. The game writes Options.Dat, save/ and logs/ beside itself and
# finds mod/ by argv[0], so it must run from its own directory. A Steam non-Steam
# shortcut can start it from any working directory, so the launcher fixes the cwd
# first. incursion-linux/'s run.sh also exports LD_LIBRARY_PATH for its bundled
# SDL2.
#
# The AppleDouble hazard this guards against: tar on macOS can embed extended
# attributes as ._* sidecar files, and one such file (._Incursion.Mod) once
# crashed the module loader with "File Version Mismatch". The loader now skips
# dotfiles (src/Wposix.cpp), but this script also refuses to ship a tarball that
# contains any ._* entry, so the two defences are independent.
#
# Usage:
#     tools/package_linux.sh          build in Docker, assemble both, tar, verify
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IMAGE="incursion-linux:bullseye"        # same image as tools/check_linux_build.sh
PLATFORM="linux/amd64"
DIST="$ROOT/dist"

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
# run -compile, and a container has no display. The build also verifies the
# shipping binary is GPL-clean and copies out the SDL2 the linux bundle needs,
# both inside the container where nm and ldd read ELF.
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
    # GPL-clean gate, run where nm understands the ELF binary. These three are
    # every function src/Art.cpp defines; any of them means the ACCENT runtime
    # shipped. src/Art.cpp:2-7 is GPLv2 and must not be distributed (inc-9df.5).
    ACC=$(nm incursion-ship 2>/dev/null | grep -c "yyparse\|yyselect\|yymallocerror" || true)
    [ "$ACC" = 0 ] || { echo "ACCENT-IN-SHIP:$ACC"; exit 1; }
    # Copy out the exact libSDL2 the shipping binary loads, resolved through the
    # symlink, for the generic-linux bundle.
    SDL_SO=$(ldd incursion-ship | awk "/libSDL2/ {print \$3}")
    [ -n "$SDL_SO" ] || { echo "NO-SDL2-RESOLVED"; exit 1; }
    cp -L "$SDL_SO" /src/libSDL2-2.0.so.0
' || { echo "FAIL: the Linux build failed inside the container"; exit 1; }

[ -f "$STAGE/incursion-ship" ]        || { echo "FAIL: no shipping binary came out of the build"; exit 1; }
[ -f "$STAGE/mod/Incursion.Mod" ]     || { echo "FAIL: no module came out of the build"; exit 1; }
[ -f "$STAGE/libSDL2-2.0.so.0" ]      || { echo "FAIL: the build copied out no libSDL2"; exit 1; }

mkdir -p "$DIST"

# --------------------------------------------------------------- assemble ----
# One function assembles either bundle. $1 is the top-level directory name the
# tarball unpacks to; $2 is "sdl" for the generic-linux bundle that carries its
# own SDL2 and a run.sh, or "" for the Deck bundle that uses the system SDL2.
assemble() {
    local dir="$1" kind="$2"
    local pkg="$DIST/$dir"
    echo "=== assembling $pkg ==="
    rm -rf "$pkg"
    mkdir -p "$pkg/mod" "$pkg/fonts" "$pkg/save" "$pkg/logs"

    cp "$STAGE/incursion-ship"    "$pkg/incursion"
    chmod +x "$pkg/incursion"
    cp "$STAGE/mod/Incursion.Mod" "$pkg/mod/"
    cp "$ROOT"/fonts/*.png        "$pkg/fonts/"
    # Deliberately NOT Options.Dat. Player::LoadOptions (src/Player.cpp) fills in
    # every option's real default when the file is absent, so a fresh install is
    # correct without it -- and the tree's Options.Dat is an all-NUL file that
    # would instead force every option to zero. Shipping it also overwrote a
    # player's customised options on each rolling-alpha update. Leaving it out
    # fixes both: real defaults on first run, and an update never touches a
    # settings file the player owns.
    cp "$ROOT/LICENSE"            "$pkg/"
    cp "$ROOT/Incursion.txt"      "$pkg/"

    # SteamOS/Linux installer: registers Incursion as a Steam shortcut and writes
    # the controller layout for every supported controller_type. install-steamos.sh
    # substitutes controller_type into incursion-steam-input.vdf, so ship that .vdf
    # at the bundle root under the exact name the installer expects (the repo keeps
    # it under docs/ with an -ally suffix).
    cp "$ROOT/install-steamos.sh"                  "$pkg/"
    chmod +x "$pkg/install-steamos.sh"
    mkdir -p "$pkg/tools"
    cp "$ROOT/tools/steam_shortcut.py"             "$pkg/tools/"
    chmod +x "$pkg/tools/steam_shortcut.py"
    cp "$ROOT/docs/incursion-steam-input-ally.vdf" "$pkg/incursion-steam-input.vdf"

    if [ "$kind" = "sdl" ]; then
        # Generic Linux: carry SDL2 and a launcher that finds it.
        mkdir -p "$pkg/libs"
        cp "$STAGE/libSDL2-2.0.so.0" "$pkg/libs/"
        cat > "$pkg/run.sh" <<'LAUNCH'
#!/bin/bash
# Incursion writes Options.Dat, save/ and logs/ next to the binary and finds
# mod/ by argv[0], so it must run from its own directory. This launcher fixes
# the cwd, then points the loader at the bundled SDL2 in libs/. Start the game
# through THIS script, not ./incursion directly.
cd "$(dirname "$(readlink -f "$0")")" || exit 1
export LD_LIBRARY_PATH="$PWD/libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec ./incursion "$@"
LAUNCH
        chmod +x "$pkg/run.sh"
    else
        # Steam Deck: SteamOS ships SDL2. A launcher only fixes the cwd, so a
        # Steam non-Steam shortcut can start the game from any directory.
        cat > "$pkg/incursion.sh" <<'LAUNCH'
#!/bin/bash
# Incursion writes Options.Dat, save/ and logs/ next to the binary and finds
# mod/ by argv[0], so it must run from its own directory. Point a Steam shortcut
# or a launcher at THIS script, not at ./incursion directly.
cd "$(dirname "$(readlink -f "$0")")" || exit 1
exec ./incursion "$@"
LAUNCH
        chmod +x "$pkg/incursion.sh"
    fi

    # Strip extended attributes that macOS or the Docker bind mount may have left
    # (com.apple.provenance, com.docker.grpcfuse.ownership). With no xattrs
    # present, bsdtar has nothing to encode as ._* AppleDouble sidecars.
    if command -v xattr >/dev/null 2>&1; then
        xattr -cr "$pkg" 2>/dev/null || true
    fi
    find "$pkg" -name '._*' -delete 2>/dev/null || true
    find "$pkg" -name '.DS_Store' -delete 2>/dev/null || true
}

# ------------------------------------------------------------------- tar ----
# COPYFILE_DISABLE=1 stops Apple's tar from writing resource forks as ._* members;
# --exclude drops any that slipped through. --no-xattrs stops libarchive from
# storing macOS xattrs (com.apple.provenance) as LIBARCHIVE.xattr.* headers, which
# GNU tar warns about on extraction ("Ignoring unknown extended header keyword").
# Each archive holds one top-level directory, so it extracts to ./<dir>/.
maketar() {
    local dir="$1" tarball="$2"
    echo "=== writing $tarball ==="
    rm -f "$tarball"
    COPYFILE_DISABLE=1 tar --no-xattrs --exclude='._*' --exclude='.DS_Store' \
        -C "$DIST" -czf "$tarball" "$dir"
}

# ----------------------------------------------------------------- verify ----
# The whole point: no AppleDouble sidecar may reach a downloader, and the payload
# a run cannot start without must be present. $3.. are extra required members.
verify() {
    local dir="$1" tarball="$2"; shift 2
    echo "=== verifying $tarball ==="
    local sidecars
    sidecars="$(tar -tzf "$tarball" | grep -E '(^|/)\._|(^|/)\.DS_Store' || true)"
    if [ -n "$sidecars" ]; then
        echo "FAIL: $tarball still contains AppleDouble/junk entries:"
        echo "$sidecars"
        exit 1
    fi
    local want
    for want in "$dir/incursion" "$dir/mod/Incursion.Mod" "$@"; do
        tar -tzf "$tarball" | grep -qx "$want" \
            || { echo "FAIL: $tarball is missing $want"; exit 1; }
    done
    echo "PASS: $tarball is clean (no ._* entries) and carries its payload."
}

echo "=== 3/5  assembling the two bundles ==="
assemble "incursion-deck"  ""
assemble "incursion-linux" "sdl"

echo "=== 4/5  writing the two tarballs ==="
DECK_TAR="$DIST/incursion-steamdeck-x86_64.tar.gz"
LINUX_TAR="$DIST/incursion-linux-x86_64.tar.gz"
maketar "incursion-deck"  "$DECK_TAR"
maketar "incursion-linux" "$LINUX_TAR"

echo "=== 5/5  verifying the two tarballs ==="
verify "incursion-deck"  "$DECK_TAR"  "incursion-deck/incursion.sh"
verify "incursion-linux" "$LINUX_TAR" "incursion-linux/run.sh" "incursion-linux/libs/libSDL2-2.0.so.0"

echo
echo "PASS: both bundles are clean and complete."
echo "  Steam Deck: $DECK_TAR   (unpacks to incursion-deck/)"
echo "  Generic:    $LINUX_TAR  (unpacks to incursion-linux/)"
