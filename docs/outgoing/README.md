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
  follower count). **Not sent.**
- `pr43-reply.expect` — the claims the gate enforces for that reply.
