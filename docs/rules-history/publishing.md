# Archived full text -- not auto-loaded. The loaded rule lives in .claude/rules/publishing.md.

# Publishing outward-facing content

## feedback-never-post-public-unread
**See the 2026-09-17 ruling below (`## AI disclosure: the ruling (2026-09-17)`)
for the current AI-disclosure default and its carve-outs -- it governs the AI
DISCLOSURE paragraph in this section.**

SCOPE, SET BY BRIAN 2026-09-08 IN TWO STEPS. READ BOTH BEFORE PUBLISHING ANYTHING.

The read-before-publish gate has exactly ONE exemption, and it is BUG TEXT ON
HIS OWN TRACKER. Everything else still needs his eyes on the literal text.

  ANOTHER PROJECT'S repo (upstream rmtew/*, any third party): PR bodies and
  titles, issue text, review comments, anything under his name on a tree he
  does not own -> HE READS THE LITERAL TEXT FIRST. No exception.

  BUGS on HIS OWN repo (networkingguru/incursion-roguelike): a bead filed,
  updated or synced there needs NO pre-read. tools/sync_issues.sh MAY publish
  without showing him bodies. Run it, then say what went out. Do not ask first
  and do not apologise afterwards.

  EVERYTHING ELSE ON HIS OWN REPO STILL NEEDS HIS READ: README.md, user-facing
  docs, release notes, store and itch pages, announcements -- anything a player
  or a visitor reads. Owning the tree does NOT exempt it. A separate
  authorisation for one of those covers that one item only.

HIS WORDS, both from 2026-09-08. First, the exemption: 'STOP PESTERING ME ABOUT
NOT READING EVERY GODDAMN BEAD. If I post something to someone else's repo,
need to read it. A bug in my own, I do not.' He said it after a session ran
sync_issues.sh, published nine issues to HIS OWN tracker, and then apologised
for it in a paragraph he did not want. Then, minutes later, the narrowing:
'This is true for beads/bug, not the whole repo. Not the read me, not
user-facing docs (unless separately authorized). Just bugs.'

THE ORIGINAL RULE, still in force everywhere the exemption does not reach:
Never publish outward-facing text until he has read the literal body and title
- not a diff, not a summary. On 2026-08-15 two PRs went to
rmtew/incursion-roguelike (#42, #43) with text he had never read and no AI
disclosure, while his own branch commits carried the Co-Authored-By trailer.
Exactly backwards. His words then: 'you do NOT push public without me fucking
reading it. And you ALWAYS disclose AI on this shit.'

AI DISCLOSURE is unchanged and is scoped to nothing: every public contribution
discloses AI assistance, and the disclosure goes in BEFORE he sees the draft,
so what he approves is the disclosed version.

HOW TO APPLY. Two questions, in order. Is it bug text going to his own tracker?
Yes -> publish. No -> paste the exact body and title and wait for a yes on THAT
text; a 'go' answering a plan is not approval of wording he has not seen.
Prefer a follow-up comment over silently editing a published body either way.

The same two-step rule is written into rule 1 of 'Publishing anything
outward-facing' in AGENTS.md and CLAUDE.md in the repo.

See [[incursion-reporting-gate]] for the separate rule that a public claim needs
an oracle that changed state, with numbers on both sides.

## feedback-ai-disclosure-is-for-authorship-not-copyediting
**See the 2026-09-17 ruling below (`## AI disclosure: the ruling (2026-09-17)`)
for the current AI-disclosure default and its carve-outs -- disclosure now
defaults to yes, with only Brian-named carve-outs, one of which is this
section's dictation case.**

Brian draws the AI-disclosure line at AUTHORSHIP, not involvement. On 2026-08-20 he cut a disclosure line from a GitHub comment he had dictated himself, saying: 'Reserve it for things where you write most of it, not when you copyedit me.'

**Why:** the disclosure exists so readers know who wrote the words in front of them. When Brian dictates the substance and Claude only fills in commit SHAs, links and names, Brian is the author. A disclosure line there overstates Claude's part and dilutes the signal on the items that genuinely need it.

**How to apply:** put the disclosure on text Claude actually composed -- commit messages, issue bodies, PR descriptions, long technical explanations drafted from scratch. Leave it off text Brian wrote or dictated where Claude only corrected or completed details. Note this does NOT weaken CLAUDE.md's rule for public CONTRIBUTIONS: every commit still carries its Co-Authored-By trailer, so the code disclosure lives where it belongs and a note merely pointing AT that code does not need to repeat it. When unsure which side a piece falls on, draft it WITH the line and let Brian cut it -- that was the order of events here and it worked. See [[feedback-brian-reads-literal-text-before-publishing]].

## AI disclosure: the ruling (2026-09-17)
BRIAN RULED 2026-09-17 on the conflict between `feedback-never-post-public-unread`
(discloses always, scoped to nothing) and
`feedback-ai-disclosure-is-for-authorship-not-copyediting` (disclosure is for
authorship, not involvement). The ruling is a DEFAULT PLUS A CARVE-OUT, not a
win for either side.

DEFAULT TO DISCLOSING. When in doubt, disclose. The default is not "decide
whether this counts as authorship" -- it is "disclose".

BRIAN NAMES THE EXCEPTIONS. YOU DO NOT INFER THEM. He will say which cases do
not need disclosure. An agent must not reason its way into an exemption on its
own.

THE ONE CARVE-OUT HE HAS STATED SO FAR: if Brian dictates what to say, no AI
disclosure is needed. If the agent writes it, the disclosure goes in. The line
is who composed the words, not who pressed send.

The list of carve-outs is OPEN: he may add more, and each one covers only the
case he names.

Bead inc-wknz.

## feedback-nightly-never-publishes
NOTHING GOES UPSTREAM WITHOUT BRIAN'S EXPRESS CONSENT. Stated 2026-08-23 as the hard caveat on the autonomous nightly workflow he wants.

THE RULE. An unattended agent MAY read, fix, review, update docs and commit to this repository. It MUST NOT publish anything outward-facing: no PR, no issue, no issue comment, no review comment, no release, no email, to rmtew's project or anywhere else. Consent is per item and per literal text, never standing.

WHY. He is deliberately removing himself from the loop on internal work so the nightly cycle can run without him. Publication is the one thing that cannot be undone and that carries his name. Automating internal work does NOT automate the gate. Two PRs went out on 2026-08-15 with text he had never read and no AI disclosure; that is the failure this prevents.

HOW TO APPLY. A nightly or cron agent that finds something worth sending upstream writes it to the HELD queue and stops. The next interactive session puts the literal text to him and waits for a yes on that text. See CLAUDE.md 'Publishing anything outward-facing', docs/REPORTING-GATE.md, [[feedback-never-post-public-unread]] and [[incursion-check-the-world-not-the-tracker]].

## feedback-default-a-bead-to-public
DEFAULT A BEAD TO public, NOT internal. Brian's rule, 2026-09-06: 'everything is public unless it is strictly tooling for ME or clearly internal.' A performance concern inside a public change is PUBLIC -- the point is that people can see the work was done, including the work that found nothing wrong.

I got this wrong on inc-wocu (the RedundantFieldGrant cost measurement) by copying the internal label from its parent inc-fiiq. Matching a parent's label is not a reason; ask instead whether the subject is game code or Brian's own tooling.

TWO CONSEQUENCES WHEN YOU CHOOSE public:
1. tools/sync_issues.sh publishes the DESCRIPTION and never the notes or the close reason. So a closed bead whose description says 'see the close reason' publishes a question with no answer. Put the whole story, numbers included, in the description.
2. The pre-push hook runs the sync. So the description is outward-facing text, and feedback-never-post-public-unread applies: paste the literal body, wait for a yes, and put the AI disclosure in before he reads it.

## feedback-evidence-stays-untracked-until-a-pr-needs-it
Do NOT commit files under docs/evidence/ as a matter of course. Brian stated the rule on 2026-08-21: 'We do not need to commit evidence until it is needed for external PRs.'

**Why:** evidence exists so a claim can be checked. Until the claim leaves this machine, the working tree is enough, and committing large binary specimens (save files, crash reports, sweep logs) puts weight in the history that nobody outside will ever read. When a claim DOES go to the parent project, the evidence must be reachable, so that is when it gets committed.

**How to apply:** create the evidence directory and its README as normal -- the durable copy still matters, and a citation must not outlive the file it names. Then LEAVE IT UNTRACKED and say so. Only add it to a commit when the fix it supports is going out as a pull request or issue comment, which is the moment the gate in docs/REPORTING-GATE.md applies. Note 70 files under docs/evidence/ ARE already tracked from earlier work; do not go and remove them, and do not read them as a precedent to commit more. See [[feedback-close-beads-without-asking]] and [[incursion-check-the-world-not-the-tracker]].
