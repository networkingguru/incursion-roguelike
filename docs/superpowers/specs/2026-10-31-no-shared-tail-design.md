# No shared tail: stop number and position collisions between branches

Bead: inc-mhn1w. Status: design for Brian's approval. Sized: Medium.

## 1. Intent

Brian works on several branches at once: master, the pantheon epic
(inc-pu6v), god branches cut from the epic, and bead worktrees cut from master
or the epic. Each branch can add stati, events, glyphs, effects, items,
monsters, script variables and other numbered things. Today two branches often
take the same number or the same resource position. Each merge then needs a
hand repair, and a wrong repair breaks saves. Live case: inc-pu6v.293, where an
old save loads Semirath's flute as Essiah's boots.

Measured pain (Observed): the master landings of inc-w6t0 (ac60f813) and
inc-gzkn (94a930b6) on 2026-10-21 both hand-resolved lines in `lib/main.irc`
and in `tools/resource_order.ledger` (`git show --cc`).

The cause is one shape. Every branch adds its new entries at the END of the
same shared lists: the end of `lib/main.irc` and of the last `.irh` file of
each array, the line above `LAST_STATI`, the tail of `STATI_CONSTNAMES`, and
the resource ledger. Git cannot merge two additions at one end of a file.

The design removes the shared tail. No two branches add text at the same
place, so git merges their additions without a conflict, and the existing
checks guard master's positions.

## 2. Rulings this design obeys (Brian, 2026-10-31)

- R1. The compiler and the save layer do not change. A resource's save id stays
  its position in the compiled module.
- R2. Only saves made from master MUST survive. A save made on any other branch
  MAY break when that branch lands.
- R3. No tool commits to master outside the landing path.
- R4. A branch MUST NOT get its numbers changed late by a resolver at landing.
- R5. For the `#define` families other than stati and events, detection only
  (a duplicate-value check) is accepted for now.

## 3. Goals, non-goals, anti-goals

Goals:
- G1. Two branches that each add new resources merge with no conflict, and
  every new position is decided once, at landing, after all of master's.
- G2. Two branches that each take a new stati or event number merge with no
  conflict at a terminator line or a name-table tail.
- G3. Two names with one value in any `inc/Defines.h` family fail a check
  before the landing reaches its base branch.
- G4. A session needs no human to land.

Non-goals:
- N1. Saves made on a branch surviving that branch's landing (R2).
- N2. Prevention for the other `#define` families (R5).
- N3. Reconciling the epic and the god branches. A follow-up bead does it
  (section 7).

Anti-goals (a failure even if it works):
- A1. A path that changes master without the landing gate.
- A2. A registry outside git that a commit depends on.
- A3. A rule a session must remember instead of a check that refuses.

## 4. The design

### 4.1 New resources go in a per-bead file

- `lib/main.irc` gets one new LAST line, once: `#include "landed.irc"`.
- `lib/landed.irc` holds only lines of the form
  `#include "landed-<bead-id>.irh"`, one per bead that added resources.
- A bead that adds any resource (any of the 21 arrays) or any module-level
  script variable creates `lib/landed-<bead-id>.irh`, declares the new things
  there, and appends its include line to `lib/landed.irc`. Bead ids hold dots
  (`inc-pu6v.17`); the file name keeps the id as it is.
- Edits to existing resources stay where they are, as today.
- A landed file is closed to new declarations once its bead lands. A later
  bead that extends the same feature makes its own landed file.
- Landed files stay flat in `lib/`. Nested includes work there today
  (`lib/sp_books.irh:3`, Observed); subdirectories under the DECUS cpp
  (`src/cpp1.c` to `src/cpp6.c`) are not verified.

Why the last include gives the last positions: positions follow declaration
order through the whole preprocessed module, and
`tools/check_v1_append_survives.sh` already appends an Effect after the
script text at the end of `lib/main.irc` and finds it at the last Effect
position.

Enforcement: new tool `tools/check_landed_files.py`.
- The bead id is the current branch name. It MUST match
  `^inc-[a-z0-9]+(\.[0-9]+)*$`; otherwise the check exits 2.
- It reads the built module's resource names (the `-resorder` dump that
  `tools/resource_order_check.py` already uses) and the base branch's ledger
  (`git show <incursionBase>:tools/resource_order.ledger`, default master).
- A name is new when the base branch's ledger does not hold it in that array.
  For each new name it searches `lib/landed-<bead-id>.irh` for that name as a
  quoted string. When the name is absent there, it refuses, naming the
  resource and its array. Where else the name is declared does not matter.
- It exits 2, not 0, when it cannot read the module, a ledger or the bead id.
- It runs in `.beads/hooks/pre-commit` (non-merge commits that stage `lib/`,
  where the module is already fresh) and in `tools/finish_bead.sh` right
  after STEP 4b.

Not covered, and stays a plain conflict: a new script variable added inside
an EXISTING resource. Two branches that do this to one resource both append
inside one block, and git stops the merge. That is detection, not silent
damage.

### 4.2 The merge rule for `lib/landed.irc`

- `.gitattributes` gets `lib/landed.irc merge=landed`.
- New script `tools/merge_landed.py %O %A %B` builds the result in this order,
  with no line twice:
  1. the lines of `master:lib/landed.irc`, in master's order;
  2. the other lines of the bead's base branch (`branch.<bead>.incursionBase`,
     recorded by `tools/worktree.sh:340`; default master), in its order;
  3. the other lines of `%A`, in its order;
  4. the other lines of `%B`, in its order.
- It exits 1 (git then leaves a normal conflict, and `tools/finish_bead.sh`
  STEP 3 stops) when any line in any input is not an include line of the form
  above, or when it cannot read master's or the base branch's copy.
- `tools/worktree.sh` sets `merge.landed.driver` in the repository config on
  every run (the same config serves every worktree, the shared checkout and
  the nightly branch there). `tools/finish_bead.sh` STEP 3 refuses when that
  config is absent. A repository without the config falls back to git's text
  merge, which stops on two appends at one end of the file: it fails safe.

Why master first: master's positions are the ones real saves hold. Every other
branch's positions move behind master's at each merge, which R2 allows.

### 4.3 Stati and event numbers rename a placeholder line

- One-time data edit on master, inside this bead:
  - STATI: one placeholder line for each number from 251 to 255, in the form
    `#define STATI_RESERVED_251 251`, with ONE BLANK LINE between each,
    and a matching `{ STATI_RESERVED_251, "STATI_RESERVED_251" },` row in
    `STATI_CONSTNAMES` (`src/Tables.cpp:5105-5295`), also with a blank line
    between each. `LAST_STATI` becomes 256 and stays there.
  - EV: placeholder lines for 301 to 320 after `EV_SPOT_CHECK`
    (`inc/Defines.h:4785`) and rows in `EV_CONSTNAMES`
    (`inc/ConstNam.h:1822`), the same way.
- `tools/next_number.sh` (inc-24cc), after it issues a number, renames that
  number's placeholder line and table row to the requested name, in place, in
  the session's worktree. It refuses, and issues nothing, when the placeholder
  is absent.
- Two branches then change different lines with a blank line between them.
  Git merges that cleanly (measured with `git merge-file`, Observed by the
  inc-mhn1w review; adjacent lines with no blank line conflict).
- When a placeholder window is used up, the allocator refuses at the band end
  as it does today, and one bead adds the next window.
- Master's stati budget is 251 to 255, five numbers. Master stores a stati
  number in 8 bits (`inc/Res.h:323`, `Nature :8`); the epic widens it to 16
  (`inc-pu6v:inc/Res.h:324`). Master gets a larger band only after the epic
  lands. 244, 246 and 248 stay unused: the master counter stands at 250
  (`issued.log` shows 245, 247, 249, 250 issued to master), and the allocator
  never issues below its counter.
- The placeholder names appear only in debug and status displays
  (`src/Debug.cpp:430`, `:1567`, `:1818`, `:2037`; `src/Status.cpp:632`). A
  save stores the stati number, never its name.

`LAST_STATI` = 256 sizes a per-creature allocation (`src/Status.cpp:182`,
`:330`; `src/SaveV1.cpp:3717`). It is not a save field (Traced by the review).
Index 255 stays valid in an array of 256.

### 4.4 The ledger is recorded at landing, not by beads

- The gate already records a legal append into the worktree's
  `tools/resource_order.ledger` on a green check (`tools/finish_bead.sh`
  STEP 4b header). `tools/finish_bead.sh` commits that ledger on the bead
  branch after STEP 4, then runs STEP 4b and STEP 5 as now.
- `.beads/hooks/pre-commit` drops the `--require-recorded` block
  (`.beads/hooks/pre-commit:241-266`). The order guard above it stays: it
  still refuses an insertion or a reorder.
- `.gitattributes` gets `tools/resource_order.ledger merge=landed-ledger`;
  that mode of `tools/merge_landed.py` always outputs master's copy
  (`git show master:tools/resource_order.ledger`), whatever the direction of
  the merge. The gate then re-records the branch's own appends after its
  build, as legal appends behind master's positions.
- STEP 4b's base-ledger guard reads master's ledger, not the base branch's.
  By R2, master's positions are the only ones a real save holds. A guard on
  the epic's positions would refuse every master-into-epic merge, because
  master's new landed files go in front of the epic's.
- The pre-commit order guard compares the module with the committed ledger
  and passes on a legal append (`tools/resource_order_check.py` passes on
  append; `tools/order_guard.sh` header), so a lagging ledger on a bead branch
  does not refuse a commit. An order-break approval lives outside the tree
  (`tools/order_guard.sh:8-11`) and does not edit the ledger.
- A bead branch thus stops editing the ledger. Only `tools/finish_bead.sh`
  does, so two beads never conflict on it.

### 4.5 Duplicate values in the other families: detection only

- New check `tools/check_define_dups.py`. It reads every integer `#define` in
  `inc/Defines.h`, evaluates its value (including expressions such as
  `FT_TUVWXYZ+48`), and groups names into families. The stati block (the
  lines from `SICKNESS` to `LAST_STATI`) is one family by line range, whatever
  the names; so is the EV block. Outside those blocks, the family is the text
  before the first `_`, and a name with no `_` is not checked. So
  `MAGIC_AURA` and `SOCIAL_MOD` collide as stati and go in the baseline.
- It fails on two names with one value in one family, unless the pair is in
  `tools/define_dups.baseline`. The baseline holds today's duplicates,
  including `MAGIC_AURA`/`SOCIAL_MOD` = 234 (`inc/Defines.h:3193-3194`,
  inc-upw.57) and the EV aliases `EV_WIELD`/`EV_PUTON`/`EV_WEAR` = 13.
- It exits 2 on an expression it cannot evaluate. It MUST NOT skip one.
- It runs in the fast set of `tools/finish_bead.sh` STEP 3b, after the base
  branch is merged in, and in `.beads/hooks/pre-commit` when `inc/Defines.h`
  is staged.
- On a failure, the landing bead renumbers its own entry. Master's number
  stays.

## 5. What guards master

Nothing in this design reaches master outside `tools/finish_bead.sh`. The
guards are the existing ones, unchanged: the gate's
`tools/check_resource_order.sh` and STEP 4b's base-ledger guard
(`tools/finish_bead.sh:657-704`), which refuses a landing that moves a
position master recorded. The new checks in 4.1 and 4.5 add refusals; they
remove none. `tools/check_v1_append_survives.sh` needs no change: its append
still lands last.

## 6. Risks

- K1 (Reasoned). The merge driver lives in git config, not in the tree. A
  repository without it gets a plain conflict, and STEP 3 refuses first.
- K2 (Traced). A branch made without `tools/worktree.sh` has no
  `incursionBase`; its lines may order before lines of the epic it has not
  seen. STEP 4b refuses that landing (`tools/finish_bead.sh:680-694`).
- K3 (Traced). A bead that adds to an already-landed file inserts positions.
  The pre-commit order guard and STEP 4b refuse it.
- K4 (Reasoned). Playtest saves on a god branch break when the god lands
  into the epic. R2 allows it.
- K5 (Observed). The epic cannot land into master today under any design:
  master's effects at 1189-1192 sit at 1237-1240 on the epic
  (`git show inc-pu6v:tools/resource_order.ledger`, lines 2051, 2099-2102).
  Section 7 handles it.

## 7. Follow-up, out of this bead

One bead under inc-pu6v, after the epic takes this design in through its
gated master merge: move the epic's appended resources into
`lib/landed-inc-pu6v.irh` and each god's into its own landed file, take
master's order, add the epic's stati placeholders for its band (300-399, the
unissued part), and re-record the ledger through
`tools/approve_order_break.sh`. God branches inc-pu6v.9, .13, .15 and .17 do
the same at their next merge of the epic.

## 8. Acceptance criteria (replace the bead's current ones)

- AC1. Two test branches that each add one effect in their own landed file
  merge with no conflict, and both effects follow every master position;
  `tools/check_resource_order.sh` passes on the result.
- AC2. Two test branches that each take a stati through
  `tools/next_number.sh` merge with no conflict in `inc/Defines.h` or
  `src/Tables.cpp`.
- AC3. `tools/check_landed_files.py` refuses a new effect declared outside the
  bead's landed file, shown red, then green with the effect moved.
- AC4. `tools/check_define_dups.py` refuses a new duplicate value, shown red,
  then green; it passes on master with the baseline.
- AC5. `tools/merge_landed.py` exits 1 on a malformed line, shown red.
- AC6. `tools/check_v1_append_survives.sh` and the gate pass on the bead.

## 9. Left to the builder

File layout inside the new scripts, the exact message text, the selftests
each check carries (including the update to `tools/next_number.sh`'s
selftest fixture for rename in place), and how the test branches for AC1 and
AC2 are built (scratch clones under `logs/`, never the shared repository's
refs).
