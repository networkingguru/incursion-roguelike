# Landing gate split: a short gate per landing, the full set nightly with bisect

Bead: inc-t3iu (epic). Children: inc-78y4 (Linux cross-build and layout sweep
to nightly), inc-3oii (slow cheap checks). Every decision below was ruled by
Brian on 2026-10-06; the rulings are in the notes of inc-t3iu.

## 1. Problem

Measured 2026-10-06 on the epic tip, quiet machine: one landing gate took 926 s.
Every landing runs every check: the cheap tier (244 s, measured again in the
inc-t3iu worktree on master d264bb27), both builds, 104 live checks (about 100
headless sessions), the Linux cross-build (329 s), the layout sweep (382 s) and
the soak (81 s, one core). The load average reached 107 on 10 cores.

## 2. Goal

A landing runs a short gate. The nightly run executes the full set. When a
check passed on its last good night and fails now, the nightly bisects the
landings since then and names the landing that broke it.

Accepted cost: a defect that only the nightly set catches can stay on master
until the next night.

## 3. Tiers

`# gate:` gets a fourth value. The four values and where each runs:

| Marker | Meaning | Landing | Nightly |
|---|---|---|---|
| `cheap` | no build, no play, seconds | yes | yes |
| `smoke` | plays the game briefly | yes | yes |
| `live` | plays the game | only when the bead changes the check file (§4.3) | yes |
| `none <reason>` | no gate | no | no |

`# gate-serial:` and `# gate-fast:` keep their meaning in every tier.

Re-marks:
- `tools/check_headless.sh`: no marker today (it is on the grandfather list in
  `tools/gate_membership.baseline`, so no gate runs it) -> `smoke`. Its line
  leaves the baseline file.
- `tools/check_char_fixture.sh`: `live` -> `smoke`.
- `tools/check_watchdog.sh` (80 s) and `tools/check_opencode_ds.sh` (64 s):
  `cheap` -> `live`. Both keep `gate-serial`.

`tools/check_gate_membership.sh` accepts `smoke` and names it in every message
that lists the tier values.

## 4. The landing gate

### 4.1 Mode

`tools/nightly_verify.sh --landing` is the landing gate. `tools/finish_bead.sh`
uses it where it uses `--compare` today (its default `GATE_CMD`).

`finish_bead.sh` picks one of three gate commands from the
`tools/docs_only_change.sh` verdict (`finish_bead.sh:436-437`). After this
work:

| Verdict | Today | After |
|---|---|---|
| 0, docs only | `--docs-only` | `--docs-only` (unchanged) |
| 1, reusable | `--reuse-pass` (falls back to a full `--compare`) | `--landing --reuse-pass` (falls back to `--landing`) |
| 2 or other | `--compare` | `--landing` |

The argument parser today reads one flag (`case "${1:-}"`). It changes to read
every argument. `--landing` combines with `--reuse-pass` only; any other
combination exits 2. `--reuse-pass` alone keeps its meaning (a full run). An
explicit `INCURSION_FINISH_GATE` is honoured untouched, as today.

To keep one word for one thing: the variable is `INCURSION_LANDING_DIFF_REF`,
not "base". In `nightly_verify.sh`, "base" keeps its one meaning, the ratchet's
recorded state file.

`finish_bead.sh` exports `INCURSION_LANDING_DIFF_REF="$BASE_BRANCH"` before it runs
the gate command, in the same subshell. For an epic landing
(`INCURSION_BASE_BRANCH=<epic>`) the base is the epic.

### 4.2 Order

1. The cheap tier, parallel then serial, stop on a failure. Unchanged.
2. Both builds (`BUILDS`: headless, then SDL). Unchanged.
3. The soak (`tools/gate_compare.sh`) in the background.
4. The non-serial `smoke` checks and the non-serial changed `live` checks
   (§4.3), through the parallel runner, beside the soak.
5. Wait for the soak.
6. The serial `smoke` checks, then the serial changed `live` checks, alone.
   A serial check needs nothing else running, so it waits for the soak.

The Linux cross-build and the layout sweep do not run (inc-78y4). The
`STEPS` array splits in two: `LANDING_STEPS` holds the soak only, and the full
run uses all three. `start_background_steps` and `wait_background_steps` take
the array to use.

### 4.3 The bead's own checks

A `live` check runs at landing when the bead's diff adds or changes its file.
The set is `git diff --name-only <base>...HEAD` filtered to discovered check
files whose tier is `live`. `<base>` is the base branch that `finish_bead.sh`
already knows (`$BASE_BRANCH`); it passes it in `INCURSION_LANDING_DIFF_REF`.

Fail closed: with `--landing`, an unset `INCURSION_LANDING_DIFF_REF`, a ref that does
not resolve, or a failed `git diff` exits 2 (could not measure). The gate never
treats "could not list the changes" as "no changes".

The tier is the marker in the tree under test, not the marker at the base. A
deleted check file is not run. A changed `none` check is not run. A `cheap` or
`smoke` check already runs.

### 4.4 Pass record

The pass record gains a `mode` field (`landing` or `full`), written by
`write_pass_record` and read by `pass_matches`. A passing `--landing` run
(not a reused one) sets `FULL_RUN=1` for this purpose and writes
`mode landing`; a passing `--compare` writes `mode full`.
`--landing --reuse-pass` reuses only a `landing` record; `--reuse-pass` alone
reuses only a `full` record. A record with no `mode` field is treated as stale
(fail closed).

### 4.5 Ratchet

A landing has no recorded base today, so every check it runs must pass
outright. That stays.

## 5. The nightly run

### 5.1 What runs

`--record` and `--compare` (no flag) are the full set: cheap, builds, smoke,
every live check, and the three big steps (Linux cross-build, layout sweep,
soak).

`--record` today records no big step ("they are verdicts on the tree"). That
changes: `--record` runs the three steps and writes one state line for each,
with the step script as the id (for example `tools/check_linux_build.sh`), with
the same exit-code meaning as a check (0 pass, 2 could not measure, else fail).
`--record` builds today only when a live check exists (`record_live`). The
steps run after the checks, so `--record` now always builds when it will run
the steps, which is always outside `--selftest`. The selftest keeps its
no-build path by stubbing the step list.

A step that fails or cannot run writes its exit code on its line; it never
aborts `--record` and never deletes the state file. Only a failed build does
that, as today. `--compare` continues to judge the steps absolutely, as today.

### 5.2 Per-night results

A new script, `tools/nightly_bisect.sh`, runs after `--record`. The harness
calls it: `VERIFY_RECORD_CMD` in
`~/Scripts/nightly-harness/projects/incursion.conf` gains
`; tools/nightly_bisect.sh` (the only harness change).

It keeps its records beside `$NIGHTLY_VERIFY_STATE`:

- `nightly-results/<YYYY-MM-DD>-<commit>.tsv`: a copy of tonight's state file,
  with the master commit it measured on its first line.
- `nightly-last-good.tsv`: per check, the last commit where it exited 0.

A check that has no line in `nightly-last-good.tsv` (a new check, or the first
night) is recorded and not bisected.

### 5.3 Newly failing

For each check that exits non-0 and non-2 tonight and has a last-good commit G
different from tonight's commit T: the candidates are
`git rev-list --first-parent --reverse G..T`.

Fail closed: when `git merge-base --is-ancestor G T` fails, or G does not
resolve, the check is reported "not measured" and nothing is named. The
harness makes T the tip of master today, but this script does not trust that.

A check id that has not appeared in tonight's state file for 30 nights is
dropped from `nightly-last-good.tsv` (a renamed or deleted check). A check that exits 2 tonight is
not bisected; the report names it as not measured.

### 5.4 One bisect step

To test commit X for check C: `git worktree add --detach <tmp> X`; build what C
needs (nothing for `cheap`, the headless build for `smoke`/`live`, the step's
own build for a big step); run C there with the same environment the gate gives
it; read 0 as pass, 2 as could not measure, else fail. Every file the check
reads comes from X's own checkout, settings files (`tools/gates/Options.Dat`,
`tools/fixtures/`) included; nothing is copied from T.

When C's file does not exist at X, or C's build fails at X, the step reads 2
(could not measure). An absent check is never a failure. Remove the worktree
whatever the result. The temporary directory is under `$TMPDIR`.

A step that reads 2 stops the bisect for C. The report gives the narrowed
range and says "not measured", and names no landing.

Test the candidates by halving. The first candidate where C fails, after a
candidate where it passes (or after G), is the guilty landing L.

Confirmation against a flaky check: before L is named, C runs again at L
(MUST fail) and at L's first parent (MUST pass). If either run disagrees with
the halving, the report says "inconsistent results, possibly flaky; not
measured" with the range, and names nothing.

Time budget: the whole script stops starting new bisect steps after
`INCURSION_BISECT_BUDGET` seconds (default 5400, 90 minutes). Every check not
finished then is reported "time budget exceeded; not measured" with its
narrowed range. Checks are bisected in a fixed order: big steps last, because
each of their steps costs minutes.

### 5.5 Second pass

After L is named: build T with L's merge reverted (`git revert --no-edit -m 1 L`
in the temporary worktree; for a non-merge commit, no `-m`) and run C.

- C passes: L is the only cause. The report says so.
- C fails: a second cause exists. Bisect the candidates after L, with L
  reverted at each step, by the same rules. Name the second landing L2. Repeat
  for L2 at most once more (three causes found in total at most); beyond that,
  report "more causes may exist; not measured".
- The revert does not apply cleanly, at T or at any candidate of the second
  bisect: report "a second cause may exist; not measured" with the range
  reached. Do not guess.

### 5.6 Report

For each named landing, file a bead through `tools/bead_new.sh` (never bare
`bd create`).

- Label `public` when the landing's merge changed a file under `src/`, `inc/`
  or `lib/`; otherwise `internal`.
- Type `bug`, priority P1.
- Title: `Nightly: <check> broke at landing <landing bead id or short commit>`.
- Description holds facts only: the check; the landing (bead id from the merge
  subject when it names one, merge commit, subject); the last good commit;
  tonight's commit; the second-pass result. Then `## Steps to Reproduce` (build
  the last good commit and the landing commit, run the check on each) and
  `## Acceptance Criteria` (the check passes at the tip of master).
- `bead_new.sh` exit 3 (likely duplicate, judged by Jev): file nothing; append
  a dated note naming the check and landing to the candidate with the highest
  probability (the first one `bead_new.sh` prints, on a tie). If no candidate
  id can be read from its output, file nothing and write the case to the
  report file as "duplicate suspected; candidate unknown". Never pass
  `--not-a-duplicate`.
- Jev not available: `bead_new.sh` files the bead and marks the duplicate check
  skipped. Nothing more.

Every result (named, only cause, second cause, not measured) also goes to a
dated report file beside the records, `nightly-bisect/<YYYY-MM-DD>.md`.

### 5.7 Failure handling

`tools/nightly_bisect.sh` never blocks the night's work: whatever happens, it
exits 0 after writing its report, unless it could not read the state file at
all (exit 2). It never changes master and never pushes. Each temporary worktree
is removed on exit, including on a signal.

## 6. Cheap-tier timing note

The note "A cheap check should cost seconds" is printed today when a cheap
check takes more than 30 s of wall-clock in the gate. Parallel checks inflate
under contention (`check_commit_lane.sh`: 17 s alone, 33 s in the gate).

New rule: a serial cheap check gets the note above 30 s wall-clock (it runs
alone, so wall-clock is its own cost). A parallel cheap check gets the note
when its CPU time (user + system of the check and its children) exceeds 45 s
(`NIGHTLY_CHEAP_CPU_LIMIT`; ruled 2026-10-06 after three checks measured 32 to
33 s of CPU and 18 to 20 s of wall-clock).

`run_check` measures CPU time by running the check under `/usr/bin/time -p`
with `-o <side file>` beside the check's log in `$LOG_DIR`. The check's own
output and exit code are unchanged. When the side file is missing or does not
parse, the note falls back to the 30 s wall-clock rule (no silent pass).

## 7. Documentation

- `docs/VERIFICATION.md`, section "The landing gate": the split, the four
  tiers, where each step runs, and the landing gate's measured wall-clock time
  before and after.
- `tools/README.md` §7: the tiers and where each one runs; rows for every new
  check and script.

## 8. Checks this work leaves behind

- `tools/nightly_verify.sh --selftest` gains cases: a `smoke` check runs under
  `--landing`; an unchanged `live` check does not; a changed `live` check does;
  `--landing` with no base exits 2; a `landing` pass record is not reused for a
  full run. The changed-check cases need a base ref, so the selftest makes a
  throwaway git repository for its made-up checks.
- `tools/check_nightly_bisect.sh` (`# gate: cheap`): builds a throwaway git
  repository in `$TMPDIR` with `--no-ff` landings and made-up checks, and runs
  `tools/nightly_bisect.sh` against it with builds stubbed. Cases: one breaking
  landing between two good ones is named; two landings that break the same
  check are both named; a revert conflict reports "not measured"; a check that
  exits 2 at a step stops with "not measured"; a check absent at an early
  commit is not blamed on the landing that adds it; G not an ancestor of T
  names nothing; a check that flips on re-run is reported as inconsistent; a
  budget of 0 reports every check as not measured; the duplicate path appends a note
  and files nothing (with `bead_new.sh` stubbed). It MUST go red when the
  bisect's halving or its second pass is removed.
- `tools/check_gate_membership.sh` selftest: `smoke` is accepted, a made-up
  value still fails.
- `tools/check_pass_record.sh` (cheap) drives `finish_bead.sh` end to end and
  asserts that a landing runs the full gate. It changes to assert the landing
  set: its made-up `live` check does not run when the fake bead leaves it
  unchanged, and does run when the fake bead changes it; a `landing` record is
  reused by the next landing and not by a full run. Its existing assertions are
  rewritten, not deleted, and the rewritten check MUST go red when
  `--landing` is replaced by `--compare` in `finish_bead.sh`.

## 9. Out of scope

- The 199 grandfathered checks with no marker. No gate runs them today; this
  work does not change that, except `check_headless.sh` (§3).
- Speeding up any single check.
- Parallel bisect of several failing checks. They run one after another.

## 10. Acceptance (from the beads)

- A landing of a `src/` change runs the builds, the cheap tier, the bead's own
  checks, the smoke set and the soak only; its wall-clock time is measured and
  recorded in `docs/VERIFICATION.md`.
- `tools/check_gate_membership.sh` enforces the tier markers, `smoke` included.
- The nightly run executes the full set, Linux cross-build and layout sweep
  included, and names the guilty landing of a newly failing check;
  `tools/check_nightly_bisect.sh` proves it on a seeded repository.
- Every `cheap` check finishes in 30 s or less on a quiet machine by the §6
  measure, and one gate run shows no slow-check note.
- `tools/README.md` §7 and `docs/VERIFICATION.md` describe the split.
