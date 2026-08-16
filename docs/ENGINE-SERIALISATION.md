# Engine map: the serialisation layer

Scope: `Registry::SaveGroup`, `Registry::LoadGroup`, `ARCHIVE_CLASS`, the handle fixups. Read-only survey. Claims are read from source unless marked **observed** (a byte dump or a count I ran; commands at the bottom).

## Where it lives

| Thing | File:line |
|---|---|
| `Registry::SaveGroup` / `LoadGroup` | src/Registry.cpp:396 / :556 |
| `Registry::Block` (pointer/handle swap) | src/Registry.cpp:162 |
| `typeSize()` (bytes per object type) | src/Registry.cpp:99 |
| `ARCHIVE_CLASS` / `END_ARCHIVE` | inc/Base.h:544 / :551 |
| `class Registry` (`saveMode`, `loadMode`, `hCurrent`) | inc/Base.h:555 |
| `Game::SaveGame` / `LoadGame` | src/Registry.cpp:771 / :880 |
| `Game::SaveModule` / `LoadModules` | src/Registry.cpp:1014 / :1049 |
| `CFile` (compressed payload buffer) | inc/Term.h:791, src/Term.cpp:3160-3242 |
| ABI gate | src/AbiCheck.cpp |
| `SIGNATURE`, `SIGNATURE_TWO`, `VERSION_STRING` | inc/Defines.h:15, :16, :17 |

## File format

A save file and a `.Mod` file share one format.

- `fileHeader`, src/Registry.cpp:44-52. 96 bytes on LP64: `Sig`(4), `Version[12]`, `Name[72]`, `numGroups`(2), `Compression`(2), `numDependencies`(2), 2 pad.
- `groupHeader`, src/Registry.cpp:59-68. 28 bytes: `Signature`, `hGroup`, `groupSize`, `compSize`, `objCount`, `dataCount`, `LastHandle`.
- Payload, compressed as one blob: `objCount` x (1 type byte + `typeSize(type)` raw bytes); `SIGNATURE_TWO` (4); `dataCount` x (handle 4, owner 4, size 4, size bytes).

**Observed** in `mod/Incursion.Mod`: `Sig`=0x1234ABCD, `Version`="0.6.9Y19", `numGroups`=1, `hGroup`=128, `groupSize`=2945286, `compSize`=1080412, `objCount`=1, `dataCount`=19, `LastHandle`=148. `save/Jaoin.sav` carries the same signature and version string.

`Compression` and `numDependencies` are declared and never assigned or tested; `dependHeader` (src/Registry.cpp:54) is never used. LZ versus RLE is a **caller argument, not a file field**: saves pass `false` (:865, :945), modules pass `true` (:1036, :976, :1067), and src/Term.cpp:3202 picks the codec from that argument alone.

## SaveGroup, in order (src/Registry.cpp:396-552)

1. `ClearDataTable()` (:402); reserve a `groupHeader` (:449); open an in-memory `CFile` (:452).
2. `saveMode = true` (:457). Per object: `Serialize(*this,true)` (:468), then write the type byte and `typeSize()` raw bytes (:472-474).
3. `SIGNATURE_TWO` (:485), then the data blocks registered during step 2 (:490-517).
4. `CommitCompressed` (:519); seek back, write the real `groupHeader` (:528).
5. `saveMode = 0` (:535); a second `Serialize(*this,false)` pass restores the pointers (:536-549).

`ARCHIVE_CLASS` (inc/Base.h:544) generates `Serialize(Registry&, bool isSave)` that calls the base version first. 20 classes use it. The body's only job is to name the heap blocks the object owns and to convert what a raw byte copy cannot carry.

`Registry::Block` (:162) is the whole mechanism: on save it parks the block's handle in the object's own pointer field (:175); on load it swaps the handle back for the pointer (:177). The `intptr_t` route there plus `static_assert(sizeof(void*) >= sizeof(hData))` (src/AbiCheck.cpp:97) make that reuse safe rather than lucky.

## LoadGroup, in order (src/Registry.cpp:556-718)

1. Read `fileHeader`; `strcmp(fh.Version, VERSION_STRING)` mismatch -> `EBADVER` (:575).
2. Walk group headers until `gh.hGroup == hGroup` or `hGroup == 0` (:585); bad `gh.Signature` -> `ECORRUPT`; none found -> `ENOCHUNK`.
3. `LoadCompressed` the whole payload (:596).
4. Per object: read type byte; `malloc(typeSize(oType))` (:610), a bare malloc with no zeroing; read the bytes (:615); **placement new** to reattach the vptr (:621-663). `T_GAME` is not allocated — the live `theGame` is overwritten (:607).
5. `o->Type != oType` -> `ECORRUPT` (:666). `RegisterObject(o,true)` keeps the handle the object was saved with (:244-247), so handle identity survives the round trip.
6. `SIGNATURE_TWO` check (:679); data blocks malloc'd and registered (:695-703).
7. `Serialize(*this,false)` over every loaded object (:708-711).

## The fixup contract

Repaired on load, and nothing else is:

| Repair | Where |
|---|---|
| vptr | placement new, src/Registry.cpp:621-663 |
| pointer to an owned heap block | src/Registry.cpp:177, via 30 `r.Block` sites |
| `Thing::m` from `Thing::hm` | inc/Map.h:653-656 |
| `Player::MyTerm = T1` | inc/Creature.h:1114-1115 |
| `Module` resource caches zeroed | inc/Res.h:815-816 |
| module text segment un-inverted | inc/Res.h:845-847 |

NOT repaired. `LoadGroup` contains no migration, upgrade or validation step:

- **Every `hObj` and `rID` field.** `Thing::Next`, `Thing::hm` (inc/Map.h:663), `Item::Parent` (inc/Item.h:29), `Container::Contents` (inc/Item.h:319), `Game::m[]`, `Game::p[]` (inc/Res.h:1098), `TargetSystem::t[].data` (inc/Target.h:166-177). These are plain numbers and the loader reproduces them byte for byte. **A handle that was wrong when the file was written stays wrong after every future load.** The only check on the result is `if (!p[0] || !m[0])` at src/Registry.cpp:961.
- **Block sizes.** The size is written (:510) and stored (:703) but never compared with the size the running binary computes; `Registry::Block`'s load branch (:177) discards its `sz` argument entirely.
- **Whatever a `Serialize` body omits.** `TargetSystem::Serialize` is empty (src/Target.cpp:1358-1360). Correct today, because `Target` holds only `hObj` and small integers (inc/Target.h:161-185), but nothing enforces it.

## Invariants

1. **One ABI per file, by design.** `SaveGroup` writes `sizeof(T)` raw bytes per object, vptr and inter-member padding included. src/AbiCheck.cpp turns a width change into a build failure; read its header comment for the defect that zeroed every player position.
2. **The bytes are not reproducible.** Padding is never written by any assignment. `Object::operator new` memsets (inc/Base.h:515), but the module resource tables come from `new TMonster[...]` (src/RComp.cpp:339) on a class with no zeroing allocator, and `LoadGroup` uses bare `malloc` (:610, :695). A byte diff of `mod/Incursion.Mod` is therefore not a test of a serialiser change. Read, not observed: I did not run the compiler.
3. **Resource tables carry no code pointers.** `Resource` has no virtual function (the sole candidate is commented out at inc/Res.h:292) and `TMonster` (inc/Res.h:332-419) has no pointer member, so a module data block holds no vptr for the loader to fail to repair. I checked `TMonster`, not all 21 tables.
4. **Saving allocates handles.** `RegisterBlock` takes `LastUsedHandle++` per block (:278) and writes the new value to `gh.LastHandle` (:527), so `LastUsedHandle` grows on every save.

## The module question

"No version stamp and no rejection" is **refuted as written, and true in effect.**

- A stamp exists: `SaveModule` writes `VERSION_STRING` (:1030) and `LoadGroup` rejects a mismatch (:575). Confirmed in the observed bytes above.
- `VERSION_STRING` is a hand-edited literal at inc/Defines.h:17. Nothing derives it from struct layout, so it does not move when a struct does.
- One layout change is caught by accident: a change to `sizeof(Module)` shifts the reader past the `SIGNATURE_TWO` separator and raises `ECORRUPT` (:679). `objCount` is 1 for a module, so this covers exactly the `Module` object.
- A change to `sizeof(TMonster)` or any other resource table is **not** caught. Those blocks sit after the separator, their recorded size is never compared with the running binary's `sizeof`, and the loader indexes old bytes with a new stride. The module loads, no error fires, and the game plays on with garbage.

## How to check this page

```
grep -rn "ARCHIVE_CLASS" inc | grep -v define | wc -l                   # 20
grep -rn "r\.Block(" inc src | wc -l                                    # 30
grep -rn "numDependencies\|dependHeader\|Compression" src/Registry.cpp  # 3, all declarations
grep -rn "VERSION_STRING" src inc                                       # 12; only :410 :575 :907 compare
xxd -l 16 mod/Incursion.Mod                                             # Sig + Version
xxd -s 96 -l 28 mod/Incursion.Mod                                       # groupHeader
head -c 16 save/Jaoin.sav | xxd                                         # same Sig + Version
grep -n "virtual" inc/Res.h | head -3                                   # first live virtual is line 859
ls -l mod/Incursion.Mod                                                 # 1081048 bytes
```

## Suspected defects

1. src/Registry.cpp:416-434 — the "delete the old group" loop does `fh.numGroups++` inside `for(i=0;i!=fh.numGroups;i++)`, so `i` never reaches the bound, and it rewrites the file header every iteration. Unreachable today: both call sites pass `newFile=true` (:865, :1036).
2. src/Registry.cpp:649-654 — `T_STAFF` (52) has no case in the `LoadGroup` switch and sits inside the item range, so it falls to the default and placement-news an `Item`. A staff is built as a `Weapon` (src/Item.cpp:260-261) and sized as one (src/Registry.cpp:131), so a loaded staff keeps the right byte count but gets `Item`'s vtable and loses every `Weapon` override, `isWeapon()` included (inc/Item.h:348).
3. src/Registry.cpp:644 — the mirror image. `T_COIN` (29) is built as a plain `Item` (src/Item.cpp:293-299) and sized as one, but `LoadGroup` placement-news a `Coin`, so a coin's vtable changes across a save.
4. src/Registry.cpp:138 vs :658-662 — `typeSize` handles `T_ANNOT` (90) but `LoadGroup` has no case and 90 is outside the item range, so loading one hits `Fatal`. Dead today; annotations live in `Module::Annotations`.
5. src/Term.cpp:3184-3187 — `CFile::FRead` past the end zero-fills and reports nothing, so a short or truncated group yields zeros rather than an error.
6. src/Term.cpp:3220-3241 — `LoadCompressed` never checks that decompression produced `uncompressed_size` bytes. `groupSize` and `compSize` come from the file and size the heap buffer, so a corrupt header is a heap-write primitive.
7. src/Term.cpp:3197 — `realloc(data, alloc);` discards the return value. `CFile::Seek` has no caller in src/Registry.cpp, so it is unreached today.
8. inc/Res.h:817-819 vs :845-847 — `SaveModule` inverts `QTextSeg` in place on the save pass, but the restore pass runs with `saveMode` and `loadMode` both false (src/Registry.cpp:535, :569), so neither branch runs and the segment stays inverted in memory. Harmless only because the resource compiler exits immediately (src/RComp.cpp:223-231).
9. src/Registry.cpp:75-78 vs inc/Base.h:564-566 — `reg_log` is opened under `#ifdef DEBUG_OBJECTS` but declared under `#ifdef DEBUG`; defining one without the other fails the build.
10. src/Registry.cpp:363-390 — the data-removal branch of `RemoveObject` is unreachable (the function returns at :357 on success) and, if reached, dereferences `r`, which is NULL there.
11. **Observed, unexplained.** `mod/Incursion.Mod` is 1081048 bytes. Headers are 96 + 28 = 124 and `compSize` is 1080412, totalling 1080536; 512 trailing bytes are unaccounted for. I could not determine the cause without running the resource compiler.
