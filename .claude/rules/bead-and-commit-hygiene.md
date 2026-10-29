# Bead and commit hygiene

## commit-approves-the-text-it-carries
"commit" IS approval of any literal text the commit carries (README row, doc line, anything pasted for a yes). Do NOT hold a commit for lack of a separate yes on already-shown text; put it in and commit. Save-means-stop still bars NEW edits invented at commit time only.
Why: approving twice wastes a round trip and can deadlock the merge gate.
History: docs/rules-history/bead-and-commit-hygiene.md#commit-approves-the-text-it-carries.

## commit-gate-stage-before-commit
NEVER combine staging and committing in one Bash call — stage, then commit SEPARATELY, or `commit-gate.py` sees an empty staged index and fails closed to BLOCK. Keep "commit gate" out of `bd-remember` content (substring-matched). Do NOT weaken the hook to parse chained staging. `commit-gate.py` allows a commit only when Brian's latest message says commit, save or push, or answers yes to a commit Claude proposed; there is no approval marker.
Why: a chained call hides that the change is docs-only from the hook.
History: docs/rules-history/bead-and-commit-hygiene.md#commit-gate-stage-before-commit.

## commit-means-land-the-bead
"commit"/"save"/"push" means LAND IT, in order: (1) `git commit` on the bead's branch through the gate; (2) `tools/finish_bead.sh <bead-id>` (gate, merge `--no-ff`, delete branch, drop worktree); (3) `bd close <bead-id>` ONLY AFTER the merge lands. Closing before step 2 makes `tools/check_orphan_branches.sh` red and blocks the merge — recover with `bd update <id> --status open`, re-run, then close. Exception: a worktree holding another bead's uncommitted work — commit only your own paths, say so, don't land that bead.
History: docs/rules-history/bead-and-commit-hygiene.md#commit-means-land-the-bead.

## wait-on-the-load-guard-before-a-commit
Before `git commit` and before `tools/finish_bead.sh`, wait until the machine is fit: `until tools/load_guard.sh; do sleep 30; done`, in a background Bash call. `tools/load_guard.sh` refuses (exit 2) only while kernel memory pressure is 2 (warn) or higher; it prints the load average but does not refuse on it, and it never waits on its own. Every gate and fast check run appends its load and elapsed time to `logs/check-timing.tsv` in the shared checkout; read that log before you call a failure load-caused. NEVER bypass it with `--no-verify` or `INCURSION_LOAD_GUARD_OFF=1`. `tools/load_guard.sh` is the only wait: MUST NOT wait for an idle machine, which never occurs.
Why: memory pressure slows every session at once, while no failure caused by load alone has been measured; the timing log is the evidence any future load limit needs.
History: docs/rules-history/bead-and-commit-hygiene.md#wait-on-the-load-guard-before-a-commit. Beads inc-r80o, inc-b0ziu.8.

## beads-blocking-a-commit-fix-the-bead
A bead blocking your commit: LOOK IT UP AND FIX IT, don't stop/ask/present options. Write missing `## Steps to Reproduce`/`## Acceptance Criteria` from the bead's own description, even if another session filed it. Block only if truly unable to work it out. NEVER `git commit --no-verify`.
Why: asking turns a one-command fix into a round trip.
History: docs/rules-history/bead-and-commit-hygiene.md#beads-blocking-a-commit-fix-the-bead.

## bead-label-gate-guards-bd-create
Two gates live OUTSIDE this repo in `~/.claude/hooks/` — check there when a Bash command is denied unexplained. `bead-label-gate.py`: CREATE gate denies `bd create`/`bd new`/`tools/bead_new.sh` naming neither or both of `public`/`internal`; COMMIT gate denies a commit while a bead since HEAD is unclassified. `commit-gate.py` denies a commit until approved (docs-only exempt).

ALWAYS file through `tools/bead_new.sh`, NEVER bare `bd create`. A `public` bead must pass `bd lint`: description must literally contain `## Steps to Reproduce` (bugs) and `## Acceptance Criteria`. `bead_new.sh` checks immediately; `bd create` does not. Recover with `bd update <id> --body-file <file>`.
Why: an unclassified/malformed bead blocks the next commit for whoever runs it.
History: docs/rules-history/bead-and-commit-hygiene.md#bead-label-gate-guards-bd-create.

## bead-github-sync-wiring
`git core.hooksPath` is `.beads/hooks`; `.git/hooks` never fires. `.beads/hooks/pre-push` runs `tools/sync_issues.sh` on every push, must never block one. `INCURSION_NO_BEAD_SYNC=1` skips it. `bd hooks install` can silently drop that block — check afterward.

Use `tools/sync_issues.sh`, NEVER bare `bd github sync` (no label filter). Config: `github.owner`, `github.repo`; `github.org` NOT read. NEVER `bd config set github.token` (tracked `.beads/config.yaml`) — use `GITHUB_TOKEN`. NEVER `bd show` with a large id list — use `bd list --json`.
Why: keeps sync from publishing internal beads or taking minutes.
History: docs/rules-history/bead-and-commit-hygiene.md#bead-github-sync-wiring.

## epic-children-inherit-internal-label
A child bead with `--parent` inherits parent labels. After `bd create -l public --parent <internal-epic>`, run `bd update <id> --remove-label internal`.
Why: a bead cannot carry both labels; sync refuses until fixed.
History: docs/rules-history/bead-and-commit-hygiene.md#epic-children-inherit-internal-label.

## feedback-no-beads-sync
Do NOT sync/push/offer to push the beads database, report `refs/dolt/data` age, or run `bd doctor`. `bd show <id>` existing is the whole "saved" check. Code commits/pushes remain wanted.
Why: single-machine project — the local Dolt DB is the only copy that matters.
History: docs/rules-history/bead-and-commit-hygiene.md#feedback-no-beads-sync.

## feedback-handoff-notes-are-not-commits
Do NOT commit session logs or handoff writeups. Use `bd remember`, keyed `resume-<date>`. Commit only code/tests/tooling/docs. "Write notes and commit" means the pending work, not notes.
Why: a commit describes a code change, not a session log.
History: docs/rules-history/bead-and-commit-hygiene.md#feedback-handoff-notes-are-not-commits.

## check-bead-status-before-suggesting-or-starting
Before you name a bead as work to do, run `bd show <id>` in the SAME turn and state its status and assignee. A resume note, a `bd memories` entry or output from an earlier turn MUST NOT count as evidence of status. Start a bead ONLY with `tools/worktree.sh <id> [base]`, which claims it under this session's own actor (`claude-<pid>`) and refuses when another actor holds it. NEVER run `bd update --claim` by hand to start work. When it refuses, report the holder to Brian and STOP; use `--take-over` only when Brian says the holder is gone.
Why: every session shares git user "Brian Hill", so a status read or a plain claim cannot tell one session's bead from another's.
History: new rule, no prior narrative to archive. Bead inc-u1mt.

## landing-needs-evidence-for-every-acceptance-criterion
A bead lands only when a commit on its branch whose subject line names the bead id carries one line per acceptance criterion in its message, `AC<n>: <evidence>`, where evidence names the command, check or observation and its result. Number the criteria AC1, AC2, ... in the order of the `## Acceptance Criteria` bullets, then the bd `acceptance_criteria` field. `tools/finish_bead.sh` refuses the landing (STEP 2b, `tools/check_bead_evidence.py`) when a criterion has no line, or when a line admits the criterion was not verified (not observed, Traced only, unverified, untested, deferred, skipped and similar words), unless it names an open follow-up bead whose text names this bead, or carries `exception:` with a matching `AC<n> exception (Brian ...` line in the bead's notes. Write the plan and the implementer brief from the acceptance criteria, naming each one, not from the code change. A bead with no acceptance criteria is refused the same way, docs-only beads included. There is no bypass. Verify: `tools/check_bead_evidence.py --selftest`.
Why: prose rules let a bead land with half its acceptance criteria unverified, so the check is mechanical.
History: new rule, no prior narrative to archive. Bead inc-v4xe.
