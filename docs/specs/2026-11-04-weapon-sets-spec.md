# Weapon sets: a four-set Exchange command (inc-h5aql)

## Goal

A player MUST be able to change between four weapon sets with one key, and
MUST NOT need the pack to do it. The sets are:

| Set | Role | Main item |
|---|---|---|
| R | Ranged | a bow (`T_BOW`), as the `R` default is today |
| X | Extended reach | a weapon with `WT_REACH` |
| M | Melee | a melee weapon |
| S | Short | a weapon for grapples and engulfing (passes `Weapon::useInGrapple`) |

The fixed order is R → X → M → S, and the order wraps from S to R.

The game already has a two-set swap: Exchange, key `-` (`KY_CMD_EXCHANGE`,
`Character::Exchange`, `src/Inv.cpp:957`). It toggles between `defMelee` (plus
`defOffhand`) and `defRanged`. This work extends Exchange. It does not add a
second swap command.

## 1. What a set holds

- Each set holds one main item and one optional off-hand item.
- A set can take an off-hand item only when its main item leaves a hand free.
  A two-handed weapon or a bow cannot have one. Use the engine's existing
  two-hand test from `Character::Wield`; do not write a second one.
- A set item MUST be in an equipment slot (hand, shoulder, belt), not in a
  container, as `Exchange` requires today. Keep the existing stow rule: the
  old item goes to the first free slot of `SL_LSHOULDER`, `SL_RSHOULDER`,
  `SL_BELT1..5`.
- Belt slots accept a melee weapon (`T_WEAPON`) up to the wearer's own size
  (`Item::allowedSlot`, `src/Item.cpp:1103`); every other item keeps the old
  limit. A Medium character can then hold a bow and a polearm on the shoulders
  and a sword and a dagger on the belt. This is a `rules:` change.
- Before anything moves, a swap checks that every item it puts away has a
  legal slot. If one has none, the swap changes nothing, takes no time, and
  prints one line. It never drops an item.
- A set with no main item is "not configured", except M for a character with
  Martial Mastery or Unarmed Strike: bare hands are its main item. Every rule below skips it.
- A stale handle is cleared on use, as `Exchange` does today with
  `theRegistry->Exists` (`src/Inv.cpp:962-964`).

## 2. Configuring the sets (inventory screen, `src/Managers.cpp:1061-1114`)

- `R`, `X`, `M`, `S` on the selected item make it the main item of that set.
  A second press on the same item clears it. Each key accepts only an item
  that fits its role (table above). `X` and `S` are free on that screen today.
- An item can be the main item of one set only. Assigning it to a set clears
  it from any other set, as `M` and `R` clear each other's fields today.
- `O` on the selected item opens a short list of the configured sets that can
  take an off-hand item, and the player picks one. The list MUST show only
  those sets. A set's off-hand item is cleared by `O` on the same item for the
  same set.
- `A` (ammo) does not change.

## 3. The `-` key

Definitions:

- **Aware enemy**: a creature the player `Perceives()` (`inc/Creature.h:444`,
  sight, scent, shadow or detection), that the player can know is hostile.
  The hostility test MUST use only what the player can know. An enemy the
  player cannot sense, or a hostile creature the map shows as not hostile,
  MUST NOT count. If the engine has no player-visible hostility test, the
  implementer stops and reports; it does not invent one.
- **Melee range**: the farthest distance the X set can hit. Use the engine's
  own reach range (the `vRange` logic at `src/Player.cpp:1297-1300`), not a
  hard-coded 2.
- **Target**: the nearest aware enemy within melee range. The engine keeps no
  record of the creature the player attacked last, so a tie goes to the first
  creature found in map order.
- **Can hit**: the set's main item can attack the target from the player's
  square, by the engine's own checks: `isReachOnly()` (`inc/Item.h:136`),
  `WT_STRIKE_NEAR`, `MS_HAS_REACH`, and the grapple test at
  `src/Fight.cpp:1190-1196`. Do not copy the conditions. Call or factor out
  the same functions, so a weapon added later with the same flags behaves the
  same with no new code.

Rules, in order:

1. **Grabbed, grappled, grappling or engulfed**: step forward through
   R → X → M → S from the current set, and take the first configured set
   whose main item the engine lets the player use in that state.
2. **An aware enemy is in melee range**: step forward through R → X → M → S
   from the current set, and take the first configured set that can hit the
   target. Examples: target adjacent, X is reach-only: the cycle is
   M → S → R. Target adjacent, X has `WT_STRIKE_NEAR`: X is included.
3. **No aware enemy is in melee range**: step forward through all configured
   sets, R → X → M → S.

"Current set" means the set whose main item is in `SL_WEAPON`. If the wielded
item belongs to no set, start the step at R.

When rule 1 or rule 2 finds no set other than the current one, `-` changes
nothing, takes no time, and prints one line. The text is drafted later and
approved by Brian (section 7).

## 4. Forcing a set (C menu, `src/Player.cpp:1119`)

- Add one row, "Switch Weapon Sets", to the combat options menu. Its
  prerequisite hides it when no set is configured.
- The row opens a submenu that lists only the configured sets, and not the
  current set.
- A choice wields that set at once, at any time. It skips the range test and
  the grapple test of section 3; the engine still refuses an attack the
  weapon cannot make. It costs the same time and provokes the same attack of opportunity as `-`.

## 5. Time and attacks of opportunity

- Time: keep the current Exchange cost (`src/Inv.cpp:1176-1188`).
- Attack of opportunity: under the SRD 3.5 action table, sheathing a weapon
  provokes one and drawing a weapon does not. Today no wield, take-off or
  Exchange path calls `ProvokeAoO` (Traced: every call site in `src/` read).
  After this change:
  - `-` and the forced switch provoke one attack of opportunity when they put
    away a held weapon. A switch from an empty hand provokes none.
  - Taking a weapon off in the inventory screen (`Character::TakeOff`,
    `src/Inv.cpp:455`) provokes one.
  - The fix is a base-code defect fix: it gets the `upstream:` comment, a row
    in `docs/REPORTING-GATE.md`, and the bead gets the `upstream` label.

## 6. Saves

- Add the new set fields to the `Character` archive block (`inc/Creature.h`,
  tags 384-511) as new `FIELD_H` entries on free tags. Do not change the
  meaning of tags 385-388 (`defMelee`, `defRanged`, `defAmmo`, `defOffhand`).
- Update the coverage pin row and the static asserts in `src/SaveV1.cpp`.
- The epic `inc-pu6v` also adds `Character` fields. The implementer records the
  tags chosen, so the merge of master into the epic can check them.
- An old save loads with: M main = `defMelee`, M off-hand = `defOffhand`,
  R main = `defRanged`, X and S not configured. An old character's `-` then
  behaves as today until X or S is set.

## 7. Player-facing text

Every new or changed player-facing line goes to Brian one paragraph at a time
for approval before it lands (`feedback-one-paragraph-at-a-time`):

- the help entry for Exchange (`lib/help.irh:1321-1329`) and the default-weapon
  help (`lib/help.irh:993-1008`);
- the inventory-screen key hints for `X` and `S`, and the `O` set list prompt;
- the C-menu row's help text and the submenu labels;
- the "no other set can reach" message.

## 8. Acceptance criteria

- AC1: With R, X, M and S configured and no aware enemy in melee range, `-`
  steps R → X → M → S → R.
- AC2: With an aware enemy adjacent and a reach-only X, `-` from R gives M, from
  M gives S, from S gives R; X is never chosen.
- AC3: With a `WT_STRIKE_NEAR` reach weapon as X and an aware enemy adjacent,
  X is in the cycle.
- AC4: With an aware enemy 2 squares away, M and S are skipped.
- AC5: An enemy the player does not perceive changes nothing in AC1-AC4.
- AC6: While grappled, `-` chooses only a set that passes the grapple test;
  with none other than the current set, it prints the line and takes no time.
- AC7: The C menu shows "Switch Weapon Sets" only when a set is configured,
  and its submenu lists only configured sets.
- AC8: `-`, the forced switch and an inventory take-off with a held weapon
  each provoke an attack of opportunity; observed before (none) and after.
- AC9: An old save loads with its melee, off-hand and ranged defaults in M and
  R, and `-` behaves as before.
- AC10: A new save with all four sets round-trips through save and load.
- AC11: Brian approved every text in section 7.
