# Reporting gate

Rules for claiming a bug is real and that a fix is the real fix. They apply to
anything public: an issue on `networkingguru/incursion-roguelike`, a comment on
one, and above all anything sent to `rmtew` or `HexDecimal`.

The point is narrow. Upstream has no reason to trust us. A single confident
report that turns out to be wrong, or a patch that moves a bug instead of
removing it, costs more credibility than five good reports earn.

## The four questions

Answer all four in writing before the claim goes public. A missing answer is a
blocking result, not a caveat to add later.

### 1. Reachability chain

State the call path from a user action to the defect, with file and line at
every hop. "This cast is wrong" is not a chain. This is:

```
MakeLev.cpp:1108   builds a Door
  -> ft->PlaceAt(...)
  -> Display.cpp:56   Thing::PlaceAt
  -> Display.cpp:162  m->Things.Add(myHandle)   (only T_MAP is excluded)
  => every dungeon with a door puts a Door* in the list Augury walks
```

You MUST build the chain before filing, not after somebody asks for it.

### 2. Provenance

Ask: would this misbehave on Win32, with the original typedefs, on the upstream
compiler?

- **No** -> the defect is ours. It MUST NOT go upstream. The save-corruption
  bug fails here: `*((long*)&hm)` was harmless on Windows, because `long` is 4
  bytes there. Our typedef narrowing created the overrun.
- **Yes** -> it is upstream's. Say what makes you certain. Best evidence is the
  codebase arguing against itself: `Map::besideWall()` carries a comment about
  the same out-of-bounds trap that `Monster::ChooseAction()` walks into.

### 3. Blast radius

Two checks, both after the fix compiles:

- **Siblings.** Grep every caller of the function you touched. Fixing the one
  call site named in the report, while a sibling has the same defect, is a
  band-aid. Prefer the funnel: guarding `Map::GetAt()` fixed every unguarded
  neighbour scan at once, not only `Monster::ChooseAction()`.
- **What is newly reachable.** A fix changes which branches run. Re-read the
  surrounding code and ask what now executes that did not before.

  This is not hypothetical. Adding the missing `isItem()` guard to `Magic::Augury`
  made a *second* defect more reachable: before the guard, any door set `o` to
  non-NULL, so the `o == NULL` branch rarely ran; after it, an item-free map
  reaches a backwards `goto` and hangs. Shipping only the cast fix -- the one the
  compiler found -- would have converted upstream's crash into a hang.

### 4. Confidence tier

Every report MUST carry one of these, stated in the report, in these words:

| Tier | Meaning |
|---|---|
| **Observed** | An oracle changed state. A log went quiet, a counter dropped, a crash stopped. Numbers before and after. |
| **Traced** | Reachability proved by reading code. Never executed. |
| **Reasoned** | Neither. A hypothesis, however well argued. |

**Only Observed goes to `rmtew` or `HexDecimal`.** Traced and Reasoned stay on
our fork, where being wrong costs nothing.

The tier is about evidence, not about how sure you feel. `Magic::Augury` holds
three defects that are certainly real, and it is still Traced, because that code
has never been seen to run.

## Titles

The title MUST NOT assert more than the body proves. This is the easiest rule
to break, because a title is written first and never revisited. A body that
carefully says "consistent with a present-timing artefact, though a single run
is weak evidence" under a title that says "(present-timing, not drawing)" is a
false claim, whatever the body says. A maintainer reads the title first.

## Separate the three things

Keep them apart, in the report and in your head:

- **An observation** -- something happened, here is the log. Always fileable.
- **A diagnosis** -- this is why. Needs the chain.
- **A patch** -- this fixes it. Needs the blast radius check.

Filing an observation as an observation is honest and useful. Filing an
observation dressed as a diagnosis is how you lose a maintainer's attention.

## Marking a base-code bug that we have fixed

The rules above govern what we SEND. This section governs what we KEEP. They are
different problems: a fix can sit in our tree for years without ever being
reported, and if nothing marks it, the knowledge that it was upstream's bug and
not our port's dies with the session that found it.

**Every fix to a base-code defect MUST carry an `upstream:` comment at the fix
site.** Lowercase tag, same shape as `ponytail:`. Greppable:

```
grep -rn "upstream:" src/ inc/
```

The comment MUST state four things, because a maintainer who wakes up years from
now has none of our context:

1. **That the defect is upstream's, and why.** Answer question 2 of the gate:
   would this misbehave on Win32, with the original typedefs, on the upstream
   compiler? If the answer is no, it is a port artefact and MUST NOT carry this
   marker -- mislabelling ours as theirs is exactly the credibility cost the top
   of this document is about.
2. **The evidence tier**, in the words of the table above: Observed, Traced or
   Reasoned.
3. **The tracking id**, so the full reasoning is recoverable.
4. **Whether it has been sent**, so nobody re-sends it and nobody assumes it
   went out when it did not.

Marking is NOT reporting, and marking creates no obligation to report. A marked
fix goes out only through the gate above, and only when Brian has read the
literal text that will be published.

### Base-code bugs fixed locally

| Fix | Tier | Sent? | Tracked |
|---|---|---|---|
| `Character::HasFeat` never read a race's Monster template, so players silently lost every racial feat that was not also an explicit `Grants:` entry -- 8 feats across 6 races (`src/Create.cpp`) | **Observed** -- same seed and key script; Dragonkin sheet had no Mantis Leap before, has it after | no | inc-2a0 |
| Two empty hands produced one strike per swing forever, while two weapons produced two. `AttackMode()` returns `S_BRAWL` before the `S_DUAL` test is reached, so no feat could ever apply to fists (`src/Creature.cpp`, `src/Fight.cpp`) | **Observed** -- same seed; `Hit:2 / -3` and one Punch before, `Hit:2 / 2` and two Punches after | no | inc-dzz |
| `Map::At()` answered an out-of-bounds query with the (0,0) square instead of failing, so monster AI read off the edge of the map 343 times in 13 seconds. Guarded at `Map::GetAt`, the funnel every accessor uses (`src/Display.cpp`) | **Observed** -- 444 error lines in 13s, then 0 across 877 turns | **yes**, rmtew#40 + #41, open | inc-f13 |
| `TargetSystem::giveOrder` built its `Target` uninitialised, so an escort read stack garbage as the handle of the creature to follow. Two of the eight sites also left `damageDoneToMe` uninitialised, turning escorts hostile to their own leaders (`src/Target.cpp`) | **Observed** -- 250 seeds against a build differing in nothing else; asserts 89,545 -> 0, error lines 139,948 -> 48,245 | **yes**, rmtew#42, **MERGED** | inc-zmk |
| `TargetSort` ordered targets tied on priority and type by subtracting the two objects' addresses, so the same seed played a different game on every launch. The only comparator in `src/` doing pointer arithmetic (`src/Target.cpp`) | **Observed** -- randomisation off: 30 of 30 runs identical; on: 4 of 15 diverged; p = 0.9% | **yes**, rmtew#44, open | inc-qik |
| The `Falling` global was a raw `Creature*` carried across a level change. A faller that died on the way left it dangling, and the next creature the allocator placed on that address paid 3d6 per level it never fell (`src/Move.cpp`) | **Observed** -- seed 3, two layouts, same 204,218 draws: one rolled 6d6, the other did not. 40 of 40 seeds pass after; seed 3 failed a dozen attempts before | no | inc-yml |
| `tmpstr` wrote one pointer past the end of the 64000-entry `StrBufDelQueue` before testing the bound, and the `ASSERT` meant to stop it only logs and returns (`src/Base.cpp`) | **Observed** -- A/B on a probe build with `STRING_QUEUE_SIZE=400`, same seed, reproducing then not reproducing the live crash's twelve assert lines | no | inc-upw.18 |
| `CurrentRoutine` was a 64-byte global filled by `strcpy` and two `strcat`s with no length check, on the hottest path in the engine (`src/VMachine.cpp`) | **Traced** for the overrun -- read out of the code, never seen to fire. The *speed* half of the same commit is NOT listed: that one is ours, because the breadcrumb is inside `#ifdef DEBUG` and reached players only because our build must pass `-DDEBUG` (inc-9df.3) | no | inc-upw.20 |
| `Magic::Augury` held three defects in six lines: a handle cast to a pointer, a missing `isItem()` guard, and a `goto` to a label above the scan that made an item-free map loop forever (`src/Effects.cpp`) | **Traced** -- never executed. Augury has therefore never worked, which is also why there is no regression risk | no | inc-upw.1 |
| `Player::MoveDepth` declared its follower array `static` in a function that re-enters itself (`src/Feature.cpp`) | **Reasoned** -- kept as hardening only. The crash claim made for it in b3b5351 was retracted in 668043c after a controlled A/B showed the same seed segfaulting identically with and without it | **yes**, rmtew#43, sent as hardening, open | inc-upw.15 |
| Loading a save/module group trusted `compSize`/`groupSize` out of the file with no sanity check, and handed the decompressor (`LZ_Uncompress`/`RLE_Uncompress`) only the compressed input's length -- never the output buffer's real capacity -- with nothing afterwards comparing what came out against the size the file claimed. A corrupt or hostile stream could write past the heap block sized for that claim (`src/lz.c`, `src/rle.c`, `src/Term.cpp`, `src/Registry.cpp`) | **Traced** -- read `CFile::LoadCompressed`, `LZ_Uncompress` and `RLE_Uncompress` together; confirmed with a canary-guarded-buffer harness (`tools/check_lz_uncompress.sh`) and 10 hand-corrupted save files exercising bad/negative/huge `compSize`/`groupSize`, truncation, an actual overflow-attempt stream, and a stream that decodes shorter than it claims (`tools/check_load_corrupt.sh`) -- all refused cleanly under UBSan, none touching memory past its declared capacity | no | inc-l0t |
| `CFile::Seek` discarded `realloc()`'s return value when growing its buffer, so on a move `data` kept pointing at memory `realloc` may have already freed -- every access after a growing `Seek()` was a use-after-free (`src/Term.cpp`) | **Traced** -- read the code; the return value was never assigned or checked | no | inc-l0t |
| `CFile::FRead` zero-filled and reported nothing when a read ran past the end of the decompressed in-memory buffer, so a short or corrupt group read back as fabricated zero fields instead of failing (`src/Term.cpp`) | **Traced** -- read every call site (7, all in `Registry::LoadGroup`) to confirm none relies on a legitimate short read before changing the behaviour; confirmed via `tools/check_load_corrupt.sh`'s truncated-file cases | no | inc-l0t |
| `Creature::Multiply` refused to breed a child above `GENERATION` 1, but only stamped that stati on the child AFTER placing it, so anything the placement threw (a field re-triggering the blast that started it) saw an unstamped, generation-0 child and passed the cap. An instrumented probe build showed the recursion never actually reaches a child at all: `Creature::FieldOn`'s `FI_MODIFIER` case sets the re-thrown event's `EActor` to the field's *creator* (the original parent, forever generation 0) rather than the creature standing in the field, and a monster script (e.g. brown mold) calls `EActor->Multiply(...)`, so the same parent recurses on its own field, unbounded, no matter how any child is stamped. Fixed both: `GENERATION` now stamps before placement (real but insufficient on its own), and `Multiply` now refuses to nest past a small depth -- the bead's own second proposed fix, "Multiply must not recurse within one event chain" (`src/Creature.cpp`) | **Traced** -- read `Creature::Multiply`, `Creature::FieldOn`, `Magic::Blast`, `Magic::MagicHit` together; the generation-order hypothesis was disproven and the actual mechanism found with an instrumented probe build logging every `Multiply` entry, child creation, and `Blast` `EActor`/`EVictim` pair across the reproduction seed; reproduced clean before and after (`tools/headless.sh tools/keys/dive.keys 3104`: `Fatal("Event Stack Overflow!")` -> completes with `errors: none`) | no | inc-upw.5 |
| `Game::Get` computed a module slot as the resource id's top byte minus one with no range check, so an id with a zero top byte wrapped (unsigned arithmetic) into a huge slot and an id above `MAX_MODULES` ran off the array; the `ASSERT` guarding the dereference (`inc/Defines.h:73`) only logs and falls through, so an out-of-range slot holding non-zero garbage crashed with nothing in `errors.log`. Range-checked the slot and return `NULL` -- a logged miss -- instead (`src/Res.cpp`) | **Traced** -- read `Game::Get` and `ASSERT`'s fall-through definition; reproduced clean before and after (`tools/headless.sh tools/keys/dive.keys 3387`: SIGBUS with no log -> `Game::Get: resource id 1 names module slot -1, out of range` logged). Fixing this exposed a second, distinct, PRE-EXISTING defect one call deeper -- `Creature::isMType` dereferences `TMON(tmID)` with no NULL check, so the same seed now SIGSEGVs instead of SIGBUS-ing, at `src/Values.cpp:2163`. That defect is real, was masked by `Game::Get`'s crash-or-garbage behaviour before now, and is flagged but deliberately NOT fixed here -- tracked separately as inc-upw.24 | no | inc-upw.16 |
| `Creature::isMType` dereferenced `TMON(tmID)` (`#define TMON(l) ((TMonster*) theGame->Get(l))`, `inc/Res.h:11`) with no NULL check, at `src/Values.cpp:2164` and again at `:2248` (`MA_PERSON` case) further down the same function. Once inc-upw.16 made `Game::Get` return `NULL` for a wild resource id instead of a garbage-but-nonNULL pointer, this became a live SIGSEGV instead of a silent garbage-field read. Fetched `TMON(tmID)` once into a local `TMonster*`, return `false` (an unresolvable template matches no type) if it is `NULL`, and reused the same pointer at both dereference sites (`src/Values.cpp`) | **Traced** -- read the whole function body for every use of `TMON(tmID)`; reproduced clean before and after (`tools/headless.sh tools/keys/dive.keys 3387`: SIGSEGV twice in a row on the pre-fix `incursion-headless` binary, both times logging `Game::Get: resource id 262145 names module slot -1, out of range` immediately before the crash -> clean exit after, across 6 seeds and `tools/check_headless.sh`'s full regression suite) | no | inc-upw.24 |
| `AuditMap`'s check 1 (Contents-chain check) skips a creature that is `MOUNT`ed or `ENGULFED`, with a comment saying both are deliberately absent from `Contents` by design; check 3 (the orphan sweep, `src/MapAudit.cpp:205-223`) had no such exemption and reported every one of those same by-design-absent creatures as map corruption. Gave check 3 the identical `HasStati(MOUNT) \|\| HasStati(ENGULFED)` exemption check 1 already has (`src/MapAudit.cpp`) | **Traced** -- read check 1 and check 3 side by side; the exemption is present in one sibling check and absent in the other within the same function, with no platform or compiler dependence. Confirmed with a 40-seed sweep under `tools/keys/dive.keys`: audit findings 13,976 -> 2 (the 2 remaining are named creatures orphaned by the separate, already-tracked `inc-6d5` Contents-list-corruption path, not mounts). **This drop is the audit getting honest, not the engine improving** -- `tools/gates/dive.baseline` re-recorded to match | no | inc-rx0 |
| `Player::Create` zeroed `SkillRanks[0..SK_LAST]` inclusive (`i != SK_LAST+1`), one write past the 49-element `SkillRanks[SK_LASTSKILL]`. Every other loop over `SkillRanks` in the codebase stops at `i != SK_LAST` with no `+1` (`src/Debug.cpp:1653`, `src/Create.cpp:2620`/`2652`, `src/Managers.cpp`, `src/Help.cpp:82`); this was the only outlier. Dropped the `+1` (`src/Create.cpp`) | **Traced** -- UBSan chargen (seed 8, `tools/keys/dive.keys`): `index 49 out of bounds for int8[49]` at `Create.cpp:114` before, gone after; compared against all 8 sibling loops over `SkillRanks` for consistency | no | inc-bd2 |
| `Creature::CalcValues` looped `i=0..4` over the five `A_HIT_*`/`A_SPD_*` slots (ARCHERY, BRAWL, MELEE, THROWN, OFFHAND) and fed `i` straight into `Character::GetBAB(mode)`, but `TClass::AttkVal` holds only the 4 real combat modes -- there is no OFFHAND entry, and OFFHAND's hit bonus already borrows MELEE's value everywhere else in the same function (`A_HIT_OFFHAND`/`A_SPD_OFFHAND` above it). Made the `GetBAB` call do the same for `i==4` instead of reading `AttkVal[4]` (`src/Values.cpp`) | **Traced** -- UBSan chargen: `index 4 out of bounds for uint8[4]` at `Values.cpp:2589` and `:2590` (two reads of the same bad index, one function) before, gone after | no | inc-bd2 |
| `Character::FeatPrereq`'s `FP_ATTR` case forwards `fc->arg` straight into `Character::IAttr(int8 a)`, which is sized only for the 7-entry base-ability-score domain (`A_STR..A_LUC`, see `BAttr[7]`, `TRace::AttrAdj[7]`, `FT_IMPROVED_STRENGTH+a`). Two Iron Skin prerequisites in `FeatTab.cpp` pass `A_SAV_FORT` (28) -- an index from the unrelated 41-entry `A_HIT_*`/`A_SAV_*`/... scheme `Creature::Attr`/`GetAttr` is sized for -- 42 bytes past `BAttr`'s end, with whatever those bytes held silently deciding whether the feat's Fortitude-save prerequisite passed. `AdvanceLevel` already calls `CalcValues()` immediately before feat prereqs are checked, commented `// For Attribute-based feat prereqs`, so the fully-computed `Attr[]` table is available; made `IAttr` defer to `GetAttr` for any index outside the ability-score range instead of reading past `BAttr` (`src/Create.cpp`) | **Traced** -- UBSan chargen: `index 28 out of bounds for int16[7]` and `int8[8]` at `Create.cpp:3691` (two reads at one call site) before, gone after; checked all 8 `IAttr` callers and the ~60 other `FP_ATTR` entries in `FeatTab.cpp` -- all pass 0-6, so behaviour for every existing caller is unchanged. **May change observable feat-grant behaviour**: Iron Skin's two `A_SAV_FORT` conjuncts now check the real, computed Fortitude-save bonus instead of reading whatever garbage followed `BAttr` in memory | no | inc-bd2 |
| inc-zmk (`inc-upw.4`'s own fix) only stops a NEW `Target` from carrying garbage; `Registry::SaveGroup`/`LoadGroup` copy whole objects as raw bytes, so a `Target` already written to a save or module before c9201dd came back with its stale `data` union untouched, and `Target::GetThingOrNULL`'s `default:` branch treated ANY `TargetType` with no case of its own -- including `OrderWalkToPoint`, whose `data.Area.x/y` sit in the same union bytes -- as a creature handle, then cast whatever `Exists()` found without checking it was actually a Creature (`GetCreature`'s own `ASSERT` for that only logs and keeps going, per `Defines.h`). Added `TargetSystem::SanitizeLoadedTargets()`, run once for every `Creature` object `Registry::LoadGroup` loads (covers save files and modules alike, since both use this same loop) to zero `data` for every `Target` type that does not legitimately carry a creature handle, and separately tightened `GetThingOrNULL` to enumerate the legitimate types explicitly, verify the resolved object's actual type before returning it, and give `OrderWalkToPoint` its own no-handle case instead of falling into the old catch-all (`src/Registry.cpp`, `src/Target.cpp`, `inc/Target.h`) | **Observed** -- a 20-turn sandboxed walk on a read-only copy of Brian's own `save/Jaoin.sav`, loaded under a binary carrying c9201dd but not this fix, logged 74 `ASSERT failed: '...Get(h)->isCreature()'` lines (`inc/Base.h:607`, from `Target::GetThingOrNULL` via `Monster::Movement`); 0 with this fix in place, same save, same walk, same seed. A save written entirely by the fixed binary (fresh character, save, reload) produced byte-identical `-dump` output whether loaded by a binary with or without this fix, confirming the sanitiser is a no-op on already-clean data | no | inc-upw.13 |
| `Food::Eat` (`CA_BURNING_HUNGER` branch) ran `Eaten += 5` before checking eligibility, and its refusal branch did `return ABORT` instead of `goto StopEating`, so it skipped the give-back that the sibling vomit/full branches in the same function already use. The eat menu (`Player.cpp`) splits one unit off the stack with `TakeOne()` before `EV_EAT` fires; a refused Dragonkin meal (blood-only diet) degraded and destroyed that split-off unit anyway, one ration per refused attempt, with the player told no and charged for it every time. Moved `Eaten += 5` to after the eligibility check and changed the refusal to `goto StopEating`, the same label the vomit/full branches already jump to (`src/Item.cpp`) | **Observed** -- `tools/keys/dragonkin-ration.keys`, seed 1: pre-fix, "9 food rations" decremented by one on every refused eat, down to quantity 1 ("food ration") after 8 refusals; post-fix, the same 8 refusals leave "9 food rations" unchanged throughout. Regression-checked with a non-`CA_BURNING_HUNGER` character (plain Lizardfolk, same seed): eating a food ration still prints "You finish eating the food ration.", raises Hunger State, and decrements the stack (8 -> 7) exactly as before | no | inc-i9q.1 |
| `Character::Sacrifice` walked a god's `SACRIFICE_LIST` two slots at a time and stopped at the first zero in the LEFT slot of a (category, value) pair. `MA_ALL` is `0` (`inc/Defines.h:1513`), so a `MA_ALL` row terminated the list instead of matching every creature, and every row after it was unreachable. Khasrach, the orc god, is seven rows of which the last five are `MA_ALL` (`lib/religion.irh:2828`), so his altar refused every corpse that was not an orc or a goblinoid and his only two reachable rows were both punishments. Terminate on a whole zero ROW instead, which is the contract `Resource::GetList` documents when it pads every list with three zeros *"because certain loops use values three at a time"* (`src/Annot.cpp:351`); `Creature::isMType` likewise opens with `if (!mt) return true;` (`src/Values.cpp:2145`), a line that exists only to make `MA_ALL` a wildcard and was unreachable from here (`src/Prayer.cpp`) | **Observed** -- seed 1, same key script, one line of source between the two builds. Dwarf corpse at a Khasrach altar: *"Khasrach seems uninterested in your offering"* before, *"Khasrach is impressed"* with `sacVal 88` and favour 0 -> 88 after. Control on the same seed, kobold corpse (matches row 1, `MA_GOBLINOID SAC_ANGRY`, which sits before the first `MA_ALL` and was always read): *"Anger: Khasrach +1 (offensive sacrifice)"* on **both** builds, byte-identical. Both runs are `tools/check_sacrifice.sh`, which was confirmed red on the unfixed build and green on the fixed one. Sibling sweep: `SACRIFICE_LIST` is the only list in the game whose left column has a legal zero value -- `FU_*`, `AID_*` and `MSG_*` all start at 1 and `REL_DEFAULT` is -20, so the other four pair/triple-stepping loops over `GetList` results (`MakeLev.cpp:3118`, `Prayer.cpp:235`/`556`/`1824`) cannot hit this. Newly reachable: Khasrach's five `MA_ALL 10` rows and Aiswin's two `MA_ALL 2` rows, all taking the plain weight branch; Aiswin's trailing `MA_CHOICE1`/`MA_CHOICE2` rows stay unmatched because `isMType` returns false for 125/126 | no | inc-upw.27 |

### Fixes deliberately NOT listed, because they are ours and not upstream's

Recording these matters as much as the table above: claiming our port artefact
is upstream's bug is the credibility cost this document opens with.

| Fix | Why it is ours |
|---|---|
| `*((long*)&hm)` destroyed the player's position in every save | Harmless on Win32, where `long` is 4 bytes. Our typedef narrowing created the overrun. The gate's worked example. |
| `int32` etc. were 64-bit off Windows; `src/AbiCheck.cpp` now gates the widths | The typedefs were correct for LLP64. This is the port meeting the base code, not a defect in it. |
| `src/RComp.cpp` is inside `#ifdef DEBUG` while generated `yygram.cpp` calls it unconditionally | A build-configuration collision that only a non-Windows build reaches. |
| `argv[0]` resolved to an absolute path at startup | Visual Studio always supplied an absolute `argv[0]`, so Windows never saw it. Borderline -- a Win32 user launching from `cmd` in the game directory would get a bare filename -- but there is no evidence it misbehaves there, and no-evidence means do not claim it. |
| macOS window dimming, and the input failure traced to the machine | Platform-specific, and the second was not a code defect at all. |
| Saves keyed on the layout they were written with | A port-format problem that the base code cannot have. |
| The `#ifdef DEBUG` VM breadcrumb's *speed* cost | Upstream ships without `DEBUG` and never paid it. Only the unbounded write inside it is theirs. |
| The pathfinding terrain cache, and clearing only the map that exists | A performance improvement, not a defect fix. Nothing was incorrect before it. |

### Base-code fixes that arrived before this port

`esran` fixed three base-code defects in the `networkingguru` fork before this
port began, and they are in the tree unmarked: the god-abandonment bug
(961c54b, 2021), grey dwarves' missing racial weapons (ceceebf, 2021), and
`Race::HasSkill` reading only the first six skills (9cbc308, 2025). They are
upstream defects by the gate's test, but they are not this port's work and
carry no evidence we generated. They are listed here rather than marked in the
source, so the marker convention keeps meaning "this port found and fixed it".

**This table was completed by inc-iqh on 2026-08-16**, which swept the port's
history for base-code defects. It is complete as of that date for fixes made in
this repository. `tools/check_upstream_marks.sh` still cannot find an unmarked
fix on its own -- nothing tells it which diffs were bug fixes -- so the rule in
AGENTS.md and CLAUDE.md remains the only thing that keeps this table current.

## Current status of our issues

### Sent to rmtew

| PR | Tier when sent | Status as of 2026-08-17 |
|---|---|---|
| [#42](https://github.com/rmtew/incursion-roguelike/pull/42) zero-initialise `Target` at its eight construction sites | **Observed** -- 89,545 asserts to 0 over 250 seeds, against a build differing in nothing else | **MERGED** 2026-08-15 |
| [#41](https://github.com/rmtew/incursion-roguelike/pull/41) bounds-check `Map::GetAt()` | **Observed** -- 444 errors in 13s, then 0 across 877 turns | open, no comment or review since 2026-08-14 |
| [#43](https://github.com/rmtew/incursion-roguelike/pull/43) `MoveDepth` re-entrancy | **Reasoned** -- sent as hardening, explicitly NOT as a crash fix, after the crash claim was retracted | open. **rmtew replied on 2026-08-15 with three technical questions and they are not yet answered.** See inc-upw.15 |
| [#44](https://github.com/rmtew/incursion-roguelike/pull/44) compare handles, not addresses, in `TargetSort` | **Observed** -- seed 8 went 1 divergence in 6 runs to 18 identical in 18; randomisation off gave 30 of 30 identical against 4 of 15 diverging with it on | sent 2026-08-16 |

**Read the pattern before sending anything else.** The one that merged is the one
whose evidence was a number that moved on both sides of a controlled run. That is
exactly what this document predicts, and it was the first real-world confirmation
the gate had.

**Then #43 complicated the picture, in a useful direction.** On 2026-08-15 rmtew
answered it -- not with a merge and not with a rejection, but with three questions:
how many times can the function call itself, what is the provable maximum stack
from recursive calls, and why not size the array from the number of followers.

Two lessons, and the second one costs more than the first.

*A weak tier does not mean silence.* #43 went as **Reasoned**, the lowest tier in
this document, and it is the one that got engagement. The tier governs what we may
CLAIM, not whether a patch is worth sending. What earned the reply was almost
certainly that the patch was small, honest about being hardening rather than a
fix, and did not ask him to trust a number.

*An unanswered question costs more than a rejected patch.* His comment sat for two
days before anybody here noticed, and it was found by accident while auditing
documentation. A maintainer who asks and gets nothing has been told what our
attention is worth. Watch the submissions, not just the queue: `gh api
repos/rmtew/incursion-roguelike/pulls/N --jq .comments` is the cheap check, and
nothing in this project was doing it.

**Why #44 was the next one sent, and it is not only the tier.** #41 is Observed
too and has not moved, so meeting the evidence bar is necessary and not
sufficient. The sharper difference is how much work the patch asks of a
maintainer who does not know this fork. #42 changed nothing any caller could
observe except the bug, so it could be verified in isolation. #41 makes
`Map::GetAt()` return NULL where it used to return a square, which cannot be
accepted without auditing every accessor that funnels through it. #44 sits on
the #42 side: the comparator's contract is unchanged and only its tiebreak input
moves, so nothing outside the function needs re-reading. Whether that reading is
right is now a live prediction rather than a claim, and #44 is the test of it.

Note that #41's tier is Observed and it still has not moved. Meeting the bar buys
a fair hearing, not a merge. Nothing is owed by a maintainer who never asked for
our help.

### Not sent

| Issue | Tier | Why not |
|---|---|---|
| `Thing::Remove` corruption | **Observed** -- 57 occurrences logged | no diagnosis, so no patch; fileable as an observation |
| `FI_SIZE` inconsistency | **Observed** once; not reproduced | one sighting is not a report |
| window flicker | **Reasoned** -- cause unknown, one hypothesis already disproved | fails the gate; also macOS-only |
| `Magic::Augury`, 3 defects | **Traced** -- never executed | not until Observed |

Base-code defects fixed here but never submitted are marked in the source and
listed above under *Base-code bugs fixed locally*. Marking is not sending.
