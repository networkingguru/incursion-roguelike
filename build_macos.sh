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
# Which host we are building on. macOS wants clang and an OpenGL framework;
# Linux wants gcc and neither. Both honour $CC/$CXX if the caller sets them.
HOST="$(uname -s)"
case "$HOST" in
    Darwin) CC="${CC:-clang}"; CXX="${CXX:-clang++}"; GUI_LIBS="-framework OpenGL" ;;
    # -ldl -lpthread: libtcod calls dlopen/dlclose and sem_*. macOS has both in
    # libSystem; glibc before 2.34 keeps them in separate libdl and libpthread.
    # Harmless on newer glibc, where both are stubs inside libc.
    Linux)  CC="${CC:-gcc}";   CXX="${CXX:-g++}";     GUI_LIBS="-ldl -lpthread" ;;
    *)      echo "Unsupported host '$HOST' (want Darwin or Linux)"; exit 1 ;;
esac
AR="${AR:-ar}"
NM="${NM:-nm}"

# Which machine the binary is FOR, as opposed to $HOST, the one it is built on.
#   native   (default) this host. Nothing changes.
#   windows  cross-compile Incursion.exe with mingw-w64. Install the toolchain
#            with `brew install mingw-w64`, and stage SDL2, zlib and their
#            headers under build/win-deps. The recipe is docs/WINDOWS-BUILD.md,
#            and staging is still a manual step: see inc-wefr.3.
# This is a separate axis from BACKEND on purpose. BACKEND picks which source
# file defines main(); TARGET picks which compiler and which libraries. Windows
# uses the SAME libtcod backend the Mac does.
TARGET="${TARGET:-native}"
WIN_DEPS="$ROOT/build/win-deps"
case "$TARGET" in
    native) ;;
    windows)
        # Not $CC/$CXX: those name a compiler for $HOST, and honouring them here
        # would silently build a Mac binary under a Windows name.
        CC="x86_64-w64-mingw32-gcc"; CXX="x86_64-w64-mingw32-g++"
        AR="x86_64-w64-mingw32-ar";  NM="x86_64-w64-mingw32-nm"
        GUI_LIBS=""
        OUT="${OUT:-Incursion.exe}"
        command -v "$CXX" >/dev/null 2>&1 \
            || { echo "No $CXX. Install it with: brew install mingw-w64"; exit 1; }
        [ -d "$WIN_DEPS/lib" ] \
            || { echo "No $WIN_DEPS/lib. Stage SDL2 and zlib for mingw first:"
                 echo "  see docs/WINDOWS-BUILD.md section 1."; exit 1; }
        ;;
    # TARGET is a common name to have exported already -- autotools, Rust and
    # several CI runners all set it. Say so, or a stray one in the environment
    # reads as this script being broken.
    *)      echo "Unknown TARGET '$TARGET' (want native or windows)."
            echo "If you did not set it, it came from the environment: unset TARGET."
            exit 1 ;;
esac

BACKEND="${BACKEND:-libtcod}"

case "$BACKEND" in
    libtcod) OUT="${OUT:-incursion}" ;;
    posix)   OUT="${OUT:-incursion-headless}" ;;
    *)       echo "Unknown BACKEND '$BACKEND' (want libtcod or posix)"; exit 1 ;;
esac

# src/Wposix.cpp needs alarm()/SIGALRM and fnmatch(), and mingw-w64 gates the
# first behind __USE_MINGW_ALARM and does not ship the second at all. The
# windowed build is scriptable on its own (-keys), so nothing is lost.
if [ "$TARGET" = windows ] && [ "$BACKEND" != libtcod ]; then
    echo "TARGET=windows builds the libtcod backend only (BACKEND=$BACKEND asked for)"
    exit 1
fi

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
# AllocString() and AllocRegister() -- called at src/yygram.cpp:7857 and
# src/yygram.cpp:8548, defined inside the block that just vanished. That
# undefined-symbol link failure is the whole reason -DDEBUG was pinned on here
# in the first place. Windows solved it the same way: build.bat:93 filters
# yygram.cpp, tokens.cpp and cpp*.c out of a Release build.
#
# WHAT ELSE DROPPING -DDEBUG CHANGES, and all three are what a shipped game
# should do:
#   src/Player.cpp:791    wizard mode starts honouring the OPT_DISALLOW game
#                         option instead of ignoring it
#   src/Main.cpp:2181     the "(Debugging Commands)" entry leaves the start menu
#   src/Wlibtcod.cpp:632  Breakpad crash reporting is enabled -- Windows only,
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

# The C++ warning switch. It defaults to -w, which is what every ordinary build
# has always used, so leaving this unset changes nothing.
#
# IT EXISTS BECAUSE EXTRA_CXXFLAGS CANNOT TURN A WARNING BACK ON. clang's -w is
# not an ordinary -W option that a later one overrides: it sets
# SuppressAllDiagnostics on the diagnostic engine, and nothing after it revives
# a warning. Verified on clang 17, arm64: -w -Wno-everything -Wformat and even
# -w -Werror=format both print nothing on a call with too few arguments, while
# the same command without -w reports it. So a diagnostic build must REPLACE
# -w, not append to it:
#   WARN_FLAGS="-Wno-everything -Wformat" EXTRA_CXXFLAGS=-DFMTAUDIT \
#   OUT=incursion-fmt BACKEND=posix ./build_macos.sh
# Set EXTRA_CXXFLAGS to something as well, as above, so the build takes the
# instrumented path: its own object directory, and no rewrite of the shared
# mod/Incursion.Mod. See tools/check_format_strings.sh.
WARN_FLAGS="${WARN_FLAGS:--w}"

# The object directory must encode every flag that changes what an object IS.
# COMPILER belongs in it: a shipping build and a developer build differ by
# -DDEBUG, and -DDEBUG changes real code in Player.cpp and Main.cpp, so sharing
# a directory would link a mixture of the two and the result would be neither.
if [ "$TARGET" != native ]; then
    # A cross build's objects are for another machine entirely, so they get a
    # directory of their own no matter what OUT says.
    OBJ="$ROOT/build/obj-$TARGET-$OUT"
    [ "$COMPILER" = no ] && OBJ="$OBJ-nocompiler"
elif [ "$OUT" = "incursion" ] && [ -z "$EXTRA_CXXFLAGS" ] && [ "$COMPILER" = yes ]; then
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

if [ "$TARGET" = windows ]; then
    # SDL2 and zlib come from build/win-deps, not from pkg-config: pkg-config on
    # this Mac answers for the Mac. -lmingw32 -lSDL2main is what gives the .exe a
    # WinMain, and -mwindows puts it in the GUI subsystem so no console opens
    # behind the game window. libSDL2.dll.a is named by PATH, not by -lSDL2, for
    # the reason LINK_LIBS gives below.
    #
    # -DTCODLIB_API= is not optional. libtcod/include/libtcod.h:152-163 makes
    # TCODLIB_API mean __declspec(dllimport) on Windows, so every call into the
    # vendored static library looks for an __imp_ symbol that a static archive
    # does not have. The macro is #ifndef-guarded, so defining it empty on both
    # sides of the link -- here and in TFLAGS below -- turns those back into
    # ordinary calls. Mac and Linux never see this: there TCODLIB_API is empty.
    SDL_CFLAGS="-I$WIN_DEPS/include -I$WIN_DEPS/include/SDL2"
    SDL_LIBS="-L$WIN_DEPS/lib -lmingw32 -lSDL2main $WIN_DEPS/lib/libSDL2.dll.a"
    INCLUDES="-Iinc -Ilib -Ilibtcod/include -Icompat $SDL_CFLAGS"
    DEFINES="$DEBUG_DEFINE -DLIBTCOD_TERM -DTCODLIB_API="
    SKIP_BACKENDS="Wcurses Wposix"
    # -flifetime-dse=1 is load-bearing, not a tuning knob. Object::operator new
    # (inc/Base.h:661) memsets every allocation to zero, and constructors across
    # the Object/Thing/Creature/Item/Monster hierarchy lean on that fill instead
    # of initialising their own members. C++ says an object's lifetime has not
    # begun until its constructor runs, so at the default -flifetime-dse=2 GCC is
    # entitled to DELETE that memset. Members nobody assigns then hold heap
    # garbage, and a garbage hObj is an invalid object handle
    # (src/Registry.cpp:468) moments after character creation.
    #
    # Measured 2026-09-07 in a Windows 11 ARM64 VM, same source, three binaries
    # differing only in flags: -O2 crashes after chargen, -O0 is clean, and
    # -O2 -flifetime-dse=1 is clean. Optimisation-dependent, so it is undefined
    # behaviour the optimiser may exploit rather than a port defect.
    #
    # ponytail: this MASKS the defect, it does not remove it. The real fix is the
    # constructor audit in inc-uusj -- every member initialised by its own
    # constructor instead of by the allocator. clang has the same licence to
    # elide that memset and merely does not take it today, so macOS and Linux are
    # latent rather than safe. Do not read this flag as "a GCC problem".
    CXXFLAGS_EXTRA_TARGET="-flifetime-dse=1"
    # -static is what keeps the package to ONE DLL. Without it the .exe also
    # imports libgcc_s_seh-1.dll, libstdc++-6.dll and libwinpthread-1.dll, none
    # of which ships with any Windows, so a player who has not installed mingw
    # gets "the code execution cannot proceed" and nothing else. Measured with
    # objdump -p: 3 extra DLLs without it, 0 with it.
    #
    # -static-libgcc -static-libstdc++ do NOT do the job on their own. The GCC
    # driver expands each to -Bstatic <lib> -Bdynamic, so its own -Bdynamic
    # lands after libstdc++, and libstdc++'s gthread layer (pthread_once,
    # pthread_key_create, pthread_mutex_*) then resolves against the DLL.
    #
    # SDL2 escapes -static because SDL_LIBS names libSDL2.dll.a by path rather
    # than with -lSDL2. -static changes the -l search, and a path is not a
    # search, so this one library still links as a DLL import.
    LINK_LIBS="-L$WIN_DEPS/lib -lz -mwindows -static"
elif [ "$BACKEND" = posix ]; then
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
    LINK_LIBS="-lz $GUI_LIBS"
fi

# ---------------------------------------------------------------- libtcod ----
# Built from the vendored copy. The bundled zlib is too old to compile against
# a modern SDK (it redefines fdopen), so it is skipped in favour of system -lz.
TCODLIB="$ROOT/build/libtcod_local.a"
TOBJ="$ROOT/build/tcodobj"
TCOD_PIC="-fPIC"
TCOD_CSTD=""
TCOD_API=""
if [ "$TARGET" = windows ]; then
    TCODLIB="$ROOT/build/libtcod_win.a"
    TOBJ="$ROOT/build/tcodobj-win"
    # Same reason as DEFINES above: without it libtcod's own cross-file calls
    # also go looking for __imp_ symbols.
    TCOD_API="-DTCODLIB_API="
    # All PE code is position independent, so -fPIC only earns a warning per file.
    TCOD_PIC=""
    # libtcod/include/libtcod.h:143 is `typedef uint8 bool;`. GCC 15 and later
    # default to C23, where bool is a keyword and that line is an error. Apple
    # clang still defaults to gnu17 and never sees it, so only this arm pins it.
    TCOD_CSTD="-std=gnu17"
fi
if [ "$BACKEND" = posix ]; then
    TCODLIB=""
elif [ ! -f "$TCODLIB" ]; then
    echo "--- building vendored libtcod ---"
    mkdir -p "$TOBJ"
    TFLAGS="-O2 -w $TCOD_PIC $TCOD_API -DTCOD_SDL2 -DNO_OPENGL $SDL_CFLAGS -Ilibtcod/include -Ilibtcod/src"
    for f in $(find libtcod/src -name '*.c' -o -name '*.cpp'); do
        case "$f" in libtcod/src/zlib/*) continue ;; esac
        o="$TOBJ/$(echo "$f" | tr '/' '_').o"
        if [ "${f##*.}" = "c" ]; then
            $CC $TCOD_CSTD $TFLAGS -c "$f" -o "$o"
        else
            $CXX $TFLAGS -fpermissive -c "$f" -o "$o"
        fi
    done
    $AR rcs "$TCODLIB" "$TOBJ"/*.o
fi

# ------------------------------------------------------------------ game -----
echo "--- compiling Incursion ---"
# ${CXXFLAGS_EXTRA_TARGET:-} carries flags a cross target cannot build without;
# only TARGET=windows sets it, and it is empty everywhere else. It sits BEFORE
# $EXTRA_CXXFLAGS so a caller can still override it from the command line.
CXXFLAGS="-O2 $WARN_FLAGS -fpermissive -Wno-narrowing ${CXXFLAGS_EXTRA_TARGET:-} $DEFINES $INCLUDES $EXTRA_CXXFLAGS"
CFLAGS="-O2 -w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-return-mismatch -Wno-return-type $DEBUG_DEFINE -Iinc -Ilib -Icompat"

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
    $CXX -std=$std $CXXFLAGS -c "$f" -o "$OBJ/$n.o"
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
    $CC -std=gnu89 $CFLAGS -c "$f" -o "$OBJ/c_$n.o"
done

echo "--- linking ---"
$CXX -std=c++17 $EXTRA_LDFLAGS -o "$ROOT/$OUT" "$OBJ"/*.o $TCODLIB $SDL_LIBS $LINK_LIBS

# ------------------------------------------------------------- game data -----
# A shipping binary cannot build its own data: that is the point of it. The
# module has to come from a developer build of the SAME source, because
# Registry writes raw struct bytes and the file is welded to the layout of the
# binary that produced it.
# NOTHING DETECTS A MODULE THAT HAS FALLEN BEHIND ITS SCRIPTS. Registry stamps
# every file with a layout digest (src/Registry.cpp:61) and refuses a mismatch,
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
#
# A CROSS BUILD CANNOT DO ANY OF THIS. Its binary does not run on this machine,
# so it takes the module a NATIVE developer build of the same source wrote. That
# is safe for the reason docs/SAVE-SCHEMA-SPEC.md gives: the module is
# fixed-width and layout-safe, and src/AbiCheck.cpp's static_asserts fail the
# compile above if any of those widths differ on the target.
if [ "$TARGET" != native ]; then
    if [ ! -f "$ROOT/mod/Incursion.Mod" ]; then
        echo
        echo "No mod/Incursion.Mod, and a $TARGET binary cannot compile one here."
        echo "Build the native developer binary first, which will produce it:"
        echo "    ./build_macos.sh"
        exit 1
    fi
elif [ ! -f "$ROOT/mod/Incursion.Mod" ] || { [ -z "$EXTRA_CXXFLAGS" ] && [ "$COMPILER" = yes ]; }; then
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
    echo "    $NM '$ROOT/$OUT' | grep -c 'yyparse\|yyselect\|yymallocerror'"
    echo "expecting 0. Those three are every function src/Art.cpp defines, and"
    echo "Art.cpp is the GPLv2 file. Do not grep for 'accent' -- none of the"
    echo "symbols carry that word, so it reports 0 either way."
fi
