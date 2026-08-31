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
0233d4e and checked with `git apply --check` against the probe-free file. The
source copy was removed from `src/Skills.cpp` on 2026-08-31; this patch is now
the only copy, and `tools/check_probe_hooks.sh` no longer lists the hook at all.

Removing it moved every line below `src/Skills.cpp:4129` up by 25, which
re-stales the `src/Skills.cpp` citations in docs/REPORTING-GATE.md and
docs/ENGINE-MAP-CREATURE.md. The removal was done FIRST, ahead of the citation
sweep in the same run, because a citation is cheap to re-derive and a deleted
probe is not. Tracked in bd inc-loa.18.
