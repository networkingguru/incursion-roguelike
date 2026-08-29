# inc-upw.37 — a monster deletes itself mid-spell, and the caster keeps its map

Forensics for inc-upw.37. Gathered 2026-08-20. The defect is **upstream's**.

Everything here was produced at commit `2f58be3`, seed 3390, key script
`tools/keys/dive.keys`, the live `Options.Dat`, with `INCURSION_OOB_PROBE=1`
set in the environment. The builds carry `-g -O0` so the traces name variables.

## What the crash is

A hiding monster casts a spell. `Creature::MakeNoise` checks that the caster is
still standing on the map, and the check passes. It then calls `Reveal(true)`.
Reveal deletes the monster. `MakeNoise` returns to its next line and
dereferences the map pointer that deleting just set to null.

    src/Creature.cpp:342   if (!c || !c->m || c->x == -1)   <- the check, passes
    src/Creature.cpp:346   Reveal(true);                    <- deletes the monster
    src/Creature.cpp:349   c->m->MakeNoiseXY(...)           <- SIGSEGV

`EXC_BAD_ACCESS`, `KERN_INVALID_ADDRESS` at `0x10`, which is the offset of
`Map::sizeX`. The map pointer is null and `x` is `-1`, so `Map::At`'s own
`InBounds` test short-circuits on `x < 0` without touching the object, logs its
assert, and only then faults on `this->sizeX`. That is why the crash and the
last logged assert share a return address.

## Why Reveal deletes it

Losing the HIDING status makes `CalcValues` recompute the creature's size.
Measured on this seed: `oldSize` is 5 (`SZ_LARGE`, `FaceRadius` 0) and the new
`Attr[A_SIZ]` is 6 (`SZ_HUGE`, `FaceRadius` 1). A face radius of 1 needs a 3x3
footprint. There is none free at (69,114), and `Thing::PlaceNear` deletes any
non-player thing it cannot seat — the commented-out "You hear a disturbing
*crunch*" path.

The object goes on `theGame->DestroyQueue` rather than being freed, so this is a
null dereference and not a use-after-free.

## Files

| file | what it proves |
|---|---|
| `crash-backtrace.txt` | the faulting stack, with `Map::At(this=0x0, x=-1, y=-1)` |
| `caller-is-self.txt` | `c == this` at the crash, so the guard at `src/Creature.cpp:342` did cover the object that later went null |
| `watchpoint-map-pointer.txt` | **the key artefact.** A hardware watchpoint on the caster's `m`, catching the write of null and naming every frame from `MakeNoise` down to `Thing::Remove` |
| `size-change.txt` | `oldSize` 5 -> `Attr[A_SIZ]` 6, and `FaceRadius` 0 -> 1 |
| `three-builds.txt` | unmodified / widen / collapse on one seed, one flag apart |
| `unmodified-never-replaces.txt` | a negative result: the unmodified build never reaches the re-placement at all on this seed |
| `crash2.lldb`, `watch.lldb`, `size2.lldb`, `pn2.lldb` | the lldb command files, so each result can be re-run |
| `Options.Dat` | the settings the crash was recorded under, snapshotted so that later play cannot quietly change them. `tools/check_reveal_delete.sh` pins this file rather than the live one |

## The regression check

`tools/check_reveal_delete.sh`. It builds a `-DINCURSION_OOB_PWFIX_WIDEN`
binary, runs seed 3390 under the pinned settings above, and fails if the session
does not exit 0. Verified in both directions on 2026-08-20: **red** on a
pristine worktree at `bdf47e9` (exit 139, two screens), **green** with the guards
in (exit 0, eleven screens). The one flag is the only lever known to reach the
branch; the stock layout does not produce a hiding `SZ_HUGE` monster in a square
too small for it on any seed we have.

## Reproducing it

    git worktree add /tmp/wt 2f58be3
    cd /tmp/wt
    EXTRA_CXXFLAGS="-DINCURSION_OOB_PROBE -DINCURSION_OOB_PWFIX_WIDEN -g -O0" \
      BACKEND=posix OUT=incursion-oob-widen ./build_macos.sh
    INCURSION_OOB_PROBE=1 INCURSION_BIN=./incursion-oob-widen \
      tools/headless.sh tools/keys/dive.keys 3390

Exit 139, with `Registry::Get -- invalid object handle (55538)` three times and
one `InBounds` assert in `errors.log`.

**Two ways to make this look clean, both of which caught me first.** Passing
`INCURSION_OPTIONS=tools/gates/Options.Dat` plays a different game and the
character dies early. Omitting `INCURSION_OOB_PROBE=1` from the environment
leaves the probe compiled in but asleep. Either one produces a run that ends
`cleanly` with `errors: none`, which reads as "the crash is not real".

To get the traces, add a launcher and a command file:

    INCURSION_LAUNCHER="lldb -b -s ../watch.lldb --" \
      tools/headless.sh tools/keys/dive.keys 3390 -headless

`-headless` is required: under lldb the game inherits lldb's 80x24 terminal,
decides it cannot draw, and exits before it plays anything. The lldb launcher
string is word-split by `tools/headless.sh`, so quoted commands inside it do not
survive — that is why these are command files and not `-o` arguments.

## What this says about the rectangle repairs (inc-65j)

inc-65j records that the widening repair to `Rect::PlaceWithin` "-> SEGMENTATION
FAULT" and prefers the collapsing repair on that basis. **That reasoning does not
hold.** `three-builds.txt` has all three on one seed:

| build | result |
|---|---|
| unmodified | exit 0, 47,954 out-of-bounds `At()` reads — matching the figure already recorded in `docs/evidence/inc-5xn/` |
| widen | exit 139, this crash |
| collapse | exit 0, no errors |

The whole chain above sits in code that no repair flag touches. Widening only
changes where rooms are, so on this seed it stands a hiding `SZ_HUGE` monster
where a 3x3 will not fit. The collapsing repair is not immune to the defect; it
lays the level out differently and happens not to trigger it here. Neither
repair — and not the `PlaceWithinSafely` two-square change recommended on
rmtew#40 — does anything about this crash.

`docs/evidence/inc-5xn/README.md` says both repairs "run clean" and that the
earlier crash report was an instrument artefact. On this seed that is wrong, and
`three-builds.txt` is the counter-evidence.

## What is NOT shown here

The crash without a geometry change. `unmodified-never-replaces.txt` shows the
unmodified build never even reaches the re-placement on seed 3390. So "any
layout change can trigger this" is read out of the code, not observed. Finding a
seed where the stock game hits it would need a sweep, and no sweep was run.
