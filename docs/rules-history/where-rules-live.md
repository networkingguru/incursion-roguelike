# Archived full text -- not auto-loaded. The loaded rule lives in .claude/rules/where-rules-live.md.

# Where rules live

Rules that bind every session live in `.claude/rules/*.md` and in AGENTS.md.
They are tracked in git, reviewed, and loaded natively at launch.

`bd remember` is for reference material and `resume-*` session notes only. It
is NOT for rules any more.

WHY: a SessionStart hook is cut at 10,000 characters with no error and no
warning, so a rule delivered by a hook is a rule that may silently never
arrive. That is what happened here -- 55 rules were being delivered at 87,802
characters and roughly 2% of them reached each session.

When you write a new rule, add it to the right file under `.claude/rules/`.
If none fits, make a new file there.

Brian set this on 2026-09-17. Bead inc-wknz.
