<!-- citations: this-port -->

# Brief: remove the lying pipeline status (inc-mwjc)

**Goal.** A `grep -q` that finds its match must never be reported as "no
match". Convert the 44 status-consuming early-exit pipelines in the 15
gate-declared check scripts, and add a ratcheting guard so the shape cannot
come back.

**Spec.** `docs/specs/2026-09-22-sigpipe-status-spec.md`. Read §3 before
touching a line; it holds the five transform rules and the one precondition.

**Stack.** bash only. No C++, no module rebuild, no game behaviour.

**Lane.** `tools:`.

## Files touched

| file | what happens |
|---|---|
| `tools/check_sigpipe_status.sh` | NEW. The guard. Scan plus selftest in one run. Spec §4. |
| `tools/sigpipe_status.baseline` | NEW. Per-file counts, `LC_ALL=C` sorted. |
| `tools/README.md` | NEW ROW under `### The regression checks`, or `check_readme_checks.sh` refuses the landing. |
| `tools/check_upstream_marks.sh` | 11 sites: 130, 133, 134, 280, 297, 325, 482, 483, 484, 485, and `hit_is_negated` at 151. All R1. |
| `tools/check_readme_checks.sh` | 4 sites: 107, 109, 111, 113. All R1. |
| `tools/check_citations.sh` | 4 sites: 242, 250, 296, 529. R5 for 242, 250 and 529, R3 for 296. Line 255 MUST NOT change. `path_in_ref` at 242 is the site that opened this bead. |
| `tools/check_commit_lane.sh` | 4 sites: 54, 58, 59, and `is_exempt` at 120. All R1. This is the `commit-msg` hook. |
| `tools/check_error_handling.sh` | 3 sites: 32, 39, 46. All R4. The only false-PASS direction. |
| `tools/check_key_directives.sh` | 3 sites: 46, 54, 64. All R1. |
| `tools/check_reapply_single_grant.sh` | 3 sites: 36, 41, 47. All R1. |
| `tools/check_prestige_tables.sh` | 2 sites: 44, 84. All R1. |
| `tools/check_breath_dice.sh` | 1 site: 64. R1. |
| `tools/check_erich_speaks.sh` | 1 site: 42. R1. Pattern takes `$msg`; spec §3.6. |
| `tools/check_orphan_branches.sh` | 4 sites: 149, and `is_grandfathered` 66, `has_worktree` 76, `is_bead_id` 80. All R1. |
| `tools/check_readline_overflow.sh` | 1 site: 71. R3. |
| `tools/check_rules_channel.sh` | 1 site: 162. R1. |
| `tools/check_sentinel_live.sh` | 1 site: 55. R1. |
| `tools/check_virtual_override.sh` | 1 site: 374. R1. Pattern takes `$2`; spec §3.6. |

Untracked, under `docs/evidence/inc-mwjc/`: `equiv_test.sh`, `before/`,
`after/`, `README.md`.

## Phases

**P1 -- the guard, proved red before it is trusted.**
Write `tools/check_sigpipe_status.sh` to spec §4.1-§4.3. Record
`tools/sigpipe_status.baseline` on the UNCONVERTED tree; the 38 gate-declared sites
MUST be exactly the list hand-verified in the spec's §2.2 table; the total over
all of `tools/` is whatever `--record` measures and is not predicted here. Then prove each selftest case fails for the right
reason before it passes. Add the `tools/README.md` row. Run
`tools/check_readme_checks.sh` and `tools/check_gate_membership.sh` green.
Commit.

**P2 -- capture the before-state.**
For each of the nine cheap-tier scripts record stdout, stderr and exit status
into `docs/evidence/inc-mwjc/before/`. For the six live-tier scripts record one
run each, exit status and normalised output; spec §5.2 says why bytes cannot
match. For the seven with a `--selftest`, record the
selftest output too. Nothing is edited in this phase. No commit; the directory
is untracked.

**P3 -- convert the nine cheap-tier scripts.**
`check_upstream_marks`, `check_readme_checks`, `check_citations`,
`check_commit_lane`, `check_error_handling`, `check_erich_speaks`,
`check_orphan_branches`, `check_rules_channel`, `check_virtual_override`.
Apply the rule named per row above and nothing else -- no reflow, no renaming,
no comment rewriting, because an unrelated whitespace change hides the real
diff. Re-record the baseline. Commit.

**P4a -- widen the guard to the function-final class.**
Add rule (e) of spec §4.1 and the tenth selftest case. The guard then flags
every pipeline that is a function's last statement, which is the class it was
blind to. Re-record the baseline; the four value-position cases named in §2.3
join the backlog. Commit.

**P4 -- convert the six live-tier scripts.**
`check_key_directives`, `check_reapply_single_grant`, `check_prestige_tables`,
`check_breath_dice`, `check_readline_overflow`, `check_sentinel_live`.
Re-record the baseline; the 15 converted files must now read 0. Commit.

**P5 -- the three test classes, spec §5.**
Write `docs/evidence/inc-mwjc/equiv_test.sh` and run it. Run `--stress` and
require red-and-green in one run. Capture the after-state and diff it against
P2. Prove `check_error_handling.sh` still goes red with a planted
`sprintf(__buff2`. Write `docs/evidence/inc-mwjc/README.md`. Commit the guard's
final baseline if it moved.

**P6 -- the gate.**
`tools/nightly_verify.sh --compare` green in the worktree.

## Test plan

- **Adversarial.** The guard's eight selftest cases, spec §4.3, each proved red
  first. The equivalence harness's four inputs per site, spec §5.3, including
  the last-line case that is the only way the added `<<<` newline could bite.
- **The fix itself.** `--stress` under generated load. A run that shows only
  green is INCONCLUSIVE, not a pass -- it means the load generator failed.
- **No regression.** Byte-identical before/after output for the nine cheap-tier
  scripts and for all seven selftests; same verdict and normalised output for
  the six live-tier scripts.
- **The errors are still caught.** Planted `sprintf(__buff2` turns
  `check_error_handling.sh` red, and removing it turns it green.
- **Live data.** `tools/nightly_verify.sh --compare`, which is what
  `tools/finish_bead.sh` runs before it merges.

## What Codex must not do

- Do not change `tools/check_citations.sh:255`. Its reader has no `-q` and its
  value, not its status, is used.
- Do not convert a `| head` in value position. Spec §2.3 names the four and
  says why. A pipeline that is a function's LAST statement IS in scope when a
  caller reads its status; §2.3 lists the six.
- Do not widen the scope to the non-gate sites. They belong on the baseline.
- Do not delete or weaken any existing check, guard or selftest case to make a
  conversion fit. If one blocks you, stop and report it with its file and line.
- Do not run git. Do not run `bd`. Leave every change in the working tree.
