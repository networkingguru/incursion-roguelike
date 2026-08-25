# Agent Instructions

## Publishing anything outward-facing

Two rules, and neither has an exception.

1. **Brian reads the literal text before it is published.** Not a diff, not a
   summary of what it claims — the exact body and title that will be posted.
   This covers pull requests, issues, review comments, and anything else that
   leaves this machine or appears under his name. A "go" that answers a plan is
   NOT approval of wording he has not seen. Paste the text, wait for a yes on
   that text.

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

## If you are Codex

Claude plans and reviews. You implement. These rules hold on every run, whether
or not the prompt repeats them. Where a prompt and this section disagree, say so
in your report rather than choosing silently.

**Never delete an existing guard, bounds check, invariant, assertion or test to
make new code fit.** If one blocks you, STOP and report it with its file and
line and say why it blocks you. Most of them exist because a specific defect got
through once, and the comment above them usually says which. Deleting one is the
single most damaging thing you can do here, because every check stays green
afterwards and the loss is invisible in a report. This was broken on 2026-08-25:
the AutoBuffs terminator invariant in `inc/Creature.h` was removed while
reworking how that array is stored. Three loops walk `AutoBuffs` with no index
limit (`src/Term.cpp:152` and `:234`, `src/Sheet.cpp:778`), so the removal
re-opened an out-of-bounds read reachable from a crafted save file, on the old
save path as well as the new one.

**Build only with `BACKEND=posix ./build_macos.sh`.** The default libtcod build
compiles the game module by RUNNING the SDL binary, which aborts inside your
sandbox with "the video driver did not add any displays". The posix build
produces `incursion-headless` and compiles `mod/Incursion.Mod` entirely inside
the sandbox. Use `./incursion-headless` as the compiler in any script you write.

**Never invoke `./incursion`.** It is the SDL binary and it cannot run in your
sandbox. Five checks invoke it or invoke git, so you cannot run them:
`check_flavor_stability.sh`, `check_dump_save.sh`, `check_convert_guard.sh`,
`check_stair_warn.sh` and `check_dup_names.sh`. Do not run them, do not edit
them, and do not report them as failures. A human runs them outside the sandbox.

**Run no git commands.** Leave every change in the working tree. A human reads
the diff and records it.

**Change no issue-tracker state.** Do not run `bd`. You do not open, close,
claim or annotate issues. This was broken on 2026-08-25: bead `inc-mdi6` was
closed unasked, with a reason describing different work.

**Stay inside the stated scope.** Do not edit the spec or the plan you were
given unless the prompt says you may. Do not make unrelated whitespace or
formatting changes; they hide the real diff. If you believe the spec or the plan
is wrong, say so in your report with evidence and do not implement what you
believe is wrong.

**Report what you removed.** List every deletion your change makes, separately
from what you added. A reviewer's weakest sense is for what is no longer there.

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

Verify with `tools/check_upstream_marks.sh`. Find them all with
`grep -rn "upstream:" src/ inc/`.

## Classifying a change

**Every commit subject MUST open with a lane, and the lane MUST be one of six.**
An outsider reading `git log --oneline` has to be able to sort a defect fix from
a rules redesign without opening a single body. Today they cannot, and that is
the fault this rule fixes.

| Lane | What belongs in it |
|---|---|
| `fix:` | A defect. The behaviour was wrong against the game's own rules or its own documentation. |
| `port:` | Platform, build, toolchain, packaging. No behaviour a player sees. |
| `data:` | `lib/*.irh` content that was wrong: a stat, a name, a spell list, a table row. |
| `rules:` | A deliberate change to how the game plays. Balance, mechanics, a system redesign. |
| `docs:` | Prose only. `README.md`, `docs/`, help text, comments. |
| `tools:` | The harness, the checks, the gate, packaging scripts. |

Pick the lane by what the change DOES, not by what motivated it. Making the code
agree with the manual is still `rules:` when a player will feel the difference.
The armour change (545e07f) is the worked example: the manual was the reason, and
the lane is `rules:`, because damage now resolves differently.

**A `rules:` commit MUST name a design bead in its body.** The bead holds the
ruling and the reasoning. The commit holds the change. A `rules:` commit with no
bead is a balance change nobody agreed to.

**A lane is not a substitute for the verification record.** Whatever the lane,
the body still states the oracle, the mutation and the checks re-run, as
`docs/VERIFICATION.md` requires.

Verify with `tools/check_commit_lane.sh`.

## The comment budget

**A comment at a fix site states the invariant and stops.** Four things belong
there, and nothing else: what must be true, the evidence tier, the tracking id,
and whether it has been sent. That is the `upstream:` marker described above.

**The reproduction, the measurements and the argument go in the bead.** They are
valuable and they are not source. Reference them by id.

This is not a matter of taste. `tools/check_doc_freshness.sh` records the cost: a
102-line probe block added at the top of `src/Event.cpp` moved 92 of that page's
131 line citations, and nothing noticed for days. Bulk in a source file breaks
every citation below it.

**Limits, enforced by `tools/check_comment_budget.sh`:**

- A comment block in `src/` or `inc/` SHOULD NOT exceed 30 lines.
- A `#ifdef <NAME>_PROBE` block SHOULD NOT exceed 30 lines. A larger probe moves
  to its own function, or to its own file, and the site keeps the `#ifdef` call.
- Neither limit is retroactive. The check ratchets: it fails on a block that grew
  past the ceiling in this change, not on one that was already over it. The
  existing oversize blocks are tracked in `tools/comment_budget.baseline`.

## Issue tracking

This project uses **bd** (beads) for issue tracking. Run `bd prime` for full workflow context.

> **Architecture in one line:** Issues live in a local Dolt database
> (`.beads/embeddeddolt/`); cross-machine sync uses `bd dolt push/pull` (a
> git-compatible protocol), stored under `refs/dolt/data` on your git
> remote — separate from `refs/heads/*` where your code lives.
> `.beads/issues.jsonl` is a passive export, not the wire protocol.
>
> See [sync-concepts.md](https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md)
> for the one-screen overview and anti-patterns (don't treat JSONL as the
> source of truth; don't `bd import` during normal operation; don't
> reach for third-party Dolt hosting before trying the default).

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work atomically
bd close <id>         # Complete work
bd dolt push          # Push beads data to remote
```

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

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
