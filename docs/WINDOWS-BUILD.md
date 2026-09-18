<!-- citations: this-port -->

# Building Incursion for Windows

This page is the recipe `build_macos.sh` points at when it refuses with
*"No build/win-deps/lib. Stage SDL2 and zlib for mingw first."*

The Windows build is **cross-compiled from macOS** with mingw-w64. There is no
Windows machine attached to this project, and no Windows build runs here. What
follows produces the binary; it does not prove it plays. See "What this cannot
verify" at the end.

## What is scripted and what is not

Be clear about this before you start, because two of the three steps are manual
and nothing in the tree performs them.

| Step | State |
|---|---|
| Stage SDL2 and zlib into `build/win-deps/` | **Manual.** This page is the only recipe. |
| Cross-build the vendored libtcod | Scripted, inside `build_macos.sh` |
| Compile and link the `.exe` | Scripted — `TARGET=windows ./build_macos.sh` |
| Assemble and zip the package | **Manual.** There is no `tools/package_windows.sh`. |

Closing the two manual gaps is bead **inc-wefr.3**. Until it is closed, treat
this page as load-bearing rather than as background reading.

## 0. The toolchain

    brew install mingw-w64

That gives GCC, not clang — Homebrew has no clang cross-mingw. Measured with
GCC 16.2.0, target triple `x86_64-w64-mingw32`. Confirm before going on:

    x86_64-w64-mingw32-g++ --version

**The compiler choice has a consequence you must know about.** GCC's optimiser
exposes latent undefined behaviour in the object hierarchy that clang does not,
which is why the Windows arm carries `-flifetime-dse=1`. If a Windows binary
crashes just after character creation with *"invalid object handle"*, read bead
`inc-uusj` before you look for a porting bug. It is not one.

## 1. Stage SDL2 and zlib

Everything lands under `build/win-deps/`, which is gitignored. Paths below are
relative to the repository root.

    mkdir -p build/win-deps/src build/win-deps/include build/win-deps/lib build/win-deps/bin

### SDL2

**Take the version the Mac links, not the newest.** Check with
`pkg-config --modversion sdl2` and use that number. A skew between the macOS and
Windows builds is a decision for Brian, not a detail to settle quietly. As of
2026-09-07 that is 2.32.10.

    cd build/win-deps/src
    curl -sSL -O https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-devel-2.32.10-mingw.tar.gz
    tar xzf SDL2-devel-2.32.10-mingw.tar.gz

Use SDL's own prebuilt mingw development package. Do not cross-build SDL from
source, and do not use the vendored `SDL2/` tree in this repository — that is a
2.0.5 snapshot from 2016 that only the dead MSVC `build.bat` ever used.

    cd ../../..
    cp -R build/win-deps/src/SDL2-2.32.10/x86_64-w64-mingw32/include/SDL2 build/win-deps/include/
    cp build/win-deps/src/SDL2-2.32.10/x86_64-w64-mingw32/lib/libSDL2*.a build/win-deps/lib/
    cp build/win-deps/src/SDL2-2.32.10/x86_64-w64-mingw32/bin/SDL2.dll build/win-deps/bin/

### zlib

**`zlib.net` serves a 404 for the tarball.** Take the GitHub release asset:

    cd build/win-deps/src
    curl -sSL -o zlib.tar.gz https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
    tar xzf zlib.tar.gz
    cd zlib-1.3.1
    make -f win32/Makefile.gcc PREFIX=x86_64-w64-mingw32- libz.a

`PREFIX=` with a trailing dash is what points zlib's makefile at the cross
compiler. Then stage it:

    cd ../../../..
    cp build/win-deps/src/zlib-1.3.1/libz.a build/win-deps/lib/
    cp build/win-deps/src/zlib-1.3.1/zlib.h build/win-deps/src/zlib-1.3.1/zconf.h build/win-deps/include/

Do **not** reach for `libtcod/src/zlib/`. `build_macos.sh` skips that copy
deliberately on every platform: it redefines `fdopen` and will not compile
against a modern SDK.

### The layout the build expects

    build/win-deps/include/SDL2/      SDL2 headers
    build/win-deps/include/zlib.h
    build/win-deps/include/zconf.h
    build/win-deps/lib/libSDL2.a
    build/win-deps/lib/libSDL2.dll.a
    build/win-deps/lib/libSDL2main.a
    build/win-deps/lib/libz.a
    build/win-deps/bin/SDL2.dll      ships beside the .exe

## 2. Build

    COMPILER=no TARGET=windows OUT=Incursion-ship.exe ./build_macos.sh

`TARGET` is a separate axis from `BACKEND`: `BACKEND` picks which source file
defines `main()`, `TARGET` picks the toolchain. Windows uses the same `libtcod`
backend the Mac does. `TARGET=windows BACKEND=posix` is refused by name, because
mingw gates `alarm()`/`SIGALRM` behind `__USE_MINGW_ALARM` and has no
`fnmatch()`.

`COMPILER=no` is not optional for anything you distribute. It drops `src/Art.cpp`,
the GPLv2 ACCENT runtime, which must not be linked into a shipped binary. Prove
it worked rather than trusting it:

    x86_64-w64-mingw32-nm Incursion-ship.exe | grep -c 'yyparse\|yyselect\|yymallocerror'

Zero on a shipping binary. Run the same command on a `COMPILER=yes` build and it
returns 3 — that is how you know the gate bites rather than merely being quiet.

The script cross-builds the vendored libtcod on first run into
`build/libtcod_win.a`. Delete that file to force a rebuild.

## 3. Package

By hand, until `inc-wefr.3` lands. Model it on `tools/package_linux.sh`'s
`assemble()`.

    dist/incursion-windows/
        Incursion.exe          the COMPILER=no build, renamed
        SDL2.dll               from build/win-deps/bin
        mod/Incursion.Mod      see below
        fonts/*.png            all four
        graphics/logo.png      REQUIRED -- without it the title falls back to ASCII
        LICENSE
        Incursion.txt
        save/                  empty
        logs/                  empty

**Not** `Options.Dat`: the tree's copy is the maintainer's own settings, and
`Player::LoadOptions` fills in real defaults when it is absent. Shipping it also
overwrites a player's settings on update. **Not** `lib/` or `lang/` — those are
resource-compiler input and no code opens them at run time.

**The module must come from a macOS developer build of the same source.** A
cross-built `.exe` cannot compile its own module, because it does not run here.
`./build_macos.sh` produces `mod/Incursion.Mod`; copy that one.

That is safe for a reason the tree already checks. `src/AbiCheck.cpp` pins every
serialised width with `static_assert`, and all 28 hold under mingw. That file is
the designed tripwire for a Windows bitfield-ABI difference. **If it ever fails
to compile, stop and report it — that is a real finding, not an obstacle. Never
relax an assert to get past it.**

Verify the result:

    file dist/incursion-windows/Incursion.exe
    # PE32+ executable (GUI) x86-64, for MS Windows

    x86_64-w64-mingw32-objdump -p dist/incursion-windows/Incursion.exe | grep 'DLL Name' | sort -u

The non-`api-ms-win-crt-*` imports are `KERNEL32.dll`, `SDL2.dll` and
`SHELL32.dll`. All three are either shipped beside the binary or present on every
Windows install. `SHELL32` arrived with the title logo; a build without the logo
code does not import it, so do not treat its absence in an older binary as a
difference that matters.

What you are checking for is the mingw runtime. If `libgcc_s_seh-1.dll`,
`libstdc++-6.dll` or `libwinpthread-1.dll` appear, the
`-static` link has broken and the package will fail on any machine without mingw
installed. `-static-libgcc -static-libstdc++` do **not** fix that; read the
comment in `build_macos.sh`'s windows arm before changing the link line.

## What this cannot verify

No step above proves the binary plays. There is no Windows on this machine, and
Homebrew disabled all three Wine casks on 2026-09-01 for failing the Gatekeeper
check. Everything here is compile-time and file-format evidence.

To actually run it, use a Windows 11 ARM64 VM under UTM (`brew install --cask
utm`, plus `crystalfetch` to build the ISO). The binary is x86-64, so it runs
under Windows-on-ARM's x64 emulation: good for *does it work*, poor for *how
fast*. The lighting shimmer is on a 30 Hz wall-clock tick, so judge pacing on
real hardware, not in the VM.

One test needs the VM and cannot be done any other way: `inc-9df.8`. The game
writes `Options.Dat`, `save/` and `logs/` beside its own executable, with no
per-user data directory anywhere. Installed to `Program Files` and run by a
**standard** user, the first settings write fails. A CI runner cannot catch this
because it runs as administrator. Do that test before any Windows release.

## The original MSVC build

The original MSVC build is still in the tree, and it is not the path this fork
took. `build_sdl2.bat`, `build_libtcod.bat` and `build_pdcurses.bat` rebuild the
checked-in dependencies, and `build.bat` produces `IncursionLibtcod.exe` and
`IncursionCurses.exe`. Three things rule it out, any one of them sufficient: it
reads a `build/dependencies/` directory that is not in this repository, it never
compiles the data module, and it has no shipping mode, so everything it can
produce links `src/Art.cpp` and the GPLv2 ACCENT runtime with it. The cross-build
answers all three. `src/Wcurses.cpp`, the second Windows frontend, is still built
by nothing.

**Why the dependencies are checked in, in Richard Tew's words:** bug fixes to
gameplay require a save game, and a save game only loads in the build that wrote
it. Character creation is varied enough that a player often cannot remember what
they picked, so reproducing a report without their save is a wild goose chase.
Keeping every binary and every source version is what makes an old save
debuggable at all.
