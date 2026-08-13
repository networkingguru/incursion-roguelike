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

OBJ="$ROOT/build/obj"
mkdir -p "$OBJ" "$ROOT/mod" "$ROOT/logs" "$ROOT/save"

SDL_CFLAGS="$(pkg-config --cflags sdl2)"
SDL_LIBS="$(pkg-config --libs sdl2)"
INCLUDES="-Iinc -Ilib -Ilibtcod/include -Icompat $SDL_CFLAGS"
DEFINES="-DDEBUG -DLIBTCOD_TERM"

# ---------------------------------------------------------------- libtcod ----
# Built from the vendored copy. The bundled zlib is too old to compile against
# a modern SDK (it redefines fdopen), so it is skipped in favour of system -lz.
TCODLIB="$ROOT/build/libtcod_local.a"
if [ ! -f "$TCODLIB" ]; then
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
CXXFLAGS="-O2 -w -fpermissive -Wno-narrowing $DEFINES $INCLUDES"
CFLAGS="-O2 -w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-return-mismatch -DDEBUG -Iinc -Ilib -Icompat"

for f in src/*.cpp; do
    n="$(basename "$f" .cpp)"
    # Wcurses is the Windows/pdcurses terminal backend; the libtcod one is used here.
    [ "$n" = "Wcurses" ] && continue
    std="c++17"
    case "$n" in Tokens|Art) std="c++14" ;; esac
    clang++ -std=$std $CXXFLAGS -c "$f" -o "$OBJ/$n.o"
done

for f in src/*.c; do
    n="$(basename "$f" .c)"
    clang -std=gnu89 $CFLAGS -c "$f" -o "$OBJ/c_$n.o"
done

echo "--- linking ---"
clang++ -std=c++17 -o "$ROOT/incursion" "$OBJ"/*.o "$TCODLIB" $SDL_LIBS -lz -framework OpenGL

# ------------------------------------------------------------- game data -----
if [ ! -f "$ROOT/mod/Incursion.Mod" ]; then
    echo "--- compiling game data module (this takes ~5s) ---"
    "$ROOT/incursion" -compile main.irc
fi

echo
echo "Built: $ROOT/incursion"
echo "Data:  $ROOT/mod/Incursion.Mod"
