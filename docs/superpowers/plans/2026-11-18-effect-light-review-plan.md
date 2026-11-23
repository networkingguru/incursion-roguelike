<!-- citations: this-port -->
# Effect Light, Review Pass — Implementation Plan (inc-jw0hw)

Sized: Large. This plan follows `2026-11-16-effect-light-plan.md` (the first pass, committed as f9cabe0d and b93cdba9). It builds what Brian ruled while he reviewed the first reel, 2026-11-17 and 2026-11-18. Every ruling, with its wording, is in the bead notes (`bd show inc-jw0hw`, NOTES). Where this plan and a note disagree, the note wins; stop and report the conflict.

**Goal:** Each visible magical effect lights only when it is luminous, in the color of what it is. Its light and glyphs cool from near white to dark on each square's own clock. Every creature an energy effect hits flashes at the end. Fireworks, lightning, color patterns and a few named effects get their own animations. Auras show as unlit colored circles. The reel shows every one of these, so Brian can review it instead of playing.

**Implementer:** `tools/claude_budget.py` said `sonnet-first` on 2026-11-18, so every coding phase goes to `sonnet` (`budget:` label). Run the budget check again before each dispatch; on `normal`, the coding row's order applies (DeepSeek first, phases split to ~40 steps).

## Global Constraints

Every constraint in the first plan's "Global Constraints" still binds. In addition:

- An effect's Desc is the main source of truth for whether it glows and in what color (ruling 2026-11-18). The bead notes hold the decision for every reel clip.
- Glow classes: energy glows (fire, cold energy, electricity, light, magic, necromantic, holy/law/chaos, disintegration). Material (acid, poison, gas, ice or snow as an object, sand, mud, blood, webs, plants, water, stone) does not glow. Force, sonic, wind and mental effects do not glow. An effect whose Desc names no light and no visible energy does not glow.
- An unlit effect still draws its glyphs exactly as today.
- Dark energy (necromantic, unholy) skips the white stage of the ramp: full color, fading to black.
- Commit lanes: `graphics:` for renderer and animation, `data:` for a corrected `lib/*.irh` value, `tools:` for the reel and checks. A new `EF_*` value follows `.claude/rules/engine-data-knowledge.md` `shared-numbers-take-a-name-or-a-frozen-value`.

## Files touched

| File | Change |
|---|---|
| `src/EffectLight.cpp`, `inc/EffectLight.h` | The glow decision (Phase 1), the cooling ramp (Phase 2), the target flash (Phase 3). |
| `src/Light.cpp`, `inc/Light.h` | Per-square age on a flash cell, so each square cools on its own clock; aura sources leave the light map (Phase 5). |
| `src/Magic.cpp` | Area, beam, bolt and chain paths call the new ramp and target flash; the special animations (Phase 4). |
| `src/Fight.cpp` | The touch flash, where a touch lands: around `ReThrow(EV_MAGIC_STRIKE, e)` at ~7392-7410, and the second `TOUCH_ATTACK` site at ~3276 (Phase 3). |
| `inc/Defines.h`, `inc/ConstNam.h`, `inc/Res.h`, `lib/*.irh` | Two new effect flags and their names, `EF_LAST` raised; corrected `cval` values (Phase 1). |
| The engine's script-function table and dispatch | One new script-callable light function (Phase 4). |
| `lib/wspells.irh` (Burning Hands ~1065, Skull Trap ~5174-5208), `lib/mon4.irh` (Dance of Ruin ~627, Nightmare smite ~1171) | Calls to the script light (Phase 4). |
| `src/Wlibtcod.cpp`, `src/Tables.cpp`, `inc/Defines.h` | Unlit aura circle and tint, additive overlap; the show/hide option (Phase 5). |
| `src/EffectReelProbe.cpp`, `tools/render_effect_reel.sh` | Reel fixes (Phase 6). |
| `tools/fixtures/effect-light-table.tsv` (new, written by Claude) | The expected glow decision and color class for every reel effect, from the bead notes. |
| `tools/check_effect_light_table.sh` (new), `tools/check_effect_light.sh` | Checks (Phases 1–5). |

## Phases

One commit each. Each phase states what it builds and how it is verified.

**Phase 0 — Merge master.** Implement: `git merge master` into branch `inc-jw0hw` (Claude runs this; it is a git state change). Verify: both builds pass; `tools/check_effect_light.sh`, `check_ball_shape.sh`, `check_lightmap.sh`, `check_aura_circle.sh`, `check_frame_recorder.sh` still pass.

**Phase 1 — The glow decision.** Implement: one function decides, per effect, LIT or UNLIT and the light color. `tools/fixtures/effect-light-table.tsv` decides every effect; the default and the data exceptions MUST reproduce each of its rows. Default by damage type, per the glow classes above. Exceptions in data: a flag that forces a glow on a non-energy type (Dehydration wand, Faerie Fire, eggshell flash-bomb, Hypnotic Pattern, Colour Spray, Chromatic Orb, Pyrotechnics;flash, Nightmare smite, Dance of Ruin, Call Lightning, Circlet of Blasting), and a flag that forbids one on an energy type (Icelance, Ice Dagger, Snowstrike, Cone of Cold, the Shards wand, Bodak Death Gaze, Revenance, Consecrate, Desecrate, and every other row the table marks unlit against its type). A `COL_*` set in `cval` beats the damage type (the Void: necromantic over cold). A plain `cval` gives the light color when the type has none (Dehydration: BROWN lightened to amber). Correct `cval` where the light color must change and no set exists: Scare to `COL_NECRO`, Dance of Ruin a dark red, Circlet of Blasting a warm sunlight yellow, Sanguine Touch crimson. Claude writes the table from the bead notes before the dispatch. Flags: `TEffect::EFlags` is sized by `EF_LAST` (`inc/Res.h:499`, `inc/Defines.h:3739`), so `EF_LAST` rises past the new flags; each new flag gets a name in `inc/ConstNam.h` so `lib/*.irh` can name it. Pick the numbers per `shared-numbers-take-a-name-or-a-frozen-value`: classify the block with a `// family:` line, then run `tools/check_define_dups.py`, `tools/check_stored_values.py` and, on a collision, `python3 tools/move_branch_values.py`. Verify: `tools/check_effect_light_table.sh` computes the decision for every effect in the reel list and compares it with `tools/fixtures/effect-light-table.tsv`. It must go red twice: with one table row flipped, and with one exception branch (a flag test or the `COL_*` precedence) removed from the decision function.

**Phase 2 — The cooling ramp.** Implement: each lit square stores the time it lit. Its light and its glyph color move along the energy's ramp by that square's age: near white, then the energy's colors, then dark (fire: white, yellow, orange, red; dark energy: no white stage). About 900 ms per square, as in `logs/ramp-mock/fire-ramp.mp4` (right panel, the ruled one). Glyphs ramp too. The rainbow ramp cools each square through its own hue. This replaces the first pass's whole-area hold and fade. The clock lives in `src/Light.cpp`: a flash cell (`FlashCell`, ~83, today `{x, y}`) gains the time it lit; `CastAreaFootprint` (~540-581) and `TickFlashes` (~884) take each cell's color and level from its own age, read from `GetElapsedMilli`; a spill cell takes the stage of the nearest lit square. `EffectLight` only adds cells with a timestamp; the blocking `EffectLight::Ramp` loop (`src/EffectLight.cpp` ~96-105) no longer drives the level. Verify: a headless probe case samples one square's light at three ages and fails unless the color moves toward the ramp's next stage and the level falls; red with the age ignored.

**Phase 3 — Target flash and touch flash.** Implement: an energy effect ends by flashing every creature it hit, in its ramp and flicker. A touch spell flashes its target when the touch lands in melee. `Magic::ATouch` (`src/Magic.cpp:6806`) only charges the hand; the touch lands in `Creature::Attack` (`src/Fight.cpp` ~7392-7410), so the flash goes around its `ReThrow(EV_MAGIC_STRIKE, e)`, and at the second `TOUCH_ATTACK` site (~3276). Call Lightning has no stroke: only this flash. Verify: probe cases for a Fireball with two kobolds (both squares flash after the rings) and a landed Chill Touch (target square flashes, necromantic, no white); red with the flash call removed.

**Phase 4 — Special animations.** Implement each as its own sub-commit:
- Fireworks (Pyrotechnics;flash): the center grows through a dot, a star and a flower shape, then fades. Each further ring starts when the ring inside it reaches the star, with shapes pointing away from the center. Glyphs are shapes, not fixed characters; choose the best fit from the font.
- Lightning meander (Lightning Bolt, Chain Lightning, lightning breath): the path is straight only where no other path exists. Between targets it leaves the line by up to one square and returns to strike each target; random per cast.
- Color patterns (Hypnotic Pattern, Colour Spray, Chromatic Orb): random glyphs in random colors, redrawn about every 100 ms while the effect shows; each square's light follows its current color.
- Burning Hands: a new script-callable light function (registered in the engine's script-function table) so its three script-drawn glyphs glow on the fire ramp (`lib/wspells.irh` ~1065-1075, drawn with `HIT_SPOT`). Skull Trap, Dance of Ruin and Nightmare smite use the same function where their light comes from script.
- Skull Trap: the skull's square glows a dim red rising in brightness from wake to explosion; the explosion uses the fire ramp.
- Dance of Ruin: glyphs fall onto each square in dark red; dark ramp.
- Nightmare smite: changing rainbow glyphs and light on the demon's square and its neighbors through the two-turn gather; the explosion uses the rainbow ramp.
- Faerie Fire: each creature hit glows for the duration in the color its message names (silver, violet, amber, azure, crimson), gently flickering, on its own square at half a blast's level (the first pass's aura level), moving with it.

Verify: one reel clip per item, rendered and inspected by Claude frame by frame before Brian sees it; a headless probe case for the meander (no step leaves the line by more than one square; every target square is struck) and for Faerie Fire (the glow moves with the creature and ends with the effect).

**Phase 5 — Unlit auras.** Implement: an aura adds no light. Keep the `LK_AURA` source that `ScanFields` (`src/Light.cpp` ~632-644) adds, because the circle reads it through `LightAuraCount`/`LightAuraAt` (~948-966); skip only its light footprint (the `CastAreaFootprint` call at ~810-811). The show/hide option is a new `OPT_*`: a `#define` in `inc/Defines.h` and a row in `src/Tables.cpp` (~2610), appended after every existing option so no option byte moves; `tools/fixtures/options-*.dat` and `tools/gates/Options.Dat` must still pass their checksums unchanged. In the SDL build it shows as the sharp pixel circle at its radius in its glyph color (neutral gray when it has none), with a faint see-through tint inside, only over squares the player sees. Overlapping tints add. A new option shows or hides auras; default shown. The console build shows no aura. Verify: `tools/check_aura_circle.sh` updated: the circle is the aura's color, the interior tint is present, a dark square inside the aura stays dark (no light), two overlapping auras sum; red with the light source restored.

**Phase 6 — Reel fixes.** Implement: a caster-centered globe (`EF_DEFENSIVE`, e.g. Electric Loop) targets the caster; directional spells aim at the target (EDir set); touch spells land the touch; Pyrotechnics gives the target a lit torch and renders each of its three forms; an `EF_ACTIVATE` effect runs as an activation (Circlet of Blasting, Madness horn; `src/Magic.cpp:932`), and Dragonshield is rechecked after that fix; each special animation has its own clip. The b93cdba9 reel change may already cover activation; confirm before rebuilding it. Verify: `tools/check_effect_reel_list.sh` still counts every effect; the table gains a `shows_nothing` column (the effects ruled to show nothing), and the reel fails on any clip whose frames are all identical unless its row says so.

**Phase 7 — Full reel and gate.** Render the full reel. Claude checks a frame sample of every clip against the table before Brian sees it. Then Brian reviews the reel. The landing gate runs at `tools/finish_bead.sh`.

## Acceptance criteria, mapped

- AC1 (each kind lights with its design's color, brightness, duration, flicker): Phases 1–4, `check_effect_light_table.sh`, probe cases, Brian's reel review.
- AC2 (light goes away when the effect ends): Phase 2 probe (level reaches zero), existing `check_effect_light.sh` end cases.
- AC3 (an unseen effect adds no visible light): existing case C, kept green through every phase.
- AC4 (unattended reel of every effect, off/on side by side, virtual time): Phases 6–7.
- AC5 (the console build shows what its model can show): Phase 5 (no aura), Phases 2–3 (lit squares become visible).
- AC6 (a headless check fires an effect and fails if its light is missing or stays): `check_effect_light.sh`, extended in Phases 2–3.

## Test plan

- Adversarial: a ramp on a square that leaves sight mid-ramp; a meander next to walls (no step into rock); a chain with one target; overlapping auras of the same color; Faerie Fire on a creature that dies or teleports; the show/hide option toggled while an aura shows. `OPT_ANIMATION` None: the probes force it to 0 (`src/EffectLightProbe.cpp` ~349), so Phase 2 adds one probe case with it set to 2 that fails unless `LightFlashCount()==0` after a Fireball and the run ends cleanly.
- User path: the full reel, SDL build, every clip, by Brian.
- Live data: one headless dive (`tools/keys/dive.keys`, the fixture options) per phase, compared with the gate baseline for new engine errors.
