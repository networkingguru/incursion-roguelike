# inc-5bl3 -- TRUE_SIGHT sees through invisibility and darkness, out to its range

The before/after gameplay observation for the TRUE_SIGHT fix. Brian required an
observation rather than a probe result on 2026-09-18, because the change is in
the `rules:` lane and a player feels it.

## How to reproduce it

Two builds, one key script, one seed. The builds differ only by the fix.

    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_RUN_DIR=logs/runs/obs-s1 \
        tools/headless.sh tools/keys/true-sight-observe.keys 1

The script makes the standard orc mage, sets the Infinite Mana and Freeze
Monsters wizard switches, jumps to depth 2 to get off the arrival room -- which
is lit by design and would hide the darkness half -- learns True Seeing, summons
a sprite one square east, dumps the screen, casts True Seeing, and dumps it
again. A sprite carries `Stati[INVIS,INV_IMPROVED]` (`lib/mon2.irh`), so it is
invisible with no extra step.

The before build is master at b443f8f. The after build is the same tree plus the
fix. Both runs report 22 turns over 4 keys, no stall, no errors and a clean map
audit, so the two sessions are the same game and the only variable is the build.

## What the two screens show

The files here are the rendered screens, `@dump`ed by the harness.

`seed1-after-trueseeing-BEFORE-FIX.txt` -- True Seeing is active and changes
nothing. The player stands in a corridor on depth 2, the Ancient Library:

                                           ###########
                                          ......@......
                                           ###########

`seed1-after-trueseeing-AFTER-FIX.txt` -- the same turn of the same game:

                                      #  # ###########
                                    ............@f......#
                                      #  # ###########

Two changes, one per half of the fix.

1. **Invisibility.** `f` is the sprite, one square east. It is drawn only on the
   fixed build, and "f sprite" appears in the Things in View panel only there.
2. **Darkness.** The corridor now renders about twelve squares each way instead
   of six, and two side openings appear. Twelve squares is True Seeing's range,
   120 feet at this codebase's ten-feet-per-square scale.

`seed1-before-cast-AFTER-FIX.txt` is the control: the fixed build one keystroke
earlier, before the spell is cast. It matches the pre-fix screen. So the
difference above is the spell taking effect, not the build drawing more of every
map.

## Coverage, stated plainly

Seed 1 is the seed that shows BOTH halves, because the corridor it lands in is
longer than the player's light radius. Seeds 3, 7 and 4242 also run clean and
show the sprite appearing, but their rooms fit inside normal light, so the
darkness half does not show there. Use seed 1.
