<!-- citations: this-port -->

# Plan: module manifest and position-keyed references

Goal: make a v1 save survive a legal append to any resource list, and refuse a
load loudly when the append-only rule has been broken.

Spec: `docs/SAVE-SCHEMA-SPEC.md` (normative). Read it first.

Architecture: the save gains a per-module manifest holding each array's length
and each entry's name, in position order. Resource references stay plain
`rID` values. The reader converts a saved `rID` to (array, position) using the
manifest's lengths, applies the drift rules, and converts back using the loaded
module's lengths. All conversion is deferred to `SaveV1_ResolveNames()`,
because modules reload after the save group is read.

## Files touched

| File | What changes |
|---|---|
| `src/SaveV1.cpp` | The manifest record, its parser, the conversion, the drift rules, the version rules. Nearly all the work. |
| `inc/Creature.h` | Nothing in this plan. `Spells[]`, the nine god arrays, `MMArray`, `AutoBuffs`, `SpellKeys` and `QuickKeys[].Value` stay ordinary `FIELD_ARRAY` lines: `SpellNum`/`GodNum` (`src/Res.cpp:64-77`) are plain array positions, and append-only keeps them stable. |
| `inc/Res.h`, `src/Res.cpp` | Read-only helper to fetch a module's 21 array lengths in fixed order, if one is needed. Do not change `__GetResource` or any `rID` arithmetic. |
| `docs/ENGINE-SERIALISATION.md` | The manifest's wire shape, after phase 2 lands. |

## Rules for this work

- The **array order is a wire constant**: Monster, Item, Feature, Effect,
  Artifact, Quest, Dungeon, Routine, NPC, Class, Race, Domain, God, Region,
  Terrain, Text, Variable, Template, Flavour, Behaviour, Encounter. It MUST
  match `__GetResource` (`src/Res.cpp:102-215`) and `V1GetPool`
  (`src/SaveV1.cpp:820`). Assert it rather than trusting it.
- **Bump `SCHEMA_REV`** (`src/SaveV1.cpp:51`) once, in phase 1.
- **The v0 path is not touched.** Every `FIELD_ARRAY` line and every v0 reader
  branch stays exactly as it is.
- **Do not delete a bounds check, a guard, or an error path** to make something
  fit. If one is in the way, say so in the report and stop. `tools/review_deletions.sh`
  is run on every diff from this work.
- Do not open `tools/craft_bad_v1_saves.py` or `tools/check_v1_adversarial.sh`.
  The adversarial cases are written separately.

## Phases

One commit each. Build with `BACKEND=posix ./build_macos.sh`, which compiles
`incursion-headless` and the module without a display.

**Phase 1 — write the manifest.**
Add a per-module-slot manifest to the save. Put it in the existing per-slot
scope, tag 816 (`inc/Res.h:1253`), where slot `i` is already inner tag `1+i` --
that tag IS the addressing, there is no name lookup. Two new tags inside that
scope, alongside the segment record already there: the 21 array lengths as one
`K_ARRAY` of 21 `uint32`, and every entry's name in position order, array by
array, as one length-prefixed blob. Do NOT copy the module filename in; it is
already in `ModFiles`, tag 868 (`inc/Res.h:1108`). Adding tags inside the
existing scope keeps the generic scanner and the harness field parsers working. Save direction only; nothing reads it
yet. Bump `SCHEMA_REV`. Verify: a save written by the new binary is still
loadable by it, and `tools/check_schema_roundtrip.sh` (or the existing
round-trip check) stays green.

**Phase 2 — parse the manifest.**
Read the manifest into a deferred structure that outlives the save group, the
way `v1Seg[]` already does. `Game::Modules` is stale or zeroed at parse time —
do not touch it here. Validate shape only: 21 lengths present, each within a
sane bound, the name count equal to the sum of the lengths, no length or offset
that runs past the record. A malformed manifest throws `ECORRUPT`. Still
nothing uses it.

**Phase 3 — convert references by position.**
Replace name-keyed resolution. On save, `V1InternRid` stops computing the
ordinal and stops storing a name per reference; a reference is written as the
plain `rID`. On load, `SaveV1_ResolveNames()` converts each saved `rID`:
split off the module slot, walk the manifest's lengths for that slot to get
(array, position), then walk the loaded module's lengths to rebuild the `rID`.
**Refuse a shrink before converting anything.** If any loaded array is shorter
than the length the manifest recorded, the append-only rule was broken by a
removal: throw `ECORRUPT` naming the array, the recorded length and the length
found. This check runs over all 21 arrays up front, not per reference, because
the shrink is the defect whether or not a saved reference falls in the missing
range. Do not clamp, do not skip, do not zero. A position past the loaded
array's length is likewise `ECORRUPT`, naming the array and the position. Delete `V1ResolveEntry`'s name search, the
`ordinal` field, and the `required`/optional split — the spec's "What this
deletes" lists them. Verify: a save written before an Effect is appended to
`lib/` loads correctly after the append, which is the whole point of the work.

**Phase 4 — memory-segment rows.**
The resource-memory rows (`src/SaveV1.cpp:1130-1150`) carry their own inline
pool + ordinal + name key. Convert them to (array, position) on the same
terms as phase 3. Their discard-on-missing semantics go away: under
append-only a recorded position always exists.

**Phase 5 — drift rules.**
Compare the manifest's name list against the loaded module's, per array, over
positions 0 to (manifest length − 1). Refuse only on a **slide** (a run of two
or more consecutive positions where the current name equals the manifest's name
one position earlier or later) or a **shuffle** (same set of names, at least
one at a different position). Every other difference loads silently, including
one changed name and every name changed — that is the spec's rule 3 and it is
not negotiable. A refusal names the array, the first offending position, the
recorded name and the found name. Verify with `tools/check_spell_god_drift.sh`,
which needs repointing from "renumbering survives" to "an illegal insertion is
refused"; keep its sandbox-module and reload machinery, it is the expensive
part.

**Phase 6 — version and unknown-tag rules.**
Refuse a file whose schema revision is newer than the binary's, naming both.
Refuse an unknown field tag rather than skipping it. An older revision still
loads and takes constructed defaults for fields it lacks.

**Phase 7 — document it.**
Add the manifest's wire shape to `docs/ENGINE-SERIALISATION.md`, in the style
of the sections already there, with file:line references.

## Test plan

The spec's "Test plan" is the normative list. Split by who writes it:

- **Codex writes**: round trip with no drift; legal append; legal replacement
  of one name; legal mass rename of a whole array; illegal insertion; illegal
  shuffle; illegal removal from the middle; illegal removal of an array's last
  entry, run with a save that references nothing in the missing range. These need a sandbox module
  and a rebuild, and `tools/check_spell_god_drift.sh` already has that
  machinery.
- **Claude writes**: unknown-tag refusal, version refusal, and the adversarial
  malformed-manifest cases. These build
  deliberately corrupt files and a Codex run that touches that tooling is
  terminated by OpenAI's content filter.

Two checks cannot run inside the Codex sandbox because they launch the SDL
binary: `tools/check_flavor_stability.sh` and `tools/check_dump_save.sh`.
Claude runs those outside it.

## Not in this plan

The build-time order ledger — a committed list of every resource in position
order, checked as a strict prefix on every build, so an illegal reorder fails
the build instead of a save. It enforces the same rule from the other side and
is tracked separately.
