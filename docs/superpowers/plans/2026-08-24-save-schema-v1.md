<!-- citations: this-port -->

# Save Schema v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the raw-memory-dump save format (v0) with a named, extensible, resource-safe, layout-safe tagged-record format (v1), while the v0 reader keeps reading every existing save and every module stays on the raw path.

**Architecture:** A v1 save keeps the existing 96-byte `fileHeader` and 28-byte `groupHeader` shapes, but the payload becomes a stream of tagged records (one per object) followed by a resource name table. Field declarations live inside the existing `ARCHIVE_CLASS` bodies as `FIELD_*` macro lines that serve the v0 path, the v1 save path, and the v1 load path from one declaration. All v1 state lives in file-scope context objects in a new `src/SaveV1.cpp` — never in `Registry` data members, because `sizeof(Registry)` feeds `SaveLayoutDigest()` and moving it orphans every v0 save.

**Tech Stack:** C++17 (clang, arm64 macOS), bash test scripts driving headless binaries (the project's test idiom — no unit-test framework), Python 3 for save-mutation crafting.

**Spec:** `docs/SAVE-SCHEMA-SPEC.md` (approved 2026-08-24). Background: `docs/ENGINE-SERIALISATION.md`. The plan argues from the spec; executors read both.

## Global Constraints

Every task's requirements implicitly include this section.

1. **Never `-fsanitize=address`.** It deadlocks on this machine. UBSan works (`tools/check_load_corrupt.sh` shows the pattern).
2. **Name resolution is case-SENSITIVE.** `stricmp` is FORBIDDEN anywhere in the name table code. `Module::FindResource` uses `stricmp` and stays untouched; the name table does not call it. Measured basis: case-sensitive names are unique in every pool except Flavour; case-folded they are not (`Effect "Heartstone"` vs `Effect "heartstone"`).
3. **An unresolvable name-table entry MUST abort the load** with a message naming every unresolvable entry. It MUST NOT be zeroed and MUST NOT be skipped. (Exception, per spec §resource memory segment: a *memory row* naming a missing resource is discarded — it is annotation, not a reference. The flavour `rID` *values inside* `EffMem` go through the global table and get abort semantics.)
4. **Tag numbers are never reused and never change.** A new field takes the next unused number in its class's range. A retired field's number is dead forever.
5. **No data member may be added to, removed from, or resized in any class listed in `SaveLayoutDigest()`** (`src/AbiCheck.cpp:144-163`: `Game`, `Term`, `Map`, `Registry`, `Monster`, `Player`, `Module`, `Portal`, `Door`, `Trap`, `Feature`, `Container`, `Food`, `Corpse`, `Weapon`, `Armour`, `Annotation`, `Item`, plus `LocationInfo` and `TAttack`). Moving the digest changes `SaveFormatID()` and every v0 save — Brian's `save/Dench.sav` and both fixtures — becomes unreadable before Task 10 can convert it. New v1 state goes in file-scope objects in `src/SaveV1.cpp`, non-virtual `Registry` methods, and statics. Each task verifies the stamp is unchanged (command given per task).
6. **The v0 reader stays in the binary.** Modules stay on the raw `SaveGroup` path (`Game::SaveModule`, `src/Registry.cpp:1361`, is not touched by any task).
7. **The fixtures `docs/evidence/inc-upw.13/Furious_Fox.sav` and `docs/evidence/inc-upw.13/Jaoin.sav` must NEVER be converted.** They are evidence. Task 10 builds a guard that refuses them.
8. **The debug-build coverage check is NON-OPTIONAL.** Every byte of every archived object must be covered by exactly one field declaration (or an explicit `FIELD_SKIP`, or a pinned padding range). It is the divergence insurance against upstream adding members. It lands in Task 1 and every later task's verification re-runs it.
9. **Build commands:** `./build_macos.sh` (graphical + module recompile), `BACKEND=posix ./build_macos.sh` (headless). The default developer build carries `-DDEBUG`, which is where the coverage check runs.
10. **Every commit message ends with:**
    ```
    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
    ```
11. **Work happens on `master`.** No feature branch, no worktree.
12. **This is port feature work, not an upstream bugfix** — no `upstream:` marks, no REPORTING-GATE ledger rows, with one exception called out in Task 2 (the empty `TargetSystem::Serialize`, which is a spec-named upstream defect getting fixed as a side effect; its mark is specified there).

## File Structure

| File | Role |
|---|---|
| `inc/Base.h` | `FIELD_*` macros, `K_*` kind constants, `SP_*` pool ids, new `Registry` method declarations (methods only — no data members, see constraint 5) |
| `src/SaveV1.cpp` (new) | v1 writer, v1 reader, name table build/resolve, coverage machinery + pin table, `RunSchemaTest`, `RunSchemaLoad`, `RunSaveConvert` |
| `src/Registry.cpp` | version dispatch in `LoadGroup`, v1 branch in `Game::SaveGame`, deferred name resolution call in `Game::LoadGame` |
| `src/Dump.cpp` | deferred name resolution call, `Format:` line prints the file's stamp |
| `src/Wposix.cpp`, `src/Wlibtcod.cpp` | parse `-schematest`, `-schemaload`, `-convert` beside `-dump` |
| `src/RComp.cpp` | duplicate-name rejection at compile time |
| class headers (`inc/Map.h`, `inc/Item.h`, `inc/Creature.h`, `inc/Feature.h`, `inc/Res.h`, `inc/Target.h`, `src/Target.cpp`) | field declarations inside existing `ARCHIVE_CLASS` bodies |
| `tools/check_schema_roundtrip.sh`, `tools/craft_bad_v1_saves.py`, `tools/check_v1_adversarial.sh`, `tools/check_dup_names.sh`, `tools/check_v1_full_roundtrip.sh`, `tools/check_flavor_stability.sh`, `tools/check_convert_guard.sh` (all new) | the checks |
| `docs/SCRIPT-DATA-SEGMENT.md` (new, Task 8) | investigation deliverable |
| `docs/ENGINE-SERIALISATION.md` | updated in Task 11 to describe both formats |

## The archived-class census (verified against source, 2026-08-24)

`grep -rn "ARCHIVE_CLASS" inc src | grep -v define` yields exactly 20 users:

| Class | Declared at | Chain |
|---|---|---|
| `Thing` | `inc/Map.h:663` | `Object` → `Thing` |
| `Map` | `inc/Map.h:492` | `Object` → `Map` |
| `Item` | `inc/Item.h:20` | `Thing` → `Item` |
| `QItem` | `inc/Item.h:256` | `Item` → `QItem` |
| `Food` | `inc/Item.h:279` | `QItem` → `Food` |
| `Corpse` | `inc/Item.h:311` | `Food` → `Corpse` |
| `Container` | `inc/Item.h:339` | `QItem` → `Container` |
| `Weapon` | `inc/Item.h:384` | `QItem` → `Weapon` |
| `Coin` | `inc/Item.h:397` | `Item` → `Coin` |
| `Armour` | `inc/Item.h:423` | `QItem` → `Armour` |
| `Feature` | `inc/Feature.h:13` | `Thing` → `Feature` |
| `Door` | `inc/Feature.h:47` | `Feature` → `Door` |
| `Trap` | `inc/Feature.h:86` | `Feature` → `Trap` |
| `Portal` | `inc/Feature.h:120` | `Feature` → `Portal` |
| `Creature` | `inc/Creature.h:162` | `Thing` + `Magic` → `Creature` (`Magic` has NO data members — verified `inc/Magic.h`) |
| `Character` | `inc/Creature.h:819` | `Creature` → `Character` |
| `Player` | `inc/Creature.h:1124` | `Character` → `Player` |
| `Monster` | `inc/Creature.h:1205` | `Creature` → `Monster` |
| `Module` | `inc/Res.h:813` | `Object` → `Module` |
| `Game` | `inc/Res.h:1066` | `Object` → `Game` |

Phase 1 (Task 1) covers `Thing` and `Item`. The remaining 18 are Tasks 2–6, grouped: Creature (Task 2); Character/Player/Monster (Task 3); Feature/Door/Trap/Portal (Task 4); QItem/Food/Corpse/Container/Weapon/Coin/Armour (Task 5); Module/Game/Map (Task 6). `Object` itself (`inc/Base.h:618`) has no `ARCHIVE_CLASS`; its two members are handled by the record envelope: `Type` is the record's type byte, `myHandle` is the envelope's handle field.

## The wire format (normative for every task)

A v1 save file:

```
fileHeader        96 bytes, exact shape of src/Registry.cpp:44-52, Sig = SIGNATURE (0x1234ABCD)
                  Version[12] = "IS1." + decimal SCHEMA_REV, from SaveSchemaID()
                  ("IS1.0" at Task 6, "IS1.1" after Task 7, "IS1.2" after Task 9;
                  the reader dispatches on the "IS" prefix, v0 files carry "SF" +
                  digest or the old VERSION_STRING)
                  Compression = 1 (RLE payload) or 0 (raw payload; DEBUG builds write raw
                  when INCURSION_V1_RAW=1, so tools can craft mutants). v0 never reads
                  this field (declared and never assigned/tested, per ENGINE-SERIALISATION).
groupHeader       28 bytes, exact shape of src/Registry.cpp:86-95. dataCount = 0 always
                  (v1 has no data-block section; FIELD_STR/FIELD_BLOB write contents inline).
                  groupSize = uncompressed payload size, compSize = compressed size,
                  LastHandle = LastUsedHandle, objCount = record count.
payload           (RLE-compressed through the existing CFile when Compression==1):
    objCount x record
    uint32  SIGNATURE_TWO       separator, as today
    name table:
        uint32  entryCount
        entryCount x entry
```

One record per object:

```
uint8   type        the T_* constant, as today
uint32  handle      the object's myHandle (v0 kept it inside the raw bytes;
                    RegisterObject(o,true) preserves it — src/Registry.cpp:1019)
uint32  length      bytes from the end of this field to the end of the record
  repeated field:
    uint16  tag     stable field number, unique within the class chain; 0 = terminator
    uint8   kind
    ...     payload sized by kind (fixed for K_U8..K_I32/K_RID/K_H;
                    length-prefixed for K_STR/K_BLOB/K_EMBED;
                    count*elemSize+8 for K_ARRAY)
  terminator tag 0 (uint16)
```

Kinds:

```cpp
enum {
  K_U8 = 1, K_I8 = 2, K_U16 = 3, K_I16 = 4, K_U32 = 5, K_I32 = 6,
  K_STR   = 7,   /* uint32 len, len bytes, no NUL */
  K_BLOB  = 8,   /* uint32 len, len bytes */
  K_RID   = 9,   /* uint32 name-table index; 0xFFFFFFFF encodes rID 0 (null) */
  K_H     = 10,  /* uint32; hObj/hData value (signed int stored two's-complement) */
  K_ARRAY = 11,  /* uint32 count, uint32 elemSize, count*elemSize raw bytes */
  K_EMBED = 12   /* uint32 len; a nested field stream with its own tag scope
                    and its own tag-0 terminator */
};
```

The reader's loop: a tag it knows, it stores. A tag it does not know, it skips using `kind` (and the length prefix where the kind has one). A tag it knows and does not meet, it leaves at the value construction gave it — v1 load allocates with `malloc(typeSize(t))` + `memset(0)` + the same placement-new switch `LoadGroup` uses (`src/Registry.cpp:948-990`), so "constructed default" means zero, matching `Object::operator new`'s memset (`inc/Base.h:650-659`). An unknown *kind* value cannot be sized and throws `ECORRUPT`. An unknown record *type* is skipped whole via `length` — same extensibility rule one level up.

**Known tag, unexpected kind: `ECORRUPT`.** A tag the reader implements whose `kind` byte is not the kind the field list declares is corruption, not extension — the file and the binary disagree about a field both claim to know. The reader MUST throw `ECORRUPT`, never skip it and never coerce it. (This rule goes live in earnest at Task 9, where existing tags change kind across a revision bump.)

**Load-direction ordering (normative for every `ARCHIVE_CLASS` body and every `FieldsV1`).** The v1 reader replays `Serialize`; a member's value lands only when its `FIELD_` line runs. So fixup logic and size-dependent field lines MUST run *after* the fields they read. Put load-direction fixups in a trailing `if (!isSave)` block (in `FieldsV1` bodies: after an `r.Loading()` check) below the last field they depend on; save-direction staging (`if (isSave) …`) stays at the top, where v0 always ran it. Replay order is the order of the *lines* in the body — tag numbers are identity only and impose no order.

**Schema revisions (normative).** `SCHEMA_REV` is the decimal after `IS1.` in `Version`, produced by `SaveSchemaID()`. Any change to the meaning of an existing tag or record shape bumps it: Task 7 bumps 0→1 (tag 672 changes `K_BLOB`→`K_EMBED`), Task 9 bumps 1→2 (`MDataSeg` changes `K_BLOB`→row records). The reader MUST reject a revision it does not implement with a clean error naming both revisions — the file's and the binary's — and MUST NOT try to read it. Each bump also updates every harness assertion that names the literal revision string.

Name-table entry:

```
uint8   pool        SP_* pool id (below) — NOT the resource's Type byte, because
                    T_TNPC and T_TCLASS are both 70 (inc/Defines.h:383-384) and the
                    Type byte cannot tell the NPC pool from the Class pool
uint8   moduleSlot  Game::Modules index the rID's top byte named at save time
uint16  ordinal     count of earlier same-pool, same-name resources, declaration order
uint16  nameLen
...     nameLen bytes of the resource's name (module text, no NUL)
```

```cpp
/* Wire pool ids, in the canonical declaration order of inc/Res.h:875-897.
   Append-only forever. */
enum {
  SP_MON = 0, SP_ITM = 1, SP_FEA = 2, SP_EFF = 3, SP_ART = 4, SP_QUE = 5,
  SP_DGN = 6, SP_ROU = 7, SP_NPC = 8, SP_CLA = 9, SP_RAC = 10, SP_DOM = 11,
  SP_GOD = 12, SP_REG = 13, SP_TER = 14, SP_TXT = 15, SP_VAR = 16,
  SP_TEM = 17, SP_FLA = 18, SP_BEV = 19, SP_ENC = 20
};
```

Encoding an `rID` into an entry: `slot = (id >> 24) - 1`; the pool and in-pool index come from the same subtractive walk `Module::__GetResource` does (`src/Res.cpp:102-208`: subtract `szMon`, `szItm`, `szFea`, `szEff`, `szArt`, `szQue`, `szDgn`, `szRou`, `szNPC`, `szCla`, `szRac`, `szDom`, `szGod`, `szReg`, `szTer`, then `szTxt`/`szVar`/`szTem`/`szFla`/`szBev`/`szEnc`); the name is `Modules[slot]->GetText(res->Name)`; the ordinal counts earlier same-name entries in the same pool array by `strcmp`. Resolving an entry: walk the named pool array in `Modules[moduleSlot]`, `strcmp` each name, count matches; the match whose running count equals `ordinal` gives the in-pool index; rebuild `rID = poolBase + index + ((moduleSlot+1) << 24)` where `poolBase` is the sum of the counts of every earlier pool. An ordinal at or past the count of same-named resources aborts the load, naming the entry.

**Deferred resolution.** Records are read before the name table, and the module the names resolve against is reloaded *after* the save group in both load paths (`Game::LoadGame` reloads modules at `src/Registry.cpp:1317-1334`; `RunSaveDump` at `src/Dump.cpp:151-172`). So `V1Rid` on load stores the table index in the `rID` slot and queues the slot's address; a single `SaveV1_ResolveNames()` call after each path's module-reload loop resolves every queued slot, or aborts naming every failure. Nothing may touch a resource field between load and resolve — both call sites sit before any `CalcValues`/report code. (Task 9 defers the memory-row placement to this same point, for the same reason.)

## Tag-range registry (goes verbatim into inc/Base.h as a comment, maintained forever)

```
/* v1 tag ranges. Within a range: a new field takes the next unused number, a
   retired number is never reused, a number never changes. Tags are unique
   within a class CHAIN, so a chain crossing two ranges never collides.
     Thing      1-31        Item      32-63
     QItem     64-79        Food      80-95      Corpse    96-111
     Container 112-127      Weapon   128-143     Coin     144-159
     Armour   160-175       Feature  176-191     Door     192-207
     Trap     208-223       Portal   224-239     Creature 256-383
     Character 384-511      Player   512-639     Monster  640-671
     Map      672-767       Module   768-799     Game     800-899 */
```

---

### Task 1: Phase 1 — wire format, macros, name table, dispatch, coverage check, Thing + Item, adversarial suite

**Files:**
- Modify: `inc/Base.h` (kind/pool enums + tag-range comment above the `ARCHIVE_CLASS` define at `inc/Base.h:686`; new `Registry` method declarations inside `class Registry`, `inc/Base.h:697-777` — methods and statics ONLY, constraint 5)
- Create: `src/SaveV1.cpp`
- Modify: `src/Registry.cpp` (dispatch in `LoadGroup` at :870-874; `SaveV1_ResolveNames()` call after the module loop ending :1334)
- Modify: `src/Dump.cpp` (`SaveV1_ResolveNames()` call after the module loop ending :172)
- Modify: `src/Wposix.cpp` (parse `-schematest <out-dir>` and `-schemaload <file>` beside `-dump`, :550-558) and `src/Wlibtcod.cpp` (same, :500-505)
- Modify: `inc/Map.h` (`Thing` body :663-676; `StatiCollection::FieldsV1` beside :622)
- Modify: `inc/Item.h` (`Item` body :20-23)
- Modify: `src/Base.cpp` (`Array<S,I,D>::FieldsV1` beside `Serialize` at :657-659; `String` needs nothing — `FIELD_STR` handles it)
- Modify: `src/RComp.cpp` (duplicate-name rejection after `CountResources`' first pass, :248)
- Create: `tools/check_schema_roundtrip.sh`, `tools/craft_bad_v1_saves.py`, `tools/check_v1_adversarial.sh`, `tools/check_dup_names.sh`

**Interfaces:**
- Consumes: `Registry::Block` (`src/Registry.cpp:367`), `CFile` (`inc/Term.h:807`), `typeSize` (`src/Registry.cpp:304`), the placement-new switch (`src/Registry.cpp:948-990`), `String::Serialize` (`src/Base.cpp:504`).
- Produces (every later task relies on these exact names):
  - Macros in `inc/Base.h`: `FIELD_U8/I8/U16/I16/U32/I32(tag,m)`, `FIELD_H(tag,m)`, `FIELD_RID(tag,m)`, `FIELD_STR(tag,m)`, `FIELD_BLOB(tag,ptr,sz)`, `FIELD_ARRAY(tag,ptr,elemSize,count)`, `FIELD_OBJ(tag,m)`, `FIELD_EMBED(tag,m)`, `FIELD_SKIP(m)`.
  - `Registry` methods (declared `inc/Base.h`, defined `src/SaveV1.cpp`): `bool V1Active(); void V1Field(uint16,uint8,void*,size_t); void V1Str(uint16,String&); void V1Blob(uint16,void**,size_t); void V1Rid(uint16,rID&); void V1Array(uint16,void*,size_t,uint32); void V1EmbedBegin(uint16 tag, void *member, size_t size); void V1EmbedEnd(); void V1Cover(const void*,size_t); int16 SaveGroupV1(Term&,hObj); int16 LoadGroupV1(Term&,fileHeader&,hObj);`
  - Free functions in `src/SaveV1.cpp`: `void SaveV1_ResolveNames(); const char* SaveSchemaID(); /* "IS1." + SCHEMA_REV: "IS1.0" until Task 7's bump */ bool SaveV1_Raw(); /* DEBUG && INCURSION_V1_RAW=1 */ bool RunSchemaTest(const char *outDir); bool RunSchemaLoad(const char *path);` Callers that write a v1 `fileHeader` set `fh.Compression = SaveV1_Raw() ? 0 : 1` themselves, before the header write; `SaveGroupV1` consults the same helper for the payload, so the decision lives in one function.
  - The `FieldsV1(Registry&)` convention: any member reached by `FIELD_OBJ`/`FIELD_EMBED` implements a NON-VIRTUAL `void FieldsV1(Registry &r)` (non-virtual so no vtable appears or grows — constraint 5) whose body uses the same `FIELD_*` macros (embedded tag scopes start at 1).
  - The pin table `SchemaPin` in `src/SaveV1.cpp` with rows for the `Item` chain.

- [ ] **Step 1: Write the failing round-trip check**

Create `tools/check_schema_roundtrip.sh` (the project idiom: `set -uo pipefail`, a `fail()` collector, exit 0/1 — copy the skeleton of `tools/check_dump_save.sh:22-38`):

```bash
#!/bin/bash
# Round-trip check for the v1 save schema, phase 1 (docs/SAVE-SCHEMA-SPEC.md).
# Drives `incursion-headless -schematest`, which: loads the modules, builds a
# set of Item objects (class Item exactly, via the LoadGroup allocation idiom)
# with real module rIDs in iID/eID/homeID, stati, a name and backRefs; writes
# them as a v1 group; reads the file back into a fresh registry; compares every
# field; writes a second file; and byte-compares the two. DEBUG builds also run
# the coverage check on every record and any finding is fatal.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
FAILED=0; fail() { echo "FAIL: $1"; FAILED=1; }
[ -x ./incursion-headless ] || { echo "FAIL: build first: BACKEND=posix ./build_macos.sh"; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-schema.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# < /dev/null + -timeout: a binary that predates the flag would otherwise start
# an ordinary interactive session and hang (src/Wposix.cpp:549-558); the
# redirect is the tools/check_dump_save.sh:46-47 idiom.
if ! ./incursion-headless -schematest "$WORK" -timeout 120 < /dev/null > "$WORK/out.txt" 2>&1; then
    tail -30 "$WORK/out.txt"
    fail "-schematest exited non-zero"
fi
grep -q "^SCHEMATEST PASS" "$WORK/out.txt" || fail "no 'SCHEMATEST PASS' line"
grep -q "byte-identical" "$WORK/out.txt" || fail "second save was not byte-compared"
if grep -q "SCHEMA COVERAGE" "$WORK/out.txt"; then
    grep "SCHEMA COVERAGE" "$WORK/out.txt"; fail "coverage findings"
fi
[ "$FAILED" -eq 0 ] && { echo "PASS: v1 round trip (Item chain) is exact"; exit 0; }
exit 1
```

- [ ] **Step 2: Run it to verify it fails**

Run: `BACKEND=posix ./build_macos.sh && tools/check_schema_roundtrip.sh`
Expected: FAIL — `-schematest` is an unknown flag, so the binary ignores it and the output has no `SCHEMATEST PASS` line. The run terminates rather than hanging because the script's invocation carries `< /dev/null` and `-timeout` (see the comment in the script; an ordinary session otherwise starts at `src/Wposix.cpp:549-558` and waits on stdin).

- [ ] **Step 3: Macros and enums in inc/Base.h**

Above the `ARCHIVE_CLASS` define (`inc/Base.h:686`), add the `K_*` enum, the `SP_*` enum, and the tag-range comment from the plan header, all verbatim. Then the macros:

```cpp
/* One declaration serves four duties: the v0 save/load path (where the raw
   dump already carries scalars, so scalar macros are no-ops there and the
   STR/BLOB/OBJ macros perform exactly the legacy Serialize/Block calls they
   replace), the v1 write, the v1 read, and the DEBUG coverage map. */
#define FIELD_U8(tag,m)   r.V1Field((tag), K_U8,  &(m), sizeof(m))
#define FIELD_I8(tag,m)   r.V1Field((tag), K_I8,  &(m), sizeof(m))
#define FIELD_U16(tag,m)  r.V1Field((tag), K_U16, &(m), sizeof(m))
#define FIELD_I16(tag,m)  r.V1Field((tag), K_I16, &(m), sizeof(m))
#define FIELD_U32(tag,m)  r.V1Field((tag), K_U32, &(m), sizeof(m))
#define FIELD_I32(tag,m)  r.V1Field((tag), K_I32, &(m), sizeof(m))
#define FIELD_H(tag,m)    r.V1Field((tag), K_H,   &(m), sizeof(m))
#define FIELD_RID(tag,m)  r.V1Rid((tag), (m))
#define FIELD_STR(tag,m)  do { if (r.V1Active()) r.V1Str((tag),(m)); \
                               else (m).Serialize(r); } while (0)
#define FIELD_BLOB(tag,p,sz) do { if (r.V1Active()) r.V1Blob((tag),(void**)&(p),(sz)); \
                                  else r.Block((void**)&(p),(sz)); } while (0)
#define FIELD_ARRAY(tag,p,elem,count) r.V1Array((tag),(p),(elem),(count))
#define FIELD_OBJ(tag,m)  do { if (r.V1Active()) { r.V1EmbedBegin((tag),&(m),sizeof(m)); \
                               (m).FieldsV1(r); r.V1EmbedEnd(); } \
                               else (m).Serialize(r); } while (0)
#define FIELD_EMBED(tag,m) do { if (r.V1Active()) { r.V1EmbedBegin((tag),&(m),sizeof(m)); \
                                (m).FieldsV1(r); r.V1EmbedEnd(); } } while (0)
#define FIELD_SKIP(m)     r.V1Cover(&(m), sizeof(m))
```

`ARCHIVE_CLASS`/`END_ARCHIVE` themselves (`inc/Base.h:686-693`) do NOT change: the generated `Serialize(Registry&, bool)` signature, the base-first call, and the closing brace all stay. The macros are lines *inside* the bodies. Declare the `Registry` methods from the Interfaces block inside `class Registry` — no data members (constraint 5); put the mutable context in file-scope structs in `src/SaveV1.cpp`.

- [ ] **Step 4: The writer, reader, name table, and coverage in src/SaveV1.cpp**

Implement per the wire format section. Key requirements, each one load-bearing:

- `SaveGroupV1(Term &t, hObj hGroup)`: write `fileHeader` is the *caller's* job (as with v0); this writes the `groupHeader` placeholder at `t.Tell()`, opens a `CFile`, sets `saveMode = true` for the walk and clears it after (so `Registry::Saving()`/`Loading()` drive per-direction staging inside `FieldsV1` bodies, which have no `isSave` parameter), iterates `ObjTable` exactly as `SaveGroup` does (`src/Registry.cpp:754-779`) honouring `inGroup(hGroup)`, sets `hCurrent`, and for each object: begin record (type byte, `myHandle`, length placeholder) — the envelope writer calls `V1Cover` on `Object::Type` and `myHandle` here, because the envelope carries them and no `FIELD_` line does, and they must not be absorbed into pad rows — set a "v1 save" flag in the context, call `o->Serialize(*this, true)`, write terminator, backpatch length via `CFile` seek, run the coverage check (DEBUG), call `SaveFailProbe(false, count)` (`src/Registry.cpp:770` precedent — keeps `tools/check_save_fail.sh` meaningful). Then `SIGNATURE_TWO`, then the name table accumulated during the walk (first-use order, so a second save is byte-identical). The payload commits raw when `SaveV1_Raw()` (DEBUG + `INCURSION_V1_RAW=1`), else RLE-compressed. The header is not this function's business in either mode: the contract is exactly the Interfaces signature, `int16 SaveGroupV1(Term&, hObj)`, and the CALLER writes the complete `fileHeader` — `SaveSchemaID()` into `Version`, `fh.Compression = SaveV1_Raw() ? 0 : 1` — before calling, as the Interfaces block states; Tasks 6 and 10 spell that assignment out at their call sites. No `SaveFixupScope` is needed: v1 never parks handles in pointer slots and never mutates the object (the hand-written per-mode fixup lines in bodies still run, which is why `Thing`'s `hm = m ? m->myHandle : 0` keeps working unchanged).
- `LoadGroupV1(Term &t, fileHeader &fh, hObj hGroup)`: mirror `LoadGroup`'s group walk and the `compSize`/`groupSize` range checks verbatim (`src/Registry.cpp:909-920` — same `ECORRUPT` behaviour, same `CFILE_SANE_MAX_SIZE` ceiling). It consults `fh.Compression` for the payload: 0 reads raw bytes, 1 reads RLE through `CFile` as today — the adversarial suite crafts and loads raw-mode files, so the raw branch is load-bearing, not a debug nicety. Per record: read type/handle/length; `T_GAME` overwrites `theGame` (memset `typeSize(T_GAME)` bytes first), others `malloc(typeSize(type))` + `memset` 0; placement-new switch copied from `src/Registry.cpp:948-990` (including the `T_COIN`/`T_STAFF` behaviour as-is — spec risk 3 says v1 must not fix or be blamed for those); index the record's fields (tag → kind + payload pointer) with strict bounds checks (`ECORRUPT` on any overrun or unknown kind); set the object's `myHandle` from the envelope; call `o->Serialize(*this, false)` with the "v1 load" context so each macro pulls its tag; `SanitizeLoadedTargets` for creatures (`src/Registry.cpp:1015-1016`); `RegisterObject(o, true)`. After records: `SIGNATURE_TWO` check, read the name table into the context. Resolution is deferred (see plan header).
- `V1Rid`: save — null `rID` writes index `0xFFFFFFFF`; else intern (pool, slot, ordinal, name) into the table, write the index. Load — store index into the slot, queue the address for `SaveV1_ResolveNames()`. `strcmp` only (constraint 2).
- Coverage (DEBUG only): context holds a byte map sized `o->ObjectSize()` per record write — NEVER `typeSize(Type)`. The two disagree on the purpose-preserved upstream defects (spec risk 3): `typeSize(T_STAFF)` returns `sizeof(Weapon)` (`src/Registry.cpp:335-337`) while the placement-new switch (`src/Registry.cpp:948-990`) has no `case T_STAFF` and constructs a bare `Item`, so a `typeSize`-sized map would report `sizeof(Weapon)-sizeof(Item)` bytes uncovered and the fatal check would fire on any real save containing a staff. `ARCHIVE_CLASS` already generates `ObjectSize()` (`inc/Base.h:689`), which reports the class the object really is. The pin-table lookup follows the same rule: consult the row whose class matches `ObjectSize()`, never `typeSize` — for `T_COIN`, `typeSize`'s default returns `sizeof(Item)` while the switch news a `Coin` (`src/Registry.cpp:971`, `:347-348`), and the row that applies is `Coin`'s. Base pointer is the object being written; every `V1Field/V1Str/V1Blob/V1Rid/V1Array/V1Cover` marks its member's bytes ((char*)&m - (char*)base), erroring on double-cover; an address OUTSIDE the object's range is legal and marks nothing (a field may stage its value in a stack temporary — `TargetSystem::FieldsV1` in Task 2 does). Embeds: `V1EmbedBegin(tag, member, size)` marks the whole `[member, member+size)` range — interior padding of the embedded type included — and while its scope is open, a mark falling inside that range is legal and redundant rather than a double-cover error, so the sub-member macros in `FieldsV1` bodies cost nothing. After `Serialize` returns, compare uncovered ranges against the pin table:

```cpp
struct SchemaPad { uint32 off, len; };
struct SchemaPin { const char *cls; int16 type; size_t size;
                   const SchemaPad *pads; int npads; };
/* One row per archived class. size pins sizeof(Class): a member added or
   removed by upstream moves it and the v1 field list must be revisited ON
   PURPOSE (add the FIELD_/FIELD_SKIP line, re-pin). pads lists the byte
   ranges the compiler leaves between members plus the vptr at offset 0;
   the failing check PRINTS the actual uncovered ranges, so filling a row
   is mechanical. Anything uncovered, double-covered, or outside its pinned
   pad is an Error() naming class, offset and length. */
```

Failure text starts `SCHEMA COVERAGE` (what `check_schema_roundtrip.sh` greps).
- `RunSchemaTest(outDir)`: load modules the way game start does (`Game::LoadModules`); build 4+ `Item` instances via the LoadGroup allocation idiom (`malloc(typeSize(T_RING))` + memset + `new(o) Item(this)` — types in the `T_FIRSTITEM..T_LASTITEM` default branch so the class is exactly `Item`); populate every `Item`/`Thing` field with distinct non-zero values, `iID`/`eID`/`homeID` with real module rIDs (e.g. `ItemID(0)`, `EffectID(3)`, `RegionID(1)` — the same base macros `GetMemoryPtr` uses, `src/Res.cpp:715-742`), a `Named` string, stati via direct `__Stati` population, `backRefs` entries. Registration goes into a LOCAL `Registry` instance on the stack, with `theRegistry` temporarily repointed at it (the `SaveModule` pattern, `src/Registry.cpp:1382-1384`) and explicit `RegisterObject` calls — placement-new constructors register nothing, and this keeps `theGame` and everything else in `MainRegistry` OUT of the test group, which matters because their classes have no field lists until Tasks 2–6. Then `SaveGroupV1` to `outDir/a.sav`; load into a SECOND local registry via the v1 reader + `SaveV1_ResolveNames()`; compare every field by direct accessor and print one line per mismatch; `SaveGroupV1` from the second registry to `outDir/b.sav`; byte-compare a/b and print `byte-identical`; print `SCHEMATEST PASS` and return true only if everything held; restore `theRegistry` on every path.
- `RunSchemaLoad(path)`: open, dispatch, v1-load, resolve, then print one `field <class>.<member>=<value>` line per declared field of every loaded object (mechanically: re-run `Serialize` with a "print" context — or simpler, print the handful of `Thing`/`Item` fields directly; the adversarial checks below grep these lines). Errors go to stderr with the same `Lookup(FileErrors, ...)` texts `-dump` uses (`src/Dump.cpp:131-138`).
- Dispatch: in `Registry::LoadGroup` right after the header read (`src/Registry.cpp:870`), before `SaveFormatMatches`:

```cpp
if (fh.Sig == SIGNATURE && !strncmp(fh.Version, "IS", 2)) {
    if (strncmp(fh.Version, "IS1.", 4)) throw EBADVER;  /* future major */
    return LoadGroupV1(t, fh, hGroup);
}
```

`LoadGroupV1` additionally rejects a `SCHEMA_REV` it does not implement, with a clean error naming the file's revision and the binary's (wire-format §schema revisions) — at this task that means anything other than `0`.

Also extend the save-menu filter in `Game::LoadGame` (`src/Registry.cpp:1254`) to accept an `IS1.` prefix beside `SaveFormatMatches`, and `-schemaload`/`-schematest` parsing in both backends beside `-dump` (`src/Wposix.cpp:550-558`, `src/Wlibtcod.cpp:518-523`).
- `Thing`'s body (`inc/Map.h:663-676`) becomes the spec's example — `Serialize` calls replaced by macros, and the fixups re-seated per the load-direction ordering rule: the save-direction staging stays on top, but `m = oMap(hm)` moves into a trailing `if (!isSave)` block, because on load `hm` has a value only after `FIELD_H(2, hm)` has run — left where v0 had it, `m` would load as `oMap(0)`. Keep the existing upstream comment at `inc/Map.h:664-668` (the `*((long*)&hm)` LP64 note) in place above the staging lines:

```cpp
ARCHIVE_CLASS(Thing,Object,r)
  /* ... the existing inc/Map.h:664-668 LP64 comment stays here ... */
  if (isSave)
    hm = m ? m->myHandle : 0;
  FIELD_SKIP(m);               /* rebuilt from hm, never stored */
  FIELD_H  (1, Next);
  FIELD_H  (2, hm);
  FIELD_I16(3, x);
  FIELD_I16(4, y);
  FIELD_U32(5, Image);
  FIELD_I16(6, Timeout);
  FIELD_I16(7, StoredMovementTimeout);
  FIELD_U32(8, Flags);
  FIELD_STR(9, Named);
  FIELD_OBJ(10, __Stati);
  FIELD_OBJ(11, backRefs);
  if (!isSave)
    m = oMap(hm);              /* load fixup: hm has landed by here */
END_ARCHIVE
```

- `Item`'s body (`inc/Item.h:20-23`): replace `Inscrip.Serialize(r); GenStats.Serialize(r);` with the full member walk of `inc/Item.h:25-41` in declaration order — `FIELD_U16(32, Known)`, `FIELD_I8(33, Plus)`, `FIELD_I8(34, Charges)`, `FIELD_I8(35, DmgType)`, `FIELD_I16(36, GenNum)`, `FIELD_H(37, Parent)`, `FIELD_RID(38, homeID)`, `FIELD_I16(39, Flavor)`, `FIELD_I16(40, cHP)`, `FIELD_I16(41, Age)`, `FIELD_U8(42, swingCount)`, `FIELD_U32(43, Quantity)`, `FIELD_STR(44, Inscrip)`, `FIELD_STR(45, GenStats)`, `FIELD_RID(46, iID)`, `FIELD_RID(47, eID)`, `FIELD_U16(48, IFlags)`.
- `FieldsV1` implementations: `StatiCollection` (beside `inc/Map.h:622` — save `Last`/`Allocated` and per-`Status` embeds with `FIELD_RID` on `Status::eID` and `FIELD_H` on `Status::h`, scalars for the rest; on load rebuild `Idx` and zero `Added`/`Nested`/`Removed`, `ASSERT(Added == NULL)` as the v0 body does — this load fixup goes AFTER the field lines it reads, in a trailing `r.Loading()` block, per the load-direction ordering rule); `Array<S,Initial,Delta>` (beside `src/Base.cpp:657-659` — `K_ARRAY` of `Count` raw elements for POD element types; the template instantiations at `src/Base.cpp:661-679` say which are needed). rID-bearing element types (`TerraRecord.eID`, `Field.eID`) get their own `FieldsV1` in Task 6; Task 1 needs only `Array<hObj,...>` for `backRefs`.
- Duplicate-name rejection in the resource compiler — MEASURE FIRST, then make it fatal. The spec's measurement covered 15 pools, but `CountResources` carries 21 name arrays (`MonNames` through `EncNames`, `src/RComp.cpp:341-442`): `TextNames`, `VarNames`, `TempNames`, `BevNames` and `EncNames` are unmeasured, and one duplicate in any of them turns this task's commit red. So, before wiring the rejection in, re-run the `lib/program.i` parser idiom the spec describes across all 21 pools and record the result. The technical reviewer's measurement, for the implementer to CONFIRM rather than assume: the only non-Flavour same-case duplicate in `lib/` is Terrain `"Summoning Circle"` (`lib/dungeon.irh:1452` and `lib/dungeon.irh:4826`), and the second sits inside `#if 0`, so the compiled stream is expected to pass — the measure step MUST still run. Then: after `CountResources` (`src/RComp.cpp:248`) has filled the per-pool name lists, error out (message naming pool, name, and both positions) on any same-`strcmp` duplicate in every pool EXCEPT Flavour. `stricmp` stays out of it.

- [ ] **Step 5: Run the round-trip check to verify it passes**

Run: `BACKEND=posix ./build_macos.sh && tools/check_schema_roundtrip.sh`
Expected: `PASS: v1 round trip (Item chain) is exact`

- [ ] **Step 6: Prove the coverage check bites**

Temporarily comment out `FIELD_I16(3, x);` in `inc/Map.h`, rebuild headless, run `tools/check_schema_roundtrip.sh`.
Expected: FAIL with a `SCHEMA COVERAGE` line naming `Thing`, the offset of `x`, length 2. Restore the line, rebuild, re-run, expected PASS. (This is the spec's risk-1 mitigation demonstrated live, not assumed.)

- [ ] **Step 7: Write the failing adversarial check**

Create `tools/craft_bad_v1_saves.py` — unlike v0, v1 is parseable by design, so this parses a RAW-mode v1 file (`Compression == 0`, produced under `INCURSION_V1_RAW=1`) and emits one mutant per case, printing `name|path|expected-stderr-substring` lines exactly like `tools/craft_corrupt_saves.py` does (its consumer loop, `tools/check_load_corrupt.sh:107-131`, is the pattern). Cases, mapped one-to-one from spec §Test plan:

1. `truncated_at_record_N` — one file per record boundary, cut immediately before record N's type byte. Expect refusal, stderr containing `Corrupt`.
2. `unknown_tag` — insert a `tag=999, kind=K_U32, payload=0xDEADBEEF` field into the first Item record (fix up record length and groupSize). Expect SUCCESS (exit 0) and every original `field` line still printed by `-schemaload` — the skip rule at work.
3. `deleted_tag` — remove the `tag=6` (`Timeout`) field from the first Item record. Expect SUCCESS and `field Thing.Timeout=0` (the constructed default; `Timeout` is a `Thing` member and tag 6 sits in `Thing`'s range — the record is an Item record, but `-schemaload` labels the field by the class that declares it).
4. `bad_name` — rewrite a name-table entry's name to `No Such Effect Anywhere`. Expect refusal, stderr containing `No Such Effect Anywhere`.
5. `bad_ordinal` — set a name-table entry's ordinal to 250. Expect refusal, stderr naming the entry.
6. `wrong_kind` — change the `kind` byte of a known tag (e.g. `Timeout`'s tag 6, `K_I16`) to `K_U32` without touching anything else. Expect refusal, stderr containing `Corrupt` — the known-tag/unexpected-kind rule from the wire-format section.
7. `truncated_fixed_sizes_at_record_N` — the same cuts as case 1, but with the `groupHeader`'s `compSize` and `groupSize` patched down to the shortened length, so the header range check passes and the PER-RECORD bounds loop must catch the overrun. Expect refusal, stderr containing `Corrupt`. (Case 1 alone never reaches that loop — the header check refuses it first.)

Create `tools/check_v1_adversarial.sh`: build the base file via `INCURSION_V1_RAW=1 ./incursion-headless -schematest "$WORK"`, craft mutants, drive each through `./incursion-headless -schemaload <mutant>` (every headless invocation in this script carries `< /dev/null` and `-timeout`, same reason as step 1's script), assert the expectations above, and assert no mutant ever produces the `SCHEMATEST`/full field dump on a refused file. Skeleton and safety assertions as in `tools/check_load_corrupt.sh` (including the real-`save/`-untouched assertion, :57 and :134-137).

- [ ] **Step 8: Run the adversarial check to verify current failure, then finish the reader until it passes**

Run: `tools/check_v1_adversarial.sh`
Expected first: failures wherever the reader's bounds/abort behaviour is incomplete. Fix the reader (never the test's expectations) until: PASS on all cases.

- [ ] **Step 9: Write and run the duplicate-name compile check**

Create `tools/check_dup_names.sh`: build an `INCURSIONPATH` sandbox the way `tools/dump_save.sh:74-77` does, but with `lib/` COPIED rather than symlinked and `mod/` empty; append a SYNTACTICALLY VALID minimal `Effect` declaration whose name duplicates `"Heartstone"` to the copied `lib/m_items.irh` (copy the shape of an existing minimal Effect — a bare invalid fragment would fail the compile for the wrong reason); run `./incursion -compile main.irc` with `INCURSIONPATH` pointing at the sandbox; expect a non-zero exit AND the rejection's own diagnostic — the specific duplicate-name message from step 4's rejection code, naming the pool and `Heartstone` — not merely any error that echoes the name (an ordinary syntax error would false-pass a looser grep); then run the same compile from a clean sandbox copy and expect success. No tracked file is ever modified.
Run: `./build_macos.sh && tools/check_dup_names.sh`
Expected: PASS both halves.

- [ ] **Step 10: Confirm the v0 world is untouched**

Run each, expecting PASS / identical output:
```
tools/check_dump_save.sh
tools/check_load_corrupt.sh
tools/check_abi.sh
./incursion-headless -dump docs/evidence/inc-upw.13/Furious_Fox.sav >/dev/null 2>&1; echo "exit $?"
```
The last line's exit code must match what it prints on the commit *before* this task (run it there first and note it) — the fixture path's behaviour, whatever it is, must not move. Also assert the stamp did not move (constraint 5): the `Format:` line printed by `tools/dump_save.sh` on a fresh smoke save must be byte-identical before and after this task.

- [ ] **Step 11: Commit**

```bash
git add inc/Base.h src/SaveV1.cpp src/Registry.cpp src/Dump.cpp src/Wposix.cpp src/Wlibtcod.cpp inc/Map.h inc/Item.h src/Base.cpp src/RComp.cpp tools/check_schema_roundtrip.sh tools/craft_bad_v1_saves.py tools/check_v1_adversarial.sh tools/check_dup_names.sh
git commit -m "Add the v1 tagged-record save schema: format, macros, name table, Thing and Item

Phase 1 of docs/SAVE-SCHEMA-SPEC.md. Real saves still write v0; the v1
writer and reader are exercised by -schematest / -schemaload, the
adversarial suite, and the DEBUG coverage check.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Phase 2, group 1 — Creature, with a real TargetSystem field list

**Files:**
- Modify: `inc/Creature.h:162-164` (`Creature` body)
- Modify: `inc/Target.h` (declare `void FieldsV1(Registry &r);` on `TargetSystem`, near :187-201)
- Modify: `src/Target.cpp:1447-1449` (the empty `TargetSystem::Serialize` stays for the v0 path; `FieldsV1` is new, beside it)
- Modify: `src/SaveV1.cpp` (schematest group-2 section; pin rows for `Creature` and a `pending` row for `Monster`)
- Test: `tools/check_schema_roundtrip.sh` (extend)

**Interfaces:**
- Consumes: every macro and method from Task 1, unchanged names.
- Produces: `TargetSystem::FieldsV1(Registry &r)`; the convention that a class group's schematest section constructs instances via the LoadGroup allocation idiom and asserts field-for-field equality after a v1 round trip; the pin-table `pending` mechanism (a row whose `pads` cover the WHOLE range of a not-yet-declared derived class's own members, carrying a comment naming the task that removes it).

- [ ] **Step 1: Extend the round-trip check to fail**

Add to `tools/check_schema_roundtrip.sh` an assertion that `-schematest` output contains `SCHEMATEST GROUP creature PASS`. In `RunSchemaTest`, add a `creature` section that builds a `Monster` (`malloc(typeSize(T_MONSTER))` + memset + `new(o) Monster(this)`), populates every `Creature` member with distinct values — including `mID`/`tmID` with real module rIDs and 3 targets in `ts` of types `TargetEnemy`, `TargetArea`, `TargetItem` — round-trips, and compares.

- [ ] **Step 2: Run to verify it fails**

Run: `BACKEND=posix ./build_macos.sh && tools/check_schema_roundtrip.sh`
Expected: FAIL — coverage reports `Creature`'s members uncovered (no pin row exists yet), and the field comparison finds zeros.

- [ ] **Step 3: Declare Creature's fields and TargetSystem's**

In `inc/Creature.h:162-164`, keep `ts.Serialize(r);` (v0 no-op, unchanged behaviour) and add, from the members at `inc/Creature.h:167-190` in declaration order using the kind table (tags 256+): `FIELD_OBJ` for `ts` (routes to `FieldsV1` on v1), `FIELD_RID` for `mID` and `tmID`, `FIELD_I16` for `PartyID`/`cHP`/`mHP`/`Subdual`/`cFP`/`StateFlags`/`Attr[]` (fixed array → `FIELD_ARRAY(tag, Attr, sizeof(int16), ATTR_LAST)`), `FIELD_I32` for the four mana fields, `FIELD_I8`/`FIELD_U8` for the small scalars, and `FIELD_SKIP` for every precalc that is derived state (the range caches `TremorRange..NatureSight` may be stored OR skipped — decide by one rule: if `CalcValues()`/`CalcVision()` rebuilds it on load, `FIELD_SKIP`; otherwise store it. `LastMoveDir` is a `Dir` enum — store as `FIELD_I8` with a cast through a temporary if `sizeof(Dir) != 1`; check `sizeof` first and match the kind to the real width). Statics are not instance members and need nothing. Then grep-audit: `grep -n "rID\|hObj" inc/Creature.h | sed -n '1,40p'` — every hit inside `Creature`'s own member block (:167-190) must appear as a `FIELD_RID`/`FIELD_H` line or a `FIELD_SKIP` with a one-line reason. Ordering audit (wire-format §load-direction ordering): move every load-direction fixup in this group's bodies below the fields it reads; Player's `if (!isSave) MyTerm = T1;` is order-independent and stays.

`TargetSystem::FieldsV1` in `src/Target.cpp` (this is spec risk 2 — the empty `Serialize` at `src/Target.cpp:1447-1449` was correct only by luck):

```cpp
/* upstream: TargetSystem::Serialize above is empty, and was correct only
   because v0 dumps the embedding Creature raw. The v1 field list below is
   the real one. Evidence: Traced (docs/ENGINE-SERIALISATION.md, "Whatever a
   Serialize body omits"). Tracking: the save-schema work, docs/
   SAVE-SCHEMA-SPEC.md risk 2. Not sent. */
void TargetSystem::FieldsV1(Registry &r)
{
  FIELD_U8(1, tCount);
  FIELD_U8(2, shouldRetarget);   /* bool; static_assert(sizeof(bool)==1) first */
  for (int i = 0; i < NUM_TARGETS; i++) {
    /* One embed per slot, tag 3+i. The union travels as two u32 words,
       which covers every arm (inc/Target.h:166-177: max 8 bytes, and the
       first word is the handle in both handle-bearing arms). memcpy, never
       a type-punned cast. */
    uint32 w0 = 0, w1 = 0;
    if (r.Saving()) memcpy(&w0, &t[i].data, 4), memcpy(&w1, ((char*)&t[i].data)+4, 4);
    r.V1EmbedBegin(3 + i, &t[i], sizeof(t[i]));
    FIELD_I32(1, t[i].type);     /* TargetType: verify sizeof(TargetType)==4,
                                    else size the kind to the measured width */
    FIELD_U16(2, t[i].priority);
    FIELD_U16(3, t[i].vis);
    FIELD_I32(4, t[i].why);      /* TargetWhy: same width check */
    FIELD_U32(5, w0);
    FIELD_U32(6, w1);
    FIELD_SKIP(t[i].data);       /* the union travels as w0/w1 above */
    r.V1EmbedEnd();
    if (r.Loading()) memcpy(&t[i].data, &w0, 4), memcpy(((char*)&t[i].data)+4, &w1, 4);
  }
}
```

The `w0`/`w1` temporaries live outside the object, so they escape the coverage map by address; the `FIELD_SKIP(t[i].data)` line in the block covers the union explicitly (skip = covered-not-written-directly; under the embed's range mark it is redundant but states the intent), and the enum fields cover their own bytes. The embed's `[&t[i], &t[i]+sizeof(Target))` range mark also covers any padding `sizeof(Target)` leaves, so no pin pads are needed for it. The `r.Loading()` memcpy sits AFTER `V1EmbedEnd()` and complies with the load-direction ordering rule: `w0`/`w1` land inside the embed, before the memcpy reads them.

Pin rows: `Creature` (fill from the coverage report), and a `pending` row for `Monster` covering `Monster`'s own-member range with the comment `/* pending: Task 3 declares these */`.

- [ ] **Step 4: Run to verify it passes**

Run: `tools/check_schema_roundtrip.sh` then `tools/check_v1_adversarial.sh` and `tools/check_dump_save.sh`
Expected: all PASS (the last two prove the v0 world and phase-1 behaviour are still intact).

- [ ] **Step 5: Commit**

```bash
git add inc/Creature.h inc/Target.h src/Target.cpp src/SaveV1.cpp tools/check_schema_roundtrip.sh
git commit -m "Declare v1 fields for Creature, including a real TargetSystem list

Phase 2 group 1 of docs/SAVE-SCHEMA-SPEC.md. The empty
TargetSystem::Serialize stays for the v0 path; v1 records every target
slot explicitly (spec risk 2).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Phase 2, group 2 — Character, Player, Monster

**Files:**
- Modify: `inc/Creature.h:819-820` (`Character`), `:1124-1130` (`Player`), `:1205-1206` (`Monster`)
- Modify: `src/SaveV1.cpp` (schematest sections; pin rows; delete the `Monster` pending row)
- Test: `tools/check_schema_roundtrip.sh` (extend)

**Interfaces:**
- Consumes: Task 1 macros; Task 2's schematest-section and pending-row conventions.
- Produces: pin rows for `Character`, `Player`, `Monster`; nothing new for later tasks.

- [ ] **Step 1: Extend the round-trip check to fail**

Add `SCHEMATEST GROUP character PASS` to the script's expectations. In `RunSchemaTest`, build a `Player` and a `Monster` via the allocation idiom, populate a representative slice of each class's own members — for `Player` that MUST include at least one entry in each rID-bearing member the grep in step 3 finds (gods, classes, races are the renumbering victims from the spec's Why section) — round-trip, compare.

- [ ] **Step 2: Run to verify it fails**

Run: `BACKEND=posix ./build_macos.sh && tools/check_schema_roundtrip.sh`
Expected: FAIL — coverage names `Character`'s (and `Player`'s, `Monster`'s) uncovered members.

- [ ] **Step 3: Declare the three field lists**

For each class: open `inc/Creature.h`, walk the class's own member declarations top to bottom, write one `FIELD_` line per member in declaration order using the kind table (Character tags 384+, Player 512+, Monster 640+), `FIELD_SKIP` for derived/rebuilt state with a one-line reason each. Do NOT transcribe lists from this plan — the header is the source of truth and the coverage check is the completeness proof. Hard requirements:

- `Player`'s existing body lines stay: `if (!isSave) MyTerm = T1;` (the fixup, `inc/Creature.h:1125-1126`), and `Journal`, `JournalInfo.bestItem`, `JournalInfo.bestMonster` convert from `.Serialize(r)` calls to `FIELD_STR` lines (`inc/Creature.h:1127-1129`). `MyTerm` gets `FIELD_SKIP`. `JournalInfo`'s remaining members get an `FIELD_EMBED` with a `JournalInfoType::FieldsV1` (`inc/Creature.h:847+`) or per-member fields — executor's choice, coverage arbitrates.
- rID audit per class: `grep -n "rID" inc/Creature.h` — every hit inside the class's member block becomes `FIELD_RID` (arrays of rID — e.g. class/race/god arrays — get per-element `FIELD_RID` inside an embed, NOT `FIELD_ARRAY`, because `K_ARRAY` payloads bypass the name table).
- hObj audit likewise: every handle member is `FIELD_H` (handles survive as numbers; `RegisterObject(o,true)` keeps identity, `src/Registry.cpp:1019`).
- `Monster`: `Inv` is `FIELD_H`, `BuffCount`/`FoilCount` `FIELD_I8`, `Recent[6]` `FIELD_ARRAY(…, sizeof(uint8), 6)`; statics (`Acts`, `Effs`, etc., `inc/Creature.h:1143-1152`) take nothing. Remove the pending pin row; add real rows for all three classes.
- Ordering audit (wire-format §load-direction ordering): move every load-direction fixup in this group's bodies below the fields it reads; Player's `if (!isSave) MyTerm = T1;` is order-independent and stays.

- [ ] **Step 4: Run to verify it passes**

Run: `tools/check_schema_roundtrip.sh && tools/check_v1_adversarial.sh && tools/check_dump_save.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add inc/Creature.h src/SaveV1.cpp tools/check_schema_roundtrip.sh
git commit -m "Declare v1 fields for Character, Player and Monster

Phase 2 group 2 of docs/SAVE-SCHEMA-SPEC.md.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Phase 2, group 3 — Feature, Door, Trap, Portal

**Files:**
- Modify: `inc/Feature.h:13-14` (`Feature`), `:47-48` (`Door`), `:86-87` (`Trap`), `:120-121` (`Portal`)
- Modify: `src/SaveV1.cpp` (schematest section; pin rows)
- Test: `tools/check_schema_roundtrip.sh` (extend)

**Interfaces:**
- Consumes: Task 1 macros; Task 2 conventions.
- Produces: pin rows for the four feature classes.

- [ ] **Step 1: Extend the round-trip check to fail**

Add `SCHEMATEST GROUP feature PASS`. Build one of each of `Feature`/`Door`/`Trap`/`Portal` via the allocation idiom (types `T_FEATURE`/`T_DOOR`/`T_TRAP`/`T_PORTAL`), populate `fID`/`tID` with real module rIDs, `cHP`/`mHP`/`MoveMod`/`DoorFlags`/`SecretSavedGlyph`/`TrapFlags` with distinct values, round-trip, compare.

- [ ] **Step 2: Run to verify it fails**

Run: `BACKEND=posix ./build_macos.sh && tools/check_schema_roundtrip.sh`
Expected: FAIL with coverage findings on all four classes.

- [ ] **Step 3: Declare the four field lists**

All four bodies are empty today (`ARCHIVE_CLASS`…`END_ARCHIVE` with nothing between). Members, from the header (verify against `inc/Feature.h` while writing, per-class tags from the range registry): `Feature` (176+): `cHP`, `mHP` (`FIELD_I16`), `fID` (`FIELD_RID`), `MoveMod` (`FIELD_I8`). `Door` (192+): `DoorFlags` (`FIELD_I8`), `SecretSavedGlyph` (`FIELD_U32` — `Glyph` is `uint32`, `inc/Defines.h:57`). `Trap` (208+): `TrapFlags` (`FIELD_U8`), `tID` (`FIELD_RID`). `Portal` (224+): no own members — body gains nothing, but a pin row (size only, no pads beyond inherited) still lands so upstream additions get caught. Add the four pin rows. Ordering audit (wire-format §load-direction ordering): move every load-direction fixup in this group's bodies below the fields it reads; Player's `if (!isSave) MyTerm = T1;` is order-independent and stays.

- [ ] **Step 4: Run to verify it passes**

Run: `tools/check_schema_roundtrip.sh && tools/check_v1_adversarial.sh && tools/check_dump_save.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add inc/Feature.h src/SaveV1.cpp tools/check_schema_roundtrip.sh
git commit -m "Declare v1 fields for the four Feature kinds

Phase 2 group 3 of docs/SAVE-SCHEMA-SPEC.md.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Phase 2, group 4 — QItem, Food, Corpse, Container, Weapon, Coin, Armour

**Files:**
- Modify: `inc/Item.h:256-257`, `:279-280`, `:311-312`, `:339-340`, `:384-385`, `:397-398`, `:423-424`
- Modify: `src/SaveV1.cpp` (schematest section; pin rows)
- Test: `tools/check_schema_roundtrip.sh` (extend)

**Interfaces:**
- Consumes: Task 1 macros; Task 2 conventions.
- Produces: pin rows for the seven item classes. (The spec's phase list says "six item kinds"; the census above shows seven `ARCHIVE_CLASS` users below `Item` — `QItem` is the seventh. All seven are done here so the census, the digest list and this plan agree.)

- [ ] **Step 1: Extend the round-trip check to fail**

Add `SCHEMATEST GROUP items PASS`. Build one instance per class via the allocation idiom (`T_TOOL`→`Item` is already covered; use `T_FOOD`→`Food`, `T_CORPSE`→`Corpse`, `T_CHEST`→`Container`, `T_WEAPON`→`Weapon`, `T_COIN`→`Coin` — note `LoadGroup` placement-news `Coin` for `T_COIN` while `typeSize` sizes it as `Item` (`src/Registry.cpp:971`, `:347-348`); mirror exactly what the v1 reader will do, which mirrors v0, spec risk 3 — `T_ARMOUR`→`Armour`, and a `QItem`-typed instance via `T_SCROLL` if `typeSize`'s default maps it to `Item`: check first; if no T_ constant placement-news a bare `QItem`, exercise `QItem`'s fields through `Food`). Populate `mID` (Corpse) with a real module rID; round-trip; compare.

- [ ] **Step 2: Run to verify it fails**

Run: `BACKEND=posix ./build_macos.sh && tools/check_schema_roundtrip.sh`
Expected: FAIL with coverage findings.

- [ ] **Step 3: Declare the seven field lists**

Per class, from `inc/Item.h`, own members only, tags from the range registry: `QItem` (64+): `Qualities[8]` (`FIELD_ARRAY(64, Qualities, sizeof(int8), 8)`), `KnownQualities` (`FIELD_U8`). `Food` (80+): `Eaten` (`FIELD_I16`). `Corpse` (96+): `mID` (`FIELD_RID`), `TurnCreated` (`FIELD_U32`), `LastDiseaseDCCheck` (`FIELD_I16`). `Container` (112+): `Contents` (`FIELD_H`). `Weapon` (128+): `Bane` (`FIELD_I16`). `Coin` (144+): none — pin row only. `Armour` (160+): none — pin row only. Verify each against the header while writing; the coverage check arbitrates completeness, not this paragraph. Add seven pin rows. Ordering audit (wire-format §load-direction ordering): move every load-direction fixup in this group's bodies below the fields it reads; Player's `if (!isSave) MyTerm = T1;` is order-independent and stays.

- [ ] **Step 4: Run to verify it passes**

Run: `tools/check_schema_roundtrip.sh && tools/check_v1_adversarial.sh && tools/check_dump_save.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add inc/Item.h src/SaveV1.cpp tools/check_schema_roundtrip.sh
git commit -m "Declare v1 fields for the item classes below Item

Phase 2 group 4 of docs/SAVE-SCHEMA-SPEC.md.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Phase 2, group 5 — Module, Game, Map; flip real saves to v1; full round trip; first size measurement

**Files:**
- Modify: `inc/Res.h:813-848` (`Module`), `:1066-1077` (`Game`); `inc/Map.h:492-499` (`Map`)
- Modify: `src/Registry.cpp` (`Game::SaveGame` :1202-1214 writes v1)
- Modify: `src/Dump.cpp:186` (`Format:` prints the FILE's `fh.Version`, not the binary's `SaveFormatID()`)
- Modify: `src/SaveV1.cpp` (pin rows; `LimboEntry`/`ModuleRecord`/`Field`/`MTerrain`/`TerraRecord` `FieldsV1` where rIDs demand it)
- Modify: `tools/check_dump_save.sh:91-92` (the `Format:` regex — see step 4) and `tools/check_save_fail.sh` (its staged-failure AT list, if it stages a data-block failure — see step 4)
- Create: `tools/check_v1_full_roundtrip.sh` (and `tools/keys/loadsave.keys` if no existing key script loads-then-saves)
- Test: `tools/check_v1_full_roundtrip.sh` (new), plus the whole existing suite

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: real saves are v1 from this commit on; `tools/check_v1_full_roundtrip.sh` (later tasks re-run it verbatim); the measured v0-vs-v1 size numbers (recorded in the commit message and re-recorded in docs in Task 11).

- [ ] **Step 1: Write the failing full-save round-trip check**

Create `tools/check_v1_full_roundtrip.sh`, modelled on `tools/check_dump_save.sh:22-60`:
1. Generate a deterministic save: `INCURSION_RUN_DIR="$WORK/run" ./tools/headless.sh tools/keys/smoke.keys 1` (seed 1 + smoke.keys is the established deterministic pair).
2. Assert the file's `Version` field reads `IS1.0`: `dd if="$SAVE" bs=1 skip=4 count=5 2>/dev/null` equals `IS1.0`.
3. `tools/dump_save.sh "$SAVE" > dump1.txt` — assert the same exact content lines `check_dump_save.sh:87-94` asserts (Varag the Deathbringer, 42/42), proving a v1 save reloads to the same character.
4. Save-load-save byte equality: run a second scripted session that LOADS the save and immediately saves (`tools/keys/` gains a tiny `loadsave.keys` if none fits; the load menu is deterministic with one save present), then `cmp save1 save2`. Byte-for-byte equality is the spec's "real test" and is only possible under v1 (v0 never assigns padding — ENGINE-SERIALISATION invariant 2).
5. Size measurement (spec risk 6 — measure, never assume): print `v1=<bytes>` always, and `v0=<bytes> delta=<percent>` when the caller passes `V0_BASELINE_BYTES=<n>` in the environment. The baseline number comes from this task's step 2 run, where the binary still writes v0 and the script prints the save's size on its way to the expected failure. No pass/fail threshold; the numbers are reported, judged in step 4, and carried to Task 11.

- [ ] **Step 2: Run to verify it fails (and capture the v0 baseline size)**

Run: `BACKEND=posix ./build_macos.sh && tools/check_v1_full_roundtrip.sh`
Expected: FAIL at the `IS1.0` assertion (saves are still v0). Record the v0 save's byte size printed by the script for the size comparison.

- [ ] **Step 3: Declare Module, Game, Map fields and flip the writer**

- `Module` (`inc/Res.h:813-848`, tags 768+): keep the cache memsets and the `QTextSeg` inversion lines exactly as they are (they are per-mode fixups, both paths need them). Convert each `r.Block((void**)(&QMon), …)` line (:820-844) to `FIELD_BLOB(tag, QMon, sizeof(TMonster)*szMon)` etc. This field list is UNTESTED BY DESIGN, and stays anyway — one honest sentence for the record: no check in this plan ever produces a `T_MODULE` v1 record, because modules never take the v1 path (spec non-goal 1; `SaveModule` untouched), `-schematest` uses a local registry, and the full round trip saves MainRegistry group 0, which holds no `Module` (`ResourceRegistry` holds them). The list is kept for two reasons that survive that: `LoadGroupV1`'s placement-new switch knows `T_MODULE`, so a crafted v1 file can present one, and the body must then replay safely under the macro set instead of running raw `r.Block` calls in a v1 context — `FIELD_BLOB` inlines the blocks so such a record loses nothing; and the pin row still catches upstream member changes. `Annotations`/`Symbols` `.Serialize(r)` calls become `FIELD_OBJ`. Scalar members (`Name`, `FName` are `hText` ints, `Slot`, the 21 `sz*` counts) each get a `FIELD_` line; `GetResourceCache`/`GetResourceIndex` get `FIELD_SKIP` (rebuilt by the memsets).
- `Game` (`inc/Res.h:1066-1077`, tags 800+): `DungeonLevels[i]` arrays convert to per-dungeon `FIELD_BLOB(tag+i, DungeonLevels[i], sizeof(hObj)*(DungeonSize[i]+1))` guarded exactly as today; `MDataSeg[i]` STAYS `FIELD_BLOB` in this task (Task 9 replaces it — the raw block is v0-equivalent, not worse); `Limbo`/`ModFiles`/`SaveFile` convert to `FIELD_OBJ`/`FIELD_STR`; then one `FIELD_` line per scalar member of the class body (`Day`, `Turn`, `m[4]`/`p[4]` per-element `FIELD_H`, `Timestopper`, flags, `Difficulty`, `DungeonID[]` per-element `FIELD_RID` — dungeon ids are resources and were among the renumbering victims — `DungeonSize[]`, `FindCache`+`szFindCache` `FIELD_SKIP` (cache), the `cc*` counters and `VM` per their nature: `VM` is `VMachine` — read its definition before deciding; if v0 relied on the raw dump to carry live VM state across saves, it gets an `FIELD_EMBED` with a `FieldsV1`; if it is rebuilt, `FIELD_SKIP` with the reason). `LimboEntry` and `ModuleRecord` get `FieldsV1` (grep both structs for `rID` — any hit is `FIELD_RID`).
- `Map` (`inc/Map.h:492-499`, tags 672+): `Grid` stays a raw `FIELD_BLOB(672, Grid, sizeof(LocationInfo)*sizeX*sizeY)` in THIS task (Task 7 packs it). Ordering requirement (wire-format §load-direction ordering): the `FIELD_` lines for `sizeX` and `sizeY` — and for any other member a later line's size expression reads — MUST sit ABOVE the tag-672 grid line. On load the grid line evaluates `sizeX*sizeY` when it runs, and replay order is LINE order, not tag order, so with the grid line first those sizes would still be 0. `Things`/`Fields`/`TerraXY`/`TorchList` convert to `FIELD_OBJ` (with `Field::FieldsV1` carrying `FIELD_RID(1, eID)` per element, and `TerraXY`'s `MTerrain` as POD array); `TerraList` gets a per-element embed whose `FieldsV1` carries `FIELD_RID` for `TerraRecord.eID` and `FIELD_H` for `Creator` (spec §map grid: "`TerraList` … gets `FIELD_RID` treatment per element"); every scalar member of `Map`'s body gets its `FIELD_` line (walk the header; coverage arbitrates).
- Flip: in `Game::SaveGame` (`src/Registry.cpp:1206`, :1212), write `strcpy(fh.Version, SaveSchemaID())` AND `fh.Compression = SaveV1_Raw() ? 0 : 1;` — the `memset(&fh,0,sizeof(fh))` at `src/Registry.cpp:1205` otherwise leaves `Compression` claiming raw while the payload is RLE — then call `theRegistry->SaveGroupV1(*T1, 0)` in place of `SaveGroup(*T1, 0, false, true)` (the caller-writes-the-complete-header contract from Task 1).
- Ordering audit (wire-format §load-direction ordering): move every load-direction fixup in this group's bodies below the fields it reads; Player's `if (!isSave) MyTerm = T1;` is order-independent and stays.
- `src/Dump.cpp:186`: print the loaded file's `fh.Version` (thread it through or re-read the first 16 bytes) so the dump names the FILE's format.
- Pin rows for `Module`, `Game`, `Map`.

- [ ] **Step 4: Run everything and fix the directly broken assertions**

Run, in order, expecting PASS after minimal updates listed:
```
tools/check_schema_roundtrip.sh
tools/check_v1_adversarial.sh
tools/check_v1_full_roundtrip.sh
tools/check_dump_save.sh        # update :91-92 — Format: regex becomes ^Format:    IS1\.0$
tools/check_load_corrupt.sh     # header offsets unchanged (same fileHeader/groupHeader), RLE unchanged; expect PASS as-is — if an expected-stderr substring differs, fix LoadGroupV1's error text, not the script
tools/check_save_fail.sh        # SaveGroupV1 carries SaveFailProbe; if the script stages a data-block failure (AT values with the 'true' flag), that stage no longer exists under v1 — adjust the AT list in the script with a comment, keep the object-stage cases
tools/check_headless.sh
tools/check_dup_names.sh
tools/check_abi.sh
```
Then the module-path soak (spec live check: "the module path is untouched"): `tools/soak.sh 1 87655 tools/keys/explore.keys` — expect the session report with no new error classes versus a pre-task run of the same seed.
Then the stamp guard (constraint 5): `./incursion-headless -dump docs/evidence/inc-upw.13/Furious_Fox.sav; echo $?` — same behaviour as recorded in Task 1 step 10.
Record the `v0=… v1=… delta=…` line from `check_v1_full_roundtrip.sh`. Spec expects under 5 percent; if it is over, STOP and report to Brian before committing — do not silently accept it.

- [ ] **Step 5: Commit**

```bash
git add inc/Res.h inc/Map.h src/Registry.cpp src/Dump.cpp src/SaveV1.cpp tools/check_dump_save.sh tools/check_save_fail.sh tools/check_v1_full_roundtrip.sh tools/keys
git commit -m "Declare v1 fields for Module, Game and Map, and write real saves as v1

Phase 2 group 5 of docs/SAVE-SCHEMA-SPEC.md. Save-load-save is now
byte-identical. Measured size: v0=<N> bytes, v1=<M> bytes (<P>%).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
(Replace `<N>/<M>/<P>` with the measured numbers — they are the risk-6 record.)

---

### Task 7: Phase 3 — the packed LocationInfo grid

**Files:**
- Modify: `inc/Map.h` (grid field in `Map`'s body :492-499 area; the packed-layout comment + `static_assert` beside `LocationInfo` :33-57)
- Modify: `src/SaveV1.cpp` (pack/unpack loop; grid-record header; mismatch abort)
- Modify: `tools/craft_bad_v1_saves.py`, `tools/check_v1_adversarial.sh` (the `grid_mismatch` case); `tools/check_v1_full_roundtrip.sh`, `tools/check_dump_save.sh` (literal revision strings → `IS1.1`, per the bump in step 3)
- Test: `tools/check_v1_adversarial.sh`, `tools/check_v1_full_roundtrip.sh`

**Interfaces:**
- Consumes: Task 6's `Map` field list and full-roundtrip check.
- Produces: the packed tile layout below (append-only, like tags).

- [ ] **Step 1: Extend the adversarial check to fail**

Add to `tools/craft_bad_v1_saves.py` a `grid_mismatch` case: locate the grid embed in a raw-mode full save (crafting now targets a real save produced under `INCURSION_V1_RAW=1` via a smoke session, not the schematest file), overwrite its `sizeX` with `sizeX+1`, fix lengths. `tools/check_v1_adversarial.sh` drives it through `tools/dump_save.sh` expecting refusal with stderr containing `grid`.

- [ ] **Step 2: Run to verify it fails**

Run: `tools/check_v1_adversarial.sh`
Expected: FAIL — the crafter cannot find a grid record yet (the grid is still one anonymous blob), which is the point.

- [ ] **Step 3: Implement the packed grid**

The grid MUST NOT be written field-by-field (an 80x100 map would emit ~120,000 field records — spec §map grid). Replace `Map`'s `FIELD_BLOB(672, Grid, …)` line with `if (r.V1Active()) { r.V1EmbedBegin(672, &Grid, sizeof(Grid)); GridFieldsV1(r); r.V1EmbedEnd(); } else r.Block((void**)&Grid, sizeof(LocationInfo)*sizeX*sizeY);` where `void Map::GridFieldsV1(Registry &r)` is a new NON-virtual method (declared in `inc/Map.h`, defined in `src/SaveV1.cpp`) holding the pack/unpack loops. (`Grid` is a pointer member; the embed covers the pointer slot, and the pointed-to storage travels as the K_BLOBs below. The line keeps its Task 6 position BELOW the `sizeX`/`sizeY` field lines.) The grid record:

```
tag 672, K_EMBED:
  1: K_I16 sizeX      2: K_I16 sizeY     3: K_U8 elemSize (= 8)
  4: K_BLOB packed    sizeX*sizeY*8 bytes — the bitfield image, port-defined
  5: K_BLOB glyphs    sizeX*sizeY*4 bytes — LocationInfo::Glyph
  6: K_BLOB memory    sizeX*sizeY*4 bytes — LocationInfo::Memory
  7: K_BLOB contents  sizeX*sizeY*4 bytes — LocationInfo::Contents (hObj)
```

Packed element, written beside `LocationInfo` (`inc/Map.h:33-57`) with this exact comment-and-assert discipline:

```cpp
/* v1 packed tile (docs/SAVE-SCHEMA-SPEC.md §map grid). 8 bytes, fixed:
   byte 0: Region        byte 1: Terrain     (8-bit TerraList indices)
   bytes 2-3, little-endian, bit 0 first, DECLARATION ORDER of the flag
   bitfields: Opaque, Obscure, Lit, Bright, Solid, Shade, hasField, Dark,
   mLight, mTerrain, cOpaque, Special, isWall, isVault, isSkylight, mObscure
   bytes 4-5: Visibility (16 bits)   bytes 6-7: reserved, write 0
   Glyph, Memory and Contents travel as sibling blobs in the grid record;
   they are not part of this element. Append new flags to the reserved
   bytes; never renumber a bit. */
static_assert(sizeof(LocationInfo) == 20,
    "LocationInfo changed size: a member was added, removed or resized. "
    "Extend the packed layout into the reserved bytes and re-verify the "
    "pack/unpack loops deliberately.");
static_assert(offsetof(LocationInfo, Glyph) == 0 &&
              offsetof(LocationInfo, Memory) == 12 &&
              offsetof(LocationInfo, Contents) == 16,
    "LocationInfo members moved: re-verify the packed layout and the "
    "pack/unpack loops.");
```

The 20 and the offsets are measured, not guessed (verified 2026-08-24 with a replica compile on this toolchain): `Glyph` `uint32` at offset 0, then one full 32-bit unit of bitfields (`Region` 8 bits + `Terrain` 8 bits + the 16 flag bits), then `Visibility` (16 bits) in a second unit, then `Memory` at 12 and `Contents` (`hObj`) at 16 — `inc/Map.h:33-57`.

Alongside the asserts, a DEBUG probe runs once (first grid write): fill one `LocationInfo` with all-ones in every declared field (memset it to 0 first, then assign each field its all-ones value — the assignment list lives beside the pack loop and is maintained with it), pack it, unpack into a zeroed second tile, and `memcmp` the two — any field the pack or the unpack loop drops, truncates or mis-orders fails the probe immediately, and a flag added to the struct and to the fill list but not to both loops fails it the same way. A `Fatal()` on mismatch, DEBUG builds only.

One hand-written pack loop and one unpack loop in `src/SaveV1.cpp`, reading/writing the bitfields BY NAME (never memcpy of the bitfield block — the compiler owns that layout, which is the defect being removed). On load, the cross-check compares the embed's own fields 1/2 against `Map::sizeX`/`sizeY` as ALREADY LANDED by the field lines above the grid line (Task 6's ordering requirement guarantees they have values by the time the embed runs); a disagreement, or `elemSize != 8`, aborts with `ECORRUPT` after an stderr line containing `grid`. For v1 files, the guards on `LocationInfo` are exactly the asserts and the probe above — `SaveLayoutDigest` does not gate the v1 path.

Also in this step, the revision bump (wire-format §schema revisions): tag 672 changes meaning (`K_BLOB`→`K_EMBED`), so `SaveSchemaID()` becomes `"IS1.1"`, `LoadGroupV1` rejects any revision it does not implement with a clean error naming the file's revision and the binary's, and every harness assertion naming the literal revision updates — `tools/check_v1_full_roundtrip.sh`'s `IS1.0` byte check and `tools/check_dump_save.sh`'s `Format:` regex become `IS1.1`.

- [ ] **Step 4: Run to verify it passes**

Run: `tools/check_v1_adversarial.sh && tools/check_v1_full_roundtrip.sh && tools/check_schema_roundtrip.sh && tools/check_dump_save.sh`
Expected: all PASS, including byte-identical save-load-save with the packed grid.

- [ ] **Step 5: Commit**

```bash
git add inc/Map.h src/SaveV1.cpp tools/craft_bad_v1_saves.py tools/check_v1_adversarial.sh tools/check_v1_full_roundtrip.sh tools/check_dump_save.sh
git commit -m "Pack the map grid into a port-defined 8-byte tile layout

Phase 3 of docs/SAVE-SCHEMA-SPEC.md. No compiler-chosen bitfield order
reaches the file; a grid/size mismatch aborts the load.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Phase 4, first task — the script-data-segment investigation

**Files:**
- Create: `docs/SCRIPT-DATA-SEGMENT.md`
- No tracked source file changes. Diagnostics happen in the scratch directory.

**Interfaces:**
- Consumes: nothing from other tasks (pure investigation; spec says it BLOCKS the rest of phase 4). The spec contradicts itself on timing — "It MUST be investigated before phase 2" (§resource memory segment) versus "the first task of phase 4" (§Phases); this plan resolves it to phase 4, the reading that makes sense, since nothing before Task 9 touches the segment.
- Produces: `docs/SCRIPT-DATA-SEGMENT.md`, whose "Verdict" section Task 9 reads before writing a line of code.

- [ ] **Step 1: Frame the questions the note must answer**

The front of each `MDataSeg[i]` block (`inc/Res.h:1096-1097`, written raw at `inc/Res.h:1071-1073`) is `szDataSeg` bytes of compiled script state, laid out by the resource compiler; the memory rows follow it (`Module::GetMemoryPtr`, `src/Res.cpp:711-754`). The note MUST answer, with evidence tier marked per claim (Observed / Traced / Reasoned, the project's ledger convention):
1. What writes the script data segment and when (trace from `szDataSeg`'s assignments in `src/RComp.cpp` and the VM's reads in `src/VMachine`/`src/Res.cpp`).
2. Is its LENGTH module-build-dependent (does adding one Effect move `szDataSeg`)? Measured: build the module twice, once at HEAD and once with a scratch Effect appended (the `check_dup_names.sh` sandbox technique), and compare the two `szDataSeg` values — observed numbers in the note.
3. Is its CONTENT position-dependent (does it embed rIDs or offsets that renumber)? Traced from what the compiler stores there.
4. What therefore happens on load when the saved segment's length differs from the loaded module's `szDataSeg`, and what the v1 segment record must do about it: carry-raw-and-length-check (abort on mismatch), carry-raw-and-truncate/extend, or rebuild-from-module. One recommended verdict, stated as MUST for Task 9.

- [ ] **Step 2: Run the measurements**

Run the two module builds and any byte diffs inside `/private/tmp/.../scratchpad` sandboxes (never against the real `mod/`). Record commands and numbers in the note verbatim.

- [ ] **Step 3: Write the note**

`docs/SCRIPT-DATA-SEGMENT.md`, headed `<!-- citations: this-port -->`, sections: What it is / How it is written / Measurements / What renumbering does to it / Verdict for the v1 segment record. Every `file:line` cited must be verified while writing.

- [ ] **Step 4: Check the note's citations**

Run: `tools/check_citations.sh && tools/check_doc_citations.sh`
Expected: PASS (the repo gates doc citations; see the tools' own headers).

- [ ] **Step 5: Commit**

```bash
git add docs/SCRIPT-DATA-SEGMENT.md
git commit -m "Investigate the module script data segment ahead of the memory-row work

Phase 4 first task of docs/SAVE-SCHEMA-SPEC.md; the verdict here governs
how the v1 segment record carries the script state.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Phase 4 — name-keyed resource memory rows

**Files:**
- Modify: `inc/Res.h:1066-1077` (`Game`'s `MDataSeg` field line)
- Modify: `src/SaveV1.cpp` (segment record write/read; deferred row placement in `SaveV1_ResolveNames()`)
- Modify: `src/Dump.cpp` (step 1 extends the dump to print Known/Tried if it does not already)
- Modify: `tools/check_v1_full_roundtrip.sh`, `tools/check_dump_save.sh` (literal revision strings → `IS1.2`, per the bump in step 3)
- Create: `tools/check_flavor_stability.sh`
- Test: `tools/check_flavor_stability.sh`, plus the standing suite

**Interfaces:**
- Consumes: Task 8's Verdict (the segment-blob handling below is CONDITIONAL on it — where the verdict contradicts this task's default, the verdict wins and the executor adjusts the segment sub-record only, never the row format); Task 6's full-roundtrip check.
- Produces: the segment record format below.

- [ ] **Step 1: Write the failing flavour-stability check**

Create `tools/check_flavor_stability.sh` — this is the spec's oracle ("it fails on the raw block"). One note on wording: the spec phrases the oracle around a CONVERTED save ("convert a save, rebuild the module with one Effect added, load"); this check uses a natively-written v1 save instead, which is functionally equivalent — both produce a v1 file whose memory rows are name-keyed, and the module rebuild is the same — and Brian's walk-a-level check stays his manual acceptance step in Task 10. The steps:
1. Deterministic session, seed 1, `smoke.keys`; keep its save. `tools/dump_save.sh` it; extract every line naming a flavoured appearance and the Known/Tried state (the dump walks `EffMem` via real accessors; if the current dump omits Known/Tried, extend `src/Dump.cpp` in this task to print them — that extension is part of making the oracle real).
2. In an `INCURSIONPATH` sandbox, rebuild the module with one scratch `Effect` appended to a COPY of `lib/m_items.irh` (the Task 1 `check_dup_names.sh` technique, unique name).
3. `tools/dump_save.sh` the SAME save against the sandbox module (`INCURSIONPATH` points the binary at the sandbox's `mod/`).
4. Assert every potion/scroll appearance line and every Known/Tried flag is unchanged between the two dumps.
Also assert the reverse control: the check run against a REVERTED (pre-task) binary FAILS step 4 — prove the oracle bites before trusting it (run once against the Task 7 commit's binary and record the failing diff in the script's header comment).

- [ ] **Step 2: Run to verify it fails**

Run: `BACKEND=posix ./build_macos.sh && tools/check_flavor_stability.sh`
Expected: FAIL at step 4 — the raw `MDataSeg` block shifts every row and every stored flavour `rID` when `szEff` grows (the 4ba035b defect reproduced on purpose).

- [ ] **Step 3: Implement the segment record**

Replace `Game`'s `FIELD_BLOB` for `MDataSeg[i]` with, per non-null slot, `if (r.V1Active()) { r.V1EmbedBegin(tag+i, &(MDataSeg[i]), sizeof(MDataSeg[i])); SaveV1_SegmentFields(r, *this, i); r.V1EmbedEnd(); } else r.Block((void**)&(MDataSeg[i]), MDataSegSize[i]);` — `void SaveV1_SegmentFields(Registry &r, Game &g, int slot)` is a free function in `src/SaveV1.cpp` (`Game`'s arrays are public, `inc/Res.h:1096-1097`). The embed's contents (tags continue Game's range):

```
segment record (one per non-null MDataSeg[i]):
  1: K_BLOB  script data segment — the first szDataSeg bytes, raw,
             handled per docs/SCRIPT-DATA-SEGMENT.md's Verdict
             (default if the verdict permits: carry raw + store the saved
             szDataSeg; abort the load on length mismatch)
  2: K_U32   rowCount
  then rowCount row sub-records, each:
     u8   rowKind      0=MonMem 1=ItemMem 2=EffMem 3=RegMem
     u8   pool         SP_MON/SP_ITM/SP_EFF/SP_REG (matches rowKind; redundancy is a cheap check)
     u16  ordinal
     u16  nameLen + name bytes     — INLINE key, not a global-table index:
                                     rows have discard-on-missing semantics
                                     (constraint 3's exception) and the global
                                     table's entries abort
     u8   payloadLen + payload
```

Payloads are packed BY NAME from the bitfields (`inc/Res.h:1201-1238`), never memcpy'd: `MonMem` fields in declaration order into fixed bytes; `ItemMem` one byte; `EffMem` = two `uint32` name-table indices (FlavorID, PFlavorID — through the GLOBAL table, abort semantics, spec: "MUST route through the name table like any other resource reference") + one flags byte (Known/Tried/PKnown/PTried); `RegMem` one `uint32`. Only rows whose memory is non-zero are written ("a resource with no row keeps zeroed memory, as a new game gives it").

On load, the timing is two-phase, and MUST be — during the segment-record read, `Game::Modules` is stale or zeroed, because both load paths reload modules only AFTER the save group (`src/Registry.cpp:1317-1334`; `src/Dump.cpp:151-172`), so nothing module-dependent may run yet:

1. **Record read**: parse the script-segment blob and the raw row records (kind, pool, ordinal, inline name, payload) into the v1 file-scope context. No resolution, no allocation from module geometry — the same deferred-resolution design the name table already follows.
2. **After each path's module-reload loop**, in (or alongside) `SaveV1_ResolveNames()`: allocate each `MDataSeg[i]` from the LOADED module's geometry (`szDataSeg + counts*sizeof(row)` exactly as `GetMemoryPtr` computes them), zero it, place the script segment per the Verdict, then walk the parsed rows: resolve each inline key case-sensitively; a missing resource DISCARDS the row silently-by-design (log one stderr line per discard in DEBUG builds so the behaviour is observable); a resolvable row lands at the position `GetMemoryPtr` derives. The `EffMem` flavour values resolve through the global table with abort semantics, in the same pass.

`SetFlavors` (`src/Item.cpp:310`) is not called on load — verify that remains true after this change by grepping the load path.

Also in this step, the revision bump (wire-format §schema revisions): `MDataSeg` changes shape (`K_BLOB`→row records), so `SaveSchemaID()` becomes `"IS1.2"`, the reader keeps rejecting any revision it does not implement with the error naming both revisions, and the literal revision strings in `tools/check_v1_full_roundtrip.sh` and `tools/check_dump_save.sh`'s `Format:` regex become `IS1.2`. A save written in the Task 6–8 window (`IS1.0`/`IS1.1`) is thereby refused cleanly instead of misread.

- [ ] **Step 4: Run to verify it passes**

Run: `tools/check_flavor_stability.sh && tools/check_v1_full_roundtrip.sh && tools/check_v1_adversarial.sh && tools/check_dump_save.sh && tools/check_schema_roundtrip.sh`
Expected: all PASS. (`check_v1_full_roundtrip.sh`'s byte-identical assertion now also covers row ordering — rows must be written in a deterministic order: memory-layout order, which is what the allocation walk gives.)

- [ ] **Step 5: Commit**

```bash
git add inc/Res.h src/SaveV1.cpp src/Dump.cpp tools/check_flavor_stability.sh tools/check_v1_full_roundtrip.sh tools/check_dump_save.sh
git commit -m "Key the per-player resource memory rows by name, not position

Phase 4 of docs/SAVE-SCHEMA-SPEC.md. Adding an Effect no longer shifts
MonMem/ItemMem/EffMem/RegMem or the stored flavour rIDs; the oracle is
tools/check_flavor_stability.sh.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Phase 5 — `-convert`, the fixture guard, and Brian's save

**Files:**
- Modify: `src/SaveV1.cpp` (`RunSaveConvert`), `src/Wposix.cpp` (:550-558 area) and `src/Wlibtcod.cpp` (:500-505 area) (parse `-convert <file>`)
- Create: `tools/check_convert_guard.sh`
- Untracked data: `save/Dench.sav` converted in place with a `save/Dench.sav.v0` copy kept (`save/` is gitignored)
- Test: `tools/check_convert_guard.sh`

**Interfaces:**
- Consumes: the v0 reader (untouched), `SaveGroupV1`, `SaveV1_ResolveNames` — all existing names.
- Produces: `bool RunSaveConvert(const char *path)`; exit codes 0 converted, 2 usage/missing, 3 refused (fixture guard).

- [ ] **Step 1: Write the failing guard check**

Create `tools/check_convert_guard.sh`:
1. `-convert docs/evidence/inc-upw.13/Furious_Fox.sav` must exit 3, print a refusal naming the fixture rule, and leave the file byte-identical (`cmp` against a pre-copy). Same for `Jaoin.sav`.
2. A COPY of `Furious_Fox.sav` in a scratch dir must convert: exit 0, the output's `Version` reads `IS1.2` (the current `SaveSchemaID()` after Task 9's bump), a `<name>.v0` sibling holds the original bytes, and `tools/dump_save.sh` of the converted copy matches `tools/dump_save.sh` of the `.v0` copy line for line except the `Format:` line (this is the spec's "-dump before and after MUST match line for line" applied to a fixture — Dench gets the same treatment in step 4).
3. Real `save/` untouched throughout (the standard assertion).

- [ ] **Step 2: Run to verify it fails**

Run: `BACKEND=posix ./build_macos.sh && tools/check_convert_guard.sh`
Expected: FAIL — `-convert` does not exist.

- [ ] **Step 3: Implement `-convert`**

`RunSaveConvert(path)`: `realpath()` the input; refuse (exit-code 3 path) any resolved path containing `/docs/evidence/`; load through the EXISTING v0 flow exactly as `RunSaveDump` does (`src/Dump.cpp:126-173`: v0 `LoadGroup`, module reload loop — conversion is only correct when the module's numbering matches the save, which is the operator's responsibility, spec §Compatibility); write `<path>.v0` (byte copy of the original, refuse to overwrite an existing one); then write the v1 file to `path`: fill the `fileHeader` with `SaveSchemaID()` in `Version` AND `fh.Compression = SaveV1_Raw() ? 0 : 1;` (the caller-writes-the-complete-header contract — without the assignment the header claims raw while the payload is RLE), write it, then `SaveGroupV1`. The conversion is where the renumbering is repaired: the v0 read resolves every `rID` against the loaded module, and the v1 write records the resulting names. Parse `-convert <file>` in both backends beside `-dump`.

- [ ] **Step 4: Run the guard, then convert Brian's save by the verified procedure**

Run: `tools/check_convert_guard.sh` — expected PASS.

Then the spec §Compatibility procedure, exactly (the save predates `4ba035b`, which grew `szEff` by one via `lib/m_items.irh`; the module must match the save's numbering during the v0 read):

```bash
cd /Users/brianhill/Scripts/Incursion
git show 4ba035b^:lib/m_items.irh > /tmp/m_items_pre.irh
cp lib/m_items.irh /tmp/m_items_head.irh
cp /tmp/m_items_pre.irh lib/m_items.irh
./incursion -compile main.irc                      # module now matches the save
tools/dump_save.sh save/Dench.sav > /tmp/dench_before.txt
./incursion-headless -convert save/Dench.sav       # writes save/Dench.sav.v0 + v1 file
cp /tmp/m_items_head.irh lib/m_items.irh           # restore HEAD scripts
./build_macos.sh                                   # module back at full HEAD, immolation included
tools/dump_save.sh save/Dench.sav > /tmp/dench_after.txt
diff <(grep -v '^Format:' /tmp/dench_before.txt) <(grep -v '^Format:' /tmp/dench_after.txt)
git status --porcelain                             # must be clean: lib/ restored
```

Expected: the diff is EMPTY (line-for-line match across the module rebuild — Orc, Zurvash, Ranger 3 / Rogue 2 / Druid 3, The Goblin Caves depth 6, per the spec's verified reading), and the working tree is clean. If the diff is non-empty, STOP: do not delete `save/Dench.sav.v0`, report the differing lines to Brian.

Hand-off note for Brian (the plan cannot automate his hands): load the converted save in the real game, walk a level, save, reload — character sheet, inventory, mount and god unchanged. That is the spec's live check and it is his acceptance step.

- [ ] **Step 5: Commit**

```bash
git add src/SaveV1.cpp src/Wposix.cpp src/Wlibtcod.cpp tools/check_convert_guard.sh
git commit -m "Add -convert with a fixture guard, and convert the pre-4ba035b save

Phase 5 of docs/SAVE-SCHEMA-SPEC.md. The evidence fixtures refuse
conversion by path; save/Dench.sav (untracked) was converted against the
pre-4ba035b module and re-reads identically under the HEAD module.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Phase 6 — the harness scripts and the documentation

**Files:**
- Modify: `tools/dump_save.sh`, `tools/check_dump_save.sh`, `tools/check_load_corrupt.sh`, `tools/craft_corrupt_saves.py`, `tools/check_save_fail.sh`, `tools/check_stair_warn.sh`, `tools/check_headless.sh` — the seven save-touching harness scripts. The finding grep `grep -ln "\.sav\|save/" tools/*.sh tools/*.py` returns ELEVEN files (verified 2026-08-24); the four not listed above are excluded for stated reasons: `tools/flickerscan_selftest.py` and `tools/flickerthumbs.py` match only on Python image `.save()` calls (false positives, no save file involved); `tools/headless.sh` and `tools/package_macos.sh` are format-agnostic — they place, point at, or package save paths and never parse a byte of a save, so they need nothing.
- Modify: `docs/ENGINE-SERIALISATION.md`
- Test: the whole suite (list in step 4)

**Interfaces:**
- Consumes: everything shipped in Tasks 1–10.
- Produces: documentation of both formats; a suite that is green end to end.

- [ ] **Step 1: Audit each of the seven scripts against v1 (write the findings before editing)**

For each script, run it, then record in one scratch note what (if anything) is stale:
- `tools/dump_save.sh` — behaviour is format-agnostic; header comment (:9-16) still describes only the v0 memory-image reasoning → rewrite that paragraph to name both formats and when each is read.
- `tools/check_dump_save.sh` — Format regex updated in Task 6; header comment (:10-14, "a .sav is a memory image welded to the exact struct layout") is now half-true → update to say v0 fixtures are welded, v1 saves are not.
- `tools/check_load_corrupt.sh` + `tools/craft_corrupt_saves.py` — they exercise the shared header/decompression path, which both readers use; confirm PASS, update both headers to say the corpus now exercises the v1 reader's header path and the v0 reader stays covered by the fixtures.
- `tools/check_save_fail.sh` — AT-list adjusted in Task 6; confirm the control-vs-staged comparison still bites by staging one failure and watching it report.
- `tools/check_stair_warn.sh` — its fixture (`INCURSION_WCF_SAVE`, out-of-repo v0 save) loads through the v0 reader forever; add one header line saying so, so nobody "helpfully" converts it.
- `tools/check_headless.sh` — asserts save-file existence, not bytes; confirm PASS, no edit expected.

- [ ] **Step 2: Update `docs/ENGINE-SERIALISATION.md`**

Add a v1 section describing: the dispatch (`"SF"`/old literal → v0 raw reader; `"IS"` → v1), the record and name-table wire format (copy from this plan's normative section, then verify each cited line still matches source), the packed grid, the memory rows, the coverage check and pin table, the tag-number contract, and the measured v0-vs-v1 size numbers carried from Task 6's commit. Mark the v0 description as the legacy format that the reader keeps for old saves and all modules. Update the "How to check this page" block with the new grep/xxd lines (a v1 save's first 16 bytes now show `IS1.2`, the revision after Task 9's bump). Document the revision history — `IS1.0` Task 6, `IS1.1` Task 7, `IS1.2` Task 9 — and the reader's reject-unknown-revision rule.

- [ ] **Step 3: Apply the script edits from the step-1 findings**

Comment-only edits stay comment-only; any behavioural edit beyond the step-1 list means something was missed in Tasks 6–10 — stop and fix it there conceptually (i.e., in the code), not by loosening a check.

- [ ] **Step 4: Run the whole suite**

Run, each expecting PASS:
```
BACKEND=posix ./build_macos.sh
./build_macos.sh
tools/check_schema_roundtrip.sh
tools/check_v1_adversarial.sh
tools/check_v1_full_roundtrip.sh
tools/check_flavor_stability.sh
tools/check_convert_guard.sh
tools/check_dup_names.sh
tools/check_dump_save.sh
tools/check_load_corrupt.sh
tools/check_save_fail.sh
tools/check_headless.sh
tools/check_abi.sh
tools/check_module_rebuild.sh
tools/check_citations.sh
tools/check_doc_citations.sh
```
Plus one soak seed: `tools/soak.sh 1 87655 tools/keys/explore.keys` — no new error classes.

- [ ] **Step 5: Commit**

```bash
git add tools/dump_save.sh tools/check_dump_save.sh tools/check_load_corrupt.sh tools/craft_corrupt_saves.py tools/check_save_fail.sh tools/check_stair_warn.sh tools/check_headless.sh docs/ENGINE-SERIALISATION.md
git commit -m "Bring the save-reading harness scripts and the format doc up to v1

Phase 6 of docs/SAVE-SCHEMA-SPEC.md. ENGINE-SERIALISATION.md now
describes both formats, with the measured size delta.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Spec traceability

| Spec section / requirement | Task |
|---|---|
| Header, `"IS1"` dispatch | 1 |
| Name table, case-sensitive, ordinal, abort-on-unresolvable | 1 |
| Compiler rejects same-case duplicates (except Flavour) | 1 |
| Records, skip rule, tag contract | 1 |
| `Thing`/`Item` field lists | 1 |
| Adversarial: truncation (header-checked and bounds-checked families), unknown tag, deleted tag, bad name, bad ordinal, known tag with wrong kind | 1 |
| Adversarial: grid mismatch | 7 |
| Schema revision bumps + reader rejects unimplemented revisions | wire-format section (rule), 7 and 9 (bumps) |
| Coverage check (risk 1) | 1 (built + bite-proven), every task step 4 (kept green) |
| 18 remaining classes, dependency-ordered, one commit per group | 2–6 |
| `TargetSystem` real field list (risk 2) | 2 |
| `T_STAFF`/`T_COIN` NOT fixed here (risk 3) | 5, 6 (behaviour mirrored, not changed) |
| Byte-for-byte save-load-save | 6 (and re-run in 7, 9, 11) |
| Save size measured, not assumed (risk 6) | 6 (measure + stop-if-over), 11 (recorded in doc) |
| Soak on unchanged module path | 6, 11 |
| Packed `LocationInfo`, bit assignment + `static_assert` | 7 |
| Script-data-segment investigation blocks rest of phase 4 (risk 5) | 8 (Task 9 conditional on its Verdict) |
| Name-keyed memory rows, flavour rIDs through the table, discard semantics (risk 4 accepted) | 9 |
| Flavour/Known/Tried oracle across a module rebuild | 9 |
| `-convert`, repair-at-conversion, pre-4ba035b module procedure | 10 |
| Fixtures never converted | 10 (guard) + Global Constraint 7 |
| `-dump` before/after line-for-line | 10 |
| Brian's live walk-a-level check | 10 (hand-off note — his acceptance step) |
| Seven harness scripts + ENGINE-SERIALISATION.md | 11 (with the two directly-broken assertions patched in 6, where they break) |
| Non-goals (modules raw, gallery/Options untouched, String/Array untouched on v0 path, rID stays an index in memory) | Global Constraints 5, 6 + Task 6 notes |
