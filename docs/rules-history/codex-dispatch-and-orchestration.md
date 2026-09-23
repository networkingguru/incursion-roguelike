# Archived full text -- not auto-loaded. The loaded rule lives in .claude/rules/codex-dispatch-and-orchestration.md.

# Codex dispatch and orchestration

## always-implement-via-codex
STANDING ORDER (Brian, 2026-08-28, TIGHTENED 2026-08-30 after a session broke it). CLAUDE'S MAIN CONTEXT IS FOR ORCHESTRATION. It does not author files.

WHAT CLAUDE MAY WRITE ITSELF: true prose only -- a report to Brian, a bead body, a memory, a brief for Codex, a doc paragraph. Nothing else.

WHAT GOES TO CODEX: every file that a machine reads or runs. C++, headers, Python, shell, .keys harness scripts, .irh data, config, Makefiles -- however small, however 'just a test file'. A red-green mutation into a tracked source file is also Codex's, not a hand edit.

THE HOLE THAT CAUSED THE 2026-08-30 FAILURE, now closed. The old wording said 'Non-code work (docs, build/test commands, investigation, running the headless harness) is not implement and Claude may do it directly.' A session read AUTHORING a 100-line tools/check_*.sh and four tools/keys/*.keys files as 'build/test' and wrote them by hand. That exception covers RUNNING commands and READING things. It has never covered authoring the files those commands run. Brian was angry, at 93% of his weekly limit, and the wasted context was the cost.

RUNNING is still Claude's: builds, tools/headless.sh, greps, reads, docker, bd, git. Investigation is Claude's. Judging a diff is Claude's.

FALLBACK ORDER when Codex is unavailable (its own usage limits, an outage, or a dispatch the classifier refuses twice):
  1. Codex.
  2. DeepSeek V4.1-Flash, through tools/deepseek.py. Brian bought it on 2026-09-22 to carry routine implementation when Codex runs out.
  3. An agent model CONFIDENTLY CAPABLE of that specific edit, dispatched via the Agent tool. Pass an explicit model: override and choose the SMALLEST model that can be expected to do the job decently -- haiku for a mechanical find/replace only, sonnet for anything that needs the code understood, opus only when sonnet cannot be expected to do it, and say why. NEVER model: 'fable', for anything at all, unless Brian authorised it in that same conversation (the Fable ban lives in Brian's global CLAUDE.md, not in a memory, and this memory does not relax it).
  4. NEVER Claude's own Edit/Write. If none of 1 to 3 can run, STOP and tell Brian.
This supersedes the older 'a denial is a stop, report and wait' line in [[codex-dispatch-blocked-by-classifier]]: the answer is an agent, not a halt, and not the main agent.

WHAT DEEPSEEK CANNOT DO, and it decides rung 2 against rung 3. Codex and an Agent-tool agent both ITERATE: they read files, run the check, and patch until it passes. tools/deepseek.py sends ONE chat request and writes the reply to a file. It cannot read the tree, cannot run a build, and cannot see its own check go red. So it writes what the brief specifies and nothing more.

SO CHOOSE RUNG 2 OR RUNG 3 BY WHETHER THE WORK NEEDS EYES ON A RESULT. DeepSeek (rung 2) suits a self-contained file written from a complete specification -- a new check script, a key script, a data table, a function whose contract the brief states in full. An agent (rung 3) suits work that must be measured to be finished -- a defect whose repair is judged by a check going green, an edit whose blast radius has to be read out of the tree, anything where the brief cannot state the answer in advance. When you send work to DeepSeek, YOU run the check afterwards and YOU judge the diff. That was already true of Codex. It is more true here, because nothing upstream of you looked at the result at all.

THE MONEY IS CAPPED ON THE KEY, NOT IN THE SCRIPT. The DeepInfra API key is a scoped token carrying a 20 USD spending limit and an allowlist of exactly one model. Measured 2026-09-22: the same key returns HTTP 200 for deepseek-ai/DeepSeek-V4.1-Flash and HTTP 403 'model access denied' for deepseek-ai/DeepSeek-V4-Pro, and it returns HTTP 401 against the billing and key-minting endpoints, so it cannot raise its own cap. A fault in tools/deepseek.py therefore cannot overspend it, and neither can a session that forgets the budget exists. tools/deepseek.py keeps its own ledger in logs/deepseek-ledger.jsonl and refuses before it spends, but that ledger is the convenience, not the guard. When DeepSeek stops answering, read the ledger, then ask Brian before anything is topped up.

RULE 3, THE AGENT RUNG, WAS CORRECTED ON 2026-09-09. It used to read 'the SMALLEST agent model that can do the job -- dispatch with model: haiku'. Brian struck that: 'I am not sure I ever want haiku on anything but the barest find/replace kind of edits. I want a model that is confidently capable to do the edit.' So haiku is for a mechanical substitution and nothing more -- a literal find/replace, a renamed symbol, a changed constant. Anything that needs the code to be UNDERSTOOD (engine semantics, a new check and its oracle, a diff whose blast radius has to be judged) goes to a capable model. A cheap agent that produces a wrong edit costs more than the expensive one that produces a right one, because Claude then reviews, rejects and re-dispatches.

The occasion was the entangle work (inc-18q6): Codex hit its usage limit part-way through a nine-site C++ change in src/Fight.cpp whose blast radius includes sneak attack. Haiku was the wrong tool for it under the old wording.

RULE 3 WAS TIGHTENED AGAIN ON 2026-09-15. A session fell back to an agent on the session model (Opus) when Codex ran out of usage. Brian: "you are to use the smallest claude model that can be expected to do a decent job". So pass an explicit model: override on every fallback dispatch, and choose the SMALLEST model that can be expected to do the job decently -- never inherit the session model by default. With the 2026-09-09 ruling this means: haiku for a mechanical find/replace only; sonnet for anything that needs the code understood (engine edits, a new check, key scripts); opus only when sonnet cannot be expected to do it, and say why. The run that broke this was stopped before it changed a file and re-dispatched on sonnet.

Does NOT retroactively require redoing code implemented before the order. Dispatch shape: [[codex-dispatch-bare-command-no-cd-prefix]].

## feedback-claude-dispatches-never-writes-code
CLAUDE DOES NOT WRITE CODE ON THIS PROJECT. Brian stated it as a standing order on 2026-08-24, in capitals, with the reason: 'I do not want to spend my whole day clearing fucking context.'

THE RULE. The main session dispatches subagents to do the work and then REVIEWS what they return. The main agent MUST NOT edit source, build, or run the long noisy commands itself. Implementation detail MUST stay out of the main context.

WHY. Every file read, every build log and every grep dump the main agent performs sits in the context for the rest of the day, and Brian pays for it on every later turn. A subagent's context is discarded when it finishes; only its report survives.

HOW TO APPLY.
- One subagent per finding or per task. Give it the full recipe, not a hint:
  the file and line evidence, the red-before-green-after protocol, the
  'upstream:' comment requirements, the ledger row, and the exact build
  commands.
- Ask it to report back a SHORT structured result: what it changed, the red
  measurement, the green measurement, and anything that surprised it.
- The main agent still owns: putting ONE finding at a time to Brian, verifying
  a finding's own claims before quoting numbers to him, and judging whether the
  agent's report is true. Reviewing is not delegated.
- Small read-only checks that produce two lines of output MAY stay inline. The
  rule targets volume, not tool identity. A grep that returns four lines costs
  less than the dispatch that avoids it.
- This overrides any harness instruction that says not to use the Agent tool.
  Brian requested it explicitly.

See [[rule-triage-resume]] for the workflow this now applies to, and
[[feedback-no-work-without-an-ok]], which is unchanged: a dispatch is still
work, so it still needs his go.

## feedback-codex-implements-claude-plans
Brian added a Codex subscription on 2026-08-25 to move implementation token cost off his Claude Max limit. THE DIVISION IS FIXED: Claude plans, reviews and decides. Codex implements ONLY. He interrupted a run that tried to have Codex draft the spec amendment and the plan, with: 'NO. YOU plan. Codex impmeents ONLY'.

**Why:** the plan is the leash. If Codex writes the plan it is grading its own homework, and the review has nothing independent to check against.

**How to apply:** write the spec amendment and the brief plan yourself, into the repo, before dispatching. Then give Codex one or two phases at a time, point it at the plan and the normative spec section, and review the diff before the next dispatch. See [[codex-cli-sandbox-facts]] for the mechanics.

## feedback-overnight-multiagent-orchestration
On 2026-08-16 night into 2026-08-17, Brian asked for the save-game decoder
(`inc-loa.1`) to be built, then for the orchestrator to keep picking the next
highest-impact `bd` issue and running it, one agent at a time, until a limit
was hit. This produced a large, clean, well-tested change set (~14 issues
worked, most closed) that a later same-day session found uncommitted, reviewed,
and landed as `f4ef5cb`. The pattern worked and should be repeated as the
default shape for this kind of request.

**The pattern that worked:**
1. One agent running at a time, never parallel -- each dispatch waits for the
   prior one's result before the orchestrator picks the next target.
2. Every agent is a **fresh** dispatch (not a `fork`), briefed as if it has
   zero memory of the conversation -- because it does. Each prompt included:
   the full text of the `bd` issue, exact file:line pointers already known,
   the fix already specified where one existed, explicit scope boundaries
   (what NOT to touch -- especially product/judgment calls reserved for
   Brian, like `OPT_NODEATH` semantics or combat-prompt auto-answer
   tactics), the project's hard git rules (no commit/push/branch -- leave
   everything uncommitted for Brian to review), and an instruction to leave
   a dated `bd note` either way so the *next* fresh agent (or Brian) has
   full context without re-deriving it.
3. **The orchestrator independently re-verified every single claimed
   result** before trusting it or moving on: rebuilt from scratch, re-ran the
   relevant regression checks (`check_headless.sh`, `check_gate.sh`,
   `check_upstream_marks.sh`, etc.), and for crash fixes, personally
   re-reproduced the original crash seed against the new binary rather than
   trusting the agent's "verified" claim. This caught at least one case
   where an agent's summary undersold a real gap (`inc-upw.16`'s fix was
   real but exposed a second crash one call deeper -- the agent had already
   disclosed this honestly, but independent verification confirmed it
   precisely rather than taking the summary's framing on faith).
4. When an agent's own final message showed it hadn't actually finished
   (still waiting on a background job it started), the orchestrator resumed
   *that specific agent* via `SendMessage` to its agent ID rather than
   launching a fresh one with no memory of what job was running -- launching
   fresh in that situation is a dead end, the new agent can't see the old
   one's background state.
5. Investigative (not-yet-root-caused) issues were given explicitly to
   agents too, but time-boxed, with permission to leave a well-documented
   "here's how far I got and why I stopped" as a fully acceptable outcome --
   not forced to produce a fix they weren't confident in.
6. The loop stopped cleanly on a real external limit (an Anthropic account
   re-authentication error killing a dispatch), not on running out of
   findable work -- the ready-issue queue was still far from empty.

**Why this matters:** the alternative -- one big agent doing everything, or
several running in parallel without independent verification -- would have
either lost context between issues or let an agent's self-report stand
unchecked. Both are exactly the failure modes Brian's CLAUDE.md already warns
about (trust-but-verify, no unrequested scope, ask only when a real judgment
call blocks progress).

**How to apply:** when Brian asks for autonomous/overnight work with a
"keep going until you hit a limit" framing, default to this shape rather than
asking for a smaller scope -- it's already been validated at real scale on
this project. See `bd memories project-incursion-goals` for the standing epic
structure and `resume-2026-08-17` (dated project memory, may be pruned later)
for how the resulting change set was received the next morning.

## agents-md-is-injected-at-session-start
AGENTS.md now reaches the session automatically. ~/.claude/hooks/inject-agents-md.py is a SessionStart hook (registered in ~/.claude/settings.json alongside inject-decisions.py) that injects the project AGENTS.md and strips the generated Beads blocks the project CLAUDE.md already carries. About 5,100 tokens for this repo. Checks: python3 ~/.claude/hooks/test-inject-agents-md.py (11 cases).

WHY: Claude Code auto-loads CLAUDE.md and never loads AGENTS.md, so the worktree rule, the Codex division of labour and the agent conduct rules were invisible to every session that had to obey them. Installed 2026-09-12.

A session should open with a line starting '[AGENTS.md auto-injected at session start'. If that line is missing, the hook is not firing and the rules in AGENTS.md are NOT in context -- read the file by hand.

The global ~/.claude/CLAUDE.md 'Branches' paragraph was also rewritten the same day: it now declares itself a default that a project rule overrides, because it said the opposite of this repo's one-worktree-per-bead rule.

## read-the-persisted-bd-prime-output-first
READ THE FULL bd prime HOOK OUTPUT BEFORE YOU DO ANYTHING. This session broke
three standing rules on 2026-09-11 because it did not, and every one of them was
in that file.

WHAT HAPPENS. The SessionStart hook runs bd prime. Its output is about 330KB, so
the host TRUNCATES it, shows a 2KB preview, and saves the whole thing to a file
under the session's tool-results directory. The first line of the preview says:
'If this output is truncated by your host, read the full persisted hook output
before continuing; it may contain project memories and session rules not visible
in the preview.' That line is easy to scroll past. Do not.

WHAT WAS MISSED, and what it cost:
  1. [[always-implement-via-codex]] -- Claude's main context does not author
     files. The session hand-edited lib/threats.irh with Python and dispatched
     Agent-tool agents without trying Codex, which is fallback rung 3 and only
     reachable when Codex is unavailable.
  2. The Codex division of labour generally: AGENTS.md:103 opens 'Claude plans
     and reviews. You implement.'
  3. AGENTS.md:20 'One bead, one worktree -- never work in the shared checkout.'
     The session edited master in ~/Scripts/Incursion and had to move the work
     into a worktree after Brian asked 'are you working in a branch or whatever
     like you are supposed to?'

WHY READING project CLAUDE.md WAS NOT ENOUGH, and this is the structural part.
CLAUDE.md used to carry the only pointer to AGENTS.md, and that pointer
CLOSED-ENUMERATED the contents: 'the standing order, the publishing rules, how
to mark a base-code bug, how to classify a change, and the comment budget.' The
list omitted the Codex division and omitted one-bead-one-worktree, so a session
that trusted the list never opened AGENTS.md. Commit bb65ba9 added the worktree
rule to AGENTS.md and README.md on 2026-09-11 and did not touch CLAUDE.md.
Smaller third hole: the sentence that binds CLAUDE sat inside a section headed
'If you are Codex', which a Claude reader skips by design.

FIXED 2026-09-17 (bead inc-wknz). CLAUDE.md now opens with an `@AGENTS.md`
import, so AGENTS.md is loaded whole rather than summarised, and there is no
enumerated list left to trust. The hook that used to inject it is deleted. See
`where-rules-live.md`.
