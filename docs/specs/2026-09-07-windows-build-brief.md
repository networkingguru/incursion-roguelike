<!-- citations: this-port -->

# Build brief: a Windows executable for release 4 (inc-wefr item 7)

**For:** Codex (`codex exec -C /Users/brianhill/Scripts/Incursion -s workspace-write - < brief`).
Codex writes the source fixes, the build-script arm and the packaging, and
proves the `.exe` runs. Codex MUST NOT commit and MUST NOT push. The Claude
session reviews each phase's diff.

**Approved by Brian on 2026-09-07:** "get started on it. I want a windows build
of r4 specifically."

## The target, pinned

| What | Value |
|---|---|
| Tag | `release-4` (annotated: "iNCURSION release 4 - a lighting system, and colours that suit it") |
| Commit | `9821fdd` — *fix: the title screen says release 4, and a check stops it lying again*, 2026-09-07 07:29:55 -0400 |
| Source of truth for the name | `inc/Defines.h:34`, `#define FORK_RELEASE "4"`, guarded by `tools/check_fork_release.sh` |

`master` is two commits ahead of `release-4`. Both are docs and tools. The only
`src/` delta is `src/Feature.cpp`, and it is comment text plus one corrected
line-number citation. **The r4 and master engines are the same program.** Build
from the tag anyway, because that is what was asked for.

Every fix site named below was checked against the `release-4` tree, not
against master. Line numbers in this brief are r4's.

## Deliverable

One file: `Incursion.exe`, x86-64, the SDL/libtcod frontend, that launches on
Windows 10 or later and plays a character from the title screen to a dungeon
level. Plus the data it needs beside it.

**Not** in this deliverable, and Codex MUST NOT build them:

- `IncursionCurses.exe`. See "Decisions already made".
- An installer, a signed binary, or anything published.
- A Windows headless/`Wposix` build.
- A fix for the per-user data directory (`inc-9df.8`). It is a release gate,
  not a build task; see "The gate this does not clear".

## Decisions already made — do not re-derive, do not question

**1. Cross-compile from the Mac with mingw-w64. Do not use MSVC and do not
touch `build.bat`.**

`build.bat` was last touched 2025-06-28, thirteen months before this port began.
Three separate things make it a dead end, any one of them sufficient:

- It reads `build/dependencies/`, which does not exist in this repository.
  `flex.exe` and Breakpad's three `.lib` files are nowhere in the tree or in
  its history, and nothing records which versions worked.
- It never compiles the module. It emits two `.exe` files and stops. Without
  `mod/Incursion.Mod` the game cannot start. `build_macos.sh:245` does this step.
- It has no shipping mode, so every `.exe` it can produce links `src/Art.cpp`,
  the GPLv2 ACCENT runtime. `COMPILER=no` in `build_macos.sh:128-135` exists to
  prevent exactly that.

**2. Use clang or GCC through mingw-w64, never MSVC.** Three independent
reasons, and the third is the one that saves the most work:

- `inc/Globals.h:10`, `inc/Base.h:185` and `src/Feature.cpp:1165` use
  `__attribute__((format(printf,1,2)))` and `__builtin_frame_address(0)`. MSVC
  has neither. mingw-w64 has both, so **these three sites need no change at
  all** on this path.
- GCC -O2 miscompiled this engine once already (`inc-nw0v`, fixed in `6dc3223`),
  and `inc-uusj` is open: the same constructor pattern was never enumerated
  across the object hierarchy. Prefer clang if the cross-toolchain offers it.
  If only GCC is available, use it, but treat any character-creation crash as
  `inc-uusj` first and not as a new defect.
- `src/Wcurses.cpp`'s Win32 code has had no compiler over it in a year. Not
  building it removes that risk entirely.

**3. Ship the SDL frontend only.** `src/Wcurses.cpp` is Windows-only source
that neither macOS build mode compiles. During this fork it has taken three
commits, each of whose message states in terms that the change is unverified,
against `src/Wlibtcod.cpp`'s twenty-seven and `inc/Term.h`'s nine. Reviving a
second frontend nobody asked for is not in this deliverable.

**4. Drop Breakpad.** Its source is not in the repository — only prebuilt
`.lib` files of unknown provenance from `ab1053f`. Every reference in the
backends sits inside `#ifdef USE_BREAKPAD`, so simply never defining it
compiles clean with no dangling symbols.

**5. Verify with `-keys` on the SDL build. Do not port `src/Wposix.cpp`.**
Deterministic key-script playback landed in the SDL backend in `04431f2`, so the
windowed binary is scriptable on its own. This matters because `Wposix.cpp`
needs two things mingw-w64 does not give you by default: `alarm()`/`SIGALRM`
are gated behind `__USE_MINGW_ALARM`, and `fnmatch()` does not exist at all.
Building the SDL frontend skips `Wposix.cpp` entirely
(`build_macos.sh:137-154`, `SKIP_BACKENDS`) and none of that work is needed.

## Phase 0 — branch and toolchain

Branch `windows-r4` from tag `release-4`. Work there. Do not work on `master`
and do not build in a detached HEAD.

Install the cross toolchain: `brew install mingw-w64`. Target triple
`x86_64-w64-mingw32`. Confirm `x86_64-w64-mingw32-g++ --version` answers before
going further.

**STOP and report** if the brew formula fails or if the toolchain has no C++
support. Do not substitute a different toolchain on your own judgement.

## Phase 1 — the three dependencies

`build_macos.sh` links three things the cross build must supply for Windows.

**SDL2.** The macOS build takes it from Homebrew via `pkg-config`
(`build_macos.sh:148-149`). For Windows, use SDL's own prebuilt mingw
development package (`SDL2-devel-<version>-mingw.tar.gz`) rather than
cross-building SDL from source. Note the version you take; it goes in the
commit message.

**zlib.** `build_macos.sh:146,153` links `-lz`. Cross-build zlib, or take a
mingw build of it. Do not reach for `libtcod/src/zlib/` — `build_macos.sh:127`
skips that copy deliberately, because it redefines `fdopen` and will not
compile against a modern SDK.

**libtcod.** Build from the vendored source exactly as `build_macos.sh:160-176`
does, with the cross compiler, keeping `-DTCOD_SDL2 -DNO_OPENGL` and skipping
`libtcod/src/zlib/`. The vendored copy is a 1.6.3-era snapshot. Do **not**
upgrade it here; that is `inc-1rak` and it is deferred.

**STOP and report** if any dependency needs a version different from what the
macOS build uses. A version skew between the Mac and Windows builds is a
decision for Brian, not a detail to settle quietly.

## Phase 2 — source fixes

Two files. Both are this fork's own regressions, added after the Windows build
last worked, so **neither gets an `upstream:` mark** and neither gets a ledger
row. Read `AGENTS.md` on marking before you are tempted.

**`src/ErrorLog.cpp` — the known blocker, bead `inc-xo4o`.**

Lines 25-28 include `<dirent.h>`, `<execinfo.h>`, `<unistd.h>` and
`<sys/stat.h>` with no platform guard, and `build.bat` compiled the file into
both configurations. That is why the Windows build has not compiled since
2026-08-14.

On the mingw path the file is far less broken than the bead says. mingw-w64
ships `<dirent.h>` with working `opendir`/`readdir`/`closedir`, and ships
`<unistd.h>` and `<sys/stat.h>`. **Only `<execinfo.h>` is genuinely absent.**
So the minimum correct change is:

- Guard `#include <execinfo.h>` (line 26).
- Guard the `backtrace()` / `backtrace_symbols()` block at lines 140-141, and
  in its place write one line into the log saying the call stack is not
  available on this platform. Do not reach for `CaptureStackBackTrace` — a
  stack trace is not in this deliverable.
- Leave `opendir`/`readdir`/`closedir` (lines 67-73), `unlink` (line 86) and
  `stat` (lines 94, 103) alone unless the compiler objects.

**The POSIX path MUST come out byte-identical.** `tools/check_logrotate.sh`
compiles this file standalone and exercises it directly, and
`docs/outgoing/issue8-reply.md:45` describes its behaviour to the parent
project. Run that check before and after, and put both results in the commit
message.

If `<unistd.h>` or `<sys/stat.h>` turns out to be missing after all, guard it
the same way and say so in the report — that would correct this brief.

**`src/KeyScript.cpp:57` — one line.**

    if (!strcasecmp(tok, NamedKeys[i].name)) {

`strcasecmp` is POSIX. This codebase already solved this: `inc/Incursion.h:60-63`
defines `stricmp` and macro-translates it to `strcasecmp` under `#ifndef WIN32`.
Use `stricmp`. Do not add a new guard, and do not add a second spelling of a
thing the tree already has one spelling for.

**Everything else surfaces at the compiler.** The Linux port is the precedent:
six defects, one commit, and not one of the six was found by reading — all six
were found by building. Expect the same shape. Fix what the compiler names,
one commit per coherent group, and report anything that is not a mechanical
guard before you change it.

## Phase 3 — the build-script arm

Add a Windows case to `build_macos.sh`. Do not write a second script and do not
fork the logic.

`build_macos.sh` already does four things `build.bat` never did, and the
Windows arm must inherit all four: it discovers sources by glob, so new files
need no script edit; it has the `COMPILER=no` shipping split that keeps GPLv2
`src/Art.cpp` out of a distributed binary; it compiles the module; and it is
under active maintenance.

Follow the shape `BACKEND=posix` already uses (`build_macos.sh:137-154`): a
branch that sets the compiler, the includes, the defines, `SKIP_BACKENDS` and
the link libraries. Windows sets `SKIP_BACKENDS="Wcurses Wposix"`, the same as
the libtcod branch, and adds `-lmingw32 -lSDL2main -lSDL2 -mwindows` in place of
the macOS frameworks.

Keep `-DDEBUG`. `docs/PORT-STATUS.md:186-188` records why: `src/RComp.cpp` is
inside `#ifdef DEBUG` while the generated `src/yygram.cpp` calls into it
unconditionally, so a developer build without it fails to link. Do not "fix"
that here.

## Phase 4 — module and package

The `.exe` alone is not a game. It needs `mod/Incursion.Mod`.

A cross-built `.exe` cannot compile its own module, because it will not run on
the Mac. **Use the module the macOS developer build produces from the same
source.** `docs/SAVE-SCHEMA-SPEC.md` and `src/AbiCheck.cpp` are the reason to
expect this to work: the module and the v1 save schema are fixed-width and
layout-safe, and `AbiCheck.cpp`'s `static_assert`s fire at compile time if any
width differs.

**STOP and report if `src/AbiCheck.cpp` fails to compile.** That is the one
place where a Windows ABI difference — MSVC-style bitfield packing rather than
Itanium — would show itself, and it is exactly what that file was written to
catch. It is a real finding, not an obstacle to work around. Do not relax an
assert.

Package on the pattern of `tools/package_linux.sh`. The manifest is the macOS
one minus the dylib: the `.exe`, `mod/Incursion.Mod` (~1M), `fonts/` (28K),
`LICENSE`, `Incursion.txt`, and empty `save/` and `logs/`. Ship the SDL2 DLL
beside the `.exe` unless it is linked statically. **`graphics/logo.png` IS
needed** — the title screen reads it at `src/Wlibtcod.cpp:1563`, and without it
the title falls back to the ASCII wordmark. This paragraph said the opposite
until the `#ifndef _WIN32` guard around that load came off; the file is one
line in `tools/package_linux.sh`'s `assemble()` and is the same one line here.
`lib/` and `lang/` are not shipped; they are resource-compiler input.

## Phase 5 — verification

`docs/VERIFICATION.md` is not optional, and its step 2 is the one that matters:
a check that has never failed has never been tested.

1. Build both macOS targets from the `windows-r4` branch and confirm the source
   fixes broke neither: `./build_macos.sh` and `BACKEND=posix ./build_macos.sh`.
2. `tools/check_logrotate.sh` — the oracle for the `ErrorLog.cpp` change.
3. `tools/check_key_directives.sh` — the oracle for the `KeyScript.cpp` change.
4. `tools/nightly_verify.sh --compare`.
5. The Windows run. See below.

**Codex cannot do step 5 and MUST NOT pretend to.** There is no Windows on this
Mac, and Homebrew disabled all three Wine casks on 2026-09-01 for failing the
Gatekeeper check. Codex's job ends at "the `.exe` and its package exist, and
every macOS check is green." Report that state and stop. Brian decides where
the binary runs.

Do not add a `tools/check_windows_build.sh`. `tools/check_linux_build.sh` could
exist because Docker gave this repository a Linux it could reach; there is no
equivalent for Windows, and a check nobody can run is not a check.

## The gate this does not clear

The build is not the release. `inc-9df.8` is open and applies to Windows harder
than it applies to macOS: all three backends resolve `argv[0]`, `chdir` there,
and write `Options.Dat`, `save/` and `logs/` beside the executable
(`src/Wlibtcod.cpp:589-675`). A repository-wide grep for `APPDATA`,
`SHGetKnownFolderPath` and `CSIDL` returns nothing.

Installed to `Program Files` and run by a standard user, the first settings or
save write fails. **A GitHub windows runner will not catch this**, because it
runs as administrator. It needs a real standard-user account, or a change to
the path resolution.

Do not fix it in this brief. Do flag it in the handoff, because shipping the
`.exe` without deciding it is how a first Windows player loses their character.

## What Codex reports

Per phase: the diff, the commands run, and their output. At the end, one
summary naming the toolchain and dependency versions taken, every source fix
made beyond the two specified here, the macOS check results before and after,
and the exact contents of the package directory.

Nothing is committed and nothing is pushed. Claude reviews; Brian decides.
