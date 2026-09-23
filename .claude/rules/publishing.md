# Publishing outward-facing content

## feedback-never-post-public-unread
The read-before-publish gate has exactly ONE exemption: BUG TEXT ON HIS OWN TRACKER. Everything else needs Brian's literal-text read first.
- Another project's repo (upstream `rmtew/*`, any third party): PR/issue/review text under his name -> HE READS THE LITERAL TEXT FIRST. No exception.
- Bugs on his OWN repo (`networkingguru/incursion-roguelike`): a bead filed/updated/synced needs NO pre-read. Run `tools/sync_issues.sh`, then say what went out. Do NOT ask first, do NOT apologise after.
- Everything else on his own repo (`README.md`, user-facing docs, release notes, store/itch pages, announcements) still needs his read, even though he owns the tree.

Never publish outward-facing text until he has read the literal body and title. A "go" answering a plan is NOT approval of wording not yet seen. Prefer a follow-up comment over silently editing a published body. AI disclosure goes in BEFORE he sees the draft (see the 2026-09-17 ruling below for carve-outs).
Why: publication under his name cannot be undone.
History: docs/rules-history/publishing.md#feedback-never-post-public-unread.

## feedback-ai-disclosure-is-for-authorship-not-copyediting
Put the disclosure on text Claude actually composed (commit messages, issue bodies, PR descriptions, long explanations drafted from scratch). Leave it off text Brian wrote or dictated and Claude only corrected. Every commit still carries `Co-Authored-By` regardless. When unsure, draft WITH the line and let Brian cut it.
Why: a disclosure line on Brian's own dictated text overstates Claude's part.
History: docs/rules-history/publishing.md#feedback-ai-disclosure-is-for-authorship-not-copyediting.

## AI disclosure: the ruling (2026-09-17)
DEFAULT TO DISCLOSING — when in doubt, disclose. BRIAN NAMES THE EXCEPTIONS; do NOT infer them. The one carve-out stated so far: if Brian dictates what to say, no disclosure is needed; if the agent composes it, disclosure goes in. The carve-out list is open — each new one covers only the case he names.
History: docs/rules-history/publishing.md#ai-disclosure-the-ruling-2026-09-17.

## feedback-nightly-never-publishes
NOTHING GOES UPSTREAM WITHOUT BRIAN'S EXPRESS CONSENT. An unattended agent may read, fix, review, update docs and commit. It MUST NOT publish anything outward-facing (PR, issue, comment, release, email) to `rmtew`'s project or anywhere else. Consent is per item and per literal text, never standing. A nightly/cron agent that finds something worth sending upstream writes it to the HELD queue and stops; the next interactive session pastes the literal text and waits for a yes.
Why: publication cannot be undone and carries his name.
History: docs/rules-history/publishing.md#feedback-nightly-never-publishes.

## feedback-default-a-bead-to-public
Default a bead to `public`, NOT `internal`. Everything is public unless strictly Brian's own tooling. Do NOT copy a parent bead's label by default. When `public`: (1) `tools/sync_issues.sh` publishes the DESCRIPTION only, never notes or close reason — put the whole story there; (2) the pre-push hook runs the sync, so the description is outward-facing text and `feedback-never-post-public-unread` applies.
Why: a bead wrongly suppressed as `internal` is invisible; a bead wrongly published gets corrected.
History: docs/rules-history/publishing.md#feedback-default-a-bead-to-public.

## feedback-evidence-stays-untracked-until-a-pr-needs-it
Evidence has two parts, and each part has one place:
- The REPRODUCTION (key script, seed, options file, command) is a tool. It goes in `tools/` and is committed with the bead, ALWAYS — not only when a PR needs it.
- The SPECIMEN (screen dump, log, save, crash report) is output. It goes in `docs/evidence/<bead>/` IN THE SHARED CHECKOUT `~/Scripts/Incursion`, with its README, and stays UNTRACKED there. Add it to a commit only when the fix it supports goes out as a PR or issue comment (the `docs/REPORTING-GATE.md` gate moment).

NEVER write an uncommitted file of either part inside a bead's worktree: `tools/finish_bead.sh` destroys the worktree at landing, and refuses to land one that holds untracked files. An implementer (Codex, opencode) cannot write outside its worktree, so it writes a specimen under the worktree's `logs/` and names the path in its report; Claude copies it to the shared checkout before the landing. A commit body MUST NOT cite a file that is not in history. ~70 pre-existing tracked files under `docs/evidence/` stay; do not remove them or treat them as precedent to commit more.
Why: a reproduction in git keeps a claim re-runnable, and a specimen inside a worktree either blocks its own landing or dies with it.
History: docs/rules-history/publishing.md#feedback-evidence-stays-untracked-until-a-pr-needs-it.
