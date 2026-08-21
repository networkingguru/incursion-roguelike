# Outgoing

Text that is meant to leave this machine — replies on upstream pull requests,
issue reports, anything that appears under Brian's name in another project.

Two rules govern everything in here, and they come from `../../CLAUDE.md`:

1. **Brian reads the literal text before it is posted.** Not a diff, not a
   summary. A file living here is a draft, not an approval.
2. **The AI-assistance disclosure is written in before he reads it**, so what he
   approves is the disclosed version.

## Before posting

Run the citation gate over the document and its expectations file:

```
tools/check_citations.sh docs/outgoing/pr43-reply.md --expect docs/outgoing/pr43-reply.expect
```

It resolves every `File.ext:NNNN` against `upstream/master` — **their** line
numbers, not ours, which have drifted — and every GitHub `#L` anchor against the
ref named in the URL itself. It fails if an evidence link points at a path that
is not yet on `origin/master`, because a link that exists only in the working
tree is a 404 for the reader.

**Pin outgoing links to a commit, not to a branch.** The whole value of a
citation is its line number, and `master` moves under it. Put the SHA in the
URLs and name it once in the opening sentence, as `pr43-reply.md` does.

**Repin last, after the evidence is final.** Pinning has a trap: pin the links,
then edit an evidence file, and the pin now serves the superseded text — which
is worse than a branch link, because it looks deliberate. The order is: finish
the evidence, commit it, then rewrite every fork URL to that commit and commit
again. It cost two rounds here to learn that, both recorded in the log.

**All fork links point at ONE commit, and the prose names that commit.** The
reply's opening sentence says which commit the evidence links resolve to. Add a
new evidence file and the links to it need a LATER commit than the ones already
pinned -- so the document would quietly carry two, while the sentence still names
one, and an older link would serve superseded text. The fix is to move every
fork link and the sentence together, at the same moment.

The mechanism is a placeholder. While evidence is still being written, every
fork URL and the commit named in the opening sentence read `PINME`, which no
clone can resolve, so the gate fails and the document cannot go out. When the
evidence is final and committed, replace every `PINME` in one pass with the new
SHA and run the gate again. Do not pin some links early: a half-pinned document
passes the gate and is wrong.

The gate cannot tell whether the sentence around a citation is true. That still
needs a reader. What it does is close the one class of error that recurred three
times in a single day: citing our tree's line numbers as theirs.

## Formatting

Write each paragraph as one long line. GitHub renders a newline inside a comment
as a line break, so a document hard-wrapped at 78 columns posts with a ragged
right edge. The raw file is unpleasant in a terminal and correct in the browser,
which is the only place it is read.

## Files

- `pr43-reply.md` — the reply to rmtew's three questions on PR #43 (how deep the
  recursion goes, its stack cost, and why the array is not sized from the
  follower count). **Sent 2026-08-18**, comment 5329016046.
- `pr43-reply.expect` — the claims the gate enforces for that reply.
- `issue40-reply.md` — the reply to rmtew's question on issue #40, which asks
  what the player observes before and after. It is largely a correction: the
  reads come from level generation, not monster AI, and #41 covers 8 of 47,962.
  The player-facing effect it reports is doors built on squares the code never
  chose — two sealed in rock and one moved to (1,1) by `Thing::PlaceAt` — in 2
  of 500 scripted sessions. **Sent 2026-08-19**, comment 5345710784. Evidence in
  `docs/evidence/inc-5xn/`.
- `issue40-reply.expect` — the claims the gate enforces for that reply.
- `issue40-addendum.md` — a follow-up on issue #40 recording what the fork
  settled on: the repair went into `Rect::PlaceWithin` rather than the
  `PlaceWithinSafely` change the earlier reply proposed, plus the
  `Creature::MakeNoise` crash found while testing it. Cites no line numbers, by
  choice, because the two trees have drifted. **Sent 2026-08-20**, comment
  5358799776. Nothing is asked of rmtew.
- `issue8-reply.md` — the reply to rmtew's issue #8, which asks for automated
  play. It reports the headless harness built for this port, what it measures,
  the one idea in that thread that was tried and abandoned, and what was got
  wrong on the way. **Sent 2026-08-19**, comment 5345774328.

**A limit worth knowing before you trust a green gate.** The `PINME` mechanism
described above only bites on refs inside `https://github.com/` URLs. A document
whose only fork reference is a bare prose placeholder passes the gate completely
unpinned, and `issue40-reply.md` is such a document. The `.expect` file is the
only part that reads content rather than addresses — write one for every
outgoing document, because the gate proving a line exists is not the gate
proving your sentence about it is true.
