<!-- citations: this-port -->

# The Yuse menu (`y`) — every verb, and whether it does anything

The `y` command opens a verb menu: *"What do you want to do?"* Its table holds
63 entries, it offers you the ones your character can actually use, and it is
the only route to several actions that have no key of their own, **Mount**
among them.

The game documents the command but not its contents. `lib/help.irh` gives the
`y` key its own help entry (`lib/help.irh:1272`) and names the menu again
under Quick Keys, Dip, mounted combat and oils. None of those lists
the verbs. There is no verb listing in the manual, in the help topics, or
anywhere else. This file is that listing.

**24 of its 57 distinct verbs have no implementation**, filling 27 of the 63
entries. The menu no longer offers them: `Player::YuseMenu` drops any entry
whose `MissingImplementation` flag is set (`src/Player.cpp:1597-1604`,
`inc/Creature.h:41`). Until that gate was added, a dead verb was offered like
every other, took your prompts and your target, and did nothing. They are
listed below because the table still carries them, and because which verbs are
dead is what this file exists to record.

Derive the menu size, the distinct verb count, and how many of them are dead:

```sh
sed -n '3129,3447p' src/Tables.cpp | grep -c '^  { EV_'
sed -n '3129,3447p' src/Tables.cpp | grep '^  { EV_' |
    sed 's/^  { \(EV_[A-Z_]*\),.*/\1/' | sort -u | wc -l
sed -n '3129,3447p' src/Tables.cpp |
    awk '/^  \{ EV_/ { match($0,/EV_[A-Z_]+/); v=substr($0,RSTART,RLENGTH) }
         /true *\}/ { print v }' | sort -u | wc -l
```

---

## How the menu works

The verbs live in `YuseCommands[]`, `src/Tables.cpp:3129-3447`. Each entry
carries up to three prompts and a flag word:

```c
{ EV_APPLY, "Apply", "applied",
     /* ETarget */ Q_INV|Q_TAR|Q_NEAR, "What do you want to apply it to?",
     /* EItem1  */ Q_INV|Q_OPT,        "What do you want to apply?",
     /* EItem2  */ 0, NULL,
     /* Flags   */ YU_REVERSE },
```

- **The menu is built from what your character can do.** `Player::YuseMenu`
  walks the table and drops an entry on either of two rules: its
  `MissingImplementation` flag is set, or it carries a `Prerequisite` predicate
  that returns false for you (`src/Player.cpp:1597-1604`). Two entries carry a
  prerequisite today: **Mount** needs the Ride skill, a humanoid body with
  limbs, and no mount under you already; **Dismount** needs you mounted
  (`src/Tables.cpp:3118-3127`). If nothing survives both rules the command
  says *"You have no usable verbs."* `tools/check_command_menu_gating.sh`
  reads the `y` screen and fails if a dead verb is on it.
- **The prompts run in table order**, target first, unless the entry carries
  `YU_REVERSE`, which asks for the item first. `src/Player.cpp:1621`.
- **`Q_INV` reaches inside containers.** The item picker walks
  `FirstInv`/`NextInv`, which descends into packs (`src/Inv.cpp:814`), so
  verbs offer packed items without you unpacking them.
- **The five most recent verbs float to the top** of the menu
  (`src/Player.cpp:1584`), so the list reorders as you use it. A recent verb
  is gated the same way as any other, so it drops off the top when it stops
  applying.
- **Verbs can be bound to Quick Keys** (`QKY_VERB`, `src/Player.cpp:1611`).
  Worth doing for Mount if you ride.
- **Ten social verbs refuse non-creatures** with *"Don't socialize with the
  furniture."* (`src/Player.cpp:1648`).

### What an unimplemented verb does if something else throws it

You cannot pick one from this menu any more, because the menu does not list it.
The path is still there for an event thrown by any other route: nothing handles
it, so it falls through to `Creature::HandleVerb` (`src/Player.cpp:1735` via
`src/Creature.cpp:1009`), which prints **"That verb can't be used that way."**
for post-phase events and otherwise returns silently.

---

## Implemented — 33 distinct verbs, 36 entries

### Social verbs

All are implemented in `src/Social.cpp`, and `src/Creature.cpp:720-768`
dispatches them. None of them carries a prerequisite or a
missing-implementation flag, so the `y` menu offers every one of them to every
character (`src/Player.cpp:1597-1604`). The conditions below gate the **Talk**
prompt instead: `Creature::PreTalk` (`src/Social.cpp:101`) drops a choice from
that prompt when its condition fails (`src/Social.cpp:140-198`). So a verb you
cannot see when you Talk is usually a verb that does not apply to that
creature, and you can still reach it from the `y` menu. That prompt also
offers one more choice, **Offer Terms** (`EV_TERMS`), which has no `y`
menu entry at all.

| Verb | What it does | Offered on the Talk prompt only when |
|---|---|---|
| Barter With | trade goods | not hostile, not summoned, has hands; and you have Diplomacy or CHA 13+, or it is a merchant (`M_SELLER`) |
| Cow | intimidate into backing down | target hostile and not already afraid; you have Intimidate |
| Dismiss | send a follower away | target friendly |
| Distract | pull its attention | target not friendly, not already distracted |
| Enlist | recruit it | target neither hostile nor friendly |
| Fast Talk | bluff a hostile | target hostile; you have Bluff |
| Greet | say hello | always, except your own summons |
| Order | give orders | target friendly |
| Quell | make peace | target hostile |
| Issue Request | ask a favour | target neither hostile nor friendly |
| Surrender To | yield | target hostile and not afraid |
| Taunt | enrage it | target not friendly, not already enraged |

The neutral-only verbs — Enlist and Issue Request — are the ones easily
missed, because they leave the Talk prompt the moment a creature turns hostile
or friendly.

### Items, features and movement

| Verb | What it does | Handler |
|---|---|---|
| Activate | trigger an item's power | `src/Item.cpp:846` |
| Drink | drink a potion | `src/Item.cpp:823` |
| Eat | eat food | `src/Item.cpp:1954` |
| Read | read a scroll or book | `src/Item.cpp:830` |
| Zap | aim a wand at a target | `src/Item.cpp:816` |
| Wield | equip a weapon | `src/Creature.cpp:925` |
| Shoot / Throw | ranged attack — **one event**, `EV_RATTACK` | `src/Creature.cpp:832` |
| Insert | put an item into a container | `src/Inv.cpp:1111` |
| Divide | split a stack; refuses singular items; the new stack is `DROPPED` for 10 turns | `src/Player.cpp:1745` |
| Open / Open With | doors and containers | `src/Feature.cpp:612` |
| Close | shut a door | `src/Feature.cpp:727` |
| Enter | portals and the like | `src/Feature.cpp:254` |
| Break | break a target | `src/Creature.cpp:989` |
| Push | shove a target | `src/Creature.cpp:793` |
| Dig | dig in a direction | `src/Creature.cpp:949` |
| Talk | open conversation | `src/Creature.cpp:716` |
| **Mount** | ride a creature — full validation, see below | `src/Creature.cpp:966` |
| **Dismount** | get off; takes no target | `src/Creature.cpp:970` |

### Verbs that work but are narrower than they look

These have handlers, so the survey counts them implemented — but each covers
far less ground than its name suggests. Verified by reading the script.

- **Apply** is a liquid mechanism. The potion hook (`lib/mundane.irh:41`)
  copies the item's effect onto the event, so it means "apply this potion's
  effect to that target". Nothing else answers `EV_APPLY` except three
  alchemical liquids (`lib/alchemy.irh:82`), poison from a small
  glass vial onto a weapon (`lib/mundane.irh:1016`), the weapon oils
  (`lib/m_items.irh:1480`) and the lantern below.
- **Dip** has five handlers and they cover two targets: a **fountain**
  (`lib/dungeon.irh:2180` and `:2350`, plus the Spell Storing ring at
  `lib/m_items.irh:5318`) and an **alchemical flask**, where only acid does
  anything (`lib/alchemy.irh:97` and `lib/alchemy.irh:598`). Dipping into anything else has
  nothing behind it.
- **Fill / Pour** (`lib/mundane.irh:640`) — the only combination implemented
  is refilling a **brass lantern** from a **flask of oil**, and the flask must
  already be identified. Both verbs share that one handler.

Notes on individual verbs:

**Divide** splits a stack, and refuses singular items with *"Singular items
cannot be divided."* The new stack is marked `DROPPED` for 10 turns
(`src/Player.cpp:1745`).

**Mount** is offered only to a character who could ride: the Ride skill, a
humanoid body with limbs, and no mount already under you
(`src/Tables.cpp:3118-3122`). It is the only command that rides a creature: no
key binding throws `EV_MOUNT`, and only this verb and the spells that summon a
steed do (`lib/wspells.irh:1808` and `:1903`, `lib/pspells.irh:3460`). Once
picked it runs a full validation path — Ride skill, humanoid form, the
target's `M_MOUNTABLE` flag, hostility, prone/stuck/grappled/asleep, plane,
size, challenge rating, and whether the creature will accept you at all
(`src/Skills.cpp:4254`).
**Dismount** has a second route: the Cancel (`x`) command drops a standing
`MOUNTED` stati (`src/Skills.cpp:451` and `:567`).

**Shoot and Throw are the same event**, `EV_RATTACK`, differing only in
prompt wording.

---

## Not implemented — 24 distinct verbs, 27 entries

These have **no handler in `src/` and no `On Event` in `lib/`**. The event
constants appear only in the verb table and in the constant-name lists. Check
any one of them with `grep -rn EV_BURN src/ inc/ lib/`: a dead verb answers
from `src/Tables.cpp`, `inc/ConstNam.h` and `inc/Defines.h` and nowhere else.

```
Burn        Clean       Clean With   Cut         Dissect     Examine
Force       Give        Imbue        Inscribe    Inscribe With
Jam         Mix         Play         Press       Pull        Rub
Rub With    Show        Sit          Smell       Taste       Touch
Tie To      Tie Up      Twist        Wave
```

Some of these are load-bearing gaps rather than flavour:

- **Examine** does nothing here. To examine an item in a pack, turn on
  **Use Container Cursor** (`OPT_CONTAINER_CURSOR`, default NO) and press
  `x` in the inventory screen instead.
- **Give** has no implementation, so there is no way to hand an item to a
  companion through this menu. Note `EV_GIVE_AID` is a *different* event and
  is implemented — do not confuse them when grepping.
- **Mix** is absent despite an alchemy system existing in `lib/alchemy.irh`.

---

## How this was produced, and what it does not tell you

Generated by parsing `YuseCommands[]` and cross-referencing each event
against `case EV_X:` in `src/` and `On Event`/`PRE`/`POST`/`META` in `lib/`.
Spot-checked by grepping four of the unimplemented events across the whole
tree by hand.

**This is code reading, not play-testing.** The "implemented" column means a
handler exists and is reachable, not that the verb behaves correctly or
usefully. A verb can have a handler and still be broken.

**One known limit of the method.** It finds handlers by pattern. A verb
dispatched through some path that matches neither pattern would be
misreported as dead. That is exactly the mistake that made an earlier pass
of this work claim Mount did not exist, so treat a surprising "not
implemented" as worth one hand-check before acting on it.
