# Verification methodology

## incursion-verification-oracles-that-cannot-fail
Every verification tool in Incursion MUST be proved to go RED before its green
result is worth anything. Five have now been caught reporting success on things
they never actually checked:

- `check_api_arity.py` -- `main()` returned 0 on every path but an unreadable
  input, while printing 2 MISALIGNED slots.
- `check_upstream_marks.sh` -- blind to malformed markers, so two real ones went
  unseen for months.
- `check_citations.sh` -- three separate silent passes, including a bogus line
  number in a file it *could* check, under the summary *"Every citation resolves
  in upstream/master"*.
- `FLICKER_PROBE` -- sampled only when the game presented a frame, and the game
  not presenting was the bug. Deleted 2026-08-18.
- The first `MoveDepth` A/B -- both arms ran in a worktree with no live
  `Options.Dat`, so neither arm entered a map. Two runs that measured nothing
  agreed perfectly and produced a false PASS. See
  `bd memories incursion-worktree-ab-needs-live-options-dat`.

**Why:** a check that cannot fail is worse than no check. It converts "unknown"
into "verified" and stops anyone looking. Four of the five above were passing
for weeks.

**How to apply:**

1. Before trusting a check, break the thing it guards, rebuild, and watch it go
   red. Then restore. If you cannot make it fail, it is not evidence.
2. When a check reports a defect, verify the defect is real before fixing the
   code -- `check_citations.sh` reported four correct citations as errors while
   silently passing four wrong ones in the same sentence.
3. Brian's rule, from 2026-08-18: **a tool must FAIL, not pass, when it cannot
   establish what it is looking at.** Silent adoption of a stale or guessed
   context is a hard error, never a shrug.
4. A resolving reference is not a true one. A citation can point at a line that
   exists and still be wrong, because it is not the line the prose described.
   No tool catches that; only a person re-reading the claim against the source.
   Keep that manual pass in the routine.

## incursion-a-diagnosis-needs-its-falsifier
A DIAGNOSIS WRITTEN WITHOUT ITS FALSIFIER GETS RE-READ AS FACT. Put the falsifier in the bead.

WHAT HAPPENED. inc-upw.23, the store menu that would not scroll, was diagnosed on 2026-08-16 and diagnosed WRONG. The bead blamed a hardcoded page height of 32 rows and concluded that scrolling UP therefore still worked. It also wrote down, in plain words, what would disprove it: 'If both directions are broken, this diagnosis is wrong and the fault is elsewhere -- say so and I will look again.'

On 2026-08-19 Brian reported from play that up was broken too. That sentence is the only reason the wrong cause did not survive into the fix. The real cause was elsewhere entirely: BarterManager's redraw label opens with ClearScroll(true), which zeroes TextTerm::offset (src/TextTerm.cpp:720-728), and every arrow key jumps back to that label before the one draw call, so the computed offset was always discarded.

THE RULE. When filing a defect diagnosed by reading code rather than by observing it, state what observation would prove the diagnosis wrong. Say the tier too (Observed, Traced, Reasoned). A bead that only asserts a cause reads, months later, as though the cause were established.

RELATED: incursion-verification-oracles-that-cannot-fail, incursion-check-for-a-live-instance, incursion-measure-where-the-value-lands. Same family -- all four are about not trusting a conclusion whose evidence was never able to come out the other way.

THE REPRODUCTION IS ALSO WORTH KEEPING, because it needs no wizard mode: the cave entrance asks 'Store, Inn, Retire or Descend?' (lib/dungeon.irh:203) and [s] opens Roark Ironbeard's shop with 40-odd stacks. tools/keys/store-scroll.keys does it, and presses [x] at both ends of the list so that a session whose keys never reached the menu cannot pass by accident.

## incursion-check-for-a-live-instance
BEFORE filing or ranking a defect read out of the code, check whether the game has a LIVE INSTANCE of it. This cost credibility twice on 2026-08-16, both times in the same hour.

CASE 1. 'A staff loses its Weapon behaviour on every save' went in at P1 and was
described to Brian as touching real characters. One command disproves it:

    grep -oE '^Item "[^"]+" : [0-9]+' lib/program.i | grep -oE '[0-9]+$' | sort -n | uniq -c

Type 52 (T_STAFF) appears zero times. Nothing in the ruleset is a staff. What
misled me: 'quarterstaff' and 'staff' are type 58, which is T_WEAPON.

CASE 2. 'Tree Stride can never find a square' was filed from the C++ signatures
alone. Reading the spell in lib/program.i shows the player path takes a
targeting prompt and never calls the broken function, and that the monster path
works by accident when the caster stands under a tree. Real, but far narrower
than filed.

THE RULE. A defect proven by reading is a defect in the CODE. Whether it is a
defect in the GAME needs one more question: does anything reach it? Ask
  - does an instance of the type or resource exist?   grep lib/program.i
  - does any script or call site reach the path?      grep lib/program.i, dispatch.h
  - which branch does a PLAYER actually take?         read the whole function
Each is seconds of work and each can move a P1 to a P3.

The finding is still worth filing when nothing reaches it -- say LATENT and say
what would make it live. inc-vsw is the model: the trap is real, and epic D is
exactly the work that would spring it.

## incursion-check-the-world-not-the-tracker
A BEAD NOTE IS NOT THE WORLD. Before saying anything to Brian about a published PR, issue comment, release or test, ask the thing itself.

THIS COST A WHOLE EXCHANGE ON 2026-08-19, twice in one message.

1. Brian was told two upstream replies were drafts waiting for him to read. Both were already live on GitHub: issue #40 at 17:29Z, issue #8 at 17:35Z, four hours earlier. The evidence used was inc-5xn's note reading 'UNSENT, Brian has not read it yet' and the presence of the draft files in docs/outgoing/. Neither proves anything: the note was written before the posting and never updated, and the outgoing file is the SOURCE of what went up, not a queue. One command settles it: gh issue view N --repo rmtew/incursion-roguelike --comments.

2. The same message told him nobody had run the Mac release on a machine that did not build it. He had, on 2026-08-17, and had said so in his own words. gh release view also reports the asset size and download count, and the transcripts under ~/.claude/projects/-Users-brianhill-Scripts-Incursion/*.jsonl hold every message he has sent.

HOW TO APPLY.
- Outward-facing state comes from gh, never from bd, never from a file in docs/outgoing/, never from a memory.
- Before telling Brian something is untested, unanswered or unsent, grep his transcripts for his own account of it.
- When you find a stale note, fix the note in the same breath as reporting the truth. inc-5xn now carries its posting time for this reason.

## incursion-measure-where-the-value-lands
Three rounds on upstream issue #40 each claimed an effect that had only been
measured as an input.

- Round 3 recorded the coordinates handed to `Map::MakeDoor` and called that
  "doors are built in the wrong place". `MakeDoor` returns early when a feature
  already stands there, so an argument is not a door.
- Round 4 read the square before and after the call -- better -- but modelled only
  the `(uint8)` truncation. `Thing::PlaceAt` applies a SECOND repair,
  `if (!m->InBounds(_x,_y)) _x = _y = 1;`, so a coordinate the probe recorded as
  "not built" was in fact built at (1,1). The measured count was wrong by one
  door per occurrence.
- The same round's probe performed 2 out-of-bounds lookups of its own, so the
  instrumented build reported 47,966 reads where uninstrumented code reports
  47,962. The instrument appeared in its own measurement.

**Why:** Brian asked "have you SEEN it?" and "N of 1 is junk". Both times the
honest answer was that a proxy had been measured, not the thing.

**How to apply:** before quoting an effect, name the square, object or file the
value finally reaches, and read THAT. Grep the callee chain for further clamps,
truncations and early returns. Then check whether the probe itself contributes
to the number being reported. Relates to
`bd memories incursion-verification-oracles-that-cannot-fail`.

## incursion-never-mark-a-question-settled
NEVER write 'settled, do not re-open' into evidence or a brief. It entrenches whatever was wrong.

On 2026-08-17 I traced two lines of Status.cpp, concluded that dominated and commanded creatures are carried between levels, and wrote a note into docs/evidence/inc-90u/README.md telling future readers the question was closed. I also told the next review agent it was settled. The answer was on the third line: Status.cpp:677 calls removeCreatureTarget(player, TargetAny) immediately after MakeCompanion adds the target, so the entry is invalidated and Retarget rebuilds without it. Two review passes carried the error forward because I had told them not to look.

RULES:
1. State a conclusion with its code path, never with its status. 'X because A->B->C' can be checked; 'X, settled' cannot.
2. When briefing a reviewer, give the code path and invite contradiction. If you must say a question was decided, say WHAT decided it and demand a contradicting path rather than deference.
3. A claim built on reading N lines is worth exactly N lines. Read to the end of the block, then to the end of the function.
4. The tell: I felt annoyed that a reviewer 'reopened' something. That annoyance is the signal to re-read, not to reassert.

## incursion-test-the-path-the-user-takes
Verify on the path the USER takes, not the one that is convenient locally. Two
Incursion releases shipped broken in two days and both were invisible on the
build machine for the same structural reason.

**Why:** a file you create yourself carries no `com.apple.quarantine` attribute,
so macOS never consults Gatekeeper on it. Testing a locally built folder
therefore cannot detect a Gatekeeper refusal -- not "did not", *cannot*. The first
release was correctly signed and notarised and still refused to launch for
everyone who downloaded it. Separately, the packaging gate inspected the
artifact's contents without ever running it, and so passed a package that could
not load its own module.

**How to apply:** before claiming a release works, download it from where the
user gets it, set the quarantine attribute, and launch it the way they launch it.
For anything else, ask what the user's path differs from the test path in, and
test that difference specifically. The same error shape recurs: verifying an
oracle that agrees with itself. A check that recomputes an expected value from
the same sources it is checking will always pass while the artifact stays broken
-- ask the ARTIFACT, not the source tree.

Related: `bd memories resume-2026-08-17`, and the same class of mistake recorded in
`bd memories resume-2026-08-15-evening` where a session that never entered a map was
counted as a clean pass.

## feedback-no-repro-no-work
NO REPRO, NO WORK. Brian's rule, stated 2026-08-22 morning and restated the same afternoon after it was ignored.

THE RULE. If we do not have a test that shows the bug, we do not work on the bug. The first and only goal for such a bug is a reproduction. Not a patch, not a hunt, not a shortlist of candidate sites, not a sweep to see whether it still happens.

WHY. Because a fix cannot be confirmed without one. If no test fails before the change, then no test passes after it, and 'fixed' is an opinion. This project has already published a fix that fixed nothing, on 2026-08-14, for exactly this reason.

HOW TO APPLY.
1. When triaging or ranking bugs, a bug with no live reproduction is NOT eligible to be recommended as work. Rank it below any bug that has a failing test, however small that bug is. Say plainly that it has no repro.
2. When a bug's own reproduction step passes, STOP THERE and report. Do not widen the search to prove absence. Absence of a repro is the answer, and it is the whole answer.
3. Writing a reproduction IS the work, and it is legitimate work. File it as its own task. inc-upw.43 is the model: 'produce a deterministic reproduction, or prove the fault cannot occur', with DONE MEANS stated as a command that fails or a written argument that the path is unreachable.
4. An old bead that records a repro is not evidence the repro still works. Run it before believing it.

WHAT IT COST ON 2026-08-22. inc-dhc was recommended as the top piece of work. Its documented reproducer, check_layout.sh on seed 3, passed on the first try. The session then ran 176 more sessions and 48 plain runs to establish that it does not reproduce -- a result that the first 12 seconds had already given. The rule had been agreed that morning and was recorded only inside inc-upw.43's description, where no triage would look. It is here now.

See [[incursion-a-diagnosis-needs-its-falsifier]] and [[incursion-headless-false-clean-run]], which are the same principle at other points: a claim needs the thing that would disprove it.

## probe-dump-guard-blindness
Diagnostic guards can hide the defect you are hunting. src/Light.cpp ProbeDump wrote a dump block only when the map, the player position or the source count changed. Casting a spell changes none of the three, so a fog cloud produced NO block at all and fog was invisible to every light check. Fixed 2026-09-02 (inc-qh0w) by folding an FNV-1a signature over the FILTER grid into the guard, via a new FilterMark(). LESSON: before trusting a check that reads a log, confirm the log actually records the state you are testing -- grep the dump for the thing itself, not for the absence of a complaint.
