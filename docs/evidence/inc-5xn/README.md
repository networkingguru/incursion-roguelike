# inc-5xn — what an out-of-bounds map read actually does, measured

> **STATUS 2026-08-18, round 4. This block supersedes the round-3 block below
> it.** Brian asked two questions: is the door effect proof or theory, and has
> the fix been SEEN to remove it. Both are now answered by measurement.
>
> ## 1. The door effect is proven, and round 3 had not proven it
>
> Round 3 measured only the ARGUMENTS the door loop handed to `MakeDoor`. That
> is not a door: `Map::MakeDoor` returns early when a feature already stands on
> the square (`if (FFeatureAt(x,y)) return;`), and no probe looked. Round 4
> reads the square before the call and after it:
>
> ```
> DOOR_PLACED raw=(116,-7151) truncated=(116,17) feature_before=0 door_after=1 room=(116,5)-(123,4) truncated_inside_room=0
> DOOR_PLACED raw=(123,14601) truncated=(123,9)  feature_before=0 door_after=1 room=(116,5)-(123,4) truncated_inside_room=0
> ```
>
> Nothing on the square before, a door on it after, and neither square lies in
> the room the door belonged to. `doors-seed3390-upstream.log`.
>
> The same log prints the FINISHED level around each one, so the artefact can be
> seen rather than argued (`+` the door, `#` solid, `.` open):
>
> ```
> ###......####          ........###
> ###.####...##          ........###
> ###.#########          ###########
> ###.#########          ###########
> ###.##+######          ######+####
> ###.#########          ###########
> ###.#########          ###########
> ```
>
> Both doors stand sealed inside solid rock, three squares from the nearest
> corridor.
>
> ## 1b. ROUND 5: the third door is not discarded, it is moved to (1,1)
>
> The round-4 probe classified a coordinate whose `uint8` truncation was STILL
> off the map as "not built". Wrong. `Thing::PlaceAt` bounds-checks where
> `Map::MakeDoor` does not, and its repair is
> `if (!m->InBounds(_x,_y)) _x = _y = 1;` (upstream src/Display.cpp:151-152), so
> the door is built at (1,1) — the map's top-left corner. That is also the source
> of the single stray `ASSERT m->InBounds(_x,_y)` line each affected session logs
> next to the tens of thousands from the decorator; the stack in
> `r6-3390/logs/errors.log` reads PlaceAt <- MakeDoor <- DrawPanel.
>
> Seed 3390 therefore builds THREE doors off-plan, not two, and all three are
> still standing when generation finishes:
>
> ```
> DOOR_PLACED raw=(116,-7151) lands_at=(116,17) feature_before=0 door_after=1
> DOOR_PLACED raw=(123,-25691) lands_at=(1,1) (PlaceAt clamped to 1,1) door_after=1
> DOOR_PLACED raw=(123,14601) lands_at=(123,9) feature_before=0 door_after=1
> ```
>
> Corrected 500-session totals (seeds 3300-3799, unmodified build):
> 4,958 door placements, 4 raw out-of-bounds coordinates, **4 doors built**,
> 0 blocked by an existing feature, 4 landing outside their room, 1 clamped to
> (1,1). Seed 3390 contributes 3, seed 3515 one, and 3 of the 4 survive to the
> end of generation.
>
> **The lesson repeats.** Round 3 measured arguments and called it an effect.
> Round 4 measured the effect but modelled only ONE of the two repairs the engine
> applies on the way. Trace the value to where it lands, not to where it is
> passed.
>
> ## 2b. The 500-session totals, both builds
>
> | | unmodified | range reserve |
> |---|---|---|
> | `PlaceWithinSafely` calls | 41,785 | 40,414 |
> | of those, returned short | 16,372 | 6,241 |
> | edges trimmed: left / top / right / bottom | 10,877 / 10,823 / 1,288 / 1,277 | 0 / 0 / 3,984 / 4,010 |
> | `PlaceWithin` calls / returned inverted | 831 / **2** | 800 / **0** |
> | out-of-bounds `Map::At` reads | 48,354 | **0** |
> | door placements / built at a truncated coordinate | 4,958 / **3** | 4,979 / **0** |
> | decorator attempts / abandoned | 286,677 / 3,385 | 289,014 / 2,583 |
> | sessions ending in a crash | 6 | 4 |
>
> Abandoned decorations per session: median 2, next-worst session 43, seed 3390
> **494**. The range reserve does NOT cure the silent shortfall -- it moves it to
> the far edges, where the caller's fixed margin has room to absorb it.
>
> ## 2. How often, over 500 sessions
>
> Seeds 3300-3399 and 3400-3799, `tools/keys/dive.keys`, unmodified build:
>
> | | count |
> |---|---|
> | sessions | 500 |
> | sessions where `PlaceWithin` inverted the rectangle | **2** (3390, 3515) |
> | sessions with any out-of-bounds read | 2 |
> | out-of-bounds reads in those sessions | 47,954 and 398 |
> | door placements, all sessions | 4,958 |
> | doors built at a truncated coordinate | **3** |
> | of those, still standing at the end of generation | **2** |
>
> The inversion is rare — about 1 session in 250 — and loud when it happens.
>
> **A round-3 claim this corrects.** Seed 3515's misplaced door is GONE by the
> end of generation; the printed map shows open corridor at that square, so
> something later overwrote it. "A door is built in the wrong place" holds for
> all three. "A door REMAINS in the wrong place" holds for two of three.
>
> ## 3. The fix, measured on 500 sessions and not on one
>
> `-DINCURSION_OOB_RANGEFIX`, the same 500 seeds:
>
> | | unmodified | range fix |
> |---|---|---|
> | sessions | 500 | 500 |
> | door placements | 4,958 | 4,979 |
> | doors built at a truncated coordinate | **3** | **0** |
> | sessions with out-of-bounds reads | **2** | **0** |
> | sessions ending in a crash | 5 | 4 |
>
> The crash counts are the pre-existing `Player::MoveDepth` re-entrancy (inc-upw.15),
> confirmed by reading a faulting stack from the fixed build: it is the same
> `MoveDepth -> PlaceAt -> TerrainEffects -> MoveDepth` null dereference, on
> different seeds because the fix moves the random stream. The fix adds no crash.
>
> **The comparison is same-seed, not same-level.** Any fix that changes what the
> random generator is asked for produces different dungeons from the same seed;
> that is why the door-placement totals differ (4,958 against 4,979). A
> same-level A/B is not available for this class of change.
>
> ## 3b. A trap the round-4 probe set for itself
>
> The round-4 probe reads the square before and after `MakeDoor`, and on seed 3390
> one of those reads uses a truncated coordinate that is STILL off the map
> (y=165 on a 128-square map). So the probe performs 2 out-of-bounds lookups of
> its own, worth 4 reads. The instrumented build therefore reports 47,966 reads
> and `oob_calls=6`, where uninstrumented code reports 47,962 and `oob_calls=4`
> (`census-seed3390-upstream.log`). **Quote the uninstrumented numbers upstream.**
> The measurement instrument must not appear in the measurement.
>
> ## 4. A round-3 claim that is now RETRACTED
>
> Round 3 said the inverted rectangle costs the double room its inner chamber.
> **That is false, and the cause is unrelated to the inversion.** The finished
> level shows no inner wall ring for HEALTHY inner rectangles either — measured
> on seed 3390, which has two healthy ones ((5,14)-(10,20) and (69,107)-(74,109))
> and one inverted. The reason is priority: `WriteRoom` writes the outer room's
> interior floor at `PRIO_ROOM_FLOOR` (70, inc/Defines.h:4340) and the inner ring
> is then written at `PRIO_PILLARS` (50, :4337); `WriteAt` returns early when
> `At(x,y).Priority > Pri` (src/MakeLev.cpp:268). Every inner-ring wall write is
> dropped. So `RM_DOUBLE` builds no inner room in any case. Filed separately;
> it must not be attributed to this defect.
>
> **What survives as the player-visible effect** is therefore narrow and exact: a
> door object standing in solid rock, away from any room, in 2 of 3 firings, at
> about 1 session in 250. Everything else the inversion causes is invisible to
> the player and visible only in the logs.


> **STATUS 2026-08-18, after the third review round.** The draft reply
> (`docs/outgoing/issue40-reply.md`) is **stale and must not be sent**. Read this
> block before anything below it, because parts of the body are superseded.
>
> **There IS a player-visible effect, and it is not in the reply yet.** Doors are
> built at arbitrary squares. `MakeDoor` takes `uint8` and `FDoorAt` takes
> `int16` (src/MakeLev.cpp:2792-2793). When the rectangle inverts, the garbage
> `y` is truncated for `MakeDoor` and often lands back inside the map, so a door
> is placed on an unrelated square — `Map::MakeDoor` has no bounds check, only
> `if (FFeatureAt(x,y)) return;` — while `FDoorAt` fails on the raw value, so the
> inner room never gets its door. Silent: no assert, no error-log line.
> **Measured on seed 3390: 5 door placements, 3 with a raw coordinate off the
> map, 2 of those truncated back in bounds.** Tracked as inc-b5b.
>
> **Which repair helps, all measured on seed 3390:**
>
> | variant | out-of-bounds reads | decorations abandoned | doors misplaced | outcome |
> |---|---|---|---|---|
> | upstream as it stands | 47,962 | 494 | 2 | runs |
> | height test at the decorator's caller | 8 | 0 | **2** | runs |
> | `PlaceWithin` collapses | 0 | 6 | 0 | runs |
> | `PlaceWithin` widens | — | — | — | crashed on this seed |
> | `PlaceWithinSafely` reserves 2 in its range | **0** | **0** | **0** | runs |
>
> The height test at the decorator **does not fix the doors**, because the door
> loop uses the rectangle before the decorator runs. Neither does PR #41's guard.
> That is the argument for repairing the rectangle at source.
>
> **The last row is the best candidate and needs no API change.** Reserve the
> same 2 squares in `PlaceWithinSafely`'s random range that its clamps already
> demand, so the clamps have nothing left to repair:
> `r.x1 = (uint8)(x1 + 2 + random(max(0,((x2-x1)-3)-sx)));`
> Built as `-DINCURSION_OOB_RANGEFIX`. Caveat: 7 short placements remain, now on
> the **far** edges, so the silent-shortfall behaviour is not gone — only the
> failure it caused here.
>
> **Three claims below are now known FALSE:**
> 1. "only the top or left edge was ever trimmed" — across the 400-seed sweep,
>    13,000 short placements include 1,103 with the right edge trimmed and 1,080
>    with the bottom. Generalised from 11 lines on one seed.
> 2. "both repairs run clean" — four firings are known (3390, 4007, 4008, 4310)
>    and 3390 crashed. One in four. And 0 of 3 bounds the per-firing crash rate
>    only to about 63% at 95% confidence.
> 3. "the caller's existing width test hides the x-branch trap" — there is no
>    such test at that point; the door loop uses the rectangle first.
>
> **Instrument gap still open:** the pre-repair firing probe was added to the `y`
> branch only. The `x` branch carries the repair with no probe before it, so
> "neither crashing seed fired the repair" is unproven for `x`. That is the same
> class of defect as the two already caught.


rmtew asked this on issue #40 on 2026-08-15, and it is why pull request #41 is
still open:

> What is the observed effect of this change to the player? How does the monster
> behave before with the incorrect lookups and how does it behave afterwards
> with the failures? The answer to that guides what the proper fix should be
> IMO.

**All line numbers here are against `upstream/master` at `7469d3ed`**, not our
tree, because the reply that links this file cites theirs.

## The conclusion first

1. **The cause is a placement routine that silently returns less than it was
   asked for.** `Rect::PlaceWithinSafely` (inc/Base.h:285) places the rectangle
   at full size, then applies four *unconditional* clamps keeping it 2 clear of
   the panel border (inc/Base.h:293-296). They are not a does-it-fit test: they
   move only the offending edge, so a rectangle placed hard against the panel
   edge is trimmed rather than shifted, and the caller is never told. The room-within-a-room case then subtracts a fixed
   2-square margin as if it had received the size it requested.
   **Measured: asked 12x7, got 12x5, margin left 8x1.**
2. That 1-tall strip reaches `Rect::PlaceWithin` (src/MakeLev.cpp:2763), whose
   own does-not-fit branch insets by one more and returns a rectangle whose
   bottom is above its top. **Measured: `(115,4)-(123,5)` + request 7x1 ->
   `(116,5)-(123,4)`.**
3. From there: `random()` gets a negative size, returns an arbitrary `int16`,
   and the level builder reads outside the map **47,962 times** in the one seed
   of 80 that reproduces it.
4. **The guard in PR #41 stops 4 lookups, 8 of those reads**, and changes
   nothing the player sees.
5. **Monster AI is not the source of these reads**, but the claim stops there —
   see "What about the monster".

## How it was measured

One commit, built several ways, all carrying an env-gated probe
(`INCURSION_OOB_PROBE=1`):

| flag | what it makes |
|---|---|
| *(none)* | our tree as it stands, with the #41 guard |
| `-DINCURSION_OOB_UNGUARDED` | removes the #41 guard, restoring upstream |
| `-DINCURSION_OOB_RECTFIX` | adds a height test where the decorator is called |
| `-DINCURSION_OOB_PWFIX` | `PlaceWithin` collapses instead of inverting |
| `-DINCURSION_OOB_PWFIX_WIDEN` | `PlaceWithin` widens instead of inverting |

```
EXTRA_CXXFLAGS="-DINCURSION_OOB_PROBE -DINCURSION_OOB_UNGUARDED -g" \
  OUT=incursion-oob-g BACKEND=posix ./build_macos.sh
INCURSION_OOB_PROBE=1 INCURSION_BIN=./incursion-oob-g \
  tools/headless.sh tools/keys/dive.keys 3390
```

The probe records what the error log cannot. The log keeps one call stack per
distinct message, so 47,954 reads are represented by one stack, and that single
stack was previously read as though it spoke for all of them. The probe counts
every out-of-bounds `Map::At()` **by its own call stack**; records what the
unguarded `GetAt` would have returned; counts rectangles returned inverted by
`PlaceWithin` and `PlaceWithinSafely` separately; captures the outer room before
and after the margin is subtracted; and watches whether the hiding-monster scan
ever picks a victim off the map.

**The harness is a generator stress test, and that has to be said.**
`tools/keys/dive.keys` drives the wizard menu to descend repeatedly. It reaches
`Player::MoveDepth` and `Map::Generate`, the same path as a staircase, but far
more often than play would.

## What the numbers say

Seed 3390, a 128x128 map. Logs in this directory.

| build | out-of-bounds `At()` reads | decorations abandoned | outcome |
|---|---|---|---|
| upstream as it stands | 47,962 | 494 | runs |
| height test at the decorator's caller | 8 | 0 | runs |
| `PlaceWithin` widens when it will not fit | not measured | not measured | crashed on this seed; see Blast radius |
| `PlaceWithin` collapses when it will not fit | 0 | 6 | runs |

**The fixed builds do not generate the same levels.** Changing the rectangle
changes what the random stream is spent on: `PlaceWithinSafely` goes from 30
calls to 66, and the decorator from 720 to 550. "Zero reads" is measured on a
different set of levels, not the same levels minus the bug. No way to hold that
constant has been found.

1 of 80 sessions reproduced it; 79 measured anything at all (one explore session
never entered a map). **This is deliberately not converted into a per-level
rate**: the dive script visits many levels per session, so sessions and levels
are not interchangeable.

An earlier version of this file claimed the older 250-seed sweep hit this on
three seeds. That was wrong. Only seed 3390 has it. Seeds 3199 and 3255 hold two
asserts each from `Thing::Remove` <- `Creature::Multiply`, a different defect.
The error came from counting occurrences of the assert text instead of reading
the stacks.

## The chain, one measured link at a time

1. `Rect::PlaceWithinSafely` (inc/Base.h:285) places a rectangle of the
   requested size, then applies four unconditional clamps (inc/Base.h:293-296)
   that keep it 2 clear of the panel border. There is no does-it-fit test and no
   way to report a shortfall. **Measured:** asked for 12x7, placed at full 12x7,
   returned `(113,2)-(125,7)` = 12x5 after clamping.
2. The room-within-a-room case subtracts a fixed margin on every side
   (src/MakeLev.cpp:2759) as though it had received 12x7:
   `r.x1 += 2; r.x2 -= 2; r.y1 += 2; r.y2 -= 2;`

   The full geometry, using this code's convention that height is
   `bottom - top` (so rows 2..7 count as 5, not 6):

   | step | left | right | top | bottom | width | height |
   |---|---|---|---|---|---|---|
   | the panel | 96 | 127 | 0 | 31 | 31 | 31 |
   | room size asked for | | | | | 12 | 7 |
   | where it was placed | 113 | 125 | **0** | 7 | 12 | 7 |
   | after the four clamps | 113 | 125 | **2** | 7 | 12 | **5** |
   | after the fixed margin | 115 | 123 | 4 | 5 | **8** | **1** |

   The room fits the panel easily and was placed at full size. Its top edge
   landed on y=0, the panel's own top edge. The clamps keep a room 2 clear of
   the border by moving the offending edge inward -- top 0 becomes 2 -- and
   nothing moves the opposite edge to compensate, so the room is trimmed rather
   than relocated. The width survives because neither side edge broke the rule.

   **Not a one-off within the run**, though this is one seed's session only. Of
   30 placements, 11 came back smaller than requested, and in all 11 only the
   top or left edge was trimmed -- bottom and right never once. Raw lines:
   `PWS_SHORT` in `census-seed3390-upstream.log`.

   The margin is then subtracted as though the room were 7 tall, taking 4 off a
   5 and leaving 1. At the requested 7 it would have left 3. An 8x1 inner room
   is a corridor, so the nesting is degenerate before anything goes out of
   bounds.
3. That strip goes to `Rect::PlaceWithin` (src/MakeLev.cpp:2763). Its does-not-
   fit branch (inc/Base.h:276) insets by one on each side:
   `if (sy >= (y2-y1)) { r.y1 = y1+1; r.y2 = y2-1; }`
   The test is `1 >= 1`, so it insets: top becomes 4+1 = 5, bottom becomes
   5-1 = 4, and the top is now below the bottom.
   **Measured:** area `(115,4)-(123,5)`, request 7x1, result `(116,5)-(123,4)`.
   The same trap is in the width branch at inc/Base.h:269; the caller's existing
   width test hides that one.
4. The decorator picks a square as `y = r.y1 + random(r.y2-r.y1)`
   (src/MakeLev.cpp:2967), handing `random()` a negative size.
5. `random(int16 mx)` is `(int16)(genrand_int32() % mx)` (inc/Inline.h:38).
   `genrand_int32()` is unsigned, so a negative `mx` becomes a huge unsigned
   divisor and the result is the raw value cut to 16 bits.
   `random-negative-selftest.cpp` proves this in isolation: 19,960 of 20,000
   draws leave a 128-square map; the same size the right way round, none.
6. `SolidAt` reads there (src/MakeLev.cpp:2978). `Map::At` (inc/Map.h:214)
   answers with the (0,0) square, which is indestructible rock and so solid, so
   the loop retries up to 100 times.

**Ruled out by measurement, not by argument:** `PlaceWithinSafely` never itself
returned an inverted rectangle (30 calls, 0). And the requested size never went
negative on this seed (`requested_size_negative=0`), so the `(uint8)` cast at
src/MakeLev.cpp:2763 did not contribute here — it is a hazard visible in the
source that was not observed firing, and must not be reported as the cause.

**Observed `x` stayed in 116..122 on the 47,954-read stack only**; other stacks
show 116..123 and 123..123. That range is simply `116 + random(7)` — ordinary
behaviour, evidencing nothing. An earlier version of this file called it
corroboration on the grounds that the width was zero. The width is 7. The
`worst_dx=0` in the logs is the probe's untouched initial value and can never
update, because the caller's own test guarantees a positive width.

## What about the monster

The scan originally blamed is of the eight squares around a hiding monster
(src/Monster.cpp:547), so the monster must stand on the outer ring for it to
leave the grid. `Creature::Walk` rejects those coordinates (src/Move.cpp:271) by
coordinate rather than by terrain, covering walking, being pushed and jumping.
The ambush probe never fired in 79 sessions.

That is as far as the evidence goes, and the stronger claim is withdrawn. Two
things in our own evidence contradict it. `Map::besideWall` carries `/* ww:
someone at (0,122) will do an out-of-bounds At() check ... yes, this happened to
me! */` (src/Display.cpp:688). And in the widening build the out-of-bounds
assertion fired with the stack `Monster::ChooseAction` -> `Creature::Cast` ->
`Map::MakeNoiseXY` -> `Map::FieldAt` -> `Map::At`, which the ambush probe could
never have seen. This is the logged **assertion** on a real coordinate check, a
separate event from the segfault under Blast radius, which is a null object
rather than a bad coordinate; both occurred in the same run. Observed once, in a
modified build, not investigated here.

Note also that the terrain's `ABORT` on `EV_MON_CONSIDER` is irrelevant to this
scan: `FCreatureAt` is `GetAt(x,y,T_CREATURE,true)` (inc/Map.h:244) and throws
no event, so no terrain script can suppress the read.

## What PR #41 actually does

- Stops 4 lookups, which made 8 of the 47,962 reads. Checkable rather than
  asserted: an unguarded `GetAt` reads the corner square twice when it finds
  nothing, and 47,962 - 47,954 = 8.
- Those 4 came from `Map::DrawPanel` and `Map::MakeDoor` — level building.
- All 4 found the corner square empty, so no answer changed. Screen dumps are
  byte-identical across 11 dumps; session logs differ only in timestamps.

## Blast radius

`Rect::PlaceWithin` has **exactly one** caller in the tree, src/MakeLev.cpp:2763.
`PlaceWithinSafely` has **sixteen** call sites, all in src/MakeLev.cpp, so making
it report the failure it currently hides is a far larger change.

Two repairs to `PlaceWithin` were built: collapse to a single row, and widen to
the available area. **Both run clean.** An earlier version of this file said
widening crashes. That was wrong, and the way it went wrong is worth keeping.

**Two defects in the instrument, both of which hid the answer.**

1. The inversion was recorded *after* the repair ran, so a repaired build saw a
   corrected rectangle and logged nothing. A build where the change never
   applied and a build where it applied both reported zero firings.
2. The count was only emitted in the exit summary, and a run that segfaults
   never reaches it. Crashed runs — precisely the ones under investigation —
   reported nothing.

Together they produced a confident false reading: a 20-seed sweep showed 19
clean and 1 crash, "so the crash is a fluke"; then the probe logs showed
`returned_inverted=0` on all 19, which read as "the branch fired once and
crashed". Both readings were artefacts. **A pass rate means nothing until you
confirm the changed code actually ran.**

With detection moved before the repair and written as it happens, a 400-seed
sweep of the widening build gives:

| | count |
|---|---|
| seeds where the repair fired | 3 (4007, 4008, 4310) |
| ...that crashed | **0** |
| ...that recorded out-of-bounds reads | **0** |
| seeds that crashed | 2 (4168, 4188) |
| ...that fired the repair | **0** |

The two crashing seeds crash on the **unmodified** build as well — confirmed by
running them — with a different faulting stack: null at 0x0 in a re-entrant
`Player::MoveDepth` <- `Creature::TerrainEffects` <- `Thing::PlaceAt` <-
`Player::MoveDepth`. That is tracked as inc-upw.15, and these are two fresh
reproducing seeds for it. So this codebase segfaults on roughly 0.5% of dive
seeds by itself.

The one crash that did coincide with a firing, on seed 3390, had a different
stack again — `Map::At` inlined into `Map::FieldAt`, from `Map::MakeNoiseXY`,
from `Creature::Cast`, from `Monster::ChooseAction`; a null `Map` pointer at
offset 0x10, i.e. a monster with no valid map casting a spell. Object lifetime,
not geometry. One occurrence against three clean firings, and not evidence
against widening. Crash report kept as
`crash-seed3390-placewithin-widen.ips`.

Both variants are compile flags so either can be reproduced.

## Provenance

Upstream's, not the port's. `int16` is `short` on MSVC too, `genrand_int32()` is
unsigned in both, and the conversion that turns a negative divisor into a huge
unsigned one is the same rule. The rectangle arithmetic is plain integers on
`uint8` fields.

## What is wrong in the published text

Issue #40 and commit `0b1abe6` say a hiding monster at a map edge produced 343
out-of-bounds reads in 13 seconds, logged as the `inc/Map.h` assert. That assert
is in `Map::At`, which every path here reaches. The attribution was inferred
from one call stack, not measured, and nothing reproducible supports it.

The verification line — "877 turns over 583 seconds produced an empty error log,
against 444 errors in 13 seconds before" — cannot be the guard's doing either.
The guard is in `GetAt`; these reads arrive through `Map::At` by another route.
A soak on 2026-08-14, after the guard landed, logged 47,954 of the same
assertion. That figure appears three times in this file for three related
quantities, which is worth stating so it does not read as a copy error: the
dominant single stack in the unguarded run is 47,954, the guarded run's total is
47,954, and the 2026-08-14 soak was itself a guarded build. They agree because
the guard removes exactly the 8 reads that are not on that stack. The original session is not reproducible: the count was real, the
attribution is withdrawn.

## Files

- `census-seed3390-upstream.log` — full census, upstream behaviour, including
  the outer-room and `PlaceWithin` measurements.
- `census-seed3390-ycheck.log` — height test at the decorator's caller.
- `census-seed3390-placewithin-collapse.log` — `PlaceWithin` collapsing. Zero
  reads. Note it shows the same flattened outer room, so the cause is unchanged
  up to the last step.
- `errors-seed3390-placewithin-widen-CRASH.log` — the widening variant's crash.
- `random-negative-selftest.cpp` — standalone proof of the `random()`
  arithmetic. Build and run; exits 0 and prints PASS.
