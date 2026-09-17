# Communication and reporting

## feedback-a-question-about-a-bug-is-still-a-question
SCOPE, NARROWED BY BRIAN ON 2026-09-09, in the same week he set feedback-bug-edits-need-no-approval. Both are live. This one says where that one stops.

WHAT HAPPENED. He sent a screenshot and wrote 'Explain this message.' The session explained it. He then asked 'Isn't that a bug?' The session read that as the standing order (a bug in his tree IS a work order) and went and fixed it -- traced it, filed bead inc-aocw, built a probe, wrote a headless fixture and a check script, edited two source files and rebuilt both binaries. He interrupted mid-turn: 'Did you fix this? I just asked if it was a bug.'

THE RULE. 'Is this a bug?' is a QUESTION. So is 'why does it do that?'. Neither is a work order. AGENTS.md already said this for 'why', in the residue of the Boots of Providence incident (inc-izuu); the 2026-09-09 reading extends it to 'is it'. ANSWER IT AND STOP. He will say go if he wants the repair, and he did say go, one message later.

WHAT THE STANDING ORDER ACTUALLY COVERS: a bug he REPORTS or hands you, or one you find while doing work he asked for. Not one he is asking you to confirm the existence of.

HOW TO TELL, in one test: did his sentence end in a question mark about the DEFECT rather than about the FIX? Then he wants a verdict, not a diff.

WHAT SAVED IT. The report after the interruption led with the answer, listed every file touched, and gave him the exact revert command. He did not ask for a revert; he asked how the fix worked, then said 'go ahead and finish'. So the recovery from this mistake is: state the overreach plainly, hand him the undo, do not grovel, and wait.

## feedback-ask-followups-before-answering
Brian told me on 2026-08-21 to ASK follow-up questions instead of assuming what he means, and to write the rule down. His words: 'When I ask a q, you always ask follow ups. Do not assume. You are getting me wrong more than right. When you think you see a problem, or inconsistency, or just a dumb idea, ask.'

**Why:** he had asked for an invisible mounted archer build. I assumed 'invisible' meant the INVIS stati and spent a long answer proving invisibility and hiding both break on attack. He actually meant a fog/concealment spell that follows him around, which is a completely different mechanic. The whole answer was wasted because I never asked what he meant by one word.

**How to apply:** before answering a non-trivial question, name the 1-3 assumptions the answer turns on and ask about them. Ask when a request seems to contain a problem, an inconsistency, or a bad idea -- do not silently work around it and do not silently prove it impossible. This is stronger than the global CLAUDE.md rule: it applies to QUESTIONS, not just tasks, and it applies mid-answer as well as before starting. Execution work (grep, read, compute) still needs no permission -- ask about MEANING and INTENT, never about whether to go look something up. See [[feedback-brian-reads-literal-text-before-publishing]].

## feedback-mechanism-prose-style
When explaining how a mechanism works or breaks, use this exact shape. Brian called it "fucking perfect" on 2026-08-19 after rejecting every earlier attempt at the same explanation.

1. **One line first saying what the thing IS in physical terms.** "A room with a smaller room standing inside it. You walk into the room, walk around the subroom, find its door, go in." Not its purpose in the code -- what it looks like on the screen.
2. **Name every distinct object once, in a short list, before the narrative starts.** Panel, room, space, subroom. Then never use another word for any of them. A synonym introduced mid-narrative destroys the whole piece.
3. **Narrate as actors doing one thing each.** "The builder asks the room placer for a spot." Give functions role-names, not their identifiers.
4. **State the fault line explicitly, on its own line.** "That is the fault. Everything after it follows."
5. **Work the two directions/cases separately when one works and one does not.** Showing the working case is what makes the broken case legible.
6. **End with the counterfactual.** "Had it given the 7 it was asked for, the space would have been 3 deep and the subroom would have come back normal."

**Why:** the failure mode is writing in the vocabulary of the code -- variables, branches, "the caller", "the fallback". Brian cannot check a claim he cannot picture, and he will not publish what he cannot check. See `bd memories feedback-never-post-public-unread`.

**How to apply:** write the plain version FIRST and get it accepted, then add file names, line numbers and code blocks as a second pass. Never write them together -- the citations pull the prose back into jargon. Traps hit on the way: inventing a word ("carve", "fallback", "hole") for something the code does not do; presenting an inference in the same shape as a computation; and leading with a cause that measurement does not support. See `bd memories incursion-measure-where-the-value-lands`.

## feedback-never-paste-multiline-give-a-file
HARD RULE, stated angrily and repeatedly (latest 2026-09-03): NEVER give Brian multiline text to copy-paste into the terminal. The terminal corrupts long/multiline pastes. When the deliverable is text he must USE elsewhere (a prompt, a snippet, a doc, a message body), WRITE IT TO A FILE and give him the path to open. This includes code blocks, blockquotes, and any block spanning more than one line. One-line answers in chat are fine; multiline content goes to a file, every time.

## feedback-never-report-unverified-state
Never assert the state of anything you have not just inspected. This failed
twice on 2026-08-18, in two different disguises, and Brian caught both.

1. **A claimed launch that never happened.** A message ended "Running the
   confirming pair on this text now." No agent was launched. The closing line of
   a report is naturally "and now X", and X is the one step still untaken -- so
   the failure clusters at end-of-turn, where the narrative feels finished
   before the work is.
2. **A guessed diagnosis of a live process.** An AddressSanitizer run was
   described as "well over ten minutes" of honest work. It was deadlocked in its
   own initializer and had never reached `main`. One `sample <pid>` settled it
   in seconds. See `bd memories incursion-asan-deadlocks-here`.

**Why:** prose and tool calls are separate channels and nothing makes them
agree. A sentence can describe an action that was never taken, and it reads
exactly like one that was. Brian then builds on a false picture, and has to
spend a message asking "is something running?" to find out.

**How to apply:**
- Launch first, describe second. If a sentence says something is running, the
  tool call that started it MUST already appear above that sentence in the same
  message.
- End a message with what is true, not what is next. State a next step as
  explicit intent ("I will start X next"), never as status.
- Before characterising any process, inspect it: `pgrep`, `ps -o etime`,
  `sample <pid>`, or the output file. "Still going" is a measurement, not an
  assumption.
- The same rule covers files: do not say a report, log or artefact exists
  without listing it.

## feedback-incursion-brian-tests-faster
Claude **can** see and drive Incursion: Screen Recording and Accessibility are
both granted, so `screencapture -R<x,y,w,h>` captures the window and `osascript`
System Events sends keystrokes. Get the rect with `tell application "System
Events" to tell process "incursion" to return (position of window 1) & (size of
window 1)`.

Brian's instruction on 2026-08-13, while watching Claude drive character
creation one screenshot at a time: *"you are slow and I can do it faster."*

**Why:** he is a fast, expert player of this specific game. A round trip of
keystroke -> screenshot -> read costs Claude many turns for something he does in
seconds.

**How to apply:** ask him to play and hand over `logs/errors.log`. That log is
the highest-yield oracle in the project -- three confirmed defects in one
evening, zero false positives. Reserve GUI driving for verification he cannot
perform, or for unattended runs. Never drive his GUI while he is using the
machine unless he asked for it.

See `bd memories project-incursion-goals`.
