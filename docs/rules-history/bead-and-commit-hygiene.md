# Archived full text -- not auto-loaded. The loaded rule lives in .claude/rules/bead-and-commit-hygiene.md.

# Bead and commit hygiene

## commit-approves-the-text-it-carries
RULE (Brian, 2026-09-14, angry): when he says commit, that IS approval of any literal text the commit carries -- a README row, a doc line, anything pasted to him for a yes. His words are in the session: 'If i say commit, I approve the fucking text.' Do NOT hold a commit, or report the gate will stop, because a pasted line still lacks a separate yes. Put the text in and commit. WHAT HAPPENED: inc-7wmu. A README row was pasted for his read; he asked about other things, then said 'Commit it'. The session committed without the row (reading the save-means-stop rule as 'no unmade change'), finish_bead.sh then hit a merge conflict, and the report said the gate would stop again on the missing README row pending his yes. The save-means-stop rule still bars NEW edits the session invents at commit time; it does not bar text he was already shown and asked to approve.

## commit-gate-stage-before-commit
Never combine staging and committing in one Bash call. commit-gate.py is a PreToolUse hook that runs before the command; it reads the staged index (diff --cached) while still empty, cannot see the change is docs-only, and fails closed to BLOCK. Fix: stage in one call, then commit in a SEPARATE call; the hook then sees the docs-only staged set and exempts it, no marker. Confirmed 2026-08-29 (doc commit 687d3f8 passed in auto mode). Gotcha: the hook substring-matches the two-word phrase in the command text, so even a non-git command whose argument contains that phrase gets blocked -- keep the phrase out of bd-remember content. Do NOT weaken the hook to parse chained staging: it would have to strip heredocs and reject commit pathspecs, else a docs-stage plus a code-pathspec-commit slips past review. Separate code-only issue: in auto mode the classifier denies create-approval-marker.py, so Brian must run the marker via bang-prefix or leave auto mode for non-docs commits.

## commit-means-land-the-bead
In Incursion, 'commit' / 'save' / 'push' from Brian is ONE instruction meaning LAND IT, not a request to commit and then ask. Run the whole thing without stopping between steps:

  1. git commit on the bead's branch (through the usual gate)
  2. tools/finish_bead.sh <bead-id>    -- gate, merge --no-ff, delete branch, drop worktree
  3. bd close <bead-id>                -- ONLY AFTER the merge lands

ORDER MATTERS AND IT BIT A SESSION ON 2026-09-17. Closing the bead BEFORE
finish_bead makes tools/check_orphan_branches.sh go red ('bead closed, work NOT
on master'), which fails finish_bead's own gate, which blocks the merge. Deadlock.
Recover with: bd update <id> --status open, re-run finish_bead, then close.

WHY THIS KEEPS GOING WRONG. Two rules in the same context say the opposite, and
both are wrong here: the generated Beads block in AGENTS.md ('Conservative/
default: report status and proposed commands; wait for approval') is upstream
boilerplate this repo overrides; and the global CLAUDE.md 'save/commit means
stop' forbids new EDITS before committing, NOT the landing. AGENTS.md:46 has
said 'when Brian says commit ... then run tools/finish_bead.sh' since before
this incident.

Brian, 2026-09-17, after a session committed, closed nothing and asked whether
to land: 'Why in the fuck do you never finish beads? ... Instead, now you ask me
between each fucking step.'

THE ONE THING THAT STILL STOPS YOU: a worktree holding another bead's
uncommitted work. Commit your own paths there, say so, and do not land that bead.

## beads-blocking-a-commit-fix-the-bead
STANDING RULE, Brian 2026-09-12, given in anger after a session stopped and offered him three options: when a bead blocks your commit, LOOK THE BEAD UP AND FIX IT. Do not stop, do not present options, do not ask. The pre-commit hook refuses a commit while any new 'public' bead lacks '## Steps to Reproduce' or '## Acceptance Criteria' (tools/check_bead_publish.py, via bd lint). Read the bead's own description -- these beads are written with file:line citations, expected-vs-actual and a suggested fix, which is everything both sections need -- and write the sections from that evidence. This holds even when ANOTHER session filed the bead. Block ONLY if you literally cannot work out what belongs in the sections. Never use git commit --no-verify to get past it. Worked example: inc-3mz5, inc-feec, inc-j5hn and inc-l59x were all fixed this way in one pass, and check_bead_publish.py went from FAIL on four to PASS.

## bead-label-gate-guards-bd-create
TWO HARNESS GATES LIVE OUTSIDE THIS REPO, in ~/.claude/hooks/, which is NOT under git. Nothing in the tree points at them, so look here first when a Bash command is denied for a reason the repo cannot explain.

bead-label-gate.py (PreToolUse, Bash) has TWO gates. The CREATE gate denies bd create, bd new and tools/bead_new.sh when the command names neither 'public' nor 'internal', or names both; nothing is filed, so no half-made bead is left behind. It is scoped to the 'inc' id prefix and does nothing in other repositories. The COMMIT gate denies a commit while a bead created since HEAD is still unclassified; it is the backstop for beads the create gate never sees. Added 2026-09-07, inc-exye.

commit-gate.py (PreToolUse, Bash) denies a commit until Brian approves and a marker exists. Docs-only commits are exempt.

BOTH READ THE COMMAND WITH shell_commands.py, a shared parser, NOT a substring search. This matters: until 2026-09-07 commit-gate.py matched 'git commit' anywhere in the raw string, so writing a FILE THAT DISCUSSES COMMITTING through a heredoc was denied as a commit (inc-21yu). If you add a gate here, use shell_commands.invocations() -- the repo documents its own gates, so its documents quote the phrases the gates watch for.

ALWAYS FILE THROUGH tools/bead_new.sh, NEVER BARE bd create. The label gate catches both, but the LABEL IS NOT THE ONLY REQUIREMENT. tools/check_bead_publish.py also demands that every new bead labelled 'public' pass bd lint, which means the description must literally contain the headings '## Steps to Reproduce' (bugs only) and '## Acceptance Criteria' (bugs and features). bd create does not check that; bead_new.sh runs the checker on the new bead immediately and tells you at once. Otherwise the fault surfaces only at the next commit -- and it blocks WHOEVER commits next, which may not be you. On 2026-09-10 I filed three beads with bare bd create in an oracle session, all three missed the headings, and Brian hit the wall himself: 'Fix the beads you created. They are blocking a commit.' Fixing them afterwards means bd update <id> --body-file <file>, which is fine but is a round trip he should never have paid for.

The wording of that requirement is fixed text, not a judgement: write the two headings verbatim with '## '. A bead full of file:line evidence still fails without them, because the check measures the heading and not the content.

tools/bead_new.sh in the repo STAYS and is not replaced by any of this: it runs for people not using this harness and it checks more than the label.

## bead-github-sync-wiring
HOW BEADS REACH THE GITHUB ISSUES TAB (wired 2026-09-03, uncommitted at that date).

TRIGGER: git core.hooksPath is .beads/hooks, so those five beads shims are the ONLY hooks git runs -- anything in .git/hooks never fires. A block appended below the managed BEADS INTEGRATION marker in .beads/hooks/pre-push runs tools/sync_issues.sh on every push. It must never block a push: warn and continue. INCURSION_NO_BEAD_SYNC=1 skips it. Beware: 'bd hooks install' regenerates those shims and will silently drop the block.

WHY THE WRAPPER AND NOT bare 'bd github sync': bare sync has no label filter and would publish the internal beads (harness, docs checks, agent process) to a public tracker. sync_issues.sh computes the public-labelled set and passes --issues.

CONFIG KEYS: the ones bd reads are github.owner and github.repo. github.org is NOT read (an earlier session set it by mistake; it was unset). Token: NEVER 'bd config set github.token' -- that writes into .beads/config.yaml, which is TRACKED in a PUBLIC repo. Use the GITHUB_TOKEN env var; sync_issues.sh falls back to 'gh auth token' on its own.

PERFORMANCE, and the trap that caused it: a full run took FOUR MINUTES because 'bd show --json <368 ids>' costs 116 SECONDS -- it pays a round trip per id -- and the script called it twice. 'bd list --json' returns external_ref and status for the whole database in 0.6s. The script now reads the database once into a temp file and all three steps parse it, re-reading once after the push because the sync writes new external_ref values. Full run is now about 10 seconds, nearly all of it 'gh issue list'. NEVER call bd show with a large id list.

## epic-children-inherit-internal-label
A child bead created with --parent inherits the parent's labels. Under an epic labelled internal, 'bd create -l public' yields BOTH labels and tools/sync_issues.sh refuses the bead. After creating a public child of an internal epic, run 'bd update <id> --remove-label internal'. Hit on 2026-09-13 with inc-pu6v.29 and .30.

## feedback-no-beads-sync
Do NOT sync, push, or offer to push the beads database. Do not report the age of refs/dolt/data. Do not run bd doctor to investigate why auto-push stopped.

Brian said this on 2026-08-19, sharply, after I reported that the remote Dolt ref was three days stale and asked twice what to do about it.

**Why:** he works on a single machine. The local Dolt DB is the only copy that matters and a remote copy buys him nothing. A stale refs/dolt/data is the expected steady state here, not a defect.

**How to apply:** treat 'is the bead saved?' as answered by the bead existing in the local database. `bd show <id>` is the whole check. Answer about git separately -- code commits and pushes are still wanted, and 'save/commit means stop' still applies to them. Never bundle a beads-sync offer into a status report.

## feedback-handoff-notes-are-not-commits
Do NOT commit session logs, handoff notes, or "what I did last night" writeups
to the repository. Brian objected sharply when a dated session log landed in
`docs/` as its own commit, with a message that read as a diary of my own
mistakes.

A commit message describes a change to the code. A session log is a note from
me to myself for when the conversation is cleared. Those are different things
and only the first belongs in the history of a fork of somebody else's project.

**Why:** the repo history is a permanent, shared record. A dated log accretes
clutter, and a confessional commit message is noise to every future reader.

**How to apply:** write resume notes with `bd remember`, keyed
`resume-<date>`. This project keeps ALL persistent knowledge in beads; the
~/.claude memory directory is not used for it. Keep issue detail on the beads
themselves, where it already lives. Commit only code, tests, tooling and
documentation that a user of the project would want. If asked to "write notes
and commit", the commit means the pending *work*, not the notes -- ask if
unsure. See `bd memories resume-2026-08-14-overnight`.
