#!/bin/bash
# Run ANY scripted headless session on Linux, in a Docker container, and leave
# its output, save files and logs on the host. (bd inc-eikp.4)
#
# Usage:
#   INCURSION_OPTIONS=<options file> tools/linux_run.sh \
#       [--distro debian11|arch] [--cc clang|gcc] [--load <save file>] \
#       [--name <run name>] <keys> [seed]
#
# WHY. There is no Linux machine attached to this project, and the Linux tester
# who reports "saves do not load on x64 Linux", "ASSERT(h <= LastUsedHandle) in
# Registry::GetQuiet", and "Illegal system object number" during a module
# compile gives us no way to reproduce any of it here. Docker on this arm64 Mac
# runs linux/amd64 containers, which execute real x86-64 code, so any seeded
# session can be played there. This script is that runner; check_linux_build.sh
# remains the fixed smoke check, and this one takes arbitrary keys, a compiler
# and an optional save.
#
# THE BUILD CACHE. Emulated builds take minutes, so the exported, BUILT tree is
# kept per distro+compiler at logs/linux/<distro>-<cc>/src and bind-mounted into
# the container. A hash of the exported tracked content sits beside it, and the
# tree is re-exported and rebuilt ONLY when that hash changes -- two launches in
# a row must not both rebuild. The bind mount is of an EXPORT, not of the
# checkout, so the container owning it is exactly what we want (contrast
# tools/check_linux_build.sh, which uses a throwaway export precisely so nothing
# persists). The build's own output goes to logs/linux/<distro>-<cc>/build.log,
# beside the cache and therefore outside the tree a rebuild deletes, so the log
# of a failed build survives to be read.
#
# RUN DIRECTORIES LIVE OUTSIDE THE CACHE. Runs are written to
# logs/linux/runs/<name>, NOT under the cached tree, and that directory is
# bind-mounted into the container on its own at /runs. A rebuild deletes and
# re-exports $SRC; a run directory kept inside it would be destroyed by the
# first tree change after a session, taking that session's saves and logs with
# it. A rebuild MUST NOT touch logs/linux/runs/.
#
# --cc gcc IS ALLOWED ON PURPOSE. GCC -O2 once corrupted object handles during
# character creation (inc-nw0v) and check_linux_build.sh tells you not to switch
# to gcc to green a red run. Here the opposite: being able to build with gcc is
# the point, so the corruption can be seen.
#
# INCURSION_GCC_RAW_DSE IS PART OF THE CACHE IDENTITY. build_macos.sh applies
# -flifetime-dse=1 to every GCC build (inc-eikp.3), which MASKS unassigned
# members; INCURSION_GCC_RAW_DSE=1 omits that flag so a guard can see them. The
# two produce different binaries from the same tree, so they must never share a
# cache dir or hash file: the flag is folded into CACHE below. It is passed into
# the container only when set (default off), so an ordinary run is unmasked-GCC
# for gcc and unaffected for clang.
#
# Exit: headless.sh's own exit code inside the container, or 2 when docker or
#       the environment is not there to run at all.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

. "$ROOT/tools/linux_docker.sh"

PLATFORM="linux/amd64"

DISTRO=debian11
CC=clang
LOAD=""
NAME=""

usage() {
    echo "usage: INCURSION_OPTIONS=<options file> tools/linux_run.sh \\"
    echo "           [--distro debian11|arch] [--cc clang|gcc] [--load <save file>] \\"
    echo "           [--name <run name>] <keys> [seed]"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --distro) DISTRO="${2:-}"; shift 2 ;;
        --cc)     CC="${2:-}";     shift 2 ;;
        --load)   LOAD="${2:-}";   shift 2 ;;
        --name)   NAME="${2:-}";   shift 2 ;;
        -h|--help) usage; exit 2 ;;
        --) shift; break ;;
        -*) echo "unknown option: $1" >&2; usage; exit 2 ;;
        *) break ;;
    esac
done

KEYS="${1:-}"
SEED="${2:-}"

if [ -z "$KEYS" ]; then usage; exit 2; fi
if [ ! -f "$KEYS" ]; then
    echo "no such key script: $KEYS"
    exit 2
fi

case "$DISTRO" in
    debian11|arch) ;;
    *) echo "--distro must be debian11 or arch (got '$DISTRO')" >&2; exit 2 ;;
esac
case "$CC" in
    clang|gcc) ;;
    *) echo "--cc must be clang or gcc (got '$CC')" >&2; exit 2 ;;
esac

# The raw-DSE opt-out changes GCC codegen, so it is part of the cache key. The
# default is off (masked), matching build_macos.sh. Fold a distinct suffix in
# for the raw build so the two never overwrite each other's binary or hash.
RAW_DSE="${INCURSION_GCC_RAW_DSE:-0}"
CACHE_SUFFIX=""
if [ "$RAW_DSE" = "1" ]; then
    CACHE_SUFFIX="-rawdse"
    export INCURSION_GCC_RAW_DSE=1
fi

# INCURSION_OPTIONS is mandatory, exactly as it is for headless.sh: settings are
# an input to the result and there is no default.
if [ -z "${INCURSION_OPTIONS:-}" ]; then
    echo "INCURSION_OPTIONS is required; choose a settings file from tools/fixtures/"
    exit 2
fi
if [ ! -f "$INCURSION_OPTIONS" ]; then
    echo "INCURSION_OPTIONS names a file that is not there: $INCURSION_OPTIONS"
    exit 2
fi
if [ -n "$LOAD" ] && [ ! -f "$LOAD" ]; then
    echo "--load names a file that is not there: $LOAD"
    exit 2
fi

# Same wording as check_linux_build.sh's SKIP lines.
linux_docker_preflight || exit 2

# The default run name follows check_linux_build.sh/headless.sh's shape: which
# distro, which compiler, which key script, which seed, and when. The pid is
# part of the stamp for the same reason headless.sh carries it: two runs in the
# same second would otherwise share a directory, and one run must be one
# directory.
if [ -z "$NAME" ]; then
    NAME="$DISTRO-$CC$CACHE_SUFFIX-$(basename "$KEYS" .keys)-${SEED:-clock}-$(date +%Y%m%d-%H%M%S)-$$"
fi

CACHE="$ROOT/logs/linux/$DISTRO-$CC$CACHE_SUFFIX"
SRC="$CACHE/src"
HASHFILE="$CACHE/tree.sha256"
BUILD_LOG="$CACHE/build.log"
# Outside CACHE/SRC on purpose: a rebuild wipes and re-exports $SRC, and a run
# directory kept under it would be deleted by the first tree change after the
# session (see the header).
RUNS_DIR="$ROOT/logs/linux/runs"
RUN_HOST="$RUNS_DIR/$NAME"

# One run, one directory. A reused directory would merge two sessions' save/
# and logs/ under one name and read as a single longer session -- the exact
# shape that produced the first wrong inc-90u follower count.
if [ -e "$RUN_HOST" ]; then
    echo "refusing to reuse run directory $RUN_HOST (one run, one directory)"
    exit 2
fi

# A hash of the tracked working-tree content. git ls-files is already sorted, so
# the digest is stable for a given tree; the per-file sha256 records the PATH as
# well as the bytes, so a rename counts as a change.
tree_hash() {
    git ls-files -z | xargs -0 shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}'
}

WANT_HASH="$(tree_hash)"
HAVE_HASH=""
[ -f "$HASHFILE" ] && HAVE_HASH="$(cat "$HASHFILE")"

REBUILD=0
if [ "$WANT_HASH" != "$HAVE_HASH" ]; then
    REBUILD=1
elif [ ! -x "$SRC/incursion-headless" ]; then
    REBUILD=1
fi

if [ "$REBUILD" -eq 1 ]; then
    echo "--- exporting working tree and building (hash changed or first run) ---"
    rm -rf "$SRC"
    linux_export_tree "$SRC" || exit 2
    linux_ensure_image "$DISTRO" || exit 2

    if [ "$CC" = "gcc" ]; then
        BUILD_CC="gcc"; BUILD_CXX="g++"
    else
        BUILD_CC="clang"; BUILD_CXX="clang++"
    fi

    # The build output goes to $BUILD_LOG, beside the cache and outside $SRC, so
    # a failed attempt leaves evidence that the next rebuild does not delete.
    # Overwritten on every build. On failure the tail is printed here, so the
    # reason is visible without opening the file.
    docker run --rm --platform "$PLATFORM" \
        -e SDL_VIDEODRIVER=dummy -e SDL_AUDIODRIVER=dummy \
        -v "$SRC:/src" "$(linux_image_tag "$DISTRO")" sh -c '
        set -e
        CC='"'$BUILD_CC'"' CXX='"'$BUILD_CXX'"' INCURSION_GCC_RAW_DSE='"'$RAW_DSE'"' BACKEND=posix ./build_macos.sh
    ' >"$BUILD_LOG" 2>&1 || {
        echo "FAIL: the posix build failed"
        echo "--- last 30 lines of $BUILD_LOG ---"
        tail -30 "$BUILD_LOG" | sed 's/^/  /'
        echo "full build log: $BUILD_LOG"
        exit 2
    }

    printf '%s\n' "$WANT_HASH" > "$HASHFILE"
else
    echo "--- reusing built tree (tree hash unchanged) ---"
fi

# The image is needed even on a cache hit (the tree is built, but the container
# still has to exist). The run directory is created on the host OUTSIDE the
# cached tree and bind-mounted into the container on its own at /runs, so the
# session's save/ and logs/ land there and a later rebuild cannot delete them.
linux_ensure_image "$DISTRO" || exit 2
mkdir -p "$RUN_HOST"

# A save to load must be visible inside the container. Copy it under the
# exported tree and pass that container path; headless.sh then copies it into
# its own sandbox, so the original is never played in place.
LOAD_ARGS=()
if [ -n "$LOAD" ]; then
    LOAD_DIR="$SRC/logs/linux/loads"
    mkdir -p "$LOAD_DIR"
    LOAD_BASE="$(basename "$LOAD")"
    cp -f "$LOAD" "$LOAD_DIR/$LOAD_BASE" || {
        echo "FAIL: could not copy $LOAD into the container tree"; exit 2; }
    chmod u+w "$LOAD_DIR/$LOAD_BASE"
    LOAD_ARGS=(-e "INCURSION_LOAD=/src/logs/linux/loads/$LOAD_BASE")
fi

# INCURSION_OPTIONS names a HOST file, which the container cannot see. Copy it
# into the same container-visible staging area as the load (the exported tree)
# and pass the container path to headless.sh, which copies it into the run's
# own Options.Dat. An absolute path or an untracked file would otherwise be
# invisible inside the container.
OPTIONS_DIR="$SRC/logs/linux/options"
mkdir -p "$OPTIONS_DIR"
OPTIONS_BASE="$(basename "$INCURSION_OPTIONS")"
cp -f "$INCURSION_OPTIONS" "$OPTIONS_DIR/$OPTIONS_BASE" || {
    echo "FAIL: could not copy $INCURSION_OPTIONS into the container tree"; exit 2; }
chmod u+w "$OPTIONS_DIR/$OPTIONS_BASE"
OPTIONS_IN="/src/logs/linux/options/$OPTIONS_BASE"

# headless.sh needs its own key script visible inside the exported tree. A key
# script under the repository is already in the export; one from anywhere else
# is copied in beside the loads, so a private script can be run there too.
KEYS_ABS="$KEYS"
case "$KEYS" in
    /*) KEYS_ABS="$KEYS" ;;
    *)  KEYS_ABS="$ROOT/$KEYS" ;;
esac
if [ -f "$SRC/$KEYS" ]; then
    KEYS_IN="/src/$KEYS"
else
    KEYS_DIR="$SRC/logs/linux/keys"
    mkdir -p "$KEYS_DIR"
    cp -f "$KEYS_ABS" "$KEYS_DIR/$(basename "$KEYS")" || {
        echo "FAIL: could not copy $KEYS into the container tree"; exit 2; }
    KEYS_IN="/src/logs/linux/keys/$(basename "$KEYS")"
fi

docker run --rm --platform "$PLATFORM" \
    -e SDL_VIDEODRIVER=dummy -e SDL_AUDIODRIVER=dummy \
    -e "INCURSION_OPTIONS=$OPTIONS_IN" \
    -e "INCURSION_RUN_DIR=/runs/$NAME" \
    ${LOAD_ARGS[@]+"${LOAD_ARGS[@]}"} \
    -v "$SRC:/src" -v "$RUN_HOST:/runs/$NAME" \
    "$(linux_image_tag "$DISTRO")" \
    sh -c 'tools/headless.sh '"$KEYS_IN"' '"${SEED:-}" 2>&1
STATUS=$?

echo "linux-run: $RUN_HOST"
exit "$STATUS"
