# Brief plan: unified light model (inc-jcg4)

Implementer: **Codex.** This session (Claude) reviews and fixes; it does not
author the implementation. Spec: `2026-08-31-unified-light-model.md` (read it —
this plan does not repeat the rationale, the bug descriptions, or the settled
decisions). Tier: Medium (heavy). One commit per phase.

## Goal / architecture / stack

One authoritative brightness query, `LightLevelAt(x,y) -> 0..255`, in
`src/Light.cpp`, becomes the single truth. Vision, the 5 hide gates, the 3
light-averse sites, and the render all read it. Legacy `.Lit`/`.Bright` and
`FI_LIGHT` fields become INPUTS, not parallel truths. Save format unchanged.
C++03, the existing SDL + `BACKEND=posix` headless builds.

Two accumulators already exist and must not be conflated:
- **`SrcLit[idx]`** (`Light.cpp:477`) — scalar 0..255, the max STEADY footprint
  weight over ALL sources, torches included (torches flicker, so they are in
  `Frame` not `Steady`, but their steady weight is still in `SrcLit`). This is
  the predicate's base. A scalar `max` cannot double-count.
- **`Steady`/`Frame`** (colored RGB, `SumSteady`/`ComposeFrame`) — the render.
  Additive, so folding legacy in here DOES need an anti-double-count guard.

## Files touched

| File | Change | Spec § |
|---|---|---|
| `inc/Light.h` | Add `LIGHT_HIDE_MIN 90`; add legacy-static level constants (`LIGHT_LEGACY_BRIGHT`, `LIGHT_LEGACY_LIT`); declare `LightLevelAt`, `LightBrightAt`. | Design; thresholds |
| `src/Light.cpp` | Implement `LightLevelAt` = `max(SrcLit, legacyLevel)` minus darkness; `LightBrightAt` = `>=LIGHT_HIDE_MIN`; route existing `LightLitAt` through `LightLevelAt`. In `SumSteady`: DELETE the `Skylight` ambient, ADD a legacy-static colored contribution ONLY where `SrcLit[idx]==0`. | Design; render fold-in; skylight=0 |
| `inc/Inline.h` | `Map::BrightAt` becomes a thin alias to `LightBrightAt` WHEN `lmMap==this`; else keep the old static-only body (off-map / light map not built for this map). Keeps the darkness/shadow guard. | BrightAt itself |
| `src/Vision.cpp` | `:729` add `\|\| LightLitAt(x,y)` so can-a-creature-see reads the unified answer; `:44`,`:59` already do. | Repoint readers |
| `src/Fight.cpp` | `:3551`,`:3557` — `inField(FI_LIGHT)` -> `LightBrightAt(x,y)`. Leave `:3604` glowing-weapon `+2` (flag-gated, not ambient). | Light-averse |
| `src/Status.cpp` | `:1664` squint message: convert from `FI_LIGHT` field-entry event to a per-turn dim->bright transition. See Phase 4. | Light-averse |
| `docs/REPORTING-GATE.md` | Rows for the Bug-B hide-gate extension and the light-averse fold-in (both `upstream:`). | Upstream marking |

The 5 hide gates (`Player.cpp:318`, `Monster.cpp:1502`, `Skills.cpp:2806`,
`Move.cpp:1376`, `Move.cpp:445`) are repointed CENTRALLY: they call
`m->BrightAt`, which now returns the unified answer. Do NOT edit each site;
verify each still wants unified + keeps its `|| LightRange` carried-light term.

## The legacy-static level mapping

`legacyLevel(x,y)`: `.Bright` -> a value clearly `>= LIGHT_HIDE_MIN` (propose
**160**, breaks hide, renders lit); `.Lit` but not `.Bright` -> a value in
`[LIGHT_SEE_MIN, LIGHT_HIDE_MIN)` (propose **64**, visible, still hideable);
neither -> 0. Both are provisional knobs (inc-qvk9). The darkness guard
(`FI_DARKNESS`/`FI_SHADOW` present, no covering `FI_LIGHT`) forces the final
level to 0, matching today's `BrightAt`.

## Phases (one commit each)

1. **Predicate + constants.** Add the constants and the three functions;
   route `LightLitAt` through `LightLevelAt`; make `BrightAt` the guarded alias.
   No render change yet. VERIFY: both builds compile; `check_lightmap.sh` green;
   add one assert-based check that the torch falloff (255/191/96/34) crosses
   `LIGHT_HIDE_MIN` between d=1 and d=2.
2. **Repoint hide + vision readers (no render).** `Vision.cpp:729`; the 5 hide
   gates via the central `BrightAt` alias (verify, don't per-site edit).
   VERIFY: `check_hide_carried_light.sh` green; Bug-B behavioral check (hidden
   char steps into magma-/external-torch-/wall-torch-lit cell -> warns and
   reveals), A/B on this commit.
3. **Light aversion — penalty AND its message together.** They MUST land in one
   commit so the mechanic and its feedback never disagree. (a) `Fight.cpp:3551/
   3557` — `inField(FI_LIGHT)` -> `LightBrightAt(x,y)`; the combat log already
   self-labels " -4 light". (b) `Status.cpp:1664` squint: the penalty's ambient
   tell outside combat. Replace the `FI_LIGHT`-entry trigger with a per-turn
   edge detector — each creature turn read `LightBrightAt` at its cell, emit the
   line once on the dim->bright transition, not every turn. Mechanism: a
   transient bit on the creature (stati or bool member) holding last turn's
   bright state; Codex proposes the exact hook + storage in review, Claude
   checks no spam and no save-format touch. Both read the SAME 90 cutoff.
   VERIFY: a light-averse creature by a wall torch takes -4 AND squints once on
   entry; two dim tiles out it takes neither; stationary in light does not spam.
4. **Render fold-in + skylight delete.** `SumSteady`: delete `Skylight`, add
   the legacy colored contribution where `SrcLit[idx]==0` (pick a warm dim
   ambient, e.g. a dimmed wall-torch hue — a tuning knob, flag it for Brian's
   eye). VERIFY: Dench Bug-A repro renders the `.Bright` square LIT; warning
   still fires; `nightly_verify --compare` no new failures.
5. **Guard + marks + gate rows.** The non-normal-detection invariant guard
   (Phase-0 baseline vs post: blind / infra / scent-tremor dumps byte-identical
   on fixed seeds). Add the `upstream:` marks at each fix site and the
   `REPORTING-GATE.md` rows. VERIFY: `check_upstream_marks.sh`,
   `check_ledger_rows.sh` green.

## Test plan

- **Adversarial:** Bug B three ways (magma / external creature torch / wall
  torch); dim-vs-bright boundary exactly at 90 (level 89 hides, 91 breaks);
  `FI_DARKNESS` over a lit cell forces unlit; `BrightAt` on a map the light
  map was NOT built for returns the old static-only answer (no stale read).
- **User:** the Dench repro — `.Bright` square renders lit after / dark before,
  warning fires both. Light-averse creature beside a wall torch takes -4 and
  squints; the same creature two dim tiles further out takes neither.
- **Live / regression:** `tools/headless.sh tools/keys/dive.keys`;
  `nightly_verify --compare`; `check_lightmap.sh`, `check_hide_carried_light.sh`,
  `check_distant_light_vision.sh` all green.
- **Invariant guard (hard gate):** blind, infravision-only, and scent/tremor
  characters — vision + detection dumps byte-identical before and after.

## Review / integration

Codex commits per phase. Claude reviews each phase's diff (correctness +
the anti-double-count rule + the invariant), applies fixes directly, and runs
the checks. `/code-review` at the end if Brian asks. No push without Brian's go.
