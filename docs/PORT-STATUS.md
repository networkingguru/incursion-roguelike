<!-- citations: this-port -->

# Port status

Last reviewed 2026-08-20. This is the running state of the macOS/POSIX port.

**Where the current truth lives.** This file drifts, because it is written during
investigations and not revisited when they end. Before trusting anything here:

| Question | Authoritative source |
|---|---|
| What is fixed, and how it was verified | [`FIXED.md`](FIXED.md) |
| What is open right now | `bd ready`, `bd list --status open` |
| What went upstream and what became of it | [`REPORTING-GATE.md`](REPORTING-GATE.md) |
| How to build, package and ship | [`../README.md`](../README.md) |

`bd list --status closed` shows the closed issues. The port ships as a
signed and notarised `Incursion.app`; the plain-folder layout this document
describes in places was withdrawn because a bare executable cannot be approved by
Gatekeeper (inc-g1y). Saves now live in
`~/Library/Application Support/Incursion/`, not beside the game.

**Closed since 2026-08-17**, all with their evidence in
[`FIXED.md`](FIXED.md): the bottom-of-dungeon null dereference on all four
routes that reach it; a hiding monster deleting itself inside `Reveal()`; the
`Rect::PlaceWithin` inversion that put doors in solid rock, which is also the
real cause behind the withdrawn `Map::At()` report; a failed save and a refused
load each taking the process with it; the target cursor's one-axis scoring; the
store menu never scrolling; `<` and `>` doing nothing on the overview map; the
six C escapes the port's path sweep ate; colliding run directories; and the
`Natural Weapon Speed` balance option.

## RESOLVED 2026-08-14: keyboard input dies — it was the machine, not the game

**Outcome: not our bug.** Confirmed and closed as inc-4bh / commit `9284bb8`,
"Move the input failure out of the engine and onto the machine". The window
session was degraded; the game was healthy throughout. The investigation is kept
below because the method is reusable and because the suspects below were
eliminated, which is worth not re-doing.

The single most useful takeaway: **use `lsappinfo`, not AppleScript/System
Events**, when asking which application is frontmost or whether a process owns a
window.

The original notes follow, unedited.

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
`git merge-base --is-ancestor c5bfa41 upstream/master`. This may well have been
deliberate on Richard's part, so it has NOT been raised with him.
`HexDecimal/incursion-roguelike` (Kyle Benesch, the current libtcod maintainer) has
unmerged topic branches from Aug 2024 — `standard-types`, `libtcod-1.24.0`,
`minmax`, `char-funcs`, `mod-arch`, `vcpkg-manifest` and others. That is real work
already done, but **most of it is Windows plumbing**: MSVC project files, CI
workflows, vcpkg. Measured 2026-08-14 -- the full stack touches 124 files and
overlaps 19 of the 50 our port touches, including every core header. Rebasing
onto it would also put us on a base rmtew does not have, so our patches would
stop applying upstream. Decision: do NOT rebase. Cherry-pick at most
`fix-27` (a real array overflow), `fix-mapiter` (still open as PR #34),
`minmax`, and `standard-types` (better than ours, but we have a working
equivalent and adopting it means rewriting `src/AbiCheck.cpp`).

Brian's fork is `networkingguru/incursion-roguelike` (public, issues enabled). It
is git remote **`origin`**, not `mine` — an earlier version of this line named a
remote that does not exist. The remotes are `origin` (the fork), `upstream`
(rmtew), and `hex` (HexDecimal).

Bugs are tracked in Beads locally; the GitHub issue tracker on the fork is for
reports from outside, which is where networkingguru#6 came from.

## The three findings that mattered

**`int32` was `typedef signed long`.** Windows is LLP64 so `long` is 4 bytes; macOS
and Linux are LP64 where it is 8. Every "32-bit" type in the codebase — `int32`,
`uint32`, `rID`, `hObj`, `hText`, `hCode`, `hData` — was silently 64-bit off Windows.
The codebase catches this itself: `inc/RComp.h:221` asserts
`sizeof(int32) <= sizeof(VCode)` and fires on every opcode the resource compiler
emits. Narrowing the typedefs in `inc/Defines.h` dropped printf format mismatches
from 325 to 26.

**Narrowing the typedefs then broke saving.** `inc/Map.h:664` did
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
instead. **2026-08-17: "no `(long*)` cast remains" was too strong.** Eight
survive, all in `src/Art.cpp` (`:550`, `:552`, `:554`, `:556`, `:1337`, `:1339`,
`:1341`, `:1343`). They are not the same defect: each casts the return of
`malloc`/`realloc` for an array declared `long`, and the matching `sizeof(long)`
is on both sides, so the width is self-consistent whatever it is. Nothing is
serialised through them. Correct the sentence, do not "fix" the casts. The audit
that swept for the rest of this class is below.

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
| ~~Screen flicker, whole window dims or brightens~~ | **FIXED 2026-08-14 by `c564e6d`. inc-4bh closed, GitHub #4 closed 2026-08-17.** The cause and the one residual are at the END of this cell; everything between here and there is the pre-fix investigation, kept because the eliminations are reusable. **Repeatable trigger found 2026-08-14: on the options screens, move the selection up and down. The whole screen brightens, then dims a few seconds later.** Two hypotheses are dead: the `BlinkCursor()` theory (disproved by a 1200ms build), and a display-level content-adaptive backlight (disproved by Brian's control test -- other apps on the same display, including black-background terminals, never do it). **`-DFLICKER_PROBE` cannot answer this**: it runs inside libtcod's `actual_rendering()`, so it samples only when the game presents, and the game presents ~2/sec with gaps to 3.4s. Anything changing between presents is invisible to it, which explains both its flat 8.99 reading and the multi-second ramp. Replacement instrument is `tools/flickerscan.sh`, which samples the composited screen every 500ms; noise floor measured at 0.011 against a 0.5 threshold. **Untested against the real bug** -- blocked by the input problem above. **2026-08-14: the flicker may not be ours either.** With input dead, hovering the window's close/minimise buttons brightens the whole window and dims it seconds later. That is a window gaining and losing the active appearance, which fits "correlated with keypresses, not periodic" better than any renderer theory. **FIXED 2026-08-14 by `c564e6d`, and everything above this line is the pre-fix investigation — read it as history, not as open work.** inc-4bh is closed. The cause was that on menus the game waits for a key with the cursor off and *nothing presents at all*; the window sits unchanged for seconds and macOS dims it. Loading a game appeared to fix it only because `CursorOn()` then makes the cursor blink repaint every 300ms forever. The fix repaints on that same 300ms tick when the cursor is off — not a guessed rate, since the cursor-on state already used it and demonstrably never flickered. Brian confirmed the flicker is gone in play. It treats the symptom: the pixels were proven clean over 957 frames, and why the window server dims a quiet window is still unidentified, so `src/Wlibtcod.cpp:1837` carries a `ponytail:` marker naming the ceiling (one wasted repaint every 300ms forever, which is battery on a handheld and therefore matters for the Steam Deck target) and the upgrade path. **One residual, never retested:** an unfocused instance still showed a 10s repaint gap on the startup screen, so at least one screen does not run the tick. |
| `Thing::Remove` list corruption | **Line numbers below have drifted; as of 2026-08-20 the message is at `src/Display.cpp:2001`, and there is a sibling at `:1728` for `Thing::Move` that calls `Fatal()` instead of `Error()` — the same inconsistency is fatal on one path and survivable on the other. Two things now make this tractable that did not exist when this was written: an instrumented build behind `-DINC6D5_PROBE` (`src/Display.cpp:46-152`) that logs every Move/Remove/PlaceAt for a named creature with a call stack and also watches its square, and the map audit's orphan check finally having the mount/engulf exemption its own first check has — that was burying this signal under thousands of by-design findings per run, and orphan counts are now single digits per seed. Frequency in scripted play: 2 occurrences across a 40-seed run, which is NOT comparable to the 57-in-13-seconds figure below because the exposure is completely different.** `Contents list wierdless in Thing::Remove!`, `src/Display.cpp:1160`, 57 occurrences in one session. **The name misleads: the list is not corrupt.** The Thing simply is not in the chain of the square it claims. The damage is the bare `return` at :1161, which skips the rest of teardown -- `m`/`x`/`y`/`Next` keep stale values, `CleanupRefedStati()` never runs so other creatures keep dangling references, and `F_DELETE` plus the destroy-queue push never happen. It has already been dropped from `Things[]`, so it becomes a zombie in neither list, never destroyed. An engulf-related root cause was hypothesised and **disproved** (`Thing::Remove` handles ENGULFED and nulls `m`, so the Contents walk never runs). **2026-08-17: that disproof cited `:1084`, which has drifted and now holds a `LineOfSight` test. The real site is `src/Display.cpp:1925-1928`, inside `Thing::Remove` which begins at `:1918`. The disproof still stands; only the citation was wrong. It matters because this line number is the whole evidence for ruling engulf out of inc-6d5.** Root cause still unknown. `src/MapAudit.cpp` detects the zombie signature; run with `INCURSION_MAP_AUDIT=1`. See bead inc-6d5. |
| `FI_SIZE` inconsistency | `Map::GetAt()` finds `FieldAt(x,y,FI_SIZE)` true with no matching entry in `Fields[]`. Fired during monster AI; not seen since. **2026-08-17: there are TWO such `Error()` sites, `src/Display.cpp:680` and `:1517`, not the one this entry originally named. And it has appeared zero times across the kept 40-seed gate runs since `Map::GetAt()` started refusing out-of-bounds coordinates — weak support for the theory that it was a consequence of that bug, not proof, since it was only ever seen once and absence in scripted play is not absence.** |
| Negative map scroll offsets | The clamp that would stop `XOff`/`YOff` going negative is commented out at `src/Term.cpp:1005-1015`. Harmless once positions are correct, but it turned the save bug into a fully blank screen instead of a visibly wrong one. **2026-08-17, first attempt, WRONG — retracted the same day.** It said "there is no commented-out `XOff` clamp anywhere in `src/Term.cpp` now". There is: the whole clamp block is inside `/* */` at `src/Term.cpp:1043-1057`. Only the line number had drifted, and the original entry was true. Two lessons, both cheap: a failed grep is not an absence, and a retraction needs the same evidence bar as the claim it retracts. Note also that the commented-out code is malformed — `if(XOff<0 &&` at `:1044` has no right-hand operand — so it could never have compiled as written, which suggests it was disabled part-way through an edit rather than deliberately retired. Note also that a negative `XOff` is deliberate in one case — `src/Term.cpp:1013` sets `XOff = -((MSizeX() - m->SizeX())/2)` on purpose to centre a map smaller than the window — so "negative is wrong" is too strong as written. Re-derive this entry from the code before acting on it.** |
| Resolution warning on startup | `Wlibtcod.cpp`. Pre-existing, matches an open upstream issue. Options top out at 1920x1200; no Retina/HiDPI handling. |
| 58 format-string defects | 26 residual type mismatches, plus 32 that are live bugs on Windows too. **2026-08-17: the enumeration step written here is already done and is now a no-op.** `Format()` carries `__attribute__((format(printf,1,2)))` at `inc/Base.h:185`, as does `Error()`. So the 58-defect count cannot be reproduced by "add the attribute"; it needs a compile with the attributes already in place. Note that `build_macos.sh:152-153` puts `-w` in both `CXXFLAGS` and `CFLAGS`, which silences every warning, so a normal build shows none of these. Compile with `-Wformat` and without `-w` to see them. |
| ~~No headless mode~~ | **DONE.** The ncurses backend exists (`BACKEND=posix`), and the harness drives the game from key scripts with no display. Closed as inc-73g; roughly 1,100 unattended sessions had run by 2026-08-17, and the gate has added to that on every change since. |
| No x86_64 slice, no universal binary, no Linux run, no CI | |
| `build.sh` does not build on macOS | **Held on purpose, not a regression.** It is upstream's: Richard Tew added it in `ab1053f` (2025-06-28) with the Windows batch scripts, this fork has never touched it, and it carries no `darwin`/`macos`/`uname` handling at all. It compiles libtcod's vendored zlib, which `build_macos.sh:139` deliberately skips for the reason at `:128`. Measured 2026-08-20: dropping to `-std=gnu89` does NOT rescue it, because `libtcod/src/zlib/zutil.c` fails at every standard inside the SDK's own `_stdio.h`, at line 322 of the copy on this machine, on the `fdopen` redefinition. That header is in no repository and its line numbers move with the Xcode version, so the number records this run and is not a citation into either tree. Use `build_macos.sh`. Whether `build.sh` is repaired as the Linux on-ramp or retired is a decision deferred to the Linux/Steam Deck work: bead inc-7ud.1. Do not repair it as a drive-by. |
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

**MID — finish the shipped ruleset.** **D** (`inc-tek`), the real work: the
races whose subraces the game's own help marks `(Unimplemented)`, the Fighter
capstone feat trees, and the markers of unfinished work across `lib/`. Not gated
on C — Brian can fix content today without an engine map.

**LONG — addons.** **E** (`inc-pw1`): world mode, more dungeons. Content beyond
what Mensch shipped rather than completing it.

The Steam Deck waits on Linux.

GitHub issues on `origin` (`networkingguru/incursion-roguelike`) hold only the
defects that are genuinely upstream bugs rather than port artefacts, so they can
be reported to `rmtew`/`HexDecimal` later. Those are cross-linked from Beads via
`external-ref` (`gh-2`, `gh-3`, `gh-4`, `gh-5`). The remotes are `origin` (ours),
`upstream` (rmtew) and `hex` (HexDecimal); there is no remote named `mine`.

**Read `docs/REPORTING-GATE.md` before writing anything public.** It holds the
four questions every claim must answer — reachability chain, provenance, blast
radius, confidence tier — and the rule that only Observed-tier findings may go
to `rmtew` or `HexDecimal`.

**Pull requests have been sent to rmtew, and one is merged.** See the table
under "Sent to rmtew" in `docs/REPORTING-GATE.md` for the current state of #41,
#42, #43 and #44. As of 2026-08-19 both of his open threads are answered: the
#40 correction that withdraws the monster-AI cause, and issue #8 on automated
testing, open since 2024. An earlier version of this paragraph said nothing had been
sent; that was wrong, and it was wrong on the one subject this paragraph exists
to govern.

Two rules bind every outward-facing item, and neither has an exception. Brian
reads the literal text — the exact title and body — before it is published; a
"go" that answers a plan is not approval of wording he has not seen. And every
public contribution discloses AI assistance, put in before he is shown the
draft. Both were broken on 2026-08-15. See `CLAUDE.md`.

## Who verifies what

Agents own the C++: port, engine, build, harness. All machine-checkable.

Brian owns the ruleset in `lib/*.irh` — the IncursionScript that holds the
`On Event` handlers, the monsters, the items, the effects, the classes and the
races. (Count the lines with `cat lib/*.irh | wc -l`, and each entity kind with
`grep -ch '^Monster "' lib/*.irh`. Do not compare these counts
against `lib/program.i`, which is the preprocessed live set and differs.)
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

**The full inventory is in the README's
[For developers](../README.md#for-developers) section**, which lists the main
switches with the question each answers, and in [`DEVTOOLS-AUDIT.md`](DEVTOOLS-AUDIT.md),
which carries a verdict on each. What follows is the part specific to this
document: how they are armed, and the three that were deleted.

Environment-gated diagnostics cost nothing when the variable is unset, so they
ship in every binary. Compile-time probes need
`EXTRA_CXXFLAGS=-D<SYMBOL> ./build_macos.sh` and reach no shipped build.

```sh
INCURSION_MAP_AUDIT=1 tools/play.sh                       # env-gated
EXTRA_CXXFLAGS=-DPATH_PROBE OUT=incursion-path ./build_macos.sh   # compile-time
```

Environment-gated, as of 2026-08-23:

| Variable | What it answers |
|---|---|
| `INCURSION_SEED` | Determinism. Every measurement in this project rests on it. |
| `INCURSION_MAX_KEYS` | The headless key budget. |
| `INCURSION_MAP_AUDIT=1` | Every Thing must appear both in `m->Things[]` and in the Contents chain of the square it claims (`logs/mapaudit.log`). Runs every tenth turn and the instant `Thing::Remove` fails to unlink. The log carries a header when armed, so a silent log means "clean" and an absent log means "never ran". |
| `INCURSION_SAVE_PROBE=1` | Player position either side of save/load (`logs/saveprobe.log`). |
| `INCURSION_MAP_PROBE=1` | What `ShowMap()` drew (`logs/mapprobe.log`). |
| `INCURSION_CHAR_PROBE=1` | Writes a readable character sheet beside every save, automatically. |
| `INCURSION_ERROR_PROMPT=1` | Restores the old blocking error dialog. |
| `INCURSION_TARGET_PROBE=1` | Each target-cursor press and where it landed. Behind `check_target_order.sh`. |
| `INCURSION_STAIR_PROBE=1` | The staircase candidate list and its ranking. Behind `check_stair_cycle.sh`. |
| `INCURSION_DOOR_PROBE=1` | `DoorFlags` either side of `Door::SetImage`'s orientation branch. Behind `check_broken_door.sh`. |
| `INCURSION_QUIET_PROBE=1` | Whether a handle lookup spoke. Behind `check_quiet_lookup.sh`. |
| `INCURSION_SAVE_FAIL_AT=N` | Stages a save failure at a chosen point, throwing what a short write throws. Fires once per process. A real full disk cannot reach the interesting case, because both write loops write into memory first. |
| `INCURSION_STACK_PROBE=1` | Nested entries into depth changes. Found the bottom-of-dungeon crash. |
| `INCURSION_FOLLOWER_PROBE`, `INCURSION_GOWITH_PROBE` | Follower loss across a level change. |
| `INCURSION_FALL_CHAIN`, `INCURSION_FALL_CHAIN_SKIP`, `INCURSION_CHASM_WALK`, `INCURSION_LEVITATE_CHASM` | The chasm and falling investigations. |
| `INCURSION_DUNGEONMAP_PROBE`, `INCURSION_DESCEND_PROBE` | Dungeon and descent structure. |
| `INC6D5_PROBE_NAMES` | Names the creatures `INC6D5_PROBE` follows. |

Compile-time:

| Symbol | What it answers |
|---|---|
| `-DDIVERGE_PROBE` | Counts every random number drawn. Two runs of one seed draw the same numbers in the same order unless something outside the generator changed a decision, so the first differing count is the first place two runs stopped playing the same game. |
| `-DINCURSION_LAYOUT` | Shifts every heap allocation by a seeded offset, so an address-dependent decision splits on demand instead of by luck. The other half of `DIVERGE_PROBE`; `tools/check_layout.sh` depends on it. |
| `-DPATH_PROBE` | Pathfinding work per call. Showed one line to be 89% of a burst. |
| `-DPALETTE_LOG` | Repaint, keypress, palette and window-rect logging. This is the instrumentation that settled the flicker. |
| `-DINC6D5_PROBE` | Names the creature and the code path behind each orphan the map audit reports. |
| `-DTARGET_PROBE`, `-DRETARGET_PROBE` | Names the target type behind every bad handle reaching the failing branch. Settled the one change merged upstream. |
| `-DINCURSION_OOB_PROBE` | Names the creature and code path behind each out-of-bounds map read. |
| `-DINCURSION_OOB_UNGUARDED` | Removes the `Map::GetAt` guard, restoring the original behaviour for an A/B. |
| `-DINCURSION_OOB_RECTFIX`, `-DINCURSION_OOB_RANGEFIX` | Behaviour variants from the level-builder investigation. The widening variant is no longer a variant: it shipped in `3208aa7`. |
| `-DSTRING_QUEUE_SIZE=N` | A size override, not a `getenv`. `tools/check_strqueue.sh` builds against it. |

Instruments have been deleted, and each deletion is the record rather than
housekeeping:

- **`-DFLICKER_PROBE`, deleted 2026-08-18.** It logged luminance per presented
  frame, sampling only inside libtcod's `actual_rendering()`, so it could not see
  anything happening between presents — and the game presenting only about twice
  a second was the flicker itself. The instrument was structurally blind to the
  defect it was built for, and its flat 8.99 reading was true and irrelevant. Use
  `tools/flickercapture.sh` with `tools/flickerscan.py`, which capture and crop
  the real window. See [`DEVTOOLS-AUDIT.md`](DEVTOOLS-AUDIT.md).
- **`INCURSION_DEPTH_PROBE`, deleted 2026-08-23.** It logged, for every level
  `Map::Generate` built, the level's depth, the dungeon's declared depth, the
  number of chasm squares and the number of down stairs the stairs loop was
  asked to place. Its own comment said to delete it once inc-x9i was settled.
  inc-x9i closed on 2026-08-19, fixed in `a8f298a`, and `INCURSION_STACK_PROBE`
  rather than this one carried the before/after evidence. The measurements it
  made are kept in `docs/evidence/inc-x9i/README.md`. See
  [`DEVTOOLS-AUDIT.md`](DEVTOOLS-AUDIT.md).
- **`tools/run_probe.sh`, deleted 2026-08-18.** An older launcher, superseded by
  `tools/play.sh`. Its own header said to delete it once the saved-game position
  bug was fixed, and that bug is fixed. Nothing invoked it.

`tools/play.sh` is the launcher for a real session; it arms the map audit, the
save probe and the character probe. `tools/flickercapture.sh` and
`tools/flickerscan.py` capture the game window, crop to it, and correlate
brightness against repaints; `flickerscan.py` refuses to reach a verdict on black
frames, which is the failure that had the older whole-screen scan confidently
reporting results from captures macOS had blocked, and
`tools/flickerscan_selftest.py` checks that the refusal still works.
