# Where rules live

Rules that bind every session live in `.claude/rules/*.md` and in `AGENTS.md`. They are tracked in git, reviewed, and loaded natively at launch. `bd remember` is for reference material and `resume-*` session notes only, NOT for rules. When you write a new rule, add it to the right file under `.claude/rules/`; make a new file there if none fits.
Why: a SessionStart hook truncates at 10,000 characters with no warning, so a rule delivered only by a hook may silently never arrive (measured: 55 rules at 87,802 characters, ~2% reaching each session).
History: docs/rules-history/where-rules-live.md. Bead inc-wknz.

## rule-entry-format

A loaded rule entry (a `## heading` in `.claude/rules/*.md`, or an `AGENTS.md` section) MUST hold only: the rule as imperative prose with every MUST/MUST NOT/NEVER/ALWAYS requirement, exact command, path, env var, flag, number and procedure needed to obey it; one `Why:` line (one sentence); one `History:` line pointing at `docs/rules-history/`.

Incident narration, dated accounts, and direct quotes of Brian MUST NOT appear in `.claude/rules/*.md`, `AGENTS.md`, or `CLAUDE.md` — they go verbatim into the matching `docs/rules-history/` file, appended under the same heading, never deleted. An overruled rule's loaded entry collapses to one line naming what supersedes it, plus the `History:` pointer.
Why: these files load into every session and cost tokens on every turn; only the obligation belongs here.
History: new rule, no prior narrative to archive. Bead inc-h4w8.
