# inc-otz -- an up staircase buried inside a dungeon wall

## What Brian saw

On 2026-08-21, in normal play, Brian stood one square south of a staircase
that appeared to sit inside a wall. He could not move onto it.

## What the measurement shows

`portals-depth3.txt` is the portal report for his depth-3 map, taken from his
save. The relevant entry:

    Portal 2: "up stairs" at (74,70)
      terrain      : "Dungeon Wall"
      At().Solid   : TRUE
      SolidAt()    : TRUE
      portal Flags : 0x0
      neighbourhood ('#' solid, '.' open, '@' player):
        ###
        #P#
        .@.
      reachable    : NO -- no open path from the player

The staircase is a real Portal object on a solid Dungeon Wall square, with all
eight neighbours solid. The player stands directly south of it. This is not a
display fault and not a merely walled-off floor square.

## How to reproduce the report

The instrument is a temporary `=== Map Portals ===` section in `src/Dump.cpp`,
marked `Delete with inc-otz`. It prints, for every portal on the player's map,
the terrain, `At().Solid`, `Map::SolidAt()`, `isVault`, the portal flags, the
3x3 neighbourhood, and a breadth-first reachability walk from the player.

    BACKEND=posix OUT=incursion-mapprobe ./build_macos.sh
    INCURSION_BIN=./incursion-mapprobe tools/dump_save.sh <save-file>

The separate `OUT` name matters: it leaves `./incursion`,
`./incursion-headless` and `mod/Incursion.Mod` alone, so the report can be
taken while a real game is running.

## The save

The save this report came from is NOT in this repository. Saves are 1.2 MB of
binary and `save/` is in `.gitignore`. The copy lives at:

    /Users/brianhill/Scripts/incursion-repro-stair-in-wall/Furious_Fox.sav
    /Users/brianhill/Scripts/incursion-repro-stair-in-wall/Furious_Fox.sav.backup

sha1 of the .sav: a7d5b6eb6e24534d313fe106dfa4239e3c570f59

It was copied, not moved, while Brian was playing. The live save was not
modified.

## Root cause candidate

`src/MakeLev.cpp:1740-1775`. An up staircase is not placed freely. Each one is
forced onto the coordinates of a down staircase on the level above. When that
square is solid, the generator carves a one-square pocket and seals it:

    if (SolidAt(t->x, t->y)) {
        WriteAt(r, t->x, t->y, FIND("floor"), ..., PRIO_FEATURE_FLOOR);
        ASSERT(At(t->x, t->y).Solid == 0);
        for (j = 0; j < 8; j++)
            WriteAt(r, t->x + DirX[j], t->y + DirY[j],
                FIND("dungeon wall"), ..., PRIO_CORRIDOR_WALL);
    }

`WriteAt` takes a priority and refuses a write that existing content outranks,
so the floor write can fail and leave the square solid.

## The assertion that did not fire

`src/MakeLev.cpp:2051` asserts that no portal sits on a solid square. That
assertion is never compiled out -- `inc/Defines.h:93` expands it to `Error()`,
which writes to `logs/errors.log` and continues. It detects and never repairs.

No error log in `logs/` contains it. Assertions do reach the log in general:
`logs/soak/oob-widen-wide/messages` carries seven distinct `ASSERT failed`
lines from real runs. So either this map was generated in a session whose log
has rotated away, or the square was buried after the validation ran.

## Second finding, not yet a defect

Of 4105 open squares on this level, 2932 are reachable from the player. Four
of the eight portals are unreachable, including three of the four down stairs.

The walk treats a closed door as passable and a SECRET door as solid, because
`Map::SolidAt` does. A region entered only through a secret door therefore
counts as unreachable here although a searching player could enter it. The
1173 unreachable open squares MAY all be legitimate hidden areas. Counting the
secret doors on each region's boundary would settle it.

Portal 2 does not depend on that caveat.

## Upstream

The generation code and the orphaned buried-stairs comment at
`src/MakeLev.cpp:3023` are both upstream's, from Richard Tew (f062112,
2014-10-27). A fix here is a base-code fix and needs an `upstream:` mark and a
row in `docs/REPORTING-GATE.md`.
