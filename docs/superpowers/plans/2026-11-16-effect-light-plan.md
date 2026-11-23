# Effect Light Implementation Plan (inc-jw0hw)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Implementers also obey AGENTS.md "If you are the implementer".

**Goal:** Every visible magical effect lights its surroundings with the color, timing, flicker and reach the bead's design names. One unattended command renders a video of every effect, with the light off and on side by side.

**Architecture:** The light map (`src/Light.cpp`) gets a new kind of source, the *flash*. Spell code adds a flash, changes its level and removes it while the animation runs, then calls `T1->ShowMap()` to rebuild the light and vision. Aura fields become light sources in `ScanFields`. The SDL backend draws a pixel circle for each aura in its post-render callback. It also gets a frame recorder that runs on virtual time, so the effect reel renders without a window and faster than real time.

**Tech Stack:** C++ (engine, libtcod/SDL2 backend, posix backend), bash, Python 3, ffmpeg (`/opt/homebrew/bin/ffmpeg`).

**Spec:** bead `inc-jw0hw`, description section `## Design` and `## Acceptance Criteria` (`bd show inc-jw0hw`). Rulings and their wording are in the bead notes.

## Global Constraints

- Build only with `BACKEND=posix ./build_macos.sh` (headless) and `./build_macos.sh` (SDL). Run the game only through `tools/headless.sh`; the SDL build through it with `INCURSION_BIN=./incursion`.
- Every harness run names `INCURSION_OPTIONS`.
- The light state stays file-static in `src/Light.cpp`. Add no member to `Map`, `Term` or `LocationInfo` (they are in `SaveLayoutDigest()`, `src/AbiCheck.cpp`).
- `src/Light.cpp` includes no backend header; the posix build compiles it.
- A new `INCURSION_*` name gets a row in `tools/probe_names.txt` naming inc-jw0hw.
- A new `#define` family or enum carries a `// family: <name> internal` line.
- A new or changed `tools/check_*` file carries `# fact: <fact> -- <control>` lines for every fact it reads (`docs/VERIFICATION.md`).
- A comment block in `src/`/`inc/` stays at 30 lines or fewer. Mark a deliberate corner cut with a `ponytail:` comment naming its ceiling.
- American spelling in prose and comments (identifiers such as `GlyphColour` stay).
- Commit lane: `graphics:` for every source task, `tools:` for tool-only tasks.
- Colors (RGB): Fire 255,140,40; Cold 170,210,255; Electricity 210,225,255; Light 255,250,235; Silvery 220,225,240; Magic 210,190,255; Necromantic 140,100,180; Poison 170,210,90; Acid 120,230,100; Disintegration 80,240,160; Petrification 200,180,140; Polymorph 240,130,220; Sonic 200,200,200 at faint gain; Rainbow cycles pale hues. A plain palette color (0..15) is lightened halfway to white.
- Timing: ball ring lights as drawn (70 ms per ring); the hold stays 300 ms at full level; the fade takes 250 ms. Beam: each square rises to full in 60 ms as the beam reaches it; after the beam is drawn, it fades in 100 ms. Missile: one point at steady level, no trail; after impact, it fades in 250 ms.
- Reach: balls, bursts, globes, cones 2 squares past the edge; beams 1; missiles 1; auras 1. Aura level is half a blast's.
- Flicker: fire flickers and electricity flashes on balls, bursts, globes and cones only. Beams, missiles and auras do not take damage-type flicker; auras keep the gentle field flicker.
- The flash is real light: while a flash is on, the vision test counts it, so the player sees what it lights and map memory records it. A fade changes only the drawn color, never vision.
- A flash is added only on a square the player has line of sight to (`PossiblyPause`'s test, `src/Magic.cpp:1706`).
- Cones are out of this plan: no cone code exists, and inc-epzc0 builds cone light with `EffectLight` (`EL_AREA`).
- With `OPT_ANIMATION` None, the light map is in legacy mode; flashes then add nothing. This is the existing contract of that option.

## Review Focus

1. **A big ball (the Hellstorm, lval 8) costs too much.** One flash per struck square, with radius 2, is about 200 sources. Expected: the animation still runs at its 70 ms ring rate in the SDL build. Test: Task 4 times a Hellstorm with the frame recorder and fails if one `ShowMap` takes over 20 ms.
2. **Vision rebuilt mid-animation fires game events** (a monster seen, an interrupt, a "you see" message) in the middle of a spell. Expected: no message appears mid-animation that would not appear after it. Test: Task 4 compares the message log of a Fireball cast in a dark room, flash on against flash off; only the order may differ, never the set.
3. **An effect off the player's sight.** Expected: no flash, no change to any square the player can see. Test: Task 8 case C (the boxed-in player from `tools/check_ball_shape.sh`).
4. **A flash left behind** by an early exit of `ABallBeamBolt` (bolt with no victim, self target, engulfed, remote trap) or by a spell that kills the caster. Expected: no flash survives the function. Test: Task 5 fires a bolt with no victim and an engulfed cast, and checks the light dump after for zero flash sources.
5. **The reel misses an effect kind.** Expected: the reel's list covers every `EA_BLAST`, `AR_GLOBE` and aura-field effect in `lib/program.i`. Test: Task 9 counts them independently with grep and fails on a mismatch.

---

### Task 1: Spike — the SDL build renders a frame with no window

The video requirement depends on this. If it fails, stop and report; do not work around it.

**Files:**
- Create: `tools/spike_offscreen_shot.sh` (deleted again in Task 2 if Task 2 absorbs it; otherwise kept as the record)

- [ ] **Step 1:** Run the SDL build through the harness with `SDL_VIDEODRIVER=offscreen`, `INCURSION_BIN=./incursion`, the fixture and key script of `tools/keys/inc-moh9-darkvision-scene.keys` (it already ends in `@shot`).
- [ ] **Step 2:** Pass if the run writes a non-black bitmap of the full window size and no window appears (`osascript` window list of process `incursion` is empty during the run). Report the driver used and the bitmap path. If `offscreen` fails, try `SDL_VIDEODRIVER=dummy`; report both.

### Task 2: Frame recorder on virtual time

**Files:**
- Modify: `src/Wlibtcod.cpp` (`SleepTicking` ~1254, `LightFrame` ~1238, the `SK_SHOT` branch ~2006)
- Create: `tools/frames_to_video.sh`
- Modify: `tools/probe_names.txt`

**Interfaces:**
- Produces: env `INCURSION_FRAMES=<dir>`. While set, `SleepTicking(ms)` does not sleep. It advances a virtual clock in steps of 33 ms. At EVERY step, whether or not `LightFrame` fires (it never fires in Fast mode), it calls `LightTick(virtual)`, repaints every lit cell, flushes, and saves the frame as `<dir>/<clip>/f<NNNNN>.bmp`. `<clip>` is `default` until `FrameClip(const char *name)` (declared in `inc/Term.h` as a free function, no-op in posix) names a new one.
- Every read of the clock in `src/Wlibtcod.cpp` goes through one function, `static uint32 NowMs()`, which returns the virtual clock while recording and `TCOD_sys_elapsed_milli()` otherwise: `GetElapsedMilli()`, the `ticks_light_last` seed (~1231), `SleepTicking` (~1255, ~1263), the script pause and the main loop (~2001, ~2033, ~2071-2073).
- Produces: `tools/frames_to_video.sh <clipdir> <out.mp4>` (ffmpeg, 30 fps, H.264, yuv420p) and `--pair <offdir> <ondir> <out.mp4>` (ffmpeg `hstack`, labels "light off" / "light on").

- [ ] **Step 1: Failing check** `tools/check_frame_recorder.sh`: runs the Task 1 scene plus one cast of Fireball (reuse the cast keys of `tools/keys/ball-shape.keys` or a probe call, whichever Task 1 proved works) with `INCURSION_FRAMES` set; asserts frame count is between 0.9× and 1.1× of (ring count × 70 + 300) / 33, with the ring count read from the `BallRingHook` lines of the same run, not assumed. No wall-time assertion (load changes it). Header: `# fact: ring count -- read from the run's own BallRingHook lines`, `# fact: character -- fixture xsummon-priest-seed5-opt0822`, `# fact: settings -- options-2026-08-22.dat; OPT_ANIMATION forced Normal by the probe`.
- [ ] **Step 2:** Run it; expect FAIL (no frames).
- [ ] **Step 3:** Implement the recorder as above. The virtual clock is a file-static `uint32` in `src/Wlibtcod.cpp`.
- [ ] **Step 4:** Run it; expect PASS. Mutation: make `SleepTicking` skip the save; expect FAIL.
- [ ] **Step 5:** Commit (`graphics:`, because it changes the backend).

### Task 3: Flash sources and effect colors in the light map

**Files:**
- Modify: `inc/Light.h`, `src/Light.cpp` (`KindTable` ~30, `LightSource` ~47, `LightRebuild` ~679, `LightTick` ~742, `ComposeFrame` ~661, `ProbeDump` ~819)

**Interfaces (Produces):**
```cpp
// family: light-flash-style internal
enum { LF_STEADY = 0, LF_FIRE = 1, LF_ARC = 2, LF_RAINBOW = 3 };
LightRGB LightEffectColour(int16 blastColour);   // COL_FIRE..COL_SILVERY or a palette index 0..15
// One flash = one lit AREA: the effect's own squares plus a spill of `reach`.
int32 LightFlashAdd(LightRGB c, uint8 style, float gain, int16 reach);  // returns an id >= 0, empty area
void  LightFlashCell(int32 id, int16 x, int16 y);   // adds one effect square to the area
void  LightFlashMoveTo(int32 id, int16 x, int16 y); // the area becomes this one square (missiles)
void  LightFlashLevel(int32 id, float level);       // 0..1; render only; calls ComposeFrame itself
void  LightFlashRemove(int32 id);
void  LightFlashClearAll();
int32 LightFlashCount();
bool  LightFlashDisabled();                         // INCURSION_EFFECT_LIGHT_OFF is set
```
- Flashes live in their own file-static list, outside `Src`, and survive `LightRebuild`. `LightRebuild` casts each live flash after `ScanFields` as kind `LK_FLASH`, with its own footprint: every effect square at weight `gain`; every open cell within `reach` of the nearest effect square at the existing falloff (`RawFall`, windowed as in `CastFootprint`) times `gain`, if `Reaches` from that nearest effect square. A cell takes the MAX over the area, not a sum, so a big ball keeps its color and dims with distance instead of saturating to white. One footprint per flash, not one source per square (review: about 200 sources for the Hellstorm).
- Flashes take their own render path, never the steady one: `SumSteady` skips `LK_FLASH`; `ComposeFrame` adds each flash scaled by `level × noise`; `anyFlicker` is true while any flash is live, so `LightTick` runs. `FoldSrcLit` counts a flash at full weight whatever its level, so a fade never changes vision.
- `LF_FIRE`: amp 0.45, freq 11 Hz, 4 octaves, bias 0.6. `LF_ARC`: the level steps at random between 1.0 and 0.5 at 15 Hz (a hashed step, not smooth noise). `LF_RAINBOW`: hue cycles with a 2 s period at saturation 0.35, full value. `LF_STEADY`: amp 0.
- `LightEffectColour` returns the Global Constraints table; a palette index returns `Palette[i]` lightened halfway to white. Sonic's faint gain is the caller's (Task 4/5 pass gain 0.6 for COL_SONIC).
- `ProbeDump` writes one `F <id> <ncells> <reach> <style> <level>` line per live flash.
- `LightFlashAdd` returns -1 and adds nothing when `LightFlashDisabled()`; the other calls ignore id -1.
- This task also creates the check's skeleton (moved here from Task 8, so every later task can run red first): `src/EffectLightProbe.cpp` (modeled on `src/BallShapeProbe.cpp`, call site in `Game::Play` beside it, env `INCURSION_EFFECT_LIGHT_PROBE`), `tools/check_effect_light.sh` and `tools/keys/effect-light.keys`, with the fact header listed in Task 8. Later tasks add cases.

- [ ] **Step 1: Failing check** case A: the probe adds one fire flash with one cell at a known open square in its dark map, sets `p->UpdateMap = 1`, calls `ShowMap`. The dump MUST show the `F` line; the cell MUST be lit, `LightLitAt` true and in the player's `Visibility`; its color MUST keep the Fire hue (red ≥ green ≥ blue, and green/red within 0.15 of 140/255). At `LightFlashLevel(id, 0.3)` the frame light MUST drop and `LightLitAt` MUST stay true. After `LightFlashRemove`, `UpdateMap`, `ShowMap`, the cell MUST be unlit again.
- [ ] **Step 2:** Run; expect FAIL.
- [ ] **Step 3:** Implement the interface above.
- [ ] **Step 4:** Run; expect PASS. Mutation: drop the flash scan from `LightRebuild`; expect FAIL.
- [ ] **Step 5:** Commit.

### Task 4: Balls, bursts and globe flashes light

**Files:**
- Create: `src/EffectLight.cpp`, `inc/EffectLight.h` (one helper, used by Tasks 4 and 5)
- Modify: `src/Magic.cpp` (`ABallBeamBolt` ball fill ~2756-2815 and its exits; `AGlobe` ~1771-1806), the build file list in `build_macos.sh` if sources are listed there

**Interfaces (Produces):**
```cpp
// A struct, not a class with virtuals: one per animation, on the stack.
struct EffectLight {
  EffectLight(Map *m, int16 blastColour, uint8 shape);   // one flash, reach and style from shape
  ~EffectLight();                // backstop for early exits: calls End() if not yet ended
  void Light(int16 x, int16 y);  // LightFlashCell, only if the player has LOS to (x,y)
  void MoveTo(int16 x, int16 y); // missile: LightFlashMoveTo, only if LOS; else the flash empties
  void Refresh();                // p->UpdateMap = 1; T1->ShowMap()  (light, vision, memory, overlay)
  void Hold(int16 ms);           // EffectLightHook(EL_HOLD); T1->StopWatch(ms)
  void Ramp(int16 ms, float from, float to);  // level steps through T1->StopWatch(33) slices;
                                              // always ends with the level exactly `to` (posix waits 0)
  void End();                    // remove the flash, Refresh(), EffectLightHook(EL_END)
};
// family: effect-light-phase internal
enum { EL_LIT = 0, EL_HOLD = 1, EL_END = 2 };
// Test hook, NULL unless the probe sets it; called at EL_LIT after each Refresh().
extern void (*EffectLightHook)(int phase);
// family: effect-light-shape internal
enum { EL_AREA = 0, EL_BEAM = 1, EL_MISSILE = 2 };
```
- Style: `EL_AREA` takes `LF_FIRE` for COL_FIRE/RED-fire sets, `LF_ARC` for COL_ELEC, `LF_RAINBOW` for COL_RAINBOW, else `LF_STEADY`. Other shapes take `LF_STEADY`, except `LF_RAINBOW` keeps its hue cycle.
- **The light ends before any hit is resolved.** Vision (`src/Vision.cpp:48, 63, 943`) and hiding (`src/HideCheck.cpp:36`) read the light map, and the hits (`src/Magic.cpp:2818-2850`) call `Perceives`. So `End()` runs explicitly before the hits; a hit never sees a flash. The destructor only covers early exits (Review Focus 4). This also keeps the reel's off and on runs identical in everything but the light.
- Ball: `Light()` each square drawn in a ring, `Refresh()` after each ring, before its existing `StopWatch(70)`; `Hold(300)` replaces the existing `StopWatch(300)`. Then `o.DeActivate()` and `T1->ShowMap()` so the glyphs go, then `Ramp(250, 1, 0)`, then `End()`, then the hits. The overlay is not re-activated for the hits.
- Globe (`AGlobe`, highlight drawn by direct `PutGlyph`, `src/Magic.cpp:1792-1806`): `Light()` every square and `Refresh()` BEFORE the `PutGlyph` loop, because `ShowMap` repaints every cell and would wipe the highlight. Keep the existing pause. Then the existing `RefreshMap()` (the highlight goes), `Ramp(250, 1, 0)`, `End()`, then the hits.
- `CalcVision` mid-spell: Step 4 MUST show it adds no message and no interrupt (Review Focus 2).

- [ ] **Step 1: Failing check** `tools/check_effect_light.sh` case B: Fireball in the dark probe map. At the `EL_HOLD` hook, every struck square and every open square within 2 of the area that has LOS from the nearest struck square MUST be lit and in `Visibility`; the center keeps the Fire hue (as case A); the edge of the reach is dimmer than the center. At the `EL_END` hook, and again after the function returns, the light dump MUST equal the dump from before the cast, and `LightFlashCount()` MUST be 0. Sample only at hooks, never by elapsed time (posix `StopWatch` waits 0, `src/Wposix.cpp:803`).
- [ ] **Step 2:** Run; expect FAIL.
- [ ] **Step 3:** Implement `EffectLight` and wire balls, bursts and globes.
- [ ] **Step 4:** Run; expect PASS. Run `tools/check_ball_shape.sh`; it MUST still pass unchanged. Time a Hellstorm under the frame recorder (Review Focus 1) and compare the message sets (Review Focus 2).
- [ ] **Step 5:** Commit.

### Task 5: Beams, breaths, chains, bolts, rays and ranged touches light

**Files:**
- Modify: `src/Magic.cpp` (travel loop ~2509-2682, chain ~2685-2748, early exits ~2331-2478)

- Beam, `AR_BREATH`, `AR_CHAIN`: `EL_BEAM`. Each square is added at full level when drawn, and `Refresh()` runs before its existing `PossiblyPause(…,35)`; the beam's growth is its travel, one square per 35 ms. No per-square ramp (60 ms cannot fit in a 35 ms step, and an extra wait per square would slow every beam). After the travel ends: `Hold` for the existing end pause, overlay off, `Ramp(100, 1, 0)`, `End()`, then the hits.
- `AR_BOLT`, `AR_RAY`, `MM_PROJECT` ranged touch: `EL_MISSILE`. One flash, reach 1, `MoveTo` each square, `Refresh()` before each existing pause; no trail. At impact: overlay off, `Ramp(250, 1, 0)`, `End()`, then the hit.
- `End()` before the hits holds here too (Task 4). A chain's next leg starts a new `EffectLight`.
- The travel loop calls `MagicXY` on each square while the flash is on (`src/Magic.cpp:2563-2569`). Step 4 MUST show `MagicXY` reads no light (grep its callees for `LightLitAt`, `LightLevelAt`, `Perceives`); if one does, report it and stop.
- Glyph drawing does not change (a ray keeps its beam glyphs).

- [ ] **Step 1: Failing check** case D (beam: Lightning Bolt lights its line ±1 while it shows, gone after) and case E (Acid Arrow: during flight, at most 9 lit cells around one point; after, none), and case F (bolt with no victim and an engulfed cast leave `LightFlashCount()==0`).
- [ ] **Step 2:** Run; expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run; expect PASS.
- [ ] **Step 5:** Commit.

### Task 6: Aura fields light

**Files:**
- Modify: `src/Light.cpp` (`ScanFields` ~528, `KindTable`)

- A field with `FI_MODIFIER` or `FI_BLOCKER` and not `FI_LIGHT` becomes a source of new kind `LK_AURA`: radius `f->rad + 1`, gain 0.5, the `LK_FIELD` flicker row, color its glyph color lightened halfway to white (`LightEffectColour` on its palette index). `FI_LIGHT` fields stay `LK_FIELD`, unchanged.

- [ ] **Step 1: Failing check** case G: a Minor Globe of Invulnerability field on the probe map lights its area +1 at a level between `LIGHT_SEE_MIN` and 0.6 × a Fireball's center level; after the field is removed, unlit.
- [ ] **Step 2:** Run; expect FAIL. **Step 3:** Implement. **Step 4:** PASS; mutation: drop `FI_BLOCKER` from the test; a Magic Circle case goes red. **Step 5:** Commit.

### Task 7: The aura circle in the SDL build

**Files:**
- Modify: `src/Wlibtcod.cpp` (`LogoRenderCB` ~143, made a general post-render callback; `LightFrame`)
- Modify: `inc/Light.h`, `src/Light.cpp`: `int32 LightAuraCount(); bool LightAuraAt(int32 i, int16 &cx, int16 &cy, int16 &rad, LightRGB &c, float &noise);`

- The circles draw before `LogoRenderCB`'s `if (!g_logo || !screen) return;` (`src/Wlibtcod.cpp:145`), which would otherwise skip them whenever no logo is loaded.
- After the console renders, for each aura: draw a circle of radius `(rad + 0.5)` cells in pixels, centered on the center of its cell, 2 px wide, at the aura color × noise, alpha-blended; fill the inside with the same color at alpha 0.12. Draw a pixel only inside a cell the player sees now (the cell's `Visibility` from the map; the Term must not cache it). Walls the player sees take the circle; cells behind them do not.
- In `LIGHT_SHIMMER` mode the circle redraws with each `LightFrame`; dirty the cells it covers so libtcod repaints them before the next draw.

- [ ] **Step 1:** Frame-recorder clip of the Task 6 scene, before and after. **Step 2:** Implement. **Step 3:** Clip shows a sharp circle, cut at cells out of sight; a mutation that skips the visibility test draws into a dark cell and the clip's pixel probe (a Python reader of the BMP at a known out-of-sight pixel) goes red. **Step 4:** Commit.

### Task 8: The headless check, whole

**Files:**
- Modify: `src/EffectLightProbe.cpp`, `tools/check_effect_light.sh` (created in Task 3; cases A, B, D-G added by Tasks 3-6): add case C and the final wiring.
- Modify: `tools/probe_names.txt` (`INCURSION_EFFECT_LIGHT_PROBE`, `INCURSION_EFFECT_LIGHT_OFF`, `INCURSION_FRAMES`), `tools/README.md` §7 row

The check plan, in the order `check-plan-purpose-method-changes` requires:
1. **What it should do:** fire one effect of each shape where the player watches, and confirm the light shows on the effect's squares and their reach while the effect shows, and is gone when it ends; and confirm an effect out of sight adds no light.
2. **Why it does not today:** it does not exist; no effect adds light.
3. **How:** the probe builds a dark room, casts Fireball (case B), Lightning Bolt (D), Acid Arrow (E), a no-victim bolt and an engulfed cast (F), a Minor Globe field (G), and Fireball with the player boxed in (C, from `check_ball_shape.sh`). It samples the light at the hooks the effect already has (`BallRingHook`, plus a new `EffectLightHook(int phase)` called by `EffectLight` at light, hold, fade-end). The script grades `EFFECT_LIGHT` lines.
4. **Holes:** none known. Facts and controls:
   - `# fact: character -- fixture xsummon-priest-seed5-opt0822`
   - `# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS; the probe forces OPT_ANIMATION Normal`
   - `# fact: terrain and darkness -- the probe builds the map and clears legacy Lit/Bright`
   - `# fact: monsters -- placed by the probe at fixed offsets`
   - `# fact: effect radii and colors -- read from the data by the probe (TEFF lval, cval)`
   - `# fact: which squares are struck -- no roll decides them (as check_ball_shape.sh)`
   - `# fact: player's sight in case C -- the probe makes the player's eight neighbors opaque`

- [ ] Steps: write the probe and script, run red before Tasks 3-6 land (each case red against master), green after; mutation per case named in its task. Commit (`tools:`).

### Task 9: The effect reel

**Files:**
- Create: `src/EffectReelProbe.cpp` (call site in `Game::Play`), `tools/render_effect_reel.sh`, `tools/check_effect_reel_list.sh`
- Modify: `tools/probe_names.txt` (`INCURSION_EFFECT_REEL`), `tools/README.md`

- With `INCURSION_EFFECT_REEL=1`, the probe enumerates every effect in the loaded module that is `EA_BLAST` (every `aval`), `AR_GLOBE`, or `AR_FIELD`/`AR_MFIELD` whose `rval` has `FI_MODIFIER` or `FI_BLOCKER`, plus "Breath Weapon" once per damage type any monster breathes. For each, it rebuilds the dark room with three targets, calls `FrameClip("<rID>-<name>")`, casts it from the player at a fixed target, and for an aura lets 2 s of virtual time pass. It writes `REEL <n> <name> <kind>` lines.
- `tools/render_effect_reel.sh [--only <name>...]`: runs the SDL build offscreen (Task 1's driver) twice through `tools/headless.sh`, once with `INCURSION_EFFECT_LIGHT_OFF=1`, each with `INCURSION_FRAMES` set; then `tools/frames_to_video.sh --pair` per clip into `logs/effect-reel/<date>/<clip>.mp4`, plus one `index.html` that lists the clips with a `<video>` per clip. It prints the count, wall time and output path.
- `tools/check_effect_reel_list.sh`: counts the same effects in `lib/program.i` by grep and fails when the probe's `REEL` count differs (Review Focus 5). Header: `# fact: the effect list -- read from lib/program.i at run time, and from the loaded module by the probe; no fixed number`, `# fact: character -- fixture xsummon-priest-seed5-opt0822`, `# fact: settings -- options-2026-08-22.dat`. Its red is the probe skipping one kind (drop `AR_GLOBE` from the probe's filter).

- [ ] Steps: list check red first (no probe), then green; render the reel; confirm every clip has frames and both halves differ in at least one pixel where an effect shows light. Commit (`tools:`).

### Task 10: Review by Brian, and the console build

- [ ] Claude watches a sample of the reel (Fireball, Cone of Cold as a beam, Lightning Bolt, Acid Arrow, Disintegrate, a breath, Sleep, Minor Globe), then sends Brian `logs/effect-reel/<date>/index.html`.
- [ ] Console build: the probe's case B under the posix build shows the struck squares and their reach visible (`EFFECT_LIGHT` vision lines), which is all its light model shows. This is the console acceptance criterion.
- [ ] Land per `commit-means-land-the-bead`, with one `AC<n>:` line per acceptance criterion.

## Acceptance criteria → tasks

| AC | Task |
|---|---|
| AC1 each kind lights as designed | 3, 4, 5, 6, 7 |
| AC2 light gone after | 4, 5, 6, 8 |
| AC3 unseen adds none | 8 case C |
| AC4 video reel of every effect | 1, 2, 9, 10 |
| AC5 console build | 10 |
| AC6 headless check | 8 |
