# Finding work

## work-request-without-a-bead-id-check-recent-work-first
When Brian asks for work and names no bead id (a topic, a description of a bead, or "where we left off"), run `tools/recent_work.py` FIRST, before any keyword search of `bd list`. Match his words against the beads it lists and against their open related beads. When exactly one bead or one open related bead clearly matches, claim it with `tools/worktree.sh <id>` and start. When several match, or none does, show him the candidates from that list and wait. Fall back to a keyword search of all beads only when the recent-work list has no candidate; say that you fell back. Run `bd show <id>` on the match before you claim it, per `check-bead-status-before-suggesting-or-starting`.
Why: a keyword search over every bead finds a bead that shares a word, while his recent sessions record which bead he means.
History: new rule, no prior narrative to archive. Bead inc-bsgy.
