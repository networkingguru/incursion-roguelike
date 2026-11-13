# Shared allocation spaces

A shared allocation space is a number or a name that two branches can each
take on their own, so that git merges both with no conflict. Bead inc-cjos0
exists because of one: master and the epic `inc-pu6v` both took Character save
tags 449-451, the merge compiled, and 17 of 88 fixtures then failed to load.

This file is the inventory of every such space. A new space MUST be added here,
with a protection and a planted-duplicate row in
`tools/check_space_mutations.sh`, in the commit that creates it
(`.claude/rules/engine-data-knowledge.md`,
`shared-numbers-take-a-name-or-a-frozen-value`).

## The three protections

- **A name, not a number.** The save file carries the name. Two branches choose
  two names, so nothing collides. A duplicate name in one scope is refused.
- **A value frozen on master.** A `#define` family or enum carries a
  `// family:` class. `tools/check_stored_values.py` refuses a changed or
  removed master value and a branch value that collides with one. Off master,
  `tools/move_branch_values.py` moves the branch's own value. Nobody edits a
  stored number by hand.
- **A line that names its owner.** The line that takes the number or name also
  carries the id of the bead that took it. Two branches that take the same
  thing write two different lines at one place, and git stops on a text
  conflict.

## Where detection runs

- **Every commit in a bead worktree, merge commits included:** the pre-commit
  hook runs `tools/fast_checks.sh`, which runs every check with a `gate-fast:`
  header: `tools/check_define_dups.py`, `tools/check_stored_values.py`,
  `tools/check_save_names_fast.sh` and `tools/check_probe_names.py`.
- **Every landing:** `tools/finish_bead.sh` merges the base, runs the mover
  when the base is not master, and runs the same fast set (STEP 3b). Its
  ledger and landed-file steps (STEP 4b, 4c) check resource positions.
- **The master-into-epic merge:** it is a merge bead
  (`.claude/rules/epic-branches.md`), so its merge commit passes the hook and
  its landing passes `tools/finish_bead.sh`.
- **Every build:** `build_macos.sh` runs `tools/check_define_dups.py`,
  `tools/check_stored_values.py` and `tools/check_save_names.py` before it
  compiles, and the compiler and the resource compiler refuse the rest.

The resource-position checks (`tools/order_guard.sh`,
`tools/check_landed_files.py`) do not run on a merge commit. Their hook block
first refuses any commit whose staged `lib/` files are newer than the module,
and a merge commit stages the other side's `lib/` files without a build, so the
block skips merges (bead inc-4320). They run at every landing instead, before
anything reaches the base branch.

## Inventory

"Before" is the state before bead inc-cjos0. Caught: git, a compiler, a check
or a load refusal stopped a double allocation. Silent: nothing stopped it.

| # | Space | Before | Evidence for the mark | Protection now | Planted duplicate |
|---|---|---|---|---|---|
| 1 | Saved field identity | silent | A field tag was a function argument, so two equal tags compiled, and git merged the two lines because they sat apart. Only the load refused, late. The 2026-11-05 merge is the instance. | A name unique in its scope; a numeric tag fails to compile; master's old numbers frozen in `inc/SaveLegacyTags.h`. | row 1 |
| 2 | Save container revision `SCHEMA_REV` | silent | Two branches that bump 7 to 8 make the identical one-line edit, and git merges it clean. | The define carries `/* rev owner: <bead> */`; `tools/check_save_names.py` refuses a define without one. | row 2 |
| 3 | Resource-array positions | caught at landing | The no-shared-tail system: the order ledger and `tools/check_landed_files.py` refuse a mid-list insert. | Unchanged. A save converts positions by manifest name. | row 3 |
| 4 | Module-level script variables | caught in part | `tools/check_landed_files.py` refused a variable declared in another bead's landed file, but two beads that each declared the same name in their own landed file compiled. | The resource compiler refuses a variable declared twice at module level. | rows 4a, 4b |
| 5 | Script variables in one resource | silent | Two declarations of one name in one resource body compiled, and the save reader then refused the save. | Variables load by owner and name; the resource compiler refuses a name declared twice in one body. | row 5 |
| 6 | Stati natures | caught | Disjoint number bands plus `tools/check_define_dups.py`. The bands are retired. | `// family: stati stored`; master values frozen; the mover. | row 6 |
| 7 | Event numbers `EV_` | caught | Bands plus `tools/check_define_dups.py`. Not saved. | `// family: ev internal`; the duplicate-value rule. | row 7 |
| 8 | God message ids `MSG_` | caught | The same as row 7. These exist only on the epic. | The same as row 7. | epic only |
| 9 | Other `#define` and enum families | caught in part | Only one value twice in one family inside `inc/Defines.h`; other headers were not read. | Every family in every file carries a class; skills take 800-999 and feats stop at 799. | row 9 |
| 10 | Option numbers and `Options.Dat` bytes | caught in part | The same as row 9; a short `Options.Dat` aborted the reader. | `opt` family, `stored`, `grows OPT_LAST`; the player's options reader accepts a shorter file. `Game::Opt` still aborts on one (bead inc-w9sts). | row 10 |
| 11 | Saved array dimensions | caught at load | A count mismatch threw at load. | A limit that sizes a saved array may grow and never shrink; the reader accepts a shorter array. | row 11 |
| 12 | Auto-numbered stored enums | silent | A mid-list insert shifted the later values, and no check read them. | Enum families carry a class; the mover appends a branch member with an explicit value. | row 12 |
| 13 | Data migrations | silent | Migrations were keyed to revision numbers, so two branches could each add one for the same revision. | A migration has a name, and the save lists the names it applied; a name registered twice is refused. | row 13 |
| 14 | Skill and feat numbers | silent | One value could be a skill and a feat, and both set one bit. | Skills 800-999, feats below 800; `tools/check_define_dups.py` refuses a skill or feat outside its range. | row 14 |
| 15 | `lib/dispatch.h` ids | caught | Generated from `inc/Api.h` on every build and never saved; `.gitattributes` marks it `-merge`. | Unchanged. | row 15 |
| 16 | Debug menu numbers | caught | Each number is a `case` in one `switch` in `src/Debug.cpp`, so a duplicate fails to compile. The number is never saved, and key scripts choose entries by label, so a merge MAY pick one by hand (ruling 2026-11-12). | Unchanged. | row 16 |
| 17 | Saved-class pad rows | caught at landing | `tools/check_save_pad_rows.sh` failed when two branches each added a member. | Class sizes and pad tables are generated from the compiler's record layout. | row 17 |
| 18 | Parallel name tables (`ConstNam.h`, `src/Tables.cpp`) | caught | Two appends at one table end conflict as text. A missing row only changes a debug label. | Unchanged. | by git, not planted |
| 19 | File names: checks, key scripts, fixtures, tools | caught | The same path added on two branches is an add/add conflict. | Unchanged. | row 19 |
| 20 | `tools/fixtures/chars/MANIFEST` rows | caught | A row describes a `.char` file, and two branches that add one fixture name conflict on that file (row 19) and on the row. No tool reads the manifest for allocation. | Unchanged. | row 20 |
| 21 | `INCURSION_*` probe names | silent | Two branches could each add one name with two meanings; `tools/check_probe_hooks.sh` never tested uniqueness. | `tools/probe_names.txt` holds one sorted row per name with its owner bead; `tools/check_probe_names.py` refuses a name with no row, a stale row and a second row. | row 21 |
| 22 | Shared-tail text files (baselines, exemptions, retired-name lists, ledger rows) | caught | Two appends at one end conflict as text, and a duplicate line is harmless. | Unchanged. | row 22 |
| 23 | Names made from a bead id (`lib/landed-<bead>.irh`, branches, `docs/evidence/<bead>/`) | caught | `bd` issues each id once. | Unchanged. | by construction |

## Not allocation spaces

- **`gallery.dat`.** It is an array of raw `ReincarnationInfo` structs with no
  version, so a change to the struct misreads old records. That is format drift,
  not two branches taking one number. Bead inc-tq5kd tracks it.
- **Module-record blobs (`QCla` and the others in `inc/Res.h`).** No game save
  holds a module: modules save on the raw path (`Game::SaveModule`), never in a
  character save.

## Outside this inventory, by ruling

The pressure-test scope ruling of 2026-11-11 (bead inc-cjos0) leaves out cases
that need a deliberate trick to hide a declaration from the checks (a wrapper
macro, a conditional declaration, a same-spelling local), a change made on one
branch alone (a migration that keeps its name and changes its function), and a
number far beyond present content (the 12-bit spell and 8-bit module packing
ceilings).
