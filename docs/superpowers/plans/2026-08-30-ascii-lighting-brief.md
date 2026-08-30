<!-- citations: this-port -->

# Coloured, shimmering light on the ASCII map — spec and plan (brief)

**Sized:** Medium. **Status:** approved 2026-08-30; phases 1-3 committed, phase 4 tuning waits on Brian's eye. **Branch:** `lighting`, worktree `.claude/worktrees/lighting` (another session held master).

**Goal.** The SDL build lights the map the way Brogue does: every light source on
the level casts its own colour, light fades with distance, is stopped by walls,
and flickers continuously at about 30 frames per second while the game waits
for a key. The map stays ASCII. Game rules do not change. The headless and
curses builds draw exactly what they draw today.

**Architecture.** One runtime light map (RGB per cell) in a new file, rebuilt
once per turn from the level's sources and re-evaluated with noise once per
frame. `PutGlyph` multiplies each visible cell's 16-colour base by its light
and hands a true-colour pair to one new backend call. The libtcod backend draws
it and keeps a per-cell buffer so an idle tick can re-light the map without
touching game state. Every other backend ignores the RGB and draws the 16-colour
glyph it draws today.

**Stack.** C++17, libtcod (vendored, SDL2), bash checks. No new dependency.

**Reads first.** `docs/VERIFICATION.md`; the digest rule in
`docs/superpowers/plans/2026-08-24-save-schema-v1.md` §Global Constraints 5.

## Spec

### S1. Scope line: visual only

- Visibility, `MarkAsSeen` (`src/Vision.cpp:36`), perception (`src/Vision.cpp:715`)
  and every game rule stay untouched. The light map never feeds a rule.
- Only `WIN_MAP` gets RGB. Message window, sidebar, menus stay 16-colour.
- Cells that are remembered but not visible keep today's dimming
  (`FloorShading` memory branch, `src/Term.cpp:1201-1211`). No light on them.
- `Dark` cells stay blank as today (`src/Term.cpp:1192`).

### S2. Where the light map lives

- New `src/Light.cpp` + `inc/Light.h`. File-scope object, not a `Map` member:
  `Map`, `Term` and `LocationInfo` are in `SaveLayoutDigest()`
  (`src/AbiCheck.cpp:151-161`); a new member there orphans every save.
- Keyed by the displayed map's handle and size. Rebuilt when the map shown by
  `T1->getMap()` changes, when its size differs, or when the turn advances.
- Must compile in the posix build: no libtcod or SDL types in it. Own
  `struct LightRGB { uint8 r,g,b; }`.

### S3. Sources, per turn

| Source | Found by | Radius | Colour | Flicker |
|---|---|---|---|---|
| Creature with a light | `Creature::LightRange` field (`inc/Creature.h:230`), set at `src/Values.cpp:1565-1569` | its `LightRange`, capped at 12 (`src/Effects.cpp:58` sets 100 for an effect) | kind table (S5) | torch high, lantern low, glowing weapon none |
| Magical light field | `Fields` with `FI_LIGHT` (`inc/Map.h:235`, `inc/Defines.h:3449`) | `Field.rad` | `Field.Color` → palette RGB | low |
| Local-light terrain | cells whose terrain has `TF_LOCAL_LIGHT` (magma, brimstone: `lib/dungeon.irh:1908,1992`) | 2 | terrain glyph foreground → palette RGB | high |
| Lit room | `LocationInfo.Lit` (`src/MakeLev.cpp:155-163`) | flat ambient on the cell | neutral warm white, low intensity | none |
| Skylight | `LocationInfo.isSkylight` | flat ambient on the cell | pale blue-white | none |

Each source records a **footprint**: the list of `(cell index, weight)` it
reaches. Weight = `1 - (d / (r + 1))^2`, clamped to `[0,1]`, Brogue's curve.
A cell enters the footprint only if `Map::LineOfVisualSight` from the source
reaches it, so light stops at walls. Cost per turn is sources × (2r+1)² × one
ray, well under the vision pass the game already runs.

### S4. Per frame

- `LightTick(ms)` advances one smooth noise value per flickering source:
  `1 + A·(0.6·sin(ω₁t+φ₁) + 0.4·sin(ω₂t+φ₂))`, `A` from the kind table.
- `LightAt(idx, out)` sums, per channel, every footprint weight × source
  colour × its noise, plus the cell's ambient, clamped to 255.
- The tick never reads game objects. It reads only the footprints built in S3.

### S5. Colour of a source (the `ponytail:` decision)

Default: the source's own glyph foreground, through the backend palette. A
small code table in `Light.cpp` overrides by kind: torch `(255,147,41)`,
brass lantern `(255,214,150)`, glowing weapon `(150,180,255)`, magma
`(255,80,20)`. `ponytail:` the upgrade path is a `Light Colour:` field in the
`.irh` grammar (`lang/Grammar.acc:598`), which needs the generated parser
rebuilt; not in this plan.

### S6. Compositing

- For a visible map cell: `fg = palette[fg16] × (floor + L)`, same for `bg`,
  where `floor` = 0.35 keeps every glyph readable outside any light and `L` is
  S4's value scaled to `[0,1]`. Clamp to 255.
- `FloorShading` still runs first and still produces the 16-colour fallback
  glyph. That glyph is what non-RGB backends draw, unchanged.
- The `F_HILIGHT` back-colour (`src/Term.cpp:828`), field overlay
  (`src/Term.cpp:1248`) and the fg==bg fixup (`src/Term.cpp:868`) apply before
  lighting, so they keep their meaning.

### S7. Backend contract

- `Term` gains one virtual:
  `void APutCharRGB(int16 x, int16 y, Glyph g, LightRGB fg, LightRGB bg)`.
  Default body in `TextTerm`: `APutChar(x, y, g)`. `Wposix.cpp` and
  `Wcurses.cpp` are not edited.
- `libtcodTerm` overrides it: `TCOD_console_put_char_ex(bScreen, x, y, ch, fg, bg)`
  (today's call is `src/Wlibtcod.cpp:1002`), and records into a new per-cell
  buffer `{ Glyph g; LightRGB fgBase, bgBase; int32 lightIdx; bool lit; }`.
- Any plain `APutChar` to a cell clears its `lit` flag, so a menu or prompt
  drawn over the map is never re-lit. `Save()`/`Restore()`
  (`src/Wlibtcod.cpp:976-984`) save and restore the flag buffer beside `bSave`.
- A window or font change (`src/Wlibtcod.cpp:1271-1286`) reallocates the buffer.

### S8. The tick

- In `GetCharRaw`'s idle branch (`src/Wlibtcod.cpp:1652-1664`): when shimmer is
  on and `Mode == MO_PLAY`, every `LIGHT_TICK_MS` (33) call `LightTick`, re-put
  every cell with `lit` set, then one `TCOD_console_flush`. This replaces the
  300 ms `IDLE_REPAINT_MS` repaint while shimmer is on; that branch and its
  `ponytail:` stay for the other modes.
- The idle sleep (`src/Wlibtcod.cpp:1682-1686`) is capped to the next tick.
- `StopWatch` (`src/Wlibtcod.cpp:1057`) sleeps in ≤33 ms slices and ticks
  between them, so spell and missile animations keep shimmering.
- The Windows `readkey` branch (`src/Wlibtcod.cpp:729-731`) gets the polling
  loop macOS already uses (`:721-727`). The two fatal-error prompts
  (`:1114`, `:1170`) stay blocking; they cover the map with a box.

### S9. Option

`OPT_ANIMATION` (`src/Tables.cpp:2349`): Normal and Player → shimmer;
Fast → steady coloured light, per turn only; None → legacy 16-colour path,
no RGB call at all. No new option, so `Player` (in the digest) is untouched.

### S10. Out of scope

Fonts, per-cell texture and wall glyphs: bead inc-tyud, its own brief after
phase 2 is visible. Tiles, light in the overview map, light on the
sidebar, sound. Lighting that changes what the player can see.

## Files touched

| File | Change |
|---|---|
| `inc/Light.h`, `src/Light.cpp` (new) | S2–S5: light map, sources, footprints, noise, kind table, `INCURSION_LIGHT_PROBE` dump |
| `inc/Term.h` | S7: `APutCharRGB` virtual with default body |
| `src/Term.cpp` | `ShowMap` calls `LightRebuild` (`:940`); `PutGlyph` (`:1239`) composes S6 and calls `APutCharRGB` |
| `src/Wlibtcod.cpp` | S7 override and cell buffer; S8 tick, sleep cap, `StopWatch` slicing, Windows `readkey`; S9 switch |
| `tools/check_lightmap.sh` (new) | the runnable check: seeded headless run with the probe, asserts light near the torch and none behind a wall |
| `docs/ENGINE-MAP.md` | one section: the light map is runtime state outside `Map`, and why |
| `tools/README.md` | the new check in §7 Tier 3 |

Not touched: `Wposix.cpp`, `Wcurses.cpp`, any `.irh`, the grammar, save code,
`Values.cpp`, `Vision.cpp`.

## Phases, one commit each

1. **Light model, no drawing.** `Light.cpp` builds sources and footprints each
   turn from `ShowMap`; `INCURSION_LIGHT_PROBE=1` dumps the map as text to
   `logs/light.log`. `tools/check_lightmap.sh` proves a torch lights its
   neighbourhood and nothing behind a wall. Headless output unchanged
   (`nightly_verify --compare` clean). Verify `tools/check_abi.sh`: stamp unchanged.
2. **Steady coloured light in the SDL build.** `APutCharRGB`, the libtcod
   override and buffer, S6 in `PutGlyph`, S9 switch. Brian sees torch, lantern,
   Light spell and magma in colour. `None` shows today's screen, pixel for pixel.
3. **Shimmer.** S8: the tick, sleep cap, `StopWatch` slicing, Save/Restore of
   flags, Windows `readkey`. Measure CPU at idle for 30 s with `top` and record
   it in the commit message.
4. **Tuning and docs.** Kind-table colours and amplitudes by eye with Brian,
   `ponytail:` comment, `docs/ENGINE-MAP.md`, `tools/README.md`.

## Test plan

- **Adversarial.** Level change mid-tick; font or window change reallocates the
  buffer; source at the map edge; `LightRange` 100 is capped; a creature and a
  field on one cell; inventory open over the map is not re-lit; Save/Restore
  round trip keeps the flags; a map smaller than the window; `Mode != MO_PLAY`.
- **User.** Carry a torch, drop it, pick a lantern, read a Light scroll, stand
  by magma, open a menu, cast a bolt (StopWatch). Each `OPT_ANIMATION` value.
- **Live.** `BACKEND=posix ./build_macos.sh`, `tools/nightly_verify.sh --compare`
  (must show no change), `tools/check_lightmap.sh`, `tools/check_abi.sh`,
  `tools/check_comment_budget.sh`, Tier 1 checks; then `./build_macos.sh` and a
  play session with the SDL binary.
- **Note for the dimming hunt.** `tools/flickerscan.py` measures window
  luminance over time. Run it with Animation = None while shimmer exists, or
  the shimmer swamps the signal it looks for.
