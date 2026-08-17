# Evidence for inc-90u

Changing level abandons a follower whenever two followers sit next to each other
in the level's `Things` list. A player with three followers arrives with two;
the third stays on the level he left, silently, and never catches up.

Captured 2026-08-17, macOS 15 arm64, `incursion-headless` built from this tree
plus one temporary probe.

## Reproduce

```
BACKEND=posix ./build_macos.sh
INCURSION_RUN_DIR=/tmp/inc-90u-3362 INCURSION_FOLLOWER_PROBE=1 \
    tools/headless.sh tools/keys/followers.keys 3362
```

Deterministic: the same seed run twice writes the same line.

**Set `INCURSION_RUN_DIR` when running several seeds.** `tools/headless.sh:82`
names the run directory `$(date +%Y%m%d-%H%M%S)-<script>`, so runs that start
inside the same second share one directory, and the probe appends to its log.
Without a distinct directory per run the log accumulates lines from earlier
seeds and looks like one session that changed level several times. An earlier
version of this file reported "seven level changes" for that reason; the figure
was an artefact of the shared directory, not a measurement.

## The result

`followerprobe-10seeds.log`, one run per seed, each in its own directory:

| seed | followers | at (index in `Things`) | collected | left behind |
|---|---|---|---|---|
| 3362 | 3 | 393, 394, 395 | 2 | 1 |
| 111 | 3 | 440, 441, 442 | 2 | 1 |
| 555 | 3 | 183, 184, 185 | 2 | 1 |
| 888 | 3 | 667, 668, 669 | 2 | 1 |
| 999 | 3 | 306, 307, 308 | 2 | 1 |
| 1234 | 3 | 815, 816, 817 | 2 | 1 |
| 2468 | 3 | 490, 491, 492 | 2 | 1 |
| 13579 | 2 | 236, 237 | 1 | 1 |
| 777 | 2 | 395, **397** | 2 | 0 |
| 4242 | — the script desynced and this session never changed level — | | | |

`followers_before` is a read-only pass over the level taken before the
collection loop runs, so it cannot alter what it measures. `at` is each
follower's index in `m->Things`. `collected` is what the loop gathered.
`left_behind` re-asks the old level what is still standing on it afterwards.

Seed 777 is the control. Its two followers are at 395 and 397, one apart, and
both were collected. Every session whose followers were consecutive lost one.
That is the whole of the defect: not "followers are lost", but "an entry that
slides into a just-consumed index is skipped".

## Why it happens

Three pieces of ordinary code that are wrong only in combination:

1. the collection loop walks the level's contents by index — `MapIterate`
   (`inc/Base.h:78` upstream) advances with `i++`;
2. collecting a follower calls `Remove`, which deletes that creature from
   `m->Things` (`src/Display.cpp:1130` upstream);
3. `Array::Remove` memmoves the tail one place left (`src/Base.cpp:535`
   upstream).

So the entry after a removed one slides into the index the loop has just
finished with, and `i++` steps over it. Three consecutive followers therefore
yield two: the loop takes the first and the third, and the second slides into
the consumed slot.

## They do not catch up

`screen-arrived-depth2.txt` is the arrival on depth 2 of seed 3362: `@` with two
`k` beside it and "Things in View: k kobold, k kobold". `screen-after-60-turns.txt`
is the same session sixty turns later — one kobold and one kobold corpse, killed
by a black orc. The count only falls. No third kobold appears.

The code says why. The turn loop iterates the player's current map only
(`MapIterate(mp,t,i)`, `src/Main.cpp:220` upstream), so a creature on any other level
receives no turns at all. Even if it could act, the stairs handler sends a
non-player through `Thing::MoveDepth`, which is `Remove(true)` — a monster that
takes stairs is deleted, not moved. Other code does move creatures between maps -- dungeon entry and return at
`src/Feature.cpp:270` and `:278`, `Game::LimboCheck`, several spells -- but
`Player::MoveDepth`'s collection loop is the only thing that brings a player's
followers with him.

## Scope

The same loop carries animal companions (`ANIMAL_COMPANION` with `TA_LEADER`),
Leadership followers and charmed creatures between levels. Creatures created
together — a summoned group, an encounter — are appended to `Things` together,
which is exactly the adjacency the defect needs. Nothing tells the player that
anything was left behind.

## Relationship to PR #43

This is why the answer to rmtew's question (c) — why not size the array from the
number of followers — is not a simple yes. The obvious implementation counts in
one pass and collects in a second, and the two cannot agree while the collect
pass mutates the list it is walking. A growable container removes the counting
pass instead of trying to fix it. The index skip is a separate defect from the
container choice and wants its own patch.

## Provenance

Upstream's. Plain array indices and a memmove; nothing depends on the port, and
it behaves identically on Win32 with the original typedefs. Tier: Observed.
Not sent.
