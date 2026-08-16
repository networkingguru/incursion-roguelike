# Engine map: events and dispatch

How an event is raised, finds handlers, orders them, and how a handler changes the outcome. Aimed at the three P1 crashes in
inc-s6m.

## Where it lives
Event stack and `Throw*`: `src/Event.cpp`. `EventInfo` and the `PEVENT`/`DAMAGE`/`THROW` macros: `inc/Events.h`. C++ -> script
boundary: `src/Annot.cpp:1098`. Bytecode VM: `src/VMachine.cpp:399`. Generated script-callable C++ API: `lib/dispatch.h`.
Preprocessed ruleset: `lib/program.i`. Event numbers and `PRE`/`POST`/`META`/`GODWATCH`/`EVICTIM`: `inc/Defines.h:4360-4366`; 183
`EV_` numbers exist. `EvReturn` is `int8` (`inc/Defines.h:38`): `ERROR -1`, `NOTHING 0`, `DONE 1`, `ABORT 2`, `NOMSG 3`
(`inc/Defines.h:92-96`).

## Raising an event
14 functions push a frame then call `RealThrow`; each starts `EventSP++; CHECK_OVERFLOW;`. They differ only in the fields they
preload, all in `src/Event.cpp`: `Throw` (400), `ThrowField` (415), `ThrowDir` (431), `ThrowXY` (448), `ThrowVal` (466),
`ThrowEff` (482), `ThrowEffDir` (498), `ThrowEffXY` (516), `ThrowLoc` (564), `ThrowDmg` (585), `ThrowTerraDmg` (605),
`ThrowDmgEff` (641), `ReThrow` (366, reuses the caller's `EventInfo`), `RedirectEff` (542, copies outer to inner only).
`Resource::PEvent` (`src/Annot.cpp:1062`) and `PEVENT` (`inc/Events.h:65`) call `Resource::Event` directly and never touch
`EventSP`, adding C++ depth the event stack does not see.

## Order of execution
`RealThrow` (`src/Event.cpp:317`) runs the recipient sweep three times: `PRE(Ev)`=Ev+500, then `Ev`, then `POST(Ev)`=Ev+1000
(`:339-349`). `ABORT`/`DONE` in PRE skips the main pass; `ABORT` also skips POST. The sweep is `ThrowEvent` (`:55`), in this
order: Region under the subject (`:75`), special Terrain (`:95`), illusory Terrain (`:109`); dungeon `EMap->dID` (`:126`);
`EField->eID` else `e.eID` (`:139`, `:152`); every god twice, `GODWATCH(Ev)` for the actor (`:167`) and `GODWATCH(EVICTIM(Ev))`
for the victim (`:188`); the map object (`:208`); then `e.p[3]` down to `e.p[0]` — item2, item, victim, actor (`:225`), each
preceded by its `TRAP_EVENT` stati matching `META(S->Mag)` (`:228-242`). `ThrowTo` (`:266`) then walks the class hierarchy upward
— Player -> Character -> Creature -> Thing, Weapon -> Item -> Thing (`HIER` macro, `:274-310`); any level may stop it.
`Creature::Event` (`src/Creature.cpp:576`) asks the monster resource and each `TEMPLATE` stati, first as `EVICTIM(Ev)` if this
creature is the victim (`:579`), then as the plain event if it is the actor (`:597`).

A handler changes the outcome four ways. `DONE`/`ABORT` stop dispatch at every level above (`src/Event.cpp:82`, `:148`, `:214`,
`:279`); `NOMSG` sets `e.Terse` and continues (`:84`); `NOTHING` continues, and a whole non-PRE/non-POST sweep of `NOTHING` makes
`RealThrow` call `Fatal` (`:350-359`), which logs and `exit(1)` (`src/Wposix.cpp:1357-1372`); fourth, handlers mutate `EventInfo`
in place, and `ReThrow` copies the frame back into the caller's `e` (`:377-380`).

## The C++ / script boundary
The boundary is exactly `Resource::Event` (`src/Annot.cpp:1098`); above it is C++, below it is bytecode. It rejects fast on a
16-bucket mask, `EventMask & BIT((e.Event%16)+1)` (`:1110`) — a coarse filter, not a match — then walks the annotation chain, 5
events per record (`:1113-1116`). A positive match runs `theGame->VM.Execute` and returns its value cast to `EvReturn`
(`:1120-1125`); a negative match (`-e.Event`) is a message, not code (`:1127`), printed at `:1141-1167`. Script code reaches C++
through `lib/dispatch.h`: it calls `ThrowEff` (`:2533`), `ThrowEffDir` (`:2537`), `ThrowEffXY` (`:2541`), and assigns `pe->eID =
val` (`:3413`), with no validation.

The build holds 1459 `On Event` occurrences; the `.irh`/`.irc` sources hold 1469 — the figure quoted in the issue. They are not
the same set: `#if 0` at `lib/main.irc:36` and `:268` and a comment block at `:176` delete source handlers, while macro
`ALIENIST_CLAUSE` (`lib/defines.irh:68`) expands one source occurrence into 18 built ones. **1469 counts source text, not handlers
in the build.**

## The event stack
`EventInfo EventStack[EVENT_STACK_SIZE]`, `EventSP` starting at -1 (`src/Event.cpp:33-34`); the size is 128 (`inc/Defines.h:60`).
The only bound is `CHECK_OVERFLOW` (`src/Event.cpp:31`), which calls `Fatal("Event Stack Overflow!")` and exits. There is no depth
budget, no recursion counter and no cycle detection in `src/Event.cpp`. Unrelated code reads frames assuming the enclosing
context: `src/Fight.cpp:156-163`, `src/Prayer.cpp:571`, `src/Skills.cpp:1569`, `src/Target.cpp:1486`.

## Re-entrancy
**The system has no general protection against re-entrancy.** Shared by every nested event: `VMachine::Regs[64]`, `SRegs[64]`,
`Stack[8192]`, `Memory`, `szMemory` are `static` (`inc/Res.h:66-74`) with one VM instance, `theGame->VM` (`inc/Res.h:1114`);
`Execute` saves and restores only `Regs[63]` (`src/VMachine.cpp:412`, `:475-483`). `Resource::cAnnot`, `cAnnot2` and `EvMsg[64]`
are `static` on `Resource` (`inc/Res.h:224-225`) — one annotation cursor for the whole game. The code says so: "Nested
FAnnot/NAnnot doesn't normally [work]" (`src/Annot.cpp:619-621`); `FAnnot2` is a one-level kludge, and depth 3 has no cursor.
`Thing::PlaceNear` holds `static Creature* Displace[64]` (`src/Display.cpp:275`) and re-enters itself via `PlaceAt` (`:412`),
which the code notes can overflow the C stack (`:406-408`). Only two places are protected: `StatiCollection::Nested` defers stati
fixups to the outermost iteration (`inc/Map.h:547`, `:585-593`), and `Creature::Perceives` uses a static counter as a recursion
mutex (`src/Vision.cpp:383-384`).

## The three P1 crashes
**1. Event Stack Overflow: blast -> Multiply -> place -> blast.** `Magic::Blast` throws `EV_DAMAGE` (`src/Effects.cpp:261`) -> a
script handler on `POST(EV_DAMAGE)`/`EVICTIM(EV_DAMAGE)` calls `Multiply` (`lib/program.i:45324`, `:45757`, `:46360`) ->
`Creature::Multiply` (`src/Creature.cpp:405`) -> `mn->PlaceAt` (`:458`) throws `EV_PLACE` (`src/Display.cpp:114`, `:135`) and
`EV_FIELDON` (`:197`) -> `Creature::FieldOn` re-throws `EV_EFFECT` for `FI_MODIFIER` (`src/Status.cpp:1688`) -> `Magic::MagicHit`
dispatches `EA_BLAST` back into `Blast` (`src/Magic.cpp:1174`). *Invariant violated:* `Multiply` stamps `GENERATION` at
`src/Creature.cpp:461`, **after** placing the child at `:458`, so the generation cap at `:419` never sees a child still inside its
own placement and cannot fire. Only `m->BreedCount >= 50` (`:423`) survives, far above the 128-frame stack.

**2. `Player::MoveDepth` re-enters itself.** `MoveDepth` calls `PlaceAt` (`src/Feature.cpp:947`) -> `PlaceAt` throws
`EV_PLACE`/`EV_FIELDON` (`src/Display.cpp:114`, `:197`) and calls `TerrainEffects` (`:220`) -> a portal or terrain handler calls
`MoveDepth` again (`src/Feature.cpp:260`; `src/Move.cpp:1409`, inside `Creature::TerrainEffects` at `src/Move.cpp:1294`). The
re-entry path is ordinary event dispatch; no C++ call from `MoveDepth` to `MoveDepth` exists. *Invariant violated:* a function its
caller can re-enter must hold no call-lifetime state in `static` storage. The follower array is now local, `Thing *GoWith[64]`
(`src/Feature.cpp:863`), bounded at `:919`; `static Creature* Displace[64]` (`src/Display.cpp:275`) still violates it.

**3. Wild resource id crashes `Game::Get` inside `Magic::Blast`.** Handlers get ids from three unvalidated places: the `eID` a
caller put in the frame (`src/Event.cpp:492`), script assignment `pe->eID = val` (`lib/dispatch.h:3413`), and script `ThrowEff`
with an arbitrary int32 (`lib/dispatch.h:2533`). *Invariant violated:* `Game::Get` indexes the module table by the top byte,
`Modules[(xID >> 24)-1]` (`src/Res.cpp:313-314`), `MAX_MODULES` being 126 (`inc/Defines.h:4330`), so an id with a zero top byte
indexes `Modules[-1]`. The guard is `ASSERT(Modules[(xID >> 24)-1])`, and `ASSERT` only calls `Error` and falls through
(`inc/Defines.h:73`) — it does not stop the next line's dereference. Hence SIGBUS with no log: if the out-of-range slot holds
non-zero garbage, `ASSERT` passes silently and `->GetResource` runs on a garbage `Module*`.

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
1. `src/Creature.cpp:458` places the child before `:461` stamps `GENERATION`, so the cap at `:419` cannot see a child inside its
own placement.
2. `src/Display.cpp:275` `static Creature* Displace[64]` in a function re-entering itself at `:412`; `Displace[dc++]` (`:372`) has
no bound check and `dc` is `uint8`.
3. `src/Effects.cpp:153` states `e.eID` may be 0 for breath weapons; `:166` then reads `TEFF(e.eID)->Schools` unchecked. Same
shape at `src/Creature.cpp:720`, `src/Magic.cpp:1168`.
4. `src/Res.cpp:313` `ASSERT` does not stop execution, so it cannot guard `:314`.
5. `src/VMachine.cpp:506` restores `xID` after `CMEM` because the call may have re-entered `Execute`, but not `mn`, `Memory` or
`szMemory` (`:447-451`), leaving a cross-module outer script on the inner module's data segment.
6. `src/Annot.cpp:1102` declares `res` as `uint32`; `:1125` casts it to `int8`, so a script returning 256 becomes `NOTHING`.
7. `inc/Events.h:77-78` (`PEVENT`) and `src/Annot.cpp:1074-1075` assign `e.EXVal` twice, `e.EYVal` never.
8. `src/Event.cpp:220` indexes `e.p[i]` in the map sweep's `ERROR` branch, where `i` is the god loop counter and is uninitialised
when no god ran.
