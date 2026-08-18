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

Each function opens with the same register save, `stp x28, x27, [sp, #-0x60]!`,
which is the 0x60 term below; the `sub sp` immediate is the locals.

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
This pair carries `-DDEBUG` and the probes. At shipping flags the same keyword
moves the frame by 528, not 512, because the compiler allocates 16 bytes of
further locals with the array; the next section disassembles both.

So the recursion costs 2400 bytes a level with the patch, of which 512 is the
array it moved onto the stack. Without the patch a level costs 1872, disassembled below; an earlier
reading of 1888 came from subtracting the array size instead.

The provable maximum of the recursion's own frames adds one more frame. It is a
floor on the process's peak, not the peak itself: MoveDepth calls SaveGame on
every entry (src/Feature.cpp:858) and that subtree is not counted here. The entry that asks for `DUN_DEPTH + 1`
allocates its prologue before it reads anything and faults at `Feature.cpp:887`,
never reaching `PlaceAt`, so it contributes `MoveDepth` alone:

    15 completed moves + the faulting entry, patched    15 x 2400 + 656 = 36,656
    15 completed moves + the faulting entry, unpatched  15 x 1872 + 128 = 28,208

The chain reaches sixteen entries only when the outermost one arrives on level 1.
Two call sites arrive there with safe=false and so need only the one chasm
square: the spell Shift Level (lib/wspells.irh:7065, which reaches MoveDepth
through the binding that drops the safe argument) and wizard Ascend/Descend
(src/Debug.cpp:810). The ordinary arrivals -- the up-staircase
(src/Feature.cpp:260), the two skylight routes -- by levitation and by rope,
both inside the one isSkylight block at src/Skills.cpp:3990 (:4008, :4066) --
and resurrection (src/Prayer.cpp:1482) all pass safe=true, so each needs the
landing square AND all eight neighbours to be chasm. A chain that instead starts by falling from level 1 is
one entry shorter.

The 128 is disassembled, not subtracted. See the next section.

## The unpatched frame, disassembled rather than subtracted

Captured 2026-08-18. An earlier version of this file gave 144 bytes for the
unpatched `MoveDepth` frame by subtracting the measured 512-byte array from the
patched 656. That subtraction was wrong. Compiling the function both ways and
reading the prologue gives:

```
Thing *GoWith[64]         stp x28, x27, [sp, #-0x60]!   96
                          sub sp, sp, #0x230           560   total  656
static Thing *GoWith[64]  sub sp, sp, #0x80            128   total  128
```

Each function has exactly one stack allocation; `objdump -d
--disassemble-symbols=__ZN6Player9MoveDepthEsb` shows no second `sub sp` in
either. The difference is **528 bytes**, not 512. The array is 512 of it; the
compiler allocates 16 bytes of further locals alongside it, and it also lays the
register saves out differently -- the unpatched build covers saves and locals in
one `sub sp, #0x80`, where the patched build pre-decrements with the `stp` and
then subtracts the locals separately.

Method, which needs no full build and disturbs no working tree:

```
git show 4c7a138~1:src/Feature.cpp > base.cpp          # last probe-free revision
sed '874s/    Thing \*GoWith/    static Thing *GoWith/' base.cpp > static.cpp
clang++ -std=c++17 -O2 -w -fpermissive -Wno-narrowing -DPOSIX_TERM \
    -Iinc -Ilib -Icompat -c base.cpp -o base.o         # and again for static.cpp
objdump -d --disassemble-symbols=__ZN6Player9MoveDepthEsb base.o
```

These are the shipping flags: `COMPILER=no` drops `-DDEBUG`, so a build carrying
it is not comparable. The check that the method is sound is that `base.o` gives
`sub sp, sp, #0x230`, which is byte for byte what `incursion-ship` gives above.

The `.bss` symbol shows up in this pair too, not just in the full-build pair
above -- `nm` on the two objects:

```
base.o    (Thing *GoWith[64])          no GoWith symbol
static.o  (static Thing *GoWith[64])   00000000000079d8 b __ZZN6Player9MoveDepthEsbE6GoWith
```

The `b` is BSS. One array for the process in the static build; nothing at all in
the patched one, because the array lives in the frame.

So one level costs **1,872 bytes** without the patch, not 1,888:

    Player::MoveDepth (static)   128
    Thing::PlaceAt               528
    Creature::TerrainEffects    1216
                        total   1872

and the provable maximum of the recursion's own frames becomes

    15 completed moves + the faulting entry, patched    15 x 2400 + 656 = 36,656
    15 completed moves + the faulting entry, unpatched  15 x 1872 + 128 = 28,208

The difference, 8,448, is 16 x 528. The patched figures are unchanged.

## A correction, recorded because the wrong number was nearly sent

An earlier reading gave 432 bytes for the array by comparing `incursion-ship`
against `incursion-debug`, a binary built four days earlier from different
sources. Two builds that differ in more than one thing cannot measure one thing.
The A/B above changes exactly one keyword, and 512 is both the measured delta
and the size the array must have. Anyone re-deriving these figures should build
the pair rather than compare whatever binaries are lying around.

__ZN5Thing7PlaceAtEP3Mapssb (incursion-ship)
    0000000100042dbc stp x28, x27, [sp, #-0x60]!

__ZN8Creature14TerrainEffectsEv (incursion-ship)
    0000000100111510 stp x28, x27, [sp, #-0x60]!
