# iNCURSION

A fork of [Incursion](http://incursion-roguelike.net), Julian Mensch's D&D 3.5
roguelike, brought to macOS and POSIX.

The original runs on Windows only. This fork builds, runs, and plays natively on
macOS ARM64 — and compiles its own game data along the way.

```
brew install sdl2 pkg-config
./build_macos.sh
./incursion
```

Two minutes from a clean checkout.

---

## Status

| | |
|---|---|
| **macOS ARM64** | Builds, plays, saves, loads |
| **Terminal (curses)** | Plays in any POSIX terminal — no SDL, no libtcod |
| **Headless** | Plays itself from a key script, with no display |
| **macOS x86_64 / universal** | Not yet |
| **Linux** | Not yet — unblocked, next up |
| **Steam Deck** | The target. Waits on Linux. |
| **Windows** | Still works; see below |

Character creation, exploration, combat, save and load all work. The game
compiles its own 82,768-line ruleset into a data module on first build.

---

## What this fork fixed

The upstream README says a POSIX build *"just failed to find exported symbols it
should have been able to find"*. That diagnosis is wrong, and believing it is
what kept the port stuck.

**The real cause: `src/RComp.cpp` is wrapped in `#ifdef DEBUG`, while the
generated `src/yygram.cpp` calls into it unconditionally.** Build with `-DDEBUG`
and it links. One consequence worth knowing: every macOS build is a DEBUG build.

Three more findings, each of which had to be fixed before the game was playable:

**`int32` was `typedef signed long`.** Windows is LLP64, so `long` is 4 bytes
there. macOS and Linux are LP64, where it is 8. Every "32-bit" type in the
codebase — `int32`, `uint32`, `rID`, `hObj`, `hText`, `hCode`, `hData` — was
silently 64-bit off Windows. Narrowing the typedefs dropped printf format
mismatches from 325 to 26.

**Narrowing the typedefs then destroyed every save.** `inc/Map.h` did
`*((long*)&hm)`, writing 8 bytes into what had become a 4-byte field. The
overrun covered the `int16 x,y` declared immediately after it, so **every save
zeroed the player's position**. Loading placed the character at (0,0) — the
map's solid outer corner — where the game crushed them to death on the first
turn. Fixed, and now guarded at compile time by `src/AbiCheck.cpp`.

**Monster AI read off the edge of the map, 343 times in 13 seconds.**
`Map::At()` answers an out-of-bounds query by returning the square at (0,0)
rather than failing, so wrong answers looked real. Guarding the single function
every accessor funnels through took the error log from 444 entries in 13 seconds
to **zero across 877 turns**.

That last one is an upstream defect, not a port artefact, and it has been sent
back: [rmtew#40](https://github.com/rmtew/incursion-roguelike/issues/40) and
[rmtew#41](https://github.com/rmtew/incursion-roguelike/pull/41).

---

## Roadmap

### Short — make it run everywhere

All engineering. None of it changes the game.

- Linux x86_64 build. Unblocked: the ABI audit that gated it is done, and every
  serialised type is proven byte-identical on arm64 and x86_64.
- macOS x86_64 slice and a universal binary.
- **Steam Deck.** The concrete platform target, and why Linux comes first.
- ~~An ncurses backend, which would make the game text-capturable and
  scriptable~~ — **done**, see *Playing itself* below. What remains is drawing
  to a real terminal, so the same binary can be played over ssh.
- HiDPI and resolution handling. Options currently top out at 1920x1200.
- Drain `logs/errors.log` through real play, and clear the known defects:
  contents-list corruption in `Thing::Remove`, a `FI_SIZE` inconsistency,
  window flicker on Metal, 58 format-string defects.
- Four comprehension passes over the engine — map and creature model,
  serialisation, the IncursionScript compiler, and event dispatch — because
  everything below this line needs a map of the engine first.

### Mid — finish the game that is already here

This is the real work. Incursion ships with a great deal of content that is
described but not built, and the game says so itself.

- **Complete the incomplete.** Eight playable races — kobold, gnome, dwarf, elf,
  drow, halfling, lizardfolk, orc — have their subrace sections labelled
  `(Unimplemented)` in the game's own help text, while `lib/subraces.irh`
  compiles 924 lines of subrace definitions. Whole feat trees, including every
  Fighter capstone line, carry the same label. Across `lib/` there are 64
  markers of unfinished work.
- **Fix the core ruleset bugs.** Every entity's prose specification sits in the
  same file as its implementation, so a mismatch between the two is a provable
  defect that needs no C++ at all. That is the richest bug seam in the project.
- Finish the skills and classes that advertise more than they deliver.

### Long — build past it

- **Addons.** World mode. More dungeons. New content that goes beyond what
  Julian Mensch shipped, rather than completing it.

Work is tracked in [Beads](https://github.com/gastownhall/beads) (`bd ready`),
not in this file.

---

## Playing itself

The game now has a third terminal backend, and it does two jobs. `src/Wposix.cpp`
looks at its own standard input and output. Given a real terminal it runs a live
curses UI. Given anything else it takes its keystrokes from a file and writes its
screen to a file, so a session runs with no display, no keyboard and nobody
watching.

```
BACKEND=posix ./build_macos.sh                    # links no SDL, no libtcod
tools/headless.sh tools/keys/smoke.keys 1         # one session
tools/headless.sh --tty tools/keys/smoke.keys 1   # the same, drawn by curses
tools/soak.sh 200 1                               # two hundred dungeons
```

The curses UI was not a goal. It fell out of building the harness, and it is the
first way to play Incursion in a terminal on any platform — the existing
`src/Wcurses.cpp` is Windows and pdcurses only.

It also leaves the engine unusually easy to re-skin. The backend narrowed the
game to two chokepoints: output is one plain array of `Glyph`, and input is one
`ScriptKey`, which a live keystroke and a script token both become before
anything downstream sees them. A new front end has to satisfy those two and
nothing else.

Short runs repeat exactly. The game used to reach for the clock as a source of
randomness in six places, so no two sessions ever matched and no screen could
be compared with an earlier one; `INCURSION_SEED` now replaces all six. The
same seed and the same key script produce byte-identical screens, and a
different seed produces a different game — both checked, in both directions.

**Long runs do not**, and that was measured on 2026-08-15, after this section
first claimed otherwise. Over a full dive, seed 8 stays byte-identical for two
screens and then parts company: at depth 12 one run has the character alive
with the map drawn, and the other has `You are drowning!` and `You die...`.

The dice are not the cause. The same binary run thirty times with address
randomisation switched off was identical thirty times; the same binary with it
switched on was not, four runs in fifteen. So the game reads a memory address
as if it were data. One of the places it does that is now known, and it is not
subtle — `TargetSort` in `src/Target.cpp` ordered two equally-rated targets by
**subtracting their objects' addresses**. Every reader of that list takes the
first match, so the address ordering chose which target a monster attacked, and
one decision was enough to end the game differently. `git blame` puts the line
in the 2014 import: it is original Incursion, not a port defect, and it is
wrong on Windows and Linux too, both of which randomise addresses as standard.

Fixing it makes seed 8 repeat, eighteen runs out of eighteen. It does **not**
close the subject: seed 3 still produces four outcomes in twenty-four runs, and
diverges inside `Map::Generate` instead. It is the same class of fault — that
binary is also identical ten times out of ten with randomisation off. So this
is a defect class rather than a bug, tracked in `inc-dhc`.

The tool that finds them is in the tree, behind `#ifdef DIVERGE_PROBE` and
compiled into nothing by default:

```
EXTRA_CXXFLAGS=-DDIVERGE_PROBE OUT=incursion-probe BACKEND=posix ./build_macos.sh
tools/keys/dive12.keys      # the six-second reproducer, seed 8
```

It counts every random number the game draws and prints the running total at
map generation, at each creature's action, and at the monster's target list.
Two runs of one seed draw the same numbers in the same order until something
outside the generator changes a decision, so **the first probe where the counts
differ is the first place the two runs stopped playing the same game.** That is
what located the sort, starting from nothing more than a screen that differed.

That determinism holds for one binary. It does **not** survive a code change, and
a measurement on 2026-08-15 settled how to compare two builds. Almost any correct
fix shifts the game state a little, and from the first changed decision onward the
screens diverge and the crashing seeds move: across two controlled A/B pairs the
seed that segfaulted moved between 3362 and 3387 depending on which fix was
present. So neither screen equality nor "does seed N crash" is a usable
regression signal here. Error volume and message-set membership are. Those held
still and stayed readable — 89,545 asserts to zero for one fix, with the
post-change message set a strict subset of the pre-change one.

That is now a gate rather than an argument:

```
tools/gate_record.sh tools/keys/dive.keys 40 1   # what this build complains about
tools/gate_compare.sh                            # what the next one complains about
```

`record` plays the seeds and writes `tools/gates/dive.baseline`, which is
committed. `compare` plays them again on the current build and fails on a
message the baseline has never seen, on sessions that stopped reaching a map,
and on new `Fatal()` or watchdog endings. A message that has *gone* is reported
as a fix, not a failure. Volume is reported and never failed on, because a
change that keeps the character alive longer produces more turns and therefore
more of everything.

Two things it deliberately tolerates. A message seen in only one or two
sessions is printed but not failed on, because the engine produces those by
itself (`inc-dhc`); a real regression of this kind arrives in many sessions at
once, as the 89,545 did. And it detects only what reaches a log — a defect that
silently does the wrong thing and says nothing passes clean. It never replaces
a play-test.

It was shown to fail, not merely to pass: reverting the `Target` zero-init and
rebuilding moved the gate from `PASS` to `FAIL` with 378 assertions at
`inc/Base.h:577` across 18 of 40 sessions, and restoring the fix returned it to
`PASS`.

**A run that measures nothing now says so.** A session whose keystrokes are all
eaten by character generation never enters a map, and the game exits 0. The
harness used to report that as a clean pass, and 250 such sessions were once read
as evidence that a fix worked. `tools/headless.sh` now promotes that ending to
exit 5, `NO GAMEPLAY`; `tools/soak.sh` counts it by name and warns; and
`check_headless.sh` asserts it, having been shown to fail without the guard.

This is what makes `logs/errors.log` — the best defect finder this project has
— fill up without a person. The first six-session soak produced a one-line
recipe for a defect that previously had none:

```
tools/headless.sh tools/keys/explore.keys 101
```

A celestial mastiff claims the map while appearing in neither list the map
keeps, and it keeps *moving* for thousands of turns afterwards.

The same backend runs the game's own ruleset checker, which had never been part
of anyone's workflow because it drew its report into a scrollable box on
screen. It now also writes `logs/consistency.txt`.

Reading that report carefully was worth more than running it. Its largest
section is headed *Purposeless Effects*, and the name is a trap: `Purpose` is
the monster-AI spell-selection hint, not an implementation flag. A zero there
means *no monster will ever choose to cast this*, not *this does nothing* —
and `EP_PLAYER_ONLY` is `0x00000`, so a deliberate player-only spell is
indistinguishable from an unfinished one. Of the 136 entries, none were found
to be unimplemented. Nine are the real finding: spells that appear only on a
monster's list, which that monster can therefore never cast.

### What the soaks have found so far

About 1,100 unattended sessions have run. One engine defect is fixed and
measured, eight more are diagnosed to root cause with a reproducing seed, and
one claim had to be withdrawn.

**Fixed and verified.** `TargetSystem::giveOrder` built its `Target`
uninitialised, so an escort read stack garbage as the handle of the creature to
follow and walked toward an arbitrary object instead of its leader. Two of the
eight construction sites also left `damageDoneToMe` uninitialised, which turned
escorts hostile to their own leaders after a stray hit. Zero-initialising all
eight, measured over 250 seeds against a build differing in nothing else:

| | asserts at `Base.h:577` | total error lines |
|---|---|---|
| before | 89,545 | 139,948 |
| after | 0 | 48,245 |

**Withdrawn.** A second change — making `Player::MoveDepth`'s follower array
re-entrant — was committed as a segfault fix. It is not one. A controlled A/B
showed the same seed segfaulting identically with and without it, on the same
stack. The re-entrancy it describes is real and the stack proves it, so the
change is kept as hardening, but the crash claim was wrong and is retracted in
the history.

The original measurement passed because the scratch worktree it ran in lacked
the modified `Options.Dat` this tree uses, so no session in either arm ever
entered a map. Two runs that both did nothing agreed perfectly. That is the
whole reason for the `NO GAMEPLAY` exit code above.

## How this project works

**Agents own the C++.** Port, engine, build and harness are all
machine-checkable, and six regression checks run on demand:

```
./tools/check_abs_path.sh        # the relative-directory bug
./tools/check_error_handling.sh  # error reporting stays non-blocking
./tools/check_abi.sh             # type widths + handle/pointer confusion
./tools/check_headless.sh        # unattended play, and that short runs repeat
./tools/check_strqueue.sh        # the string queue's bound
./tools/check_gate.sh            # the regression gate reaches the right verdict
```

Each has been proven to *fail* when its defect is reintroduced, not merely to
pass. `check_headless.sh --selftest` demonstrates its own assertions rejecting
known-bad input.

**A human owns the ruleset.** `lib/` holds 82,768 lines of IncursionScript —
1,469 event handlers, 522 monsters, 264 items, 191 effects, 39 classes, 17
races. Every entity's prose specification sits in the same file as its
implementation, so a mismatch between them is a provable bug. But no agent can
tell an intentional Incursion divergence from D&D 3.5 apart from a defect. A
person who knows 3.5 can.

**Nothing goes upstream on reasoning alone.** `docs/REPORTING-GATE.md` holds the
four questions any public claim must answer, and the rule that only findings
where an oracle changed state — with numbers on both sides — get sent to the
parent project.

More detail: [`docs/PORT-STATUS.md`](docs/PORT-STATUS.md) is the running state of
the port and should be read before touching anything.

---

## Upstream

This is a fork of [rmtew/incursion-roguelike](https://github.com/rmtew/incursion-roguelike),
which remains the parent project and where fixes are sent.

- **Julian Mensch** wrote Incursion and released the source.
- **Richard Tew** has maintained it since, and vendored the dependencies that
  make old builds reproducible.
- **Kyle Benesch** (HexDecimal) did substantial modernisation work in 2024 —
  standard types, `std::min`/`max`, dead-code removal, CI. A sibling fork worth
  reading before writing anything new.

Port artefacts stay here. Genuine upstream defects go back to rmtew.

---

## Windows

The original build still works and is unchanged by this fork. Pre-compiled
dependencies are included; the scripts below rebuild them if needed.

```
build_sdl2.bat        # SDL2
build_libtcod.bat     # libtcod
build_pdcurses.bat    # pdcurses
build.bat             # Incursion itself
```

`build.bat` produces `IncursionLibtcod.exe` and `IncursionCurses.exe`.
`modaccent.exe` builds in Debug configuration only.

**Why the dependencies are checked in, in Richard Tew's words:** bug fixes to
gameplay require a save game, and a save game only loads in the build that wrote
it. Character creation in Incursion is varied enough that a player often cannot
remember what they picked, so reproducing a report without their save is a wild
goose chase. Keeping every binary and every source version is what makes an old
save debuggable at all.

Module compilation is built into the Debug build and offered in the game menu.
It is kept out of Release builds for GPL reasons.

---

## Links

- [Incursion website](http://incursion-roguelike.net)
- [RogueBasin page](http://www.roguebasin.com/index.php?title=Incursion)
- [Bay12 thread](http://bay12forums.com/smf/index.php?topic=139289) — the old
  discussion home

## Licence

See [LICENSE](LICENSE). Incursion is Julian Mensch's work; this fork changes
nothing about that.
