<!-- citations: this-port -->

# Engine map: the serialisation layer

Scope: both save formats — v1 (`"IS1.x"`, tagged records, every save the game
writes today) and v0 (raw memory image, kept for old saves and every module) —
plus `ARCHIVE_CLASS`, the handle fixups, and the checks. Read-only survey.
Claims are read from source unless marked **observed** (a byte dump or a count
I ran; commands at the bottom). Normative spec: `docs/SAVE-SCHEMA-SPEC.md`.

## Two formats, one dispatch

- **v1** is what `Game::SaveGame` writes (src/Registry.cpp:1199-1212): the
  96-byte `fileHeader` and 28-byte `groupHeader` shapes survive, but the
  payload is a stream of tagged records plus a resource name table, deflated
  with zlib level 6. The stamp is `SaveSchemaID()` — `"IS1."` + the schema
  revision, `"IS1.2"` today (src/SaveV1.cpp:51-59).
- **v0** is the legacy raw-memory format described further down. The v0
  reader stays in the binary for every save written before the switch, and
  modules stay on the raw path entirely: `Game::SaveModule`
  (src/Registry.cpp:1388) still writes a `.Mod` through `SaveGroup` with the
  `"SF"` layout digest stamp (:1404).
- The reader dispatches on the file's own stamp, in `Registry::LoadGroup`
  (src/Registry.cpp:857-862): `Sig` right and `Version` starting `"IS"` goes
  to `LoadGroupV1`; an `"IS"` file that is not `"IS1."` is a future major
  version and throws `EBADVER`; anything else falls through to the v0 raw
  reader. `Game::LoadGame` lists v1 saves beside the v0 files this binary's
  own stamp matches (:1262-1266).
- `incursion -convert <file>` (`RunSaveConvert`, src/SaveV1.cpp:4445)
  rewrites a v0 save as v1, leaving the v0 bytes in a `<name>.v0` sibling.
  The two committed evidence fixtures are refused by a realpath guard;
  tools/check_convert_guard.sh proves both directions.

## Where it lives

| Thing | File:line |
|---|---|
| `fileHeader` / `groupHeader` (both formats) | inc/Base.h:700 / :710 |
| v1 wire kinds `K_*`, pool ids `SP_*`, tag ranges | inc/Base.h:723-752 |
| `FIELD_*` macros (one line, four duties) | inc/Base.h:758-776 |
| `ARCHIVE_CLASS` / `END_ARCHIVE` | inc/Base.h:778 / :785 |
| `class Registry` (`saveMode`, `loadMode`, `hCurrent`) | inc/Base.h:789 |
| v0 `Registry::SaveGroup` / `LoadGroup` (+ v1 dispatch) | src/Registry.cpp:664 / :834 (:857-862) |
| v1 `Registry::SaveGroupV1` / `LoadGroupV1` | src/SaveV1.cpp:2248 / :2402 |
| `SCHEMA_REV`, `SaveSchemaID()`, `SaveV1_Raw()` | src/SaveV1.cpp:41-72 |
| `Registry::Block` (v0 pointer/handle swap) | src/Registry.cpp:352 |
| `typeSize()` (bytes per object type) | src/Registry.cpp:289 |
| `Game::SaveGame` / `LoadGame` | src/Registry.cpp:1111 / :1227 |
| `Game::SaveModule` / `LoadModules` | src/Registry.cpp:1388 / :1423 |
| Deferred v1 name resolution call sites | src/Registry.cpp:1359, src/Dump.cpp:228 |
| `CFile` (v0 compressed payload buffer) | inc/Term.h:804, src/Term.cpp:3460-3610 |
| ABI gate | src/AbiCheck.cpp |
| `SaveFormatID()` / `SaveFormatMatches()` (the v0 stamp) | src/AbiCheck.cpp:167 / src/Registry.cpp:58 |
| `SIGNATURE`, `SIGNATURE_TWO`, `VERSION_STRING` | inc/Defines.h:15, :16, :23 |

## The shared file skeleton

A v0 save, a v1 save and a `.Mod` all start the same way:

- `fileHeader`, inc/Base.h:700-708. 96 bytes on LP64: `Sig`(4),
  `Version[12]`, `Name[72]`, `numGroups`(2), `Compression`(2),
  `numDependencies`(2), 2 pad.
- `groupHeader`, inc/Base.h:710-719. 28 bytes: `Signature`, `hGroup`,
  `groupSize`, `compSize`, `objCount`, `dataCount`, `LastHandle`.

The `Version` stamp tells them apart: `"IS1."` + revision is v1;
`"SF"` + eight hex digits of `SaveLayoutDigest()` is v0; the bare
`"0.6.9Y19"` `VERSION_STRING` is a pre-digest v0 file that
`SaveFormatMatches` (src/Registry.cpp:58-76) still accepts under a
migration allowance that is marked for deletion.

`fh.Compression` was declared and never assigned or tested in the original
code; **v1 gave it a meaning**: 1 = the payload is zlib level 6
(src/SaveV1.cpp:2349-2369), 0 = raw, which DEBUG builds write when
`INCURSION_V1_RAW=1` so the mutation tools can craft byte-exact test files
(src/SaveV1.cpp:61-72). The v1 reader follows the file's field
(src/SaveV1.cpp:2468-2498). The v0 paths still ignore it: v0's LZ-versus-RLE
choice is a **caller argument, not a file field** — `SaveGroup`/`LoadGroup`
take `use_lz`, the v0 save path passes `false` (src/Registry.cpp:1303),
modules pass `true` (:1334, :1410, :1441), and src/Term.cpp:3525-3536 picks
the codec from that argument alone. `numDependencies` and `dependHeader`
(src/Registry.cpp:47) remain unused by everything.

## The v1 format (`"IS1.x"` — what the game writes)

After the two headers, the payload (zlib-deflated unless `Compression` is 0):

```
objCount x record
uint32  SIGNATURE_TWO       separator, as v0
name table:
    uint32  entryCount
    entryCount x entry
```

`groupSize` is the uncompressed payload size, `compSize` the compressed
size, `objCount` the record count, `dataCount` always 0 — v1 has no
data-block section; `FIELD_STR`/`FIELD_BLOB` write contents inline.
Trailing bytes after the name table are `ECORRUPT` (src/SaveV1.cpp:2690).

One record per object (written at src/SaveV1.cpp:2284-2298):

```
uint8   type        the T_* constant
uint32  handle      the object's myHandle
uint32  length      bytes from the end of this field to the end of the record
  repeated field:
    uint16  tag     stable field number, unique within the class chain; 0 ends
    uint8   kind    K_* below
    ...     payload sized by kind
  terminator tag 0 (uint16)
```

The kinds, pool ids and tag-range registry live in inc/Base.h:721-752. Fixed
sizes for `K_U8..K_I32`, `K_RID`, `K_H`; length-prefixed for
`K_STR`/`K_BLOB`/`K_EMBED`; `count`/`elemSize` header for `K_ARRAY`;
`K_EMBED` is a nested field stream with its own tag scope and terminator.

**Extensibility and corruption, one rule each way.** A tag the reader knows,
it stores. A tag it does not know, it skips by kind. A known tag it does not
meet stays at the zeroed default construction gave it. An unknown *kind*
cannot be sized and throws `ECORRUPT`; an unknown record *type* is skipped
whole via `length`. A known tag carrying a kind other than the one the field
list declares is `ECORRUPT` — the file and the binary disagree about a field
both claim to know; it is never coerced.

**Field declarations.** `FIELD_*` macro lines inside the existing
`ARCHIVE_CLASS` bodies (inc/Base.h:754-776) serve the v0 path (scalar macros
are no-ops there; `FIELD_STR`/`FIELD_BLOB`/`FIELD_OBJ` perform exactly the
legacy `Serialize`/`Block` calls they replaced), the v1 write, the v1 read,
and the DEBUG coverage map, from one declaration. Replay order is line
order, not tag order: load-direction fixups sit below the fields they read
(e.g. `Thing`'s `m = oMap(hm)`, inc/Map.h:915). Tag numbers are never
reused and never change; a new field takes the next unused number in its
class's range (inc/Base.h:743-752).

**The name table.** Every `rID` a record carries travels as `K_RID`: a
uint32 index into the file's own name table (0xFFFFFFFF is the null rID).
An entry is `pool`(1) — the `SP_*` id, because `T_TNPC` and `T_TCLASS`
share a Type byte — `moduleSlot`(1), `ordinal`(2, count of earlier
same-pool same-name resources in declaration order), `nameLen`(2), then the
name bytes (src/SaveV1.cpp:2328-2339). Resolution is case-SENSITIVE
`strcmp` — never `stricmp`; case-folded names are not unique in this
module. An unresolvable entry, or an ordinal at or past the count of
same-named resources, **aborts the load naming every failing entry**; it is
never zeroed and never skipped.

**Deferred resolution.** Records are read before the name table, and both
load paths reload modules only after the save group (src/Registry.cpp:1328-1346,
src/Dump.cpp:200-228). So a v1 load stores the table index in the `rID`
slot and queues the slot; one `SaveV1_ResolveNames()` call after each
path's module reload (src/Registry.cpp:1359, src/Dump.cpp:228) resolves
every queued slot or aborts. A v0 load queues nothing.

**The packed grid (Map tag 672, since IS1.1).** The map grid is not dumped
as raw `LocationInfo` (20 bytes each, bitfield order at the compiler's
whim) but as a `K_EMBED` record: dimensions, an elemSize of 8, then four
sibling blobs — the 8-byte packed tile image, and the `Glyph`, `Memory`
and `Contents` words (record shape src/SaveV1.cpp:2087-2101, layout comment
and `static_assert`s inc/Map.h:59-76). The packed tile is port-defined:
Region and Terrain bytes, sixteen flag bits in declaration order, sixteen
Visibility bits, sixteen reserved. A DEBUG probe fills a tile with all-ones
field by field, packs, unpacks and compares, so a flag added to the struct
but not the pack loops fails at first save (src/SaveV1.cpp:2048-2085).

**The memory rows (Game tag 816, since IS1.2).** The per-module resource
memory segment (`MDataSeg`) is not a raw blob but, per slot: the script
data segment with its own length, then name-keyed rows — one per
Mon/Item/Eff/Reg memory entry, keyed by pool + ordinal + inline name
(record shape src/SaveV1.cpp:1092-1111). A module rebuild that adds,
removes or reorders resources no longer shifts every row. A row naming a
resource the module no longer has is **discarded** — a row is annotation,
not a reference — but the flavour `rID` values inside `EffMem` go through
the global name table and keep abort semantics. Placement runs inside
`SaveV1_ResolveNames()`, after the module reload (src/SaveV1.cpp:1323).

**Schema revisions.** `SCHEMA_REV` (src/SaveV1.cpp:41-51) is the decimal
after `"IS1."`. Any change to the meaning of an existing tag or record
shape bumps it:

| Revision | Change |
|---|---|
| `IS1.0` | the initial v1 format: tagged records + name table |
| `IS1.1` | Map tag 672: raw `LocationInfo` blob → packed grid record |
| `IS1.2` | Game tag 816: raw `MDataSeg` blobs → script blob + name-keyed memory rows |

The reader rejects a revision it does not implement with a clean error
naming both revisions, the file's and the binary's, and reads nothing
(src/SaveV1.cpp:2414-2425).

**The coverage check (DEBUG, save direction, non-optional).** Every byte of
every archived object must be covered by exactly one field declaration, an
explicit `FIELD_SKIP`, or a pinned padding range from the per-class pin
table (`SchemaPin`, src/SaveV1.cpp:203-238), which also pins each class's
`sizeof` — upstream adding or moving a member is a loud finding, not a
silently dropped field. A finding on the real save path refuses to write
the file (src/SaveV1.cpp:2306-2323): the player sees "Error writing save
file" rather than a save with a hole in it.

**Measured size.** The v1 format earns its keep. The seed-1 check save
measured 239,535 bytes as v0 and 26,571 bytes as v1 at the `IS1.0` flip —
**−88.91%**. At `IS1.2` the same scenario measures 32,813 bytes (the
name-keyed memory rows buy their robustness with ~6KB) — still −86.3%
against the v0 baseline. tools/check_v1_full_roundtrip.sh prints the
current `v1=` number on every run, and the delta too when it is handed a
v0 baseline. The codec ruling behind the win: RLE compresses runs and a
tagged-record stream has none, so the same payload measured 552,209 raw →
332,517 as RLE (worse than v0) but ~26,4xx as zlib-6
(src/SaveV1.cpp:2349-2355).

**Observed** in a fresh seed-1 save (2026-08-25): `Sig`=0x1234ABCD,
`Version`="IS1.2", `Name` carries the character line, `numGroups`=1,
`Compression`=1; `groupSize`=546036, `compSize`=32700, `objCount`=330,
`dataCount`=0.

## The v0 format (legacy — old saves and every `.Mod`)

Everything below describes the raw path. It is frozen, not dead: the v0
reader must keep reading every pre-v1 save, and the module writer/reader
lives here permanently.

- Payload, compressed as one blob through `CFile`: `objCount` x (1 type
  byte + `typeSize(type)` raw bytes); `SIGNATURE_TWO` (4); `dataCount` x
  (handle 4, owner 4, size 4, size bytes).

**Observed** in `mod/Incursion.Mod` (rebuilt 2026-08-25): `Sig`=0x1234ABCD,
`Version`="SF0F7B6EDC", `numGroups`=1, `hGroup`=128, `groupSize`=2955566,
`compSize`=1084151, `objCount`=1, `dataCount`=19, `LastHandle`=148.
`docs/evidence/inc-upw.13/Furious_Fox.sav` carries the same signature and
stamp; `docs/evidence/inc-upw.13/Jaoin.sav` predates the stamp and carries
"0.6.9Y19", which `SaveFormatMatches` still accepts.

### SaveGroup, in order (src/Registry.cpp:664-831)

1. `ClearDataTable()` (:674); reserve a `groupHeader` (:721); open an
   in-memory `CFile` (:724).
2. `saveMode = true` (:738). Per object: `Serialize(*this,true)` (:749),
   record the object in `SaveFixupScope` (:752), then write the type byte
   and `typeSize()` raw bytes (:757-759).
3. `SIGNATURE_TWO` (:770), then the data blocks registered during step 2
   (:773-802).
4. `CommitCompressed` (:805); seek back, write the real `groupHeader`
   (:814-815).
5. `fixup.Restore()` (:827) clears `saveMode` and replays
   `Serialize(*this,false)` over the recorded objects only (:187-192),
   which restores the pointers. On a throw, `SaveFixupScope`'s destructor
   (:193-194) runs the same `Restore()`, and `RegistryScope` (:733) clears
   `saveMode` and deletes the `CFile`.

`ARCHIVE_CLASS` (inc/Base.h:778) generates `Serialize(Registry&, bool
isSave)` that calls the base version first. 20 classes use it. On the v0
path the body's job is unchanged from upstream: name the heap blocks the
object owns and convert what a raw byte copy cannot carry — the scalar
`FIELD_` lines are no-ops here.

`Registry::Block` (:352) is the whole v0 mechanism: on save it parks the
block's handle in the object's own pointer field (:365); on load it swaps
the handle back for the pointer (:367). The `intptr_t` route there plus
`static_assert(sizeof(void*) >= sizeof(hData))` (src/AbiCheck.cpp:97) make
that reuse safe rather than lucky. v1 never parks anything: `SaveGroupV1`
reads through the same bodies without mutating the object, so it needs no
`SaveFixupScope` (src/SaveV1.cpp:2379-2382).

### LoadGroup, in order (src/Registry.cpp:834-1065)

1. `RegistryScope guard(loadMode, &cf)` (:848), then `loadMode = true`
   (:852). Read `fileHeader`; the v1 dispatch runs here (:857-862);
   `SaveFormatMatches(fh.Version)` failure -> `EBADVER` (:866-867).
2. Walk group headers until `gh.hGroup == hGroup` or `hGroup == 0`
   (:871-881); bad `gh.Signature` -> `ECORRUPT`; none found -> `ENOCHUNK`
   (:883). Then range-check `gh.compSize` and `gh.groupSize` -> `ECORRUPT`
   (:903-913).
3. `LoadCompressed` the whole payload (:916).
4. Per object: read type byte (:921); `malloc(typeSize(oType))` (:930), a
   bare malloc with no zeroing; read the bytes (:935); **placement new** to
   reattach the vptr (:941-983). `T_GAME` is not allocated — the live
   `theGame` is overwritten (:927-928).
5. `o->Type != oType` -> `ECORRUPT` (:986-987). A loaded `Creature` gets
   `ts.SanitizeLoadedTargets()` (:1008-1009). `RegisterObject(o,true)`
   keeps the handle the object was saved with (:1012), so handle identity
   survives the round trip.
6. `SIGNATURE_TWO` check (:1021-1022); data blocks malloc'd and registered
   (:1027-1046).
7. `Serialize(*this,false)` over every loaded object (:1049-1052).
   `loadMode` is still true here; the guard clears it on return and on
   every throw above.

`LoadGroupV1` (src/SaveV1.cpp:2402) mirrors steps 4-7 for records: same
placement-new switch, then a two-pass replay (register every object first,
then run every field list) so cross-object load fixups resolve regardless
of record order.

### The fixup contract

Repaired on load, and nothing else is:

| Repair | Where |
|---|---|
| vptr | placement new, src/Registry.cpp:941-983 |
| pointer to an owned heap block | src/Registry.cpp:367, via the 7 direct `r.Block` sites plus every `FIELD_BLOB`/`FIELD_OBJ` line's v0 branch (inc/Base.h:768-773) |
| `Thing::m` from `Thing::hm` | inc/Map.h:915 |
| `Player::MyTerm = T1` | inc/Creature.h:1355 |
| `Module` resource caches zeroed | inc/Res.h:836-837 (save side), :919-920 (load side) |
| module text segment un-inverted | inc/Res.h:908-912 |
| garbage payload in a loaded `Target` | src/Registry.cpp:1008-1009, src/Target.cpp:1561 |

NOT repaired on the v0 path, whose only validation is the group-header
range check at src/Registry.cpp:903-913:

- **Every `hObj` and `rID` field.** `Thing::Next`, `Thing::hm`
  (inc/Map.h:919), `Item::Parent` (inc/Item.h:44), `Container::Contents`
  (inc/Item.h:343), `Game::m[]`, `Game::p[]` (inc/Res.h:1299),
  `TargetSystem`'s per-target `data` (inc/Target.h:166-177). These are
  plain numbers and the v0 loader reproduces them byte for byte. **A handle
  that was wrong when the file was written stays wrong after every future
  load.** The only check on the result is `if (!p[0] || !m[0])` at
  src/Registry.cpp:1319. (v1 reproduces handles the same way — `K_H` is a
  number — but every `rID` goes through the name table instead of riding
  as an index, and out-of-range file-fed indexes are bounded on load.)
- **Block sizes.** The size is written (:796) and stored (:1046) but never
  compared with the size the running binary computes; `Registry::Block`'s
  load branch (:367) discards its `sz` argument entirely.
- **Whatever a `Serialize` body omits.** The canonical example,
  `TargetSystem::Serialize`, is still empty on the v0 path
  (src/Target.cpp:1447-1449, `upstream:` mark below it) — harmless there
  because v0 dumps the embedding `Creature` raw. The v1 field list beside
  it is the real one, so the omission cannot recur silently on the path
  that ships.

### Invariants

1. **One ABI per v0 file, by design.** `SaveGroup` writes `sizeof(T)` raw
   bytes per object, vptr and inter-member padding included.
   src/AbiCheck.cpp turns a width change into a build failure; read its
   header comment for the defect that zeroed every player position. (This
   is the invariant v1 exists to escape: a v1 record names its fields, so
   layout changes move the writer, not the file.)
2. **The v0 bytes are not reproducible.** Padding is never written by any
   assignment. `Object::operator new` memsets (inc/Base.h:668), but the
   module resource tables come from `new TMonster[...]` (src/RComp.cpp:339)
   on a class with no zeroing allocator, and `LoadGroup` uses bare `malloc`
   (src/Registry.cpp:930 and :1037). A byte diff of `mod/Incursion.Mod` is therefore not a
   test of a serialiser change. (v1 saves are compared as a save-load-save
   FIXPOINT by tools/check_v1_full_roundtrip.sh, field-aware, with a
   documented allowlist of clock/profiling fields.)
3. **Resource tables carry no code pointers.** `Resource` has no virtual
   function (the sole candidate is commented out at inc/Res.h:292), so a
   module data block holds no vptr for the loader to fail to repair.
4. **Saving allocates handles.** `RegisterBlock` takes `LastUsedHandle++`
   per block (:546) and the new value is written to `gh.LastHandle`
   (:813), so `LastUsedHandle` grows on every save.

### The module question

"No version stamp and no rejection" is **refuted for the object types in
the digest, and still true for the resource tables.**

- A stamp exists: `SaveModule` writes `SaveFormatID()`
  (src/Registry.cpp:1404) and `LoadGroup` rejects a mismatch (:866-867)
  through `SaveFormatMatches` (:58). Confirmed in the observed bytes above.
- The stamp is derived from struct layout, not hand-edited.
  `SaveLayoutDigest()` (src/AbiCheck.cpp:144-166) hashes the primitive
  widths, `LocationInfo`, `TAttack` and every whole-object type
  `typeSize()` can return, and `SaveFormatID()` renders it as "SF" plus
  eight hex digits. A change to `sizeof(Player)` or `sizeof(Module)` moves
  it by itself.
- `SaveFormatMatches` also accepts the old `VERSION_STRING` literal (:73),
  so files written before the digest existed still load. That branch is
  marked for deletion in the source.
- A change to `sizeof(Module)` is caught twice: by the digest, and by the
  `SIGNATURE_TWO` separator, which a shifted reader misses and raises
  `ECORRUPT` (src/Registry.cpp:1021-1022).
- A change to `sizeof(TMonster)` or any other resource table is **not**
  caught. No resource table is in the digest list. Those blocks sit after
  the separator, their recorded size is never compared with the running
  binary's `sizeof`, and the loader indexes old bytes with a new stride.
  The module loads, no error fires, and the game plays on with garbage.
  (Unchanged by v1: modules are out of the v1 format's scope on purpose.)

## How to check this page

```
grep -rn "ARCHIVE_CLASS(" inc | wc -l                                   # 20
grep -rn "r\.Block(" inc src | wc -l                                    # 7 (the rest went through FIELD_BLOB)
grep -rn "numDependencies" src inc | wc -l                              # 1, the declaration; nothing uses it
grep -n  "Compression" src/SaveV1.cpp | head -3                         # the field v1 gave a meaning
grep -rn "VERSION_STRING" src inc | wc -l                               # 15; only src/Registry.cpp:73 compares
grep -rn "SaveFormatID\|SaveFormatMatches" src inc                      # the v0 stamp that does compare
grep -n  "SCHEMA_REV" src/SaveV1.cpp | head -2                          # 2 today -> "IS1.2"
xxd -l 16 mod/Incursion.Mod                                             # Sig + "SF" digest stamp
xxd -s 96 -l 28 mod/Incursion.Mod                                       # groupHeader
head -c 16 docs/evidence/inc-upw.13/Furious_Fox.sav | xxd               # v0 fixture: same "SF" stamp
head -c 16 docs/evidence/inc-upw.13/Jaoin.sav | xxd                     # pre-digest stamp "0.6.9Y19"
head -c 16 <any freshly written .sav> | xxd                             # "IS1.2" -- a v1 save
tools/check_v1_full_roundtrip.sh                                        # prints current v1/v0 sizes + delta
grep -n "virtual" inc/Res.h | head -3                                   # first live virtual is line 924
```

## Suspected defects

1. src/Registry.cpp:688-706 — the "delete the old group" loop does
   `fh.numGroups++` inside `for(i=0;i!=fh.numGroups;i++)`, so `i` never
   reaches the bound, and it rewrites the file header every iteration.
   Unreachable today: the only caller passes `newFile=true` (:1410).
2. src/Registry.cpp:969-970 vs :978-980 — `T_STAFF` (52) has no case in
   the `LoadGroup` switch and sits inside the item range, so it falls to
   the default and placement-news an `Item`. A staff is built as a `Weapon`
   (src/Item.cpp:260-261) and sized as one (src/Registry.cpp:321), so a
   loaded staff keeps the right byte count but gets `Item`'s vtable and
   loses every `Weapon` override, `isWeapon()` included (inc/Item.h:373).
   v1 mirrors this behaviour deliberately (spec risk 3): fixing it is a
   vtable change across a load, out of the schema work's scope.
3. src/Registry.cpp:964 — the mirror image. `T_COIN` (29) is built as a
   plain `Item` (src/Item.cpp:293-299) and sized as one, but `LoadGroup`
   placement-news a `Coin`, so a coin's vtable changes across a save. Also
   mirrored by v1, same reasoning.
4. src/Registry.cpp:328 vs :978-982 — `typeSize` handles `T_ANNOT` (90)
   but `LoadGroup` has no case and 90 is outside the item range, so loading
   one hits `Fatal`. Dead today; annotations live in `Module::Annotations`.
5. **Fixed.** `CFile::FRead` past the end used to zero-fill and report
   nothing. It now throws `ECORRUPT` (src/Term.cpp:3493-3494). inc-l0t.
6. **Fixed.** `LoadCompressed` now range-checks both sizes
   (src/Term.cpp:3556-3560), passes the real buffer capacity to the
   decoder, and compares the produced length with `uncompressed_size`
   (src/Term.cpp:3601-3602). `LoadGroup` checks the same header fields
   first (src/Registry.cpp:903-913). inc-l0t.
7. **Fixed.** `CFile::Seek` now tests `realloc`'s return value and throws
   `EMEMORY` (src/Term.cpp:3507-3518). It still has no caller in
   src/Registry.cpp, so it is unreached today.
8. inc/Res.h:838-840 vs :908-912 — `SaveModule` inverts `QTextSeg` in
   place on the save pass, but the restore pass runs with `saveMode` and
   `loadMode` both false (`SaveFixupScope::Restore`,
   src/Registry.cpp:187-193), so neither branch runs and the segment stays
   inverted in memory. Harmless only because the resource compiler exits
   immediately (src/RComp.cpp:223-231). The loading half is fine:
   `LoadGroup` runs its fixup pass with `loadMode` still true
   (src/Registry.cpp:1049-1052), so the un-inversion does fire.
9. **Fixed.** `reg_log` is now declared unconditionally (inc/Base.h:815)
   while its uses stay under `#ifdef DEBUG_OBJECTS`. It was declared under
   `#ifdef DEBUG`, which also changed `sizeof(Registry)` between build
   flavours and so changed the save stamp. inc-tm4.
10. src/Registry.cpp:631-658 — the data-removal branch of `RemoveObject`
    is reached only when the object was not found in the object table, and
    `r` is NULL by then, so its `while(r)` loop never runs. The branch does
    nothing, walks `DataTable` with an object-table pointer, never reads
    the `d` it sets, and falls through to the `Error` at :661.
11. **Resolved by re-observation.** An earlier survey found 512 trailing
    bytes in `mod/Incursion.Mod` that headers + `compSize` did not account
    for. In today's module (observed 2026-08-25) the accounting is exact:
    96 + 28 + 1084151 = 1084275 = the file size. Whatever produced the
    residue is gone; nothing to chase.
