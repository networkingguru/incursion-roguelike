# Verification methodology

## incursion-verification-oracles-that-cannot-fail
Every verification tool MUST be proved to go RED before its green result is worth anything. Break the thing it guards, rebuild, watch it go red, restore — if it can't fail, it's not evidence. Verify a reported defect is real before fixing code. A tool MUST FAIL, not pass, when it cannot establish what it's looking at. A resolving citation isn't necessarily true — re-read the claim against the source; no tool catches that.
Why: a check that cannot fail converts "unknown" into "verified" and stops anyone looking.
History: docs/rules-history/verification-methodology.md#incursion-verification-oracles-that-cannot-fail.

## incursion-a-diagnosis-needs-its-falsifier
When filing a defect diagnosed by READING code, state what observation would prove it wrong, plus the evidence tier: Observed, Traced, or Reasoned.
Why: a diagnosis with no stated falsifier survives even when later evidence contradicts it.
History: docs/rules-history/verification-methodology.md#incursion-a-diagnosis-needs-its-falsifier.

## incursion-check-for-a-live-instance
Before filing/ranking a code-read defect, check for a LIVE INSTANCE: does the type/resource exist (`grep lib/program.i`)? does any script/call site reach the path (`grep lib/program.i`, `dispatch.h`)? which branch does a PLAYER take (read the whole function)? File it anyway if unreached — say LATENT, state what would make it live.
Why: unreachable-in-play is a different severity than a defect a player will hit.
History: docs/rules-history/verification-methodology.md#incursion-check-for-a-live-instance.

## incursion-check-the-world-not-the-tracker
Before telling Brian about a published PR/comment/release/test, check the thing itself. Outward-facing state comes from `gh` (`gh issue view N --repo rmtew/incursion-roguelike --comments`, `gh release view`), NEVER `bd`, a `docs/outgoing/` file, or memory. Grep his transcripts (`~/.claude/projects/-Users-brianhill-Scripts-Incursion/*.jsonl`) before claiming untested/unanswered/unsent. Fix a stale note while reporting the truth.
Why: a bead note can be written before an action and never updated.
History: docs/rules-history/verification-methodology.md#incursion-check-the-world-not-the-tracker.

## incursion-measure-where-the-value-lands
Before quoting an effect, read where the value FINALLY lands, not an intermediate input. Grep the callee chain for downstream clamps/truncations/early returns. Check whether the measuring probe itself contributes to the reported number.
Why: an intermediate value can be corrected downstream, or a proxy can be reported as the final effect.
History: docs/rules-history/verification-methodology.md#incursion-measure-where-the-value-lands.

## incursion-never-mark-a-question-settled
NEVER write "settled, do not re-open". State a conclusion with its code path, not its status. Give a reviewer the code path and invite contradiction. A claim built on reading N lines is worth exactly N lines — read to the end of the function.
Why: marking a question settled tells future readers not to look, so a wrong conclusion propagates.
History: docs/rules-history/verification-methodology.md#incursion-never-mark-a-question-settled.

## incursion-test-the-path-the-user-takes
Verify on the path the USER takes. A locally-created file has no `com.apple.quarantine` attribute, so a local test CANNOT detect a Gatekeeper refusal even on a signed/notarised release. Before claiming a release works: download it from where the user gets it, set the quarantine attribute, launch it their way. Avoid an oracle that recomputes its expected value from the same sources it checks.
Why: the build machine's own test path can't exercise a failure only a real download hits.
History: docs/rules-history/verification-methodology.md#incursion-test-the-path-the-user-takes.

## feedback-no-repro-no-work
NO REPRO, NO WORK. No test showing the bug means do NOT work on it — the only goal is a reproduction. A bug with no live repro is NOT eligible as recommended work; rank below any bug with a failing test. When a repro step passes, STOP and report — don't widen the search to prove absence. Writing a reproduction IS legitimate work, its own task. An old bead recording a repro is NOT evidence it still works — run it first.
Why: a fix can't be confirmed without a failing-then-passing test.
History: docs/rules-history/verification-methodology.md#feedback-no-repro-no-work.

## probe-dump-guard-blindness
FIXED. Before trusting a diagnostic-log check, confirm the log records the state under test — grep for the thing itself, not the absence of a complaint (`src/Light.cpp` `ProbeDump` missed spell-cast fog; fixed via `FilterMark()`).
History: docs/rules-history/verification-methodology.md#probe-dump-guard-blindness.

## check-fact-lines-close-the-hole-first
Every commit, on every branch, that adds or changes a `tools/check_*` file runs `tools/check_fact_lines.py` from `.beads/hooks/pre-commit`. It refuses a check with no `# fact: <fact> -- <control>` line, with an empty control, with a control that is only "none" or says "known hole", "pre-existing" or "no control", or with a control that pins a seed and names no bead. When it refuses, follow this order: (1) close the hole yourself: add the control, file the missing hook, or choose a different scenario; (2) if you cannot, bring the hole to Brian: the fact, why no catalog control fixes it, and what you tried, and look for a way together; (3) ONLY when neither of you finds one, ask "Is tools/check_<name> exempt?" in a message that names the hole. His yes (typos allowed) mints a pass for that one commit, through the PreToolUse hook `tools/fact_exempt_pass.py`. A permanent exemption is a `# fact-exempt: <reason>` line, and the commit that adds or changes it needs the same one-commit yes. Exemption MUST be exceedingly rare. NEVER ask the exemption question as the first answer to a refusal. NEVER mint a pass yourself. Verify: `tools/check_fact_lines.py --selftest`, `tools/fact_exempt_pass.py --selftest`.
Why: a check that reads a fact it does not fix breaks on the next resource append, and nothing enforced the header rule before.
History: docs/rules-history/verification-methodology.md#check-fact-lines-close-the-hole-first. Bead inc-131k2.
