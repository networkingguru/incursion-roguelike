# TRUE_SIGHT: SRD parity — brief

Bead: `inc-5bl3`. Lane: `rules:` (a player feels the difference).
Attribution: **upstream**, not the port. Evidence tier of the defect: Traced.

This brief cites by SYMBOL, never by line number. A spec outlives the numbers,
and `tools/check_doc_citations.sh` resolves a bare `file:line` against
upstream/master, where these numbers do not exist at all.

## Goal

Make the `TRUE_SIGHT` stati do what the 3.5 SRD's True Seeing does, inside one
range, and stop it doing anything outside that range.

Brian ruled on 2026-09-18 that both halves are in scope, and confirmed the
shape on the same day: true sight sees through invisibility and through
darkness, in any lighting condition, **out to the limit of its range**.

## What the SRD says, and what it excludes

Confirmed against the 3.5 SRD text, two decisive clauses:

- "The range of true seeing conferred is 120 feet."
- "It does not negate concealment, including that caused by fog and the like."

Plus "sees through normal and magical darkness" and "sees invisible creatures
or objects normally", recorded on the bead on 2026-09-13.

At this codebase's scale of **10 feet per square** (`docs/REPORTING-GATE.md`
records the scale twice, for the Telepathy helm and the flame tongue), 120 feet
is **12 squares**.

Three things therefore DO NOT change, and a diff that touches them is wrong:

| Left alone | Why |
|---|---|
| `ObscureAt` / `ignoreObscure` | The SRD excludes concealment and fog. `ignoreObscure` stays driven by `NatureSight` alone. |
| `OpaqueAt` | "True seeing does not penetrate solid objects." No X-ray vision. |
| `SightRange` | True sight does not restore sight to the blind. `Map::MarkAsSeen`'s outer `if (SightRange)` gate stays, so a blind creature — `SightRange == 0`, set in `Creature::CalcValues` — is unaffected. |

## Where the range comes from

`Creature::TrueSightRange()` — new, returns squares, 0 when the creature has no
`TRUE_SIGHT` stati.

The stati's `Mag` carries the range. `Mag` defaults to `-1` in the
`GainPermStati` and `GainTempStati` declarations in `inc/Map.h`, and one
existing grantor passes `0` explicitly (the kuo-toa in `lib/mon2.irh`), so the
rule is:

    Mag > 0  ->  Mag squares
    Mag <= 0 ->  TRUE_SIGHT_RANGE (12), the SRD default

Take the LARGEST contribution when a creature carries more than one
`TRUE_SIGHT` stati — a racial one plus an item's. Do not use `GetStatiMag`,
which returns the FIRST match, not the largest; walk the stati with
`StatiIterNature` in one pass.

**No data file changes.** All six existing grantors — the `True Seeing` spell
in `lib/wspells.irh`, `lib/mon1.irh`, the kuo-toa in `lib/mon2.irh`,
`lib/mon4.irh`, the 8th-level grant in `lib/religion.irh`, the 7th-level grant
in `lib/prestige.irh` — keep working and get 12. A grantor that wants a longer
reach sets a positive `Mag`; that is the hook Asherath's crowning Eye
(`inc-pu6v.2`) will use.

**No new save field.** The range is derived from a stati that already
serialises. Do not add a `Creature` member and do not touch
`docs/SAVE-SCHEMA-SPEC.md`.

Cost: one stati walk per call site per call — NOT per cell. Cache it in a local
the way `Creature::Perceives` caches `HasStati(SEE_INVIS)`.

## Files touched

| File | Change |
|---|---|
| `inc/Creature.h` | Declare `TrueSightRange()` and `TrueSightProbe()`. Define `TRUE_SIGHT_RANGE` (12). |
| `src/Vision.cpp` | The helper, and the five behaviour sites below. |
| `src/Fight.cpp` | Range-check the miss-chance exemption in `Creature::Strike`. |
| `src/Main.cpp` | Call `TrueSightProbe()` beside the existing `QuietProbe` and `XPDrainProbe` calls. |
| `lib/wspells.irh` | True Seeing's `Desc` — add the darkness and range clauses. Prose only; do not touch `xval`, `Level`, flags. |
| `tools/check_true_sight.sh` | New check, `gate: live`. |
| `README.md` | One row for the new check, under "### The checks". |
| `docs/REPORTING-GATE.md` | One row in "Base-code bugs fixed locally". |

## The five behaviour sites in `src/Vision.cpp`

1. **`Creature::Perceives`, invisibility.** The `t_HasStati_INVIS` and
   `t_HasStati_INVIS_TO` tests gate on `HasStati_SEE_INVIS` alone. `Dist` is
   already in scope. Cache `TrueSightRange()` beside `HasStati_SEE_INVIS`, then
   treat the creature as seen when
   `HasStati_SEE_INVIS || (TrueRange && Dist <= TrueRange)`.

2. **`Creature::Perceives`, ordinary darkness.** The clause that strips
   `PER_VISUAL` when the target stands in an unlit square beyond
   `LightRange * 2` is the gate that hides an invisible creature in a dark
   room. It must not fire when `TrueRange && Dist <= TrueRange`.

3. **`Map::MarkAsSeen`.** Add a `TrueRange` parameter. Inside the existing
   `if (SightRange)` block, after the `dist > SightRange` return and **before**
   the shadow-range branch, add: when `TrueRange && dist <= TrueRange`, set
   `Mask = (VI_VISIBLE | VI_DEFINED) << (pn*4)`. Lighting is irrelevant there.
   It must precede the shadow-range branch, which otherwise ends the ray on an
   unlit cell.

4. **`CARE_ABOUT_SEEING`, and the two `ignoreDark` definitions in
   `Map::LineOfVisualSight` and `Map::VisionPath`.** Replace the hard-coded
   `const bool ignoreDark = false;` with an `int16` range taken from `c`. The
   macro has `sx, sy, cx, cy` in scope, so the dark test becomes
   distance-limited:

       (Here.Dark && !(ignoreDarkRange && dist(sx,sy,cx,cy) <= ignoreDarkRange))

   Leave the `ObscureAt` clause and the `OpaqueAt` clause exactly as they are.

5. **`Map::VisionThing`.** Compute the range once beside `SightRange` and pass
   it to `MarkAsSeen` and `VisionPath`. `Map::BlindsightVisionPath` and its
   `MarkAsSeen` call pass **0**: blindsight is not true sight.

## `Creature::Strike`, in `src/Fight.cpp`

`can_see_you` lists `TRUE_SIGHT` beside `SEE_INVIS` with no distance test, so
today the miss-chance benefit reaches any distance. Gate the `TRUE_SIGHT` term
alone on the victim being within `TrueSightRange()` squares, and compute it
INSIDE the `StatiIterNature(e.EVictim,MISS_CHANCE)` loop, not above it — a
melee attack against a victim with no `MISS_CHANCE` stati must not pay a stati
walk. Leave `SEE_INVIS`, `M_SEE_INVIS` and `ILLUMINATED` untouched.

If this site is left alone, combat and sight disagree again in the opposite
direction, which is the fault the bead exists to remove.

## The oracle

`Creature::TrueSightProbe()`, gated on `getenv("INCURSION_TRUESIGHT_PROBE")`,
modelled on `Registry::QuietProbe` and `Character::XPDrainProbe`, and called
from `src/Main.cpp` where a live player and a live map already exist. Report
through `Error()` so the lines land in `logs/errors.log`.

It must print, one `TRUESIGHT_PROBE:` line each:

1. the computed range for a player granted `TRUE_SIGHT` with no `SEE_INVIS`
   (expect 12);
2. `Perceives` on an invisible creature placed **inside** the range in a lit
   square — expect `PER_VISUAL` set;
3. the same, in an **unlit** square inside the range — expect `PER_VISUAL` set;
4. the same, in a square **outside** the range — expect `PER_VISUAL` clear;
5. a control with neither `TRUE_SIGHT` nor `SEE_INVIS` — expect `PER_VISUAL`
   clear.

`Creature::Perceives` returns nothing at all while `theGame->InPlay()` is
false, and the probe runs ahead of `Game::Play()` setting `PlayMode`. Borrow
play mode for the length of the probe and put it back.

`tools/check_true_sight.sh` drives one seeded `tools/headless.sh` run with
`INCURSION_TRUESIGHT_PROBE=1` and asserts all five lines. It MUST name
`INCURSION_OPTIONS` (`tools/headless.sh` exits 2 without it).

**Prove it red.** Revert each half in turn — the `Perceives` invisibility term,
then the `MarkAsSeen` branch — rebuild, and confirm the check fails on the
matching assertions. A check that cannot fail is not evidence
(`docs/VERIFICATION.md`).

## The observation

The lane is `rules:`, so a probe is not enough: Brian required a gameplay
before/after on 2026-09-18. `tools/keys/true-sight-observe.keys` stages it —
the standard orc mage, a jump to depth 2 because the arrival room is lit by
design, "Learn Any Spell" for True Seeing, a summoned sprite (natively
invisible) one square east, then `@dump` either side of the cast. Run the same
script on a pre-fix build and a post-fix build and compare the screens. Seed 1
is the one whose corridor is longer than the player's light radius, so it is
the only seed of those tried that shows the darkness half as well as the
invisibility half.

## Marking

Three obligations, all required:

1. An `upstream:` comment at the `src/Vision.cpp` fix site stating that the
   defect is upstream's **and why**, the evidence tier, the bead id `inc-5bl3`,
   and that it has **not** been sent.
2. A row in the "Base-code bugs fixed locally" table of
   `docs/REPORTING-GATE.md`.
3. `bd label add inc-5bl3 upstream` — the one people miss, and without it
   `tools/sync_issues.sh` refuses and the gate reports UNMEASURED.

## Phases

1. `TrueSightRange()` helper + `TRUE_SIGHT_RANGE`, no call sites yet. Builds.
2. The five `src/Vision.cpp` sites + `Creature::Strike`.
3. The probe and `tools/check_true_sight.sh`; prove red both ways, then green.
4. The observation, the `Desc`, the `upstream:` mark, the ledger row, the
   README row, the bead label.

## Test plan

- Adversarial: `TrueRange` 0 (no stati), `Mag` negative, `Mag` 0, `Mag` larger
  than `SightRange`, a blind creature with `TRUE_SIGHT`, a monster with
  `TRUE_SIGHT` (kuo-toa) as the perceiver, target at exactly `TrueRange` and at
  `TrueRange + 1`.
- Regression: `tools/check_distant_light_vision.sh` (the other `MarkAsSeen`
  behaviour), `tools/check_headless.sh`, `tools/check_upstream_marks.sh`,
  `tools/check_comment_budget.sh`, `tools/check_commit_lane.sh`.
- Live: one seeded `tools/headless.sh` run to confirm no crash and no new
  `logs/errors.log` noise.
