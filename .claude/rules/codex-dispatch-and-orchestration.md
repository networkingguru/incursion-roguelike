# Codex dispatch and orchestration

## always-implement-via-codex
Claude's main context does NOT author files — only true prose (report, bead body, memory, brief for Codex, doc paragraph). Every machine-read/run file (C++, headers, Python, shell, `.keys`, `.irh`, config, Makefiles, a red-green mutation into a tracked source) goes to Codex, never a hand edit. Claude still RUNS: builds, `tools/headless.sh`, greps, reads, docker, `bd`, git, investigation, judging diffs.

Fallback order when Codex is unavailable:
  1. Codex.
  2. DeepSeek V4.1-Flash via `tools/deepseek.py` — a self-contained file from a complete spec; it cannot iterate, so YOU run the check and judge the diff after.
  3. Agent-tool dispatch, explicit `model:` override (NEVER inherit session model): `haiku` ONLY for mechanical find/replace; `sonnet` for anything needing the code understood; `opus` only when sonnet can't, say why. NEVER `model: 'fable'` without Brian's authorisation that conversation. Use for work needing iteration to finish (a check going green, a blast radius read from the tree).
  4. NEVER Claude's own Edit/Write. If none of 1–3 can run, STOP and tell Brian.

The DeepInfra key behind `tools/deepseek.py` has a 20 USD cap, one allowed model, cannot raise its own cap. Ledger: `logs/deepseek-ledger.jsonl`. If it stops answering, read the ledger, ask Brian before topping up.
Why: keeps implementation detail out of Claude's context; matches model size to task difficulty.
History: docs/rules-history/codex-dispatch-and-orchestration.md#always-implement-via-codex.

## feedback-claude-dispatches-never-writes-code
Claude does NOT write code on this project. The main agent MUST NOT edit source, build, or run long noisy commands itself. Dispatch one subagent per finding/task with: file:line evidence, red-before-green-after protocol, `upstream:` comment requirements, ledger row, exact build commands. It reports back SHORT: what changed, red/green measurements, surprises. The main agent still owns: one finding at a time to Brian, verifying claims before quoting numbers, judging report truth — not delegated. Two-line read-only checks MAY stay inline.
Why: implementation detail in the main agent's own context costs tokens every later turn.
History: docs/rules-history/codex-dispatch-and-orchestration.md#feedback-claude-dispatches-never-writes-code.

## feedback-codex-implements-claude-plans
Claude plans/reviews/decides; Codex implements ONLY, never drafts the spec or plan. Write the spec amendment and plan yourself before dispatching; give Codex one or two phases at a time against it; review the diff before the next dispatch.
Why: if Codex writes the plan, review has nothing independent to check against.
History: docs/rules-history/codex-dispatch-and-orchestration.md#feedback-codex-implements-claude-plans.

## feedback-overnight-multiagent-orchestration
Default shape for an overnight "keep going until a limit" request: (1) one agent at a time, never parallel; (2) every agent is a FRESH dispatch with zero assumed memory — full `bd` issue text, known file:line pointers, out-of-scope boundaries, hard git rules (no commit/push/branch, leave uncommitted), instruction to leave a dated `bd note`; (3) independently RE-VERIFY every claimed result (rebuild, re-run checks, re-reproduce crash seeds yourself); (4) resume an unfinished agent via `SendMessage` to its id, don't launch fresh; (5) investigative issues may go to agents too, time-boxed, "here's how far I got" acceptable; (6) stop only on a real external limit.
Why: avoids one agent losing context, or parallel self-reports standing unchecked.
History: docs/rules-history/codex-dispatch-and-orchestration.md#feedback-overnight-multiagent-orchestration.

## agents-md-is-injected-at-session-start
`AGENTS.md` is auto-injected by the `~/.claude/hooks/inject-agents-md.py` SessionStart hook; check with `python3 ~/.claude/hooks/test-inject-agents-md.py`. A session should open with `[AGENTS.md auto-injected at session start`; if missing, read `AGENTS.md` by hand. `~/.claude/CLAUDE.md`'s "Branches" paragraph is a default this repo's one-worktree-per-bead rule overrides.
Why: Claude Code auto-loads `CLAUDE.md` but never `AGENTS.md` on its own.
History: docs/rules-history/codex-dispatch-and-orchestration.md#agents-md-is-injected-at-session-start.

## read-the-persisted-bd-prime-output-first
Read the FULL `bd prime` SessionStart hook output, not just the truncated preview. `CLAUDE.md` now opens with `@AGENTS.md`, closing the hole this rule targeted; still applies to whatever else `bd prime` delivers.
Why: a rule visible only in the untruncated output is invisible to a session trusting the preview.
History: docs/rules-history/codex-dispatch-and-orchestration.md#read-the-persisted-bd-prime-output-first.
