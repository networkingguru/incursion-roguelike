# Weapon sets: plan brief (inc-h5aql)

Goal, design and acceptance criteria: `docs/specs/2026-11-04-weapon-sets-spec.md`
(cited below as "spec §N"). Stack: C++ engine, `BACKEND=posix ./build_macos.sh`,
`tools/headless.sh` checks.

## Files touched

| File | Change |
|---|---|
| `tools/check_weapon_sets.sh`, `tools/keys/weapon-sets-*.keys` | The check: one assertion per spec §8 criterion. Red before the change. |
| `inc/Creature.h` | New set fields on `Character`, archive tags (spec §6). |
| `src/SaveV1.cpp` | Pin row, static asserts, old-save conversion (spec §6). |
| `src/Managers.cpp` | `R`/`X`/`M`/`S` main-item keys, `O` set picker (spec §2). |
| `src/Inv.cpp` | `Exchange` rewritten to four sets and the section-3 rules; attack of opportunity on sheathe in `Exchange` and `TakeOff` (spec §3, §5). |
| `src/Fight.cpp`, `inc/Item.h` | Factor the "can this weapon hit that square" test out of the attack path so `Exchange` calls the same code (spec §3). |
| `src/Player.cpp` | C-menu row and submenu (spec §4). |
| `lib/help.irh`, `src/Help.cpp`, `src/Tables.cpp` | Help and labels, after Brian approves the text (spec §7). |
| `docs/REPORTING-GATE.md` | Ledger row for the attack-of-opportunity fix. |

## Phases (one commit each)

1. **Check (red).** Write `tools/check_weapon_sets.sh` from a loaded character
   fixture. Run it on the unchanged build: the four-set and attack-of-opportunity
   assertions MUST fail, the old-save assertion MUST pass.
2. **Saves.** Add the set fields and the old-save conversion. Verify: save
   round trip, old fixture loads with M and R filled.
3. **Configure.** Inventory-screen keys and the `O` picker. Verify: headless
   key script sets all four sets.
4. **Exchange.** The shared hit test and the section-3 rules. Verify: check
   assertions AC1-AC6 green.
5. **C menu.** Row and submenu. Verify: AC7 green.
6. **Attack of opportunity.** Sheathe provokes in `Exchange`, forced switch and
   `TakeOff`; `upstream:` mark and ledger row. Verify: AC8 red before, green after.
7. **Text.** Draft each text of spec §7, one paragraph at a time, to Brian. Land
   only approved text. Verify: AC11.

## Test plan

- Adversarial: unset sets, a stale handle, a cursed wielded weapon, a
  two-handed main item with an off-hand assigned, an item assigned to two sets,
  an invisible adjacent enemy, a neutral adjacent creature, grappled with no
  usable set, engulfed.
- User: a fighter with all four sets swapping through a fight with a goblin
  that closes from range to adjacent and grabs.
- Live: Brian plays the epic build after the merge.
- Gate: `tools/nightly_verify.sh --compare` and `tools/finish_bead.sh`.
