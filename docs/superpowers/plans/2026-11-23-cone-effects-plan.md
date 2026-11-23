# Cone effects (inc-epzc0) — implementation brief

**Goal.** Effects the game calls cones strike a real d20 cone, play the band-by-band wave that balls play, and light as balls light.
**Spec.** The bead's description and notes (`bd show inc-epzc0`): the geometry paragraph, eight acceptance criteria, and the rulings of 2026-11-06, 2026-11-21 and 2026-11-23.
**Base.** master at 67f83f85 (inc-az4d2 ball volume and wave, inc-jw0hw effect light, both landed).
**Implementer.** Coding: `sonnet` while `tools/claude_budget.py` says `sonnet-first` (it did on 2026-11-23), else the coding row of `always-implement-via-codex`. Check design: Codex.

## Design

**Volume.** A cone's length is the effect's `lval` in squares. Its volume is the count of squares (dx,dy), not the source, with `4(dx²+dy²) ≤ (2·lval+1)²` (the ball's disc test) whose angle from the aim line is at most 45°. Enlarge Spell doubles the volume and Focus Spell divides it by 3. The result then snaps to the nearest cone count at a whole length, as `BallVolume` snaps to a disc (tie takes the larger).

**Aim.** The aim line runs from the source to the target square. An `isDir` effect aims at source + 8·(DirX,DirY). The 45° test uses the true angle, so a cone can aim between the eight directions.

**Fill.** One best-first flood from the source over open squares, the way `BallFill` floods (`src/Magic.cpp:3915`). It uses the same 8 neighbors, the same wall and F_SOLID stop, and records the same kind 1/2 squares. The priority key is (outside the cone, d²): every reachable in-cone square is taken before any outside square. It takes whole key-shells while they fit the count, then stops. On open floor this gives exactly the cone. Where walls cut the cone short, the leftover volume flows to the nearest open squares outside it, back past the source and onto the source square itself, so a cone fired down a hallway can strike its caster. Band = `BallBand` (rounded distance from the source). The output is the same `vector<BallSquare>` sorted by band, so the ball's wave, strike and light loop runs unchanged.

**Breath shape.** A new monster constant, `BREATH_SHAPE` (first breath, A_BREA) and `BREATH2_SHAPE` (second, A_BRE2), in the `const_id internal` family next to `DRAGON_FEAR_DC` (`inc/Defines.h:4310`). Value `AR_CONE` makes that breath a cone. An absent constant leaves it a line (`AR_BREATH`, a beam). Spits (A_SPIT) never read it and stay lines. `src/Fight.cpp:3751` sets the breath effect's `aval` from it. The half-red dragon template must reach the constant too; the implementer confirms how a template's constants resolve and reports.

## Files

| File | Change |
|---|---|
| `src/Magic.cpp`, `inc/Magic.h` | `ConeVolume`, `ConeFill` beside `BallVolume`/`BallFill`. `ABallBeamBolt` (`:4095`): an AR_CONE branch that takes the ball path with `ConeFill` (wave, `MagicXY`, ADD_TARGET, `EffectLight` EL_AREA, `FlashStruck` EL_AREA). Add AR_CONE to the dispatch switch (`:1847-1855`), the line-of-fire exemption list (`:416-422`) and the monster prediction (`:5029`, which must equal the strike). |
| `src/Fight.cpp` | Breath `aval` from `BREATH_SHAPE`/`BREATH2_SHAPE` (`:3751`). AR_CONE in the AI area-clipping list (`:8185`). |
| `src/Effects.cpp` | A cone case in the blast message switch (`:341-386`). |
| `inc/Defines.h`, `inc/ConstNam.h` | `BREATH_SHAPE`, `BREATH2_SHAPE` constants and their names. |
| `lib/wspells.irh` | Cone of Cold (`:7890`), Fear (`:6268`), Shout and its rider (`:~6383`) to AR_CONE. |
| `lib/m_items.irh` | Ice;wand (`:1899`), horn of Blasting and its rider (`:6467`) to AR_CONE. |
| `lib/alchemy.irh` | Dragon tattoo (`:2681`) to AR_CONE. |
| `lib/mon1.irh`, `lib/mon3.irh`, `lib/mon4.irh` | `BREATH_SHAPE`/`BREATH2_SHAPE AR_CONE` on every cone breath in the bead's 2026-11-23 notes (SRD cones; non-SRD named cones; the 15 unnamed non-spit breaths). Brass dragon blast names to "line of fire" / "cone of sleep gas"; water mephit to "cone of water". |
| `src/ConeShapeProbe.cpp`, `tools/check_cone_shape.sh`, `tools/keys/cone-shape.keys` | New check, modeled on `tools/check_ball_shape.sh` and `src/BallShapeProbe.cpp`. |
| `tools/check_effect_light.sh`, `src/EffectLightProbe.cpp` | One lit cone case. |
| `tools/probe_names.txt`, `tools/README.md` | The new probe name and check. |

## Phases (one commit each)

1. **Geometry.** `ConeVolume` and `ConeFill`, with no caller yet. Implement; verify with a probe self-test that prints the open-floor cone for lengths 1–8 in the 8 directions and one off-axis aim, and the hallway fill for length 6.
2. **Strike and draw.** The AR_CONE branch in `ABallBeamBolt`, the switch, the line-of-fire list, the prediction, the AI clipping list and the message. Convert Cone of Cold only. Verify by casting it headless with the ball probe hooks: the struck set equals `ConeFill`, and the bands grow one per frame.
3. **Breaths.** The two constants, the `Fight.cpp` read, every breath's data, and the two renames. Verify with the probe: a gold dragon's fire breath is a cone, a blue dragon's is a beam with its jagged path, and a spit is a beam.
4. **The other cone effects.** Fear, Shout, Ice;wand, Blasting and the Dragon tattoo. Verify each strikes a cone.
5. **Check.** `tools/check_cone_shape.sh` (Codex designs it, sonnet builds it). It is described under Tests.
6. **Light.** The cone case in `tools/check_effect_light.sh`. `tools/check_effect_light_table.sh` stays green with no row changed (Cone of Cold, Shout and Blasting stay unlit).

## Tests

- **`tools/check_cone_shape.sh`** loads a fixture (`INCURSION_LOAD`) and builds its own map in the probe, so it reads no seed. It has these cases:
  - **Open floor.** It fires a cone at a known group. It fails if a creature inside the quarter circle is missed, if one outside is struck, or if the struck count is not the volume.
  - **Hallway.** It fails unless the struck count equals the open-floor volume and the caster is struck.
  - **Wall.** It fails if a square behind a wall is struck.
  - **Off-axis aim.** It fails unless the cone centers on the target.
  - **Wave.** It fails unless the bands grow one per frame, in 70 ms steps, with a 300 ms hold.
  - **Prediction.** It fails unless the monster prediction equals the strike.
  - **Breaths.** It fails unless one cone breath is a cone and one line breath and one spit are beams.
  - **Red/green.** Each case must go red under a planted mutation: drop the outside-cone overflow, widen the angle to 60°, and draw all bands in one frame.
- **Light.** The `check_effect_light.sh` cone case: a lit cone lights to 2 squares past its edge, with fire flicker. An unlit cone (Cone of Cold) adds no light.
- **Console build.** The check runs on the posix build. One SDL rendered reel (`tools/render_effect_reel.sh`) of a red dragon's breath gives the before/after observation.
- **Gate.** `tools/nightly_verify.sh --compare` through `tools/finish_bead.sh`. A death-count shift is expected, because cones strike more creatures; per-seed evidence goes in the commit if the baseline is re-recorded.

## Acceptance criteria → evidence

| AC | Evidence |
|---|---|
| AC1 AR_CONE implemented | check: open floor, wall and hallway cases |
| AC2 every cone effect converted, line breaths beam | check: breath case; the diff of the phase 3–4 data |
| AC3 allies and caster struck | check: open-floor group with an ally; hallway case |
| AC4 wave covers exactly the struck squares | check: wave case |
| AC5 SDL and console | posix check run; SDL reel |
| AC6 god effects | no god effect has a cone shape today (no AR_BEAM god effect's text says cone); state it, with the grep |
| AC7 headless check | `tools/check_cone_shape.sh` green, plus its red/green pairs |
| AC8 light | `check_effect_light.sh` cone case; table check unchanged |
