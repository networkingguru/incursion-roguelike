# Engine map: the serialisation layer

Scope: `Registry::SaveGroup`, `Registry::LoadGroup`, `ARCHIVE_CLASS`, the handle fixups. Read-only survey. Claims are read from source unless marked **observed** (a byte dump or a count I ran; commands at the bottom).

## Where it lives

| Thing | File:line |
|---|---|
| `Registry::SaveGroup` / `LoadGroup` | src/Registry.cpp:679 / :849 |
| `Registry::Block` (pointer/handle swap) | src/Registry.cpp:367 |
| `typeSize()` (bytes per object type) | src/Registry.cpp:304 |
| `ARCHIVE_CLASS` / `END_ARCHIVE` | inc/Base.h:664 / :671 |
| `class Registry` (`saveMode`, `loadMode`, `hCurrent`) | inc/Base.h:675 |
| `Game::SaveGame` / `LoadGame` | src/Registry.cpp:1118 / :1227 |
| `Game::SaveModule` / `LoadModules` | src/Registry.cpp:1361 / :1396 |
| `CFile` (compressed payload buffer) | inc/Term.h:804, src/Term.cpp:3440-3586 |
| ABI gate | src/AbiCheck.cpp |
| `SaveFormatID()` / `SaveFormatMatches()` (the file stamp) | src/AbiCheck.cpp:167 / src/Registry.cpp:65 |
| `SIGNATURE`, `SIGNATURE_TWO`, `VERSION_STRING` | inc/Defines.h:15, :16, :23 |

## File format

A save file and a `.Mod` file share one format.

- `fileHeader`, src/Registry.cpp:44-52. 96 bytes on LP64: `Sig`(4), `Version[12]`, `Name[72]`, `numGroups`(2), `Compression`(2), `numDependencies`(2), 2 pad.
- `groupHeader`, src/Registry.cpp:86-95. 28 bytes: `Signature`, `hGroup`, `groupSize`, `compSize`, `objCount`, `dataCount`, `LastHandle`.
- Payload, compressed as one blob: `objCount` x (1 type byte + `typeSize(type)` raw bytes); `SIGNATURE_TWO` (4); `dataCount` x (handle 4, owner 4, size 4, size bytes).

**Observed** in `mod/Incursion.Mod`: `Sig`=0x1234ABCD, `Version`="SF0F7B6EDC", `numGroups`=1, `hGroup`=128, `groupSize`=2947784, `compSize`=1081067, `objCount`=1, `dataCount`=19, `LastHandle`=148. `save/Furious_Fox.sav` carries the same signature and stamp. `save/Jaoin.sav` predates the stamp and carries "0.6.9Y19", which `SaveFormatMatches` still accepts.

`Compression` and `numDependencies` are declared and never assigned or tested; `dependHeader` (src/Registry.cpp:54) is never used. LZ versus RLE is a **caller argument, not a file field**: `SaveGroup` and `LoadGroup` take a `use_lz` parameter, saves pass `false` (:1212, :1292), modules pass `true` (:1323, :1383, :1414), and src/Term.cpp:3511 picks the codec from that argument alone.

## SaveGroup, in order (src/Registry.cpp:679-845)

1. `ClearDataTable()` (:689); reserve a `groupHeader` (:736); open an in-memory `CFile` (:739).
2. `saveMode = true` (:753). Per object: `Serialize(*this,true)` (:764), record the object in `SaveFixupScope` (:767), then write the type byte and `typeSize()` raw bytes (:772-774).
3. `SIGNATURE_TWO` (:785), then the data blocks registered during step 2 (:790-818).
4. `CommitCompressed` (:820); seek back, write the real `groupHeader` (:830).
5. `fixup.Restore()` (:842) clears `saveMode` and replays `Serialize(*this,false)` over the recorded objects only (:205-210), which restores the pointers. On a throw, `SaveFixupScope`'s destructor (:211-212) runs the same `Restore()`, and `RegistryScope` (:137-147, :748) clears `saveMode` and deletes the `CFile`.

`ARCHIVE_CLASS` (inc/Base.h:664) generates `Serialize(Registry&, bool isSave)` that calls the base version first. 20 classes use it. The body's only job is to name the heap blocks the object owns and to convert what a raw byte copy cannot carry.

`Registry::Block` (:367) is the whole mechanism: on save it parks the block's handle in the object's own pointer field (:380); on load it swaps the handle back for the pointer (:382). The `intptr_t` route there plus `static_assert(sizeof(void*) >= sizeof(hData))` (src/AbiCheck.cpp:97) make that reuse safe rather than lucky.

## LoadGroup, in order (src/Registry.cpp:849-1065)

1. `RegistryScope guard(loadMode, &cf)` (:863), then `loadMode = true` (:867). Read `fileHeader`; `SaveFormatMatches(fh.Version)` failure -> `EBADVER` (:873).
2. Walk group headers until `gh.hGroup == hGroup` or `hGroup == 0` (:878); bad `gh.Signature` -> `ECORRUPT`; none found -> `ENOCHUNK`. Then range-check `gh.compSize` and `gh.groupSize` -> `ECORRUPT` (:909-920).
3. `LoadCompressed` the whole payload (:923).
4. Per object: read type byte (:928); `malloc(typeSize(oType))` (:937), a bare malloc with no zeroing; read the bytes (:942); **placement new** to reattach the vptr (:948-990). `T_GAME` is not allocated — the live `theGame` is overwritten (:934-935).
5. `o->Type != oType` -> `ECORRUPT` (:993). A loaded `Creature` gets `ts.SanitizeLoadedTargets()` (:1015-1016). `RegisterObject(o,true)` keeps the handle the object was saved with (:527-530), so handle identity survives the round trip.
6. `SIGNATURE_TWO` check (:1028); data blocks malloc'd and registered (:1044-1052).
7. `Serialize(*this,false)` over every loaded object (:1057-1060). `loadMode` is still true here; the guard clears it on return and on every throw above.

## The fixup contract

Repaired on load, and nothing else is:

| Repair | Where |
|---|---|
| vptr | placement new, src/Registry.cpp:948-990 |
| pointer to an owned heap block | src/Registry.cpp:382, via 30 `r.Block` sites |
| `Thing::m` from `Thing::hm` | inc/Map.h:668-671 |
| `Player::MyTerm = T1` | inc/Creature.h:1120-1121 |
| `Module` resource caches zeroed | inc/Res.h:815-816 |
| module text segment un-inverted | inc/Res.h:856-858 |
| garbage payload in a loaded `Target` | src/Registry.cpp:1015-1016, src/Target.cpp:1452-1491 |

NOT repaired. `LoadGroup` contains no migration or upgrade step, and its only validation is the group-header range check at :909-920:

- **Every `hObj` and `rID` field.** `Thing::Next`, `Thing::hm` (inc/Map.h:680), `Item::Parent` (inc/Item.h:29), `Container::Contents` (inc/Item.h:319), `Game::m[]`, `Game::p[]` (inc/Res.h:1098), `TargetSystem::t[].data` (inc/Target.h:166-177). These are plain numbers and the loader reproduces them byte for byte. **A handle that was wrong when the file was written stays wrong after every future load.** The only check on the result is `if (!p[0] || !m[0])` at src/Registry.cpp:1308.
- **Block sizes.** The size is written (:811) and stored (:1052) but never compared with the size the running binary computes; `Registry::Block`'s load branch (:382) discards its `sz` argument entirely.
- **Whatever a `Serialize` body omits.** `TargetSystem::Serialize` is empty (src/Target.cpp:1442-1444). Correct today, because `Target` holds only `hObj` and small integers (inc/Target.h:161-184), but nothing enforces it.

## Invariants

1. **One ABI per file, by design.** `SaveGroup` writes `sizeof(T)` raw bytes per object, vptr and inter-member padding included. src/AbiCheck.cpp turns a width change into a build failure; read its header comment for the defect that zeroed every player position.
2. **The bytes are not reproducible.** Padding is never written by any assignment. `Object::operator new` memsets (inc/Base.h:628), but the module resource tables come from `new TMonster[...]` (src/RComp.cpp:339) on a class with no zeroing allocator, and `LoadGroup` uses bare `malloc` (:937, :1044). A byte diff of `mod/Incursion.Mod` is therefore not a test of a serialiser change. Read, not observed: I did not run the compiler.
3. **Resource tables carry no code pointers.** `Resource` has no virtual function (the sole candidate is commented out at inc/Res.h:292) and `TMonster` (inc/Res.h:332-416) has no pointer member, so a module data block holds no vptr for the loader to fail to repair. I checked `TMonster`, not all 21 tables.
4. **Saving allocates handles.** `RegisterBlock` takes `LastUsedHandle++` per block (:561) and writes the new value to `gh.LastHandle` (:828), so `LastUsedHandle` grows on every save.

## The module question

"No version stamp and no rejection" is **refuted for the object types in the digest, and still true for the resource tables.**

- A stamp exists: `SaveModule` writes `SaveFormatID()` (:1377) and `LoadGroup` rejects a mismatch (:873) through `SaveFormatMatches` (:65). Confirmed in the observed bytes above.
- The stamp is derived from struct layout, not hand-edited. `SaveLayoutDigest()` (src/AbiCheck.cpp:144-166) hashes the primitive widths, `LocationInfo`, `TAttack` and every whole-object type `typeSize()` can return, and `SaveFormatID()` renders it as "SF" plus eight hex digits. A change to `sizeof(Player)` or `sizeof(Module)` moves it by itself.
- `SaveFormatMatches` also accepts the old `VERSION_STRING` literal (:80), so files written before the digest existed still load. That branch is marked for deletion in the source.
- A change to `sizeof(Module)` is caught twice: by the digest, and by the `SIGNATURE_TWO` separator, which a shifted reader misses and raises `ECORRUPT` (:1028).
- A change to `sizeof(TMonster)` or any other resource table is **not** caught. No resource table is in the digest list. Those blocks sit after the separator, their recorded size is never compared with the running binary's `sizeof`, and the loader indexes old bytes with a new stride. The module loads, no error fires, and the game plays on with garbage.

## How to check this page

```
grep -rn "ARCHIVE_CLASS" inc | grep -v define | wc -l                   # 20
grep -rn "r\.Block(" inc src | wc -l                                    # 30
grep -rn "numDependencies\|dependHeader\|Compression" src/Registry.cpp  # 3, all declarations
grep -rn "VERSION_STRING" src inc | wc -l                               # 14; only src/Registry.cpp:80 compares
grep -rn "SaveFormatID\|SaveFormatMatches" src inc                      # the stamp that does compare
xxd -l 16 mod/Incursion.Mod                                             # Sig + Version
xxd -s 96 -l 28 mod/Incursion.Mod                                       # groupHeader
head -c 16 save/Furious_Fox.sav | xxd                                   # same Sig + Version
head -c 16 save/Jaoin.sav | xxd                                         # pre-digest stamp "0.6.9Y19"
grep -n "virtual" inc/Res.h | head -3                                   # first live virtual is line 859
ls -l mod/Incursion.Mod                                                 # 1081703 bytes
```

## Suspected defects

1. src/Registry.cpp:703-721 — the "delete the old group" loop does `fh.numGroups++` inside `for(i=0;i!=fh.numGroups;i++)`, so `i` never reaches the bound, and it rewrites the file header every iteration. Unreachable today: both call sites pass `newFile=true` (:1212, :1383).
2. src/Registry.cpp:976-977 vs :985-987 — `T_STAFF` (52) has no case in the `LoadGroup` switch, not even beside the other weapons, and sits inside the item range, so it falls to the default and placement-news an `Item`. A staff is built as a `Weapon` (src/Item.cpp:260-261) and sized as one (src/Registry.cpp:336-337), so a loaded staff keeps the right byte count but gets `Item`'s vtable and loses every `Weapon` override, `isWeapon()` included (inc/Item.h:348).
3. src/Registry.cpp:971 — the mirror image. `T_COIN` (29) is built as a plain `Item` (src/Item.cpp:293-299) and sized as one, but `LoadGroup` placement-news a `Coin`, so a coin's vtable changes across a save.
4. src/Registry.cpp:343 vs :985-989 — `typeSize` handles `T_ANNOT` (90) but `LoadGroup` has no case and 90 is outside the item range, so loading one hits `Fatal`. Dead today; annotations live in `Module::Annotations`.
5. **Fixed.** `CFile::FRead` past the end used to zero-fill and report nothing. It now throws `ECORRUPT` (src/Term.cpp:3473-3474). inc-l0t.
6. **Fixed.** `LoadCompressed` now range-checks both sizes (src/Term.cpp:3537-3540), passes the real buffer capacity to the decoder, and compares the produced length with `uncompressed_size` (src/Term.cpp:3581-3582). `LoadGroup` checks the same header fields first (src/Registry.cpp:909-920). inc-l0t.
7. **Fixed.** `CFile::Seek` now tests `realloc`'s return value and throws `EMEMORY` (src/Term.cpp:3497-3498). It still has no caller in src/Registry.cpp, so it is unreached today.
8. inc/Res.h:817-819 vs :856-858 — `SaveModule` inverts `QTextSeg` in place on the save pass, but the restore pass runs with `saveMode` and `loadMode` both false (`SaveFixupScope::Restore`, src/Registry.cpp:207), so neither branch runs and the segment stays inverted in memory. Harmless only because the resource compiler exits immediately (src/RComp.cpp:223-231). The loading half is fine: `LoadGroup` runs its fixup pass with `loadMode` still true (src/Registry.cpp:1057-1060), so :856 does fire.
9. **Fixed.** `reg_log` is now declared unconditionally (inc/Base.h:701) while its uses stay under `#ifdef DEBUG_OBJECTS`. It was declared under `#ifdef DEBUG`, which also changed `sizeof(Registry)` between build flavours and so changed the save stamp. inc-tm4.
10. src/Registry.cpp:646-673 — the data-removal branch of `RemoveObject` is reached only when the object was not found in the object table, and `r` is NULL by then, so its `while(r)` loop never runs. The branch does nothing, walks `DataTable` with an object-table pointer, never reads the `d` it sets, and falls through to the `Error` at :676.
11. **Observed, unexplained.** `mod/Incursion.Mod` is 1081703 bytes. Headers are 96 + 28 = 124 and `compSize` is 1081067, totalling 1081191; 512 trailing bytes are unaccounted for. I could not determine the cause without running the resource compiler.
