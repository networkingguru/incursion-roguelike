# Names in the file: implementation brief

Bead: inc-cjos0. Sized: Large. Spec (the authority, read it first):
`docs/superpowers/specs/2026-11-07-names-in-the-file-design.md`, revision 4,
approved by Brian 2026-11-07. Section numbers (5.3, AC4) refer to it. It
replaces the revision 3 spec and plan of 2026-11-06, which were never built
past phase 0.

**Goal:** a save stores field names, not field tag numbers; master's stored
values never change and a branch's colliding value moves by tool.

**Stack:** C++ (`src/SaveV1.cpp`, `inc/Base.h`, every `ARCHIVE_CLASS` and
`FieldsV1` body), Python 3 stdlib tools, bash checks, the headless build
`BACKEND=posix ./build_macos.sh`.

**Execution:** route each coding phase by the coding row of
`.claude/rules/codex-dispatch-and-orchestration.md`; run
`tools/claude_budget.py` and `bd memories out-until` before EACH coding
dispatch (2026-11-07: `sonnet-first`). Work only in
`~/Scripts/Incursion-inc-cjos0`. Claude reviews each diff, runs the named
checks, and commits before the next phase. Every new check carries
`--selftest`, a `# fact:` header (AGENTS.md), and is shown red before green.
Kept from phase 0 (735f09ba): `tools/number_values.py`,
`tools/check_number_values.sh`.

## Files touched

| File | Change |
|---|---|
| `tools/number_values.py` | Label rule: a literal index keeps its number (`m#0`); the grid embed's rows get scope `MapGrid` (spec 5.1). Phase 1. |
| `tools/gen_legacy_tags.py` | New, phase 1. Reads master's dump plus an override list, writes `inc/SaveLegacyTags.h`; `--selftest`. Run once; output frozen. |
| `tools/legacy_tag_overrides.txt` | New, phase 1. The rows that are not member fields, and the range rows of every computed run (spec 5.4). |
| `inc/SaveLegacyTags.h` | New, phase 1, generated then frozen: fixed rows `(scope, tag, name, revLo, revHi)` and range rows `(scope, baseTag, bound, name)`; tag `base+i` reads as `<name>#i`. |
| `inc/Base.h` | `FIELD_*` macros take a name string; `_AT` forms take name plus index (phase 2). |
| `src/SaveV1.cpp` | Name ids per file, name-table record, reader pre-scan, legacy path, frame duplicate refusal, retired and rename lists, `SCHEMA_REV 7` (phase 2); variables by name (phase 3); named migrations (phase 4). |
| `inc/*.h`, `src/*.cpp` with field calls | Every tag literal becomes a name (phase 2, by `tools/convert_tags_to_names.py`). |
| `tools/convert_tags_to_names.py` | New, phase 2, one-shot. Reads `inc/SaveLegacyTags.h`, never live tag numbers. Rewrites each call site from `(scope, tag)` to the legacy table's name, so source and table agree by construction. Kept in `tools/` as the record of the conversion. |
| `tools/retired_field_names.txt` | New, phase 2. Starts empty except tag 434's name; format `<scope> <name>` and `rename <scope> <old> <new>`. |
| `src/Registry.cpp` | Revision tests at 1448/1452 become named migrations (phase 4). |
| `inc/Defines.h`, `inc/Target.h`, `inc/RComp.h`, other headers with stored families | Family marks gain class, shape, width, sentinel (phase 5). |
| `tools/check_define_dups.py` | Reads the new mark fields; refuses an unclassified family; reads every marked file (phase 5). |
| `tools/check_stored_values.py` | New, phase 5 (spec 6). |
| `tools/move_branch_values.py` | New, phase 5 (spec 6). |
| `tools/retired_values.txt` | New, phase 5, empty. |
| `tools/check_number_values.sh` | Part 3 retires (no tags in source); part 4 scans fixtures through the legacy table and adds `terra-save.keys` with its fixture load (phase 6). |
| `tools/keys/terra-save.keys` | Exists, from gap 1 (uncommitted); committed in phase 6. |
| Number bands | Phase 6 deletes `tools/number_bands.txt`, `tools/next_number.sh`, `tools/number_bands.py`, `tools/check_number_bands.sh`, `tools/check_number_bands.py`, `tools/check_number_bands_tree.sh`, the pre-commit block at `.beads/hooks/pre-commit:175-195`, the `branch.$BEAD.incursionBase` write at `tools/worktree.sh:354-358`, and their `tools/README.md` lines. |
| `docs/SAVE-SCHEMA-SPEC.md`, `docs/VERIFICATION.md`, `.claude/rules/` | The rule (phase 6). |
| `tools/pressure_numbers.sh` | New, phase 7 (AC8). |
| `tools/fast_checks.sh` (STEP 3b of `finish_bead.sh`), the merge-bead path | Phase 5 wires `check_stored_values.py` into `tools/fast_checks.sh`; `move_branch_values.py` runs off master only (master-into-epic merge bead, landings into the epic) and is a no-op on master. |

## Phases (one commit each)

0. Done (735f09ba): master dump and its four-part check.

1. Legacy table. Fix the dump's label rule (literal index, `MapGrid`
   scope), then generate `inc/SaveLegacyTags.h` from MASTER's current tree
   with the override list and range rows. Verify: every `(scope, tag)` the
   part 4 scan saw in the fixtures, evidence and generated saves maps to
   exactly one name (fixed row or range row); no two ranges overlap in a scope; no
   `(scope, name)` has two tags in one revision range; selftest red on a
   dropped row and on a duplicated name. No engine change yet.

2. Names in the engine. `tools/convert_tags_to_names.py` rewrites every call
   site; `inc/Base.h` macros and the `Registry::V1*` calls take names; the
   writer assigns ids and appends the name-table record; the reader
   pre-scans for it, or builds it from `inc/SaveLegacyTags.h` for revisions
   3-6; frame duplicate refusal; retired and rename lists. `SCHEMA_REV` 7.
   Verify: AC1 (planted numeric tag fails compile), AC2 (every fixture loads,
   one planted wrong legacy row makes one refuse), AC3 (`-schematest`,
   `tools/check_v1_full_roundtrip.sh`, the gate), AC4 (duplicate, unknown,
   retired). Split for the implementer: 2a conversion script and its dry-run
   report; 2b engine API and reader/writer; 2c run the conversion and build.
   Nothing compiles between 2a and 2c: the three are one commit, and 2b is
   verified only after 2c.

3. Script variables by name (spec 7). Verify: AC6 with a scratch module
   owner that gains a variable before its last one; every fixture still
   load.

4. Named migrations (spec 8). Verify: a revision 4 fixture runs both
   migrations, a revision 6 fixture runs none, a revision 7 save records
   both names; every fixture still load.

5. Values (spec 6). Marks on every stored family; `check_define_dups.py`
   extension; `check_stored_values.py`; `move_branch_values.py`. Verify:
   AC5, each case red then green on scratch copies; the checks pass on the
   tree with zero evaluated-value change against phase 0's dump.

6. Retire and document. Bands deleted; `check_number_values.sh` part 3
   retired and part 4 rewired; `terra-save.keys` in part 4; docs and the
   rule (AC9). Verify: the check passes; its selftest goes red per part.

7. Merge rehearsal and pressure test. AC7: replay master e94c7d4b into
   inc-pu6v d71c1823 in a scratch clone after converting the epic's field
   calls with `tools/convert_tags_to_names.py` plus names for epic-only
   fields; build; no collision; no hand edit of a number. AC8: an
   independent adversarial agent (not the implementer) designs the cases;
   an implementer writes `tools/pressure_numbers.sh`; the main session runs
   it. Every case and result goes in the bead.

Then the Large-tier code review (`/code-review`), fixes, and the landing on
master through `tools/finish_bead.sh inc-cjos0`. The epic converts in its
own master-into-epic merge bead afterwards (spec 11).

## Test plan

- Adversarial: planted numeric tag, planted duplicate name in a frame,
  unknown name in a file, wrong legacy row, retired name, value collision
  of each shape, full bit word, value wider than its storage, changed
  stored-array sentinel, unclassified family, variable added mid-list.
- User-focused: every fixture in `tools/fixtures/chars`, `smoke`, `dive`, `marathon` and
  `terra-save` sessions save and reload; a master save made before the
  change loads in the new build and plays on.
- Live: the gate (`tools/nightly_verify.sh --compare` through
  `tools/finish_bead.sh`), then Brian plays a master character saved before
  the change in the new build.
