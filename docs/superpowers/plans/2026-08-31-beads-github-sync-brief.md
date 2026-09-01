# Brief: publish code-relevant beads to GitHub Issues, automatically

Sized: **Small for the sync itself** -- two scripts, one workflow file, one
mechanical labelling pass. Phase 5, the review of 196 lint-failing bugs, is
separate work of its own and carries its own bead; it is listed here because
it gates what publishes, not because it ships with the rest. Brief format, no
separate spec.

Written 2026-08-31. Nothing in this plan is implemented yet.

## Goal

Every bead that describes a defect or a wanted feature **in the game** appears
in the Issues tab of `networkingguru/incursion-roguelike`, stays up to date,
and gets there with no action from Brian and no action from an agent. Beads
about process, agents, and the test harness never appear.

The point is that a stranger who is about to file a bug sees it already filed.

## The constraint that shapes everything

`bd github sync` is real and bidirectional, but its only selectors are
`--issues <comma-separated ids>` and `--parent <bead>` (push only). There is
no filter by type, label, or status. Measured facts, 2026-08-31:

- 428 beads total, 287 open.
- 224 of the 428 have **no parent**, so `--parent` cannot express the filter.
- `bd github sync --push-only --dry-run` says "Would create" for all 428.

So the filter must be computed outside bd and handed to `--issues`. That is the
only moving part this plan adds.

## The filter

Publication is decided by a **mandatory label**, not by a default. Every bead
carries exactly one of `public` or `internal`, and a gate check fails the
commit when a newly created bead carries neither. An agent cannot forget a
required field that blocks the commit the way it can walk past a paragraph in
`AGENTS.md` -- which has happened here twice on record (2026-08-15, the
publishing rule; 2026-08-23, the standing order).

`public` publishes. `internal` never does. Type and ancestor are no longer the
decision -- they only seed the one-time backfill in phase 3.

**The heuristic is advisory, and it runs in both directions.** It reports, and
does not block: a `public` bead whose title talks about `tools/`, `check_`,
`.keys`, `.sh`, `soak`, `harness`, `subagent`, `nightly`, `key script`,
`Options.Dat`, `Codex`, `Claude`, `bead`, `agent`, `session`, `gate` or
`probe`; and an `internal` bead whose title talks about the game. The second
direction matters most: an over-suppressed bead is the failure no hold list can
see, because it simply never appears.

Measured, to size the backfill. Of 428 beads, 317 are type `bug` or `feature`,
outside `inc-loa`, and would seed as `public`; 111 seed as `internal`. Of the
317, the heuristic flags 21 for a human look -- about eleven genuinely internal
(`inc-ekv`, `inc-h1a`, `inc-p9jm`, `inc-t4te`, `inc-kh0b`, `inc-3m6o`,
`inc-gjzx`, `inc-uh0`, `inc-w43`, `inc-nx0z`, `inc-b64`) and about ten false
positives where a game bug happens to use a word like "gate" (`inc-47d` Flurry
of Blows, `inc-tek.29` Staff of Exorcism, `inc-urs` Twilight Huntsman,
`inc-upw.53` mana potion, `inc-upw.4` dead creature handle).

The four beads Brian objected to by name all seed `internal`: `inc-50qp`,
`inc-5ysg` and `inc-s0wy` are type `task`, and `inc-loa.9` is under `inc-loa`.

**Quality gate.** `bd lint` requires "Steps to Reproduce" and "Acceptance
Criteria" on a bug, and 196 open bugs are missing one or both today. A bug
going to a public tracker without repro steps reads as noise, so the gate runs
`bd lint` over newly created `public` beads. History is handled by phase 5, not
by blocking every commit on a backlog.
## Known one-time costs

- **~30 beads need the `internal` label.** They are typed `bug`, sit outside
  `inc-loa`, and are about the harness rather than the game. Examples found:
  `inc-ekv`, `inc-h1a`, `inc-p9jm`, `inc-t4te`, `inc-kh0b`, `inc-3m6o`
  (all `check_*.sh`), `inc-w43` (the regression tool), `inc-nx0z` and
  `inc-b64` (key scripts). Phase 3.
- **One duplicate issue.** Neither sync direction adopts the six issues that
  already exist. Push wants to *create* rather than update for `inc-003`
  (issue #3) and `inc-6d5` (issue #2), ignoring the `external_ref: gh-3`
  already on the bead; pull would import all six as six new beads. Since #1,
  #4 and #5 are already closed and #2 and #6 are being closed separately, the
  live damage is issue #3 alone. Close it as superseded after the first push.

## Files touched

| File | Change |
|---|---|
| `tools/check_bead_publish.sh` | New. Gate check: fails when a newly created bead carries neither `public` nor `internal`, or both; runs `bd lint` over new `public` beads; prints the advisory heuristic's disagreements without failing. |
| `tools/sync_issues.sh` | New. Computes the filtered id list and calls `bd github sync --push-only --issues`. Reads the token from `gh auth token` locally, `GITHUB_TOKEN` in CI. |
| `.github/workflows/beads-sync.yml` | New. The repo has no `.github/` at all. Fetches `refs/dolt/data`, runs `bd bootstrap`, runs the script. Scheduled, plus `workflow_dispatch`. |
| `AGENTS.md` | One paragraph: every bead carries `public` or `internal`, the gate enforces it, and what each means. |
| `tools/README.md` | One row in the §7 tier table for `sync_issues.sh`. |

No game source changes. No bead schema changes.

## Phases, one commit each

1. **Prove the data is reachable from CI.** In a scratch clone with no
   `.beads/embeddeddolt`, fetch `refs/dolt/data` from origin (the ref exists:
   `07cb47f`) and confirm `bd bootstrap` produces a database `bd list` can
   read. If it cannot, stop and re-plan around a `gh`-only pusher that keys on
   a `bead: <id>` marker in the issue body. No commit; this is a finding.
2. **Write `tools/sync_issues.sh`, plus the `AGENTS.md` and `tools/README.md`
   notes.** Verify by `--dry-run` that it selects 317 and names none of
   `inc-50qp`, `inc-5ysg`, `inc-s0wy`, `inc-loa.9`.
3. **Backfill the label on all 428 beads, mechanically.** Seed `internal`
   where the type is not `bug`/`feature` or an ancestor is `inc-loa`, else
   `public`. Then look at the 21 the advisory heuristic flags and correct them
   by hand. Bead data only, no commit.
4. **Add `tools/check_bead_publish.sh` to the gate.** It fails the commit when
   a bead created since the last commit carries neither `public` nor
   `internal`, or carries both. It also runs `bd lint` over newly created
   `public` beads, and prints -- without failing -- the advisory heuristic's
   disagreements in both directions.
5. **Review every `public` bead for whether it actually needs a repro.**
   `bd lint` demands "Steps to Reproduce" of anything typed `bug`, and 196
   open bugs lack it. Most of those are not missing content, they are the
   wrong type: an audit or a triage list -- "Magic items: 82 prose-vs-script
   mismatches", "Strip CA_WEAPON_IMMUNITY from 44 sites" -- is a task, and a
   task is not asked for a repro. Three outcomes per bead: a genuine defect
   gets repro steps written; a mistyped one is re-typed to `task` or
   `feature`, which retires the lint finding honestly rather than by
   exemption; an obsolete one is closed. Tracked as bead `inc-uh76` so it can run
   incrementally, and it does NOT block phase 6 -- but no bead still failing
   lint publishes until it is resolved one of the three ways.
6. **First real push into a private scratch repo, not the real one.** This is
   the free artifact before the costly one. Answers the two things the dry run
   cannot: whether a closed bead arrives closed or open, and whether a second
   run updates rather than duplicates.
7. **Point it at `networkingguru/incursion-roguelike` and run once.** Then
   close issue #3 as superseded by the new one.
8. **Add the workflow and confirm one scheduled run is idempotent** -- it must
   create nothing on a run where no bead changed.

## Test plan

- **Adversarial:** a new bead with no label, with both labels, and with a label
  added in the same commit that creates it; a `public` bug with no repro
  section; an existing bead edited but not created (must not fail the gate);
  empty filter result (must exit 0 and push nothing); missing
  `GITHUB_TOKEN`; `bd` absent or database unreadable; a bead title containing
  quotes, backticks or a newline; the id list at full length (317 ids is about
  2.9 KB of argument, well inside `ARG_MAX`, but assert rather than assume);
  a bead deleted between two runs.
- **User-focused:** run twice with no changes -- second run is a no-op. Close a
  bead, re-run, the issue closes. Edit a bead title, re-run, the issue title
  follows. File an issue on GitHub by hand, run a pull, it lands in beads.
- **Live:** phases 4 and 5 are the live runs. Phase 4 is against a throwaway
  repo so that a wrong answer costs nothing public.

## Open questions this plan does not answer

- Whether closed beads push as closed issues or as open ones. Phase 4.
- Whether bd stores the bead-to-issue link durably enough that phase 6's
  scheduled run updates instead of duplicating. Phase 4 tests it twice; phase 6
  tests it across a fresh CI checkout, which is the harder case.
- Whether the workflow should also run `--pull-only`, so issues filed by other
  people become beads. Worth having, but it writes to the database from CI,
  which needs its own thought about who owns the Dolt ref. Deferred; this plan
  ships push-only.

## Stop conditions

Stop and ask Brian if: phase 1 fails; phase 4 shows closed beads arriving open;
the filter's kept count moves more than ten either way from 317 without an
explanation; a sync run would publish a bead still failing `bd lint`; or the phase 5
review turns out to need more than one working day, in which case it is split
off and the sync ships without it.
