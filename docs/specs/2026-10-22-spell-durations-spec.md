# Spell durations follow the SRD duration classes (inc-nt3z)

Status: draft. Section 11 lists the rulings still open; no phase that touches
an open item starts before its ruling. Every ruling is in the notes of bead
inc-nt3z. A note wins over the per-spell table in the bead's design field.

File and line citations are from the inc-nt3z worktree before it merges
master (74 commits behind on 2026-10-22). Master's lines differ: find each
spell by name.

## 1. Units

One status unit is 60 ticks, which is two 6-second rounds (inc/Defines.h:132-136).
The unit does not change. A duration in rounds converts to units with
`RoundsToUnits` (master src/Status.cpp:101, built in inc-trfo). It halves the
count. An odd count rounds up at random half the time. The minimum is 1. A
count of 0 or less passes through unchanged. Scripts call it through
lib/dispatch.h, as lib/alchemy.irh does.

## 2. Engine: four new duration flags

Add four effect flags, numbered 110-113 in inc/Defines.h, before `EF_LAST`.
These numbers follow master, where `EF_FIXED_PRICE` is 109 and `EF_LAST` is
110:

| Flag | SRD class | Duration in units |
|---|---|---|
| `EF_DROUND` | 1 round/level | (CL+1)/2, minimum 1 |
| `EF_DMIN` | 1 minute/level | 5 × CL |
| `EF_D10MIN` | 10 minutes/level | 50 × CL |
| `EF_DHOUR` | 1 hour/level | 300 × CL |

- `EF_LAST` becomes 114. `EFlags` (inc/Res.h:498) grows from 14 to 15 bytes
  through its own formula.
- Add one `{ EF_x, "EF_x" }` entry per flag in inc/ConstNam.h, before the
  `EF_LAST` entry, so the resource compiler reads the names.
- `Magic::CalcEffect` (src/Magic.cpp:576-589; doublings at 591-599) adds the four flags to its
  duration chain, after `EF_DXLONG` and before `EF_PERSISTANT`.
- A day-class spell (24 hours, 1 day/level) uses the existing `EF_PERSISTANT`
  (-2, ends at the next full rest). There is no day flag.
- The duration MUST be computed in a 32-bit integer through every doubling
  (Anchor, Mystic Preparation, Extend). A result above 32767 becomes -2
  (persistent), because `vDuration` is int16 (inc/Events.h:233).
- A computed duration of 0 means permanent (src/Status.cpp:245). The
  `EF_DROUND` minimum of 1 prevents that.
- `EF_D1ROUND` stays 2 units. `EF_DSHORT` stays 1d4+1 units. The eggshell
  flash-bomb (lib/alchemy.irh) converts its own `EF_DSHORT` value, so
  `EF_DSHORT` MUST NOT change.

Other readers of the duration flags:

- Monster pre-buff (src/Monster.cpp:2716, where `EF_DLONG` qualifies 25% of
  the time) and buff-all (src/Creature.cpp:1293, where it always qualifies)
  treat `EF_DHOUR` and `EF_D10MIN` as each site treats `EF_DLONG`. `EF_DMIN` and
  `EF_DROUND` do not qualify a spell for a pre-buff.
- Spell help (src/Help.cpp:5398-5401) prints "1 round per level.",
  "1 minute per level.", "10 minutes per level." and "1 hour per level."
  for the new flags.

## 3. Buff spells

A buff spell lasts until the next full rest and holds its mana while active.
The `IS_A_BUFF` macro (lib/defines.irh:42-44) gives it `EF_PERSISTANT` and
`EF_LOSEMANA`. A buff gets no SRD duration class.

### 3a. Buffs that lose an extra timer flag

A timer flag beside `IS_A_BUFF` wins in the duration chain, so it MUST go.
A full pass found 157 spells that use `IS_A_BUFF` (159 uses in code); these 7
carry a timer flag. Four buffs also carry `EF_PERMANANT` (Silversheen,
Ironwood, Etherealness, Surreal Presence); it sits after `EF_PERSISTANT` in
the chain, so they need no change.

| Spell | File:line | Remove |
|---|---|---|
| Rainstorm | pspells.irh:1642 | `EF_DLONG` (1643) |
| Protection from Undead | wspells.irh:1584 | `EF_DLONG` (1616) |
| Gaze Reflection | wspells.irh:2015 | `EF_DLONG` (2017) |
| Iron Mind | wspells.irh:2032 | `EF_DLONG` (2038) |
| Endure the Elements | wspells.irh:5662 | `EF_DLONG` on 4 chained parts (5670-5676) |
| Resist the Elements | wspells.irh:7488 | `EF_DLONG` on 4 chained parts (7497-7503) |
| Protection from Elements | wspells.irh:8744 | `EF_DLONG` on 4 chained parts (8753-8759) |

A flag on a chained `and` part lands on the spell's one `EFlags` array: the
`Flags:` rule calls `theEff->SetFlag` whatever part it sits in
(Grammar.acc:~705, yygram.cpp:3473). So the chained-part removals matter.

### 3b. Spells that become buffs

Each gets `EF_PERSISTANT` and `EF_LOSEMANA` and loses any timer flag:
Invisibility (wspells.irh:2884), Levitation (wspells.irh:3399), Divine Power
(pspells.irh:4033), Righteous Might (pspells.irh:4924), Shield Other
(pspells.irh:2156), Tevlar's Transformation (wspells.irh:8761), Slow Poison
(pspells.irh:590), Neutralize Poison (pspells.irh:4166).

Use the flags directly. Do not switch a spell to `IS_A_BUFF`, because the
macro also changes its base chance and purpose (ruled 2026-10-23). Each spell
also gets `EF_CANCEL`, `EF_SHOWNAME` and `EF_NOTBAD` where it lacks them, so
the player can end it. Each keeps its `Base` and `Purpose`.

Mana cost rises to the standard `IS_A_BUFF` cost for the spell's level
(ruled 2026-10-23):

| Spell | Level | Old cost | New cost |
|---|---|---|---|
| Invisibility | 2 | 5 | 15 (`COST_2`) |
| Levitation | 2 | 4 | 15 (`COST_2`) |
| Shield Other | 2 | 3 | 15 (`COST_2`) |
| Slow Poison | 1 | 3 | 5 (`COST_1`) |
| Divine Power | 4 | 17 | 35 (`COST_4`) |
| Righteous Might | 5 | 20 | 45 (`COST_5`) |
| Tevlar's Transformation | 6 | 36 | 55 (`COST_6`) |
| Neutralize Poison | 4 | 7 | 7 (unchanged) |

## 4. Class flags

| Flag | Spells (old flag removed where present) |
|---|---|
| `EF_DROUND` | Grease, Halt Undead, Hold Person, Hold Monster, Hold Beast, Slow, Confusion, Fear, Glitterdust, Dominate Animal, Dominate Reptile (mon1.irh:752), Wind Wall, Hideous Laughter, Ethereal Jaunt, Dispel Evil, Spiritual Hammer, Flaming Sphere, Calm Emotions, Divine Sacrifice |
| `EF_DMIN` | Wall of Fog, Sleep, Deep Slumber, Bane, Doom, Polymorph Other, Polymorph Self (its existing `EF_LOSEMANA` stays), Reduce, Mirror Image, Clairvoyance, Solid Fog, Crushing Despair, Dimensional Anchor, Faerie Fire, Spectral Hand (ruled 2026-10-23; out of inc-n470) |
| `EF_D10MIN` | Change Self, Web, Fire Seeds |
| `EF_DHOUR` | Charm Person |
| `EF_D1ROUND` | Holy Smite, Order's Wrath, Command (each loses `EF_DSHORT`) |
| `EF_PERSISTANT` (day class) | Charm Monster, Dominate Person, Dominate Monster, Control Plant, Consecrate (pspells.irh:1879; SRD 2 hours/level, ruled 2026-10-23 to last until rest like Desecrate) |
| `EF_PERMANANT` | Wall of Stone |

File and line for each row: appendix A.

A charmed or dominated monster turns hostile after the next full rest. This
is accepted.

Divine Sacrifice: also delete `e.vDuration = e.vCasterLev;` and its comment
(pspells.irh:1171-1174), which are the whole handler. That line is a local
rules change (561e0ca1, inc-l8ws), not upstream code, so it gets no
`upstream:` mark.

## 5. Script-set durations

### 5a. Dice in rounds

A spell whose SRD or Desc gives a duration as dice in rounds rolls those dice
and converts the result with `RoundsToUnits`. It does not use `EF_DSHORT`.

| Spell | Dice (rounds) |
|---|---|
| Cause Fear (wspells.irh:903) | 1d4 |
| Unholy Blight (pspells.irh:4543) | 1d4, loses `EF_DSHORT` |
| Chaos Hammer (pspells.irh:4597) | 1d6, loses `EF_DSHORT` |
| Othello's Irresistable Dance (wspells.irh:9252) | 1d4+1, loses `EF_DSHORT` |
| Hypnotism (wspells.irh:2602) | 2d4, loses `EF_DLONG` |
| Ghoul Touch (wspells.irh:3249) | 1d6+2, loses `EF_DLONG` |
| Cause Blindness, spell (pspells.irh:3024) and monster ray (mon3.irh:680) | 3d4, no caster-level scaling, loses `EF_DLONG` |

### 5b. Script dice already written in rounds

Every script-set duration whose Desc states rounds converts with
`RoundsToUnits`: Scare (wspells.irh:3201), Power Word: Stun (wspells.irh:9063,
9065, 9067), Music of the Spheres paralysis (pspells.irh:5212), Convulsion
(wspells.irh:1728), Chromatic Orb (wspells.irh:1238, 1252, 1263), Stinking
Cloud nausea (wspells.irh:~3972, Desc "2d4 additional rounds"), Improved
Invisibility renewal (wspells.irh:6637, Desc "recur in 1d4+1 rounds"), and
any other found by the same test.

Each of these reaches the victim through a direct `GainTempStati` (master
src/Effects.cpp:641 or a script call), so each converts in its own script.

A duration MUST convert exactly once. On master, inc-trfo converts on the
monster and trap attack paths `AD_BLND`, `AD_PLYS`, `AD_STUK`, `AD_CONF`,
`AD_NAUS` and `AD_STUN` in src/Fight.cpp. A value that reaches the victim
through one of those paths does not convert again. Pyrotechnics blindness goes
through `AD_BLND` and is already converted.

These fail the Desc test and stay unchanged: Icelance (its stun is
`EF_DSHORT` on a chained part, and `EF_DSHORT` does not change), Colour Spray
(Desc says "turns"), Colour Burst (Desc says "briefly"), the Dancing Lights
globes, and the Pyrotechnics fear (`10d6`, Desc "much longer duration").

Emotion's despair branch (wspells.irh:6227) has no duration in its Desc, but
was ruled 2026-10-23 to convert: `RoundsToUnits(1d4)` replaces `1d4+1`, per
the design comment at wspells.irh:6178 ("1d4 rounds"). Only the duration
changes; the condition stays `PARALYSIS` with `PARA_HYPNOTIZED`.

One non-spell duration converts in this bead (ruled 2026-10-23): the Dirty
Fighting blindness (master src/Fight.cpp, the Dirty Fighting block) becomes
`RoundsToUnits(Dice::Roll(1,4,1))`, matching the feat text "1d4+1 rounds"
(src/FeatTab.cpp:1479). It is an upstream defect: it gets an `upstream:` mark
and a docs/REPORTING-GATE.md ledger row. The small-barbarian rage penalty is
already converted on master (189d53a6, inc-trfo).

Music of the Spheres conditions (pspells.irh:5216, 5241) go through
`ThrowDmg` to `AD_CONF`, `AD_NAUS` and `AD_STUN`, which halve them since
inc-trfo; `AD_SLOW` (master Fight.cpp:8647) ignores the value. Ruled
2026-10-23: the god's condition lasts 1 round per caster level, converted
with `RoundsToUnits`, for all four gods. The choir already adds to the caster
level and MUST NOT add a separate duration bonus (drop `2*choir`). Slow MUST
last the same length as the other three conditions; the change MUST NOT alter
the length of slow from any other source. `tools/check_music_spheres_area.sh`
changes its expected condition length to match.

### 5c. Fixed durations

| Spell | Duration |
|---|---|
| Chill Metal (pspells.irh:2238), Heat Metal (pspells.irh:2293) | 4 units at every caster level, set by the spell's handler. Per-turn damage is unchanged. |
| Dancing Lights (wspells.irh:1438) | 5 units at every caster level. Its globes (wspells.irh:~1480, 1487) are unchanged. |
| Vampiric Touch (wspells.irh:5029) | Unchanged (ruled 2026-10-23, superseding 2026-10-21). The spell grants no temporary hit points; its only duration is the touch charge, which keeps `EF_DLONG`. Its healing MUST NOT change. |

Every duration that a script sets in sections 5a and 5c keeps the same
metamagic rules as the duration chain in section 2: Anchor and Extend double
it, Persistent applies only at 10 units or more, and a result above 32767
becomes -2 (ruled 2026-10-23).

### 5d. Blasphemy (pspells.irh:6058)

Blasphemy becomes the SRD spell (d20srd.org/srd/spells/blasphemy.htm). It
affects nonevil creatures in range by Hit Dice against caster level, with no
save, and the effects stack:

- HD equal to CL: dazed 1 round (2 units, the `EF_D1ROUND` value).
- HD up to CL-1: also weakened, -2d6 Str for 2d4 rounds, converted with
  `RoundsToUnits` (a temporary penalty, not ability damage; confirm on the SRD
  page).
- HD up to CL-5: also paralyzed 1d10 minutes (5-50 units).
- HD up to CL-10: also killed; undead destroyed.
- HD above CL: unaffected.
- Nonevil extraplanar creatures are banished (Will save at -4).

This replaces the CR-against-CL+Cha power, the half power against neutrals,
the stun 1d4/3d6 and the `AD_DAST` 2d6.

## 6. Kept as deliberate differences

| Spell | Kept |
|---|---|
| True Strike (wspells.irh:792) | `EF_DXLONG`; waits for its one attack |
| Moment (pspells.irh:1462) | `EF_DXLONG`; waits for its one skill roll |
| Wall of Ice (wspells.irh:4027) | `EF_DLONG`; the ice melts |
| Suggestion (wspells.irh:4512) | default 10+2×CL; a game-original spell |
| Baleful Polymorph (pspells.irh:5049) | `EF_DXLONG`; a full rest, XP awards or Dispel Magic end it |
| Every other spell not named in this spec | its current duration |

## 7. Out of scope

- Concentration spells: inc-59lq owns their mechanic and durations
  (Phantasmal Force, Improved Phantasmal Force, Spectral Force, Improved
  Spectral Force, Advanced Illusion, Hypnotic Pattern, Telekinesis, Wall of
  Fire, and Mirage Arcana's 1 hour/level).
- Creature summons: inc-n470 (Monster Summoning, Summon Nature's Ally, Holy
  Summoning, Summon Swarm, Summon Shadows, Shadow Monsters, Demi-Shadow
  Monsters, Shades, Dust Devil, Giant Vermin, Verdant Aid, Conjure Vortex,
  Lesser Planar Conjuration, Conjure Oozes). inc-n470 decides which of these
  are creature summons.
- Roark's shop stock for Wall of Stone and Baleful Polymorph: inc-9lwd
  (Dispel Magic scroll, Transmute Rock to Mud scroll, pickaxes).
- Items that are not spells, and tick-based timers (hunger, `MENACE_DURATION`).
- Combat code that is not a spell, such as the rounds dice at master
  src/Fight.cpp:7370 (small-race rage penalty) and 7509 (blindness). No bead
  owns these yet (section 11).

## 8. Player text

Every Desc that states a changed duration changes: Hideous Laughter,
Neutralize Poison, Unholy Blight, Chaos Hammer, Othello's Irresistable Dance,
Ghoul Touch, Cause Fear, Hypnotism, Chill Metal, Heat Metal, Divine Sacrifice,
Blasphemy, and any other the implementers report. Claude drafts each text and
Brian approves it one paragraph at a time. An implementer pastes only
approved text.

## 9. Verification

- A probe (`INCURSION_DURATION_PROBE`, in the style of the other probe hooks)
  prints the computed duration of a named spell at caster levels 1, 6 and 20,
  with and without Extend. `tools/check_spell_durations.sh` runs it in the
  headless build and compares the values with this spec.
- The check MUST go red: break one class formula, rebuild, see the failure,
  restore.
- Each changed spell is measured before (on master) and after, in the same
  seeded run. The table goes in the commit body.
- `tools/check_music_spheres_area.sh` passes, with its expected value set by
  the section 11 ruling.
- The gate (`tools/finish_bead.sh`) runs before the merge.
- Commit lane: `rules:`, naming design bead inc-nt3z.

## 10. Phases

Each phase is one implementer run, in the order of
`.claude/rules/codex-dispatch-and-orchestration.md`. Claude reviews each diff
before the next phase.

0. Merge master into the inc-nt3z branch. The worktree lacks inc-trfo and
   `EF_FIXED_PRICE`.
1. Engine: the four flags, the duration chain, the 32-bit overflow rule, the
   AI and help readers, the probe and `tools/check_spell_durations.sh`
   (section 2, section 9).
2. Buffs: sections 3a and 3b.
3. Class flags: section 4.
4. Dice in rounds and fixed durations: sections 5a and 5c.
5. Script dice already in rounds: section 5b, with the path trace.
6. Blasphemy rules: section 5d.
7. Player text: section 8, after Brian approves each paragraph.
8. Before/after measurement over every changed spell, and the gate.

## 11. Open rulings

Every item below is ruled.

1. Music of the Spheres god condition: RULED 2026-10-23, see section 5b.
2. Consecrate: RULED 2026-10-23, see section 4.
3. Spectral Hand: RULED 2026-10-23, see section 4.
4. Emotion: Despair: RULED 2026-10-23, see section 5b.
5. Non-spell rounds dice in combat code: RULED 2026-10-23, see section 5b.
6. RULED 2026-10-23: the monster pre-buff rule for the new flags stands as
   written in section 2 (monsters stop pre-casting Polymorph Self); flags are
   set directly, with costs raised, per section 3b; every unnamed spell keeps
   its duration (section 6), with no sweep for audit misses.

## Appendix A. File and line for section 4

| Spell | File:line | Old flag |
|---|---|---|
| Grease | wspells.irh:595 | none |
| Halt Undead | wspells.irh:1575 | none |
| Hold Person | wspells.irh:4448 | none |
| Hold Monster | wspells.irh:7810 | none |
| Hold Beast | pspells.irh:2349 | none |
| Slow | wspells.irh:5291 | none |
| Confusion | wspells.irh:6164 | none |
| Fear | wspells.irh:6264 | none |
| Glitterdust | wspells.irh:2094 | none |
| Dominate Animal | pspells.irh:3396 | `EF_DLONG` |
| Dominate Reptile | mon1.irh:752 | `EF_DLONG` |
| Wind Wall | wspells.irh:2151 | `EF_DLONG` |
| Hideous Laughter | wspells.irh:2657 | `EF_DSHORT` |
| Ethereal Jaunt | pspells.irh:4098 | none |
| Dispel Evil | pspells.irh:4685 | none |
| Spiritual Hammer | pspells.irh:2175 | `EF_DLONG` |
| Flaming Sphere | pspells.irh:2457 | `EF_DLONG` |
| Calm Emotions | pspells.irh:1826 | `EF_DLONG` |
| Divine Sacrifice | pspells.irh:1151 | none |
| Wall of Fog | wspells.irh:676 | `EF_DLONG` |
| Sleep | wspells.irh:953 | `EF_DLONG` |
| Deep Slumber | wspells.irh:4437 | `EF_DLONG` |
| Bane | pspells.irh:83 | `EF_DLONG` |
| Doom | pspells.irh:381 | `EF_DLONG` |
| Polymorph Other | wspells.irh:6877 | `EF_DXLONG` |
| Polymorph Self | wspells.irh:5325 | `EF_DLONG` |
| Reduce | wspells.irh:1665 | none |
| Mirror Image | wspells.irh:2921 | none |
| Clairvoyance | wspells.irh:4224 | none |
| Solid Fog | wspells.irh:5758 | none |
| Crushing Despair | wspells.irh:6300 | none |
| Dimensional Anchor | wspells.irh:7067 | none |
| Faerie Fire | pspells.irh:1052 | none |
| Change Self | wspells.irh:1419 | none |
| Web | wspells.irh:2177 | none |
| Fire Seeds | pspells.irh:5447 | `EF_DLONG` |
| Charm Person | wspells.irh:886 | `EF_DLONG` |
| Holy Smite | pspells.irh:4528 | `EF_DSHORT` |
| Order's Wrath | pspells.irh:4582 | `EF_DSHORT` |
| Command | pspells.irh:245 | `EF_DSHORT` |
| Charm Monster | wspells.irh:6148 | `EF_DLONG` |
| Dominate Person | wspells.irh:7795 | `EF_DLONG` |
| Dominate Monster | wspells.irh:9329 | `EF_DLONG` |
| Control Plant | pspells.irh:4389 | `EF_DLONG` |
| Consecrate | pspells.irh:1879 | `EF_DLONG` |
| Spectral Hand | wspells.irh:3300 | none |
| Wall of Stone | wspells.irh:7533 | `EF_DLONG` |
