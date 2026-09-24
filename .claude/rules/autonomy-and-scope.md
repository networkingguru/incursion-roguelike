# Autonomy and scope

## feedback-bug-edits-need-no-approval
**OVERRULED 2026-09-17.** Superseded by `feedback-no-work-without-an-ok` below and AGENTS.md "No autonomous work". Do not act on this entry.
History: docs/rules-history/autonomy-and-scope.md#feedback-bug-edits-need-no-approval.

## feedback-no-work-without-an-ok
**REAFFIRMED 2026-09-17.** A bug report is NOT a work order. Do NOT edit a tracked file, build, or commit until Brian says the literal word "go" or gives an unambiguous instruction to implement. A design-question answer or release-plan context is NOT a "go". On any bug found or handed to you: state the issue and its evidence, the fix file by file, and the blast radius, then STOP. Investigation (read, grep, a scratchpad probe, `tools/headless.sh`) needs no permission; editing a tracked file does. No size exemption.
Why: unwanted work costs a review and a revert; a question costs a minute.
History: docs/rules-history/autonomy-and-scope.md#feedback-no-work-without-an-ok.

## feedback-close-beads-without-asking
Close a bead's fix in the SAME turn you verify it. Do NOT wait for confirmation. Attach the verifying evidence (test result, gate run) in the close comment. Leave a bead open only if: the fix is unverified, the work is genuinely partial, or a dependent bead needs it as a marker — say which.
Why: reopening costs one command; asking to close costs a round trip.
History: docs/rules-history/autonomy-and-scope.md#feedback-close-beads-without-asking.

## no-interim-state-questions-in-an-atomic-epic
Inside an epic that lands as one piece, do NOT ask about behaviour that is wrong only in the window between two beads of that epic — implement the design as written and say nothing. Do raise: a defect surviving the epic landing, a contradiction in the settled design, or any save-corruption or crash risk.
Why: nothing in the epic is played until it is finished, so no player sees the interim state.
History: docs/rules-history/autonomy-and-scope.md#no-interim-state-questions-in-an-atomic-epic.

## commit-problem-investigate-dont-dismiss
On any commit/build/push anomaly (hook rejects, check fails, file lands wrong) in work you did NOT produce: do NOT dismiss it as "not mine". Investigate the root cause, report issue + evidence + blast radius, do NOT fix it unless asked, then STOP. A failure in your own work is `fix-your-own-merge-blockers`, not this entry.
Why: a fast dismissal hides real problems.
History: docs/rules-history/autonomy-and-scope.md#commit-problem-investigate-dont-dismiss.

## fix-your-own-merge-blockers
When a commit hook, `tools/finish_bead.sh` or any merge gate fails on work you produced (your bead's diff, a file you or your implementer wrote), FIX IT AND RE-LAND. Do NOT ask Brian, do NOT stop to report first, do NOT offer options. This overrides "save/commit means stop" and AGENTS.md "No autonomous work" for that fix only: dispatch the fix per `always-implement-via-codex`, re-run the failing checks, commit on the bead's branch, run `tools/finish_bead.sh <bead-id>` again. Report once, after it lands, naming what failed and what you changed. STILL stop and ask when: the failure is in code you did not produce; the fix needs a change to behaviour Brian ruled on; or the fix would weaken a check, baseline or guard.
Why: a gate failure on your own work is your housekeeping, and asking costs Brian a round trip for no decision.
History: docs/rules-history/autonomy-and-scope.md#fix-your-own-merge-blockers.

## escalated-questions-check-the-commit-first
Before escalating a needs-Brian question, run `git log -S<term>` or `git log --format=%B` on the commit that introduced the thing in question — the answer is often already in its body. If found, act on it and note the earlier escalation was wrong.
Why: a held question's age is not evidence it is still unanswerable.
History: docs/rules-history/autonomy-and-scope.md#escalated-questions-check-the-commit-first.
