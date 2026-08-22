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
#   -DDEBUG          builds the DEVELOPER binary: it carries the resource
#                    compiler, so it can turn lib/*.irh into mod/Incursion.Mod.
#                    See COMPILER below for why a shipped binary must not.
#   -Icompat         supplies <malloc.h>, which macOS does not have.
#   c++14 for two    src/Tokens.cpp and src/Art.cpp use the `register` keyword,
#   files            which C++17 removed. They are flex/ACCENT output.
#   gnu89 for *.c    src/cpp1-6.c are a K&R-era C preprocessor (DECUS cpp).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# A diagnostic build gets its own binary and its own object directory, so it
# never leaves half-instrumented objects behind for the next ordinary build:
#     EXTRA_CXXFLAGS=-DPATH_PROBE OUT=incursion-path ./build_macos.sh
#
# Pick a real probe as the example, not a broken one. This line used to name
# -DFLICKER_PROBE, which was the only probe the build script mentioned and was
# also the one instrument in the tree that could not see the defect it was
# built for. It is deleted now; see docs/DEVTOOLS-AUDIT.md.
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

# Is the resource compiler part of this binary?
#
#   COMPILER=yes  (default)  the developer build. It can run -compile main.irc
#                            to produce mod/Incursion.Mod, and it is what every
#                            tool in tools/ expects.
#   COMPILER=no              a SHIPPABLE build. No compiler, no parser, no
#                            preprocessor.
#
# THIS IS NOT A SIZE OPTIMISATION. src/Art.cpp is the ACCENT parser runtime, and
# its own header says, at src/Art.cpp:2-7, that it is GPLv2 and "cannot be
# compiled into any distributed binaries, otherwise it will be a GPL violation".
# Every macOS binary built before 2026-08-16 contained it, because -DDEBUG was
# unconditional here. See inc-9df.5.
#
# WHY WHOLE FILES ARE EXCLUDED RATHER THAN LEFT TO #ifdef. src/RComp.cpp and
# src/Art.cpp are each wrapped in one #ifdef DEBUG and would compile to nothing
# anyway -- but src/yygram.cpp and src/Tokens.cpp are NOT wrapped, and they call
# AllocString() and AllocRegister() (src/yygram.cpp:7857, :8548), which live
# inside the block that just vanished. That undefined-symbol link failure is the
# whole reason -DDEBUG was pinned on here in the first place. Windows solved it
# the same way: build.bat:93 filters yygram.cpp, tokens.cpp and cpp*.c out of a
# Release build.
#
# WHAT ELSE DROPPING -DDEBUG CHANGES, and all three are what a shipped game
# should do:
#   src/Player.cpp:683    wizard mode starts honouring the OPT_DISALLOW game
#                         option instead of ignoring it
#   src/Main.cpp:2174     the "(Debugging Commands)" entry leaves the start menu
#   src/Wlibtcod.cpp:476  Breakpad crash reporting is enabled -- Windows only,
#                         since USE_BREAKPAD is not defined here
COMPILER="${COMPILER:-yes}"
case "$COMPILER" in
    yes|no) ;;
    *) echo "Unknown COMPILER '$COMPILER' (want yes or no)"; exit 1 ;;
esac
EXTRA_CXXFLAGS="${EXTRA_CXXFLAGS:-}"
# Some diagnostics have to reach the linker as well as the compiler --
# AddressSanitizer is the one that made this necessary:
#   EXTRA_CXXFLAGS="-fsanitize=address -g" EXTRA_LDFLAGS=-fsanitize=address \
#   BACKEND=posix OUT=incursion-asan ./build_macos.sh
EXTRA_LDFLAGS="${EXTRA_LDFLAGS:-}"

# The object directory must encode every flag that changes what an object IS.
# COMPILER belongs in it: a shipping build and a developer build differ by
# -DDEBUG, and -DDEBUG changes real code in Player.cpp and Main.cpp, so sharing
# a directory would link a mixture of the two and the result would be neither.
if [ "$OUT" = "incursion" ] && [ -z "$EXTRA_CXXFLAGS" ] && [ "$COMPILER" = yes ]; then
    OBJ="$ROOT/build/obj"
elif [ "$COMPILER" = no ]; then
    OBJ="$ROOT/build/obj-$OUT-nocompiler"
else
    OBJ="$ROOT/build/obj-$OUT"
fi
mkdir -p "$OBJ" "$ROOT/mod" "$ROOT/logs" "$ROOT/save"

if [ "$COMPILER" = yes ]; then
    DEBUG_DEFINE="-DDEBUG"
    # The compiler, the parser it generates, and the preprocessor it feeds.
    SKIP_SOURCES=""
else
    DEBUG_DEFINE=""
    SKIP_SOURCES="RComp Art yygram Tokens"
fi

if [ "$BACKEND" = posix ]; then
    SDL_CFLAGS=""
    SDL_LIBS=""
    INCLUDES="-Iinc -Ilib -Icompat"
    DEFINES="$DEBUG_DEFINE -DPOSIX_TERM"
    SKIP_BACKENDS="Wlibtcod Wcurses"
    # ncurses ships with macOS and with every Linux distribution, so this adds
    # no dependency to install. It is used only to draw to a real terminal;
    # a headless run never calls into it.
    LINK_LIBS="-lz -lncurses"
else
    SDL_CFLAGS="$(pkg-config --cflags sdl2)"
    SDL_LIBS="$(pkg-config --libs sdl2)"
    INCLUDES="-Iinc -Ilib -Ilibtcod/include -Icompat $SDL_CFLAGS"
    DEFINES="$DEBUG_DEFINE -DLIBTCOD_TERM"
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
CFLAGS="-O2 -w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-return-mismatch $DEBUG_DEFINE -Iinc -Ilib -Icompat"

for f in src/*.cpp; do
    n="$(basename "$f" .cpp)"
    # Only one backend links: each defines main(), Error() and Fatal().
    skip=
    for b in $SKIP_BACKENDS; do [ "$n" = "$b" ] && skip=1; done
    # And, in a shipping build, the resource compiler and everything it drags in.
    for b in $SKIP_SOURCES; do [ "$n" = "$b" ] && skip=1; done
    [ -n "$skip" ] && continue
    std="c++17"
    case "$n" in Tokens|Art) std="c++14" ;; esac
    clang++ -std=$std $CXXFLAGS -c "$f" -o "$OBJ/$n.o"
done

# src/cpp1-6.c are the DECUS preprocessor, used only by -compile, so a shipping
# binary leaves them out. src/lz.c and src/rle.c must NOT go with them: they are
# the compression Registry uses to read a save or a module at run time
# (src/Term.cpp, CFile::LoadCompressed), and dropping them fails the link with
# four undefined symbols that look like compiler leftovers and are not.
for f in src/*.c; do
    n="$(basename "$f" .c)"
    if [ "$COMPILER" = no ]; then
        case "$n" in cpp[1-6]) continue ;; esac
    fi
    clang -std=gnu89 $CFLAGS -c "$f" -o "$OBJ/c_$n.o"
done

echo "--- linking ---"
clang++ -std=c++17 $EXTRA_LDFLAGS -o "$ROOT/$OUT" "$OBJ"/*.o $TCODLIB $SDL_LIBS $LINK_LIBS

# ------------------------------------------------------------- game data -----
# A shipping binary cannot build its own data: that is the point of it. The
# module has to come from a developer build of the SAME source, because
# Registry writes raw struct bytes and the file is welded to the layout of the
# binary that produced it.
# NOTHING DETECTS A MODULE THAT HAS FALLEN BEHIND ITS SCRIPTS. Registry stamps
# every file with a layout digest (src/Registry.cpp:65) and refuses a mismatch,
# so a module built by a DIFFERENT struct layout is caught. A module with the
# right layout and last week's rules is not: it loads in silence. Gating the
# compile on the file being ABSENT therefore let a script-only fix build clean
# and change nothing in the game -- twice on 2026-08-22, once nearly reported
# as a fix. See inc-nx6c.
#
# So an ordinary developer build recompiles it every time. Five seconds is
# cheaper than one fix that fixed nothing, and it needs no freshness test to be
# right: it also covers the case that a date stamp or a hash of the scripts
# would BOTH miss, which is a change to the resource compiler itself building a
# different module out of identical scripts.
#
# Instrumented builds (EXTRA_CXXFLAGS set) keep the old absence-gate on
# purpose. They share this one module file with the ordinary build, so a flag
# that moved a struct would leave behind a module the ordinary binary then
# refuses to load.
if [ ! -f "$ROOT/mod/Incursion.Mod" ] || { [ -z "$EXTRA_CXXFLAGS" ] && [ "$COMPILER" = yes ]; }; then
    if [ "$COMPILER" = no ]; then
        echo
        echo "No mod/Incursion.Mod, and this build has no resource compiler."
        echo "Build the developer binary first, which will produce it:"
        echo "    ./build_macos.sh"
        exit 1
    fi
    echo "--- compiling game data module (this takes ~5s) ---"
    "$ROOT/$OUT" -compile main.irc
fi

echo
echo "Built: $ROOT/$OUT"
echo "Data:  $ROOT/mod/Incursion.Mod"
if [ "$COMPILER" = no ]; then
    echo
    echo "This is a SHIPPING build: no resource compiler, no GPLv2 ACCENT"
    echo "runtime, and -compile will not work. Confirm with:"
    echo "    nm '$ROOT/$OUT' | grep -c 'yyparse\|yyselect\|yymallocerror'"
    echo "expecting 0. Those three are every function src/Art.cpp defines, and"
    echo "Art.cpp is the GPLv2 file. Do not grep for 'accent' -- none of the"
    echo "symbols carry that word, so it reports 0 either way."
fi
