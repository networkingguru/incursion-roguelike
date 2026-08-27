<!-- citations: this-port -->

# Engine map: the IncursionScript compiler and the module pipeline

Where the pipeline lives, what calls what, which half of it ships. The language
is `docs/incursionscript.md`; the module format `docs/modules.md`.

## The pipeline, stage by stage

| # | Stage | Code | Input -> output |
|---|---|---|---|
| 1 | Entry | `src/TextTerm.cpp:58`, `-compile <file>`, default `main.irc` (`:61`) | argv -> `Game::ResourceCompiler` |
| 2 | chdir | `src/RComp.cpp:99` | cwd becomes `LibraryPath()`, i.e. `lib/` |
| 3 | Preprocess | `src/cpp1.c:484`, DECUS cpp in `src/cpp1-6.c` | `lib/main.irc` -> `lib/program.i` |
| 4 | Pass 1, count | `src/RComp.cpp:248` `CountResources()` | lex-only scan; sizes and names 21 resource arrays |
| 5 | Pass 2, parse | `src/RComp.cpp:184` `yyparse()`, `src/yygram.cpp` + `src/Tokens.cpp` | tokens -> filled `Module` object |
| 6 | Emit dispatch | `src/RComp.cpp:570` `GenerateDispatch()` | symbol table -> `lib/dispatch.h`, a C++ **source** file |
| 7 | Serialise | `src/RComp.cpp:223` -> `src/Registry.cpp:1406` | `Module` -> `mod/Incursion.Mod` |
| 8 | Load | `src/Registry.cpp:1453` scans `mod/*.Mod` | file -> live `Module*` in `Modules[slot]` (`src/Registry.cpp:1483`) |
| 9 | Execute | `src/VMachine.cpp`, `#include "dispatch.h"` at `:175` | `VCode` bytecode -> C++ calls |

Generator sources are kept: `lang/Tokens.lex` (flex -> `src/Tokens.cpp`) and
`lang/Grammar.acc` (ACCENT -> `src/yygram.cpp`, whose `#line 1` points back to
it). ACCENT is vendored in `modaccent/`, built by the Windows Debug
configuration (`build.bat:67-74`) and by `build.sh:125-129`. Stage 3 has no
`-I`: the include path is four hardcoded entries, `../inc`, `../lib`, `./inc`,
`./lib` (`src/cpp3.c:66-69`), which with stage 2 is why `#include "Api.h"` at
`lib/main.irc:2` resolves to `inc/Api.h`. `ICOMP` is predefined on every run
(`src/cpp1.c:458`) and is the switch that lets one header serve both compilers
(`inc/Defines.h:45`, `inc/Defines.h:4648`).

## What ships and what does not

`src/RComp.cpp` is a single `#ifdef DEBUG` block, line 1 to line 1506. So is
`src/Art.cpp`, line 1 to 1578 -- the ACCENT runtime that defines `yyparse`
(`:1524`), and which its own header calls GPLv2 code that "cannot be compiled
into any distributed binaries" (`:3`). `src/Tokens.cpp` and `src/yygram.cpp`
carry no such guard, and `src/yygram.cpp` calls `AllocString()` and
`AllocRegister()` unconditionally (`:7857`, `:8548`). Both functions live
inside the guarded block (`src/RComp.cpp:1479`, `src/RComp.cpp:1461`), so dropping `DEBUG`
alone fails the link. Each build answers that by excluding whole files.
**The macOS build takes a `COMPILER` switch** (`build_macos.sh:86`).
`COMPILER=yes`, the default, defines `DEBUG` and compiles every source
(`build_macos.sh:128-131`). `COMPILER=no` defines nothing and skips `src/RComp.cpp`,
`src/Art.cpp`, `src/yygram.cpp` and `src/Tokens.cpp` (`build_macos.sh:133-134`), and
`src/cpp1-6.c` as well (`build_macos.sh:204-206`). Windows splits the same way by
configuration: Debug adds `/DDEBUG` (`build.bat:60`), Release does not (`build.bat:63`)
and filters `cpp*.c`, `yygram.cpp` and `tokens.cpp` out of the source list
(`build.bat:93`). Compiled in every configuration: `src/Registry.cpp`,
`src/VMachine.cpp`, `lib/dispatch.h`. So `src/TextTerm.cpp:65` -- "-compile
only works in debug builds" -- holds for Windows Release and for
`COMPILER=no` on macOS.

## Invariants a port must not break

1. **`lib/dispatch.h` is a build input produced by the build's own output.**
   Stage 6 writes it, stage 9 `#include`s it, and it is committed --
   `.gitignore` lists `lib/program.i` (`.gitignore:24`) and `mod/*.Mod` (`.gitignore:28`), not it.
   `-compile` edits a source the *next* C++ build consumes.
2. **Function IDs are positional.** `MemFuncID` and `MemVarID` are counters
   bumped in declaration order (`lang/Grammar.acc:1262`, `:1270`, `:1291`,
   `:1312`), reset per run (`lang/Grammar.acc:190`). Reordering `inc/Api.h` renumbers every ID,
   as its own warning at `inc/Api.h:6-12` says.
3. **`rID` is the module slot in the top byte, a flat index below.** `Game::Get`
   takes the slot as `(xID >> 24) - 1`, range-checks it, then calls
   `Modules[slot]->GetResource(xID)` (`src/Res.cpp:348-354`); `__GetResource`
   masks with `0x00FFFFFF` and walks the 21 arrays in the fixed order at
   `inc/Res.h:941-961` (`src/Res.cpp:110`).
4. **The module is raw struct bytes.** `SaveGroup` writes `typeSize(Type)` bytes
   straight out of the object (`src/Registry.cpp:762`); `Module::ARCHIVE_CLASS`
   hands each resource array over as one block of `sizeof(TMonster)*szMon` and
   so on (`inc/Res.h:870-890`). Rebuild per platform, per ABI. `src/AbiCheck.cpp`
   pins the widths and five bitfield structs, and says plainly it does not make
   the format portable (`:21-24`).
5. **The only gate on the file is a layout digest**: `LoadGroup` throws
   `EBADVER` when `SaveFormatMatches(fh.Version)` fails (`src/Registry.cpp:870`,
   `src/Registry.cpp:61`). The stamp is `SaveFormatID()`, an FNV digest of every size the save
   format depends on (`src/AbiCheck.cpp:167`, `:144`), so adding a field to a
   serialised class rejects old files by itself. The old stamp `VERSION_STRING`,
   `"0.6.9Y19"` (`inc/Defines.h:23`), is still accepted as a migration
   allowance, and that branch is marked for deletion (`src/Registry.cpp:66`).
   The text segment is also stored bitwise-inverted, negated on save and again
   on load (`inc/Res.h:840`, `inc/Res.h:912`), so `strings` on the file shows nothing.

## Counts

| Thing | Count | Command |
|---|---|---|
| Ruleset headers | 26 | `ls lib/*.irh \| wc -l` |
| `#include` in main.irc | 29 | `grep -c '^#include' lib/main.irc` |
| `system` declarations, the whole script API | 785 | `grep -c '^system' inc/Api.h` |
| `case` labels generated into dispatch.h | 976 | `grep -c "^    case \|^        case " lib/dispatch.h` |
| Comment openers / surviving directives in `lib/program.i` | 0 / 0 | `grep -c '/\*' lib/program.i` ; `grep -c '^#if' lib/program.i` |
| Keywords valid anywhere (`Keywords1`) | 33 | `sed -n '58,72p' lang/Tokens.lex \| grep -o '{ *[A-Za-z_0-9]*, *"' \| wc -l` |
| Keywords valid outside code blocks (`Keywords2`) | 231 | `sed -n '73,300p' lang/Tokens.lex \| awk '/^};/{exit} {print}' \| grep -o '{ *[A-Za-z_0-9]*, *"' \| wc -l` |
| Top-level resource declarations | 1636 | `grep -cE '^(Monster\|Item\|Feature\|Effect\|Disease\|Poison\|Spell\|Artifact\|Quest\|Dungeon\|NPC\|Class\|Race\|Domain\|God\|Region\|Terrain\|Text\|Template\|Flavor\|Behaviour\|Encounter) ' lib/program.i` |

The 1636 is an approximation, not the compiler's own number: `CountResources`
accepts the keyword at brace depth 0 anywhere on a line
(`src/RComp.cpp:257-329`), the command matches column 0 only. By that method:
Monster 538, Item 262, Template 106, Region 92, Encounter 88, Terrain 63,
Text 61; `Effect`+`Disease`+`Poison`+`Spell` all feed one array
(`src/RComp.cpp:272-277`), 210+13+54+0 = 277; `Artifact`, `Quest`, `NPC`,
`Flavor`, `Behaviour` are 0.

## How to check this page

Each count carries its command beside it; run them from the repository root.
Structural claims are read, not counted: `sed -n '1p;1506p' src/RComp.cpp` and
`sed -n '1p;1578p' src/Art.cpp` show the `#ifdef DEBUG` / `#endif` pairs that
bracket whole files; `grep -n DEBUG build_macos.sh build.bat` shows the split.
No claim here needed a binary run.

## Suspected defects

1. **A module is written only if it defines two specific monsters.**
   `src/RComp.cpp:215` guards the save with
   `FIND("mage") && FIND("shocker lizard")`. A user module built per
   `docs/modules.md` fails that test, prints "Forgoing save." (`src/RComp.cpp:226`) and
   produces no `.Mod`, yet `ResourceCompiler` returns success (`src/RComp.cpp:232`).
2. **A missing `lib/dispatch.h` degrades silently.** `src/VMachine.cpp:195-199`
   defines empty `CallMemberFunc`, `GetMemberVar` and `SetMemberVar` when
   `DISPATCH` is undefined -- no warning, scripts just stop having effects.
3. **`GenerateDispatch` checks the `fopen` and nothing after it**
   (`src/RComp.cpp:591-592`, `fclose` at `src/RComp.cpp:955`), so a full disk yields a
   truncated `dispatch.h` the next build consumes as complete. `AddDebugInfo`
   is gated by `if (1)` at `src/RComp.cpp:535`.
