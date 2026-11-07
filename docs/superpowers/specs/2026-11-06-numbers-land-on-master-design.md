# Numbers land on master — design (inc-cjos0)

Status: spec, revision 3. Revision 2 had two adversarial reviews (engine and
save format; git and landing); round 2 is
`docs/evidence/inc-cjos0/spec-review-round2.md` (findings N1-N14), round 3
is `spec-review-round3.md` beside it (findings R3-1 to R3-5, folded in with
no further round, Brian 2026-11-06). Revision
3 fixes the findings that block the mechanism and cuts parts that only
existed to serve other parts (the `inc/landed.nums` order file, its merge
driver, the ledger merge driver, the `update-ref` swap, the automatic
restart). Every ruling in section 2 was settled with Brian on 2026-11-06
(bead inc-cjos0 notes). A line marked "engineering choice" was made by the
spec author and review may contest it.

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
- B2. A number that reaches master and is stored (in a save, `Options.Dat`
  or another file) never changes. A build-internal number MAY change; the
  epic's 76 `MSG_*` renumberings are allowed. A branch that gives a stored
  master number a new meaning collides: the epic's reuse of Character tags
  439 and 441-443 is converted to new tags, and the old tags are retired.
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
   free number in its space, after every number the tree's ledger and
   literals hold, and writes `inc/Numbers.h` (untracked). It also refuses
   the build on any collision, so a merge that skipped every hook still
   cannot build a collision.
3. When the bead lands on master, `tools/finish_bead.sh` runs the finalizer.
   It writes each name's number into the source as a literal, records it in
   the number ledger, and deletes the `.num` file.
4. A landing into any other branch does not finalize.
5. Checks refuse: a new literal off master, a changed stored master number,
   one name declared twice, one number with two names, and any number in an
   unclassified place.

Working case: master and the epic both add a save field. Master's lands
first as 449. After master merges into the epic, the epic's field is still a
name, so its next build gives it 450. Nobody edits anything. The epic's
fixtures recorded that name at 449, so they are stale and the merge bead
re-makes them (4.12).

## 4. Parts

### 4.1 Landed number files and their order

`inc/landed-<branch>.num`, one per bead (or per converted branch, section
5). One declaration per line:

    <space> <NAME> [run <count>] [// <comment>]
    retire <space> <NAME>
    rename <space> <OLD> <NEW>

- `run <count>` reserves consecutive numbers for a computed run; the name is
  the first. The comment is copied beside the literal at finalization.
- `retire` removes a stored master name; its value becomes a tombstone and is
  never handed out again. The bead's own code keeps whatever read path master
  saves need for that value (a retired tag that a master save still holds is
  ECORRUPT unless the reader asks for it, `src/SaveV1.cpp:2345-2349`).
- `rename` keeps a stored master value under a new name (a renamed `FIELD_`
  member, for example).
- `retire` and `rename` are legal only for stored spaces (4.3).

Order: the generator reads the `.num` files sorted by file name, then each
file in line order. No order file exists. A new `.num` file can move other
branches' provisional numbers; B1 allows it, and 4.12 re-makes the fixtures
it affects (engineering choice: a per-bead file name is unique, so git adds
and deletes these files with no conflict, and no merge driver is needed).

### 4.2 How code uses a name

- A define member: `NAME`, as any define. Scripts see it, because
  `inc/Defines.h` includes `inc/Numbers.h` and `lib/main.irc:1` includes
  `inc/Defines.h` (the script compiler's preprocessor resolves the include
  beside `Defines.h` and fails on a missing file, `src/cpp2.c:394,420-445`).
- A `FIELD_*` save tag: `TAG_<scope>_<label>` in the tag argument. The label
  is normalized by one rule, shared by the harvest, the conversion and C4:
  keep each identifier in the label expression in order, drop `&`, `*` and
  every index expression, and join them with `_` (`&t[i].why.data` becomes
  `t_why_data`; `Items[i]` becomes `Items`). Two fields in one scope with
  one normalized label refuse (C4).
- Every other tag position: a define from the scope's tag family,
  `// family: tag-<space>`, named explicitly (`TAG_Character_AidWaitEnd`).
  The tag-taking calls are a closed list in `tools/number_spaces.txt`:
  `V1EmbedBegin`, `V1Str`, `V1Blob`, `V1RidStatus`, `v1Find`, and both tag
  arguments of `V1ArrayWiden16`; the plan's sweep completes the list. A raw
  `v1PutU16` that writes a tag becomes `v1PutTag`, so a text check can tell a
  tag from data (the terminator `v1PutU16(&v1Out, 0)` stays as it is).
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

    <space> <kind> <stored|internal> <low> <high> <storage> <file> <anchor> [run <base> <bound-expr>]...

- kind `seq`: next integer after the space's maximum. kind `bit`: next free
  bit. kind `derived`: computed by a formula given in the row.
- `stored` or `internal` says whether B2 applies. Save tags, stati, stored
  enums, option indices and `rev` are `stored`; `MSG_*` ids are `internal`.
- `<high>` is per branch: the epic's copy of the stati row says 65535,
  because the epic widened stati (`inc-pu6v:inc/Res.h:324`); master's says
  255 until inc-xm3nq lands. A full space refuses the build, naming the
  space and the widening bead. It never wraps and never reuses a gap.
- `<storage>` is a C expression for the largest value the stored form holds
  (`UINT8_MAX` for the stati nature, `inc/Map.h:881`). The generator emits
  `static_assert(<largest assigned value> <= <storage>)` into
  `inc/Numbers.h`, so a raised `<high>` that outgrows its storage fails the
  compile.
- The generator refuses a space name that has two rows.
- `run <base> <bound-expr>` records a computed run master already holds
  (`3+i` in StatiArray, `inc/Map.h:875`; `835 + MAX_DUNGEONS` in Game,
  `inc/Res.h:1245`; every `1+i` run). The generator never hands out a number
  inside a run. A scope whose run is open-ended (`3+i` up to 0xFFF0 in
  `V1_ELEM_ARRAY_FIELDS`, `src/SaveV1.cpp:3071-3092`) is full for fixed tags.
- `<file> <anchor>`: where the finalizer writes the literal (the anchor
  comment `/* landed: <space> */`). Tags are rewritten in place instead.

Define families reuse the family marks `tools/check_define_dups.py` already
reads (`// family: <name>`), extended from `inc/Defines.h` to every file in
`inc/` and `src/` (excluding `inc/Numbers.h`).

Tag scopes: every `ARCHIVE_CLASS` body, every `FieldsV1` body and every
`V1EmbedBegin` site opens a scope (about 25, `src/SaveV1.cpp:2749-2773,
2810-2840`), and so does any other function body that holds a tag-taking
call (the epic's `Registry::V1CharSpellsAid`, epic `src/SaveV1.cpp:2787-2804`,
is one). Each gets a marker `/* tag-scope: <space> */` (a block comment,
so a marker inside a multi-line macro does not swallow the next line). Each
scope is one space. A macro that expands in more than one scope MAY hold
only run expressions and `TAG_` names, never a fixed literal. The per-class
ranges in `inc/Base.h:769-778` are dropped: they are a comment, and a tag is
16 bits wide.

Sentinels: each of the about 40 `*_LAST` / `LAST_*` defines gets a row of
kind `derived` with its own formula (max+1, an alias of a member, or a bit
count). Rule: a derived value MUST NOT be the base of another space. The
skill and feat chain breaks this today (`FT_FIRST (SK_LAST + 1)`,
`inc/Defines.h:2532`; feats are stored as bit positions,
`inc/Creature.h:819,1142`). The seed rewrites the feat chain to absolute
literals with identical values, so `FT_FIRST` is the literal 50. The skill
row's high is 48, and `SK_LAST` stays the literal 49 (it is one past the
last skill, `inc/Defines.h:2136-2137`, and code tests `ft <= SK_LAST`,
`src/Create.cpp:5226`). The skill space is therefore full until an engine
bead moves skills past the feats; the generator refuses a new skill and
names that need. This is not new: a new skill today already shifts every
feat and breaks master saves.

### 4.4 The generator, `tools/gen_numbers.py`

Inputs: the tree's `tools/number.ledger`, the tree's literals, the `.num`
files (4.1 order), the space table. It needs no git, so the Linux Docker
builds (exported tree, no `.git`, `tools/linux_docker.sh:129-136`) run it
the same way once both images have python3 (`tools/linux_docker.sh:63-66`,
`tools/package_linux.sh:73-76`). The images are reused by a fixed tag
(`tools/linux_docker.sh:101-103`), so the python3 change MUST also change
both image tags, or the old images stay in use. It evaluates C integer expressions in
defines (`(FT_TUVWXYZ + 49)`). Output: `inc/Numbers.h`, written only when
its content changes, and listed in `.gitignore` (otherwise STEP 1's
clean-tree test refuses every landing after a build). It runs checks
C1-C5 (4.8) and exits non-zero on any failure, so every build is a check.
When git is present it refuses to run when the checked-out branch is master
(`git symbolic-ref --short HEAD`) and any `inc/landed-*.num` file exists.

Every compile path runs it first: `build_macos.sh`; the Linux Docker builds;
every tool that compiles `inc/` directly (`tools/check_abi.sh`,
`tools/save_pad_rows.py`, `tools/check_options_migrate.sh`,
`tools/check_gcc_o2_char_create.sh`, `tools/check_logrotate.sh`,
`tools/check_ptr_sweep.sh`, and any other the plan's sweep finds). Module
freshness checks (`tools/finish_bead.sh:690`, pre-commit 255) count
`inc/landed-*.num`. A query mode, `--value NAME`, replaces text parsing in
tools that read a derived value (`tools/check_shadow_shifting.sh:20`
EF_LAST, `tools/check_auto_terms.sh:63` OPT_GEN_CURRENT,
`tools/check_dump_save.sh:58` and `tools/check_v1_full_roundtrip.sh:53`
SCHEMA_REV). The unmaintained Windows and `build.sh` paths (last changed
2025-06-28) MUST run it if revived.

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

### 4.6 The number ledger, `tools/number.ledger`

A new file (engineering choice: `tools/resource_order.ledger`'s parser
rejects other row kinds and its `--record` rewrites the whole file,
`tools/resource_order_check.py:107-120,424-426`). Rows:

    N <space> <value> <NAME>
    T <space> <value> <NAME>      tombstone: retired, never reused
    L <space> <NAME> <ALIAS>      rename: ALIAS now holds NAME's value

Only the finalizer writes it, so a branch's copy is always some earlier
master's copy. Git therefore merges it with no conflict and no driver:
master into a branch takes master's copy (the branch never changed it), and
a bead into master is a merge of a tree that already contains master (4.9).
The finalizer appends its rows at the end. The ledger guard (in
`gen_numbers.py --check`, which the hooks run) accepts a tree ledger L only
when the ledger at `git merge-base HEAD master` is a prefix of L, and L less
the finalizer's allowance (4.7) is a prefix of `master:tools/number.ledger`.
A merge that brings in a newer master passes (inside pre-merge-commit, HEAD
is still the pre-merge commit, round-3 R3-1); a branch's own row or a
truncation refuses. The seed harvests
every literal master holds, naming tags by the 4.2 rule. The harvest MUST
reproduce every current value exactly.

### 4.7 The finalizer, `tools/finalize_numbers.py`

Runs in `tools/finish_bead.sh` right after STEP 3, only when the base
branch is master. It records the bead head as `PRE_FINAL`. For each `.num`
declaration in 4.1 order: write the literal at the anchor (or into the tag
argument), with its comment, and add the `N` row; turn `retire` into a `T`
row and `rename` into an `L` row; then delete every `.num` file. It commits
the result on the bead branch with the subject
`tools: land numbers for <bead>`. The gate and STEP 4a-4c then run on that
commit as on any other.

Every exit before STEP 5's merge leaves the bead as it was before
finalizing: the EXIT trap that releases the landing lock runs
`git reset --hard PRE_FINAL` in the worktree while `PRE_FINAL` is set and
the bead is not an ancestor of master. The trap is installed before the
finalizer runs, so it does nothing while `PRE_FINAL` is unset, and nothing
after the merge.

`tools/finish_bead.sh` exports the finalizer's new rows as an explicit
allowance (`INCURSION_FINALIZED_ROWS=<file>`) once, right after the
finalizer, for every later step: STEP 3b, the gate, the STEP 4a commit and
the STEP 5 merge. C2 and the ledger guard accept those rows and no others.

### 4.8 The checks (all static)

For a stored space the match key is `(space, value, NAME)`. For an internal
space it is `(space, NAME)`. Every check reads the tree's ledger.

- C1 closed world. Every integer `#define` in `inc/` and `src/` sits in a
  family or a no-family block; a no-family entry carries a reason and is not
  a sentinel or a stored value. Every argument of a tag-taking call (4.2) is
  a literal, a `TAG_` name, or a declared run expression, and lies inside a
  marked scope. Every enum in `inc/` and `src/` has explicit values, unless
  the space table lists it as not stored. Every table indexed by a space
  value is keyed.
- C2 no new number off master. On any tree but master's, a literal whose key
  is not in the ledger refuses, unless the finalizer's allowance lists it. In
  a stored space, a literal whose value the ledger holds under another name
  is a collision and refuses.
- C3 stored master values hold. For a stored space, every `N` row's name has
  its value in the tree, unless a `T` row, an `L` row, or a `retire` or
  `rename` declaration in a `.num` file covers it. Internal spaces have no C3.
- C4 one name, one meaning. A name declared twice, a name both landed and
  literal, two values with one name, one value with two names in one space,
  or a `TAG_` name used outside its scope refuses.
- C5 the generator's refusals: a full space, an unknown space, a number
  inside a run, two rows for one space.

Where they run: inside every build (the generator);
`.beads/hooks/pre-commit`; a new `.beads/hooks/pre-merge-commit` that runs
only `gen_numbers.py --check` (git runs pre-merge-commit, not pre-commit, on
a clean merge, and pre-commit's own blocks misread a merge there because
MERGE_HEAD is absent, round-2 N2); `tools/finish_bead.sh` STEP 3b and STEP
4b; pre-push, which also refuses a `.num` file on master.

### 4.9 Landing races

The landing lock (`tools/finish_bead.sh:418-507`) already serializes
`finish_bead.sh` runs. STEP 5 MUST refuse, under the lock and just before
its merge, unless `git merge-base --is-ancestor master <bead>` holds, so the
merged tree is the gated tree. A refusal exits; the trap restores the bead
(4.7), and the next `finish_bead.sh` run merges the new master at STEP 3.
STEP 5's merge itself is unchanged. The nightly harness's master merge
(`~/Scripts/nightly-harness/bin/nightly.sh:529`) MUST take the same lock.

### 4.10 Per-owner script variables (B7)

The resource language gains `Extend <type> "<resource>" { <variables> }`,
legal only in `lib/landed-<bead>.irh`. The compiler binds extension
variables in a pre-pass, before the main parse, so the owner's own handlers
can use them (`lang/Grammar.acc:1429-1444,1737-1776` bind in one pass
today). Their ordinals within the owner, which the save keys on
(`src/SaveV1.cpp:1948-1986`), follow the owner's own variables, in
`lib/landed.irc` order. An Extend whose owner is not declared refuses.

A resource's own variable list is frozen once the resource is on master: a
new variable for an existing resource goes only through `Extend`.
`tools/check_landed_files.py` refuses a variable appended to an existing
resource body (it checks module-level variables only today). Without this
rule, an own variable added after an Extend landed would shift every Extend
ordinal and break master saves (round-2 N10).

### 4.11 What retires

The bands: `tools/number_bands.txt`, `tools/next_number.sh`,
`tools/number_bands.py`, `tools/check_number_bands.*`, their pre-commit block,
the out-of-tree counter directory. `docs/SAVE-SCHEMA-SPEC.md` "a new field
takes the next unused number" becomes "a new field is a name in the bead's
landed number file". `tools/fixtures/chars/MANIFEST` (no consumer) is deleted.

### 4.12 Fixtures follow the numbers

`tools/make_char_fixture.sh` records, in the fixture's `.sheet.txt`, the
`(space, NAME, value)` of every provisional name the build held. A fixture is
stale only when one of its recorded names now has another value (a
provisional value from `gen_numbers.py --value`, or a finalized literal
through the ledger). A finalized literal with the same value is not stale,
so a re-make happens only when a number really moved; a re-make under a
changed module can change the character (bef32c3), so it MUST NOT run
otherwise.

A landing (into any base) and the master-into-epic merge bead loop over
every `tools/fixtures/chars/*.sheet.txt` before the gate, re-make each stale
fixture, and commit the re-made files on the bead branch before STEP 5 (a
file left uncommitted dies with the worktree, `tools/finish_bead.sh:956`).
The loop does not go through `tools/check_char_fixture.sh`, which checks one
fixture only (`:58`).

## 5. The epic and god branches

`tools/convert_branch_numbers.py` turns every literal on a branch whose key
(4.8) is not in master's ledger into a name in
`inc/landed-<current branch>.num`, using the 4.2 naming rule. For each stored
master name that is absent from the branch, it writes a `retire` line; a
master value the branch reuses under another name is converted to a new name
(B2: Character tags 439 and 441-443). It cannot tell a rename from a
retirement, so it never writes `rename`. It runs in the master-into-epic
merge bead that follows this landing, and unchanged on every god branch at
its next epic merge. The hand repair in the inc-pu6v.369 worktree (449-451
moved to 453-455, uncommitted) is discarded. No-shared-tail R6 still holds:
no bead lands into the epic until that merge and conversion land together.

## 6. Closed-world rule

A number two branches can both take is a landed name, a literal in the
ledger, a derived value, or a no-family entry with a reason. C1 refuses
anything else, so a new kind of space fails the first time it appears, and the
commit that adds it MUST add its row to `tools/number_spaces.txt`. The rule
goes in `docs/VERIFICATION.md` and in `.claude/rules/` in the rule-entry
format.

## 7. Out of scope, stated so they are not reopened as gaps

- Widening stati and other stored numbers: inc-xm3nq.
- Moving skills past the feats: a future engine bead; the generator names it.
- Reading master's retired tags on the epic (439 Anger and the rest) so a
  master save loads there: the epic's own work under the 2026-10-31
  master-saves-survive ruling. The tombstone only stops reuse.
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
| New literal on a branch, any value | C2 |
| Stored master value edited or removed | C3 |
| Stored master value given a new meaning | C2 (collision) |
| One name, two meanings | C4 |
| Branch edits the ledger | ledger guard (4.6) |
| Clean merge that ran no hook | the generator at the next build; pre-merge-commit |
| Space full; number inside a run | C5 |
| `<high>` raised past its storage | `static_assert` in `inc/Numbers.h` |
| New space unclassified | C1 |
| Failed landing after finalizing | EXIT trap resets to `PRE_FINAL` (4.7) |
| Master moved during a landing | STEP 5 ancestry rule (4.9) |
| `.num` left on master by a hand merge | generator and pre-push refuse |
| Own variable appended after an Extend | `tools/check_landed_files.py` (4.10) |
| Fixture made at other provisional numbers | recorded names (4.12) |

## 9. Acceptance criteria

- AC1. C1 passes on master after the migration and refuses a planted
  unclassified define, a planted literal tag outside a scope, a planted
  implicit stored enum and a planted positional table (red each, restored).
- AC2. The seed reproduces every master value: the 88 character fixtures
  load, `-schematest` round-trips, the gate is green, and a diff of every
  evaluated value before and after shows zero changes.
- AC3. C2-C5, the ledger guard and the storage `static_assert` each go red
  on a planted defect and pass when it is removed, in a build, a commit, a
  clean merge (pre-merge-commit) and a landing.
- AC4. A bead adding one name of each space kind, one `retire` and one
  `rename` lands; master holds plain literals, the ledger holds its rows, no
  `.num` file remains.
- AC5. A failed gate after finalizing leaves the bead branch at `PRE_FINAL`;
  a master that moves during a landing makes STEP 5 refuse and leaves the
  bead at `PRE_FINAL`.
- AC6. Two beads that `Extend` one resource merge with no conflict, their
  variables are usable in the owner's handlers, and both land in order; a
  planted own variable appended to that resource refuses.
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
  only if every merged build holds no number with two meanings, every stored
  master value is unchanged, nobody edits a number, and every refusal names
  its space. Each case and its result is recorded in the bead.
- AC9. A master merge into a branch that changes a provisional number makes
  the fixtures that recorded it stale, and the merge bead re-makes and
  commits them with no hand step; a fixture whose recorded numbers did not
  move is not re-made, at a landing on master included.
- AC10. The bands are retired; `docs/SAVE-SCHEMA-SPEC.md`,
  `docs/VERIFICATION.md` and `.claude/rules/` state the rule.
