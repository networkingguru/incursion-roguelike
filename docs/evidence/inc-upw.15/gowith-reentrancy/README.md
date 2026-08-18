# The static GoWith array is corrupted by re-entry -- observed

Captured 2026-08-18, macOS 15 arm64, seed 3362. Until this run the claim was
read from the source and labelled as such. It is now an A/B measurement on one
keyword, with a visible consequence in the game.

## What was claimed

`Player::MoveDepth` declares `static Thing *GoWith[64]` but keeps its count
`gwc` as an ordinary local. When the function re-enters itself -- the player
arrives on a chasm square, `PlaceAt` fires `TerrainEffects`, and that calls
`MoveDepth` again -- the nested call runs its own collection loop over the
ARRIVAL level and writes the same array from index 0. The outer call then walks
its own `gwc` over contents that are no longer its own.

## How the state was arranged

Everything below happens through ordinary game mechanisms. Nothing creates
terrain, and no creature is teleported.

1. Three kobolds are summoned in wizard mode on depth 1 and each is made a
   follower. They land at consecutive indices in `m->Things` (393, 394, 395).
2. `w p 7` descends to depth 7. The collection loop takes two of the three and
   strands one on depth 1 -- the index skip of inc-90u, reproduced here as a
   side effect rather than as the subject.
3. `w p 6` ascends to depth 6. The two followers on depth 7 are adjacent (256,
   257), so the same skip strands one of THEM on depth 7. This is the
   pre-existing follower the trace needs, and it got there by playing.
4. `w p 7` descends again. This arrival is steered onto a chasm square that
   depth 7 already contains, which makes the fall -- and therefore the nested
   `MoveDepth` -- happen on demand instead of by luck.

The steering is `INCURSION_FALL_CHAIN=7` with `INCURSION_FALL_CHAIN_SKIP=1`,
which ignores the first arrival at depth 7 and steers the second. It only
chooses which existing square the arriving player lands on.

## Reproduce

```
BACKEND=posix OUT=incursion-chain ./build_macos.sh                 # as shipped
# then edit src/Feature.cpp to read `static Thing *GoWith[64];` and
BACKEND=posix OUT=incursion-static-chain ./build_macos.sh          # as upstream

INCURSION_BIN=./incursion-static-chain INCURSION_RUN_DIR=<dir> \
  INCURSION_GOWITH_PROBE=1 INCURSION_FOLLOWER_PROBE=1 \
  INCURSION_FALL_CHAIN=7 INCURSION_FALL_CHAIN_SKIP=1 \
  tools/headless.sh gowith.keys 3362
```

The probe prints the array's ADDRESS and its live entries twice per call: when
collection finishes, and immediately before the placement loop reads them back.

## The result

`gowith-static-seed3362.log`, upstream's declaration. One address throughout,
because the array is in `.bss`:

```
collected nest=1 depth=6 array=0x1011f99f8 gwc=1 entries=[0x714f80000]
collected nest=2 depth=7 array=0x1011f99f8 gwc=1 entries=[0x714f80e00]
placing   nest=2 depth=8 array=0x1011f99f8 gwc=1 entries=[0x714f80e00]
placing   nest=1 depth=8 array=0x1011f99f8 gwc=1 entries=[0x714f80e00]
```

The outer call collected `0x714f80000`. By the time it reaches its own
placement loop the array holds `0x714f80e00`, which is the creature the NESTED
call collected. So the outer call places the nested call's follower a second
time, and the follower it actually collected is placed nowhere. It appears in
no later line of the log.

`gowith-patched-seed3362.log`, the same seed and the same key script with the
`static` removed. Two addresses, both on the stack:

```
collected nest=1 depth=6 array=0x16da74a00 gwc=1 entries=[0x1033408a0]
collected nest=2 depth=7 array=0x16da73bc0 gwc=1 entries=[0x1033416a0]
placing   nest=2 depth=8 array=0x16da73bc0 gwc=1 entries=[0x1033416a0]
placing   nest=1 depth=8 array=0x16da74a00 gwc=1 entries=[0x1033408a0]
```

Each frame keeps its own array, and each places the creature it collected.

`followerprobe-static-seed3362.log` is identical in both runs, which is the
control that matters: the two builds walked the same game and collected the same
creatures at the same indices. The only difference is the keyword.

## The consequence a player would see

Both sessions end with the player on depth 8. `screen-final-patched.txt` lists
`k kobold` in Things in View. `screen-final-static.txt` lists none.

The reason is in the trace above. The outer call's `new_m` is the depth 7 map,
so its placement loop puts whatever `GoWith[0]` holds onto depth 7. In the
patched run that is the follower it collected, and the follower the nested call
placed on depth 8 stays there with the player. In the static run the outer call
re-places the nested call's follower, dragging it back up from depth 8 to depth
7, and loses its own. The player arrives alone, and one follower is on no map at
all.

## Provenance

Upstream's. The `static` is upstream's declaration, `gwc` is a local in
upstream's code, and the re-entrancy is upstream's control flow; nothing here
depends on the port, the typedefs or the compiler. Tier: Observed. Not sent.

The probes (`INCURSION_GOWITH_PROBE`, `INCURSION_FALL_CHAIN`,
`INCURSION_FALL_CHAIN_SKIP`) are temporary and are deleted with inc-upw.15.
