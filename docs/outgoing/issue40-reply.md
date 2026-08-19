This work was done with AI assistance (Claude) — the probes, the seeded runs and the analysis, not only the prose. The fork reference at the end is pinned to commit `2f58be3`; all line numbers are against your master at 7469d3ed.

**First, the withdrawal.** I inferred the cause of those reads from a single call stack and was wrong. The "343 reads in 13 seconds" I opened this issue with, and the "877 turns with an empty error log" in my commit message, were never measured as monster-AI reads; the error log keeps one stack per distinct message, and I treated that one stack as speaking for all of them. The counts were real. Blaming the monster was not.

**What I can answer.** Every out-of-bounds read in a 500-session sweep comes from level generation, with one exception I record below. I could not measure any difference in monster behaviour either side of the guard. What I did find is a defect in the level the player is handed: on the dungeons that trigger it, the builder puts doors on squares it never chose. Whether a player ever notices one, I have not measured — see the end of the next section.

Numbers are over 500 scripted sessions (seeds 3300–3799) unless I say otherwise.

## What the level builder does

The room-within-a-room case can end up with a rectangle whose bottom edge is above its top edge — how, further down. The door loop then works from it (src/MakeLev.cpp:2786):

```cpp
...
                y = r.y1 + random(r.y2 - r.y1);
...
            MakeDoor((uint8)x, (uint8)y, TREG(regID)->Door);
            if (FDoorAt(x, y))
                WriteAt(r, x, y, TREG(regID)->Floor, regID, PRIO_FEATURE_FLOOR);
```

`x` and `y` are `int16` locals, and the two calls below them see different values. `MakeDoor` takes `uint8` (inc/Map.h:348), so a `y` of -7151 arrives as 17 — a real square, and nothing about it looks wrong. Its only guard is `if (FFeatureAt(x, y)) return;` (src/MakeLev.cpp:1283-1284), so an empty square gets a door. `FDoorAt` takes `int16` (inc/Map.h:284) and sees the raw -7151, which `Map::At` answers with the (0,0) square (inc/Map.h:217), so the test fails and no floor is carved. The out-of-bounds read does trip the assertion in `Map::At` (inc/Map.h:215) — that is where these reads come from — but nothing names the door, and nothing refuses to build it.

Measured on seed 3390, reading the landing square before the call and after it, since the arguments alone prove nothing given that early return (the log interleaves other lines between these three):

```
DOOR_PLACED raw=(116,-7151) lands_at=(116,17) feature_before=0 door_after=1 room=(116,5)-(123,4) lands_inside_room=0
...
DOOR_PLACED raw=(123,-25691) lands_at=(1,1) (PlaceAt clamped to 1,1) feature_before=0 door_after=1 room=(116,5)-(123,4) lands_inside_room=0
...
DOOR_PLACED raw=(123,14601) lands_at=(123,9) feature_before=0 door_after=1 room=(116,5)-(123,4) lands_inside_room=0
```

All three squares were empty before the call and hold a door after it, and none is on the room the door belonged to. All three panels of the finished level, printed by the same probe — `+` the door, `#` solid, `.` open, blank means off the map:

```
DOOR_MAP door at (116,17) came from raw (116,-7151); 13x9 of the finished level:
###......####
###.####...##
###.#########
###.#########
###.##+######
###.#########
###.#########
###.#########
###.#########
DOOR_MAP door at (1,1) came from raw (123,-25691); 13x9 of the finished level:



     ########
     #+######
     ########
     ########
     ########
     ########
DOOR_MAP door at (123,9) came from raw (123,14601); 13x9 of the finished level:
........###
........###
###########
###########
######+####
###########
###########
###########
..#########
```

Two doors sealed in rock, each three squares from the nearest open floor, and one in the map's top-left corner. The two sealed doors arrive from opposite directions — a raw `y` of -7151 and one of +14601 — so what puts them there is the `uint8` truncation and not a sign error. The corner door is there because `Thing::PlaceAt` bounds-checks where `MakeDoor` does not, and its repair is `if (!m->InBounds(_x,_y)) _x = _y = 1;` (src/Display.cpp:151-152) — a coordinate that survives the `uint8` truncation still off the map is not dropped, it is moved to (1,1) and built. It is also the source of the one stray `InBounds(_x,_y)` assertion seed 3390 logs beside the tens of thousands from the decorator.

**What a player sees, I did not measure.** These doors stand in rock, so ordinary movement will not reach them; digging or map-revealing magic would. I can show you a level built wrong. I cannot show you a player noticing.

## How often

**2 of 500 sessions** — seeds 3390 and 3515 — producing 4 doors on squares the code never chose, out of 4,958 door placements. Three of the four are still standing when generation finishes; something later in generation overwrote the fourth. Two events is too few to state a rate, and the harness makes it worse: it drives the wizard menu to descend continuously, so it exercises level building far harder than play does, and I have no per-level denominator.

It is high-volume when it does fire. Seed 3390 logged 47,954 out-of-bounds map reads and abandoned 494 decoration attempts, against a median of 2 abandoned attempts per session across the sweep and a next-worst session of 43.

## What the monster does

I measured no difference either side of the guard, on the one seed I could measure it. I originally blamed the eight-square scan around a hiding monster (src/Monster.cpp:547). For that scan to leave the grid the monster must stand on the outermost ring, and `Creature::Walk` rejects those coordinates (src/Move.cpp:271) — a coordinate test, not a terrain one, and move, push and jump all route through it. A probe on that scan never fired in any of the 494 sessions that reached their summary; the other 6 crashed first, for an unrelated reason I come back to.

The exception I owe you: in one of my modified builds the out-of-bounds assertion fired under `Monster::ChooseAction` casting a spell, through `Map::MakeNoiseXY` and `Map::FieldAt` into `Map::At`. Once, and I have not investigated it. So the scan I blamed is not the source of these reads, and I cannot rule out some other AI path.

## Where the bad rectangle comes from

`RM_DOUBLE` builds a room with a smaller room standing inside it. You walk into the room, walk around the subroom, find its door, and go in. Four rectangles are involved, and I use one name for each throughout:

- **panel** — the patch of blank map the generator is filling. On this seed 96-127 across, 0-31 down.
- **room** — painted inside the panel.
- **space** — the part of the room where the subroom is allowed to stand, so a player can walk around it.
- **subroom** — placed inside that space.

**The builder wants a room 12 across and 7 down, and asks `Rect::PlaceWithinSafely` for a spot in the panel** (src/MakeLev.cpp:2752, inc/Base.h:285).

**The placer finds one, but it sits against the top edge of the panel.** Its rule is that nothing comes within 2 squares of that edge, so it pushes the room's top edge down by 2 and leaves the bottom edge alone (inc/Base.h:293-296). The room is now 5 down instead of 7. The four clamps are unconditional — not a does-it-fit test — and each moves only the edge that broke the rule, so a rectangle placed hard against the panel border is trimmed rather than pushed inward:

```cpp
        r.x1 = max(r.x1, x1 + 2);
        r.y1 = max(r.y1, y1 + 2);
        r.x2 = min(r.x2, x2 - 2);
        r.y2 = min(r.y2, y2 - 2);
```

It returns a `Rect&` and no status, so the builder is not told, and there is nothing it could have checked.

**The builder paints the room** (src/MakeLev.cpp:2753). `Map::WriteRoom` writes wall on the perimeter squares and floor on every square inside (src/MakeLev.cpp:332). The room is finished and nothing below alters it. A 5-deep room is perfectly good. Nothing is wrong yet.

**Now the builder works out the space, by stepping 2 squares in from each of the room's four edges** (src/MakeLev.cpp:2759-2760). Across, the room is wide, so the space comes out 8 across — plenty. Down, the room is only 5 deep, so 2 off the top and 2 off the bottom leaves a space **1 square deep**, rows 4 to 5.

**That is the fault. Everything after it follows.**

**The builder asks `Rect::PlaceWithin` for a subroom 7 across and 1 deep, to go in that space** (src/MakeLev.cpp:2763, inc/Base.h:266). Those two sizes come from src/MakeLev.cpp:2761-2762, which takes off the same 4 it just stepped in, and then a random 0 to 4 more so the subroom is smaller than the space and can be positioned within it.

**Across it works.** 7 is smaller than 8, so there is slack. The placer slides the subroom to a spot inside the space and returns it at the size asked for (inc/Base.h:269-273).

**Down it cannot.** The space is 1 deep and the request is 1 deep, so there is nowhere to slide anything. When that happens the placer gives up on the requested size and returns the whole space with one square taken off each end (inc/Base.h:276):

```cpp
        if (sy >= (y2-y1)) 
          { r.y1 = y1+1; r.y2 = y2-1; }
```

On a normal space that is sensible: a space 4 deep comes back 2 deep, sitting neatly inside. On a space 1 deep there is nothing to take. The top edge moves down one, to row 5. The bottom edge moves up one, to row 4. **They have swapped. The subroom's top is now below its bottom.** Measured: space `(115,4)-(123,5)`, request 7 by 1, result `(116,5)-(123,4)`.

**Nobody checks.** The builder paints the subroom's walls along those four edges (src/MakeLev.cpp:2773-2780), written out in the room-builder rather than going through `WriteRoom` — which does refuse a rectangle 1 or less in either direction (src/MakeLev.cpp:334-337). Then it punches doors through those walls: one, then again for as long as a 1-in-3 draw says stop, so three on average and no upper limit. To choose a door's row it starts at the subroom's top edge and steps down a random amount between zero and its depth (src/MakeLev.cpp:2786), and its depth is minus one.

**Had the placer given the 7 it was asked for, none of this happens.** The space would be 3 deep — rows 2 to 5 — and 1 is smaller than 3, so the placer would take its ordinary path and slide the subroom in at rows 3 to 4. The two squares taken quietly at the start are the reason for all of it.

Measured on seed 3390. Every width and depth below is the gap between the two edges, not a count of squares — a rectangle whose top and bottom differ by 5 covers 6 rows:

| step | left | right | top | bottom | width | depth |
|---|---|---|---|---|---|---|
| the panel | 96 | 127 | 0 | 31 | 31 | 31 |
| room, asked for | | | | | 12 | 7 |
| room, as placed | 113 | 125 | **0** | 7 | 12 | 7 |
| room, after the clamps | 113 | 125 | **2** | 7 | 12 | **5** |
| the space for the subroom | 115 | 123 | 4 | 5 | **8** | **1** |
| subroom, asked for | | | | | 7 | 1 |
| subroom, returned | 116 | 123 | **5** | **4** | 7 | **-1** |

The room fits the panel easily and was placed at the size it asked for. The only thing wrong is where it landed.

Not a one-off: across the sweep `PlaceWithinSafely` was called 41,785 times and **16,372 of those came back smaller than requested** — mostly the near edges (left 10,877, top 10,823) but not only them (right 1,288, bottom 1,277; one call can trim two edges). It never returned an inverted rectangle itself. `PlaceWithin` was called 831 times over the same sweep and inverted twice. The width branch seven lines above the one quoted (inc/Base.h:269) has the same shape; I have not observed it firing.

After that it is arithmetic. Both the door loop and the decorator pick a square as `r.y1 + random(r.y2-r.y1)` (src/MakeLev.cpp:2967 for the decorator), so `random()` is asked for a value between zero and minus one, and the unsigned modulo in `random()` (inc/Inline.h:38) returns the raw draw cut to 16 bits. Tested standalone: with an extent of minus one, 19,960 of 20,000 draws land outside a 128-square map; with the same extent the right way round, none do. The decorator retries up to 100 times (src/MakeLev.cpp:2975), reading outside the map each pass, then places nothing — that accounts for nearly all of seed 3390's 47,954 reads and all 494 abandoned decorations. The door loop, running earlier over the same rectangle, is where the doors come from.

## What #41 actually does

The guard sits in `Map::GetAt` (src/Display.cpp:612), which walks the list of things on a square; `Map::At` beneath it is what leaves the grid. On seed 3390 the unguarded build makes 47,962 out-of-bounds reads and the guarded build 47,954. The 8-read difference is consistent with the 4 out-of-bounds `GetAt` lookups the guard stops on that seed — 3 `FDoorAt` calls from the door loop and 1 `FFeatureAt` inside `MakeDoor` — at two `At()` reads each, two rather than three because none of them is a creature lookup, which costs an extra read through `FieldAt`. All 4 landed on the (0,0) square and found it empty, so the guard changed no answer: the probe counts zero occasions where it would have returned something, and the 11 screens I dumped are byte-identical between the two builds.

So the guard covers 8 reads of 47,962 and changed nothing in the screens I captured. It is defensible as belt-and-braces — nothing should read outside the grid — but the reason I gave for it was wrong, so unless you would rather keep it, I will close #41.

## The repair I would suggest

Reserve, in `PlaceWithinSafely`'s random range, the 2 squares its clamps already insist on, so the near-edge clamps have nothing left to repair (inc/Base.h:290, and the same for `x1`):

```cpp
        r.y1 = (uint8)(y1 + 2 + random(max(0,((y2-y1)-3)-sy)));
```

The upper bound was already `y2-2` whenever the range was non-empty, so only the low side changes, and the signature does not, so none of the sixteen call sites do. Measured over the same 500 seeds, both builds carrying #41's guard:

| | guard only | guard + range reserve |
|---|---|---|
| `PlaceWithin` returned inverted | 2 | **0** |
| out-of-bounds reads | 48,354 | **0** |
| doors built on squares the code never chose | 4 | **0** |
| door placements | 4,958 | 4,979 |
| decoration attempts abandoned | 3,385 | 2,583 |
| sessions ending in a crash | 6 | 4 |

Three caveats. **Same seeds, not same levels** — changing what the random stream is spent on produces different dungeons, which is why the totals differ at all. **The crashes are pre-existing** — I read one of the four stacks from the fixed build and it is a re-entrant `Player::MoveDepth` null dereference the unmodified build also hits on other seeds; I did not classify the rest and claim nothing about them. **The shortfall is moved, not cured** — the range reserve still returns a short rectangle 6,241 times in 40,414 calls, now always on the far edge (right 3,984, bottom 4,010) where the caller's step inward absorbs it, never on the near one. A caller that steps in from a size it assumes it got is still exposed.

This reproduces in your tree, not only in my port: `int16` is `short` on both compilers, the modulo conversion is the same rule, `MakeDoor` takes `uint8` in the original, and the rectangle arithmetic is plain integers on `uint8` fields.

**The one thing I need from you:** if this is worth fixing, do you want it in `PlaceWithinSafely` as above, or in `Rect::PlaceWithin` — which has exactly one caller in the tree (src/MakeLev.cpp:2763), so refusing there to return a rectangle whose bottom is above its top would stop the chain at the last step instead of the first? I measured the first; I will open a fresh issue with the full evidence for whichever you prefer.

Full probe source, the logs, the standalone arithmetic test and reproduction instructions are here: https://github.com/networkingguru/incursion-roguelike/tree/2f58be3a659a8e4b8e1b9f11d7b5982da7146df4/docs/evidence/inc-5xn
