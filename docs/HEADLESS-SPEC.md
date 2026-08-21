# Headless terminal backend — specification

**STATUS: IMPLEMENTED AND SHIPPED.** `inc-73g` is closed. This document is the
original specification and is kept for the reasoning, not as pending work —
everything below in the future tense now exists. Build it with
`BACKEND=posix ./build_macos.sh` and drive it with `tools/headless.sh`. It is how
most defects in this port were found.

Tracked as `inc-73g`. Sized: Medium.

## Why

Incursion has two terminal backends: `src/Wlibtcod.cpp` (SDL window, the one
macOS uses) and `src/Wcurses.cpp` (pdcurses, Windows only, excluded from the
macOS build). Both need a human at a keyboard.

That is the binding constraint on this project. `inc-nch` — drain
`logs/errors.log` through play — is the best defect finder here: three
confirmed defects in one evening, zero false positives. Its procedure ends
"play, then hand over the log". A person has to play. So the log only grows
when Brian is at the machine, and agents cannot test their own work at all.

A backend that takes its keystrokes from a file and writes its screen to a file
removes the person from that loop.

## What this is not

Not a replacement for the libtcod backend. The window build stays the way to
play. This is a second binary for testing, and a terminal build for people who
want one.

## Design

### One new file, one new binary

`src/Wposix.cpp` defines `posixTerm : public TextTerm`, guarded by
`#ifdef POSIX_TERM`, in the same shape as the two existing backends: it
implements the platform virtuals TextTerm leaves pure, defines `main()`,
`Error()` and `Fatal()`, and owns file I/O.

`build_macos.sh BACKEND=posix` compiles it instead of `Wlibtcod.cpp` and
produces `./incursion-headless`. It links `-lz` and `-lncurses` and nothing
else — no SDL, no libtcod.

### The screen is a plain array

Both existing backends store the screen in their graphics library's own buffer
(a `TCOD_console_t`, a curses `WINDOW`) and read it back with library calls.
`posixTerm` stores `Glyph scr[48][80]` directly.

A `Glyph` is a `uint32`: 12 bits of glyph id, 4 of foreground, 4 of background
(`inc/Defines.h:4174`). Storing it verbatim makes `AGetChar` exact. The libtcod
backend cannot do that — it stores the character its glyph table produced, so
`GetGlyph` → `PutGlyph` round trips lose the glyph id. The callers
(`src/Term.cpp:2164`, `src/Magic.cpp:1324`, `src/Skills.cpp:1931`,
`src/Skills.cpp:2844`) mask with `GLYPH_ID_MASK` and put the result back, so
exactness is what they want.

This also means the rendering target is not the screen model. The same array
serves both output modes.

### The output modes

| mode | Update() | when |
|---|---|---|
| headless | marks the frame clean, nothing else | `-headless`, or stdin or stdout is not a tty |
| ncurses | blits `scr` to `stdscr`, refreshes | a tty |

### Input comes from a script

`-keys FILE` supplies keystrokes. The file is a token stream; `#` starts a
comment. Tokens:

| token | meaning |
|---|---|
| `a` `Z` `7` | that character. An uppercase letter or shifted symbol also sets SHIFT, as a real keyboard does. |
| `"a string"` | each character in turn |
| `ESC ENTER TAB SPACE BKSP` | named keys |
| `UP DOWN LEFT RIGHT HOME END PGUP PGDN` | named keys |
| `F1`…`F12` | named keys |
| `^D` | that letter with CONTROL held |
| `TOKEN*12` | repeat the token 12 times |
| `@dump` `@dump:label` | write the current screen to `logs/screens/` |
| `@quit` | leave the game at the next key read |

SHIFT matters and is not cosmetic. `StandardKeySet` (`src/Tables.cpp:4573`)
matches `toupper(ch)` against `raw_key` and then compares the modifier flags
exactly, so `{ KY_CMD_ALL_ALLIES, 'A', 0 }` is reached by lowercase `a` and
*not* by `A`. A script that ignored SHIFT would silently dispatch the wrong
commands.

### The screen dump

`@dump` writes `logs/screens/NNNN[-label].txt`: a header line naming the dump
and the key count, then 48 screen rows with their trailing blanks stripped, so
no row is a fixed 80 characters wide. The message and status lines are rows
within those 48 and are not written again at the end. Glyph ids
become ASCII (`GLYPH_WALL` → `#`, `GLYPH_FLOOR` → `.`, `GLYPH_PLAYER` → `@`),
because the consumer is `grep`, not a font.

Dumps happen when the game asks for a key. That is the moment the screen is
settled, so a dump never catches a half-drawn frame.

### Ending a run

Unattended runs must end. The run ends in one of these ways:

1. `@quit`, or the script running out — dump the final screen, exit 0.
2. `INCURSION_MAX_KEYS` (default 20000) reached — dump, log, exit 3.
3. `Fatal()` — log, dump, exit 1.

`StopWatch()` never sleeps in headless mode, and `Error()` never prompts.

### Errors

`LogError()` currently lives inside `src/Wlibtcod.cpp` as a static. Two
backends need it, so it moves to `src/ErrorLog.cpp` beside the rotation code
that already serves it. Its caller passes the directory and the session banner,
so `ErrorLog.cpp` keeps depending on nothing from the game and
`tools/check_logrotate.sh` keeps compiling it on its own.

## Definition of done

1. `BACKEND=posix ./build_macos.sh` links with no SDL and no libtcod.
2. `./incursion-headless -headless -keys tools/keys/smoke.keys` reaches the
   start menu, creates a character, takes turns, and exits 0 with no human
   present and no tty.
3. The dumped screen contains a map: a `@` and the wall and floor glyphs.
4. `tools/check_headless.sh` passes, and fails when the backend is broken on
   purpose.
5. The existing libtcod build still builds and still plays.

## Phases — one commit each

1. Move `LogError` into `src/ErrorLog.cpp`; libtcod build unchanged and rebuilt.
2. `src/Wposix.cpp` headless: screen array, glyph→ASCII, file I/O, stub input.
   Build via `BACKEND=posix`. Proof: the binary reaches the start menu.
3. Key script and screen dump. Proof: a scripted run creates a character and
   dumps a map.
4. `tools/headless.sh` harness plus `tools/check_headless.sh` regression check,
   proven to fail.
5. ncurses rendering path, so the same binary is playable in a terminal.

Phases 1–4 stand on their own. Phase 5 is the part with no automated oracle,
so it comes last.

---

## What was actually built

All five phases are done. Phases 2 and 3 landed as one commit: splitting them
would have left a commit whose binary could not take a keystroke.

This specification did not anticipate the needs below.

**The seed.** Runs were not reproducible, and the cause was bigger than
expected: the game reached for the clock as a source of randomness in six
places, not one — twice in `src/Main.cpp`, twice while a character is built
(`src/Create.cpp`), once per equipment roll (`src/Annot.cpp`) and once after
spell formulas are chosen (`src/Skills.cpp`). All six now call `NextSeed()`,
which returns `time(NULL)` unless `INCURSION_SEED` is set. Without this the
harness would have been a smoke test and never a regression test.

**The sandbox.** `tools/headless.sh` runs each session in its own directory
under `logs/runs`. This was not in the plan and it should have been: a run
made outside it wrote a scripted character into `save/` beside real ones. Use
`tools/headless.sh --tty` to test terminal drawing, never the binary directly.

**`@include`.** Every script begins by making a character, and that sequence is
long. Without an include, changing it meant editing every script that exists.

**The script language and the exits both grew after this was written.** Read
the two tables above as the starting point, not as the current list.

- More directives joined `@dump` and `@quit`: `@include FILE`;
  `@choose "name"`, which presses whatever letter the game printed beside
  *name*; `@expect "text"`, which stops the run unless the screen shows
  *text*; `@while "text" KEY` and `@until "text" KEY`; and `@cursorto "name"
  KEY` with its `@cursorto:mark` variant. All are parsed in
  `src/Wposix.cpp:1283-1345`.
- The command line also takes `-timeout SECONDS`, the watchdog for an
  unattended run, and `-dump SAVEFILE`, which prints a save file and exits
  without starting the game.
- The ways out above became these exit codes: 0 clean, 1 `Fatal()`, 2 the key
  script could not be read or parsed, 3 out of keys or budget, 4 the watchdog
  fired, 6 an `@expect`, `@choose` or `@cursorto` assertion failed. `@while`
  and `@until` do not stop a run: they give up after a fixed number of passes,
  warn on stderr and step over. `-dump` adds 22 for a save it could not read.
  `tools/headless.sh` prints one line per code and adds one of its own,
  5, for a session that never entered a map.

One thing was added beyond the specification: `Game::CheckConsistency` now
writes `logs/consistency.txt` as well as drawing its report on screen. The
game's own ruleset checker was unusable by anything but a person scrolling a
box, which defeats the point of a backend that has no person.

### Known limits

- The terminal drawing is ASCII only, using the same letters as the screen
  dumps. Box-drawing and shading glyphs come out as `-`, `|` and `#`. The
  upgrade path is marked `ponytail:` in `src/Wposix.cpp`.
- `CheckEscape`, `ClearKeyBuff` and `PrePrompt` do nothing in a scripted run.
  They exist to drain keys already typed, and draining a script would eat the
  next real keystroke. The only thing they could skip is an animation.
- A bright background colour cannot be drawn in a terminal and appears as its
  dark twin. A terminal offers bold for the foreground and nothing for the
  background.
