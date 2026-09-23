# Communication and reporting

## feedback-a-question-about-a-bug-is-still-a-question
"Is this a bug?" / "why does it do that?" are QUESTIONS, not work orders. ANSWER AND STOP — no diagnosis, fix, or bead; wait for the literal word "go". Covers a bug Brian reports or one found in requested work, not one he's asking you to confirm exists. Test: does his sentence end in a question mark about the DEFECT, not the FIX? If you overreach: state it plainly, give the exact revert command, no grovelling, wait.
Why: narrows `feedback-no-work-without-an-ok` to where a question stops being one.
History: docs/rules-history/communication-and-reporting.md#feedback-a-question-about-a-bug-is-still-a-question.

## feedback-ask-followups-before-answering
Before answering a non-trivial question, name the 1–3 assumptions it turns on and ask — do NOT assume what Brian means. Ask when a request contains a problem/inconsistency/bad idea; don't silently work around or disprove it. Applies to questions and tasks, mid-answer too. Execution work (grep/read/compute) needs no permission — only ask about MEANING and INTENT.
Why: answering the wrong interpretation wastes the whole answer.
History: docs/rules-history/communication-and-reporting.md#feedback-ask-followups-before-answering.

## feedback-mechanism-prose-style
Explaining a mechanism: (1) one line saying what it IS physically, not its code purpose; (2) name every object once, then never use another word for it; (3) narrate as actors, role-names not identifiers; (4) state the fault line on its own line; (5) working and broken cases separately; (6) end with the counterfactual. Plain version first, get it accepted, THEN add file/line/code as a second pass — never together.
Why: Brian cannot check a claim he cannot picture.
History: docs/rules-history/communication-and-reporting.md#feedback-mechanism-prose-style.

## feedback-never-paste-multiline-give-a-file
NEVER give Brian multiline text to paste into the terminal (corrupts). When he must use it elsewhere, WRITE TO A FILE, give the path. One-line chat answers are fine.
History: docs/rules-history/communication-and-reporting.md#feedback-never-paste-multiline-give-a-file.

## feedback-never-report-unverified-state
NEVER assert a state you haven't just inspected. The tool call that started something MUST appear above the sentence claiming it started, same message. End with what's true, not what's next — state next steps as intent, never status. Inspect before characterising a process: `pgrep`, `ps -o etime`, `sample <pid>`, the output file. Don't say a report/log/artefact exists without listing it.
Why: prose and tool calls are separate channels with nothing forcing agreement.
History: docs/rules-history/communication-and-reporting.md#feedback-never-report-unverified-state.

## feedback-incursion-brian-tests-faster
Claude CAN drive Incursion: `screencapture -R<x,y,w,h>` captures the window; `osascript` System Events sends keystrokes; rect via `tell application "System Events" to tell process "incursion" to return (position of window 1) & (size of window 1)`. Prefer asking Brian to play and hand over `logs/errors.log`. Reserve GUI driving for verification he can't do, or unattended runs. NEVER drive his GUI while he's using the machine unless asked.
Why: a keystroke → screenshot → read round trip costs many turns for what he does in seconds.
History: docs/rules-history/communication-and-reporting.md#feedback-incursion-brian-tests-faster.

## feedback-one-paragraph-at-a-time
For prose Brian must approve (Desc, item description, voice lines, help text, release notes, player-facing message): write ONE paragraph, hand it over, WAIT for feedback before the next. Do NOT draft the whole piece or a "first pass". Fold corrections into the next paragraph. Does NOT apply to reports/analysis/answers — only text that will BE the product.
Why: a long draft in the wrong voice is a whole piece to throw away, and he must read all of it to say so.
History: docs/rules-history/communication-and-reporting.md#feedback-one-paragraph-at-a-time.
