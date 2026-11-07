# Names in the file — design (inc-cjos0)

Status: spec, revision 4. It replaces the names-only allocator of revision 3
(`2026-11-06-numbers-land-on-master-design.md`) and its plan. Brian chose this
method on 2026-11-07 after comparing three: the allocator, names in the file
(the method of Unreal, Unity and Godot), and one schema file (the method of
Protocol Buffers). A line marked "engineering choice" was made by the spec
author, and review may contest it. Review round 4 (Fable, 2026-11-07) found
no blocker; its findings are folded in, and the review is
`docs/evidence/inc-cjos0/spec-review-round4-fable.md` in the shared checkout.

## 1. The problem

Two branches can give one stored number two meanings. The case that opened
this bead: the epic inc-pu6v took Character save tags 449-451 on 2026-10-02
(b41df716), and master took 449-452 on 2026-11-05 (e94c7d4b). The merge
compiled clean, 17 of 88 character fixtures refused to load, and the epic's
tags were moved by hand.

A save stores numbers of two kinds:

- **Field tags.** Every saved field carries a u16 tag that says which member
  it is (`src/SaveV1.cpp:2368-2438`). About 290 call sites choose a tag by a
  literal number. This is the space that collided.
- **Values.** A field's value can be a number from a `#define` or enum
  family: a stati nature, an attribute index, a feat bit, an option number.
  Section 4 lists them.

Resource references (rIDs) are a third kind, and they are solved already: a
save carries a manifest of resource names, and the reader converts each rID
by name (`SaveV1_ResolveNames`, `src/SaveV1.cpp:2284-2335`).

## 2. Rulings

- B1. Only master's numbers matter. Saves made on any other branch are
  disposable (inc-1macr).
- B2. A value that reaches master and is stored (in a save, `Options.Dat` or
  another file) never changes. A build-internal value MAY change.
- B3. One mechanism per kind of number, and a new mechanism replaces the old
  one everywhere.
- B4. Nobody moves or edits a number by hand.
- B5 (2026-11-07). Field tags become names in the file. This supersedes the
  2026-11-06 rulings that a new number is a landed name finalized at a master
  landing.
- B6. Do not gold plate.

## 3. The mechanism in plain words

1. Source names every saved field with a string, not a number:
   `FIELD_U8("nature", nature)`. No tag number appears in source.
2. The writer gives each distinct field name a small number for this file
   only, in first-use order, and writes a name table into the file.
3. The reader reads the name table first. Each field list then asks for its
   field by name, and the reader finds the number this file used for it.
4. A save written before this change (revisions 3-6) has no name table. The
   reader uses a frozen table of master's old numbers instead (5.4).
5. Values stay numbers. Master's stored values are frozen and checked, and a
   branch value that collides with a master value is moved by a tool (6).

Working case: master and the epic both add a Character field. Master names
its field `"AidWaitEnd"` and the epic names its field `"Anger2"`. Git merges
both lines. Each file gives each name its own number, so the fields cannot
collide. If both branches choose one name for two meanings, the merged build
holds two fields with one name in one scope, and the writer refuses (5.3).

## 4. What a save stores, by kind

Research inventory, 2026-11-07, worktree inc-cjos0 (Traced from source; the
items marked "inferred" in the research were matched by name only).

| Kind | Examples | This design |
|---|---|---|
| Field tag | every `FIELD_*`, `V1*` call, raw `v1PutU16` tag | names (5) |
| rID | `FIELD_RID`, `V1Rid`, script variables of type `DT_RID` | manifest, unchanged |
| Typed family value | `Status.nature` (stati), `Status.src` (SS_), `Attr[]` by ATTR_, `SkillRanks[]` by SK_, `Feats` bits by FT_, `Abilities[]` by CA_, `Inv[]` by SL_, `Options[]` by OPT_, `numMonOfType[]` by MA_, flag words (KN_, IF_, DF_, MS_, WG_, AL_), `Target.type`/`TargetWhy.type` (implicit enums, `src/Target.cpp:1554,1561`), the record type byte T_ (`src/SaveV1.cpp:3208`), the variable type byte DT_ (`inc/RComp.h:18`) | frozen on master, checked (6) |
| Untyped value | `Status.val`/`mag` (family depends on nature), script variable ints, `AutoBuffs`, `SpellKeys`, `QuickKeys[].Value` | frozen on master, as the families they hold (6) |
| Position in a resource list | `Spells[]` by `SpellNum()`, the nine god arrays by `GodNum()`, `MMArray`, `MaxDepths` | out of scope (9) |
| Raw bytes | `Target.data`, `TargetWhy.data`, map grid blobs, `Glyph` | unchanged; no tags inside |
| Script variables | per-owner list, saved WITH names (`src/SaveV1.cpp:1008-1044`) | load by name (7) |

Files other than saves: `Options.Dat` is a headerless array of 900 option
bytes, byte i is option i (`src/Player.cpp:68-143`); its option numbers are a
typed family under 6. `gallery.dat` is a headerless array of raw
`ReincarnationInfo` structs (`inc/Creature.h:1375-1409`); it is out of scope
(9). The compiled module `mod/*.Mod` is a raw image rebuilt by every build and
is never shared between builds; it is out of scope.

## 5. Field names

### 5.1 How source names a field

- Every `FIELD_*` macro, `V1EmbedBegin`, `V1Str`, `V1Blob`, `V1RidStatus` and
  `V1ArrayWiden16` takes a name string where it took a tag number. The macro
  signature changes, so a call site that still passes a number fails to
  compile. This is how an unconverted epic line is found.
- The name is unique within its scope. A scope is what it is today: the
  nearest `ARCHIVE_CLASS` or `FieldsV1` owner, or an embed. Its scope name is
  the string `V1ProbeScope` already receives.
- The conversion writes names from the member expression by one rule (the
  rule `tools/number_values.py` already applies to make dump labels): keep
  each identifier in order, drop `&`, `*` and index expressions, join with
  `_`. A literal index keeps its number: `m[0]` becomes `m#0`
  (`inc/Res.h:1194-1197`, `inc/Map.h:657-660`). A staged temporary
  (`nature`, `val`) takes its member's name. The map grid embed
  (`src/SaveV1.cpp:3018-3073`) gets its own scope, `MapGrid`, so its `gx`
  and `gy` do not take Map's `sizeX` and `sizeY`. The conversion copies the
  dump label, after the dump's labels get the same index rule, so the frozen
  legacy table (5.4) and the new names agree.
- A computed run (`(uint16)(1+i)`, `3+i`, `835+i`) becomes a name plus an
  index: `FIELD_U32_AT("DungeonID", i, ...)`, stored in the table as
  `DungeonID#3`. Fixed inner names repeat in every element of an embed, as
  inner tag numbers do today.
- The raw manifest and variable writes (`v1PutU16` of tags 2-7,
  `src/SaveV1.cpp:1034-1143,1707-1710`) and their `v1Find(1..7)` reads become
  named calls. The `v1PutU16(..., 0)` terminators stay.

### 5.2 The file

- Revision 7. The file header and record layout do not change. Each field
  keeps its wire form `u16 id, u8 kind, payload`; `id` now means "row of this
  file's name table".
- Each group ends with one name-table record of a new record type: a list of
  `u16 id, u16 scopeLen, scope, u16 nameLen, name`. Engineering choice: the
  writer knows every name only after the last record, the payload is built in
  memory before compression (`src/SaveV1.cpp:3247-3274`), and the reader
  holds the whole group in memory for its two passes (`3468-3596`), so the
  reader finds the table first by skipping records by length.
- Ids are per (scope, name), from 1 in first-use order. Id 0 stays the
  terminator.

### 5.3 What the reader and writer refuse

- The writer refuses (ASSERT, and EGENERIC in release) one name written twice
  in one frame (one record's top level, or one embed). Sibling embeds repeat
  names legitimately (every Status element holds `nature`). This is the check
  that catches two branches that chose one name for two meanings.
- The reader keeps today's rules, keyed by name: a name no field list asks
  for is ECORRUPT (`src/SaveV1.cpp:2465-2495`); a known name with the wrong
  kind is ECORRUPT; a missing name keeps the constructed default.
- A name that master retired goes on a committed list,
  `tools/retired_field_names.txt` (`<scope> <name>`). The reader ignores a
  retired name. A retired name is never reused.
- A renamed field keeps its old name in the same file as `rename <scope>
  <old> <new>`; the reader matches either. Renames are rare, and nobody has
  to rename a field to fix a collision.

### 5.4 Saves from before the change

- Revisions 3-6 carry tag numbers and no name table. `MIN_READ_REV` stays 3,
  because other players hold master saves.
- `inc/SaveLegacyTags.h`, generated once from master's phase 0 dump
  (`tools/number_values.py`, 735f09ba) and then frozen: rows of
  `(scope, tag, name)`, with a revision range for the segment tags whose
  meaning changed at revision 4 (`src/SaveV1.cpp:1846-1855`). The generator
  takes a short override list for the rows that are not member fields: the
  retired Spells array tag 434 (read by `V1ArrayWiden16`,
  `inc/Creature.h:1201`; fixtures from inc-vqla e72bfa34 hold it), the
  segment tags read by `v1Find(1..7)`, and the dump's `?` scope, which maps to
  the runtime scope (`Game` inside the 816 embed, `inc/Res.h:1258-1266`).
- A computed run has no dump row per tag (`tools/number_values.py:660-668`),
  so the header also holds range rows `(scope, baseTag, bound, name)`; the
  reader maps tag `base+i` to name `<name>#i`. The runs are the `1+i`,
  `3+i` and `835+i` sites (`inc/Map.h:625,630,876`,
  `inc/Creature.h:1185,1204,1640,1648,1667`, `inc/Res.h:1221,1245,1262`,
  `src/SaveV1.cpp:3141`, `src/Target.cpp:1553`). The generator refuses two
  ranges or a range and a fixed row that overlap in one scope.
- Reading a revision 3-6 file, the reader builds the file's name table from
  this header instead of reading one. Everything after that is the same code
  path as revision 7.
- The header is never edited after it lands. A field added after this change
  has no legacy row, because no old file can hold it.

## 6. Values

Values stay numbers. A name table for values would also need every field to
declare which family its value comes from, and it cannot work for untyped
values (`Status.val` holds a skill number for one nature and mana for
another; a script variable is a bare int). So values keep master's numbers
fixed, as B2 says, and a branch moves.

- Each `// family: <name>` mark (`tools/check_define_dups.py`) gains a class,
  and a stored family also gains its shape and its storage width:
  `// family: <name> internal`, or
  `// family: <name> stored <ordinal|bits|enum> <u8|i8|u16|i16|u32|i32>`.
  The marks extend from `inc/Defines.h` to every file in `inc/` and `src/`
  that holds a stored family (`inc/Target.h`, `inc/RComp.h` included). A
  family with no class refuses, so a new family must be classified the first
  time it appears.
- A sentinel that sizes a stored array is a stored value of its family
  (`ATTR_LAST`, `SK_LASTSKILL`, `MA_LAST_REAL`, `MAX_GODS`, `MAX_SPELLS`,
  `MAX_DUNGEONS`; the reader checks the count exactly,
  `src/SaveV1.cpp:2750`), so changing it on master refuses. A sentinel that
  sizes memory only (`LAST_STATI`, `inc/Map.h:867`) is marked
  `sentinel <NAME>` and is exempt from the check.
- `tools/check_stored_values.py`, a gate check. It evaluates every name of
  every stored family on master and on the tree under test (the phase 0
  compiler path of `tools/check_number_values.sh` part 2). It refuses: a
  master name whose value differs in the tree; a master name absent from the
  tree unless `tools/retired_values.txt` lists it; a tree-only name whose
  value a master name or a retired value holds in the same family; and any
  name whose value does not fit the family's storage width (master saves
  stati nature as u8, `inc/Map.h:882,886`; the epic already writes the high
  byte as tag 11, `inc-pu6v:inc/Map.h:912-918`).
- `tools/move_branch_values.py`. On any branch but master, for each
  collision the check reports, it moves the tree-only name to a value free
  in the merged tree, by shape: `ordinal`, the next value after the family's
  maximum; `bits`, the next free bit, refusing when the word is full (KN_ is
  full at 0x80, `inc/Defines.h:339-348`); `enum`, the line moves to the end
  of the enum with an explicit value, so no master enumerator shifts. It
  rewrites the family's marked sentinel to max+1. It runs in the
  master-into-epic merge bead and at a bead landing, before the check.
  Engineering choice: the move happens only off master, so B2 holds, and B1
  makes the moved branch values harmless.
- A family full at its storage width makes the tool refuse and name
  inc-xm3nq.
- Option numbers in `Options.Dat` are the `opt` family, stored. The options
  generation (`OPT_GEN_*`) stays as it is (ruling 2026-11-07, no forcing
  rule).

## 7. Script variables

Variables already travel with their names. Today the reader places each
value by (owner, ordinal) and uses the name only to detect drift
(`src/SaveV1.cpp:1948-2005`). The reader instead places each value by
(owner, name); a saved name the owner no longer has is dropped, and a
variable the file lacks keeps its default. This removes the rule that a
resource's variable list is frozen (revision 3, 4.10), because a new
variable no longer shifts the others. The `Extend` grammar of revision 3 is
not needed for numbers and is dropped from this design.

## 8. Revisions and migrations

- `SCHEMA_REV` stays the container version. It moves to 7 here and changes
  again only for a container change, on master only.
- A data migration (today `MigrateSpellFlagsRev5`/`Rev6`,
  `src/Registry.cpp:1448,1452`) gets a name. Game saves a list of the
  migration names applied, as one named string field. The reader runs every
  known migration the list lacks. A revision 3-6 file implies the list of its
  revision (revision 6 implies both). Two branches that each add a migration
  pick two names, so they cannot collide.

## 9. Out of scope

- Positions in resource lists stored as numbers (`Spells[]`, god arrays,
  `MMArray`): the resource-position system (no-shared-tail, inc-mhn1w) keeps
  master's positions append-only; the comment at `inc/Creature.h:1114-1123`
  already names the limit.
- `gallery.dat` layout: no version and no guard; its own bead.
- Widening stati and other stored widths: inc-xm3nq.
- Moving skills past the feats (`FT_FIRST (SK_LAST + 1)`): adding a skill
  changes every feat value, so `check_stored_values.py` refuses it on master,
  as it should.
- Reading master's retired tags on the epic so a master save loads there:
  the epic's own work under the 2026-10-31 master-saves-survive ruling.
- Raw byte fields: they hold no tags.

## 10. What retires

From revision 3, never built: landed number files, `inc/Numbers.h`, the
generator, the number ledger, the finalizer, the space table, checks C1-C5,
`Extend`. From the tree: the number bands (`tools/number_bands.txt`,
`tools/next_number.sh`, `tools/number_bands.py`, `tools/check_number_bands.*`,
their pre-commit block and counter directory), and the per-class tag ranges
comment at `inc/Base.h:769-778`. `docs/SAVE-SCHEMA-SPEC.md` "a new field takes
the next unused number" becomes "a new field takes a name unique in its
scope". Kept: phase 0 (`tools/number_values.py`,
`tools/check_number_values.sh`), as the source of the legacy table and of the
master values check.

## 11. The epic

The epic merges master through a merge bead (rule
`merge-master-into-an-epic-through-a-bead`). Each epic-only field call still
passes a number and fails to compile; the bead names it by 5.1. Epic saves
are disposable, so the epic needs no legacy rows. The epic's reuse of master
tags 439 and 441-443 stops mattering, because the epic's fields get their own
names. Then `tools/move_branch_values.py` moves the epic's colliding values.
No hand edit of a number remains.

## 12. Failure modes

| Failure | Caught by |
|---|---|
| Two branches add fields to one scope | nothing to catch: names differ |
| One name, two meanings in one scope | writer refusal (5.3) |
| Unconverted numeric field call | compile error (5.1) |
| Name in a file no field list asks for | reader ECORRUPT (5.3) |
| Retired field name reused | `tools/retired_field_names.txt` check in the gate |
| Old master save | legacy table (5.4) |
| Master stored value changed or removed | `check_stored_values.py` |
| Branch value collides with master | `check_stored_values.py`, then `move_branch_values.py` |
| New family not classified | `check_define_dups.py` refusal |
| Two branches add a migration | names differ (8) |
| New script variable mid-list | load by name (7) |

## 13. Acceptance criteria

- AC1. Every field call in `src/` and `inc/` passes a name; a planted numeric
  tag fails to compile.
- AC2. Every character fixture in `tools/fixtures/chars` (74 on master,
  revisions 3-6) loads through the legacy
  table, and `tools/check_number_values.sh` part 4 passes on them; a planted
  wrong legacy row makes one fixture refuse.
- AC3. A revision 7 save round-trips: save, load, save gives identical field
  values (`-schematest`, `tools/check_v1_full_roundtrip.sh`), and the gate is
  green.
- AC4. A planted duplicate name in one scope makes the writer refuse; a
  planted unknown name in a file makes the reader refuse; a retired name is
  ignored.
- AC5. `check_stored_values.py` refuses a changed master stored value, a
  removed one, a colliding branch value, a value wider than its storage, a
  changed stored-array sentinel and an unclassified family (red each,
  restored); `move_branch_values.py` clears an ordinal, a bit and an enum
  collision with no hand edit and no master value moved, and refuses a full
  bit word.
- AC6. A save whose owner gained a variable before its last variable loads
  every value into the right variable.
- AC7. Replaying 2026-11-05 (master e94c7d4b into inc-pu6v at d71c1823)
  after conversion builds with no field collision and no hand edit of a
  number.
- AC8. Pressure test, as ruled 2026-11-06: an independent adversarial agent
  designs the hardest changes it can find to scratch copies of master and the
  epic (fields added on both sides, one name with two meanings, a value on
  both sides, a sentinel bump on both sides, a migration on both sides, a
  variable added mid-list, a hand merge with `--no-verify`, and its own
  cases), as a committed driver `tools/pressure_numbers.sh`. It passes only
  if every merged build holds no number or name with two meanings, every
  stored master value is unchanged, every master fixture loads, and nobody
  edits a number.
- AC9. The bands are retired; `docs/SAVE-SCHEMA-SPEC.md`,
  `docs/VERIFICATION.md` and `.claude/rules/` state the rule.
