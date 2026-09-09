# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## Standing order: fix bugs in this tree without asking

**A bug in Brian's own repository IS a work order. Read it, edit it, build it,
and run the checks. Do not ask.** He set this scope on 2026-09-09, after a
session presented issue/fix/blast-radius and stopped on a bug in his own tree:
"YOU DO NOT NEED TO ASK ME FOR EVERY FUCKING BUG EDIT, ONLY THOSE GOING TO
OTHER REPOS."

This mirrors the scope he set on the publishing rule below on 2026-09-08. One
principle covers both: **his tree, his bugs, go; somebody else's tree, ask.**

Three things still need his word, and nothing else does:

1. **Anything aimed at a tree he does not own.** A patch, issue, PR or comment
   for `rmtew/incursion-roguelike` or any third party. That is rule 1 of
   "Publishing anything outward-facing", and it is unchanged.
2. **Committing and pushing.** Separate rule, separate reason: when he says
   save, commit or push, that is a stop instruction. Nothing else starts a
   commit. Fixing a bug leaves the work in the tree for him to review.
3. **Work that is not a bug fix.** A feature, a refactor, a spec, a rule
   change, or any edit to user-facing text (README, docs, release notes,
   store pages). Those keep the old shape: propose, then wait.

**A question is still a question.** If Brian asks why something behaves the way
it does, answer the question. He asked for an explanation, not a repair. That is
the residue of 2026-08-23, which is still worth remembering: he reported that
the Boots of Providence pay no Luck bonus when carried and asked for nothing
else, and the session edited four tracked files, rebuilt both binaries and the
module, and filed a bead. The defect there was scope, not permission. See bead
inc-izuu.

When you fix a bug unasked, say what you changed, file by file, and what else
the change reaches. Report it after; do not request it before.

## Publishing anything outward-facing

Two rules. Rule 1 carries one scope limit, stated inside it. Rule 2 has none.

1. **Brian reads the literal text before it is published to a tree he does not
   own.** Not a diff, not a summary of what it claims — the exact body and
   title that will be posted. This covers pull requests, issues and review
   comments on the parent project or any third party's repo, and anything else
   that appears under his name on somebody else's property. A "go" that answers
   a plan is NOT approval of wording he has not seen. Paste the text, wait for a
   yes on that text.

   **One exemption, and it is narrow: BUG TEXT on his own tracker.** A bead
   filed, updated or synced to `networkingguru/incursion-roguelike` needs no
   pre-read. Run `tools/sync_issues.sh`, then say what went out. Do not ask
   first, and do not apologise afterwards. He set the scope on 2026-09-08,
   after a session apologised for publishing nine of his own beads: "If I post
   something to someone else's repo, need to read it. A bug in my own, I do
   not."

   **The exemption is bugs, NOT the repo.** README.md, user-facing docs,
   release notes, store and itch pages, announcements, and anything else a
   player or a visitor reads still need his eyes on the literal text before it
   goes out, even though he owns the tree. He narrowed it in the same
   conversation: "This is true for beads/bug, not the whole repo. Not the read
   me, not user-facing docs (unless separately authorized). Just bugs." A
   separate authorisation for one of those covers that one thing only.

2. **Always disclose AI assistance on public contributions.** Every commit
   carries a `Co-Authored-By` trailer; so must anything sent to another
   project. Put the disclosure in before showing him the draft, so what he
   approves is the disclosed version.

Both were broken on 2026-08-15: two PRs went to the parent project with text he
had never read and no disclosure, while his own branch commits carried the
trailer. If a published item must be corrected, prefer adding a comment over
silently editing the body — a silent edit leaves an "edited" marker and reads
as concealment.

See `docs/REPORTING-GATE.md` for the separate rule that a public claim needs an
oracle that changed state, with numbers on both sides.

## Marking base-code bugs

**Every fix to a defect that is upstream's rather than the port's MUST be marked
at the fix site with a lowercase `upstream:` comment, and MUST get a row in the
"Base-code bugs fixed locally" table in `docs/REPORTING-GATE.md`.** Most defects
in this codebase are upstream's, so assume a fix needs this unless you can say
why it does not.

The comment states four things, because a maintainer reading it years from now
has none of your context:

1. that the defect is upstream's, **and why** — would it misbehave on Win32,
   with the original typedefs, on the upstream compiler? If no, it is a port
   artefact and MUST NOT be marked; claiming ours is theirs costs credibility.
2. the evidence tier — Observed, Traced or Reasoned.
3. the tracking id.
4. whether it has been sent, so nobody re-sends it and nobody assumes it went.

**Marking is not reporting and creates no obligation to report.** It exists so
the work is findable if the original maintainer ever returns. Sending still goes
through the gate, and still needs Brian to read the literal text.

The row goes under the exact heading `### Base-code bugs fixed locally`, never
under `### Not sent`, which is a three-column table that drops the tracking id;
`tools/check_ledger_rows.sh` is the check for that.

Verify with `tools/check_upstream_marks.sh`. Find them all with
`grep -rn "upstream:" src/ inc/`.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
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
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->


## Build & Test

```bash
./build_macos.sh                        # the SDL build, ./incursion
BACKEND=posix ./build_macos.sh          # the headless build, most checks need it
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    tools/headless.sh tools/keys/dive.keys   # one seeded session, sandboxed
tools/nightly_verify.sh --record        # freeze what already fails
tools/nightly_verify.sh --compare       # did this work break anything that passed?
```

Never run the binary directly. `tools/headless.sh` gives a run its own `save/`
and `logs/`, so an unattended session cannot destroy a real character.

Every harness run MUST name its settings. `tools/headless.sh` exits 2 when
`INCURSION_OPTIONS` is unset, because settings change what a seeded session
does: e4a6499 measured one flipped option byte taking `dive.keys` on seed 4242
from 254 turns to 2190. Frozen choices live in `tools/fixtures/` and are
described in `tools/fixtures/README.md`; gates use their own
`tools/gates/Options.Dat`.

`tools/README.md` §7 groups every check into five tiers by what it needs, and
names the two you must not run casually.

## Verification

Read `docs/VERIFICATION.md` before you change behaviour. It states the rule this
project uses instead of hosted CI, and it is not optional.

## Architecture and conventions

`README.md` §For developers describes the harness, the gate and the checks.
`AGENTS.md` holds the working rules: the standing order, the publishing rules,
how to mark a base-code bug, how to classify a change, and the comment budget.
Neither is repeated here, because a third copy would drift.
