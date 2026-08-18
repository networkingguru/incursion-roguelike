# Stack cost of Player::MoveDepth, measured

arm64, Apple clang, -O2, macOS 15. Captured 2026-08-17.

## The shipping build, one level of the recursion

Each frame is the pre-decrement that saves registers plus the local
allocation. `incursion-ship` is built with COMPILER=no and carries the patch.

```
__ZN6Player9MoveDepthEsb
    00000001000669c8 sub sp, sp, #0x230
__ZN5Thing7PlaceAtEP3Mapssb
    0000000100042dd8 sub sp, sp, #0x1b0
__ZN8Creature14TerrainEffectsEv
    000000010011152c sub sp, sp, #0x460
```

    Player::MoveDepth          0x60 +  0x230 =  656
    Thing::PlaceAt             0x60 +  0x1b0 =  528
    Creature::TerrainEffects   0x60 +  0x460 = 1216
                                       total = 2400 bytes per level

The probe in `stackprobe-seed3362.log` measured 2416 for a build carrying
the probe itself, which costs 16 bytes. The two agree.

## What the patch itself costs: an A/B on one keyword

Two builds of this tree, same command, same flags, both carrying the diagnostic
probes so that the probes cancel. The only difference is the `static` on
`Thing *GoWith[64]` in `Player::MoveDepth`.

```
BACKEND=posix OUT=incursion-ab-patched ./build_macos.sh   # Thing *GoWith[64]
BACKEND=posix OUT=incursion-ab-static  ./build_macos.sh   # static Thing *GoWith[64]
```

```
incursion-ab-patched  __ZN6Player9MoveDepthEsb
    stp x28, x27, [sp, #-0x60]!
    sub sp, sp, #0x6e0                        0x60 + 0x6e0 = 1856

incursion-ab-static   __ZN6Player9MoveDepthEsb
    stp x28, x27, [sp, #-0x60]!
    sub sp, sp, #0x4e0                        0x60 + 0x4e0 = 1344
```

1856 - 1344 = **512 bytes**, which is 64 pointers of 8 bytes. The static build
also carries `__ZZN6Player9MoveDepthEsbE6GoWith` in `.bss`; the other does not.

So the recursion costs 2400 bytes a level with the patch, of which 512 is the
array it moved onto the stack. Without the patch a level costs 1888.

A provable maximum adds one more frame. The entry that asks for `DUN_DEPTH + 1`
allocates its prologue before it reads anything and faults at `Feature.cpp:887`,
never reaching `PlaceAt`, so it contributes `MoveDepth` alone:

    14 descents + the faulting entry, patched    14 x 2400 + 656 = 34,256
    14 descents + the faulting entry, unpatched  14 x 1888 + 144 = 26,576

The 144 is the patched 656 less the measured 512, not a disassembled figure.

## A correction, recorded because the wrong number was nearly sent

An earlier reading gave 432 bytes for the array by comparing `incursion-ship`
against `incursion-debug`, a binary built four days earlier from different
sources. Two builds that differ in more than one thing cannot measure one thing.
The A/B above changes exactly one keyword, and 512 is both the measured delta
and the size the array must have. Anyone re-deriving these figures should build
the pair rather than compare whatever binaries are lying around.
