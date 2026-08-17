# Evidence for inc-90u

Changing level abandons some followers. A player with three followers arrives
with two; the third stays on the level he left, silently.

Captured 2026-08-17, macOS 15 arm64, `incursion-headless` built from this tree
plus one temporary probe.

## Reproduce

```
BACKEND=posix ./build_macos.sh
INCURSION_FOLLOWER_PROBE=1 tools/headless.sh tools/keys/followers.keys 3362
```

Deterministic. Reproduced on seeds 3362, 4242, 111 and 555 — seven level
changes in total, every one of them losing exactly one follower.

## The result

`followerprobe-4seeds.log`, one line per level change:

```
MoveDepth depth=1 followers_before=3 collected=2 left_behind=1
```

Some sessions change level more than once, so some seeds contribute more than
one line. No line in any run shows all three followers collected.

`followers_before` is a read-only pass over the level, taken before the
collection loop runs, so it cannot alter what it measures. `collected` is what
the loop actually gathered. `left_behind` re-asks the old level what is still
standing on it after the loop finished.

`screen-summoned.txt` shows the three kobolds (`k`) placed beside the player
(`@`); `screen-mastered.txt` shows one of them being made a companion.

## Why it happens

Three pieces of ordinary code that are wrong only in combination:

1. the collection loop walks the level's contents by index — `MapIterate`
   (`inc/Base.h:92`) advances with `i++`;
2. collecting a follower calls `Remove`, which deletes that creature from
   `m->Things` (`src/Display.cpp:1227`);
3. `Array::Remove` memmoves the tail one place left (`src/Base.cpp:595`).

So the entry after a removed one slides into the index the loop has just
finished with, and `i++` steps over it. A single follower is therefore always
safe. The second of any adjacent pair is lost — and creatures made together, a
summoned group or an encounter, are adjacent.

## Scope

The same loop carries animal companions (`ANIMAL_COMPANION` with `TA_LEADER`),
Leadership followers and charmed creatures between levels. Nothing tells the
player that anything was left behind.

## Relationship to PR #43

This is why the answer to rmtew's question (c) — why not size the array from the
number of followers — is not a simple yes. The obvious implementation counts in
one pass and collects in a second, and the two cannot agree while the collect
pass mutates the list it is walking. A growable container removes the counting
pass instead of trying to fix it.

## Provenance

Upstream's. Plain array indices and a memmove; nothing depends on the port, and
it behaves identically on Win32 with the original typedefs. Tier: Observed.
Not sent.
