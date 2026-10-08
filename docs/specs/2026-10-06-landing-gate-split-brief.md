# Landing gate split: implementation brief

Goal: a short landing gate and a full nightly set with bisect.
Spec: `docs/specs/2026-10-06-landing-gate-split-spec.md` (approved 2026-10-06).
Bead: inc-t3iu, worktree `~/Scripts/Incursion-inc-t3iu`. Children inc-78y4 and
inc-3oii close with it.
Stack: bash (macOS bash 3.2 compatible, as the existing scripts are), git.
Implementer: DeepSeek through `tools/opencode_ds.sh`, one phase per run
(phases 1-10; 11 and 12 are Claude's).
Claude reviews each phase's diff and re-runs its checks before the next.

## Files touched

| File | Change | Phase |
|---|---|---|
| `tools/check_gate_membership.sh` | accept `smoke`; selftest case | 1 |
| `tools/nightly_verify.sh` | `smoke` tier in discovery, full runs, `--docs-only` skip (spec §3, §5.1) | 2 |
| four check files, `tools/gate_membership.baseline` | re-marks (spec §3) | 2 |
| `tools/nightly_verify.sh` | multi-flag parser (spec §4.1) | 3 |
| `tools/nightly_verify.sh` | `STEPS`/`LANDING_STEPS`; `--record` runs and records the steps (spec §4.2, §5.1) | 4 |
| `tools/nightly_verify.sh` | `--landing` order, changed-live set, fail-closed diff ref (spec §4.2-§4.3) | 5 |
| `tools/nightly_verify.sh` | pass-record `mode` (spec §4.4) | 6 |
| `tools/finish_bead.sh`, `tools/check_pass_record.sh` | routing, export, rewritten assertions (spec §4.1, §8) | 7 |
| `tools/nightly_verify.sh` | CPU-time slow-check note (spec §6) | 8 |
| `tools/nightly_bisect.sh`, `tools/check_nightly_bisect.sh` (new), `tools/README.md` row | bisect core and first cases (spec §5.2-§5.4, §8) | 9 |
| same two files | second pass, bead filing, report; remaining cases (spec §5.5-§5.7, §8) | 10 |
| `docs/VERIFICATION.md`, `tools/README.md` §7 | prose (spec §7); Claude writes | 11 |
| `~/Scripts/nightly-harness/projects/incursion.conf` | one line (spec §5.2); outside git; Claude edits with Brian's word | 12 |

## Phases

Each phase is one DeepSeek run and one commit on branch `inc-t3iu`. Every
brief names its line ranges and ends with the commands to run.

1. **Membership accepts `smoke`.** Implement: `check_gate_membership.sh`
   accepts `smoke` in its `case` (lines 71-83) and in every message that lists
   tiers; a selftest case where `smoke` passes and `bogus` fails. No check is
   re-marked yet. Verify: `tools/check_gate_membership.sh` exits 0; a mutation
   (drop `smoke` from the `case`) makes it red.

2. **`smoke` in full runs, then the re-marks.** Implement: discovery
   (`discover_checks`, lines 181-227) files `smoke` entries in their own list;
   `phase_entries` / `serial_phase_entries` accept `smoke`; `--docs-only` skips
   `smoke` as it skips `live` (line 213: `live` or `smoke`); `--compare` runs
   smoke after the builds, before live (parallel, then serial with the live
   serial phase); `--record` measures smoke and counts it for `record_live`.
   Only then re-mark the four files and remove `check_headless.sh` from
   `tools/gate_membership.baseline`, in the same commit, so no commit drops a
   check from the gate. Verify: `tools/nightly_verify.sh --selftest` exits 0,
   with a new case where a made-up `smoke` check runs under `--compare` and not
   under `--docs-only`; `check_gate_membership.sh` exits 0.

3. **Parser.** Implement: the parser (lines 130-151) reads every argument;
   only `--landing --reuse-pass` combines, other pairs exit 2. `--landing`
   parses and, in this phase only, behaves as `--compare`. Verify: selftest
   exits 0 with cases for the accepted pair and a rejected pair.

4. **Steps.** Implement: `STEPS` stays the full list; `LANDING_STEPS` holds the
   soak entry; `start_background_steps` / `wait_background_steps` (lines
   574-607) take the array to use (bash 3.2: no namerefs). `--record` (lines
   1114-1164) builds whenever it will run the steps, runs the full `STEPS`
   after the checks, and writes one `<rc>\t<step script>` line each; a step
   never aborts `--record`. Verify: selftest exits 0; under the selftest the
   steps are stubbed and `--record` writes their lines.

5. **`--landing` body.** Implement spec §4.2-§4.3: order (cheap; builds; soak
   in background; non-serial smoke + changed live in parallel; wait; serial
   smoke then serial changed live); changed-live set from
   `git diff --name-only "$INCURSION_LANDING_DIFF_REF"...HEAD`, tier read from
   the tree; exit 2 when the variable is unset, does not resolve, or the diff
   fails. Selftest cases in a throwaway git repository. Verify: selftest exits
   0; mutation (the changed-live filter returns every live check) turns a case
   red.

6. **Pass-record `mode`.** Implement spec §4.4: `--landing` sets `FULL_RUN=1`
   on a fresh run; `mode` written by `write_pass_record` and matched by
   `pass_matches` (lines 714-764); `--landing --reuse-pass` reuses only
   `landing`, `--reuse-pass` only `full`; no `mode` means stale. Verify:
   selftest cases for each reuse rule; mutation (ignore `mode` in
   `pass_matches`) turns one red.

7. **`finish_bead.sh` and `check_pass_record.sh`.** Implement: default
   `GATE_CMD` `--landing`; verdict 1 -> `--landing --reuse-pass`; export
   `INCURSION_LANDING_DIFF_REF="$BASE_BRANCH"` in the gate subshell;
   `INCURSION_FINISH_GATE` untouched. Rewrite `check_pass_record.sh`'s
   assertions per spec §8 (rewrite, never delete one). Verify:
   `tools/check_pass_record.sh` exits 0; mutation (`--landing` -> `--compare`
   in `finish_bead.sh`) turns it red; the other `tools/check_finish_bead*.sh`
   checks still pass.

8. **CPU-time note.** Implement spec §6 in `run_check` (lines 296-310) and
   `print_verdict` (lines 337-376): `/usr/bin/time -p -o <side file>`; serial
   cheap: wall-clock > 30 s; parallel cheap: user + sys > 30 s; unreadable side
   file falls back to wall-clock. The check's exit code and log are unchanged.
   Verify: selftest case with a made-up parallel cheap check that sleeps 35 s
   gets no note, and one that burns CPU for 35 s gets the note (or a scaled
   threshold variable for the selftest so it costs seconds, not minutes).

9. **Bisect core.** New `tools/nightly_bisect.sh` (`# gate: none` with a
   reason: run by the harness) and `tools/check_nightly_bisect.sh`
   (`# gate: cheap`). Implement spec §5.2-§5.4: per-night copy, last-good file,
   30-night prune, candidates, ancestor check, one step in a detached temporary
   worktree with trap cleanup, absent check or failed build -> 2, halving,
   confirmation re-runs, budget. Build and run are functions that the check can
   replace through environment variables (for example
   `NIGHTLY_BISECT_BUILD_CMD`, `NIGHTLY_BISECT_RUN_CMD`), so the check needs no
   game build. Check cases: single cause named; absent-at-early-commit not
   blamed; G not an ancestor names nothing; flaky inconsistent; budget 0.
   Verify: the check exits 0; mutation (halving picks the wrong half) turns it
   red.

10. **Bisect second pass and report.** Implement spec §5.5-§5.7: revert at T,
   second bisect with L reverted, at most three causes, revert conflict at any
   point -> not measured; bead filing through `tools/bead_new.sh` (replaceable
   by `NIGHTLY_BISECT_BEAD_NEW` for the check) with the label rule and text;
   exit 3 -> note on the top candidate via a replaceable `bd` command; report
   file; exit 0 except unreadable state (2). Check cases: two causes named;
   revert conflict; duplicate path files nothing and notes the candidate; the
   label rule picks `public` for a `src/` landing and `internal` for a
   `tools/` one. Verify: the check exits 0; mutation (remove the second pass)
   turns it red.

11. **Docs (Claude).** `docs/VERIFICATION.md` "The landing gate" and
   `tools/README.md` §7 per spec §7, with rows for `check_nightly_bisect.sh`
   and `nightly_bisect.sh`. Verify: the cheap tier passes (its doc checks read
   both files).

12. **Harness line and measurement (Claude).** Brian's word first, then add
    `; tools/nightly_bisect.sh` to `VERIFY_RECORD_CMD`. Land with
    `tools/finish_bead.sh inc-t3iu`; it runs the new landing gate on this
    `tools/`-only bead. Record the measured wall-clock of a landing gate in
    `docs/VERIFICATION.md` (a follow-up commit if the landing itself is the
    first measurement).

## Test plan

- Adversarial: the selftest and `check_nightly_bisect.sh` cases above (fail
  closed on a missing diff ref, a non-ancestor G, an absent check, a flaky
  check, a revert conflict, a zero budget, a stale pass record).
- Mutation per phase, named in each phase.
- User path: one real `--landing` run in the worktree with
  `INCURSION_LANDING_DIFF_REF=master`, timed; one real `--record` against a
  scratch `NIGHTLY_VERIFY_STATE`; one real `tools/nightly_bisect.sh` run against
  a scratch state directory with a hand-made last-good file that points two
  landings back for one cheap check.
- Before landing: `tools/nightly_verify.sh --compare` (full) passes in the
  worktree, so nothing that passed on master breaks under the old gate either.
