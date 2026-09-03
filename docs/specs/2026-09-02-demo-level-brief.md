# Build brief: lighting-showcase demo content (inc-wefr item 2)

**For:** Codex (`codex exec -C /Users/brianhill/Scripts/Incursion -s workspace-write - < brief`).
Codex authors the `.irh` content and builds/loads it in the headless sandbox to
prove it parses and generates. Codex MUST NOT commit and MUST NOT run the SDL
binary (`./incursion`). The Claude session reviews each phase's diff, runs the
SDL build outside the sandbox, and does the wizard-mode navigate-and-save that
produces the trailer save.

**This is a spec, not approval to build.** Nothing here goes to Codex until
Brian reads this file and says go.

## Goal

Hand-author dungeon content that shows the real-time lighting system in motion,
and that reads as a real place, not a prop box. Three set-piece rooms, each
foregrounding one lighting behaviour:

1. **Watchfire Hall** — warm wall-torch light: fast (9 Hz) flicker, pools that
   overlap and gap as the camera walks the hall.
2. **Rime Vault** — the showpiece: a moving light **behind translucent ice**,
   so it bleeds through the ice walls tinted blue while the player's own warm
   torch lights the near face.
3. **Emberdeep Fissure** — magma light: a slow (0.6 Hz) red pulse (a different
   colour *and* cadence from the torch hall), with fog banks drifting across it.

## Capture flow this content serves (settled — do not re-derive)

The trailer take does **not** hunt for a seed. The flow is:

1. Build the content (this brief).
2. In wizard mode, drop into the demo dungeon, generate a level instance that
   frames well, position the player at the shot's start.
3. **Save.** That save freezes the exact level instance, monster positions and
   camera start.
4. Every take: `./incursion -load <save> -keys <script>` (both flags landed in
   commit `04431f2`). Deterministic, seed-independent, repeatable.

So room placement luck is irrelevant — the good instance is frozen in the save.

## Two open decisions for Brian (recommendation given; the rest of the brief assumes the recommendation)

**D1 — container.** The three rooms are theme-incoherent inside the Goblin
Caves (an ice vault and a lava fissure do not belong under goblins — that is the
prop-box look to avoid). **Recommendation: a dedicated 3-level demo dungeon**
("The Sundered Deep" or a name Brian picks), one showcase room per level,
chained by stairs, so torch/ice/fire coexist by design and one continuous save
walks the whole sequence. The rooms below are identical either way; only the
placement section (§ Placement) changes. Alternative if Brian says no new
dungeon: add the three rooms to `The Goblin Caves` `Specials:` (`dungeon.irh:19`)
and accept the theme stretch.

**D2 — fog and light.** Placeable fog **terrain** obscures line of sight but
does **not** tint or scatter coloured light — that path is field-only
(`FI_FOG`, `src/Light.cpp:428-439`); `ScanTerrain` has no fog hook
(`Light.cpp:421-424` handles only torch/magma). **This brief uses fog as pure
atmosphere** (drifting concealment rolling across the red magma glow), which
needs zero engine work. If Brian wants fog to visibly scatter coloured light in
the trailer — a much stronger shot — that is a **separate engine task** (wire
placeable fog terrain into the `FogCol[]` path), specced on its own, not folded
in here.

**Note, not a decision:** the bead lists "will-o'-wisp emits no engine light" as
a gap to fix. It is **already fixed** — `mon3.irh:1378-1383` spawns a
`FI_LIGHT|FI_MOBILE` radius-3 white field (added under inc-aau6). The wisp is a
ready-made moving coloured light; this brief uses it as-is, nothing to build.

## Authoring grammar (confirmed against the codebase)

- A hand-placed room is `Region "Name" : RF_ROOM { ... }`
  (`lang/Grammar.acc:958`). Model on the Parthenion (`dungeon.irh:3242-3298`).
- `Grid: {: <ascii> :};` — the `{:`…`:}` delimiters are one token. **Every row
  MUST be exactly equal width** or the build dies with "Map grid alignment
  error" (`lang/Tokens.lex:311`). Whitespace inside the grid is stripped, so
  source indentation is cosmetic. Room must fit the dungeon's `ROOM_MAXX/Y`
  panel plus a 2-cell margin (`src/MakeLev.cpp:1563`).
- Default grid chars (no legend needed): `#` = room Wall (`Walls:`), `.` =
  Floor, `+` = a `Door:` door, digit `0-9` = a guardian monster at level
  `DepthCR + digit*2`, `g`/`G` = a good item, `s` = a statue, `%` = plain
  outer wall (`src/MakeLev.cpp:1164-1246`).
- `Tiles:` legend entry: `'X': $"terrain" with $"item-or-monster-or-feature";`.
  A monster tile auto-receives its own `Gear:` via `GrantGear` on placement
  (`MakeLev.cpp:1088`), so seeding `with $"will-o'-wisp"` gives a fully-kitted,
  self-lighting wisp. `[WQ_GLOWING]` on a weapon item grants light = plus×3
  when wielded.
- `RoomTypes: RM_SHAPED;` = "this room supplies its own outline via `Grid:`".
  `Flags: RF_NOGEN;` keeps it out of the random pool so it appears **only**
  where a `Specials:` line places it.

## Light building blocks (exact tokens + measured behaviour)

| Token | Kind | Radius | Colour / flicker | Source |
|---|---|---|---|---|
| `$"Wall Torch"` | opaque wall, emits | 3 | warm `{255,160,60}`, amp 0.30 @ **9 Hz** | `dungeon.irh:542`, `Light.cpp:423` |
| `$"magma"` | floor light + 6d6 fire hazard | 2 | red `{255,80,20}`, amp 0.35 @ **0.6 Hz** | `dungeon.irh:1906`, `Light.cpp:421` |
| `$"Ice Wall"` | solid wall, **not opaque** | — | passes 55% of light, tinted to ice colour | `dungeon.irh:530`, `Light.cpp:303`, `LIGHT_ICE_PASS 0.55` |
| `$"Ice Floor"` / `$"ice door"` | floor / door | — | dressing | — |
| `$"fog"` | obscures LOS | — | **no coloured-light interaction** (D2) | `dungeon.irh:1021`, `Light.cpp:428` |
| `$"will-o'-wisp"` | monster, mobile field | 3 | white, **moves** (`FI_MOBILE`) | `mon3.irh:1334` |
| `$"torch"` (rng 4) / `$"brass lantern"` (rng 6) | carried light | 4 / 6 | must be equipped in `SL_LIGHT` to shine | `mundane.irh:625/635`, `Values.cpp:1565` |

## The three rooms

The grids below are the intended layout. **Codex MUST keep every row equal
width** (the widths I count are noted) and tune torch/pool spacing on the SDL
build for the light rhythm — the exact sconce count is Brian's oracle, not a
fixed number.

### Room A — Watchfire Hall (19 wide × 11 tall)

```
Region "Watchfire Hall" : RF_ROOM
  {
    Desc: "A long guard hall. Iron sconces line the walls; the torches have
      never gone out.";
    Walls: $"Dungeon Wall"; Floor: $"Floor"; Door: $"iron door";
    RoomTypes: RM_SHAPED; Flags: RF_NOGEN;
    Grid: {:
      ###T###T###T###T###
      +.................+
      #.................#
      #....s.......s....#
      #.................#
      #..1...........2..#
      #.................#
      #........g........#
      #.................#
      +.................+
      ###T###T###T###T###
      :};
    Tiles:
      'T': $"Wall Torch";
  }
```

Torches (`T`) sit in the top and bottom walls (they are walls). Radius-3 light
reaches ~3 tiles in from each long wall, leaving a dim band across the middle
rows → the camera walking the hall crosses lit and shadowed bands, and the
overlapping pools flicker at 9 Hz. `1`/`2` are depth-scaled guards (goblins in
Goblin Caves; pick theme-appropriate denizens for the dedicated dungeon).
`s` statues and a `g` good item are real dungeon dressing, not light props.

### Room B — Rime Vault (19 wide × 13 tall) — the showpiece

```
Region "Rime Vault" : RF_ROOM
  {
    Desc: "A burial vault sealed in ice. Something cold and bright drifts
      inside the frozen lattice at its heart.";
    Walls: $"Dungeon Wall"; Floor: $"Ice Floor"; Door: $"ice door";
    RoomTypes: RM_SHAPED; Flags: RF_NOGEN, RF_NEVER_LIT;
    Grid: {:
      ###################
      +.................+
      #.......III.......#
      #......I...I......#
      #.....I.....I.....#
      #.....I..w..I.....#
      #.....I.....I.....#
      #......I...I......#
      #.......III.......#
      #.................#
      #..1...........2..#
      +.................+
      ###################
      :};
    Tiles:
      'I': $"Ice Wall",
      'w': $"will-o'-wisp";
  }
```

The `I` cells form a translucent ice ring around a will-o'-wisp (`w`). The
wisp's radius-3 white field is trapped inside the ring; its light passes the ice
at 55%, tinted blue, and because the field is `FI_MOBILE` the inner glow
**drifts** — moving coloured light bleeding through translucent walls. The
player enters carrying a torch (§ Player kit), so warm light hits the near ice
face while the cool wisp-light bleeds from within: warm/cool refraction in one
frame. `Floor: $"Ice Floor"` makes the whole room ice underfoot; `RF_NEVER_LIT`
keeps ambient light off so the wisp and torch are the only sources. `1`/`2` are
frost-themed denizens.

### Room C — Emberdeep Fissure (19 wide × 11 tall)

```
Region "Emberdeep Fissure" : RF_ROOM
  {
    Desc: "A volcanic fissure. Magma glows in the cracks and steam drifts
      across the light.";
    Walls: $"Dungeon Wall"; Floor: $"Floor"; Door: $"iron door";
    RoomTypes: RM_SHAPED; Flags: RF_NOGEN, RF_NEVER_LIT;
    Grid: {:
      ###################
      +.................+
      #..~~~.......~~~..#
      #.................#
      #....MMM...MMM....#
      #....MMM.g.MMM....#
      #....MMM...MMM....#
      #.................#
      #..~~2.......1~~..#
      +.................+
      ###################
      :};
    Tiles:
      'M': $"magma",
      '~': $"fog";
  }
```

Two magma pools (`M`) cast dim red radius-2 light pulsing at 0.6 Hz — a slow
throb, red, contrasting the torch hall's fast warm flicker. Fog banks (`~`)
drift as LOS obscurance rolling across the red glow (D2: fog does not tint the
light — it is atmosphere here). The `g` good item sits on the safe spit between
the pools (`.g.`), lit red and reachable without crossing magma (magma is 6d6
fire — a real hazard to route around, not a prop). `1`/`2` are fire denizens
that emit their own glow (the inc-aau6 creature-glow set) → more moving light.
`RF_NEVER_LIT` so magma is the only ambient source.

## Player kit for the take

The Rime Vault shot needs the player carrying a warm light. Ensure the capture
character has a `$"torch"` (or `$"brass lantern"`) **equipped in `SL_LIGHT`** —
a dropped light does not shine (`Values.cpp:1565`). This is a wizard-mode setup
step at save time, not content; note it in the capture runbook.

## Placement (assumes D1 = dedicated dungeon)

Add a `Dungeon` modelled on `The Goblin Caves` (`dungeon.irh:7`):

```
Dungeon "The Sundered Deep"
  {
    Constants:
      * ROOM_MAXX 22, * ROOM_MAXY 22,   // fit the 19-wide rooms + margin
      * STAIRS_UP $"up stairs", * STAIRS_DOWN $"down stairs",
      * DUN_DEPTH 3;
    Specials:
      * $"Watchfire Hall"    at level 1,
      * $"Rime Vault"        at level 2,
      * $"Emberdeep Fissure" at level 3;
    Desc: "...";
  }
```

Keep each level small and otherwise dark so the showcase room dominates the
frame. Confirm the wizard-mode command that jumps into a named dungeon; if the
world graph does not link "The Sundered Deep" to a start point, add a portal or
use the wizard level-jump — Claude handles this at save time, but Codex should
confirm the room `Region`s generate cleanly first (headless).

If D1 = thread into Goblin Caves instead: drop the `Dungeon` block, add the
three `Specials:` lines to `dungeon.irh:19`, and pick depths that do not collide
with the existing set-pieces (L2 already holds the library and Parthenion).

## Phases (each a review gate; Codex does NOT commit — Claude verifies)

1. **Room A (Watchfire Hall).** Author the `Region`. GATE: headless build parses
   and the module loads (`BACKEND=posix ./build_macos.sh`); grid widths equal
   (build is silent on success, loud on misalignment).
2. **Room B (Rime Vault)** + **Room C (Emberdeep Fissure).** Author both.
   GATE: same — parses, module loads, widths equal.
3. **Placement.** The `Dungeon` block (or the Goblin-Caves `Specials:` lines per
   D1). GATE: headless generates each level with its Special room present
   (a headless dive that reaches the level shows the room; Claude confirms on
   the SDL build that the room renders and lights).

Dispatch phase 1 first, review the one-room diff, then 2–3.

## Test / verify plan

- **Parse/build:** `BACKEND=posix ./build_macos.sh` compiles the module with the
  new content, exit 0. A grid-width slip fails here — that is the runnable check.
- **Generation:** a headless run that reaches each demo level confirms the
  Special room placed and the monsters/items seeded (no "Illegal char in map
  grid", no "Special room larger than map").
- **Regression:** `tools/nightly_verify.sh --compare` shows no new reds.
- **Live (Claude, SDL, the real oracle):** load a save standing in each room and
  confirm on screen — torch pools flicker warm at the hall ends; the wisp's blue
  glow bleeds through the ice and drifts; magma pulses red and slow while fog
  rolls across. The look is Brian's call; the mechanics are in `logs/palette.log`.

## Build notes for Codex

- Build headless only: `BACKEND=posix ./build_macos.sh`. The SDL build fails in
  the sandbox (no display) — leave it and every on-screen light check to Claude.
- Do NOT run `./incursion` or any `check_*.sh` that needs the SDL binary.
- Do NOT commit. Leave the tree dirty for Claude to review per phase.
- Every terrain/item/monster token above is confirmed to exist; if a token
  fails lookup, stop and report — do not invent a replacement.
