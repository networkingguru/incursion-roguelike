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
- An ncurses backend, which would make the game text-capturable and scriptable —
  and therefore testable without a human at the keyboard.
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

## How this project works

**Agents own the C++.** Port, engine, build and harness are all
machine-checkable, and three regression checks run on demand:

```
./tools/check_abs_path.sh        # the relative-directory bug
./tools/check_error_handling.sh  # error reporting stays non-blocking
./tools/check_abi.sh             # type widths + handle/pointer confusion
```

Each has been proven to *fail* when its defect is reintroduced, not merely to
pass.

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
