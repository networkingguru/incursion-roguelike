# Epic branches — history

## merge-master-into-an-epic-through-a-bead

On 2026-09-24, inc-pu6v.38 could not land on the inc-pu6v epic. Its landing gate stopped on `tools/check_item_vision.sh` (an upstream HP assertion, fixed as inc-pu6v.98). The fix for that then stopped on `tools/gate_compare.sh`: 27 of 40 soak sessions died against a baseline of 25.

Both failures came from d407f57, "Merge branch 'master' into inc-pu6v", a hand merge committed on the epic branch. No gate ran on it: `.beads/hooks/pre-commit` allows merge commits, and `tools/check_commit_lane.sh:52` exempts them. The merge changed dungeon generation, which moved seed 3 onto the upstream HP bug and reshuffled which soak seeds die. Measured: 489a461, the epic just before the merge, scored 22 died; d407f57 onward scored 27; seeds 10, 15, 18, 22, 36, 38, 40 newly died and seeds 7, 39 newly survived, with no engine error. Master's own soak passed.

Each failure surfaced only at a later bead's ~50-minute landing gate. Brian asked for the pile-up to stop, and approved gating master merges into an epic and re-recording the soak baseline in the same bead as the merge. Bead inc-1dan.
