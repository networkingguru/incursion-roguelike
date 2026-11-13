# AC9 merge 2: resolutions (Maeve inc-pu6v.9 head 4ac7f9d5, 50 commits of her own, takes the merged epic)

Preparation run: the merged epic is inc-ac9m (merge 1; resolutions here are applied to its tip 913971e7, and were first tried on da27203a, which the other agent has since replaced), not yet landed on inc-pu6v. `AC9_MERGE2_REF=inc-ac9m tools/pressure/ac9.sh <clone> merge2`
merges that branch; without the variable the step merges inc-pu6v and needs land1, as before.

Order: master's `tools/convert_tags_to_names.py --apply` runs on Maeve first (commit `port: convert god field tags to names (inc-pu6v.9)`, no hand edit; it
reads master's `inc/SaveLegacyTags.h` because Maeve has none). Then `git merge`. Then `tools/pressure/resolve_conflict.py`: the hunks, `post.patch`, the unchanged
mover `tools/move_branch_values.py` (0 moves), and the regenerated `lib/dispatch.h`.

Side names: HEAD = Maeve after the converter commit (6b23015f); inc-ac9m = the merged epic.
Every digit-bearing line of a resolution is copied verbatim from one side, or is named in `tools/pressure/ac9/allowances-merge2.txt`
(kinds: `move` a Maeve block moved verbatim to her landed file, `name` the bead id in a file name, `rewrite` edits that keep every existing constant).

STATUS: `ac9.sh merge2` commits the merge with the hooks on (0aefee3a), no refusal; the build passes (`order check: ok`); `ac9.sh attrib2` says NUMBERS-BY-HAND PASS. The mover moves 0 values.

## Hunks

| File | Hunks | Choice | Reason |
|---|---|---|---|
| docs/REPORTING-GATE.md | 1 | inc-ac9m | Maeve's side is one row (the `Thing::Remove` row); inc-ac9m holds that same row, byte for byte, with the epic's rows around it. |
| inc/Creature.h | 6 | inc-ac9m | Every hunk is master's or the epic's change beside a line the converter changed on Maeve's side (`FIELD_SKIP(LightAverseWasBright)`, `defReach..defShortOff`, `SK_COUNT`, `FEATBITS_LAST`, the `*Row` fields and `FIELD_ARRAY_ROWS`, `Spells`, `SacValsRow`, `MA_COUNT`). Maeve's own `Character` members (`AidWaitEnd`, `exAidWaitStart`, `exFavPenalty`, `exPrayerTimeout`, `HateLev`, `GodlessXP`, `lastPulse`, `godFlags`, `desiredAlign`) stay outside the hunks. Hunk 4: `V1CharSpellsAid` goes, as in merge 1: master's `FIELD_ARRAY("Spells", ...)` reads the field Maeve's branch read through it. |
| inc/Res.h, src/Base.cpp | 1 each | inc-ac9m | `V1Str("Migrations", ...)` block and `V1ProbeScope("Array")`; Maeve's side is empty there. |
| lib/dispatch.h | generated | regenerated | `BACKEND=posix ./build_macos.sh`, twice. |
| lib/main.irc | 1 | inc-ac9m (empty), then `post.patch` | The epic moved the end of `main.irc` to `lib/landed-inc-pu6v.irh` (no-shared-tail). Maeve's side of the hunk is that same old end. Her own additions to `main.irc` (six `Encounter "exact ... dragon"` entries, Template `"Fierce"`) go to the new `lib/landed-inc-pu6v.9.irh`, text unchanged, and `lib/landed.irc` includes it after `landed-inc-pu6v.irh` (see "Landed file"). |
| lib/religion.irh | 1 | Maeve | Maeve's redesign replaced the old Maeve pulse code; the epic's only change in that code was one line (`h->SetKnown(0xFF); /* inc-pu6v.361 */` in the old gift case 7). The old case 7 and case 8 are gone in Maeve's god, so the hunk takes her text. |
| src/Creature.cpp | 6 | inc-ac9m | `ForceGodPulse` and `ForcedPulseGod`, `FlockStanceProbe` (twice), `lotteryGate`, `pulseResult`, the patron draw: the epic's pulse-test controls. Maeve's `GodPulsePass` split carries the same text; her own edits in the function are outside the hunks. |
| src/SaveV1.cpp | 6 | inc-ac9m | Hunk 1: the tail of Maeve's `V1CharSpellsAid` against master's name-keyed `v1EmbedBegin`. The function goes (hunk 4 of `inc/Creature.h`). Hunks 2-6: `V1ProbeScope` lines. |
| tools/README.md | 2 | 1 inc-ac9m; 2 Maeve's rows, then inc-ac9m's two mage rows | Union of rows. Maeve's two copies of `check_mage_cast_nobook.sh` and `check_mage_loadout.sh` name `.sav`; the epic's name `.char`; the epic's win. |
| tools/check_creation_menus.sh | 1 | both | Maeve's footer-cap `case` (the maeve scenario leaves the footer uncapped), with the epic's scenarios `emptyalign` and `semirath` named in the loop and in the cap list, because they ran under 11 lines in the epic. |
| tools/creation_menus_oracle.py | 3 | see "Creation menus" | |
| tools/check_crown_pantheon.sh | 2 | both | Comment only; the check body merged without a conflict and holds both Maeve's 750 assertion and Aiswin's. Strangers are now Asherath, Zurvash (no watcher) and Essiah, Hesani, Mara, Sabine (watchers): six, so `post.patch` says "Six of the sixteen" and "six are read". |
| tools/check_favour_chart_rung9.sh | 1 | both, rewritten | See "Rung-9 check". |
| tools/check_killxp_loop.sh, tools/check_remove_field_event.sh | 1 each | inc-ac9m | `.char` fixture load. |
| tools/fixtures/chars/MANIFEST | 1 | Maeve's `elf-mage-nogod-seed1-opt0822` row only | On tip 913971e7 the epic has no rows left here: `wand-semirath`, `human-ranger` and `orc-priest-essiah` now have `.char` files, so their rows (Maeve's side still carries them) go; Maeve's own fixture has no `.char`, so its row stays. |
| tools/keys/creation-menu-maeve.keys | 1 | Maeve | Her `@while` loop already holds the epic's `@expect "Learn Spells: Level"` lines. |

## Landed file

`lib/landed-inc-pu6v.9.irh` holds the six Encounters and Template `"Fierce"`, in the order Maeve's ledger records them (Encounter positions 90-95, Template 107). The merged ledger
already held those positions, and the build says `order check: ok`. `tools/approve_order_break.sh` was not needed and was not run. The comment above `Fierce` still says "Appended at the END of
main.irc"; it is Maeve's text and stays verbatim.

## Creation menus

The merged game prints the epic's menu format (`* ` rows, the `These gods will not accept you:` heading) with Maeve's spoken refusal lines. `tools/check_creation_menus.sh` passes on the merged tree.

- Hunk 1 (Monk scenario): Maeve's comment and her `maeve_line` assertion, with the epic's `block(god, GOD_HEADING, 'god menu')` and `white_heading` lines in place of Maeve's old `Unavailable:` test.
- Hunk 2: Maeve's list of forbidders (with `MenuNoMonk`, `MenuQuietMonk`) and the epic's `\* ` row pattern.
- Hunk 3: Maeve's seven-refused-alignments test, preceded by the epic's `block(align, 'Maeve will not accept these alignments:', ...)` structure test; the epic's old-Maeve fallback-reason lines go (her priest rule fires instead).

## Rung-9 check

After the merge two gods carry a redesigned `FAVOUR_CHART` that has no 128000 (Maeve and Aiswin), so 11 of 17 charts hold it, and the old literal 12 fails. `post.patch` replaces the literal with
`len(lists) - len(REDESIGNED)`; `REDESIGNED` names the six gods in the check, so no new number is typed. Mutation: dropping `"Maeve"` from the tuple gave `FAIL: only 11 ... expected at least 12`; restored, PASS.

## Constants

Maeve's only new `#define` in `inc/` or `src/` is `MAEVE_DRAW_FORCE_SLOTS` (`src/MaevePulseProbe.cpp`). `post.patch` puts it in a `// no-family` block: a probe table size, never stored.
Maeve adds no value to a stored family (`inc/Defines.h` is not in her diff), and `tools/check_stored_values.py` passes.
