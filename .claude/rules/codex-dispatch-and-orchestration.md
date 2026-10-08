# Codex dispatch and orchestration

## always-implement-via-codex
Claude's main context does NOT author files — only true prose (report, bead body, memory, brief for an implementer, doc paragraph). Every machine-read/run file (C++, headers, Python, shell, `.keys`, `.irh`, config, Makefiles, a red-green mutation into a tracked source) goes to an implementer, never a hand edit. Claude still RUNS: builds, `tools/headless.sh`, greps, reads, docker, `bd`, git, investigation, judging diffs.

Route by the kind of work, then take the first implementer in that row that can run:

| Work | Route, in order |
|---|---|
| Coding of any kind: routine or challenging, one module or several, engine behaviour included | DeepSeek → Codex → `sonnet` → `opus` |
| Observation or reproduction design: write the key script, choose what to observe, judge the result | Codex → `sonnet` |
| Running a given reproduction: key script, seed and options supplied; report what the output shows | `haiku` → `sonnet` |
| Mechanical find/replace | `haiku` |

DeepSeek is the primary implementer. Claude MUST split coding work into phases that DeepSeek can finish, and MUST NOT send a phase to `sonnet` because it looks hard. DeepSeek runs ONE phase per run; NEVER send it a brief that continues an earlier run. Size each phase to finish in about 40 steps. `tools/opencode_ds.sh` puts `tools/opencode/brief_preamble.md` (context budget and implementer rules) in front of every brief, so a brief need not repeat them. The wrapper stops a run when one step's context passes 100K tokens (`INCURSION_DS_CONTEXT_CEILING`), records `"killed": "context"` in the ledger and exits 4; the loop detector stops a repetition loop and exits 3. Both leave the run's changes in the worktree. After either stop, Claude reviews the changes, splits what remains into a smaller phase and starts a fresh DeepSeek run. Only when a second DeepSeek run on the same phase also stops does the phase move to the next implementer in its row. A `haiku` agent MUST NOT judge whether a defect reproduced beyond reporting what the output shows; Claude judges.

`tools/dispatch_gate.py` (a PreToolUse hook in `.claude/settings.json`) blocks every Agent dispatch that does not name `model: "haiku"`, unless its description starts with one of three labels: `research:` (no tracked file changes: reading, collecting facts, a dossier brief), `repro-design:` (the observation row above), or `fallback: <run>`, where `<run>` names a DeepSeek run dir from `logs/deepseek-ledger.jsonl` that stopped on a loop or the ceiling, after an earlier stopped run in the same worktree. NEVER put `research:` on a dispatch that changes a tracked file. It logs every such dispatch to `logs/dispatch-log.jsonl`; `tools/dispatch_report.py --since <date>` counts dispatches by label next to DeepSeek runs. `INCURSION_DISPATCH_GATE_OFF=1` bypasses it, for an emergency only, and is logged.

How to run each:
- Codex: `~/Scripts/Incursion/tools/codex_exec.sh <worktree> <brief>`. It runs `codex exec` under `tools/watchdog.sh`, which stops a run that writes no event within `INCURSION_WATCHDOG_STARTUP` seconds (default 180) or goes silent for `INCURSION_WATCHDOG_IDLE` seconds (default 1800); exit 2 then names the limit. NEVER run bare `codex exec`.
- DeepSeek V4.1-Flash in the opencode harness: `~/Scripts/Incursion/tools/opencode_ds.sh <worktree> <brief>` — ALWAYS the shared checkout's copy, because a worktree's copy reads that worktree's config and sandbox profile, which the agent can edit. It runs under the same watchdog, under `tools/opencode/sandbox.sb` (writes only inside the worktree, its cache and temp), and `tools/opencode/opencode.json` denies it every git command except read-only ones (status, diff, log, show, ls-files, rev-parse), and bd, `gh` and `./incursion`. It obeys AGENTS.md "If you are the implementer". NEVER run `opencode` except through this wrapper.
- `haiku`, `sonnet`, `opus`: Agent-tool dispatch with an explicit `model:` override (NEVER inherit the session model). `opus` only when `sonnet` cannot do it; say why. NEVER `model: 'fable'` without Brian's authorisation that conversation.
- Claude's own Edit/Write ONLY when no implementer above can effectively do the work (none can run, or a rule bars every implementer from the file). Before the first edit, Claude MUST tell Brian what it will change and what context it holds, then WAIT for his word, so he can judge that context. Otherwise NEVER Claude's own Edit/Write.

`tools/deepseek.py` stays for one request with no tree access (a text answer, or a self-contained file from a complete spec); it is not an implementer. Both DeepSeek paths read one DeepInfra key from the Keychain entry `incursion-deepseek-scoped` (since inc-zuoa it holds Brian's unrestricted main key) and record every run's cost in one ledger, `logs/deepseek-ledger.jsonl`. No tool refuses a run on cost; Brian controls spending on his card. NEVER mint a scoped or capped key. If DeepSeek stops answering, read the error and the ledger, and ask Brian before any billing action.
Why: matches each implementer to the work it does reliably, keeps DeepSeek out of the long runs where it loops, and keeps implementation detail out of Claude's context.
History: docs/rules-history/codex-dispatch-and-orchestration.md#always-implement-via-codex. Bead inc-xiqb.

## model-outage-leave-a-note
When an implementer model family stops on a usage limit (Codex, DeepSeek, a Claude model), write a note for other agents at once: `bd remember --key <family>-out-until-<YYYY-MM-DD> "<text>"`, run from `~/Scripts/Incursion`. The text MUST give the return date and time the error states, the rung to skip until then, and the delete command `bd forget <key>`. Before you dispatch, run `bd memories out-until` and skip any family a note names. When you see a noted family work again, run `bd forget <key>` at once.
Why: without a note, every later session tries the dead family first and loses a dispatch to the same error.
History: new rule, no prior narrative to archive. Bead inc-3y49.

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

## bd-prime-search-memories-dont-read-all
Do NOT read the persisted `bd prime` output in full: it prints every bd memory (509 KB at 219 memories). Read its workflow section, then search for the task's topic with `bd memories <keyword>`. `CLAUDE.md` opens with `@AGENTS.md`, so the gap the old rule closed stays closed.
Why: a full read costs more context than the work it prepares for.
History: docs/rules-history/codex-dispatch-and-orchestration.md#read-the-persisted-bd-prime-output-first.
