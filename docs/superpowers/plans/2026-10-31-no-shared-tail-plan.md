# No shared tail: implementation brief

Bead: inc-mhn1w. Sized: Medium. Spec (read it first, it is the authority):
`docs/superpowers/specs/2026-10-31-no-shared-tail-design.md`. Cut down to
resources on 2026-11-01: no change to `inc/Defines.h`, `src/Tables.cpp` or
`inc/ConstNam.h` layout, and no change to `tools/next_number.sh`.

**Goal:** branches that add resources merge without conflicts, master's save
positions never move, and an implementer needs to know only "new resources go
in `lib/landed-<bead>.irh`".

**Architecture:** per-bead landed files plus a git merge driver for
`lib/landed.irc`; the resource ledger recorded only by `tools/finish_bead.sh`
and always merged from master; a duplicate-value check for every
`inc/Defines.h` family.

**Stack:** bash and Python 3 (stdlib only), git merge drivers, the existing
headless build (`BACKEND=posix ./build_macos.sh`).

**Execution:** route each phase by the coding row of
`.claude/rules/codex-dispatch-and-orchestration.md`. Run
`tools/claude_budget.py` and `bd memories out-until` before EACH coding
dispatch. Work happens in the worktree `~/Scripts/Incursion-inc-mhn1w`.
Claude reviews each diff and commits it before the next phase. Every new
check carries a `--selftest`, a header `# fact:` list per AGENTS.md, and is
shown red before green.

## Files touched

| File | Change |
|---|---|
| `tools/merge_landed.py` | New. Two modes, `landed` and `landed-ledger` (spec 4.2, 4.4). |
| `.gitattributes` | Two lines: `lib/landed.irc merge=landed`, `tools/resource_order.ledger merge=landed-ledger`. |
| `tools/worktree.sh` | Sets `merge.landed.driver` and `merge.landed-ledger.driver` on every run, BEFORE the early exit for an existing worktree (`:327`). |
| `lib/landed.irc` | New, empty. |
| `lib/main.irc` | One new last line, `#include "landed.irc"` (spec 4.1). |
| `tools/check_landed_files.py` | New (spec 4.1, enforcement). |
| `.beads/hooks/pre-commit` | Runs `check_landed_files.py` and `check_define_dups.py`; drops the `--require-recorded` block at lines 243-266. Line 241, the order guard, STAYS. |
| `build_macos.sh` | Lines 415-418 record the ledger only when `tools/finish_bead.sh`'s gate build sets an environment variable. |
| `tools/finish_bead.sh` | STEP 3 refuses without driver config; STEP 3b runs `check_define_dups.py`; commits the ledger after STEP 4 only when it changed; STEP 4b reads master's ledger; runs `check_landed_files.py` after STEP 4b. |
| `tools/check_define_dups.py`, `tools/define_dups.baseline` | New (spec 4.5). |
| `tools/check_no_shared_tail.sh` | New scenario check for AC1, scratch clones under `logs/`. |
| `tools/opencode/brief_preamble.md` | One line: new resources go in `lib/landed-<bead>.irh`. |
| `tools/README.md` §7 | One row per new check in its tier. |

## Phases (one commit each, lane `tools:`)

1. **Merge driver.** Write `tools/merge_landed.py`, the `.gitattributes`
   lines and the `tools/worktree.sh` config. Selftest runs `git merge` in
   scratch repos under `logs/`: two branches append different include lines,
   the result has master's lines first; a malformed line exits 1 and leaves
   a conflict (AC5); ledger mode outputs master's copy in both merge
   directions; with the driver unconfigured, two appends conflict.
2. **Landed files.** Add `lib/landed.irc` and the `lib/main.irc` line; build;
   confirm `tools/check_resource_order.sh` and
   `tools/check_v1_append_survives.sh` pass unchanged. Write
   `tools/check_landed_files.py` and wire it into `.beads/hooks/pre-commit`.
   It matches a resource as a quoted string and a module-level script
   variable as a whole-word identifier. Its refusal message names the file
   to use. Red: a new effect declared in `lib/mundane.irh` on a scratch
   branch named for a bead is refused; green: the same effect in its landed
   file passes (AC3). Red: a landed file with no include line in
   `lib/landed.irc` is refused; green: the line added (AC2). Exit 2 on a
   branch name that is not a bead id. Add the brief preamble line.
3. **Ledger flow.** Change `build_macos.sh:415-418` and
   `tools/finish_bead.sh` (STEP 3 config refusal, ledger commit after STEP 4
   only on a diff, STEP 4b on master's ledger, the landed-files check after
   STEP 4b); drop pre-commit lines 243-266. Verify with
   `tools/check_finish_bead_lock.sh` and any other finish_bead selftest the
   gate runs. Red cases: STEP 3 refuses when `merge.landed.driver` is unset;
   an ordinary build leaves `tools/resource_order.ledger` unmodified.
4. **Duplicate check.** Write `tools/check_define_dups.py` and the baseline
   from master today. Red: a scratch copy of `inc/Defines.h` with a new stati
   at 234 fails; green: master passes (AC4). Exit 2 on an expression it
   cannot evaluate. A new nested sub-define inside the stati block reads as a
   duplicate; that is accepted. Wire it into STEP 3b and pre-commit.
5. **Scenario check.** Write `tools/check_no_shared_tail.sh`: in a scratch
   clone under `logs/`, two branches each add one effect in their own landed
   file and merge with no conflict, both effects after every master position,
   `tools/check_resource_order.sh` green (AC1). Red: the same scenario with
   both effects appended to `lib/mundane.irh` conflicts. Add the
   `tools/README.md` rows.
6. **Landing.** File the epic reconciliation bead (spec section 7) first.
   Run `tools/worktree.sh inc-mhn1w` once so the repository has the driver
   config. Claude runs the four checks implementers may not run, then
   `tools/finish_bead.sh inc-mhn1w` (AC6). From this landing until the
   reconciliation bead lands, every landing into the epic is refused (spec
   R6); that is expected.

## Test plan

- Adversarial: driver with an empty file, a duplicate line, CRLF, a line
  with trailing spaces, an unreadable master copy; dups check on `|`, `<<`
  and nested expressions; landed check on a Flavor name that appears twice.
- User path: the AC1 scenario check, run as a session would (worktree,
  finish_bead merge step).
- Live data: the phase 2 build against the real module; the phase 6 gate.
