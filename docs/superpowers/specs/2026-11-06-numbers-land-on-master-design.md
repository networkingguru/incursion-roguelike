# Numbers land on master — design (inc-cjos0)

Status: spec, revision 2, after two adversarial reviews (engine and save
format; git and landing). Every ruling in section 2 was settled with Brian on
2026-11-06 (bead inc-cjos0 notes). A line marked "engineering choice" was
made by the spec author and review may contest it.

## 1. The problem

A shared number space is a set of numbers that two branches both draw from by
taking "the next free one": save tags, stati, events, god message ids,
`#define` families, enums that a save stores, option indices, the save
revision. Two branches can take the same number. Git merges both without a
conflict when the two lines sit in different places, and the merged build
holds two meanings for one number.

The case that opened this bead: the epic inc-pu6v took Character save tags
449-451 on 2026-10-02 (b41df716). Master took 449-452 on 2026-11-05
(e94c7d4b). The merge compiled clean, 17 of 88 character fixtures refused to
load, and the epic's tags were moved by hand.

Two earlier allocators each covered only the spaces someone listed after an
incident: the number bands (inc-24cc) and the no-shared-tail landed files
(inc-mhn1w). Neither had a rule that covers the whole class. This design
covers the class with a mechanical closed-world check (section 6).

## 2. Rulings (Brian, 2026-11-06)

- B1. Only master's numbers matter. Numbers on any other branch MAY move,
  and saves made there are disposable (inc-1macr).
- B2. A number that reaches master never changes.
- B3. One mechanism for every space; a new mechanism replaces the old ones
  everywhere (rule `reuse-the-existing-mechanism`).
- B4. Nobody moves or edits a number by hand.
- B5. On a branch a new number is a NAME. The build gives it a provisional
  number. Landing ON MASTER writes the final number into the source as a
  plain literal; master's source looks as it does today.
- B6. Each bead declares its new names in its own landed file.
- B7. The script compiler MAY change (lifts no-shared-tail R1).
- B8. No family is frozen.
- B9. Replaces no-shared-tail R4 and R5 where they conflict.
- B10. Acceptance includes an adversarial pressure test (AC8).

## 3. The mechanism in plain words

1. A bead that needs a new number writes a name in `inc/landed-<bead>.num`
   and uses that name in the code.
2. Every build runs the generator first. It gives each landed name the next
   free number in its space, after every number master holds, and writes
   `inc/Numbers.h` (untracked). It also refuses the build on any collision,
   so a merge that skipped every hook still cannot build a collision.
3. When the bead lands on master, `tools/finish_bead.sh` runs the finalizer.
   It writes each name's number into the source as a literal, records it in
   the master number ledger, and deletes the `.num` file.
4. A landing into any other branch does not finalize.
5. Checks refuse: a new literal off master, a changed master number, one
   name declared twice, one number with two names, and any number in an
   unclassified place.

Working case: master and the epic both add a save field. Master's lands
first as 449. After master merges into the epic, the epic's field is still a
name, so its next build gives it 450. Nobody edits anything.

## 4. Parts

### 4.1 Landed number files and their order

`inc/landed-<branch>.num`, one per bead (or per converted branch, section
5). One declaration per line:

    <space> <NAME> [run <count>] [// <comment>]

`run <count>` reserves consecutive numbers for a computed run; the name is
the first. The comment is copied beside the literal at finalization.

Order: `inc/landed.nums` lists one line per file, `landed-<branch>.num`. It
merges with the existing `landed` mode of `tools/merge_landed.py`
(master's lines, then the base branch's, then ours, then theirs), with the
line pattern widened to accept `.num` names. Provisional numbers follow this
order, then line order inside a file. A god landing into the epic therefore
appends after the epic's names and moves none of them (engineering choice:
reuses the resource order mechanism; keeps epic fixtures stable).

### 4.2 How code uses a name

- A define member: `NAME`, as any define. Scripts see it, because
  `inc/Defines.h` includes `inc/Numbers.h` and `lib/main.irc:1` includes
  `inc/Defines.h` (the script compiler's preprocessor resolves the include
  beside `Defines.h` and fails on a missing file, `src/cpp2.c:394,420-445`).
- A save tag, in any tag call (`FIELD_*`, `V1EmbedBegin`, `V1Str`,
  `V1Blob`, `V1RidStatus`, raw `v1PutU16` tag writes): `TAG_<scope>_<label>`.
- An enum member stored by value: the enum ends with the generated macro
  `<ENUM>_LANDED`, expanding to `NAME = <n>,` per landed name.
- A keyed name table (the 43 `*_CONSTNAMES` tables in `inc/ConstNam.h` and
  `STATI_CONSTNAMES` in `src/Tables.cpp`): the table ends with
  `<TABLE>_LANDED`, one row per landed name of its space.
- A table indexed by value (`AttrTitle`, `SlotNames`, `SkillInfo` and every
  other positional array in `src/Tables.cpp` whose index is a space value):
  converted once, in this bead, to keyed rows (each row carries its key) and
  indexed at startup. A new member adds a keyed row anywhere in the table.
- A save revision: `REV_<name>` in space `rev` (4.5).

A branch never edits a family's tail, an enum's tail or a table's tail; only
the finalizer writes there, on master, one landing at a time.

### 4.3 The space table

`tools/number_spaces.txt`, committed. One row per space:

    <space> <kind> <low> <high> <file> <anchor> [run <base> <bound-expr>]...

- kind `seq`: next integer after the space's maximum. kind `bit`: next free
  bit. kind `derived`: computed by a formula given in the row.
- `<high>` is per branch: the epic's copy of the stati row says 65535,
  because the epic widened stati (`inc-pu6v:inc/Res.h:324`); master's says
  255 until inc-xm3nq lands. A full space refuses the build, naming the
  space and the widening bead. It never wraps and never reuses a gap.
- `run <base> <bound-expr>` records a computed run master already holds
  (`3+i` in StatiArray, `inc/Map.h:875`; `835 + MAX_DUNGEONS` in Game,
  `inc/Res.h:1245`; every `1+i` run). The generator never hands out a number
  inside a run. A scope whose run is open-ended (`3+i` up to 0xFFF0 in
  `V1_ELEM_ARRAY_FIELDS`, `src/SaveV1.cpp:3071-3092`) is full for fixed tags.
- `<file> <anchor>`: where the finalizer writes the literal (the anchor
  comment `// landed: <space>`). Tags are rewritten in place instead.

Define families reuse the family marks `tools/check_define_dups.py` already
reads (`// family: <name>`), extended from `inc/Defines.h` to every file in
`inc/` and `src/` (excluding `inc/Numbers.h`).

Tag scopes: every `ARCHIVE_CLASS` body, every `FieldsV1` body and every
`V1EmbedBegin` site opens a scope (about 25, `src/SaveV1.cpp:2749-2773,
2810-2840`). Each gets a marker `// tag-scope: <space>`. Each scope is one
space. The per-class ranges in `inc/Base.h:769-778` are dropped: they are a
comment, and a tag is 16 bits wide.

Sentinels: each of the about 40 `*_LAST` / `LAST_*` defines gets a row of
kind `derived` with its own formula (max+1, an alias of a member, or a bit
count). Rule: a derived value MUST NOT be the base of another space. The
skill and feat chain breaks this today (`FT_FIRST (SK_LAST + 1)`,
`inc/Defines.h:2532`; feats are stored as bit positions,
`inc/Creature.h:819,1142`). The seed rewrites the feat chain to absolute
literals with identical values, so `FT_FIRST` is the literal 50. The skill
space is then full (0-49) until an engine bead moves skills past the feats;
the generator refuses a new skill and names that need. This is not new: a new
skill today already shifts every feat and breaks master saves.

### 4.4 The generator, `tools/gen_numbers.py`

Inputs: `master:tools/number.ledger`, the tree's literals, the `.num` files
in `inc/landed.nums` order, the space table. It evaluates C integer
expressions in defines (`(FT_TUVWXYZ + 49)`). Output: `inc/Numbers.h`,
written only when its content changes. It runs checks C1-C5 (4.8) and exits
non-zero on any failure, so every build is a check. It refuses to run when
the tree is master's (`HEAD` is master, or equals `master`) and any
`inc/landed-*.num` file exists.

Every compile path runs it first: `build_macos.sh`; the Linux Docker builds
(both images gain python3, `tools/linux_docker.sh:63-66`,
`tools/package_linux.sh:73-76`); every tool that compiles `inc/` directly
(`tools/check_abi.sh`, `tools/save_pad_rows.py`,
`tools/check_options_migrate.sh`, `tools/check_gcc_o2_char_create.sh`,
`tools/check_logrotate.sh`, `tools/check_ptr_sweep.sh`, and any other the plan's
sweep finds). Module freshness checks (`tools/finish_bead.sh:690`,
pre-commit 255) count `inc/landed-*.num` and `inc/landed.nums`. A query mode,
`--value NAME`, replaces text parsing in tools that read a derived value
(`tools/check_shadow_shifting.sh:20` EF_LAST, `tools/check_auto_terms.sh:63`
OPT_GEN_CURRENT, `tools/check_dump_save.sh:58` and
`tools/check_v1_full_roundtrip.sh:53` SCHEMA_REV). The unmaintained Windows
and `build.sh` paths (last changed 2025-06-28) MUST run it if revived.

Property P1: on a branch that has just merged master, the generator and the
finalizer assign the same number to every name. Both call one function.

### 4.5 Derived values and revisions

- Sentinels: per their row formula (4.3). Master's literal sentinels are
  converted once to `#define LAST_STATI NUM_LAST_STATI`.
- `SCHEMA_REV` is the highest `REV_` value; `OPT_GEN_CURRENT` the highest
  `OPT_GEN_` value. Migration code compares against `REV_` names (it already
  compares with `<` and `==`, `src/Registry.cpp:1448,1452`,
  `src/SaveV1.cpp:1828`). `MIN_READ_REV` is set to a `REV_` name by hand.
  Master's revisions 1-6 become `REV_` literals once.

### 4.6 The master number ledger, `tools/number.ledger`

A new file (engineering choice: `tools/resource_order.ledger`'s parser
rejects other row kinds and its `--record` rewrites the whole file,
`tools/resource_order_check.py:107-120,424-426`). Rows:

    N <space> <value> <NAME>
    T <space> <value> <NAME>      tombstone: retired, never reused
    L <space> <NAME> <ALIAS>      alias

`.gitattributes` gives it the existing `landed-ledger` driver (master's
copy). Only the finalizer writes it. The seed harvests every literal master
holds, naming tags `TAG_<scope>_<label>` by one rule shared with the
conversion script. The harvest MUST reproduce every current value exactly.

### 4.7 The finalizer, `tools/finalize_numbers.py`

Runs in `tools/finish_bead.sh` after STEP 3, only when the base branch is
master, on a temporary ref. For each name in `inc/landed.nums` order: write
the literal at the anchor (or into the tag argument), with its comment; add
the `N` row; remove the file and its `inc/landed.nums` line. It re-makes, with
`tools/make_char_fixture.sh`, every character fixture the bead added or
changed. The gate builds the finalized tree. Only after the gate is green does
the temporary ref become the bead head. Every exit before STEP 6 leaves the
bead branch as it was before finalizing (the EXIT trap that releases the
landing lock also discards the ref). The finalization commit's subject is
`tools: land numbers for <bead>`.

STEP 3b, the gate and the commit pass the finalizer's new rows as an explicit
allowance (`INCURSION_FINALIZED_ROWS=<file>`); C2 accepts those rows and no
others.

### 4.8 The checks (all static)

The match key is `(space, value, NAME)`.

- C1 closed world. Every integer `#define` in `inc/` and `src/` sits in a
  family or a no-family block; a no-family entry carries a reason and is not
  a sentinel or a stored value. Every tag argument is a literal, a `TAG_`
  name, or a declared run expression, and lies inside a marked scope. Every
  enum in `inc/` and `src/` has explicit values, unless the space table lists
  it as not stored. Every table indexed by a space value is keyed.
- C2 no new number off master. On any tree but master's, a literal whose
  `(space, value, NAME)` is not in `master:tools/number.ledger` refuses,
  unless the finalizer's allowance lists it. A literal whose value the ledger
  holds under another name is a collision and refuses.
- C3 master values hold. Every `N` row's name has its value in the tree; a
  removed name needs a `T` row; an alias needs an `L` row.
- C4 one name, one meaning. A name declared twice, a name both landed and
  literal, or a `TAG_` name used outside its scope refuses.
- C5 the generator's refusals: a full space, an unknown space, a number
  inside a run.

Where they run: inside every build (the generator); `.beads/hooks/pre-commit`
and a new `.beads/hooks/pre-merge-commit` that execs it (git runs
pre-merge-commit, not pre-commit, on a clean merge); `tools/finish_bead.sh`
STEP 3b and STEP 4b; pre-push, which also refuses a `.num` file on master.

### 4.9 Landing races

The landing lock (`tools/finish_bead.sh:418-507`) already serializes
`finish_bead.sh` runs. STEP 5 MUST refuse unless
`git merge-base --is-ancestor master <bead>` holds just before its merge, so
the merged tree is the gated tree. It writes master with
`git update-ref refs/heads/master <new> <old>`. On refusal the landing
restarts at STEP 3. The nightly harness's master merge
(`~/Scripts/nightly-harness/bin/nightly.sh:529`) MUST take the same lock.

### 4.10 Per-owner script variables (B7)

The resource language gains `Extend <type> "<resource>" { <variables> }`,
legal only in `lib/landed-<bead>.irh`. The compiler binds extension
variables in a pre-pass, before the main parse, so the owner's own handlers
can use them (`lang/Grammar.acc:1429-1444,1737-1776` bind in one pass
today). Their ordinals within the owner, which the save keys on
(`src/SaveV1.cpp:1948-1986`), follow the owner's own variables, in
`lib/landed.irc` order. An Extend whose owner is not declared refuses.

### 4.11 What retires

The bands: `tools/number_bands.txt`, `tools/next_number.sh`,
`tools/number_bands.py`, `tools/check_number_bands.*`, their pre-commit block,
the out-of-tree counter directory. `docs/SAVE-SCHEMA-SPEC.md` "a new field
takes the next unused number" becomes "a new field is a name in the bead's
landed number file". `tools/fixtures/chars/MANIFEST` (no consumer) is deleted.

## 5. The epic and god branches

`tools/convert_branch_numbers.py` turns every literal on a branch whose
`(space, value, NAME)` is not in master's ledger into a name in
`inc/landed-<current branch>.num`, using the harvest's naming rule. It runs
in the master-into-epic merge bead that follows this landing, and unchanged on
every god branch at its next epic merge. The hand repair in the
inc-pu6v.369 worktree (449-451 moved to 453-455, uncommitted) is discarded.
No-shared-tail R6 still holds: no bead lands into the epic until that merge
and conversion land together.

## 6. Closed-world rule

A number two branches can both take is a landed name, a literal in the master
ledger, a derived value, or a no-family entry with a reason. C1 refuses
anything else, so a new kind of space fails the first time it appears, and the
commit that adds it MUST add its row to `tools/number_spaces.txt`. The rule
goes in `docs/VERIFICATION.md` and in `.claude/rules/` in the rule-entry
format.

## 7. Out of scope, stated so they are not reopened as gaps

- Widening stati and other stored numbers: inc-xm3nq. Master has five free
  stati (251-255) until it lands.
- Moving skills past the feats: a future engine bead; the generator names it.
- Save pad rows: measured, not allocated; `tools/check_save_pad_rows.sh`
  stays at the gate.
- `FIELD_ARRAY` counts sized by `MAX_*`: a size, covered by inc-xm3nq.
- `lib/dispatch.h` ids: compiler-numbered with a forced conflict.
- `INCURSION_*` names: a uniqueness check joins `tools/check_probe_hooks.sh`.
- The 8 known define collisions: each has a bead; the seed records them as
  they are.
- `git merge --no-verify` skips the hooks; the build still refuses (4.4).

## 8. Failure modes

| Failure | Caught by |
|---|---|
| New literal on a branch, any value | C2 (by name and value) |
| Master value edited or removed | C3 |
| One name, two meanings | C4 |
| Clean merge that ran no hook | the generator at the next build; pre-merge-commit |
| Space full; number inside a run | C5 |
| New space unclassified | C1 |
| Failed landing after finalizing | temporary ref discarded (4.7) |
| Master moved during a landing | STEP 5 ancestry rule (4.9) |
| `.num` left on master by a hand merge | generator and pre-push refuse |
| Fixture made on a branch | P1 plus the finalizer re-making it |

## 9. Acceptance criteria

- AC1. C1 passes on master after the migration and refuses a planted
  unclassified define, a planted literal tag outside a scope, a planted
  implicit stored enum and a planted positional table (red each, restored).
- AC2. The seed reproduces every master value: the 88 character fixtures
  load, `-schematest` round-trips, the gate is green, and a diff of every
  evaluated value before and after shows zero changes.
- AC3. C2-C5 each go red on a planted defect and pass when it is removed, in a
  build, a commit, a clean merge (pre-merge-commit) and a landing.
- AC4. A bead adding one name of each space kind lands; master holds plain
  literals, the ledger holds its rows, no `.num` file remains.
- AC5. A failed gate after finalizing leaves the bead branch unchanged; a
  master that moves during a landing makes it restart.
- AC6. Two beads that `Extend` one resource merge with no conflict, their
  variables are usable in the owner's handlers, and both land in order.
- AC7. Replaying 2026-11-05 (master e94c7d4b into inc-pu6v at d71c1823) after
  conversion builds with no collision and no hand edit, and
  `tools/convert_branch_numbers.py` runs unchanged on the epic and one god
  branch.
- AC8. Pressure test. An independent adversarial agent designs the hardest
  changes it can find to a scratch copy of master and one of the epic, across
  every space: one number on both sides, a sentinel bump on both sides, a
  mid-list enum insert, a revision bump on both sides, one name with two
  meanings, `Extend` on one resource, racing landings, a hand merge with
  `--no-verify`, and any case it invents. Its cases are written as a
  committed driver, `tools/pressure_numbers.sh`, modeled on the
  `selftest_merge_repo` scratch repos in `tools/finish_bead.sh:126-188`, with
  a fake `bd`; the main session runs it, because subagents cannot commit. The
  copies merge through the real paths: bead landing, master into the epic
  through a merge bead, the epic into a god branch by hand merge. It passes
  only if every merged build holds no number with two meanings, every master
  value is unchanged, nobody edits a number, and every refusal names its
  space. Each case and its result is recorded in the bead.
- AC9. The bands are retired; `docs/SAVE-SCHEMA-SPEC.md`,
  `docs/VERIFICATION.md` and `.claude/rules/` state the rule.
