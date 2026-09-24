# Epic branches

## merge-master-into-an-epic-through-a-bead
NEVER commit `git merge master` directly on an epic branch (a bead of type `epic`, such as `inc-pu6v`). Other beads branch from an epic and land into it, so an ungated merge breaks every later landing. Use the gated path:
1. File a bead under the epic: `tools/bead_new.sh "<title>" ... --parent <epic>`.
2. `tools/worktree.sh <bead> <epic>`, then `git merge master` in that worktree.
3. Run the gate there. If `tools/gate_compare.sh` fails ONLY on a changed death count, compare per-seed died/survived status against the epic's pre-merge commit. If the change goes both ways and no session shows an engine error, re-record with `tools/gate_record.sh tools/keys/dive.keys 40 1` IN THE SAME BEAD. Put the per-seed evidence in the baseline header and in the commit body. Any other gate failure gets fixed in that bead.
4. Land it with `INCURSION_BASE_BRANCH=<epic> tools/finish_bead.sh <bead>`.
`tools/check_epic_merge.sh` (called by `.beads/hooks/pre-commit`) refuses the direct merge. `INCURSION_EPIC_SYNC_OK=1` bypasses it, for an emergency only.
Why: a merge commit runs no gate, so its breakage surfaces at the next bead's landing gate, about 50 minutes later, on someone else's work.
History: docs/rules-history/epic-branches.md#merge-master-into-an-epic-through-a-bead.
