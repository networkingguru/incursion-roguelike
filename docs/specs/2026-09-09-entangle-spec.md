# Entangled and anchored: two conditions where the engine has one

Date: 2026-09-09.
Beads: **inc-18q6** (this work), **inc-jwm0** (closes when this lands; its last
open acceptance criterion is the decision recorded here), **inc-upw.57** (the
stati-number collision, found while reading for this, fixed separately).

Brian approved the shape on 2026-09-09: "we are doing what the SRD does, both
degrees of 'entangled'. We are fixing this bullshit everywhere."

## 1. The problem in one paragraph

The engine has one condition, `STUCK`, and it means "you may do almost nothing".
The SRD has two conditions, and neither of them means that. *Entangled* is a
penalty that leaves you free to move and fight. *Glued to the floor*, which the
SRD reaches only on a failed save, stops you leaving the square and still lets
you fight. Incursion collapsed both into a single state that forbids twenty-one
different actions, and then applied it to every hazard at one difficulty.

## 2. What the code does today

### 2.1 One condition, twenty-one prohibitions

`STUCK` aborts each of these:

| Action | Site |
|---|---|
| melee attack with a weapon | `src/Fight.cpp:~400` (`WAttack`) |
| ranged attack | `src/Fight.cpp:~735` (`RAttack`) |
| bull rush | `src/Fight.cpp:~2210` |
| trip | `src/Fight.cpp:~2239` |
| disarm | `src/Fight.cpp:~2298` |
| throw a grappled creature | `src/Fight.cpp:~2559` |
| spring attack | `src/Fight.cpp:~2594` |
| whirlwind attack | `src/Fight.cpp:~2663` |
| sunder | `src/Fight.cpp:~2707` |
| sprint | `src/Fight.cpp:~2744` |
| any attack of opportunity | `src/Fight.cpp:~2837` (`canMakeAoO`) |
| jump | `src/Move.cpp:~61` |
| ascend, descend | `src/Skills.cpp:~3972`, `src/Skills.cpp:~4140` |
| pick anything up | `src/Inv.cpp:~478` |
| don or doff armour | `src/Inv.cpp:~325`, `src/Inv.cpp:~431` |
| be ridden as a mount | `src/Skills.cpp:~4252` |

It further applies: −7 to Reflex saves (`src/Creature.cpp:~3438`), −60 to spell
success, shared with a grapple (`src/Magic.cpp:~3234`), loss of the shield's AC,
cover and damage absorption (`src/Values.cpp:~633`, `src/Values.cpp:~904`), and membership of
`noDexDefense()` (`src/Fight.cpp:~2811`), which denies Dexterity to AC and so
opens the victim to sneak attack and to the auto-coup paths at `src/Fight.cpp:~543` and
`src/Fight.cpp:~1293`.

### 2.2 The asymmetry that shows this was never designed

`NAttack` — natural attacks — has no `STUCK` gate at all. A glued monster claws
at full effect while a glued character may not swing a sword.

### 2.3 Sticky terrain rolls a saving throw that always fails

`src/Move.cpp:~1512` rolls Balance against `14 + m->Depth`; on a failure it deals
`AD_STUK`. The `AD_STUK` arm (`src/Fight.cpp:~6559`) then calls
`SavingThrow(REF, e.saveDC)`. The terrain path never sets `saveDC`, and
`EventInfo::Clear()` memsets the struct (`inc/Events.h:~203`), so the DC is 0.
`Creature::SavingThrow` returns **false** for `DC <= 0` (`src/Creature.cpp:~3359`)
— a zero DC is an automatic failure, not an automatic pass. The Balance check is
therefore the only real roll, and the Reflex save is dead code that always fails.

The same dead save sits behind `lib/alchemy.irh:~308`, where tanglefoot strands
roll their own real Reflex DC 15 first, so only the terrain path is affected in
practice.

### 2.4 Sticky terrain never wears off

The terrain path passes `-1` as the duration. `src/Status.cpp:~50` only
decrements a duration greater than zero, so the condition is permanent until the
escape check passes.

### 2.5 Grease is already correct, and inc-18q6 is wrong about it

"pool of grease" (`lib/dungeon.irh:~1117`) is **not** `TF_STICKY`. It rolls
Balance against `max(15, terrain DC)` and, on a failure, prints "You slip and
fall!", throws `AD_TRIP` and aborts the move. That is the SRD's grease. Only two
terrains carry `TF_STICKY`: "pool of slime" (`lib/dungeon.irh:~877`) and "Webbing" (`lib/dungeon.irh:~1218`).
inc-18q6's hazard list must be corrected, and grease MUST NOT be changed.

## 3. Normative requirements

### 3.1 The entangled condition

**R1.** A new stati `ENTANGLED` MUST be defined at 237, and `LAST_STATI` MUST
become 238 (`inc/Defines.h`). It MUST have a row in `StatiNames`
(`src/Tables.cpp:~4416`), in `StatiLineStats` and in `StatiLineShorts`
(`src/Tables.cpp:~487`, `src/Tables.cpp:~525`), and a `StatiMessage` arm
(`src/Status.cpp:~1207`) that prints on gain and on loss.

**R2.** An entangled creature MUST take −2 on attack rolls and −4 on Dexterity.
These MUST be applied in `Creature::CalcValues` (`src/Values.cpp`), beside the
existing `STUNNED` and `SINGING` blocks, as
`AddBonus(BONUS_STATUS, A_HIT, -2)` and `AddBonus(BONUS_STATUS, A_DEX, -4)`.
The Reflex penalty that follows from −4 Dexterity MUST come from that, and MUST
NOT be added a second time.

**R3.** An entangled creature MUST move at half speed. `Creature::MoveAttr`
(`src/Creature.cpp:~3318`) MUST halve its result. Terrain that declares its own
`Mov` below 100% keeps it, and the two multiply.

**R4.** An entangled creature MUST NOT run, sprint or charge. It MUST be able to
move, attack, cast, pick things up and make attacks of opportunity.

**R5.** An entangled creature MUST take a spell-success penalty of −20 in
`Creature::CalcCastingValues` (`src/Magic.cpp:~3234`), the same value the engine
already gives a prone caster. The SRD's Concentration check has no analogue in
this engine and MUST NOT be invented for it.

### 3.2 The anchored condition

**R6.** `STUCK` MUST keep its number, 11, and MUST mean **anchored**: the
creature cannot leave its square until it escapes. A creature that is anchored
MUST also be entangled, and MUST take the entangled penalties once, not twice.

**R7.** Every prohibition in §2.1 that is not movement MUST be deleted. Named
exactly: weapon melee, ranged, trip, disarm, throw, whirlwind, sunder,
attacks of opportunity, and picking an item up.

**R8.** Every prohibition in §2.1 that is movement MUST stay: bull rush, spring
attack, sprint, jump, ascend, descend. Donning and doffing armour MUST stay
forbidden; that is minutes of work, not a round. Being ridden MUST stay
forbidden.

**R9.** `STUCK` MUST be removed from `noDexDefense()` (`src/Fight.cpp:~2811`).
An anchored creature keeps its Dexterity bonus to AC. This removes sneak attack
and the two auto-coup paths (`src/Fight.cpp:~543`, `src/Fight.cpp:~1293`) as automatic
consequences of being stuck. Brian ruled on this explicitly.

**R10.** `STUCK` MUST be removed from the `grappling` expression at
`src/Values.cpp:~633`, so an anchored creature keeps its shield's AC, cover and
absorption. A grapple keeps that penalty.

**R11.** The −7 Reflex penalty at `src/Creature.cpp:~3438` MUST be deleted. R2
supplies the correct penalty through Dexterity.

**R12.** The −60 spell penalty at `src/Magic.cpp:~3234` MUST stop applying to
`STUCK`. An anchored caster takes −40. A grapple keeps −60.

### 3.3 Escape

**R13.** The escape roll MUST stay in the `HasStati(STUCK)` branch of
`Creature::Walk` (`src/Move.cpp:~154`), MUST keep its present shape — Escape
Artist first, Strength on a failure, no armour penalty on the Strength check —
and MUST keep printing both check lines. The natural-20 clause at
`src/Skills.cpp:~1600` is unchanged.

**R14.** The two difficulties MUST come from one table, keyed on the stati's
`Val`, which already carries the hazard kind (`inc/Defines.h:~2882`). The flat
`15 + GetStatiMag(STUCK)` MUST go.

| `Val` | hazard | Escape Artist DC | Strength DC |
|---|---|---|---|
| `STUCK_BONDED` | tanglefoot strands | 22 | **17** |
| `STUCK_WEB` (new, 7) | Webbing, Ettercap Webbing | **20** | 25 |
| `STUCK_WEAPON` | net, entangling weapon | 20 | 25 |
| `STUCK_VINES` | vines | 20 | 25 |
| `STUCK_STICKY` | pool of slime | 15 | 20 |
| `STUCK_PINNED` | rubble | 20 | 20 |
| `STUCK_ATTACK` | a monster's `AD_STUK` | the attack's own DC | the attack's own DC |
| 0 or −1 | anything that declares no kind | 20 | 25 |

The inversion between the first two rows is the point, and it is the SRD's:
glue is the Strength hazard and web is the Dexterity hazard, so a rogue and a
fighter each have one they beat and one they struggle with.

**Deviation, stated deliberately.** The SRD's tanglefoot entry offers no Escape
Artist option at all. This table gives one at DC 22 rather than removing it,
because an unreachable check is what inc-jwm0 was about and the fix should not
create a second one facing the other way.

**R15.** `STUCK_WEB` MUST be added as 7 in `inc/Defines.h`. The `STUCK_*`
constants are a separate small enum from the stati numbers and none of them
collide; see inc-upw.57 for the ones that do.

**R16.** A monster's `AD_STUK` MUST pass its attack's save DC as the stati's
`Mag`, so the `STUCK_ATTACK` row has a number to read. The monster data already
carries it (`lib/mon3.irh:~1948` DC 20, `lib/mon3.irh:~2669` DC 15, `lib/mon4.irh:~2395` DC 13).

### 3.4 Which hazards grant which condition

**R17.** A hazard whose save the creature FAILS MUST grant `STUCK`. A hazard
whose save the creature PASSES, while it stays in the hazard, MUST grant
`ENTANGLED`. Leaving the square MUST remove that `ENTANGLED`.

**R18.** Each hazard MUST declare its kind, so the table in R14 can be read:

| Hazard | file | kind to declare |
|---|---|---|
| pool of slime | `lib/dungeon.irh:~877` | `STUCK_STICKY` (already correct) |
| Webbing | `lib/dungeon.irh:~1218` | `STUCK_WEB` (change from `STUCK_STICKY`) |
| Ettercap Webbing | `lib/mon1.irh:~2488` | none — see R18a |
| tanglefoot strands | `lib/alchemy.irh:~242` | `STUCK_BONDED` |
| pile of rubble | `lib/dungeon.irh:~834` | `STUCK_PINNED` (already correct) |
| entangling weapons | `src/Fight.cpp:~8109` | `STUCK_WEAPON` (already correct) |

**R18a.** "Ettercap Webbing" (`lib/mon1.irh:~2488`) is not `TF_STICKY` and grants
no stati at all. It taxes each move with `SkillCheck(SK_ESCAPE_ART, 17, true)`
— an Escape Artist check that carries the armour penalty, so it is the same
unreachable check inc-jwm0 was about, written in script instead of the engine.
It MUST gain a Strength alternative at DC 22, tried when the skill check fails,
with no armour penalty. Nothing else about that terrain changes: it still costs
a turn rather than granting a condition.

### 3.5 The two defects that ride along

**R19.** The sticky-terrain path MUST set a real `saveDC` before it throws
`AD_STUK` (`src/Move.cpp:~1512`), so the Reflex save is a real roll. The DC MUST
be the same `14 + m->Depth` the Balance check uses.

**R20.** The sticky-terrain path MUST pass a finite duration rather than −1, so
a creature that never escapes is not stuck for the rest of the game.

**R21.** R19 and R20 are upstream defects and MUST each be marked at the fix
site with an `upstream:` comment and rowed in `docs/REPORTING-GATE.md` under
`### Base-code bugs fixed locally`, per `AGENTS.md`. So must every other change
in §3.1–§3.3 that is upstream's. All of it is: the whole subject is
platform-independent integer logic and behaves identically on the original
Win32 build.

## 4. Out of scope

* The SRD's alternative escape from a tanglefoot bag — 15 points of slashing
  damage to the goo — is NOT implemented.
* `lib/m_items.irh:~1902` grants permanent `STUCK` from an ice wand. It is left
  alone in this work and will become a debuff rather than a total disable. If it
  wants re-tuning afterwards, that is a separate bead.
* `inc-upw.57`, the `MAGIC_AURA`/`SOCIAL_MOD` collision, is separate.
* The commented-out `FI_WEBBING` field code at `src/Status.cpp:~1765` stays
  commented out.
* "Old Webbing" (`lib/dungeon.irh:~1157`) is out of scope. It grants no
  condition; walking into it tears it apart and turns the square back to floor.
  Its `Mov: 25%` is terrain slowness and stays.

## 5. Save compatibility

`STUCK` keeps number 11 and keeps the meaning of its `Val`. `ENTANGLED` takes
237, which no save has ever written, and `LAST_STATI` moves from 237 to 238. No
existing stati changes number, so no migration is needed and
`tools/check_v1_append_survives.sh` MUST stay green. No new `lib/` resource is
added, so the append-only resource rule is not engaged.

## 6. Checks

Per `docs/VERIFICATION.md`, each MUST be proved red before it is trusted.

1. `tools/check_entangle_escape.sh` — extend. It currently proves the Strength
   exit exists. It MUST additionally prove the per-hazard DCs: the same paladin
   in tanglefoot strands faces Strength DC 17, not 14.
2. `tools/check_entangled_acts.sh` — new. A creature that is entangled but not
   anchored moves, attacks, and shows the −2 and −4 on its sheet.
3. `tools/check_stuck_fights.sh` — new. An anchored creature attacks and is
   refused movement. It MUST assert both halves; a change that freed the
   creature would otherwise satisfy the first.
4. `tools/check_sticky_save.sh` — new. Walking onto slime rolls a Reflex save
   with a DC above zero, and the resulting condition has a finite duration.

Each new check needs a row in `README.md` under "The checks", or
`tools/check_readme_checks.sh` goes red.

## 7. Recorded decisions

* Anchored does not deny Dexterity (R9). Brian ruled it on 2026-09-09, knowing
  it removes sneak attack against every glued or webbed target.
* Every hazard gets its own difficulty and its own governing attribute (R14).
  This is what inc-18q6 asked for and it closes inc-jwm0's second open
  criterion.
* `STUCK` becomes the SRD's entangled-plus-anchored rather than keeping its
  total prohibition (R6, R7). This closes inc-jwm0's first open criterion,
  which asked for a recorded decision either way.
