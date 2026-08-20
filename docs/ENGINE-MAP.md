# Engine map: the frame

One C++ binary. One global game object (`Game`, `inc/Res.h:1054`), one global terminal
(`extern Term *T1`, `inc/Globals.h:279`), and a ruleset that is data, not code:
`lib/*.irh` compiles to a `.Mod` the binary loads at run time. No threads, no callback
loop; control flows down one stack from `main()` and back up. Four subsystems have their
own pages and are not repeated here: `docs/ENGINE-MAP-CREATURE.md` (map grid, creature
model), `docs/ENGINE-SERIALISATION.md` (save and load), `docs/ENGINE-EVENTS.md` (event
dispatch), `docs/ENGINE-SCRIPT.md` (script compiler, module pipeline).

## 1. Modules and owning file

60 files, 146 882 lines in `src/`. Four are zero bytes and dead, not stubs: `CalcVal`,
`OverGen`, `Overland`, `Quest`. Purposes are read from each file's header comment.

| Group | Files |
|---|---|
| Kernel | `Main.cpp:1` loop and start menu, `Event.cpp:1` dispatch, `Base.cpp:1` `String`/`Dice`/`Object`, `Registry.cpp:1` handles and save/load, `Res.cpp:1` resource lookup, `Annot.cpp:1` annotations and script call-out, `Tables.cpp:1` data only |
| Map | `MakeLev.cpp:1` generator, `Display.cpp:1` placing a `Thing`, `Feature.cpp:1` doors/portals/traps/travel, `Vision.cpp:1` sight, `Djikstra.cpp:1` pathing, `Encounter.cpp:1` groups, `MapAudit.cpp:1` sweep that reports and never repairs (`:9`) |
| Creatures | `Creature.cpp:1`, `Monster.cpp:1` AI, `Player.cpp:1` keyboard switch, `Create.cpp:1`, `Values.cpp:1`, `Status.cpp:1`, `Move.cpp:1`, `Fight.cpp:1`, `Skills.cpp:1`, `FeatTab.cpp:1`, `Social.cpp:1`, `Target.cpp:1` |
| Items, magic | `Item.cpp:1`, `Inv.cpp:1`, `Magic.cpp:1`, `Effects.cpp:1`, `Prayer.cpp:1` |
| UI | `Term.cpp:1` and `TextTerm.cpp:1` are the portable `TextTerm` class; `Managers.cpp:1` screens, `Sheet.cpp:1`, `Message.cpp:1`, `Help.cpp:1`, `Debug.cpp:1` |
| Script tools | `yygram.cpp:1` generated parser (36 962 lines), `Tokens.cpp:1` generated lexer, `RComp.cpp:2` driver, `VMachine.cpp:1` interpreter, `Art.cpp:1` ACCENT runtime, `cpp1.c`–`cpp6.c` DECUS preprocessor. `RComp.cpp` and `Art.cpp` sit wholly inside `#ifdef DEBUG`, so a release build cannot compile a module (`src/TextTerm.cpp:64`) |

## 2. Keystroke to redrawn screen

The spine. Every hop is a direct call; nothing is queued or deferred.

1. `main()` `src/Wposix.cpp:463` builds `theGame` and the backend, assigns `T1`, calls `T1->Initialize()` then `theGame->StartMenu()` (`:526-553`).
2. `Game::StartMenu()` `src/Main.cpp:2114`; menu choice 0 runs `LoadModules()` (`src/Registry.cpp:1049`), `NewGame()` (`src/Main.cpp:90`), `Play()` (`:2185-2197`).
3. `Game::Play()` `src/Main.cpp:174`; the `do {} while(1)` at `:205` is the game loop. It walks every `Thing` on the player's map (`:239`), decrements `Timeout`, calls `ChooseAction()` on whatever is ready (`:301`).
4. `Player::ChooseAction()` `src/Player.cpp:129` redraws status, then blocks on `MyTerm->GetCharCmd()` (`:265`).
5. `posixTerm::GetCharCmd()` `src/Wposix.cpp:1229` flushes the screen *first* (`Update()`, `:1272`), reads one raw key (`NextKey()`, `:1277`), maps it to a `KY_CMD_*` by scanning the active keyset (`:1323-1333`). Redraw-before-read is why the screen is always current when the game waits.
6. `switch (ch)` `src/Player.cpp:286`; a direction key lands at `:1155` and, with no attack chosen, throws `ThrowDir(EV_MOVE, ...)` (`:1254`).
7. `ThrowDir` `src/Event.cpp:431` fills an `EventInfo` and calls `RealThrow` (`:317`), which fires PRE, event, POST (`:339-349`).
8. `ThrowEvent` `src/Event.cpp:55` offers the event to region, terrain, dungeon, field and effect resources in that order (`:73-160`); `ThrowTo` (`:266`) then walks the C++ hierarchy from concrete type up to base via the `HIER` macro (`:274-310`).
9. `Creature::Walk()` `src/Move.cpp:24` is the handler `EV_MOVE` reaches (`:147`); it ends at `Move(tx, ty, ...)` (`:945`).
10. `Thing::Move()` `src/Display.cpp:828` relinks square contents, calls `M->Update()` on both changed squares (`:918-920`), and sets the player's `UpdateMap` (`:935`).
11. `Map::Update(x,y)` `src/Term.cpp:701` picks one square's glyph and pushes it to `PutChar`.
12. Next pass, `TextTerm::AdjustMap()` `src/Term.cpp:977` (from `RefreshMap()` `inc/Term.h:654`, and from `src/Main.cpp:220`) scrolls the viewport and calls `ShowMap()` when the offset moved or `UpdateMap` is set (`:1048`).
13. `TextTerm::ShowMap()` `src/Term.cpp:870` calls `p->CalcVision()` (`:906`, defined `src/Vision.cpp:256`), clears `UpdateMap` (`:907`), loops the window calling `PutChar`/`PutGlyph` (`:921-929`, `:1206`).
14. `posixTerm::Update()` `src/Wposix.cpp:584` blits the 80x48 buffer to the terminal; with no terminal it only sets a flag (`:587,608`). Then `Turn++` `src/Main.cpp:393`.

**Invariant.** `Player::UpdateMap` is a one-bit dirty flag. Only `ShowMap` clears it (`src/Term.cpp:907`); every world change sets it (`src/Display.cpp:935,747`). A map that will not redraw is nearly always a lost set of that flag, not a broken draw call.

## 3. Boundaries, and what crosses them

- **Object ↔ handle.** Nothing stores a `Thing*` across a turn; it stores an `hObj` and resolves it through `oThing(h)`, `oMap(h)` and friends (`inc/Base.h:225-237`) over `class Registry` (`inc/Base.h:555`) and the globals `MainRegistry`/`ResourceRegistry` (`inc/Globals.h:110-111`). `theRegistry` switches to `ResourceRegistry` while modules load, and back after (`src/Registry.cpp:1059,1117`).
- **Game ↔ ruleset.** Resources are reached only by `rID` through `RES()`, `TMON()`, `TEFF()` (`inc/Res.h:10-13`). Every override point is an `EventInfo`.
- **C++ ↔ script.** One door: `Resource::Event()` (`src/Annot.cpp:1098`) calls `theGame->VM.Execute()` (`:1120`); `VMachine::Execute` (`src/VMachine.cpp:399`) calls back into C++ through generated `lib/dispatch.h` (`:175`). Constants are shared, not copied: `lib/main.irc:1-2` includes `Defines.h` and `Api.h`.
- **Game ↔ display.** Above `Term` everything speaks glyphs and window ids. `Term` declares 183 pure virtuals; `TextTerm` implements all but 48, and those 48 are the backend contract (`inc/Term.h:720-785`).
- **Compiler ↔ engine.** Same binary, run before the display exists: `TextTerm::RunOnCommandLine` (`src/TextTerm.cpp:39`) handles `-compile` and returns true, so `main` skips `Initialize`/`StartMenu` (`src/Wposix.cpp:550`). It preprocesses `lib/main.irc` to `lib/program.i` and parses that (`src/RComp.cpp:118,128`).

## 4. Terminal backends

`Term` (`inc/Term.h:281`) → `TextTerm` (`inc/Term.h:546`) → one concrete backend. Each backend file wraps its whole body in an `#ifdef`, so all three can be handed to the compiler and only one emits code.

| File | Class | `main()` | Guard | Owns |
|---|---|---|---|---|
| `src/Wlibtcod.cpp` | `libtcodTerm` `:210` | `:416` | `LIBTCOD_TERM` `:57` | SDL/libtcod window, fonts, tiles |
| `src/Wposix.cpp` | `posixTerm` `:119` | `:463` | `POSIX_TERM` `:32` | curses or no output; key scripts; screen dumps |
| `src/Wcurses.cpp` | `cursesTerm` `:176` | `:396` | `CURSES_TERM` `:57` | pdcurses on Windows |

All three `main()`s do the same five things in order: `new Game`, `new <backend>`, `SetIncursionDirectory`, `T1 = AT1`, then `RunOnCommandLine` or `Initialize`/`StartMenu`/`ShutDown` (`src/Wposix.cpp:526-553`, `src/Wlibtcod.cpp:488-498`, `src/Wcurses.cpp:460-470`). Each defines its own `Term *T1` (`src/Wposix.cpp:284`, `src/Wlibtcod.cpp:404`, `src/Wcurses.cpp:384`), so exactly one backend can link.

There is no headless class. `posixTerm` is headless at run time: `useCurses` (`src/Wposix.cpp:128`) is set by `UseTerminal()` (`:218`) from `-headless` and `isatty` (`:534`), and every draw path tests it.

`build_macos.sh` compiles one backend and skips the rest by filename: `BACKEND` defaults to libtcod (`:31`), the posix branch sets `-DPOSIX_TERM` and `SKIP_BACKENDS="Wlibtcod Wcurses"` (`:56-57`), enforced at `:103`. `build.sh:28` instead compiles all three and lets the define empty two. `src/Wcurses.cpp` never builds on macOS.

## How to check this page

```sh
cd /path/to/incursion-roguelike
ls src/*.cpp src/*.c | wc -l                 # 60 files
wc -l src/*.cpp src/*.c | tail -1            # 146882 lines
find src -size 0                             # the 4 empty files
wc -l src/yygram.cpp                         # 36962 lines
grep -c "=0;" inc/Term.h                     # 183 pure virtuals on Term
sed -n '546,787p' inc/Term.h | grep -c "=0;" # 48 left pure by TextTerm
grep -n "int main(int argc" src/W*.cpp       # the 3 backend entry points
grep -n "Term \*T1;" src/W*.cpp              # the 3 T1 definitions
grep -n "SKIP_BACKENDS=" build_macos.sh      # backend selection
```

Section 2 was traced by reading the listed call sites. It was not observed under a debugger, because running a binary in this tree is forbidden.

## Suspected defects

- `src/Player.cpp:274` — `ch != KY_CMD_NAME && KY_CMD_WIZMODE &&` is missing its `ch !=`. `KY_CMD_WIZMODE` is a non-zero enumerator (`inc/Term.h:186`), so the term is always true and has no effect: the wizard key is the one key in the list that is NOT exempt, and pressing it while charging asks "Break off your charge?". The seven neighbouring tests all use `ch !=`. (Corrected 2026-08-15: the page first said the opposite.)
- `src/Event.cpp:129` — inside a branch guarded by `e.EMap && e.EMap->dID`, the error text dereferences `e.EActor->m->dID`. `ThrowEvent` reaches it with `e.EActor == NULL` when `e.EMap` came from `e.EVictim` (`:66`), so the error path crashes instead of reporting.
- `src/Main.cpp:337` — `min(20048, DestroyCount+1)`; the array holds 20480 (`inc/Res.h:1101,1103`). Digits transposed. It clamps low so it cannot overrun, but 432 queued deletions per pass would be dropped silently.
- `src/Event.cpp:352-357` — `if (e.Event >= 500) return r;` makes the two following `Fatal` branches for unhandled PRE and POST events unreachable.
- `inc/Term.h:654` — `RefreshMap()` dereferences `p` unchecked and is called as `T1->RefreshMap()` (`src/Magic.cpp:1330`, `src/Skills.cpp:1937`); `ClearPlayer()` (`inc/Term.h:750`) sets `p` to NULL, so the state is reachable.
- `src/Term.cpp:7` — the header says "80x50 text mode"; the code is 80x48 (`src/Wposix.cpp:73-74`, asserted `src/TextTerm.cpp:84-85`). Stale prose.
