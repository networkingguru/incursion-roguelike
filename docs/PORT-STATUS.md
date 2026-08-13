# Port status

Last updated 2026-08-13. This is the running state of the macOS/POSIX port.
Read it before doing anything else.

## Where things stand

Incursion **builds, compiles its own game data, and is playable on macOS ARM64**.
Character creation, exploration and **save/load** all work. Brian plays it and
confirms behaviour on screen; see "Who verifies what" below.

```
brew install sdl2 pkg-config     # once
./build_macos.sh                 # ~2 min from clean
./incursion                      # play
./tools/check_abs_path.sh        # regression check, exits 0 on pass
./tools/check_error_handling.sh  # regression check, exits 0 on pass
```

Upstream is `rmtew/incursion-roguelike`, dormant since 2015 apart from a trickle.
`HexDecimal/incursion-roguelike` (Kyle Benesch, the current libtcod maintainer) has
16 unmerged topic branches from Aug 2024 — `standard-types`, `libtcod-1.24.0`,
`minmax`, `char-funcs`, `mod-arch`, `vcpkg-manifest` and others. That is real work
already done. Mine it before writing anything new.

Brian's fork is `networkingguru/incursion-roguelike` (public, issues enabled),
added as git remote `mine`. Bugs are tracked there.

## The three findings that mattered

**`int32` was `typedef signed long`.** Windows is LLP64 so `long` is 4 bytes; macOS
and Linux are LP64 where it is 8. Every "32-bit" type in the codebase — `int32`,
`uint32`, `rID`, `hObj`, `hText`, `hCode`, `hData` — was silently 64-bit off Windows.
The codebase catches this itself: `inc/RComp.h:221` asserts
`sizeof(int32) <= sizeof(VCode)` and fires on every opcode the resource compiler
emits. Narrowing the typedefs in `inc/Defines.h` dropped printf format mismatches
from 325 to 26.

**Narrowing the typedefs then broke saving.** `inc/Map.h:649` did
`*((long*)&hm) = ...`, writing 8 bytes into what had become a 4-byte `hObj`. The
overrun covered the `int16 x,y` declared immediately after it, so **every save
zeroed the player's position**, in memory and on disk. Loading placed the character
at (0,0) — the map's solid outer corner — where `Creature::DoTurn()` crushed them to
death, and the view centred on (0,0) so 91% of the map window was off-grid and blank.
Fixed by dropping the cast. **Any save written before 2026-08-13 17:42 is
unrecoverable** and all such files have been deleted.
Lesson: after changing a typedef's width, audit every cast that assumed the old one.
There were three `(long*)` casts in the tree; the two in `src/Registry.cpp` write
into a `void*` and are size-correct on LP64.

**The upstream README's diagnosis is wrong.** It says POSIX builds fail to locate
exported symbols. The real cause is that `src/RComp.cpp` is wrapped in `#ifdef DEBUG`
while the generated `src/yygram.cpp` calls into it unconditionally. Build with
`-DDEBUG` and it links. A consequence: every macOS build is a DEBUG build.

## Known open

| Issue | Notes |
|---|---|
| Screen flicker, whole window dims or brightens | Intermittent, correlated with keypresses, **not periodic**. The earlier "~300ms `BlinkCursor()`" hypothesis is **disproved**: a build with the blink interval at 1200ms looked identical, and a probe on the surface libtcod presents shows mean luminance flat at 8.99 (range 8.987–9.041) with alpha 255 everywhere. The drawn image is correct; the change happens after it. The game presents only ~2 frames/sec with gaps up to 3.4s, and the renderer is Metal. One run recorded with screen capture showed no flicker, which fits a present-timing artefact. Instrumentation is in `src/Wlibtcod.cpp` behind `-DFLICKER_PROBE`. |
| `Thing::Remove` list corruption | `Contents list wierdless in Thing::Remove!`, `src/Display.cpp:1145`, 57 occurrences, reached via `Creature::Death()`. Not investigated. |
| `FI_SIZE` inconsistency | `Map::GetAt()` finds `FieldAt(x,y,FI_SIZE)` true with no matching entry in `Fields[]`, `src/Display.cpp:669`. Fired during monster AI; not seen since. |
| Negative map scroll offsets | The clamp that would stop `XOff`/`YOff` going negative is commented out at `src/Term.cpp:1005-1015`. Harmless once positions are correct, but it turned the save bug into a fully blank screen instead of a visibly wrong one. |
| Resolution warning on startup | `Wlibtcod.cpp`. Pre-existing, matches an open upstream issue. Options top out at 1920x1200; no Retina/HiDPI handling. |
| 58 format-string defects | 26 residual type mismatches, plus 32 that are live bugs on Windows too. Enumerate them by adding `__attribute__((format(printf,1,2)))` to `Format()` (`inc/Base.h:139`) and compiling with `-Wno-everything -Wformat`. `Error()` already carries the attribute. |
| No headless mode | `src/Wcurses.cpp` is still Windows/pdcurses only. Porting it to ncurses would make the game text-capturable and scriptable. |
| No x86_64 slice, no universal binary, no Linux run, no CI | |
| Unresolved content references | Module compile warns: `Blood;Domain, Dryad, Snow Angel`. Pre-existing. Ruleset work, not engine work. |

## Work tracking

Work lives in **Beads** (`bd`), not in this file and not in markdown TODOs.

```
bd ready          # what can be worked on now
bd show <id>      # detail, including why something is blocked
bd list           # everything
```

Issue prefix is `inc`. The graph mirrors Brian's three goals: **A** port to
mac/linux/universal, **B** fix the bugs, **C** expand the game (reach). Three
items are deliberately blocked — the Linux build waits on the type-width audit,
the Steam Deck waits on Linux, and ruleset expansion waits on all four
comprehension passes.

GitHub issues on `mine` hold only the defects that are genuinely upstream bugs
rather than port artefacts, so they can be reported to `rmtew`/`HexDecimal`
later. Those are cross-linked from Beads via `external-ref` (`gh-2`, `gh-3`,
`gh-4`).

## Who verifies what

Agents own the C++: port, engine, build, harness. All machine-checkable.

Brian owns the ruleset in `lib/*.irh` — 82,768 lines of IncursionScript, 1,469
`On Event` handlers, 522 monsters, 264 items, 191 effects, 39 classes, 17 races.
It is C-lite with dice notation (`1d2`, `A_STR`), and each entity's prose spec sits
in the same file as its implementation, so a mismatch between them is a provable bug
that needs no C++. He knows D&D 3.5 cold.

**An agent cannot distinguish an intentional Incursion divergence from 3.5 from a
defect. Brian can. Do not let agents lead ruleset work.**

## Oracles that work here

There is no test suite, so use what the platform gives you:

- `logs/errors.log` — since 2026-08-13, `Error()` logs and returns instead of opening
  a modal prompt. Each distinct message gets one backtrace on first occurrence.
  Demangle with `c++filt`. This is the highest-value oracle in the project.
- `~/Library/Logs/DiagnosticReports/*.ips` — macOS writes a full crash report with
  stack trace for every crash. Parse the JSON body, read the triggered thread.
- `sample <pid> 2 -file out.txt` — works on a hung process even under lldb, and is how
  the `Error()` freeze was located.
- `lldb -b -o "run <args>" -o "bt 25"`
- `lsof -p <pid> -a -d cwd` — the game chdir()s constantly. Any diagnostic that opens
  a relative path will land in the wrong directory; build paths from
  `Term::IncursionDirectory`.
- `./incursion -compile main.irc` — headless. Exercises the preprocessor, parser,
  code generator and serializer with no window. The best smoke test available.

**Claude can now see and drive the game.** Screen Recording and Accessibility are
both granted, so `screencapture -R<x,y,w,h>` captures the window and
`osascript`/System Events sends keystrokes. Get the window rect with
`tell application "System Events" to tell process "incursion" to return
(position of window 1) & (size of window 1)`. Brian is still faster at play-testing;
use this for unattended verification, not for things he can check in ten seconds.

## Diagnostic instrumentation

All environment-gated and off by default:

- `INCURSION_ERROR_PROMPT=1` — restore the old blocking error dialog.
- `INCURSION_SAVE_PROBE=1` — log player position either side of save/load
  (`logs/saveprobe.log`).
- `INCURSION_MAP_PROBE=1` — log what `ShowMap()` drew (`logs/mapprobe.log`).
- `-DFLICKER_PROBE` at compile time — log the luminance of every presented frame.
- `tools/run_probe.sh` — launcher that sets the runtime probes. Temporary.
