# Archived full text -- not auto-loaded. The loaded rule lives in .claude/rules/autonomy-and-scope.md.

# Autonomy and scope

## feedback-bug-edits-need-no-approval
**OVERRULED 2026-09-17.** A bug report is not a work order. Do NOT act on the
rule below -- it no longer holds. `feedback-no-work-without-an-ok`, below, and
the "No autonomous work" section of AGENTS.md govern instead. Bead inc-wknz.

SCOPE SET 2026-09-09, angrily, after a session closed 8 beads then presented issue/fix/blast-radius on inc-upw.3 and stopped: 'YOU DO NOT NEED TO ASK ME FOR EVERY FUCKING BUG EDIT, ONLY THOSE GOING TO OTHER REPOS.' A bug in Brian's OWN repo is a work order: read, edit, build, run the checks, then report what changed. Do NOT ask first. This REPLACES the old CLAUDE.md standing order ('a bug report is not a work order, you MUST NOT change a file until Brian says go'), which was written after the 2026-08-23 Boots of Providence incident (inc-izuu) and which a session correctly followed on 2026-09-09 -- that is why he was angry at the rule, not at the session. Same shape as the publishing scope he set 2026-09-08. ONE PRINCIPLE: his tree, his bugs, go; somebody else's tree, ask. STILL NEEDS HIS WORD: (1) anything aimed at a tree he does not own (rmtew or third party); (2) committing and pushing -- separate rule, save/commit means stop; (3) work that is not a bug fix -- feature, refactor, spec, rule change, or user-facing text (README, docs, release notes, store pages). A QUESTION IS STILL A QUESTION: if he asks why something behaves as it does, answer it, do not repair it -- that is the real residue of inc-izuu, which was a scope failure not a permission failure. Written into CLAUDE.md and AGENTS.md 2026-09-09; both files uncommitted.

## feedback-no-work-without-an-ok
**REAFFIRMED 2026-09-17** over `feedback-bug-edits-need-no-approval`, above,
which had claimed to replace it. Bead inc-wknz.

A BUG REPORT IS NOT A WORK ORDER. Do not edit a tracked file, build, or commit until Brian says go. Answer with three things and stop: the issue and its evidence, the fix file by file, and the blast radius.

**Why:** on 2026-08-23 he reported that the Boots of Providence pay no Luck bonus when carried, and asked for nothing else. The session diagnosed it and then edited four tracked files, rebuilt both binaries and the module, and filed a bead, all unasked. He stopped it mid-run. An unwanted question costs him a minute; unwanted work costs him a review and a revert.

**How to apply:** investigation is allowed and expected -- read, grep, build a probe in the scratchpad, run tools/headless.sh to prove the defect. Editing a tracked file is not investigation. The rule has no size exemption and overrides the task-sizing rule that lets small work skip approval. It is written at the top of the project CLAUDE.md as a standing order. See [[incursion-boots-providence-carried]].

**Second incident, 2026-09-14 (inc-pu6v.23):** AN ANSWER TO A DESIGN QUESTION IS NOT A GO. The session asked 'Say go and I will implement it', Brian replied with a correction instead, and later answered a separate design question with 'Yes' plus 'I will be dogfooding this until it is ready for release'. The session read that as a go, started editing three tracked files, and he stopped it with 'Whoa, are you writing code?' then 'STOP'. Wait for the literal word go, or an unambiguous instruction to implement. Context about release plans is not one. See [[resume-2026-09-14-revocation-design]].

## feedback-close-beads-without-asking
Fixed it? Close the bead. Do NOT wait for Brian to confirm. Stated as a standing rule on 2026-08-20, after I fixed inc-upw.39, tested it, committed it, and then left the bead open 'rather than closing work you have not seen land'.

His words: 'Fix it? Close it. Don't wait on confirmation unless absolutely necessary. If you can confirm, do so, but otherwise just close. I'll reopen if needed.'

**Why:** reopening a bead costs him one command. Asking him to authorise a close costs him a round trip, and it arrives at the end of a task he has already followed. Holding the bead open is not caution; it is handing back an unfinished chore. He owns the reopen, so the asymmetry runs in favour of closing.

**How to apply:** close the bead in the same turn as the fix, once the work is verified. Prefer closing WITH the confirmation attached -- a test result, a gate run, a check that went red and then green -- so the closing comment carries the evidence. Only leave one open when closing would be actively wrong: the fix is unverified, the work is genuinely partial, or a dependent bead needs it as a marker. Say which of those applies if you do leave it open. This generalises past beads to any 'shall I finish this?' question at the end of a task: if the deciding evidence is already in hand, act on it. See [[incursion-never-mark-a-question-settled]] -- closing a bead is reversible, writing 'settled, do not re-open' is not, and only the second one is the trap.

## no-interim-state-questions-in-an-atomic-epic
DO NOT ASK BRIAN ABOUT INTERIM STATES INSIDE AN EPIC THAT LANDS AS ONE PIECE. He ruled this on 2026-09-12 while inc-pu6v.18 (the signed favour axis) was being built: 'None of this shit will be run until the god bits (at least for one) is done. Non issue what the default is, don't care.'

WHAT THE MISTAKE WAS. The axis bead implements section 5 of its design: a god who never met you does not notice your conduct unless he opts in with a new flag. No god in lib/religion.irh declares that flag yet, because the seventeen god beads set it. So between the axis landing and the first god bead landing, five DevourMonster transgressions and Essiah's exploitation transgression stop registering for a character who never worshipped those gods. A session raised that as a question worth his ruling. It is not: nothing in the epic is PLAYED until a god is finished, so no player ever experiences the interim.

HOW TO APPLY. Epic inc-pu6v lands as one piece, on branch inc-pu6v, after every god is done. For any bead inside it, a behaviour that is wrong ONLY during the window between two beads of the same epic is not a question and not a defect -- implement the design as written and say nothing. What still IS worth raising: a defect that survives the epic landing, a contradiction inside the settled design itself, and anything that would corrupt a save or crash. Those are real. 'This will look odd until bead N lands' is not.

RELATED: the same conversation produced two genuine escalations that were right to raise -- e.EParam carrying a raw favour debt into a script that throws (e.EParam)d6, and the deleted anger-wraparound guard letting the debt wrap int32. Both survive the epic. That is the line.

## commit-problem-investigate-dont-dismiss
FEEDBACK (2026-09-03, Brian, sharp): when something goes wrong at commit/build/push time -- a hook rejects, a check fails, a file lands where it should not -- DO NOT dismiss it with 'not mine' / 'nothing fails' / 'not it' and move on. Stop, investigate the actual root cause, and PRESENT what is going on. DO NOT FIX IT unless asked. Present the diagnosis and wait. Why: a fast 'not it' hides real problems and reads as laziness; he wants the truth of what happened, then he decides. How to apply: on any commit/build/push anomaly, spend the effort to trace it, report issue+evidence+blast-radius (repo standing order), then STOP. See [[incursion-standing-order-no-work-without-ok]].

## escalated-questions-check-the-commit-first
Before escalating a question to Brian, read the commit that introduced the thing you are asking about. The answer is often already in its body.

inc-loa.12 is the worked example. It held check_probe_hooks.sh red on master from 2026-08-23 to 2026-08-25, asking Brian which bead INCURSION_STAIR_WARN_PROBE serves, on the stated ground that 'choosing the id needs someone who knows which bead the stair-warning change belongs to'. That ground was false. Commit 6f578a5, which added the probe, ends its own body with 'inc-wcf', and the same commit added tools/check_stair_warn.sh and docs/evidence/inc-wcf/. A second hook failing the same check, INCURSION_DEQU_FORCE_SAVE, was never escalated at all; its id inc-473 sits at src/Fight.cpp:2015 and in the ledger row.

**Why:** three sessions repeated the escalation because each read the BEAD and not the COMMIT. A held bead is a claim that the question is unanswerable, and that claim ages badly and is never re-tested. Meanwhile the failure appeared in the session-start hook, in tools/nightly_verify.sh's header comment and in two commit bodies, which is how one P3 one-liner became noise in everything.

**How to apply:** when you meet a needs-brian bead, spend one minute on git log -S or git log --format=%B on the introducing commit before you repeat the escalation. If the answer is there, act and say in the close note that the escalation reason was wrong. Do not let a held question's age stand in for its validity.
