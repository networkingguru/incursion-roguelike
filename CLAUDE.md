@AGENTS.md

# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

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
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/lizardfolk-monk-seed1.sav \
    tools/headless.sh tools/keys/load-char-sheet.keys 1   # ...from a frozen character
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

Reach for `INCURSION_LOAD` when a check needs a character a module change cannot
rewrite: a seed-pinned character is not one, because an rID is a position.
`tools/fixtures/README.md` says why, and how to make and regenerate a fixture.

`tools/README.md` §7 groups every check into five tiers by what it needs, and
names the two you must not run casually.

## Verification

Read `docs/VERIFICATION.md` before you change behaviour. It states the rule this
project uses instead of hosted CI, and it is not optional.
