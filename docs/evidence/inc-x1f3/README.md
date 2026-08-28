# Evidence for inc-x1f3

`Creature::Devour(Corpse * c)` (`src/Skills.cpp`) builds a fake `Monster` from a
devoured corpse to score the meal, then copies the corpse's `TEMPLATE` stati
onto it so a templated corpse (celestial, fiendish, half-dragon, pseudonatural)
grants the template's resistances. It iterated `StatiIterNature(this, TEMPLATE)`
-- the EATER's templates -- instead of the corpse `c`'s, so a character with the
Devouring ability who ate a templated corpse got the base creature's payoff only
and the template's resistances were silently dropped.

The fix changes two tokens, `this` -> `c`, at the iteration's open and close
(they must name the same object; the macro bumps a `Nested` counter on its
argument). See the `upstream:` mark at the fix site and the row in
`docs/REPORTING-GATE.md`.

Captured 2026-08-28, macOS 15 arm64, `incursion-headless` built from this tree.
The character `Dench the Savage II` (`Dench.sav`, here) is a level-9 Orc with the
Devouring racial ability, standing on a fresh **celestial arsinoitherium corpse**
on depth 7 of the Goblin Caves.

## Reproduce

A/B on the same save, same seed, one build differing only in the two tokens
above. `Dench.sav` and the key script are in this directory.

```
# Fixed build (this tree):
BACKEND=posix ./build_macos.sh
INCURSION_RUN_DIR=/tmp/inc-x1f3-fixed INCURSION_OPTIONS=tools/gates/Options.Dat \
    tools/headless.sh docs/evidence/inc-x1f3/devour-celestial.keys 1
# revert src/Skills.cpp:3079/3081 back to StatiIterNature(this,..)/StatiIterEnd(this),
# rebuild, and run the same line into /tmp/inc-x1f3-prefix for the pre-fix side.
```

The key script loads the save, steps onto nothing (the corpse is under the
player), opens the Eat menu (`e`), chooses the ground corpse (`a`), answers the
one "You are full. Stop eating?" prompt with `n` (Dench is already satiated; the
prompt's `confirm` then suppresses itself for the rest of the meal), and waits
out the ~465-turn meal so `Devour()` fires on the fully-eaten corpse.

## The result

Both runs play the identical 465 turns; only the two-token source differs.

| build | message when the celestial corpse is fully devoured |
|---|---|
| pre-fix | `You finish eating the celestial arsinoitherium corpse (fresh, DC 8).` -- **no resistance gained** |
| fixed | `You gained Lightning resistance from the celestial arsinoitherium's flesh. You gained Disease resistance from the celestial arsinoitherium's flesh.` |

`prefix-devour-no-gain.txt` and `fixed-devour-gained-resistance.txt` are the
message screens dumped at the finish, one from each build.

The pre-fix run grants **zero** resistances. That is the load-bearing reading:
the fake monster is built from the base arsinoitherium plus the EATER's (empty)
template set, so it carries no celestial resistance to grant. Both announced
gains -- electricity and disease -- therefore come from the celestial *template*,
which only the fix applies. Acid and cold are not announced because a level-9
Dench already resists them and the code announces only newly gained resistances
(`src/Skills.cpp`, the `curr < lev` guard).

## Provenance

Upstream's. Pure logic -- no typedef, width, endianness or compiler dependence;
a Win32/MSVC build with the original typedefs reads `this` and drops the same
templates. The comment one line above the defect (`ww:`) states the intent the
code then fails to carry out. Tier: **Observed** (this A/B). Not sent.
