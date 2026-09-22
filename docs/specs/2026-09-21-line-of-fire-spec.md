# One rule for a body in the line of fire

Design bead: `inc-30ps`. Absorbs `inc-c4l4` (Magic Missile). Excludes
`inc-e2p7` (Vitriolic Sphere), which is a burst wrongly declared as a bolt and
is fixed separately.

Commit lane: `rules:`. A player feels this in every fight.

## The defect

The engine holds two different rules for one physical event, and neither one
is right.

**An arrow negotiates.** `src/Fight.cpp:1036-1116` walks the line. On each
square that holds a creature which is not the intended target, it rolls d100
and attacks that creature 75% of the time — 25% with Precise Shot. A real
attack roll follows. A hit stops the arrow; a miss lets it fly on. On the
target's own square, Precise Shot picks the right creature 95% of the time
against 60%.

**A spell bolt does not negotiate.** `Magic::ABallBeamBolt`, `src/Magic.cpp:1940`:

    for (cr = m.FCreatureAt(cx/2,cy/2); cr; cr = m.NCreatureAt(cx/2,cy/2))
      if (cr != e.EActor || e.vChainCount != 0)
        {
          if (cr != e.EVictim) { ADD_TARGET(cr); }
          if (!isMulti) goto OuterBreak;
        }

The first creature in the line becomes the target and the walk stops. The
chosen victim is never reached. `DoHits` at `:2121` applies the effect with no
friend filter, so a companion, a summon or an animated zombie takes the full
damage. Most bolts carry no `EF_ATTACK`, so no attack roll happens at all, and
many carry `sval: NOSAVE`, so no save happens either.

Targeting does not warn the player. `Map::LineOfFire`, `src/Vision.cpp:228`,
walks with `CARE_ABOUT_SOLID`: it cares about walls and not about creatures,
so the cursor lands on the far foe freely.

## The rule

**Each square in the line that holds at least one creature imposes a −4 penalty
on the attack.** The penalty is per SQUARE, not per creature. A square holding
four bodies costs −4, the same as a square holding one.

**The target's own square imposes the same −4 if the target is not the first
creature in that square.** First means the head of the square's contents chain.

**The attack rolls once.** Let `total` be `vHit + vRoll` and let `D` be the
target's **base** defence, without any of the −4s. Resolve in this order:

1. **`total >= D + 4N`, or a natural 20 — the target is hit. No saving throw,
   full stop.** Skill reaches the creature you aimed at.
2. **`total < D` — nothing is struck.** The shot was not good enough to hit
   even an unobstructed target.
3. **Otherwise the shot lands in a band**, `band = (total - D) / 4`, counting
   from the shooter: band 0 is the square nearest the shooter, and the highest
   band is the square nearest the target. **The band names a SQUARE, not a
   creature.**

**Inside that square, a saving throw decides who is hit, and whether anyone
is.** Each creature in the square, in contents-chain order, makes a **Reflex
save**. **The first creature to FAIL takes the hit.** If every creature in that
square makes its save, the shot is a **miss** and nothing else is tried.

**The save DC is `10 + (total - D)`** — ten, plus every point the attack rolled
over the intended target's base defence. So the DC rises with the band: a wild
shot that barely cleared the bare defence sets DC 10 and is easily stepped
away from; a shot that nearly reached the target sets a DC in the twenties and
is almost impossible to avoid.

Two consequences, both intended. Defence no longer decides who is clipped —
geometry and the save do. And the creature struck takes damage appropriate to
**itself**, not to the target: its own size chooses the damage dice and its own
type chooses the damage type.

**The band applies only to a genuine roll-based miss.** `Creature::Strike`
reports "miss" down several paths that never compare a roll to a defence —
displacement and blur, the tree-elevation and tower-shield and corner cover
rolls, `FLAWLESS_DODGE`, and a mounted defence beating `vRideCheck`. **None of
those may enter the band logic.** They are misses outright. Gate the band on
`total < D + 4N`, never on `!e.isHit`, or a natural 20 into a displaced target
shoots your own ally.

Brian ruled the saving throw on 2026-09-22, replacing an earlier version of
this section in which the band's creature was hit if the same roll beat its own
defence. His words are in the notes of `inc-30ps`.

### A shot with no chosen creature

A shot may be aimed at a square rather than at a creature — `Q_LOC` targeting,
or a flask thrown down a corridor. There is then no target, so there is no
defence to build bands from, and the rule above cannot apply.

**If the whole path holds exactly one creature, that creature IS the target.**
Resolve the shot against it normally, with **no penalty at all**. It is the
only thing there is to shoot at, so the shooter is aiming at it whether or not
they named it.

**If the path holds more than one,** roll once. Compare that single roll, at a
**flat −4**, against the head creature of each square along the path, in order
from the shooter. **The first square whose comparison is a hit takes the hit.**
If no comparison hits, the shot reaches its maximum range and strikes nothing.

The −4 is flat and does not accumulate. Each body is a thing the shot may clip,
not a body standing in front of something else, because the shooter aimed at
none of them.

Brian ruled this on 2026-09-21. His words are in the notes of `inc-30ps.2`.

**No saving throw applies to this case**, and there are no bands. The save DC
elsewhere is `10 + (total - D)`, and a shot at a square has no intended target
to supply `D`. So this rule stands exactly as he gave it: the roll is compared
to each candidate's own defence, and the first one it beats is struck. Read as
the author's reading, not as a ruling of his.

**This rule applies to spell bolts as well as to weapons.** It was first built
for the weapon path only, which left a bolt aimed down a corridor still killing
the first ally it met with certainty — one of the two faults this epic exists
to remove.

Precise Shot does not help here: the feat exists to let a shooter hit the
creature they meant, and this shooter meant a square. Read as an assumption
rather than a ruling.

The behaviour before this epic was that the shot attacked whatever it passed
through, with certainty and no roll at all.

### Worked example, normative

The target's base defence `D` is 10. Two squares in the line hold creatures.
The target is not first in its own square. So `N` is 3 and the target is
reached at 22.

| Total | Band | Square named | Save DC |
|---|---|---|---|
| 22 or more | — | **the target, no save** | — |
| 18–21 | 2 | the target's own square | 18–21 |
| 14–17 | 1 | the nearer intervening square | 14–17 |
| 10–13 | 0 | the square in front of the shooter | 10–13 |
| under 10 | — | **nothing is struck** | — |

In each banded row, every creature in the named square makes a Reflex save
against that DC, in contents-chain order. The first to fail takes the hit. If
they all save, the shot misses and no other square is tried.

Note that the DC equals the total, because `D` is 10 here and the DC is
`10 + (total - D)`. That is a coincidence of this example, not the rule.

### Which creature is "front"

Since the saving throw arrived, "front" is no longer who is hit. It is who is
asked **first**. The square's creatures are offered their saves in contents-
chain order, and the first one to fail takes the shot, so a square's head is
merely the first name on the list.

That order is the head of the square's contents chain, `At(x,y).Contents`,
walked by `Map::GetAt` at `src/Display.cpp:1437`.

The chain is deterministic and it survives a save. Both insertion sites,
`src/Display.cpp:281-290` on placement and `:1797-1805` on movement, apply one
rule: if the head is already a creature, splice the newcomer in at position
two; otherwise make the newcomer the head. So the head is the first creature
to stand there, and later arrivals follow in reverse order of arrival.

This is the creature the targeting cursor's `n` key offers first
(`src/Term.cpp:2714-2727`), so a player can see who is exposed before shooting.

**Hazard.** `Map::GetAt` keeps its cursor in static locals (`curr`, `doneflag`,
`src/Display.cpp:1439-1440`), so the whole game shares one iterator. A scan of
square B inside a loop over square A corrupts both. Copy a square's creatures
into a local array first, as the arrow path already does at
`src/Fight.cpp:1036-1039`.

## Precise Shot

Precise Shot removes every −4 and every band. A shot passes all intervening
bodies and can never strike one.

**It applies to weapon attacks only.** The SRD feat reads *"You can shoot or
throw ranged weapons at an opponent engaged in melee without taking the
standard −4 penalty on your attack roll."* It names weapons, not attacks, and
no SRD text extends it to a spell's ranged touch attack.

This diverges from the SRD in one respect, deliberately. In the SRD, Precise
Shot cancels the into-melee penalty and has no effect on soft cover. Here it
cancels the cover stack. Brian ruled this so the feat is worth taking; his
words are in the notes of `inc-30ps`.

Both existing probability tests are deleted: `src/Fight.cpp:1050` (95/60 on the
target's square) and `:1073` (75/25 on an intervening square). The feat's
description at `src/FeatTab.cpp:1633-1638` describes the deleted test and MUST
be rewritten.

## Touch defence

`Magic::MagicStrike` sets `e.vDef = e.EVictim->GetAttr(A_DEF)`
(`src/Magic.cpp:921`). The engine has no touch defence at all.

**Read this before assuming the SRD's reason applies here. It does not.**
Worn body armour never reaches `A_DEF` in Incursion. `BONUS_ARMOUR` from a worn
suit feeds Coverage, the archery penalty, speed, to-hit and Reflex saves
(`src/Values.cpp:938-950`) and never the defence class. This engine resolves
armour as coverage and damage reduction, not as d20 armour class. So "a touch
attack bypasses plate mail" describes a thing that cannot happen here.

Two things do inflate `A_DEF` against a touch attack, and only two:

- a **shield**, `AddBonus(BONUS_SHIELD, A_DEF, it->DefVal(...))`,
  `src/Values.cpp:918`;
- an **`ADJUST_ARM` stati** — a mage-armour style spell or enchantment —
  `AddBonus(BONUS_ARMOUR, S->Val, S->Mag)`, `src/Values.cpp:743`. Since no worn
  suit writes there, that slot at `A_DEF` holds nothing else.

So the touch defence is `A_DEF` less the `BONUS_SHIELD` (30) and
`BONUS_ARMOUR` (24) slots, built the way `A_CDEF` already is at
`src/Values.cpp:1491` and `:1526`.

**`BONUS_NATURAL` (23) MUST NOT be subtracted.** In this engine that slot is
not natural armour: it holds the flat base 10 every playable race carries as
`Def: 10` in `lib/races.irh`, stacked in at `src/Values.cpp:458`. Subtracting
it leaves an unarmoured character with a touch defence of 4, measured, so a
ranged touch attack would almost never miss.

A spell's ranged touch attack rolls against the touch defence. A weapon attack
continues to roll against `A_DEF`.

## Scope: the 33 bolt and ray effects

| Disposition | Count | Effects |
|---|---|---|
| Already roll; gain the cover rule only | 9 | Holy Orb, Bolt of Glory, Chromatic Orb, Flame Arrow;blast, Enervation, Dimensional Anchor, Eldritch Bolt, Spit Goo, Alchemist's Fire |
| Save → attack roll | 6 | Caustic Vitae, Chill Blood, Fire Bolts, Thunderbolts, Striking;wand, Venom of Khasrach |
| Gain attack roll, per SRD | 5 | Acid Arrow, Disintegrate, Telekinesis;thrust, Telekinesis;psi-thrust, the Ram |
| Gain attack roll, per own prose | 4 | Force Bolt, Icelance, tongue of flame, Alicorn Lance |
| Stay unerring; pass every body | 3 | Magic Missile, Force Missiles, Acid;wand |
| Becomes a touch spell | 1 | Minor Drain |
| Unchanged | 3 | Dispelling, Bodak Death Gaze, Surtension |
| Leaves the set | 1 | Vitriolic Sphere (`inc-e2p7`) |
| Skipped | 1 | Call Companions |

Two of these carry a text change as well as a mechanical one:

- **Icelance**, `lib/wspells.irh:4634`, says *"It automatically hits"*. That
  clause is removed and replaced with a ranged touch attack.
- **Alicorn Lance**, `lib/pspells.irh:1518`, becomes **3d6 force damage with a
  ranged touch attack and no saving throw**, following the Silver Marches
  printing, whose damage ours already matches. Today it is 3d6 piercing with
  `sval: REF`.

`Call Companions`, `lib/pspells.irh:757`, is not an attack. It teleports the
caster's allies onto a chosen empty square and carries `aval: AR_BOLT` only to
reach that square. It MUST NOT gain an attack roll, and its `AR_BOLT` MUST NOT
be changed in this work.

## The design

### Phase 1 — the touch defence

Compute it in both branches of `Creature::CalcValues`, `src/Values.cpp:1491`
and `:1526`, beside `A_CDEF`. Nothing reads it yet.

**It MUST NOT be a new slot in the `Attr` array.** `ATTR_LAST` sizes
`Creature::Attr` (`inc/Creature.h:226`) and that array is serialised whole as
field 269, `FIELD_ARRAY(269, Attr, sizeof(int16), ATTR_LAST)`
(`inc/Creature.h:187`), read back by `src/SaveV1.cpp:3540` and three sibling
loops. Growing `ATTR_LAST` from 41 to 42 changes field 269's length, and every
existing save carries the old length.

`docs/SAVE-SCHEMA-SPEC.md` gives the rule: append only, never reorder, never
resize in place. So the touch defence becomes its own `int16` member of
`Creature` with the next free field-map id, appended after the current highest.
Old saves then load unchanged and simply lack the new field.

**Check:** a creature in plate armour has a touch defence lower than its
`A_DEF` by exactly the armour's contribution, and a naked creature's two
numbers agree.

### Phase 2 — the cover rule for weapon attacks

`src/Fight.cpp`, the path walk at `:1036-1116`.

Walk the line once and record, in order from the shooter, every square that
holds a creature other than the shooter, along with that square's head
creature. Copy each square's contents into a local array before moving on; do
not nest `FCreatureAt` loops.

Set `e.vDef` to the target's defence plus 4 per recorded square, plus 4 more if
the target is not the head of its own square. Resolve one strike. On a miss,
read `e.vHit + e.vRoll` back and walk the bands downward to choose the square,
then strike that square's head creature. A natural 20 hits the target.

Delete the two probability tests at `:1050` and `:1073`. With Precise Shot,
skip the penalties and the bands entirely.

**Check:** fire along a line with a known number of bodies and assert the
struck creature for a forced roll in each band, including the two boundaries
and the full miss.

### Phase 3 — the cover rule for spell bolts

`Magic::ABallBeamBolt`, `src/Magic.cpp:1632`. Replace the creature loop at
`:1940-1946` for the `!isMulti` case with the same walk as phase 2. Beams
(`isMulti`) are unchanged: they strike everything in the line by design.

An effect with `EF_ATTACK` resolves through the same band logic as phase 2,
rolling against the touch defence. An effect without `EF_ATTACK` makes no roll,
so it has no bands: it passes every body and reaches the chosen target.

`Magic::PredictVictimsOfBallBeamBolt`, `src/Magic.cpp:2159`, walks the same
path separately for the monster AI. It MUST change with the real walk, or
monsters will aim by a rule the game no longer uses.

**Check:** cast an `EF_ATTACK` bolt over an ally at a forced roll in each band
and assert who is struck; cast a non-`EF_ATTACK` bolt over an ally and assert
the ally is unharmed and the target damaged.

### Phase 4 — the unerring bolts

No code change beyond phase 3. Confirm Magic Missile
(`lib/wspells.irh:1031`), Force Missiles (`:6357`) and Acid;wand
(`lib/m_items.irh:2134`) reach the chosen target past any intervening creature,
with that creature unharmed. This closes `inc-c4l4`.

**Check:** the ally-in-the-line case for all three, red against today's code.

### Phase 5 — the effect declarations

Add `EF_ATTACK` to the 15 effects listed in the scope table as gaining an
attack roll. Apply the two text changes to Icelance and Alicorn Lance, and
Alicorn Lance's damage type and save.

For the six converting from a save, remove the saving throw that represented
dodging. Where a save also governs a rider — Thunderbolts' Fortitude stun, for
example — the rider keeps its save.

**Check:** a structural check over `lib/` asserting the flag and save fields of
all 15, so the set cannot drift.

### Phase 6 — Minor Drain becomes a touch spell

`lib/wspells.irh:1502`. Change `aval: AR_BOLT` to `aval: AR_TOUCH` and drop
`qval: Q_DIR|Q_TAR|Q_LOC`, matching Chill Touch at `:1516`. Rewrite the
description to say it is delivered by touch.

The machinery already exists and needs no engine change: `Magic::ATouch`
(`src/Magic.cpp:2365`) arms a `TOUCH_ATTACK` stati, and `src/Fight.cpp:5234`
discharges it inside a normal melee attack, so the attack roll comes free.

**Check:** the spell cannot be cast at range, and its heal still fires on a
successful touch.

## Verification

`docs/VERIFICATION.md` governs. Every phase states its oracle, its mutation,
and the checks re-run.

This is a `rules:` change a player feels, so it needs a before-and-after
gameplay observation, not a structural check alone. The observation is the
ally-in-the-line case from phase 4: the same seeded session, the same key
script, the ally's hit points and the target's hit points before and after.

`tools/nightly_verify.sh --record` before the work and `--compare` after.

## Marking

The Magic Missile interception is upstream's defect, not the port's. The path
walk depends on no integer width, no typedef and no platform: it behaves
identically on Win32 with the original types. The fix site in
`Magic::ABallBeamBolt` takes an `upstream:` comment stating the invariant, the
tier, the tracking id and whether it has been sent; a row goes in the
"Base-code bugs fixed locally" table in `docs/REPORTING-GATE.md`; and the bead
takes the `upstream` label.

The cover rule itself is NOT a base-code bug. It is a deliberate rules change
and MUST NOT be marked `upstream:`.
