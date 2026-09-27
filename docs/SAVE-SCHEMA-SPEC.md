<!-- citations: this-port -->

# Spec: a named, extensible save schema

Status: normative. Written 2026-08-24, redesigned with Brian 2026-08-25.
Amended 2026-09-26 (inc-glnx): script variables, "Script variables" below.
Background reading: `docs/ENGINE-SERIALISATION.md` describes the format this
replaces. Read it first; this spec assumes it.

## Why

Two defects, both observed, both caused by the same thing.

**A save is a byte dump of live C++ objects.** `Registry::SaveGroup` writes
`typeSize(Type)` raw bytes per object (`src/Registry.cpp:762`), vtable pointer
and padding included. So the file is welded to the compiled layout of the
binary that produced it. `SaveFormatID()` (`src/AbiCheck.cpp:167`) exists only
to notice that weld breaking. It has already fired in anger: the shipping build
and the developer build computed different digests of the same file, and the
released package could not load its own module (`inc-tm4`).

**A resource id is a position in one running count, not a name.**
`Module::__GetResource` (`src/Res.cpp:110-223`) decodes an `rID` by walking 21
per-type array counts — Monsters, Items, Features, Effects, Artifacts, Quests,
Dungeons, Routines, NPCs, Classes, Races, Domains, Gods, and so on — and
subtracting each count in turn. `CountResources` (`src/RComp.cpp:248`) sets
those counts from a first pass over the scripts. Add one resource of any type
and every id above that type's block names the resource one slot earlier.

That happened on 2026-08-24. Commit `4ba035b` added one `Effect` for bead
`inc-tek.8.8`. `szEff` grew by one. Brian's Orc, who worships Zurvash, loaded as
a Lizardfolk who worships Xel, with the classes of the three classes one slot
below his own, standing in a dungeon whose id now named an Effect. Nothing in
the engine noticed, because there was nothing to notice with.

The two defects share one cause. **The file records no names — only offsets and
positions — so nothing in it can be checked, migrated, or read by a person.**

## The project rule this rests on

**Resource lists in `lib/` are append-only.** This is a hard project rule, not a
preference of the save format. The format is correct only while it holds, and
the format's job is to notice when it has been broken.

1. **Never reorder. Never delete. Append only.** No exception, no one-off, no
   alphabetising, no moving a declaration from one file to another. A list may
   grow at the end and may do nothing else.

2. **Removal is a tombstone.** To retire a spell, leave its declaration in place
   and disable it. The line stays and keeps its position.

3. **A replaced slot loads as the new resource, and that is intended.** If the
   declaration at a position is changed — renamed, or swapped for a different
   resource entirely, such as replacing an over-powered `Wish` with a
   gain-attribute spell so that a character does not simply lose his best spell
   — then every save that referenced that position loads the new resource. This
   is a known and expected effect. It is done only when it is the desired
   result. It is never a defect, it MUST NOT be reported as one, and nothing
   needs to disambiguate it.

The **kinds** of array are append-only on the same terms: a new resource kind
MAY be added at the end of the list of kinds, and no existing kind may be
reordered or removed.

**Script variables are append-only within their owner, on the same terms.** A
script variable declared inside a resource body belongs to that resource. A
module-level variable belongs to the module's global list. Within one owner, a
new variable MUST go after the existing ones, and a retired variable MUST stay
declared. There is no rule about where the owning resource sits, and none for a
variable in a new resource. A rename in place loads as the new variable at that
position, as rule 3 says for resources.

**A build-time order check enforces both rules.** A committed ledger records
every entry of the 21 arrays and every script variable per owner, in order. A
commit whose module inserts, removes or reorders an entry or a variable fails
the check, which names the entry. After a legal append the author re-records
the ledger with `--record` and commits it with the change. "Script variables"
below gives the check's full rules. The load-time drift rules stay as the
backstop.

Appending is the only structural change the rule permits, and appending is
exactly what shifts the running count. So the rule alone does not make saved
references stable. It guarantees one thing, and the format is built on it: a
resource keeps its **position within its own array**, forever.

## Goal

A save file whose schema a person can read, and which survives ordinary changes
to the game.

The format MUST satisfy four properties.

1. **Named.** Every field carries an identity, not just a position.
2. **Extensible, forwards only.** Adding a field MUST NOT invalidate existing
   saves. A field is never removed: its number is retired, never reused, and a
   save carrying a field number the running binary does not know MUST be
   refused, loudly.
3. **Resource-safe.** A saved resource reference MUST survive the module being
   recompiled with resources **appended**. Resources are never reordered and
   never removed; a save that meets evidence of either MUST be refused, loudly.
4. **Layout-safe.** No vtable pointer, no padding, and no compiler-chosen
   bitfield order reaches the file.

## Non-goals

- **Modules stay on the raw path.** `Game::SaveModule` (`src/Registry.cpp:1438`)
  keeps calling the existing `SaveGroup`. `mod/Incursion.Mod` is a separate file
  written by the resource compiler (`src/RComp.cpp:223`) and read at startup by
  `LoadModules()`. A save never contains a module; it refers to one. A module is
  regenerated by the same build that reads it, so its weld to the ABI costs
  nothing.
- **`gallery.dat` and `Options.Dat` are untouched.** They have their own writers
  in `src/Create.cpp`.
- **`String` and `Array` are not touched.** `FIELD_STR` and `FIELD_OBJ` write
  their contents inline on the v1 path, so `Registry::Block`
  (`src/Registry.cpp:355`) and the one-line `String::Serialize`
  (`src/Base.cpp:504`) are needed only by the v0 reader, which keeps them
  unchanged. No type used across the app changes at all.
- **No change to in-memory representation.** An `rID` stays a 32-bit index at
  run time. `RES()`, `NAME()` and range tests such as
  `xID >= EffectID(0) && xID <= EffectID(szEff-1)` (`src/Res.cpp:741`) keep
  working untouched. Only the bytes on disk change.
- **The engine's `rID` arithmetic is not touched.** Re-slicing the id inside the
  engine would fix the renumbering too, at the cost of auditing about 70 sites
  across 11 files. Brian rejected that blast radius. The conversion happens at
  the save/load boundary only.

## The format

A v1 save is a header, a module manifest, and a stream of tagged records.

### Header

The existing `fileHeader` (`inc/Base.h:700-708`) is kept for the fields the
load menu already reads — `Sig`, `Name`, `numGroups`. `Version[12]` carries
`"IS1"` plus a decimal schema revision instead of the ABI digest. The reader
MUST dispatch on this field: `"SF"` prefix means the v0 raw reader, `"IS"` means
v1.

### Records

One record per object. A record is:

```
uint8   type            the T_* constant, as today
uint32  length          bytes to the end of this record
  repeated field:
    uint16  tag         stable field number, unique within the class chain
    uint8   kind        u8 i8 u16 i16 u32 i32 str blob rid handle array embed
    ...     payload     sized by kind, or length-prefixed for str/blob/array
  terminator tag 0
```

The reader loops over fields. A tag it knows, it stores. A tag it knows and does
not meet, it leaves at the value the constructor gave it — that is how an older
save loads under a newer binary. **A tag it does not know MUST refuse the load**,
naming the tag: a field it cannot interpret means the file was written by
something newer than itself.

### Field numbers and class layout: the two rules

Each class owns a range of tag numbers. Within that range:

- A new field MUST take the next unused number.
- A retired field's number MUST NOT be reused, ever.
- A field's number MUST NOT change, ever.

That is the first rule. The second rule concerns the byte layout of the class.

`src/SaveV1.cpp` holds one pad row per saved class (`CreaturePads`,
`MonsterPads` and the others in `SchemaPins[]`). A pad row lists every byte of
the object that no `FIELD_` line covers: the vtable pointer, the compiler's
padding, and each member that is deliberately not saved. A DEBUG build compares
those rows with the bytes the field lists actually cover, and it refuses to
write the save on any difference.

- When you add, remove or resize a member of a saved class, you MUST re-measure
  the pad rows of that class and of every class derived from it.
- Run `tools/save_pad_rows.sh`. It reads the layout from the compiler and prints
  every row in the form `src/SaveV1.cpp` uses. Paste the rows it prints.
- `tools/check_save_pad_rows.sh` fails when a declared row differs from the
  measured one.

The member you add is often not the member that breaks. On 2026-09-21 a new
`int16` in `Creature` (inc-30ps) landed in free space, but it pushed two
existing saved fields into bytes the rows still called padding. Every save then
failed with `SCHEMA COVERAGE` errors (inc-xlwa).

### How a class declares its fields

`ARCHIVE_CLASS` (`inc/Base.h:778`) already generates a
`Serialize(Registry&, bool isSave)` that calls its base first, and 20 classes
already use it. The bodies gain field declarations beside the fixups they
already carry. `Thing` (`inc/Map.h:943-965`) becomes:

```cpp
ARCHIVE_CLASS(Thing,Object,r)
  FIELD_H  (1, Next);
  FIELD_H  (2, hm);          /* m is rebuilt from hm, as today */
  FIELD_I16(3, x);
  FIELD_I16(4, y);
  FIELD_U32(5, Image);
  FIELD_I16(6, Timeout);
  FIELD_I16(7, StoredMovementTimeout);
  FIELD_U32(8, Flags);
  FIELD_STR(9, Named);
  FIELD_OBJ(10, __Stati);
  FIELD_OBJ(11, backRefs);
END_ARCHIVE
```

`Item` (`inc/Item.h:20-38`) gains `FIELD_RID(n, iID)`, `FIELD_RID(n, eID)` and
`FIELD_RID(n, homeID)` beside its scalars. One macro set serves both directions,
as `Serialize` does today, so a field cannot be written and not read.

### The map grid

`Map::Serialize` (`inc/Map.h:674-675`) writes `Grid` as one raw block of
`sizeof(LocationInfo)*sizeX*sizeY`. `LocationInfo` (`inc/Map.h:36-60`) is
bitfields, whose order and packing the compiler chooses.

The grid MUST NOT be written field-by-field: a single 80x100 map would emit
about 120,000 field records.

Instead the grid is written as a blob of a **packed layout this port defines** —
a fixed 8 bytes per tile, with a bit assignment written down in the source
beside a `static_assert` on the count. One hand-written pack and unpack loop
converts. The record carries `sizeX`, `sizeY` and the packed element size, and
a mismatch MUST abort the load.

Terrain and region are 8-bit indices into `TerraList` (`inc/Map.h:39-40`), not
resource ids, so the grid itself carries no `rID` and needs none. `TerraList` is
an ordinary array of `rID` and gets `FIELD_RID` treatment per element.

### The 21 arrays, in their fixed order

Position 0 is `Monster`, and the order is exactly the walk order of
`__GetResource`:

```
 0 Monster    7 Routine   14 Terrain
 1 Item       8 NPC       15 Text
 2 Feature    9 Class     16 Variable
 3 Effect    10 Race      17 Template
 4 Artifact  11 Domain    18 Flavour
 5 Quest     12 God       19 Behaviour
 6 Dungeon   13 Region    20 Encounter
```

This order is a wire constant. It MUST match `__GetResource`'s walk and
`V1GetPool`'s switch (`src/SaveV1.cpp:833`). A new kind is appended at 21.

### The module manifest

A v1 save carries a manifest: one entry per module slot that was loaded when the
save was written. It is a record of the modules **as they were at save time**,
written once per file, not once per reference.

**How the reader finds a slot's entry.** By tag number. The manifest lives
inside the existing per-module scope, tag 816 (`inc/Res.h:1253`), where module
slot `i` is already written as inner tag `1+i`. The slot number is the
addressing and it comes from the top 8 bits of the `rID` itself: to convert a
reference in slot 3, the reader reads inner tag 4. There is no name lookup and
no search anywhere in this path.

**What a slot's entry holds**, as two new tags inside that slot's scope,
alongside the segment record already there:

* the length of each of the module's 21 arrays, in the fixed order above, as one
  `K_ARRAY` of 21 `uint32`;
* the name of every entry in every array, in position order, array by array, as
  one length-prefixed blob of `uint16` length plus bytes per name. The name
  count MUST equal the sum of the 21 lengths, and a disagreement is `ECORRUPT`.

**The module's identity is not in the manifest and MUST NOT be copied into it.**
It is already recorded in `ModFiles`, tag 868, whose `ModuleRecord`
(`inc/Res.h:1108`) holds `Slot`, `hMod` and `FName[1024]`. Duplicating it would
create a second copy to disagree with the first. The manifest's names are a
stronger identity check than a filename anyway: a file renamed on disk changes
nothing the format cares about, and a file with the same name but different
contents is caught by the drift rules below.

**A manifest entry for a slot with no loaded module MUST refuse the load,**
naming the slot. So MUST a loaded module in a slot the manifest does not
describe, if any reference points into it.

**Why it carries names and not only lengths.** Lengths cannot detect a reorder:
alphabetising an array changes no length, so a lengths-only manifest would load
the character silently with every reference pointing at the wrong resource. The
names are what make the drift rules below possible.

**Size, measured.** `tools/check_v1_full_roundtrip.sh` on its fixed seed writes
32,781 bytes without the manifest and 53,980 bytes with it: **+21,199 bytes
compressed**, measured 2026-08-25 by building both ways. The manifest is a fixed
cost per save, independent of how large the save is, because it describes the
module rather than the game. On that small early-game save it is a 65% increase.
On a real save -- `save/Dench.sav` is 2,439,280 bytes -- the same 21 KB is under
one percent.

That cost buys a save that validates itself against a module rather than
trusting that a build-time check was run, which matters for a module this
project did not compile.

### Resource references

**A reference to a resource is the plain 32-bit `rID` the engine uses.** No
packing, no bit-splitting, no name, no table index. Nothing about the shape of a
record changes.

The conversion is entirely in the reader:

1. Split the saved `rID` into its module slot and its running index.
2. Walk the **manifest's** lengths for that slot to turn the running index into
   an array number and a position within that array.
3. Apply the drift rules below.
4. Walk the **loaded module's** lengths to turn that array number and position
   back into the running index this run's engine uses, and rebuild the `rID`.

**A shorter array is a removal, and it MUST be refused.** If a loaded array is
shorter than the length the manifest recorded for it, the append-only rule was
broken. The reader MUST refuse before it converts anything, naming the array,
the recorded length and the length found. It MUST NOT clamp the position, skip
the reference, zero it, or load the character with the remaining entries. This
holds even when no saved reference falls in the missing range: the shrink is the
defect, not the dangling reference.

Otherwise step 4 always succeeds for any position the manifest covers, because
an array can only have grown.

**Sequencing.** Both load paths reload modules only after the save group is read
(`src/Registry.cpp:1347-1390`, `src/Dump.cpp:220-264`), so `Game::Modules` is
stale or zeroed while records are being replayed. The manifest MUST be parsed
with the records and the conversion MUST be deferred to `SaveV1_ResolveNames()`,
which already runs after the reload.

### Drift rules

For each array, the reader compares the manifest's name list against the loaded
module's name list, over positions 0 to (manifest length − 1). It refuses the
load only on positive evidence that entries **moved**. Two shapes count:

**A slide.** For some position N, the name now at each position from N onward
equals the name the manifest recorded one position earlier (an insertion) or one
position later (a deletion). A slide MUST be at least two consecutive positions
before it counts, so that a single coincidental match does not trip it.

**A shuffle.** The set of names in the loaded array over the compared range is
the same set the manifest recorded, but at least one name is at a different
position.

Anything else is accepted and loads silently. One changed name, ten changed
names, or every name changed is a rename or a deliberate replacement under rule
3 above, and rule 3 says it MUST load.

A refusal MUST name the array, the first offending position, the name the
manifest recorded there, and the name found there instead.

**The one case this cannot catch,** stated so that nobody later believes the
check is total: renaming every entry in an array **and** reordering it in the
same change is undetectable from the file, because there is no surviving name to
line up and no set to compare. No design can detect it. The build-time order
check on the source files still sees it, because there it is moved lines in a
diff.

### The resource memory segment

`Game::Serialize` writes each module's `MDataSeg` as one raw block
(`inc/Res.h:1262-1263`). The block is the module's script data segment followed
by the per-player resource memory: `MonMem[szMon]`, `ItemMem[szItm]`,
`EffMem[szEff]`, `RegMem[szReg]`, addressed arithmetically from the resource's
position (`Module::GetMemoryPtr`, `src/Res.cpp:719`). `EffMem`
(`inc/Res.h:1432`) carries `FlavorID` and `PFlavorID` — whole flavour `rID`s,
assigned by the per-game shuffle in `Game::SetFlavors` (`src/Item.cpp:342`).
This is the identification state: which potion looks like what, and what the
player has tried and knows.

Left raw, this block reproduces the renumbering defect inside v1. Add one
`Effect` and every memory row above it shifts by one row.

So the memory rows MUST NOT stay raw. Each row is written with the (array,
position) of the resource it annotates, and the flavour `rID` values inside
`EffMem` are ordinary resource references and convert like any other. A resource
with no row keeps zeroed memory, as a new game gives it. There is no
discard-on-missing case: under the append-only rule a recorded position always
exists, and a shorter array has already refused the load.

The script data segment at the front of the block holds the script variables.
"Script variables" below covers it.

### Script variables

**What they are.** The resource compiler gives each script variable one 32-bit
slot, numbered in the order it reads the declarations (`HeapHead++`,
`lang/Grammar.acc`). The virtual machine finds slot N at byte 4N of the
module's data segment. A variable is either module-level (`g_declaration`) or
declared inside a resource body (`r_declaration`). A `static` declaration
inside an event handler (`STATIC r_declaration`, `lang/Grammar.acc`) is also a
resource variable of the enclosing resource: `r_declaration` fixes the event to
0, so its owner is that resource. No `lib/` file uses `static` today.

**The defect this section repairs (inc-glnx, upstream).** `Module::szDataSeg`
was never assigned, so it was 0, and the memory rows started at byte 0 on top
of the variables. Script writes changed the first monster rows, and
monster-memory updates changed script variables. The compiler MUST set
`szDataSeg = HeapHead * sizeof(int32)`. The rows then start after the variables.

**The variable table.** The compiled module already stores one `DebugInfo` row
per compiler binding in `Module::Symbols` (field 792, filled by
`Module::AddDebugInfo` for every binding). A **variable row** is a row whose
`BType` is `GLOB_VAR` or `RES_VAR`; every other row is ignored. Its slot is
`DebugInfo.Address`, its owner is `DebugInfo.xID` (0 for `GLOB_VAR`), its name
is `DebugInfo.Ident`, and its type is `DebugInfo.DataType`.

A module is valid for this section only when all of these hold, checked on save
and on load before any value is placed. A failure is `ECORRUPT`:

* `szDataSeg` equals 4 times the number of variable rows. This also refuses a
  module compiled before the fix (`szDataSeg` 0, variable rows present).
* The variable rows' addresses are exactly 0 to N−1, with no gap and no repeat.
* Every `RES_VAR` owner is an `rID` in module slot 0 inside one of the 21
  arrays. The compiler builds only into slot 0, so only slot 0 carries
  variables; a variable row in any other slot's module refuses.

The preprocessor truncates every identifier to 31 characters (`IDMAX`,
`inc/cppdef.h`) before the compiler sees it, so `DebugInfo::Ident` always holds
the whole name, and two names that agree in 31 characters already collide as a
duplicate declaration. The compiler MUST also:

* assert, for each `RES_VAR`, that the owner it looked up by name equals the
  resource it is compiling. The owner lookup (`FIND`) is case-insensitive and
  searches every pool, so two resources whose names differ only in case could
  otherwise swap variables.

**The key.** A variable's identity in a save is (owner, ordinal), the same shape
as a resource's (array, position). The owner is the owning resource's `rID`, or
0 for a module-level variable. The ordinal is the variable's rank among its
owner's variables in slot order. The name identifies nothing; it only detects
drift. The loader does no name lookup to place a value.

**The record.** Inside each slot's segment embed, beside inner tags 2 to 5:

```
6: K_U32   varCount
7: K_BLOB  varCount records, in slot order:
             u32  owner    plain rID of the owning resource, 0 = module level
             u8   type     declared DT_* type
             u8   nameLen, then nameLen name bytes
             i32  value
```

Accepted type values are 2, 3, 4, 5, 7, 8, 9, 10, 11 and 12
(`inc/RComp.h`). Type 8 (`Rect`) and every integer or boolean type carry their
value unchanged. Types 1 (`void`) and 6 refuse, as does any value not listed.

Every slot is written, zero or not. A `DT_HTEXT` value is always written as 0,
because a text offset belongs to the module that wrote it. Save, load, save
therefore gives byte-identical files.

**Which tags a revision carries.** At revision 4 a slot's record MUST carry
tags 2, 3, 6 and 7 together, and MUST NOT carry tag 1; a record with none of
them is an empty slot, as today. At revision 3 the record MUST carry tags 1, 2
and 3 together, tag 1 MUST have length 0, and tags 6 and 7 MUST NOT appear.
Inner tag 1 is retired from revision 4 and never reused.

**The load**, deferred to `SaveV1_ResolveNames()` after the module reload:

1. Group the saved records by owner, in file order. Convert each owner `rID`
   through the manifest, with the usual abort semantics. Owner 0 stays 0.
2. Build the loaded module's variable rows per owner, in slot order.
3. Check each owner for drift. The compiler refuses a duplicate name within one
   owner, so a name is unique inside its owner. Therefore:
   * A saved name that appears in the loaded owner's list at a DIFFERENT
     ordinal refuses (an insertion, a removal or a reorder).
   * A loaded list shorter than the saved list refuses (a removal).
   * A saved name that does not appear in the loaded list at all is a rename,
     and loads at its ordinal.
   * Loaded variables past the saved range start at 0.
   * An owner with no saved records keeps all its variables at 0.

   The array drift rules need two consecutive shifted positions, which one or
   two variables cannot show. Most owners have one variable, so this rule
   replaces them for variables.
4. Place each value at the slot the loaded module gives that (owner, ordinal),
   after checking the slot is below N. `DT_RID` converts through the manifest,
   with abort semantics; 0 is null. `DT_HOBJ` loads as saved, as `FIELD_H`
   does. `DT_HTEXT` loads as 0. Every other accepted type loads as saved.
5. Allocate the segment from the loaded geometry, and place the memory rows
   after the variables.

Every refusal names the owner, the ordinal, the recorded name and the found
name. Refusals are collected and thrown as one `ECORRUPT`, as for the rows.

**Old saves: the recovery.** The file's format and stamp select it, never a
size test. It gives an old character the variable values the pre-fix game
would read.

*The frozen table.* A table of 97 rows (owner array, owner position, owner
name, variable name, type), one per slot of the pre-fix module, is committed in
the source. It is the master variable list from the start of the v1 format up
to 391e353. Commit 86edfc0 (inc-s3bb) added `choir` to Music of the Spheres,
making 98. No save file exists from 86edfc0 to the fix (checked 2026-09-26),
and a save written in that window would recover wrongly from that slot onward.
The fix bead MUST merge master before it generates the table, and MUST
generate it from the module at 391e353.

*IS1.3 files* (tag 1 of length 0, no tag 6 or 7):

1. Check the save's manifest against the table. Each of the save's 21 array
   lengths MUST be no longer than that array's length at 391e353, which the
   table records. For each table row, the manifest's name at (owner array,
   owner position) MUST equal the row's owner name. A failure refuses, naming
   the array or the row. This catches a save written by a module with a
   different variable list, such as an epic-branch save, which carries
   resources master does not have.
2. Unpack monster positions 0 to 24, numbered by the save's manifest, into a
   400-byte image with row p at byte 16p, as the rev-3 reader lays rows.
3. Read bytes 0 to 387 of that image as the values of the 97 table slots.
4. Map each table row to the loaded slot by (owner array, position, ordinal),
   with the drift checks of load step 3.
5. Place monster rows from position 25 on, after the variables. Positions 0 to
   24 load empty: the first 25 monsters lose their memory in an old save. The
   variables had already corrupted it.

An IS1.3 save keeps a slot only as far as the `MonMem` bitfields cover it: the
first unit of each row whole, the other three at 17, 18 and 21 low bits. In a
partial unit, a `DT_HOBJ` or `DT_RID` value loads as 0, because a cut handle
can name a different live object, and a cut `rID` a different resource. Other
partial values load as read, which is what the pre-fix game read.

*v0 files* (stamp `SF...` or an old `VERSION_STRING`): a v0 load puts the raw
block, sized from the file, straight into `MDataSeg`, and `SaveV1_ResolveNames`
does not act on a v0 file. A v0 branch MUST therefore run in each of the three
v0 load sites, `LoadNamedGame`, `RunSaveDump` and `RunSaveConvert`, after the
module reload and before `SaveV1_CanWrite` or any reader of the block:

1. Refuse unless the old block's size equals the loaded module's row total with
   `szDataSeg` 0.
2. Allocate a new block from the loaded geometry, and set `MDataSeg[i]` and
   `MDataSegSize[i]` to it.
3. Recover bytes 0 to 387 of the old block through the table, as IS1.3 steps
   3 and 4 do. Every unit is whole in v0.
4. Copy the old rows from position 25 on after the variables; positions 0 to
   24 stay empty.

A v0 file carries no manifest, so a v0 file from a module with a different
variable list is not detected. The v0 recovery is exact only for a file written
with the table's variable list. The committed v0 fixtures stay unconverted; only
copies are converted, as today.

`SCHEMA_REV` goes from 3 to 4. `MIN_READ_REV` stays 3, because the rev-3 reader
stays and the recovery only adds to it.

**What lands in the fix commit.** The `szDataSeg` fix alone makes every existing
save refuse to load, so one commit MUST carry all of: the fix, the regenerated
`src/yygram.cpp`, the variable record, the recovery, the revision bump, the
dump section, the build-time order check with its first ledger, updated
expectations in `tools/craft_bad_v1_saves.py` and `tools/check_dump_save.sh`,
the `docs/SCRIPT-DATA-SEGMENT.md` supersession with its `docs/doc-deps.tsv` and
`tools/doc_citations.baseline` rows, and a re-recorded `tools/gates/dive.baseline`
with per-seed evidence if the gate moves. Moving the variables off the monster
rows changes what scripts read, so seeded results can change.

**The build-time order check.** It reads the compiled module and a committed
ledger, and MUST NOT write any file. For each array, and for each variable
owner, it compares the ledger's list with the module's list. It fails when:

* the module's list is shorter than the ledger's (a removal); or
* a name the ledger records at position P is present in the module's list but
  not at P (an insertion, a removal or a reorder). A name that occurs more than
  once in the ledger's list is exempt from this test, so a reorder among
  duplicate names (for example the Flavour array's repeated colours) is not
  detected.

A name that the ledger records and the module lacks is a rename or a
replacement, and passes (rule 3). Entries past the ledger's length pass. The
ledger changes only through `--record`, which MUST refuse exactly what the
check fails, and MUST accept a rename. The ledger
diff goes in the same commit as the change that needs it. The check carries a
`# gate: live` marker, because it needs a compiled module, so
`tools/nightly_verify.sh` and `tools/finish_bead.sh` run it. Its first ledger
is recorded from master at the fix commit.

**Merging this into an epic branch.** An epic that added, removed or moved a
variable inside an existing owner breaks the append rule against the ledger.
The bead that merges master into the epic (`.claude/rules/epic-branches.md`)
MUST restore each retired declaration at its old ordinal, place each new
variable after the owner's existing ones, and re-record the ledger in that bead.
Saves written by the epic before that merge are IS1.3 files from a different
variable list, and they MUST convert, not refuse. That bead MUST build the
epic's module at each commit where the epic's variable list changed, and add
one frozen table per distinct list, each with its build's array lengths and
owner names. The recovery tries every table with IS1.3 step 1. Exactly one
table MUST match, or all matching tables MUST hold the same variable list;
otherwise the load refuses, naming the matching tables. Masok
(`~/Scripts/Incursion-inc-pu6v/save/Masok.sav`) MUST convert, and the bead
MUST show it loading.

`docs/SCRIPT-DATA-SEGMENT.md` is superseded. Its verdict rested on "0 bytes in
every real module, and no compile path can change it", which was false.

### Version rules: forward-only

* A file whose schema revision is **newer** than the running binary MUST be
  refused, loudly, naming both revisions.
* A file whose schema revision is **older** MUST load, DOWN TO A DECLARED
  FLOOR. Fields the binary knows and the file lacks keep their constructed
  defaults; the next save writes the current format.
* The floor is `MIN_READ_REV`, and a file below it MUST be refused as loudly
  as a newer one, naming both revisions. The floor exists because the
  older-revision rule above holds only while the change was ADDITIVE. A
  revision that deletes a reader is not additive: `IS1.3` deleted the code
  that read a name-table reference and a name-keyed memory row, and those
  rows travel inside one opaque blob, so nothing in the shape of an `IS1.2`
  file tells the reader that the interior cuts have moved. Such a file MUST
  NOT be handed to the new reader on the chance that a bounds check catches
  it. `MIN_READ_REV` is 3 today, and MUST rise with any future revision that
  deletes a reader.
* Within a revision, an unknown field tag MUST refuse the load, per "Records"
  above.

Saves are therefore forward-compatible only. That is accepted.

## Compatibility, and Brian's character

The v0 raw reader stays in the binary. It is 200 lines, it works, and deleting
it buys nothing.

That makes the converter trivial and exact:

```
incursion -convert save/Dench.sav
```

It loads the save with the existing v0 reader, and writes it back as v1. **The
conversion is where the renumbering is repaired**, because the v0 read resolves
every `rID` against the module in `mod/`, and the v1 write records the manifest
that pins those positions.

Therefore the converter MUST be run with a module whose numbering matches the
save. For Brian's save that is any module built before `4ba035b`. One has been
built and verified: HEAD with only the immolation `Effect` reversed reads his
save as Orc, Zurvash, Ranger 3 / Rogue 2 / Druid 3, The Goblin Caves, depth 6,
with an equipped list byte-identical to the pre-`4ba035b` reading. After
conversion the module can be rebuilt at full HEAD, immolation included, and the
save follows.

The two committed fixtures, `docs/evidence/inc-upw.13/Furious_Fox.sav` and
`Jaoin.sav`, keep loading through the v0 reader. They are evidence and MUST NOT
be converted.

## Risks

1. **A missed field is silent.** Today a forgotten member is still written,
   because the whole object is dumped. Under v1 it is simply absent and loads as
   its constructed default. Mitigated by the round-trip test below, and by a
   debug-build check that every byte of the object is covered by exactly one
   field declaration.
2. **`TargetSystem::Serialize` is empty** (`src/Target.cpp:1447-1449`) and
   correct only by luck, as `docs/ENGINE-SERIALISATION.md` records. It gains a
   real field list here.
3. **`T_STAFF` and `T_COIN` change vtable across a save today** (defects 2 and 3
   in `docs/ENGINE-SERIALISATION.md`). v1 does not fix them and MUST NOT be
   blamed for them. They are separate beads.
4. **The append-only rule is invisible in a diff.** Positions come from
   declaration order across `lib/*.irh`. Someone alphabetising a file, or moving
   entries between files, breaks every save in the wild from a commit that looks
   harmless. The drift rules catch it at load; the build-time order check
   (see the project rule) catches it before the commit lands.
5. **A variable that holds an `rID` but is declared as an integer** carries its
   value unconverted. The loader trusts the declared type. The four `rID`
   holders today are declared `rID`.
6. **Save size.** Measured, not assumed. The manifest costs +21,199 bytes
   compressed on the round-trip check's seed (32,781 -> 53,980). It is a fixed
   per-save cost, so it is 65% of a small early save and under 1% of a 2.4 MB
   one. Tags and kinds cost about 3 bytes per field on top.
7. **No runtime check that `mod/Incursion.Mod` was built by the running
   binary.** There is a file signature and range sanity checks
   (`inc/Res.h:868`), but no ABI digest. A stale module with a new binary is
   undefined behaviour rather than a refusal. Out of scope here; tracked
   separately.

## Test plan

Legal changes, which MUST load:

1. **Round trip, no drift.** Save, load, save again. The second file MUST equal
   the first byte for byte. This is possible only under v1:
   `docs/ENGINE-SERIALISATION.md` invariant 2 records that v0's bytes are not
   reproducible, because padding is never assigned.
2. **Legal append.** Add an Effect to the end of the Effect list, recompile,
   load a save written before it. Every reference MUST resolve to the same
   resource it named before. This is the case the current format gets wrong.
3. **Legal replacement.** Change the name of one entry in place. The save MUST
   load silently and the character MUST hold the new resource at that position.
4. **Legal mass rename.** Change every name in one array. Same requirement.

Illegal changes, which MUST refuse:

5. **Insertion.** Insert an Effect in the middle. The refusal MUST name the
   array and the first shifted position.
6. **Shuffle.** Alphabetise one array.
7. **Removal, middle.** Delete an Effect from the middle. This shows as a slide,
   and the array is also shorter.
8. **Removal, end.** Delete the LAST entry of an array, so no name slides and
   only the length changes. The refusal MUST come from the length alone. Run
   this with a save that references nothing in the missing range, to prove the
   refusal does not depend on catching a dangling reference.
9. **Newer revision.** A file stamped one schema revision newer. The stamp
   MUST be taken from a file the run itself produced, never written as a
   constant: a hard-coded revision stops testing the gate the day
   `SCHEMA_REV` moves.
9a. **Revision below the floor.** A file stamped below `MIN_READ_REV`.
9b. **Malformed stamp.** Digits followed by anything but NUL padding, in all
    twelve bytes of `fileHeader.Version`. It MUST be refused as malformed
    rather than read as the revision its leading digits spell, and the
    refusal MUST print the stamp bounded to twelve bytes.
10. **Unknown tag.** A file carrying a field tag the binary does not know.
11. **Adversarial.** Truncation at every record boundary; manifest lengths that
    overflow, that disagree with the name count, or that exceed the loaded
    module; a manifest for an absent module slot; a truncated manifest; a
    reference past the end of the manifest; a grid record whose `sizeX`/`sizeY`
    disagree with the map. Each MUST be refused cleanly and MUST NOT read out of
    bounds.

Live, as Brian plays:

12. Convert `save/Dench.sav`, rebuild the module at full HEAD, load, walk a
    level, save, reload. Character sheet, inventory, mount and god unchanged.
13. One full soak seed on the new binary with the unchanged module, to show the
    module path is untouched.
14. Convert a save, rebuild the module with one `Effect` appended, load. Every
    potion and scroll appearance, and every Known and Tried flag, unchanged.
    This is the oracle for the memory segment; it fails on the raw block.

Script variables. The `-dump` report MUST print every variable by owner, name,
type and value; it is the oracle for these cases. It MUST print the values as
the load placed them, copied before any report step runs game logic: the
report's own steps (for example `DumpStati`) run scripts that write variables. Legal, which MUST load with
every existing value unchanged:

15. **Round trip** with the variable records: case 1 holds.
16. **Append in a body.** One variable appended after an existing god
    tracker. The old value is unchanged; the new variable is 0.
17. **Append a module-level variable** after the last one. Same requirement.
18. **A resource append moves every slot.** Append an Effect that declares a
    variable. Every older variable keeps its value although its slot moved.
19. **Rename a variable in place.** Loads silently, value at its position.
20. **Old saves.** Every `tools/fixtures/chars/*.sav` loads, and so do
    `save/Keos.sav` and `save/Zakfienal.sav` (copies, in a sandbox). The test
    MUST name one IS1.3 fixture whose recovered slots are non-zero in a whole
    unit and in each partial unit (17, 18 and 21 bits), and MUST check each
    exact expected value, computed from the pre-fix reading.
21. **v0 convert.** `tools/check_convert_guard.sh` passes.

Illegal, which MUST refuse and name the owner, the ordinal and both names:

22. **Insert** a variable before an existing one in the same body.
23. **Swap** two variables in one body.
24. **Remove** a variable from a body, with a save that wrote it.
25. **Adversarial.** An unknown type byte; types 1 and 6; a name length past
    the blob; a `varCount` past the blob; an owner outside the manifest; a
    revision-4 file that carries tag 1, or lacks tag 6 or 7; a revision-3 file
    whose tag 1 is not empty, or that carries tag 6 or 7. Each refuses cleanly
    with no out-of-bounds read.
26. **Build-time order check.** In a sandbox `lib/`: insert a variable before
    an existing one; remove one; swap two; insert an Effect mid-array; remove
    one; swap two. The check is red for each, and `--record` refuses each.
    Append a variable and an Effect: green, and `--record` accepts. Rename a
    variable and an Effect in place: green, and `--record` accepts.
27. **Module validity.** A module with `szDataSeg` 0 and variable rows, one
    with a gap in the addresses, and one with a variable row outside slot 0:
    each is `ECORRUPT`.
28. **Recovery edge cases.** A recovered `DT_RID` that fails conversion loads
    as 0 with one stderr line. A partial-unit `DT_HOBJ` loads as 0. An IS1.3
    save whose manifest has an array longer than at 391e353 refuses. A v0 copy
    whose block size does not match refuses.
29. **A variable in a newly appended resource**, with a save written before
    the resource existed: loads, the new variable is 0.
30. **Round trip with a `DT_HTEXT` set**: cast Command, save, load, save; the
    two files are identical.

Cases 1 to 8 need a deliberately built sandbox **module**, the way
`tools/check_spell_god_drift.sh` already builds one. Cases 9 to 11 need a
deliberately malformed **save file**; those are Claude's to write, because
OpenAI's content filter terminates a Codex run that touches the crafting script.
