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
`src/Feature.cpp:270` and `:278`, and several spells -- but
`Player::MoveDepth`'s collection loop is the only thing that brings a player's
followers with him.

`Game::LimboCheck` (`src/Feature.cpp:820`) would re-place a parked Thing on the
player's current map, but it is dead code: nothing calls it, and nothing could
feed it anyway, since parking needs `EnterLimbo` and no shipped script calls
that either (`lib/dispatch.h:2174` is its only entry point).

## Scope

The loop collects whatever `ts.isLeader(this)` accepts. `getLeader` returns the
FIRST valid `TargetLeader`, `TargetSummoner`, `TargetMaster` or `TargetMount`
entry (`src/Target.cpp:903-921` upstream), so the test is whether the player is
that first leader-type target -- not merely present in the list.

That covers summoned creatures and animal companions, which reach it through
`Monster::MakeCompanion` adding `TargetSummoner` (`src/Social.cpp:2414`) rather
than through any `ANIMAL_COMPANION` stati. It does NOT cover mounts: `Mount`
removes the creature from `m->Things` (`src/Skills.cpp:4272`) and re-attaches it
by assigning `m`, `x` and `y` without re-adding it, so `MapIterate` never sees
it. `TargetMount` is added at `:4287`, not by `MakeCompanion`. No charmed creature is collected, whatever the value.
`Status.cpp:675` does route `CH_DOMINATE`, `CH_ALLY` and `CH_COMMAND` into
`MakeCompanion`, which adds the `TargetSummoner` -- and then `:677` calls
`ts.removeCreatureTarget(player, TargetAny)` on the very next line, which
invalidates every entry naming the player, the new one included
(`Target.cpp:1036-1042`), after which `Retarget(force)` rebuilds the list
skipping invalid entries (`:1264-1282`).

A charmed creature can still become a follower later by a route that does not go
through `StatiOn` -- Animal Empathy at `src/Skills.cpp:1172` or Enlist at
`src/Social.cpp:743` -- and is then collected like any other companion.

An earlier version of this file said the opposite and told future readers not to
re-open the question. That was wrong twice over: the conclusion, and the idea
that a note can settle something two lines of code decide. The wizard command
used by `tools/keys/followers.keys` -- 'Make Player Master of Monster',
`Debug.cpp:1019` -- calls `MakeCompanion` directly and never passes through
`Status.cpp:677`, which is why the measured runs collect their followers. Creatures created
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
