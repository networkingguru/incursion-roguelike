<!-- citations: this-port -->

# Engine map: Map, Thing, Creature, Grid, fields, stati

Navigational page for bead inc-e2j. Every claim carries file:line; counts carry their command. "Read" marks something I read but did not observe running.

## Ownership

- `Registry` owns every `Object` by handle `hObj` (`inc/Base.h:789`; `Object::myHandle` `inc/Base.h:630`). `theRegistry->Exists(h)` is the liveness test. Handles 1..127 are reserved (`src/Registry.cpp:251-260`).
- `Map: public Object` (`inc/Map.h:177`) owns `LocationInfo *Grid` (`inc/Map.h:188`), sized `sizeX*sizeY`. Serialization takes one of two paths (`inc/Map.h:644`): a v1 save embeds the grid through `V1EmbedBegin`/`GridFieldsV1` (`inc/Map.h:646-648`); the legacy v0 path writes it as one block with `r.Block` (`inc/Map.h:651`).
- `Thing: public Object` (`inc/Map.h:917`) holds `Map* m; hObj Next, hm; int16 x,y` (`inc/Map.h:943-945`). `m` is a raw pointer; `hm` is only its save form (`inc/Map.h:925-927`).
- Hierarchy: `Creature: Thing, Magic` (`inc/Creature.h:160`) -> `Character` (`inc/Creature.h:639`) -> `Player` (`inc/Creature.h:1173`); `Monster: Creature` (`inc/Creature.h:1538`). `Item: Thing, Magic` (`inc/Item.h:13`). `Feature: Thing` (`inc/Feature.h:11`) -> `Door`/`Trap`/`Portal`.
- Type tests are numeric, not virtual (`inc/Base.h:631-635`). `isType(T_THING)` is always true (`inc/Base.h:642`), so `Map::FirstAt` returns any Thing.

## The two lists — the central invariant

A Map records each Thing twice: `Map::Things`, an `NArray<hObj,1000,10>` (`inc/Map.h:231`), flat and unordered; and `LocationInfo::Contents` (`inc/Map.h:56`), the head of a per-square chain threaded through `Thing::Next` (`inc/Map.h:944`).

INVARIANT: a Thing with `m == M` is in both `M->Things` and the Contents chain of `M->At(x,y)`. Enforced nowhere. The pair is inserted together only in `Thing::PlaceAt` (`src/Display.cpp:278` array, `:280-290` chain) and `Thing::Move` (`src/Display.cpp:1759-1787`, chain only), and unlinked together only in `Thing::Remove` (`src/Display.cpp:2044-2076`). Insert is not FIFO: if the chain head is a creature the newcomer is spliced in second (`src/Display.cpp:280-286`, `:1778-1783`).

Three exemptions, all deliberate:
- MOUNT — `Creature::Mount` calls `Remove(false, true)`, then re-writes `x,y,m` by hand and never re-adds (`src/Skills.cpp:4300-4303`). A mount is in NEITHER list. `Thing::Remove` then skips the whole unlink block for it (`src/Display.cpp:2044`).
- ENGULFED — `Creature::DoEngulf` re-adds to `Things` only (`src/Display.cpp:2209-2212`): in list 1, not list 2.
- `Item::Next` is overloaded — the map Contents link when on the ground, the inventory link when carried (`src/Display.cpp:2159-2170`; chest walk `src/Display.cpp:372-376`). `Container::Contents` is unrelated to `LocationInfo::Contents`.

## The read path

`Map::GetAt(x,y,t,first)` (`src/Display.cpp:1437`) is the single funnel for all 22 `F*At/N*At/M*At` accessors, and it keeps `static bool doneflag` and `static Thing* curr` (`src/Display.cpp:1439-1440`).

INVARIANT: only one F/N iteration may be live at a time, process-wide. Nothing enforces it. `MCreatureAt`, `MultiAt`, `PileAt` each issue a fresh `first=true` call (`inc/Map.h:300-302`, `:348-353`), so calling one inside an `F...At`/`N...At` loop silently restarts the outer loop.

## Fields and stati

`Map::Fields` is an `OArray<Field,10,5>` of values, not pointers (`inc/Map.h:235`, next to the author's own "something is scribbling over Fields" note at `:232-234`). `LocationInfo::hasField` (`inc/Map.h:44`) caches "some field covers me"; `Map::FieldAt` short-circuits on it (`inc/Inline.h:405-415`).

INVARIANT: `hasField` is true exactly when some `Fields[i]->inArea(x,y)`. Set in `NewField` (`src/Status.cpp:1443`), recomputed in `RemoveField` (`src/Status.cpp:1367`) and `MoveField` (`src/Status.cpp:1585`) — each only over the affected field's own bounding box. `RemoveField` matches by pointer identity (`src/Status.cpp:1361`) into an array that memmoves on `Remove` and reallocs on `Enlarge` (`src/Base.cpp:583-620`), so a `Field*` held across another field operation is stale (read).

FI_SIZE (`inc/Defines.h:3457`) is the bulk of a creature above size Large, created at `src/Monster.cpp:1606` and `src/Values.cpp:1702`; `GetAt` treats it as a creature standing on every covered square (`src/Display.cpp:1527-1539`).

`Thing::__Stati` is a hand-rolled `StatiCollection`, deliberately not an Array (`inc/Map.h:786-794`): live `S[]`, pending `Added[]`, per-nature index `Idx`, and a `Nested` depth so removal inside an iteration defers compaction to `_FixupStati` (`inc/Map.h:704-709`). `Thing::backRefs` (`inc/Map.h:952`) is the reverse edge; `FixupBackrefs` (`inc/Map.h:1244`) requires every `Status::h` aimed at a Thing to have a matching backref there.

## The five open bugs, as invariant violations

1. **wierdless in Thing::Remove** (`src/Display.cpp:2062`) violates "a Thing in `Things[]` is in the Contents chain of its own square". The walk starts at `At(ox,oy).Contents` (`:2056`) and falls off the end. On failure it returns early (`:2069`) AFTER `Things.Remove(i)` (`:2047`) and BEFORE `m = NULL` (`:2079`) — leaving the Thing in neither list with `m,x,y` intact. That early return is the zombie factory `src/MapAudit.cpp:198-204` describes. The identical walk in `Thing::Move` is `Fatal`, not `Error` (`src/Display.cpp:1767`).
2. **GetOpenXY returns (0,0)** (`src/MakeLev.cpp:3587-3594`) violates "the open-square set belongs to the map being populated". `OpenX/OpenY/OpenC` are `static` members of Map (`inc/Map.h:202-203`), shared by every Map instance and by encounter generation (`src/Encounter.cpp:2547`, `:2569`). The caller is `Thing::PlaceOpen` (`inc/Map.h:1009-1011`), which decodes 0 as (0,0) unchecked. Every script call site does guard with `FindOpenAreas` (`lib/program.i`), so the failure needs `OpenC` clobbered between guard and use.
3. **GetAt reports an FI_SIZE field not in Fields[]** (`src/Display.cpp:1538`). See Suspected defects: that Error cannot fire, and the staleness worth catching is silent.
4. **Encounter placed, no creature** (`src/MakeLev.cpp:3498`, `ASSERT(c = GetEncounterCreature(0))`) violates "`CandidateCreatures[i]` refers to a live, placed creature". `enBuildMon` writes the slot at `src/Encounter.cpp:2531`, then 33 lines later can delete the monster after 50 failed terrain tries (`:2564`, `mn->Remove(true); return ABORT;`) without clearing it. The array is memset only on a non-nested generate (`src/Encounter.cpp:536`), and `GetEncounterCreature` returns the raw pointer with no liveness check (`src/Encounter.cpp:365-371`). `ASSERT` is always live — it calls `Error` (`inc/Defines.h:101`).
5. **orphans** (`src/MapAudit.cpp:224`). The two lists are `Map::Things` and the per-square Contents chains. Check 3 tests only `inThingsArray` (`:222`), and it exempts MOUNT/ENGULFED (`:220`) exactly as check 1 does (`:156`). Mounts are in neither list by design (`src/Skills.cpp:4300-4303`). That exemption landed on 2026-08-17; every orphan line in the log comes from a session before it, names a mountable creature, and reports `F_DELETE=0`.

## How to check this page

```sh
grep -c "GetAt(x,y" inc/Map.h                                   # 30 call sites
sed -n '290,355p' inc/Map.h | grep -cE "At\(int16 x, int16 y\) *$"              # 22 accessors
grep -c "map audit armed" logs/mapaudit.log                     # 16 armed sessions
grep "^    " logs/mapaudit.log | cut -c5-56 | sort | uniq -c    # 9743 orphan lines in two formats, 3 deleted-in-Things
grep -oE "x[0-9]+ " logs/mapaudit.log | tr -d 'x ' | paste -sd+ - | bc          # 13711 violations total
grep -oE "F_DELETE=[01]" logs/mapaudit.log | sort | uniq -c                     # 9742 F_DELETE=0, 0 F_DELETE=1
grep -oE "^    orphan[^x]*x[0-9]+ +[^/]+" logs/mapaudit.log | sed 's/.*x[0-9]* *//' | sort | uniq -c | sort -rn
    # celestial horse 3278, warpony 2645, warhorse 2076, Anjou 936, Star 805, giant dragonfly 2, goblin 1
grep -c "it->PlaceOpen\|tr->PlaceOpen" lib/program.i            # proof PlaceOpen is in the build
grep -n "FindOpenAreas" lib/program.i                           # the declaration and the call sites
grep -n "FindOpenAreas" lib/dispatch.h                          # :314-316, the binding
```

## Suspected defects

- `lib/dispatch.h:316` binds the script's 2nd argument of `FindOpenAreas` to the C++ **`regID`** parameter, because `inc/Api.h:122` declares two parameters (`Rect, uint16 Flags`) and `src/MakeLev.cpp:3505` defines three (`Rect, rID regID, int16 Flags`). Tree Stride sets `ta = FOA_TREES_ONLY` (0x0080, `inc/Defines.h:3558`) at `lib/pspells.irh:2317` and passes it as the 2nd argument of `FindOpenAreas` at `lib/pspells.irh:2324`; it lands in `regID`, so `src/MakeLev.cpp:3531` compares a region rID against 128, `isReg` stays false for every square, `OpenC` becomes 0 and the spell always fails — while the intended tree filter never runs. dispatch.h is compiled in at `src/VMachine.cpp:175`. This is a lib/src disagreement, not a smoothed-over one.
- `src/Display.cpp:1538` `Error("Corrupted data for FI_SIZE field!")` is unreachable: its loop repeats exactly the predicate `FieldAt` has already satisfied (`inc/Inline.h:410-413` vs `src/Display.cpp:1530-1532`). The condition worth catching is the inverse — `hasField` set with no covering field — and that returns NULL silently.
- `src/Encounter.cpp:2569` `j = random(OpenC)` with `OpenC == 0` yields j = 0 (`inc/Inline.h:40`), then reads stale `OpenX[0]/OpenY[0]` left by whatever map last ran `FindOpenAreas`.
- `src/Display.cpp:2174` `Item::Remove` zeroes `Next` before calling `Thing::Remove` at `:2179`, which then writes that zero into the predecessor's `Next` (`:2074`), truncating the square's chain. Reachable only if an Item has both `Parent` and `m` set. Read, not observed.
- `src/Effects.cpp:61-89` walks a Player's `x,y` around the map for the scrying cursor without touching Contents, restoring from `uint8` copies taken at `:55-56`. Any Remove or Move inside that loop would unlink from the wrong square.
- `src/Display.cpp:1703` `Thing::Move` caches `Map *M = m`, then throws field events (`:1721-1746`) that can re-place this Thing on another map; the unlink and insert afterwards use the stale `M`.
- `src/MapAudit.cpp:224` says "in neither list" while checking only `Things[]` (`:222`). A Thing in Contents but not `Things[]` is caught by check 2 instead (`:191`), so the wording is wrong, not the coverage.
- `src/Encounter.cpp:2546-2548` builds a `Terrains[256]` table that is never read.
