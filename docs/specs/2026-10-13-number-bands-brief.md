# Number bands and a shared allocator — brief (inc-24cc)

**Goal.** Two beads MUST NOT take the same new stati or event number, on the
same branch or on two branches. Today each session takes "highest on my branch
plus one", and the session that merges second renumbers (73e97822, fe6869f1,
62ffd244, 65fca8d7).

**Architecture.** Three parts.

1. **Bands.** A tracked table, `tools/number_bands.txt`, gives each long-lived
   branch its own range per family. A new number MUST fall inside the band of
   the branch the bead will land on.
2. **Allocator.** `tools/next_number.sh <family> <NAME>` prints the next free
   number in the caller's band. It keeps one counter file per family and band in
   `$(git rev-parse --git-common-dir)/incursion-numbers/`, which every worktree
   on this Mac shares. A lock directory (`mkdir`, as `tools/finish_bead.sh` does)
   serialises calls. The counter MUST NOT be a tracked file: a tracked counter
   conflicts at merge, which is the fault this bead removes.
3. **Check.** `tools/check_number_bands.sh`, run by `.beads/hooks/pre-commit`,
   refuses a staged `inc/Defines.h` that adds a constant in a covered family
   when the value is outside the branch's band, already used on the branch, or
   not issued by the allocator.

**Stack.** Bash and Python 3 stdlib only, like the other `tools/check_*.sh`.

## Settled decisions

- **Families.** Stati: every `#define NAME <int>` between `#define GENERIC_STATI`
  and `#define LAST_STATI` in `inc/Defines.h`, minus the non-stati families that
  sit inside that line range on the epic (`TG_*`, `SUBSPELL_*`,
  `COMPEL_WALK_STEP_MS`). Events: every `#define EV_NAME <int>`. No other family
  is covered. An alias MUST be written by name (`#define EV_X EV_Y`); the check
  ignores a define whose value is a symbol.
- **Bands.**

  | Family | master | inc-pu6v |
  |---|---|---|
  | Stati | 243–255 | 300–399 |
  | Events | 301–499 | 221–299 |

  Master's stati field is 8 bits wide (`inc/Res.h:323`, `Nature :8`), so a
  master stati MUST NOT exceed 255; stati 300 is stored as 44 (measured:
  `tools/check_seneschal.sh` fails with every tally 0). The epic widened the
  field to 16 bits (`inc/Res.h:324` on inc-pu6v), so the epic takes the high
  band. Master keeps `SENESCHAL_TALLY` 243. The epic's stati 243–260 move once
  to 300–317, in the next master-into-epic merge bead, which MUST show that the
  epic's save fixtures still load (a save stores a stati by number). That move
  is not part of this bead. Events keep their existing numbers on both branches.
  When the epic lands, master inherits the 16-bit field and its band row is
  rewritten by the landing bead.
- **Size limits.** A stati MUST fit its branch's `Nature` field: the check
  reads the width from `inc/Res.h` in the same tree and refuses a larger value.
  Stati stay low: each stati index is `LAST_STATI` entries
  (`src/Status.cpp:158`) and the save writes it whole (`inc/Map.h:825`). Events
  MUST stay below 2000, because `EVICTIM(a)` is `a+2000` (`inc/Defines.h:4537`).
- **Which band a bead uses.** `tools/worktree.sh` records the base branch with
  `git config branch.<bead>.incursionBase <base>`. The allocator and the check
  read it; a branch with no record uses master's band. On master or a
  `nightly/` branch the band is master's.
- **When a band ends.** Bands are tracked text. The next epic gets a new row,
  added by the bead that creates the epic. A band that fills makes the
  allocator exit non-zero with the family and band named; a session MUST NOT
  pick a number by hand to get around it.
- **Existing numbers** are grandfathered: the check looks only at lines the
  staged diff adds.

## Files touched

| File | Change |
|---|---|
| `tools/number_bands.txt` | New. The band table above. |
| `tools/next_number.sh` | New. The allocator; `--selftest` runs two concurrent calls and fails if they return the same number. |
| `tools/check_number_bands.sh` | New. The check; `--selftest` proves each refusal goes red. |
| `.beads/hooks/pre-commit` | Calls the check. |
| `tools/worktree.sh` | Records the base branch. |
| `tools/check_number_bands_tree.sh` | New. Runs the tree check in the fast set, which passes no arguments. |
| `tools/fast_checks.sh` set | Picks up the tree check by its `# gate-fast:` marker. |
| `tools/README.md` | One row each for the allocator and the checks. |

## Phases (one commit each)

1. Allocator, band table, `worktree.sh` record, allocator self-test. Verify: the
   concurrent self-test passes, and fails when the lock is removed.
2. The check and its pre-commit call. Verify: a mutation for each refusal
   (outside band, duplicate on branch, not issued) goes red; a legal addition
   stays green.
3. README rows; the swapped stati bands; the `Nature` width rule in the check
   and the allocator. Verify: a master stati of 256 is refused and 255 passes;
   an epic-tree stati of 300 passes; `tools/check_seneschal.sh` and
   `tools/check_char_fixture.sh` green with master's stati unchanged.

## Test plan

- Adversarial: two calls in parallel; a call with the lock left behind by a
  killed run; a band that is full; a branch with no base record; an `EV_` alias
  by value (refused) and by name (accepted).
- User path: a session in an epic worktree runs `next_number.sh EV EV_FOO`,
  adds the define, and commits.
- Live: run the check against the current master and `inc-pu6v` heads; both
  MUST be green with no change but phase 3.
