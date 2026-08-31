# Spec: one authoritative light model (inc-jcg4)

Status: APPROVED (Brian, 2026-08-31). Plan: 2026-08-31-unified-light-model-plan.md.
Tier: Medium (heavy). Related: inc-qvk9 (runtime tunables + asymptotic curve),
inc-nhrk (carried-light hide fix), inc-qw4d (distance-vision fix).

## Goal, in Brian's words

Stop having two light systems that disagree. One computed "lighting reality"
becomes the single source of truth, and vision, hiding, the hide-break
warnings, and the render all read it. Keep the legacy per-cell flags as
inputs, not as a second truth. The save format does not change.

## The two bugs this closes

Both found from `save/Dench.sav` (Goblin Caves depth 8, hiding in shadows at
(106,98), stepping E to a `.Bright` square).

- **Bug A -- eyes disagree with the rules.** A permanently torch-lit square
  reads `.Bright` (breaks Hide in Shadows, per the rules) yet the render draws
  it dark, because the render never reproduces that generation lighting.
- **Bug B -- the hide light-test is source-blind.** `Move.cpp:445` (warning)
  and `Move.cpp:1376` (reveal-on-move) test `BrightAt(x,y) || LightRange` --
  static/field light OR the player's OWN carried light. A square lit only by a
  DYNAMIC EXTERNAL source (magma, a wall torch's live light, another
  creature's torch) is `LightLitAt`=true but `BrightAt`=false, so the player
  stays hidden in plain light and gets no warning.

## Hard invariant: non-normal detection is untouched

This change is confined to NORMAL (light-based) vision and light-based hiding.
It MUST NOT alter, by even one cell, any of:

- infravision / heat sight (`InfraRange`, the infra fade in `PutGlyph`),
- blindsight / darkvision (`BlindsightVisionPath`, `BlindRange`),
- tremorsense / stonework sense (`TremorRange`, `CA_STONEWORK_SENSE`),
- scent and telepathy (`Creature::Perceives`, the `PER_*` flags),
- hiding in water (`HI_WATER`), which is terrain, not light.

These live on separate code paths already. The guard (below) proves it: a
blind/infra/scent character's vision and detection dumps are byte-identical
before and after, on the same seeds.

## Today's two representations

1. **Legacy per-cell flags.** `At(x,y).Lit`, `.Bright`, `.Dark`,
   `.isSkylight`, plus `FieldAt(FI_LIGHT/FI_DARKNESS)`. Written at generation
   (`MakeLev.cpp`: `LightPanel` places torches at `TORCH_DENSITY`; `isTorched`
   sets `.Lit`, and `.Bright` within 3 tiles of a torch in line of sight) and
   by spells. Serialized in v1 saves (`SaveV1.cpp:2487`). Read for "is it lit"
   by vision (`.Lit` at `Vision.cpp:44,59,729`) and hiding
   (`Map::BrightAt`, `inc/Inline.h:642`).
2. **Computed light map.** `src/Light.cpp` `SrcLit`/`Steady`/`Frame`,
   rebuilt every turn from SCANNED live sources: `ScanCreatures` (carried
   light), `ScanFields` (`FI_LIGHT`), `ScanTerrain` (`TF_LOCAL_LIGHT` magma
   r=2, `TF_TORCH` wall torch r=3), `ScanFog`, plus `SumSteady`'s `Skylight`
   ambient on `isSkylight` cells. `LightLitAt` reports `SrcLit >=
   LIGHT_SEE_MIN` (48/255). Read by the render, and since inc-qw4d/inc-nhrk
   partially by vision/hiding.

Why they diverge: `SumSteady` deliberately dropped an old `.Lit` ambient term
to avoid double-counting wall-torch sources (`Light.cpp:443`). So the map
expects every generation light to also be a scannable `TF_TORCH`/
`TF_LOCAL_LIGHT` source. Where a `.Bright` square has no such source, the map
draws it dark -- Bug A.

## The reader surface (the whole "load")

"Is this cell lit" is read in ~8 places, all in scope:

| Site | Today | Kind |
|---|---|---|
| `Vision.cpp:44` | `.Lit \|\| mLight \|\| LightLitAt` | normal vision (inc-qw4d) |
| `Vision.cpp:59` | `.Lit \|\| mLight \|\| LightLitAt` | normal vision (dim band) |
| `Vision.cpp:729` | `.Lit \|\| mLight` | can-a-creature-see (normal) |
| `Player.cpp:318` | `BrightAt \|\| LightRange` | auto-hide gate |
| `Monster.cpp:1502` | `BrightAt \|\| LightRange` | spawn auto-hide |
| `Skills.cpp:2806` | `BrightAt \|\| LightRange` | manual Hide |
| `Move.cpp:1376` | `BrightAt \|\| LightRange` | reveal-on-move |
| `Move.cpp:445` | `BrightAt` | move warning |
| `Fight.cpp:3551` | `inField(FI_LIGHT)` | light-averse to-hit penalty |
| `Fight.cpp:3557` | `inField(FI_LIGHT)` | light-averse defense penalty |
| `Status.cpp:1664` | `FI_LIGHT` field-entry event | light-averse "squint" message |

`.Bright` has zero direct reads outside `BrightAt`.

The three light-averse sites are the same disease as Bug B, one layer deeper.
Light aversion reads `inField(FI_LIGHT)` -- membership in a cast light FIELD
(`Light`, `Continual Flame`, a sunlight field) -- and nothing else. It never
reads `.Bright` or the light map. So a light-averse creature suffers ZERO
penalty when it stands beside the player's torch, in a wall-torch pool, on
magma, or inside a `.Bright` room -- every natural dungeon light source is
invisible to it. This misbehaves identically on Win32 (upstream never had a
unified light notion), so it is an upstream design gap, markable `upstream:`.

## Design: one predicate, legacy folded in as input

Introduce ONE authoritative query in `src/Light.cpp`, the single place that
answers how lit a cell is. It folds the legacy static flags in as inputs, so
there is no second truth and no per-caller `OR` to keep in sync.

```
uint8 LightLevelAt(Map*, x, y);   // 0..255, the authoritative brightness
bool  LightLitAt(x, y);           // LightLevelAt >= LIGHT_SEE_MIN  (vision floor)
bool  LightBrightAt(x, y);        // LightLevelAt >= LIGHT_HIDE_MIN (hide cutoff)
```

`LightLevelAt` = max over: the computed `SrcLit` at the cell; a contribution
for legacy static lighting (`.Bright`/`.Lit`) where NO live source already
covers the cell (this is the anti-double-count rule the old ambient lacked);
minus any `FI_DARKNESS`/`FI_SHADOW` field (which forces 0, matching
`BrightAt`'s darkness guard).

**Skylight contributes ZERO** (Brian, 2026-08-31). `isSkylight` is not open
sky: "Mark Skylights" (`MakeLev.cpp:2268-2288`) only runs at `Depth > 1` with
a level above, and marks a cell a skylight where the level ABOVE has a chasm
(`TF_FALL`) over it -- a shaft up to the next dungeon level, always
underground, never daylight. So the design DROPS the `Skylight = {170,185,210}`
ambient (`Light.cpp:436,442`) entirely: skylight cells feed nothing into
`LightLevelAt` and render dark like any other unlit cell. Untouched: the cyan
shaft glyph (`MakeLev.cpp:2283`), climbing (`Skills.cpp:3982,4007`), the
blind-render case (`Term.cpp:102`), the step-onto prompt (`Move.cpp:526`), and
the serialized `isSkylight` bit.

Two thresholds, because the rules let you hide in DIMLY lit tiles (Skulk) but
not brightly lit ones:

- `LIGHT_SEE_MIN` (48, existing) -- vision floor, unchanged.
- `LIGHT_HIDE_MIN` (NEW, **90**, Brian 2026-08-31) -- the "brightly lit" cutoff
  for breaking hide AND for light aversion. A knob for inc-qvk9's runtime
  tuning. Below it a cell is dim enough to hide in. Chosen by the single-torch
  falloff: a wall torch reads 255 / 191 / 96 / 34 at distance 0/1/2/3, a
  carried torch 255 / 196 / 107 / 50 / 18 at 0..4. 90 breaks hide (and bites a
  light-averse creature) out to two tiles from a torch; 128 would have reached
  only the ring you can touch.

### Repoint the readers

- The 5 hide sites: replace `BrightAt(x,y)` with `LightBrightAt(x,y)` (keep
  the `|| LightRange` carried-light term; that is the player's own light and
  is correct). Now every source -- static, field, carried, magma, external
  torch -- breaks hiding, and at the bright cutoff, not the dim floor.
- The 3 vision sites: already read `LightLitAt`; route them through the
  unified `LightLitAt` (same 48 floor, so normal vision is behaviourally
  unchanged except where the folded-in legacy light now correctly registers).
- The 3 light-averse sites: replace `inField(FI_LIGHT)` with
  `LightBrightAt(x,y)` at the SAME 90 cutoff as hiding (Brian: "if you can
  hide, no light adversity"). The two combat penalties (`Fight.cpp:3551/3557`)
  are a direct swap. The "squint" message (`Status.cpp:1664`) is today a
  one-shot fired on ENTERING an `FI_LIGHT` field; it must become a per-turn
  check ("am I standing in a bright cell this turn"), because ambient light has
  no field-entry event. Fire it once on the transition dim->bright, not every
  turn, to avoid message spam. The glowing-weapon `+2` (`Fight.cpp:3604`) is
  gated on the FLAG alone, not on ambient light -- leave it untouched.
- The render: it already reads the map. Because `LightLevelAt` folds in the
  legacy `.Bright`/`.Lit`, the render must paint those cells too -- so Bug A
  is fixed at the same place. Reconcile in `SumSteady`: add the legacy-static
  contribution to `Steady` ONLY where no source footprint already lit the
  cell, reinstating the dropped ambient without the double-count. In the SAME
  edit, DELETE the skylight ambient (`Light.cpp:436,442`) per the design above.

### Why the save format does not change

`.Lit`/`.Bright`/`.isSkylight` stay exactly as they are written and
serialized. They stop being a parallel READ-truth and become INPUTS to
`LightLevelAt`. Generation is unchanged. `SaveLayoutDigest` is unchanged, so
no save is orphaned.

### `BrightAt` itself

Keep `Map::BrightAt` as a thin alias that now calls `LightBrightAt`, so any
caller I have not enumerated still gets the unified answer. Verify the full
caller list first; if any caller wants the OLD static-only meaning (e.g. a
generation-time check that must not depend on live sources), give it a
separate explicitly-named accessor rather than silently changing it.

## Settled decisions (Brian, 2026-08-31)

- **Skylight = zero light.** RESOLVED, see the Design section: `isSkylight` is
  an underground chasm-shaft, never daylight; drop the ambient outright.
- **Sequencing: this unification (inc-jcg4) lands FIRST; the physical light
  rework (inc-qvk9) lands AFTER, as a swap behind the opaque `LightLevelAt`
  interface.** The readers compare a threshold and never see the accumulation
  math, so replacing today's max-of-sources + screen-blend with
  linear-additive accumulation + a single tone-map curve is a localized change
  with zero reader rework. Do NOT bake the 0..255 scale into any reader.

## Settled decisions (Brian, 2026-08-31), continued

- **`LIGHT_HIDE_MIN` = 90**, shared by hiding and light aversion. Provisional
  only in that inc-qvk9's additive/tone-map rework rescales the 0..255 axis
  later and makes this a live knob; the *rule* (dim-enough-to-hide ==
  dim-enough-not-to-suffer) is fixed.
- **Light aversion folds into the unified model**, at the same 90 cutoff. No
  separate `FI_LIGHT`-field path survives for it. This is a behaviour change:
  light-averse creatures now suffer near torches, lava, and the player's light,
  where before only a cast light spell bit them.

## Open items to settle in review

- None blocking. Values above are provisional against inc-qvk9's rescale only.

## Test / verification plan

- **Invariant guard (non-normal detection):** a blind character, an
  infravision-only character, and a scent/tremor character each play a fixed
  seed; their vision and detection dumps are byte-identical before and after.
  This is the hard gate on "must not modify non-normal detection".
- **Bug B, adversarial:** hidden character steps into a square lit only by
  (i) magma, (ii) an external creature's torch, (iii) a wall torch's live
  light. Each must now warn and reveal; pre-fix does neither. A/B on the fix
  commit, like `tools/check_distant_light_vision.sh`.
- **Bug A:** the Dench repro -- the `.Bright` square renders lit after, dark
  before; the warning still fires (unchanged, correct).
- **Dim vs bright:** a character in a dim torch-edge tile (level in
  [`LIGHT_SEE_MIN`, `LIGHT_HIDE_MIN`)) can still hide; one cell brighter cannot.
- **Light aversion, folded in:** a light-averse creature standing near a wall
  torch / on magma / beside the player's light now takes the -4 combat penalty
  and gets the squint message; pre-fix it took neither. A dim-tile (48..90)
  light-averse creature takes NO penalty (mirrors the hide test). The squint
  message fires once on dim->bright, not every turn.
- **No-regression:** `nightly_verify --compare`, and the existing
  `check_lightmap.sh` / `check_hide_carried_light.sh` stay green.
- **Upstream marking:** the hide-gate changes extend the inc-nhrk markers;
  add rows/marks per the gate.

## Rough size

Medium-heavy build: one new predicate + the `SumSteady` reconciliation
(~1 file), repoint 11 sites (5 hide, 3 vision, 3 light-averse), the render
fold-in, one new tunable, and the guard + three behavioural checks. The
light-averse squint message is the one non-mechanical change (field-entry event
-> per-turn dim->bright transition). The risk is concentrated in `SumSteady`'s
anti-double-count rule and in proving the non-normal-detection invariant, not
in the repointing.
