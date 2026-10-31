# No shared tail: implementation brief

Bead: inc-mhn1w. Sized: Medium. Spec (read it first, it is the authority):
`docs/superpowers/specs/2026-10-31-no-shared-tail-design.md`.

**Goal:** remove the shared tail so branches that add resources, stati or
events merge without conflicts, and master's save positions stay guarded.

**Architecture:** per-bead landed files plus a git merge driver for
`lib/landed.irc`; placeholder lines for stati and events renamed in place by
the existing allocator; the resource ledger recorded only by
`tools/finish_bead.sh` and always merged from master; a duplicate-value check
for every `inc/Defines.h` family.

**Stack:** bash and Python 3 (stdlib only), git merge drivers, the existing
headless build (`BACKEND=posix ./build_macos.sh`).

**Execution:** route each phase by the coding row of
`.claude/rules/codex-dispatch-and-orchestration.md`. Run
`tools/claude_budget.py` before EACH coding dispatch: exit 0 (`sonnet-first`)
sends the phase to an Agent dispatch with `model: "sonnet"` and the `budget:`
label; otherwise DeepSeek through `~/Scripts/Incursion/tools/opencode_ds.sh`,
then Haiku 5.5+, then `sonnet`, then `opus`. Never Codex for coding. Check
`bd memories out-until` before each dispatch. Work happens in the worktree
`~/Scripts/Incursion-inc-mhn1w`. Claude reviews each diff and commits it
before the next phase. Every new
check carries a `--selftest`, a header `# fact:` list per AGENTS.md, and is
shown red before green.

## Files touched

| File | Change |
|---|---|
| `tools/merge_landed.py` | New. Two modes, `landed` and `landed-ledger` (spec 4.2, 4.4). |
| `.gitattributes` | Two lines: `lib/landed.irc merge=landed`, `tools/resource_order.ledger merge=landed-ledger`. |
| `tools/worktree.sh` | Sets `merge.landed.driver` and `merge.landed-ledger.driver` on every run (spec 4.2). |
| `lib/landed.irc` | New, empty. |
| `lib/main.irc` | One new last line, `#include "landed.irc"` (spec 4.1). |
| `tools/check_landed_files.py` | New (spec 4.1, enforcement). |
| `.beads/hooks/pre-commit` | Runs `check_landed_files.py` and `check_define_dups.py`; drops the `--require-recorded` block at :241-266 (spec 4.4). |
| `tools/finish_bead.sh` | STEP 3 refuses without driver config; STEP 3b runs `check_define_dups.py`; commits the recorded ledger after STEP 4; STEP 4b reads master's ledger; runs `check_landed_files.py` after STEP 4b (spec 4.2, 4.4). |
| `inc/Defines.h`, `src/Tables.cpp`, `inc/ConstNam.h` | Placeholder lines and rows, `LAST_STATI` 256 (spec 4.3). |
| `tools/next_number.sh` | Renames the issued placeholder in place; refuses when absent; selftest fixture updated (spec 4.3). |
| `tools/check_define_dups.py`, `tools/define_dups.baseline` | New (spec 4.5). |
| `tools/check_no_shared_tail.sh` | New scenario check for AC1 and AC2, scratch clones under `logs/`. |
| `tools/README.md` §7 | One row per new check in its tier. |

## Phases (one commit each, lane `tools:` unless noted)

1. **Merge driver.** Write `tools/merge_landed.py`, the `.gitattributes`
   lines and the `tools/worktree.sh` config. Selftest runs `git merge` in
   scratch repos under `logs/`: two branches append different include lines,
   the result has master's lines first; a malformed line exits 1 and leaves
   a conflict (AC5); ledger mode outputs master's copy in both merge
   directions.
2. **Landed files.** Add `lib/landed.irc` and the `lib/main.irc` line; build;
   confirm `tools/check_resource_order.sh` and
   `tools/check_v1_append_survives.sh` pass unchanged. Write
   `tools/check_landed_files.py` and wire it into `.beads/hooks/pre-commit`.
   Red: a new effect declared in `lib/mundane.irh` on a scratch branch named
   for a bead is refused; green: the same effect in its landed file passes
   (AC3). Exit 2 on a branch name that is not a bead id.
3. **Ledger flow.** Change `tools/finish_bead.sh` (STEP 3 config refusal,
   ledger commit after STEP 4, STEP 4b on master's ledger, the landed-files
   check after STEP 4b) and drop the pre-commit `--require-recorded` block.
   Verify with the existing `tools/check_finish_bead_lock.sh` and any other
   finish_bead selftest the gate runs; add a red case: STEP 3 refuses when
   `merge.landed.driver` is unset.
4. **Duplicate check.** Write `tools/check_define_dups.py` and the baseline
   from master today. Red: a scratch copy of `inc/Defines.h` with a new stati
   at 234 fails; green: master passes (AC4). Exit 2 on an expression it
   cannot evaluate. Wire it into STEP 3b and pre-commit.
5. **Placeholders and allocator.** Add the placeholders (stati 251-255, EV
   301-320, blank line between each, matching table rows, `LAST_STATI` 256);
   change `tools/next_number.sh` to rename in place and update its selftest.
   Build; the gate's fast set passes. Lane `port:` (source change with no
   player-visible behavior).
6. **Scenario check.** Write `tools/check_no_shared_tail.sh`: in a scratch
   clone under `logs/`, two branches each add one effect in their own landed
   file and merge with no conflict, both effects after every master position,
   `tools/check_resource_order.sh` green (AC1); two branches each take a
   stati through `tools/next_number.sh` (pointed at a scratch counter dir)
   and merge with no conflict in `inc/Defines.h` and `src/Tables.cpp` (AC2).
   Red: the same scenario with both effects appended to `lib/mundane.irh`
   conflicts. Add the `tools/README.md` rows.
7. **Landing.** Claude runs the four checks implementers may not run, then
   `tools/finish_bead.sh inc-mhn1w` (AC6). The follow-up epic
   reconciliation bead (spec section 7) is filed before landing.

## Test plan

- Adversarial: driver with an empty file, a duplicate line, CRLF, a line
  with trailing spaces, an unreadable master copy; dups check on `|`, `<<`
  and nested expressions; landed check on a Flavour name that appears twice.
- User path: the AC1/AC2 scenario check, run as a session would (worktree,
  allocator, finish_bead merge step).
- Live data: phase 2 and 5 builds against the real module; phase 7 gate.
