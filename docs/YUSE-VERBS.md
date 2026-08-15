# The Yuse menu (`y`) — every verb, and whether it does anything

The `y` command opens a verb menu: *"What do you want to do?"* It holds 63
entries and is the only route to several actions that have no key of their
own, **Mount** among them.

The game does not document it. `lib/help.irh` mentions the menu once, in
passing, under mounted combat. There is no command listing for it in the
manual, in the help topics, or anywhere else. This file is that listing.

**24 of its 57 distinct verbs are not implemented at all.** They prompt you,
take your target, and then do nothing. That is the single most useful fact
here, and it is not discoverable except by trying them.

---

## How the menu works

The verbs live in `YuseCommands[]`, `src/Tables.cpp:3031-3352`. Each entry
carries up to three prompts and a flag word:

```c
{ EV_APPLY, "Apply", "applied",
     /* ETarget */ Q_INV|Q_TAR|Q_NEAR, "What do you want to apply it to?",
     /* EItem1  */ Q_INV|Q_OPT,        "What do you want to apply?",
     /* EItem2  */ 0, NULL,
     /* Flags   */ YU_REVERSE },
```

- **The prompts run in table order**, target first, unless the entry carries
  `YU_REVERSE`, which asks for the item first. `src/Player.cpp:1472`.
- **`Q_INV` reaches inside containers.** The item picker walks
  `FirstInv`/`NextInv`, which descends into packs (`src/Inv.cpp:809`), so
  verbs offer packed items without you unpacking them.
- **The five most recent verbs float to the top** of the menu
  (`src/Player.cpp:1454`), so the list reorders as you use it.
- **Verbs can be bound to Quick Keys** (`QKY_VERB`, `src/Player.cpp:1463`).
  Worth doing for Mount if you ride.
- **Ten social verbs refuse non-creatures** with *"Don't socialize with the
  furniture."* (`src/Player.cpp:1489`).

### What happens when you pick an unimplemented verb

The event is thrown, nothing handles it, and it falls through to
`Creature::HandleVerb` (`src/Player.cpp:1542` via `src/Creature.cpp:910`).
That prints **"That verb can't be used that way."** for post-phase events and
otherwise returns silently. So a dead verb costs you the prompts and gives
you either that message or nothing at all.

---

## Implemented — 33 entries

### Social verbs

All twelve live in `src/Social.cpp`. Each is **hidden from the menu unless
its conditions hold** (`src/Social.cpp:138-200`), so a verb you cannot see is
usually a verb that does not apply to that creature rather than one that is
missing.

| Verb | What it does | Only offered when |
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
missed, because they vanish the moment a creature turns hostile or friendly.

### Items, features and movement

| Verb | What it does | Handler |
|---|---|---|
| Activate | trigger an item's power | `src/Item.cpp:796` |
| Drink | drink a potion | `src/Item.cpp:773` |
| Eat | eat food | `src/Item.cpp:1847` |
| Read | read a scroll or book | `src/Item.cpp:780` |
| Zap | aim a wand at a target | `src/Item.cpp:766` |
| Wield | equip a weapon | `src/Creature.cpp:827` |
| Shoot / Throw | ranged attack — **one event**, `EV_RATTACK` | `src/Creature.cpp:734` |
| Insert | put an item into a container | `src/Inv.cpp:1106` |
| Divide | split a stack; refuses singular items; the new stack is `DROPPED` for 10 turns | `src/Player.cpp:1544` |
| Open / Open With | doors and containers | `src/Feature.cpp:417` |
| Close | shut a door | `src/Feature.cpp:532` |
| Enter | portals and the like | `src/Feature.cpp:218` |
| Break | break a target | `src/Creature.cpp:891` |
| Push | shove a target | `src/Creature.cpp:695` |
| Dig | dig in a direction | `src/Creature.cpp:851` |
| Talk | open conversation | `src/Creature.cpp:618` |
| **Mount** | ride a creature — full validation, see below | `src/Creature.cpp:868` |
| **Dismount** | get off; takes no target | `src/Creature.cpp:872` |

### Three that work but are narrower than they look

These have handlers, so the survey counts them implemented — but each covers
far less ground than its name suggests. Verified by reading the script.

- **Apply** (`lib/mundane.irh:41`) is a potion mechanism. Its hook copies the
  item's effect onto the event, so it means "apply this potion's effect to
  that target".
- **Dip** (`lib/dungeon.irh:2163`) has exactly one handler, and it is on
  fountains. Dipping into anything else has nothing behind it.
- **Fill / Pour** (`lib/mundane.irh:640`) — the only combination implemented
  is refilling a **brass lantern** from a **flask of oil**. Both verbs share
  that one handler.

Three notes on individual verbs:

**Divide** splits a stack, and refuses singular items with *"Singular items
cannot be divided."* The new stack is marked `DROPPED` for 10 turns
(`src/Player.cpp:1544`).

**Mount** is the only way to ride a creature. It runs a full validation path
— Ride skill, humanoid form, the target's `M_MOUNTABLE` flag, hostility,
prone/stuck/asleep, plane, and whether the creature will accept you at all
(`src/Skills.cpp:4191`).

**Shoot and Throw are the same event**, `EV_RATTACK`, differing only in
prompt wording.

---

## Not implemented — 24 distinct verbs, 27 entries

These have **no handler in `src/` and no `On Event` in `lib/`**. The event
constants appear only in the verb table and in the constant-name lists.

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
