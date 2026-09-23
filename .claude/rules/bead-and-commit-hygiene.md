# Bead and commit hygiene

## commit-approves-the-text-it-carries
"commit" IS approval of any literal text the commit carries (README row, doc line, anything pasted for a yes). Do NOT hold a commit for lack of a separate yes on already-shown text; put it in and commit. Save-means-stop still bars NEW edits invented at commit time only.
Why: approving twice wastes a round trip and can deadlock the merge gate.
History: docs/rules-history/bead-and-commit-hygiene.md#commit-approves-the-text-it-carries.

## commit-gate-stage-before-commit
NEVER combine staging and committing in one Bash call — stage, then commit SEPARATELY, or `commit-gate.py` sees an empty staged index and fails closed to BLOCK. Keep "commit gate" out of `bd-remember` content (substring-matched). Do NOT weaken the hook to parse chained staging. Auto mode denies `create-approval-marker.py`; use bang-prefix or leave auto mode for a non-docs commit.
Why: a chained call hides that the change is docs-only from the hook.
History: docs/rules-history/bead-and-commit-hygiene.md#commit-gate-stage-before-commit.

## commit-means-land-the-bead
"commit"/"save"/"push" means LAND IT, in order: (1) `git commit` on the bead's branch through the gate; (2) `tools/finish_bead.sh <bead-id>` (gate, merge `--no-ff`, delete branch, drop worktree); (3) `bd close <bead-id>` ONLY AFTER the merge lands. Closing before step 2 makes `tools/check_orphan_branches.sh` red and blocks the merge — recover with `bd update <id> --status open`, re-run, then close. Exception: a worktree holding another bead's uncommitted work — commit only your own paths, say so, don't land that bead.
History: docs/rules-history/bead-and-commit-hygiene.md#commit-means-land-the-bead.

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
