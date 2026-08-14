# Port status

Last updated 2026-08-14. This is the running state of the macOS/POSIX port.
Read it before doing anything else.

## OPEN: keyboard input dies — probably NOT our bug. Reboot first.

**Symptom, from Brian, repeatedly on 2026-08-14:** the game window is visible and
in front, the screen flickers, and **no keyboard or mouse input does anything**.
Clicks on the window's own close and minimise buttons do nothing. The only effect
Brian can produce is hovering over those buttons, which brightens the whole window
and then dims it a few seconds later.

**Leading explanation: the macOS window session is degraded, not the game.**
Status on 2026-08-14 12:58 — awaiting a reboot to confirm or kill.

The evidence that moved it out of our code:

- **`System Settings` fails the same way.** It launches (PID seen alive) and then
  reports "no available windows". It is a fully bundled Apple app. If it cannot
  present a focusable window either, the fault is not our packaging, not SDL, and
  not our build.
- **The game is not hung.** `sample <pid>` puts 99% of samples in `SDL_Delay`,
  with a live `NSApplication` and `NSEventThread`, inside
  `SDL_WaitEventTimeout` → `nextEventMatchingMask:`. It is asking for events and
  being given none.
- **Launch Services says the game is allowed to be frontmost** —
  `lsappinfo info <pid>` reports `type="Foreground"`. It simply never becomes so.
- **The frontmost-app reading is incoherent.** `lsappinfo front` returned Ghostty,
  then `Universal Control` (a faceless `UIElement`), while Brian had the game
  window visibly in front. Activation state has come apart.
- **Uptime was 24 days**, with `WindowServer` and `lsd` both running that whole
  time. The machine took input from the game at 12:01 and not at 12:40, from
  identical source. Nothing in the tree changed between those two runs.

**Next step: full restart (not a logout), then run `./incursion` and press a key.**
If input works, this was never an engine defect and the "flicker" goes with it.
If input is still dead on a freshly booted machine, the entire system layer is
eliminated and Phase 1 starts again on clean ground.

**Ruled out on 2026-08-14, do not re-tread:**

| Suspect | How it died |
|---|---|
| Stale `-DFLICKER_PROBE` objects in the build | `build/obj/` recompiled end to end 12:13–12:14; `strings ./incursion \| grep -i flicker` finds only game prose, no probe symbols |
| A bad option written to `Options.Dat` | 19 bytes differ from the committed copy; decoded against `inc/Defines.h` they are `OPT_KILL_CHEST`, `OPT_DWARVEN_AUTOFOCUS`, `OPT_TERSE_BLESSED`, `OPT_SHOW_HOW_SEE`, `OPT_HIGH_INVIS` and chargen picks. None touch input. |
| A second instance stealing the keys | No `incursion` process running while the symptom was present |
| A crash | No entry in `~/Library/Logs/DiagnosticReports` since 2026-08-13 16:51 |
| The window being a Stage Manager strip thumbnail | Brian looked: the window is genuinely in front |
| `tools/play.sh` doing something the bare binary does not | It only `cd`s to the repo root and exports two env vars |

**`osascript`/System Events is broken on this machine and is a dead end.**
`tell application "System Events" to get name` returns `osascript` — the tell
never reaches the app and silently falls back to the current process, which is
why `process` reads as an unknown class and throws `-2741`. `tell application
"Finder"` still resolves correctly, so AppleScript itself is fine. An agent
restarted the helper with `killall "System Events"` and it then refused to
relaunch at all. **Use `lsappinfo` instead** — `lsappinfo front`,
`lsappinfo info <pid>` — which needs no scripting layer and answers the only
questions that mattered here.

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
./tools/check_abi.sh             # regression check, exits 0 on pass
```

Upstream is `rmtew/incursion-roguelike`, and it is **alive**: Richard Tew committed
on 2025-06-28, including Linux/macOS compilation notes. An earlier claim here that
it was dormant since 2015 was wrong.

**Thirteen of Kyle Benesch's pull requests show as MERGED on GitHub but are not
ancestors of `rmtew/master`.** Master jumps straight from 2018-12-15 to 2025-06-28;
the whole August 2024 block is absent. Verify with
`git merge-base --is-ancestor c5bfa41 origin/master`. This may well have been
deliberate on Richard's part, so it has NOT been raised with him.
`HexDecimal/incursion-roguelike` (Kyle Benesch, the current libtcod maintainer) has
16 unmerged topic branches from Aug 2024 — `standard-types`, `libtcod-1.24.0`,
`minmax`, `char-funcs`, `mod-arch`, `vcpkg-manifest` and others. That is real work
already done, but **most of it is Windows plumbing**: MSVC project files, CI
workflows, vcpkg. Measured 2026-08-14 -- the full stack touches 124 files and
overlaps 19 of the 50 our port touches, including every core header. Rebasing
onto it would also put us on a base rmtew does not have, so our patches would
stop applying upstream. Decision: do NOT rebase. Cherry-pick at most
`fix-27` (a real array overflow), `fix-mapiter` (still open as PR #34),
`minmax`, and `standard-types` (better than ours, but we have a working
equivalent and adopting it means rewriting `src/AbiCheck.cpp`).

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
There were three `(long*)` casts in the tree; the two in `src/Registry.cpp` wrote
into a `void*` and were size-correct on LP64. They now go through `intptr_t`
instead, so no `(long*)` cast remains. The audit that swept for the rest of this
class is below.

**The width audit is done and every serialised type is arch-independent.** A
layout probe compiled for arm64 and x86_64 produced identical sizes and offsets
for all 22 resource tables, all 22 serialised object types and every scalar
typedef. No serialised struct contains a `long`, `long double`, `float` or
`double`, which is why. Linux x86-64 shares the LP64 model and the Itanium C++
ABI, so it should match too; that is inference, not measurement, until a Linux
box runs `tools/check_abi.sh`. `src/AbiCheck.cpp` now pins every width at
compile time, so the next ABI surprise fails the build instead of the save file.

**The upstream README's diagnosis is wrong.** It says POSIX builds fail to locate
exported symbols. The real cause is that `src/RComp.cpp` is wrapped in `#ifdef DEBUG`
while the generated `src/yygram.cpp` calls into it unconditionally. Build with
`-DDEBUG` and it links. A consequence: every macOS build is a DEBUG build.

## Known open

| Issue | Notes |
|---|---|
| Agent damage to be aware of | On 2026-08-14 an agent overwrote `logs/errors-17-15.log` and `logs/errors-before-boundsfix.log` with test fixtures while building `tools/check_logrotate.sh`. Both are unrecoverable; `logs/` is gitignored and there were no snapshots. Each file now holds a note saying what it was. The same agent also loaded `save/Jaoin.sav` and drove 24 moves to verify the map audit, so that save is no longer the one Brian left at 08:39. Use `mktemp -d` for fixtures; never use real `logs/` or `save/`. |
| Screen flicker, whole window dims or brightens | **Repeatable trigger found 2026-08-14: on the options screens, move the selection up and down. The whole screen brightens, then dims a few seconds later.** Two hypotheses are dead: the `BlinkCursor()` theory (disproved by a 1200ms build), and a display-level content-adaptive backlight (disproved by Brian's control test -- other apps on the same display, including black-background terminals, never do it). **`-DFLICKER_PROBE` cannot answer this**: it runs inside libtcod's `actual_rendering()`, so it samples only when the game presents, and the game presents ~2/sec with gaps to 3.4s. Anything changing between presents is invisible to it, which explains both its flat 8.99 reading and the multi-second ramp. Replacement instrument is `tools/flickerscan.sh`, which samples the composited screen every 500ms; noise floor measured at 0.011 against a 0.5 threshold. **Untested against the real bug** -- blocked by the input problem above. **2026-08-14: the flicker may not be ours either.** With input dead, hovering the window's close/minimise buttons brightens the whole window and dims it seconds later. That is a window gaining and losing the active appearance, which fits "correlated with keypresses, not periodic" better than any renderer theory. Re-test after the reboot named in the top section before spending anything more on this. |
| `Thing::Remove` list corruption | `Contents list wierdless in Thing::Remove!`, `src/Display.cpp:1160`, 57 occurrences in one session. **The name misleads: the list is not corrupt.** The Thing simply is not in the chain of the square it claims. The damage is the bare `return` at :1161, which skips the rest of teardown -- `m`/`x`/`y`/`Next` keep stale values, `CleanupRefedStati()` never runs so other creatures keep dangling references, and `F_DELETE` plus the destroy-queue push never happen. It has already been dropped from `Things[]`, so it becomes a zombie in neither list, never destroyed. An engulf-related root cause was hypothesised and **disproved** (`Thing::Remove` handles ENGULFED at :1084 and nulls `m`, so the Contents walk never runs). Root cause still unknown. `src/MapAudit.cpp` detects the zombie signature; run with `INCURSION_MAP_AUDIT=1`. See bead inc-6d5. |
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

Issue prefix is `inc`. The graph mirrors the README roadmap, in three tiers.

**SHORT — engineering, none of it changes the game.** **A** port to
mac/linux/universal, **B** fix the engine bugs, **C** understand the engine
(four comprehension passes).

**MID — finish the shipped ruleset.** **D** (`inc-tek`), the real work: eight
races whose subraces the game's own help marks `(Unimplemented)`, the Fighter
capstone feat trees, and 64 markers of unfinished work across `lib/`. Not gated
on C — Brian can fix content today without an engine map.

**LONG — addons.** **E** (`inc-pw1`): world mode, more dungeons. Content beyond
what Mensch shipped rather than completing it.

The Steam Deck waits on Linux.

GitHub issues on `mine` hold only the defects that are genuinely upstream bugs
rather than port artefacts, so they can be reported to `rmtew`/`HexDecimal`
later. Those are cross-linked from Beads via `external-ref` (`gh-2`, `gh-3`,
`gh-4`, `gh-5`).

**Read `docs/REPORTING-GATE.md` before writing anything public.** It holds the
four questions every claim must answer — reachability chain, provenance, blast
radius, confidence tier — and the rule that only Observed-tier findings may go
to `rmtew` or `HexDecimal`. Nothing has been sent to either yet: no issue, no
pull request. Of what we hold, only `gh-1` currently qualifies.

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
- `-DFLICKER_PROBE` at compile time — logs luminance per presented frame.
  **Do not reach for this.** It samples only inside `actual_rendering()`, so it
  cannot see anything happening between presents, and the game presents ~2/sec.
  A build with it on also left the game unresponsive on 2026-08-14; see the
  blocking section at the top. Build it with
  `EXTRA_CXXFLAGS=-DFLICKER_PROBE OUT=incursion-flicker ./build_macos.sh`,
  which uses a separate object directory.
- `INCURSION_MAP_AUDIT=1` — check the map against itself: every Thing must appear
  both in `m->Things[]` and in the Contents chain of the square it claims
  (`logs/mapaudit.log`). Runs every 10th turn and the instant `Thing::Remove`
  fails to unlink. The log carries a header when armed, so a silent log means
  "clean" and an absent log means "never ran".
- `tools/play.sh` — launcher, turns on the map audit and the save probe.
- `tools/flickerscan.sh` — samples the composited screen every 500ms and reports
  mean luminance over time. Use this for the flicker, NOT `-DFLICKER_PROBE`.
- `tools/run_probe.sh` — older launcher. Its own header says to delete it once the
  saved-game position bug is fixed, which it is. Superseded by `tools/play.sh`.
