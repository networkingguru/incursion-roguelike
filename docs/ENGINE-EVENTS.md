<!-- citations: this-port -->

# Engine map: events and dispatch

How an event is raised, finds handlers, orders them, and how a handler changes the outcome. Aimed at the three crashes under
inc-s6m: inc-upw.5 (P1), inc-upw.16 (P1) and inc-upw.15 (P0). inc-s6m is closed and all three crashes are fixed.

## Where it lives
Event stack and `Throw*`: `src/Event.cpp`. `EventInfo` and the `PEVENT`/`DAMAGE`/`THROW` macros: `inc/Events.h`. C++ -> script
boundary: `src/Annot.cpp:1098`. Bytecode VM: `src/VMachine.cpp:413`. Generated script-callable C++ API: `lib/dispatch.h`.
Preprocessed ruleset: `lib/program.i`. Event numbers and `PRE`/`POST`/`META`/`GODWATCH`/`EVICTIM`: `inc/Defines.h:4433-4439`; 183
`EV_` numbers exist. `EvReturn` is `int8` (`inc/Defines.h:58`): `ERROR -1`, `NOTHING 0`, `DONE 1`, `ABORT 2`, `NOMSG 3`
(`inc/Defines.h:137-141`).

## Raising an event
14 functions push a frame then call `RealThrow`; each starts `EventSP++; CHECK_OVERFLOW;`. They differ only in the fields they
preload, all in `src/Event.cpp`: `Throw` (502), `ThrowField` (517), `ThrowDir` (533), `ThrowXY` (550), `ThrowVal` (568),
`ThrowEff` (584), `ThrowEffDir` (600), `ThrowEffXY` (618), `ThrowLoc` (666), `ThrowDmg` (687), `ThrowTerraDmg` (707),
`ThrowDmgEff` (743), `ReThrow` (468, reuses the caller's `EventInfo`), `RedirectEff` (644, copies outer to inner only).
`Resource::PEvent` (`src/Annot.cpp:1062`) and `PEVENT` (`inc/Events.h:65`) call `Resource::Event` directly and never touch
`EventSP`, adding C++ depth the event stack does not see.

## Order of execution
`RealThrow` (`src/Event.cpp:414`) runs the recipient sweep three times: `PRE(Ev)`=Ev+500, then `Ev`, then `POST(Ev)`=Ev+1000
(`:438-451`). `ABORT`/`DONE` in PRE skips the main pass; `ABORT` also skips POST. The sweep is `ThrowEvent` (`:152`), in this
order: Region under the subject (`:172`), special Terrain (`:192`), illusory Terrain (`:206`); dungeon `EMap->dID` (`:223`);
`EField->eID` else `e.eID` (`:236`, `:249`); every god twice, `GODWATCH(Ev)` for the actor (`:264`) and `GODWATCH(EVICTIM(Ev))`
for the victim (`:285`); the map object (`:305`); then `e.p[3]` down to `e.p[0]` — item2, item, victim, actor (`:322`), each
preceded by its `TRAP_EVENT` stati matching `META(S->Mag)` (`:325-339`). `ThrowTo` (`:363`) then walks the class hierarchy upward
— Player -> Character -> Creature -> Thing, Weapon -> Item -> Thing (`HIER` macro, `:371-407`); any level may stop it.
`Creature::Event` (`src/Creature.cpp:674`) asks the monster resource and each `TEMPLATE` stati, first as `EVICTIM(Ev)` if this
creature is the victim (`:677`), then as the plain event if it is the actor (`:695`).

A handler changes the outcome four ways. `DONE`/`ABORT` stop dispatch at every level above (`src/Event.cpp:179`, `:245`, `:311`,
`:374`); `NOMSG` sets `e.Terse` and continues (`:181`); `NOTHING` continues, and a whole sweep of `NOTHING` reaches the
unhandled-event `Fatal` block in `RealThrow` (`:452-461`), which logs and `exit(1)` (`src/Wposix.cpp:1766-1782`) — but the guard
at `src/Event.cpp:454` returns first whenever the POST pass ran, because `e.Event` then holds `POST(Ev)`, so that `Fatal` is dead on every
normal path; fourth, handlers mutate `EventInfo` in place, and `ReThrow` copies the frame back into the caller's `e` (`src/Event.cpp:479-482`).

## The C++ / script boundary
The boundary is exactly `Resource::Event` (`src/Annot.cpp:1098`); above it is C++, below it is bytecode. It rejects fast on a
16-bucket mask, `EventMask & BIT((e.Event%16)+1)` (`:1110`) — a coarse filter, not a match — then walks the annotation chain, 5
events per record (`:1113-1116`). A positive match runs `theGame->VM.Execute` and returns its value cast to `EvReturn`
(`:1120-1125`); a negative match (`-e.Event`) is a message, not code (`:1127`), printed at `:1141-1167`. Script code reaches C++
through `lib/dispatch.h`: it calls `ThrowEff` (`:2533`), `ThrowEffDir` (`:2537`), `ThrowEffXY` (`:2541`), and assigns `pe->eID =
val` (`:3413`), with no validation.

The build holds 1459 `On Event` occurrences; the `.irh`/`.irc` sources hold 1469 — the figure quoted in the issue. They are not
the same set: `#if 0` at `lib/main.irc:36` and `:268` and a comment block at `:176` delete source handlers, while macro
`ALIENIST_CLAUSE` (`lib/defines.irh:88`) expands one source occurrence into 18 built ones. **1469 counts source text, not handlers
in the build.**

## The event stack
`EventInfo EventStack[EVENT_STACK_SIZE]`, `EventSP` starting at -1 (`src/Event.cpp:130-131`); the size is 128
(`inc/Defines.h:80`). The only bound is `CHECK_OVERFLOW` (`src/Event.cpp:128`), which calls `Fatal("Event Stack Overflow!")` and
exits. There is no depth budget, no recursion counter and no cycle detection in `src/Event.cpp`. Unrelated code reads frames
assuming the enclosing context: `src/Fight.cpp:285-292`, `src/Prayer.cpp:588`, `src/Skills.cpp:1569`, `src/Target.cpp:1726`.

## Re-entrancy
**The system has no general protection against re-entrancy.** Shared by every nested event: `VMachine::Regs[64]`, `SRegs[64]`,
`Stack[8192]`, `Memory`, `szMemory` are `static` (`inc/Res.h:66-74`) with one VM instance, `theGame->VM` (`inc/Res.h:1320`);
`Execute` saves and restores only `Regs[63]` (`src/VMachine.cpp:426`, `:489-497`). `Resource::cAnnot`, `cAnnot2` and `EvMsg[64]`
are `static` on `Resource` (`inc/Res.h:224-225`) — one annotation cursor for the whole game. The code says so: "Nested
FAnnot/NAnnot doesn't normally [work]" (`src/Annot.cpp:619-621`); `FAnnot2` is a one-level kludge, and depth 3 has no cursor.
`Thing::PlaceNear` holds `static Creature* Displace[64]` (`src/Display.cpp:413`) and re-enters itself via `PlaceAt` (`:550`),
which the code notes can overflow the C stack (`:544-546`). Only three places are protected: `StatiCollection::Nested` defers
stati fixups to the outermost iteration (`inc/Map.h:700-705`, field at `:790`), `Creature::Perceives` uses a static counter as a recursion
mutex (`src/Vision.cpp:401-402`), and `Creature::Multiply` refuses to breed past a nesting depth of 4 (`src/Creature.cpp:498`).

## The three crashes
**1. Event Stack Overflow: blast -> Multiply -> place -> blast. Fixed (inc-upw.5).** `Magic::Blast` throws `EV_DAMAGE`
(`src/Effects.cpp:261`) -> a script handler on `POST(EV_DAMAGE)`/`EVICTIM(EV_DAMAGE)` (id moss `lib/mon3.irh:2258`, brown
mold `lib/mon3.irh:2296` and `lib/mon3.irh:2304`) or on `POST(EVICTIM(EV_HIT))` (white worm mass `lib/mon3.irh:3354`)
calls `Multiply` -> `Creature::Multiply` (`src/Creature.cpp:486`) -> `mn->PlaceAt` (`:557`)
throws `EV_PLACE` (`src/Display.cpp:224`, `:248`) and `EV_FIELDON` (`:314`) -> `Creature::FieldOn` re-throws `EV_EFFECT` for
`FI_MODIFIER` (`src/Status.cpp:1685`) -> `Magic::MagicHit` dispatches `EA_BLAST` back into `Blast` (`src/Magic.cpp:1202`).
*Invariant violated:* `Creature::FieldOn` sets `EActor` to the field's creator, so the script calls `Multiply` on the same
generation-0 parent every time, and the generation cap at `src/Creature.cpp:510` can never apply to it. Only `m->BreedCount >= 50`
(`:514`) survives, far above the 128-frame stack. *Fix:* a nesting cap of 4 on `Multiply` (`:498`); `GENERATION` is now stamped at
`:553`, before the child is placed at `:557`.

**2. `Player::MoveDepth` re-enters itself. Fixed (inc-upw.15, closed as a duplicate of inc-x9i).** `MoveDepth`
(`src/Feature.cpp:1143`) calls `PlaceAt` (`:1414`) -> `PlaceAt` throws `EV_PLACE`/`EV_FIELDON` (`src/Display.cpp:224`, `:314`) and
calls `TerrainEffects` (`:358`) -> a portal or terrain handler calls `MoveDepth` again (`src/Feature.cpp:393`;
`src/Move.cpp:1433`, inside `Creature::TerrainEffects` at `src/Move.cpp:1302`). The re-entry path is ordinary event dispatch; no
C++ call from `MoveDepth` to `MoveDepth` exists. *Invariant violated:* a function its caller can re-enter must hold no
call-lifetime state in `static` storage. The follower array is now local, `Thing *GoWith[64]` (`src/Feature.cpp:1163`), bounded at
`:1310`; `static Creature* Displace[64]` (`src/Display.cpp:413`) still violates it. *Fix:* the re-entry was not the cause. The
down path read `RES(0)` whenever `BELOW_DUNGEON` is unset, which is every dungeon in `lib/`; the zero check at
`src/Feature.cpp:1255` stops it.

**3. Wild resource id crashes `Game::Get` inside `Magic::Blast`. Fixed (inc-upw.16).** Handlers get ids from three unvalidated
places: the `eID` a caller put in the frame (`src/Event.cpp:594`), script assignment `pe->eID = val` (`lib/dispatch.h:3413`), and
script `ThrowEff` with an arbitrary int32 (`lib/dispatch.h:2533`). *Invariant violated:* `Game::Get` indexed the module table by
the top byte, `Modules[(xID >> 24)-1]`, `MAX_MODULES` being 126 (`inc/Defines.h:4403`), so an id with a zero top byte indexed
`Modules[-1]`. The guard was `ASSERT(Modules[(xID >> 24)-1])`, and `ASSERT` only calls `Error` and falls through
(`inc/Defines.h:101`) — it did not stop the next line's dereference. Hence SIGBUS with no log: if the out-of-range slot held
non-zero garbage, `ASSERT` passed silently and `->GetResource` ran on a garbage `Module*`. *Fix:* `Game::Get` range-checks the
slot in signed arithmetic and returns NULL with a logged `Error` (`src/Res.cpp:348-353`). The three id sources stay unvalidated.

## How to check this page
```
grep -o "On Event" lib/program.i | wc -l              # 1459 handlers in the build
grep -rho "On Event" lib/*.irh lib/*.irc | wc -l      # 1469 in source (issue figure)
grep -c "^#define EV_" inc/Defines.h                  # 183 event numbers
grep -c CHECK_OVERFLOW src/Event.cpp                  # 15 = 1 define + 14 push sites
grep -n "EVENT_STACK_SIZE\|MAX_MODULES" inc/Defines.h # 128, 126
grep -rn "ALIENIST_CLAUSE" lib/*.irh | grep -v define # 18 macro expansions
```

## Suspected defects
1. Fixed. `src/Creature.cpp:553` now stamps `GENERATION` before `:557` places the child, and `:498` caps `Multiply` nesting at 4.
2. `src/Display.cpp:413` `static Creature* Displace[64]` in a function re-entering itself at `:550`; `Displace[dc++]` (`:510`) has
no bound check and `dc` is `uint8`.
3. `src/Effects.cpp:153` states `e.eID` may be 0 for breath weapons; `:166` then reads `TEFF(e.eID)->Schools` unchecked. Same
shape at `src/Creature.cpp:818`, `src/Magic.cpp:1198`.
4. Fixed. `src/Res.cpp:348-353` range-checks the module slot and returns NULL, so `ASSERT` no longer guards the dereference.
5. `src/VMachine.cpp:520` restores `xID` after `CMEM` because the call may have re-entered `Execute`, but not `mn`, `Memory` or
`szMemory` (`:461-465`), leaving a cross-module outer script on the inner module's data segment.
6. `src/Annot.cpp:1102` declares `res` as `uint32`; `:1125` casts it to `int8`, so a script returning 256 becomes `NOTHING`.
7. `inc/Events.h:77-78` (`PEVENT`) and `src/Annot.cpp:1074-1075` assign `e.EXVal` twice, `e.EYVal` never.
8. `src/Event.cpp:317` indexes `e.p[i]` in the map sweep's `ERROR` branch, where `i` is the god loop counter and is uninitialised
when no god ran.
9. `src/Event.cpp:454` returns before the unhandled-event `Fatal` calls at `:456-461`, because `e.Event` holds `POST(Ev)` there.
The three calls are dead on every normal path, and the two that name `PRE_` and `POST_` have those two names swapped.
