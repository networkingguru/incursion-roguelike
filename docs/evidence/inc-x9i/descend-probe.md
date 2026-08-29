# `descend-probe.patch` — the DESCEND probe, preserved

`INCURSION_DESCEND_PROBE` served inc-x9i. The bead is closed, so the probe is
scaffolding, but deleting it from `src/` would destroy the only reproduction
the finding has: a release build gives the SAME stack for the levitation branch
and the successful-climb branch of `Creature::Descend`, so a crash report
cannot tell them apart. This patch is that reproduction, saved so the source
copy can go without losing it.

Apply it to a tree that no longer carries the probe:

    git apply docs/evidence/inc-x9i/descend-probe.patch

Then build and run with the hook set. It appends one line per descent to
`logs/descendprobe.log` inside the run directory:

    BACKEND=posix ./build_macos.sh
    INCURSION_DESCEND_PROBE=1 tools/headless.sh tools/keys/dive.keys

Each line names the branch and how it reaches `MoveDepth`:

    Descend branch=levitation depth=3 enters_MoveDepth=directly, safe=true
    Descend branch=climb-failed depth=3 enters_MoveDepth=via TerrainEffects, safe=false
    Descend branch=climb-succeeded depth=3 enters_MoveDepth=directly, safe=true

Recorded 2026-08-29. The patch was cut from `src/Skills.cpp` at commit
0233d4e and checked with `git apply --check` against the probe-free file; the
source copy was then restored, so the probe is still in the tree today. See
`tools/check_probe_hooks.sh`, which reports it as RETIRED now that this file
exists — meaning the source copy CAN go, not that it must go tonight.

Removing it is not free of consequences and should not be done in a session
that is also correcting citations. It deletes 25 lines at `src/Skills.cpp:4123`
and moves every line below, including the four `src/Skills.cpp` citations in
docs/REPORTING-GATE.md rows 243, 279, 293 and 297 and the one in
docs/ENGINE-MAP-CREATURE.md, which were re-derived on 2026-08-29 and would go
stale again in the same run. Tracked in bd inc-loa.18.
