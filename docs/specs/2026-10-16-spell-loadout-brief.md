# Spell loadout checklist and rest re-memorization (inc-j5yo) — brief

**Goal.** Replace the one-pick Learn Spell menu with one checklist screen. A Mage's arcane selection is pending and takes effect at the next full rest, checked against the books it carries then. Other casters keep permanent learning.

**Spec.** The settled design is the description and notes of bead inc-j5yo (owner rulings, 2026-10-16). This brief does not repeat it; "spec §Layout" etc. names its headings. inc-q04n (cast-time book check, scroll formulas) is a separate bead that lands after this one.

**Architecture.**
- `SP_KNOWN` keeps one meaning: memorized now, castable. Casting code does not change in this bead.
- New flag `SP_PENDING` (0x1000): the arcane selection for the next rest.
- New flag `SP_GRANTED` (0x2000): a spell given by a script grant. It uses no slot, needs no book, and is locked on the screen.
- `SpellsLearned[l]` keeps its meaning: slots at level l held by slot-using spells. It stays incremental. The rest step decrements it for each dropped arcane spell and increments it for each added one.
- Slot use at level l by locked (non-arcane, permanent) spells = `SpellsLearned[l]` minus the count of memorized arcane spells at l that are not `SP_GRANTED` and not `SP_DOMAIN`.
- The level of an arcane spell is its level on the arcane list from `CalcSpellAccess()`.

**Stack.** C++ (src/, inc/), IncursionScript (lib/classes.irh), headless harness (tools/).

## Files touched

| File | Change |
|---|---|
| `inc/Term.h` | `LMenuOption` gains a flags field (header, locked, color) and a group cap. Declares the extended `LMultiSelect` behavior. |
| `src/TextTerm.cpp` | `LMultiSelect` (1335-1558) gains: header rows that cannot be marked and that the cursor skips; a cap per header group (a mark is refused when the group's marks reach the cap, with a message); live header text that shows the current count; per-row color; Tab jumps to the next header; MO_CREATE record and MO_RECREATE replay like `LMenu` (977); the stale-`i` lowercasing bug at ~1515 fixed. |
| `inc/Defines.h`, `inc/ConstNam.h` | `SP_PENDING`, `SP_GRANTED`; a new list constant `SPECIALTY_SPELLS`. |
| `inc/Creature.h` | `GainSpell` (1421) ORs in `SP_GRANTED`. |
| `lib/classes.irh` | The Mage EV_ADVANCE school switch (993-1036) is removed. The Mage class gains a `SPECIALTY_SPELLS` list: two spells per school, in school order 0-8. |
| C++ advance path | At Mage level 1, after the class EV_ADVANCE event, grant the two spells for `SPECIALTY_SCHOOL` from that list with `GainSpell`. The list is the one copy, read by the grant and by the migration. |
| `src/SaveV1.cpp` | `SCHEMA_REV` 4 -> 5. After load, when the file revision is below 5: set `SP_GRANTED` on each known arcane spell found in the player's specialty list, then set `SP_PENDING` on every known arcane spell that is not `SP_GRANTED` or `SP_DOMAIN`. |
| `src/Create.cpp` | `LearnSpell` (5792-5963) rewritten over the checklist (spec §Layout, §Which spells the screen lists, §Classes that do not re-memorize). The chargen loop (1345) keeps forcing level-1 slots full, and creation-mode marks commit at once (spec §When changes apply). |
| `src/Player.cpp` | `Player::Rest`, after `LastRest = theGame->GetTurn();` (2729), only when `Percent == 100`: apply the selection (spec §Books at the rest). |
| `src/Sheet.cpp` | The slot display (375-386) shows pending versus memorized counts. |
| `lib/help.irh` | The magic help text that describes learning (3606-3614) states the new rule. |
| `tools/keys/*.keys` | Every script that answers "Learn which spell" is updated to the new screen. A new reproduction is added (Phase 6). |

## Row rules for the screen (from the spec, made exact)

- One header per spell level 1-9 that has a slot (`SpellSlots + BonusSlots > 0`). Header text: `Level N - <marked> of <slots> slots`. The cap is `SpellSlots + BonusSlots` minus slot use by locked spells; locked rows do not count against it.
- Rows: every spell the old menu would offer at that level ignoring the "already known" and "open slot" filters, plus every memorized or pending spell. The elf, alignment and chart-level filters stay.
- Row state text, shown as words as well as color (color alone fails color-blind players): `memorized` when `SP_KNOWN`; `locked` when the spell is non-arcane known, `SP_GRANTED` or `SP_DOMAIN`; `(no book)` when arcane and no carried item `HasSpell` it.
- Mark state on open: `SP_PENDING` for arcane; `SP_KNOWN` for everything else.
- A mark on a `(no book)` row is refused with a message. An unmark of a locked row is refused with a message.
- On confirm, Mage arcane rows set or clear `SP_PENDING` only. A newly marked non-arcane row sets `SP_KNOWN | type` and increments `SpellsLearned` at once, as today. In creation mode, an arcane mark sets `SP_KNOWN | SP_PENDING | SP_ARCANE` and increments `SpellsLearned` at once. `RecalcCraftFormulas()` runs after any change, as today.
- Esc discards every change made in that open.

## Rest step (Phase 5)

For each arcane spell that is not `SP_GRANTED` or `SP_DOMAIN`:
- Known but not pending: clear `SP_KNOWN`, decrement `SpellsLearned` at its level.
- Pending and a carried item `HasSpell` it: set `SP_KNOWN` if unset (and increment `SpellsLearned`); if already known, nothing changes.
- Pending but no carried book: clear `SP_KNOWN` if set (and decrement); keep `SP_PENDING`; name the spell in one message after the loop.
Then `RecalcCraftFormulas()`. A rest with `Percent < 100` or the interruption path changes nothing.

## Phases (one commit each; each is a separate implementer run)

1. **Menu rendering.** Implement the `LMenuOption` flags, header rows, cursor skipping, per-row color in `LMultiSelect`. Verify: build; a probe behind `INCURSION_MULTISELECT_PROBE` opens a fixed eight-row menu in a headless run, and a screen dump shows headers and colors.
2. **Menu behavior.** Group caps with refusal message, live header counts, Tab, MO_CREATE/MO_RECREATE, the stale-`i` fix. Verify: the same probe with a key script that tries to over-mark a group, Tab, and confirms; a dump shows the refusal and the final marks.
3. **Flags and grants.** `SP_PENDING`, `SP_GRANTED`, `GainSpell` change, `SPECIALTY_SPELLS` list, the C++ grant, removal of the script switch. Verify: a fresh Evoker and a fresh Necromancer from key scripts know the same two spells as before (character sheet dump compared with master).
4. **Migration.** `SCHEMA_REV` 5 and the post-load step. Verify: load `tools/fixtures/chars/orc-mage-seed1-opt0822.sav`; its spells keep `SP_KNOWN`, gain the expected flags; a save and reload of that game does not migrate twice.
5. **LearnSpell and rest.** The `LearnSpell` rewrite, the chargen loop, the rest step, the sheet display, the help text. Verify: Phase 6's reproduction.
6. **Reproduction and key scripts.** New `tools/keys/mage-loadout-rest.keys` plus the updated existing scripts and any fixture the change rewrites (`tools/make_char_fixture.sh`). Verify: see test plan.

## Test plan

- **Oracle (red before green).** `mage-loadout-rest.keys` from a loaded Mage fixture: open the screen, unmark a memorized spell, mark a book spell, confirm, try to cast the new spell (refused: not memorized), rest with safe rest, cast it (succeeds), try the dropped spell (refused). Mutation: disable the rest step; the script must go red.
- **Adversarial.** Mark past a full level (refused); mark a `(no book)` row (refused); unmark a specialty spell (refused); drop the book, rest (spell not memorized, message names it, pending stays), pick the book up, rest (memorized); interrupted rest (nothing changes); a slot gained mid-day stays empty until the rest; Esc discards; an elf still sees no necromancy.
- **User.** A full re-memorization that keeps the loadout is: open sheet, `L`, Enter. A Priest sees learned spells locked and can fill an empty slot at once. A Mage/Priest sees arcane rows unlockable and divine rows locked. Chargen still forces level-1 slots full, and "create a similar character" replays the picks.
- **Regression.** `tools/nightly_verify.sh --compare` through `tools/finish_bead.sh`; every key script that touched the old menu still finishes.
- **Playtest.** Brian plays a Mage through a swap and a rest (acceptance criterion).
