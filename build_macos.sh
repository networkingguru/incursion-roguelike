#!/bin/bash
# Build Incursion for macOS (arm64). Reproduces the first working POSIX build.
#
# Requires: Xcode command line tools, and SDL2 + pkg-config from Homebrew:
#     brew install sdl2 pkg-config
#
# Produces:  ./incursion         the game binary
#            ./mod/Incursion.Mod the compiled game data module
#
# Notes on the flags below -- each one exists for a specific reason:
#   -DDEBUG          src/RComp.cpp is wrapped in #ifdef DEBUG, but src/yygram.cpp
#                    calls into it unconditionally. Without this the link fails
#                    with undefined symbols (AllocString, LockString, ...).
#   -Icompat         supplies <malloc.h>, which macOS does not have.
#   c++14 for two    src/Tokens.cpp and src/Art.cpp use the `register` keyword,
#   files            which C++17 removed. They are flex/ACCENT output.
#   gnu89 for *.c    src/cpp1-6.c are a K&R-era C preprocessor (DECUS cpp).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# A diagnostic build gets its own binary and its own object directory, so it
# never leaves half-instrumented objects behind for the next ordinary build:
#     EXTRA_CXXFLAGS=-DFLICKER_PROBE OUT=incursion-flicker ./build_macos.sh
# Which terminal backend to compile in. Only one can be linked at a time --
# each defines main(), Error() and Fatal().
#   libtcod  the SDL window build; the way to play.
#   posix    src/Wposix.cpp, which needs neither SDL nor libtcod and can run
#            with no display and no keyboard. See docs/HEADLESS-SPEC.md.
BACKEND="${BACKEND:-libtcod}"

case "$BACKEND" in
    libtcod) OUT="${OUT:-incursion}" ;;
    posix)   OUT="${OUT:-incursion-headless}" ;;
    *)       echo "Unknown BACKEND '$BACKEND' (want libtcod or posix)"; exit 1 ;;
esac
EXTRA_CXXFLAGS="${EXTRA_CXXFLAGS:-}"

if [ "$OUT" = "incursion" ] && [ -z "$EXTRA_CXXFLAGS" ]; then
    OBJ="$ROOT/build/obj"
else
    OBJ="$ROOT/build/obj-$OUT"
fi
mkdir -p "$OBJ" "$ROOT/mod" "$ROOT/logs" "$ROOT/save"

if [ "$BACKEND" = posix ]; then
    SDL_CFLAGS=""
    SDL_LIBS=""
    INCLUDES="-Iinc -Ilib -Icompat"
    DEFINES="-DDEBUG -DPOSIX_TERM"
    SKIP_BACKENDS="Wlibtcod Wcurses"
    # ncurses ships with macOS and with every Linux distribution, so this adds
    # no dependency to install. It is used only to draw to a real terminal;
    # a headless run never calls into it.
    LINK_LIBS="-lz -lncurses"
else
    SDL_CFLAGS="$(pkg-config --cflags sdl2)"
    SDL_LIBS="$(pkg-config --libs sdl2)"
    INCLUDES="-Iinc -Ilib -Ilibtcod/include -Icompat $SDL_CFLAGS"
    DEFINES="-DDEBUG -DLIBTCOD_TERM"
    SKIP_BACKENDS="Wcurses Wposix"
    LINK_LIBS="-lz -framework OpenGL"
fi

# ---------------------------------------------------------------- libtcod ----
# Built from the vendored copy. The bundled zlib is too old to compile against
# a modern SDK (it redefines fdopen), so it is skipped in favour of system -lz.
TCODLIB="$ROOT/build/libtcod_local.a"
if [ "$BACKEND" = posix ]; then
    TCODLIB=""
elif [ ! -f "$TCODLIB" ]; then
    echo "--- building vendored libtcod ---"
    TOBJ="$ROOT/build/tcodobj"
    mkdir -p "$TOBJ"
    TFLAGS="-O2 -w -fPIC -DTCOD_SDL2 -DNO_OPENGL $SDL_CFLAGS -Ilibtcod/include -Ilibtcod/src"
    for f in $(find libtcod/src -name '*.c' -o -name '*.cpp'); do
        case "$f" in libtcod/src/zlib/*) continue ;; esac
        o="$TOBJ/$(echo "$f" | tr '/' '_').o"
        if [ "${f##*.}" = "c" ]; then
            clang $TFLAGS -c "$f" -o "$o"
        else
            clang++ $TFLAGS -fpermissive -c "$f" -o "$o"
        fi
    done
    ar rcs "$TCODLIB" "$TOBJ"/*.o
fi

# ------------------------------------------------------------------ game -----
echo "--- compiling Incursion ---"
CXXFLAGS="-O2 -w -fpermissive -Wno-narrowing $DEFINES $INCLUDES $EXTRA_CXXFLAGS"
CFLAGS="-O2 -w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-return-mismatch -DDEBUG -Iinc -Ilib -Icompat"

for f in src/*.cpp; do
    n="$(basename "$f" .cpp)"
    # Only one backend links: each defines main(), Error() and Fatal().
    skip=
    for b in $SKIP_BACKENDS; do [ "$n" = "$b" ] && skip=1; done
    [ -n "$skip" ] && continue
    std="c++17"
    case "$n" in Tokens|Art) std="c++14" ;; esac
    clang++ -std=$std $CXXFLAGS -c "$f" -o "$OBJ/$n.o"
done

for f in src/*.c; do
    n="$(basename "$f" .c)"
    clang -std=gnu89 $CFLAGS -c "$f" -o "$OBJ/c_$n.o"
done

echo "--- linking ---"
clang++ -std=c++17 -o "$ROOT/$OUT" "$OBJ"/*.o $TCODLIB $SDL_LIBS $LINK_LIBS

# ------------------------------------------------------------- game data -----
if [ ! -f "$ROOT/mod/Incursion.Mod" ]; then
    echo "--- compiling game data module (this takes ~5s) ---"
    "$ROOT/$OUT" -compile main.irc
fi

echo
echo "Built: $ROOT/$OUT"
echo "Data:  $ROOT/mod/Incursion.Mod"
