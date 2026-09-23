# Agent Instructions

## No autonomous work — propose, then wait

NO mandate to operate autonomously. Before changing a tracked file: say what you found and what you'd change, then WAIT for the word — bug fix, feature, refactor, spec, rule change, user-facing text alike; no size/certainty exception. Read/grep/build/checks need no permission; changing the tree does. A "why does X behave that way?" gets answered, not repaired. Separately: save/commit/push is a stop instruction; publishing to a tree not owned needs the rule below (bug-sync exemption unchanged).
Why: unwanted work costs a review and revert; a question costs a minute.
History: docs/rules-history/AGENTS.md#no-autonomous-work--propose-then-wait.

## One bead, one worktree — never work in the shared checkout

`~/Scripts/Incursion` is integration/releases only. Start with `tools/worktree.sh <bead-id>` (branch `<bead-id>` off master, worktree `~/Scripts/Incursion-<bead-id>`); work only there — `.beads/hooks/pre-commit` refuses a non-merge commit in the shared checkout. Exemption: the overnight harness, on a `nightly/` branch there, exporting `NIGHTLY_BRANCH`. On commit: commit on the branch through the gate, then `tools/finish_bead.sh <bead-id>` (gate, merge `--no-ff`, delete branch, drop worktree, all-or-none). `tools/check_orphan_branches.sh` fails a closed-but-unmerged bead's branch, or one not named for a bead id; five pre-rule exceptions are named in that script and the list must not grow.
Why: one shared checkout can land a commit on the wrong branch or leak uncommitted files into a release export.
History: docs/rules-history/AGENTS.md#one-bead-one-worktree--never-work-in-the-shared-checkout.

## Publishing anything outward-facing

1. Brian reads the literal text — exact body and title — before anything is published to a tree he does not own (PRs, issues, review comments, third-party repos). A "go" on a plan is not approval of unseen wording. ONE exemption: bug text to his own tracker (`networkingguru/incursion-roguelike`) needs no pre-read — run `tools/sync_issues.sh`, say what went out, no asking first, no apologising after. Exemption is bugs, NOT the repo: README, user-facing docs, release notes, store/itch pages, announcements still need his read.
2. Always disclose AI assistance on public contributions (every commit carries `Co-Authored-By`), in before he sees the draft.

Prefer a follow-up comment over silently editing a published body. `docs/REPORTING-GATE.md`: a public claim needs an oracle that changed state, numbers both sides.
Why: publication under his name is irreversible.
History: docs/rules-history/AGENTS.md#publishing-anything-outward-facing.

## If you are Codex

Claude plans and reviews; you implement. Disagree with a prompt? Say so in your report, don't choose silently.
- NEVER delete an existing guard, bounds check, invariant, assertion or test to fit new code. If one blocks you, STOP, report file+line, say why.
- Build ONLY with `BACKEND=posix ./build_macos.sh` (produces `incursion-headless`, compiles `mod/Incursion.Mod` in-sandbox). Use `./incursion-headless` as compiler in scripts.
- NEVER invoke `./incursion` (SDL, no sandbox). Do NOT run/edit/report-failing: `check_flavor_stability.sh`, `check_dump_save.sh`, `check_convert_guard.sh`, `check_stair_warn.sh`, `check_dup_names.sh` — a human runs these.
- Run NO git commands; leave changes in the working tree.
- Run NO `bd`; do not open/close/claim/annotate issues.
- Stay in scope: no spec/plan edits unless told; no unrelated formatting changes; if the spec/plan is wrong, say so with evidence, don't implement what you believe wrong.
- Report every deletion separately from additions.
History: docs/rules-history/AGENTS.md#if-you-are-codex.

## Marking base-code bugs

Every upstream (not port) defect fix MUST get a lowercase `upstream:` comment at the fix site, a row in `docs/REPORTING-GATE.md`'s "Base-code bugs fixed locally" table, and bead label `upstream` (`bd label add <id> upstream`). Assume upstream unless you can say why not. Missing the label: `tools/sync_issues.sh` refuses to run, surfacing as UNMEASURED in `tools/nightly_verify.sh` (the gate `tools/finish_bead.sh` runs before merge) — found only after a ~50-min gate run.

Comment states: (1) upstream's AND WHY (would it misbehave on Win32/original typedefs/upstream compiler? if no, it's a port artefact, MUST NOT mark); (2) evidence tier — Observed/Traced/Reasoned; (3) tracking id; (4) whether sent. Marking creates no reporting obligation; sending still needs Brian's literal-text read.
Verify: `tools/check_upstream_marks.sh`. Find all: `grep -rn "upstream:" src/ inc/`.
Why: a future maintainer has none of your context.
History: docs/rules-history/AGENTS.md#marking-base-code-bugs.

## Classifying a change

Every commit subject MUST open with one of seven lanes:

| Lane | What belongs in it |
|---|---|
| `fix:` | A defect: behaviour wrong against the game's rules/docs. |
| `port:` | Platform, build, toolchain, packaging. No player-visible behaviour. |
| `data:` | `lib/*.irh` content that was wrong: stat, name, spell list, table row. |
| `rules:` | Deliberate rules-content change: class, attribute, feat, spell, balance, redesign. |
| `graphics:` | Renderer, light map, terminal look — not `rules:` even if it changes visible map area. |
| `docs:` | Prose only: README, `docs/`, help text, comments. |
| `tools:` | Harness, checks, gate, packaging scripts. |

Pick the lane by what the change DOES, not the motive. A `rules:` commit MUST name a design bead in its body. Lane doesn't replace the verification record: body still states oracle, mutation, checks re-run (`docs/VERIFICATION.md`). A `fix:`/`rules:`/`graphics:` change a player feels needs a before/after observation (gameplay, or the same rendered shot for graphics) or a written exception from Brian — a structural check alone is Traced, never Observed.
Verify: `tools/check_commit_lane.sh`. An already-pushed commit is forgiven by name in `tools/commit_lane.exempt`, NEVER by advancing `tools/commit_lane.since`. `.beads/hooks/commit-msg` enforces at commit time; `INCURSION_NO_LANE_CHECK=1` bypasses in emergency.
Why: lets a reader sort a defect fix from a redesign from `git log --oneline` alone.
History: docs/rules-history/AGENTS.md#classifying-a-change.

## The comment budget

A fix-site comment states the invariant and stops: what must be true, evidence tier, tracking id, whether sent (the `upstream:` marker) — nothing else. Reproduction/measurements/argument go in the bead, referenced by id. Limits (`tools/check_comment_budget.sh`): a comment block in `src/`/`inc/`, or a `#ifdef <NAME>_PROBE` block, SHOULD NOT exceed 30 lines (move a larger probe to its own function/file, keep the `#ifdef` call at the site). Neither limit is retroactive — ratcheted against `tools/comment_budget.baseline`.
Why: bulk in a source file shifts every line-citation below it in citing docs.
History: docs/rules-history/AGENTS.md#the-comment-budget.

## Issue tracking

Run `bd prime` for workflow context; see the marked "Beads Issue Tracker" block below for architecture/anti-patterns.

Every bead MUST have a non-empty description and exactly one of `public`/`internal`/`mirrored` (`tools/check_bead_publish.py` in `.beads/hooks/pre-commit`: blocks, except nightly branch warns). File with `tools/bead_new.sh`, NEVER bare `bd create` (the wrapper checks immediately; the hook is the backstop `bd create` would bypass). Verify: `tools/check_bead_new_gate.sh`. Description isn't optional: `tools/sync_issues.sh` publishes DESCRIPTION only, never notes. Label decides visibility: `public` publishes to `networkingguru/incursion-roguelike`, `internal` never does.
- `public` — a defect/wanted feature IN THE GAME (rules, engine, rendering, saves, in-game help, bindings, builds/releases). Choose when unsure.
- `internal` — harness, key scripts, doc checks, ledger, bead/gate machinery, agent process. Never published.
- `mirrored` — a game defect ALREADY public elsewhere; `external_ref` points at their issue; sync writes only open/closed state, never title/body.

Put diagnosis in the bead's `notes` (never published). Telling a reporter what you found is a COMMENT on their issue, never a body rewrite — goes through the publishing rule above. A new `public` bug bead must pass `bd lint`: literal headings `## Steps to Reproduce` and `## Acceptance Criteria` (existing backlog exempt, drained as inc-uh76).

A direct quote of Brian MUST go in a bead's NOTES only — NEVER description/title/acceptance criteria (covers `public` and `internal` alike). State the ruling in neutral third-person prose in the description, keep every fact, move exact words via `bd update <id> --append-notes`, attributed/dated. Quotes of anyone else stay in the description.
Why: `sync_issues.sh` publishes title+description verbatim under his name once `public`, never notes.
History: docs/rules-history/AGENTS.md#every-bead-carries-public-internal-or-mirrored, #a-quote-of-brian-goes-in-the-notes-and-nowhere-else.

## Non-Interactive Shell Commands

ALWAYS use non-interactive flags: file ops (`cp -f`, `mv -f`, `rm -f`, `rm -rf`, `cp -rf`) and prompting commands (`scp`/`ssh -o BatchMode=yes`, `apt-get -y`, `brew` with `HOMEBREW_NO_AUTO_UPDATE=1`) — an `-i`-aliased `cp`/`mv`/`rm` hangs the agent on a y/n prompt.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:970c3bf2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->
