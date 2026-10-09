<!-- citations: this-port -->

# Engine map: events and dispatch

How an event is raised, finds handlers, orders them, and how a handler changes the outcome. Aimed at the three crashes under
inc-s6m: inc-upw.5 (P1), inc-upw.16 (P1) and inc-upw.15 (P0). inc-s6m is closed and all three crashes are fixed.

## Where it lives
Event stack and `Throw*`: `src/Event.cpp`. `EventInfo` and the `PEVENT`/`DAMAGE`/`THROW` macros: `inc/Events.h`. C++ -> script
boundary: `src/Annot.cpp:1109`. Bytecode VM: `src/VMachine.cpp:413`. Generated script-callable C++ API: `lib/dispatch.h`.
Preprocessed ruleset: `lib/program.i`. Event numbers and `PRE`/`POST`/`META`/`GODWATCH`/`EVICTIM`: `inc/Defines.h:4523-4529`; 183
`EV_` numbers exist. `EvReturn` is `int8` (`inc/Defines.h:58`): `ERROR -1`, `NOTHING 0`, `DONE 1`, `ABORT 2`, `NOMSG 3`
(`inc/Defines.h:141-145`).

## Raising an event
14 functions push a frame then call `RealThrow`; each starts `EventSP++; CHECK_OVERFLOW;`. They differ only in the fields they
preload, all in `src/Event.cpp`: `Throw` (506), `ThrowField` (521), `ThrowDir` (537), `ThrowXY` (554), `ThrowVal` (572),
`ThrowEff` (588), `ThrowEffDir` (604), `ThrowEffXY` (622), `ThrowLoc` (696), `ThrowDmg` (717), `ThrowTerraDmg` (737),
`ThrowDmgEff` (773), `ReThrow` (472, reuses the caller's `EventInfo`), `RedirectEff` (666, copies outer to inner only).
`Resource::PEvent` (`src/Annot.cpp:1070`) and `PEVENT` (`inc/Events.h:65`) call `Resource::Event` directly and never touch
`EventSP`, adding C++ depth the event stack does not see.

## Order of execution
`RealThrow` (`src/Event.cpp:418`) runs the recipient sweep three times: `PRE(Ev)`=Ev+500, then `Ev`, then `POST(Ev)`=Ev+1000
(`:442-455`). `ABORT`/`DONE` in PRE skips the main pass; `ABORT` also skips POST. The sweep is `ThrowEvent` (`:152`), in this
order: Region under the subject (`:172`), special Terrain (`:192`), illusory Terrain (`:206`); dungeon `EMap->dID` (`:223`);
`EField->eID` else `e.eID` (`:236`, `:249`); every god twice, `GODWATCH(Ev)` for the actor (`:264`) and `GODWATCH(EVICTIM(Ev))`
for the victim (`:285`); the map object (`:305`); then `e.p[3]` down to `e.p[0]` — item2, item, victim, actor (`:326`), each
preceded by its `TRAP_EVENT` stati matching `META(S->Mag)` (`:329-343`). `ThrowTo` (`:367`) then walks the class hierarchy upward
— Player -> Character -> Creature -> Thing, Weapon -> Item -> Thing (`HIER` macro, `:375-411`); any level may stop it.
`Creature::Event` (`src/Creature.cpp:730`) asks the monster resource and each `TEMPLATE` stati, first as `EVICTIM(Ev)` if this
creature is the victim (`:733`), then as the plain event if it is the actor (`:751`).

A handler changes the outcome four ways. `DONE`/`ABORT` stop dispatch at every level above (`src/Event.cpp:179`, `:245`, `:311`,
`:378`); `NOMSG` sets `e.Terse` and continues (`:181`); `NOTHING` continues, and a whole sweep of `NOTHING` reaches the
unhandled-event `Fatal` block in `RealThrow` (`:456-465`), which logs and `exit(1)` (`src/Wposix.cpp:1810-1826`) — but the guard
at `src/Event.cpp:458` returns first whenever the POST pass ran, because `e.Event` then holds `POST(Ev)`, so that `Fatal` is dead on every
normal path; fourth, handlers mutate `EventInfo` in place, and `ReThrow` copies the frame back into the caller's `e` (`src/Event.cpp:483-486`).

## The C++ / script boundary
The boundary is exactly `Resource::Event` (`src/Annot.cpp:1109`); above it is C++, below it is bytecode. It rejects fast on a
16-bucket mask, `EventMask & BIT((e.Event%16)+1)` (`:1121`) — a coarse filter, not a match — then walks the annotation chain, 5
events per record (`:1124-1127`). A positive match runs `theGame->VM.Execute` and returns its value cast to `EvReturn`
(`:1136-1141`); a negative match (`-e.Event`) is a message, not code (`:1143`), printed at `:1157-1183`. Script code reaches C++
through `lib/dispatch.h`: it calls `ThrowEff` (`:2533`), `ThrowEffDir` (`:2537`), `ThrowEffXY` (`:2541`), and assigns `pe->eID =
val` (`:3413`), with no validation.

The `.irh`/`.irc` sources held 1469 `On Event` occurrences on 2026-08-16, when this page was written — the figure quoted in
the issue. That figure is a record and stays as written; both live counts have moved since (see "How to check this page").
The build's handlers and the source text are not the same set: `#if 0` at `lib/main.irc:36` and `:268` and a comment block at `:176` delete source handlers, while macro
`ALIENIST_CLAUSE` (`lib/defines.irh:88`) expands one source occurrence into 18 built ones. **1469 counts source text, not handlers
in the build.**

## The event stack
`EventInfo EventStack[EVENT_STACK_SIZE]`, `EventSP` starting at -1 (`src/Event.cpp:130-131`); the size is 128
(`inc/Defines.h:80`). The only bound is `CHECK_OVERFLOW` (`src/Event.cpp:128`), which calls `Fatal("Event Stack Overflow!")` and
exits. There is no depth budget, no recursion counter and no cycle detection in `src/Event.cpp`. Unrelated code reads frames
assuming the enclosing context: `src/Fight.cpp:675-682`, `src/Prayer.cpp:589`, `src/Skills.cpp:1739`, `src/Target.cpp:1726`.

## Re-entrancy
**The system has no general protection against re-entrancy.** Shared by every nested event: `VMachine::Regs[64]`, `SRegs[64]`,
`Stack[8192]`, `Memory`, `szMemory` are `static` (`inc/Res.h:66-74`) with one VM instance, `theGame->VM` (`inc/Res.h:1324`);
`Execute` saves and restores only `Regs[63]` (`src/VMachine.cpp:426`, `:489-497`). `Resource::cAnnot`, `cAnnot2` and `EvMsg[64]`
are `static` on `Resource` (`inc/Res.h:228-229`) — one annotation cursor for the whole game. The code says so: "Nested
FAnnot/NAnnot doesn't normally [work]" (`src/Annot.cpp:619-621`); `FAnnot2` is a one-level kludge, and depth 3 has no cursor.
`Thing::PlaceNear` holds `static Creature* Displace[64]` (`src/Display.cpp:448`) and re-enters itself via `PlaceAt` (`:594`),
which the code notes can overflow the C stack (`:588-590`). Only three places are protected: `StatiCollection::Nested` defers
stati fixups to the outermost iteration (`inc/Map.h:730-735`, field at `:820`), `Creature::Perceives` uses a static counter as a recursion
mutex (`src/Vision.cpp:599-600`), and `Creature::Multiply` refuses to breed past a nesting depth of 4 (`src/Creature.cpp:538`).

## The three crashes
**1. Event Stack Overflow: blast -> Multiply -> place -> blast. Fixed (inc-upw.5).** `Magic::Blast` throws `EV_DAMAGE`
(`src/Effects.cpp:273`) -> a script handler on `POST(EV_DAMAGE)`/`EVICTIM(EV_DAMAGE)` (brown mold `lib/mon3.irh:2308`
and `lib/mon3.irh:2316`; id moss `lib/mon3.irh:2270` has one too, but `#if 0` at `:2250` keeps it out of the build)
or on `POST(EVICTIM(EV_HIT))` (white worm mass `lib/mon3.irh:3352`)
calls `Multiply` -> `Creature::Multiply` (`src/Creature.cpp:526`) -> `mn->PlaceAt` (`:598`)
throws `EV_PLACE` (`src/Display.cpp:240`, `:264`) and `EV_FIELDON` (`:330`) -> `Creature::FieldOn` re-throws `EV_EFFECT` for
`FI_MODIFIER` (`src/Status.cpp:1802`) -> `Magic::MagicHit` dispatches `EA_BLAST` back into `Blast` (`src/Magic.cpp:1430`).
*Invariant violated:* `Creature::FieldOn` sets `EActor` to the field's creator, so the script calls `Multiply` on the same
generation-0 parent every time, and the generation cap at `src/Creature.cpp:550` can never apply to it. Only `m->BreedCount >= 50`
(`:554`) survives, far above the 128-frame stack. *Fix:* a nesting cap of 4 on `Multiply` (`:538`); `GENERATION` is now stamped at
`:593`, before the child is placed at `:598`.

**2. `Player::MoveDepth` re-enters itself. Fixed (inc-upw.15, closed as a duplicate of inc-x9i).** `MoveDepth`
(`src/Feature.cpp:1303`) calls `PlaceAt` (`:1577`) -> `PlaceAt` throws `EV_PLACE`/`EV_FIELDON` (`src/Display.cpp:240`, `:330`) and
calls `TerrainEffects` (`:393`) -> a portal or terrain handler calls `MoveDepth` again (`src/Feature.cpp:474`;
`src/Move.cpp:1570`, inside `Creature::TerrainEffects` at `src/Move.cpp:1431`). The re-entry path is ordinary event dispatch; no
C++ call from `MoveDepth` to `MoveDepth` exists. *Invariant violated:* a function its caller can re-enter must hold no
call-lifetime state in `static` storage. The follower array is now local, `Thing *GoWith[64]` (`src/Feature.cpp:1323`), bounded at
`:1470`; `static Creature* Displace[64]` (`src/Display.cpp:448`) still violates it. *Fix:* the re-entry was not the cause. The
down path read `RES(0)` whenever `BELOW_DUNGEON` is unset, which is every dungeon in `lib/`; the zero check at
`src/Feature.cpp:1415` stops it.

**3. Wild resource id crashes `Game::Get` inside `Magic::Blast`. Fixed (inc-upw.16).** Handlers get ids from three unvalidated
places: the `eID` a caller put in the frame (`src/Event.cpp:598`), script assignment `pe->eID = val` (`lib/dispatch.h:3413`), and
script `ThrowEff` with an arbitrary int32 (`lib/dispatch.h:2533`). *Invariant violated:* `Game::Get` indexed the module table by
the top byte, `Modules[(xID >> 24)-1]`, `MAX_MODULES` being 126 (`inc/Defines.h:4493`), so an id with a zero top byte indexed
`Modules[-1]`. The guard was `ASSERT(Modules[(xID >> 24)-1])`, and `ASSERT` only calls `Error` and falls through
(`inc/Defines.h:101`) — it did not stop the next line's dereference. Hence SIGBUS with no log: if the out-of-range slot held
non-zero garbage, `ASSERT` passed silently and `->GetResource` ran on a garbage `Module*`. *Fix:* `Game::Get` range-checks the
slot in signed arithmetic and returns NULL with a logged `Error` (`src/Res.cpp:348-353`). The three id sources stay unvalidated.

## How to check this page
```
grep -o "On Event" lib/program.i | wc -l              # handlers in the build; no fixed value, see below
grep -rho "On Event" lib/*.irh lib/*.irc | wc -l      # source text; printed 1469, the issue figure, on 2026-08-16
grep -c "^#define EV_" inc/Defines.h                  # 183 event numbers
grep -c CHECK_OVERFLOW src/Event.cpp                  # 15 = 1 define + 14 push sites
grep -n "EVENT_STACK_SIZE\|MAX_MODULES" inc/Defines.h # 128, 126
grep -rn "ALIENIST_CLAUSE" lib/*.irh | grep -v define # 18 macro expansions
```
The first command reads `lib/program.i`, a build product that `.gitignore` excludes and every module build rewrites, so its
count belongs to the last build, not to the repository; build the module before you trust it. It should come out somewhat
below the source count, because the `#if 0` and comment blocks above remove more handlers than `ALIENIST_CLAUSE` adds.

## Suspected defects
1. Fixed. `src/Creature.cpp:593` now stamps `GENERATION` before `:598` places the child, and `:538` caps `Multiply` nesting at 4.
2. `src/Display.cpp:448` `static Creature* Displace[64]` in a function re-entering itself at `:594`; `Displace[dc++]` (`:554`) has
no bound check and `dc` is `uint8`.
3. `src/Effects.cpp:159` states `e.eID` may be 0 for breath weapons; `:172` then reads `TEFF(e.eID)->Schools` unchecked. Same
shape at `src/Creature.cpp:874`, `src/Magic.cpp:1426`.
4. Fixed. `src/Res.cpp:348-353` range-checks the module slot and returns NULL, so `ASSERT` no longer guards the dereference.
5. `src/VMachine.cpp:529` restores `xID` after `CMEM` because the call may have re-entered `Execute`, but not `mn`, `Memory` or
`szMemory` (`:461-465`), leaving a cross-module outer script on the inner module's data segment.
6. `src/Annot.cpp:1113` declares `res` as `uint32`; `:1141` casts it to `int8`, so a script returning 256 becomes `NOTHING`.
7. `inc/Events.h:77-78` (`PEVENT`) and `src/Annot.cpp:1082-1083` assign `e.EXVal` twice, `e.EYVal` never.
8. Fixed. The map sweep's `ERROR` branch (`src/Event.cpp:321`) indexed `e.p[i]` with the god loop counter `i`; since inc-kxc6
it names `e.EMap` instead.
9. `src/Event.cpp:458` returns before the unhandled-event `Fatal` calls at `:460-465`, because `e.Event` holds `POST(Ev)` there.
The three calls are dead on every normal path, and the two that name `PRE_` and `POST_` have those two names swapped.
