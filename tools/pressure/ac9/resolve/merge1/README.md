# AC9 merge 1: resolutions (master e8ab7697 = inc-cjos0 + inc-10v7f into the epic inc-pu6v d71c1823, in the scratch clone)

Order: master's `tools/convert_tags_to_names.py --apply` runs on the epic first (commit `port: convert epic field tags to
names (inc-ac9m)`, no hand edit; it reads master's `inc/SaveLegacyTags.h` because the epic has none). Then `git merge
master`. Then `tools/pressure/resolve_conflict.py`: `deletions.txt`, `keeps.txt`, the hunks, `post.patch`, the unchanged mover
`tools/move_branch_values.py` (0 moves), and the regenerated `src/yygram.cpp`, `inc/yygram.h`, `lib/dispatch.h`.

Side names: HEAD = the epic after the converter commit; master = e8ab7697 (inc-cjos0 f8a70246, then inc-10v7f landed on it).
Every line of a hunk resolution is copied verbatim from one side, or is named in `tools/pressure/ac9/allowances-merge1.txt`
(kinds: `hand` the debug menu numbers, `compiler` size asserts, `type` family widths, `rewrite` edits that keep every constant,
`port` the canonical-dump patch, `ac7` AC7's lines).

STATUS: `ac9.sh merge1` commits the merge with the hooks on; the build passes. The mover moves 0 values.

## Paths removed or kept (modify/delete conflicts: master deleted, the epic edited)

`deletions.txt` (23 paths): master's deletion wins for every fixture that has a `.char` (the `.sav`, `.keys`, sheet of 11
fixtures) and for the nine `tools/keys/*-save.keys` scripts those `.char` files replace. `keeps.txt` (2 paths, the new
`keeps.txt` mode of `resolve_conflict.py`, selftest `--selftest`): `tools/fixtures/chars/MANIFEST` and
`tools/make_char_fixture.sh` stay as the epic has them, because six epic-only fixtures (bard-song, multitude-ninth-row,
wand-semirath, human-ranger, orc-priest-essiah, orc-priest-xel) have no `.char` and are made and rebuilt by that tool
(`tools/headless.sh` drift rebuild, `tools/check_fixtures_load.sh`). `tools/sweep_merge_repros.py` (an epic one-off, called by
nothing) names the deleted `reapply-bard-save.keys`; left alone.

## Hunks

| File | Hunks | Choice | Reason |
|---|---|---|---|
| docs/ENGINE-MAP-CREATURE.md, docs/ENGINE-SERIALISATION.md | 4, 1 | master | Line citations only. Not re-verified. |
| docs/REPORTING-GATE.md | 13 | master's rows, then the epic's rows whose text (digits blanked) master lacks | Union of ledger rows. The three epic copies of the `Armour::PenaltyVal` row at three line numbers collapse to master's one row. Citations not re-verified. |
| docs/VERIFICATION.md | 1 | the epic's dice row, master's hit-point and item rows, the epic's pulse and two percent-chance rows, master's other rows | Master's bare "Percent-chance roll: none" row dropped: the epic splits it into a script row and a C++ row. |
| inc/Base.h, inc/Res.h, src/Base.cpp | 1 each | master | `V1ArrayWiden16`, `V1EmbedBegin`, the "Migrations" block, `V1ProbeScope("Array")`; the epic's `V1CharSpellsAid` goes with its use. |
| inc/Creature.h | 10 | 1 master; 2 HEAD; 3 master; 4 master; 5 master; 6 mixed; 7 HEAD; 8 HEAD; 9 master; 10 HEAD | The epic's size asserts stay (guards). 6: the epic's `GiftsGiven`, master's `SacValsRow` and `FIELD_ARRAY_ROWS("SacVals"...)`, the epic's retired-field block and `HateLev`; master's `Anger`, `FavPenalty`, `PrayerTimeout`, `AngerThisTurn` are no members in the epic. |
| inc/Defines.h | 2 | 1 mixed; 2 HEAD plus a class | 1: master's `FT_CANNIBALISM`, the epic's perk-range block and `FT_RELIGIOUS_NONCONFORMIST`, master's `FT_LUCUBRATION` block, the epic's `FT_LAST` line. 2: the epic's `msg_band` block with the class word `internal`, master's `// family: msg internal`. |
| inc/Map.h | 1 | HEAD | Keeps `FIELD_U8 ("natureHi", natureHi)`. |
| inc/Term.h | 1 | the epic's `LMenu` (with `unavailable`), master's `ScriptLMenu` declaration | A script menu has no refusal list; `ScriptLMenu` keeps master's signature. |
| src/Create.cpp | 14 | see "Create.cpp" below | |
| src/Debug.cpp | 2 | 1 the epic's 44 and 45, master's two entries with 46 and 47; 2 master | See "Debug.cpp". |
| src/Inv.cpp | 3 | master | Master's weapon sets. `post.patch` then makes `Character::NeedsBothHands` read `WeaponSizeBonus()` instead of `HasFeat(FT_MONKEY_GRIP)`, so the epic's `WEAPON_SIZE_UP` stati still counts. |
| src/Magic.cpp, src/Main.cpp | 1, 1 | both | `oldSaveDC` and `oldVDmg`; `DispelTrapProbe` and `ChasmSwapProbe`. |
| src/Prayer.cpp | 3 | 1 both; 2 the epic's declarations plus master's `DamageClassGodEntry(e);`; 3 the epic's | See "Prayer.cpp". |
| src/SaveV1.cpp | 8 | master | Pad tables are generated at build time; the epic's `V1CharSpellsAid` function goes. |
| src/VMachine.cpp | 1 | master's `ScriptDice` call; `post.patch` makes it use the epic's `ScriptDiceRoll` | Master's sourced dice and the epic's `INCURSION_FORCE_SCRIPT_DICE` both hold. `post.patch` also folds the epic's `INCURSION_FORCE_SCRIPT_RANDOM` into master's sourced `ScriptRandom` (the epic's second `ScriptRandom` and its `#define random` go; the force is applied to the real draw inside the sourced roll). |
| src/Values.cpp | 2 | both | The epic's `WeaponSizeBonus` / `CheckMountSize` and master's declarations; the epic's `DANCING` and `DENYAC` probes and master's `BonusOrderProbeNote`. |
| src/Wposix.cpp, src/Wlibtcod.cpp | 1, 1 | the epic's cursor probes, moved into master's `GetCharCmdImpl` | Master renamed the key reader; the probes read `mode` and stay at its top. |
| src/yygram.cpp, lib/dispatch.h | 9, 0 | regenerated | `tools/regen_yygram.sh`; the build, twice. |
| tools/README.md | 14 | both | Rows from both sides, each master row inserted before the first epic row whose check name sorts after it. |
| tools/check_aura_of_menace.sh | 4 | master | Seed-free, and its fixture now sits in `tools/fixtures/specimens/`. |
| tools/check_door_lock_rate.sh, check_quality_self_immune.sh, check_v1_append_survives.sh | 1, 2, 1 | master | |
| tools/check_favour_awards.sh | 1 | the epic's roll of 19 and its comment, master's `.char` fixture lines | A natural 20 would pay the epic's Semirath Devotion on every roll. |
| tools/check_hide_search.sh | 1 | master's `.char` load, the epic's default seed 3 | Master's controls make the verdict seed-free; the epic's seed stays so its header still reads true. |
| tools/check_pray_aid_int32.sh | 1 | the epic's (no `INCURSION_LOAD`) | The epic builds the character by key script: the frozen fixture lacks the class power the key script uses. |
| tools/check_weapon_types.sh | 3 | HEAD, then `post.patch` | AC7: the epic removed Kysul's forced gift. |
| tools/craft_bad_v1_saves.py | 2 | master, plus AC7's edits | `LAST_STATI` read from `inc/Defines.h`; `nature` and `natureHi` as 255; `FavourLev` found by name. |
| tools/fixtures/README.md | 2 | both | 1: both option rows. 2: the epic's regeneration paragraph, then master's "Setup scripts" heading. |
| tools/gates/dive-depth-4.baseline | 2 | master | The landing gate re-records it. |
| tools/headless.sh | 3 | 1 both exit-8 meanings; 2 the epic's drift-rebuild functions, then master's cache comment; 3 master | A `.char` fixture comes from the cache (exit 8 `FIXTURE LOAD FAILED`); an epic-only `.sav` keeps the drift rebuild. The epic's `8)` ending line is unreachable (its `_fx_fail` exits at once). |
| tools/keys/align-treachery-play.keys, quality-self-immune-burn.keys, quality-self-immune-quality.keys, xp-penalty-crash.keys | 1 each | master | Loaded character. |
| tools/keys/aid-casting-bonus-aid-wizard.keys | 1 | the epic's `@while "-- more --" SPACE`, then master's setup include | |
| tools/keys/warrior-class-skills.keys | 1 | the epic's `@choose "No god"` line, then master's point-buy block | Not run. |
| tools/nightly_verify.sh | 1 | both | The epic's list-report marker, then master's fixture pin. |

## Create.cpp

The epic's god-fit attribute roller and its refusal parameter on `LMenu` stay; the sourced picks drive every menu.

- Class, alignment and god menus: each offered row is `LOption` and `Add`ed to the pick list with the same menu value. A refused alignment or god is in neither, so a `.char` cannot pick it. The god list also holds the godless row (`No god` or `Cancel`, value 0), so a `.char` can state it. The epic's `unavailable` text is passed through the lambda (`...,0,unavailable); });`).
- Roller: the five sets are rolled in the epic's silent block, now inside `CreationCandidates` (draws are candidates, not decisions). `attrCmds` lists only the sets the god accepts, plus point buy and the rerolls. The lambda keeps the epic's Enter handling, marker, requirement line and refusal of a failing set. `AttributesFromSource` early return sets `attrsRolled` and returns true, as the epic's recreate branch did.
- Domains: the epic's `isSwap`, title and window with master's `CK_DOMAIN` pick. Master's Multitude pool (`CK_DOMAIN_POOL`) goes: the epic gave The Multitude six ruled domains and removed that kludge (inc-pu6v.186), so no site draws it.
- `Create(bool reincarnate)` keeps its named parameter (the epic's body names it); the sites check finds no branch on it.

## Debug.cpp

A debug menu number is never saved and key scripts pick entries by label (owner ruling 2026-11-12). The epic keeps 40 and 41; master's
"Burn Worn Armour" takes 46 and master's second entry "Damage Worn Armour" (inc-10v7f) takes 47, with their `case` labels
(`post.patch`). Both are named in the allowance file, kind `hand`. `KillEveryMonster` (master's shared body) takes the epic's
`IsHeldOffMap` skip (inc-pu6v.299), so master's genocide cannot loop on a held creature.

## Prayer.cpp

`Character::Transgress`: the epic's body (one call to `applyTransgression`). Master's change there was the sourced
`random(60)` roll before the removed `Anger`/`AngerThisTurn` model; the epic's favor model has no draw in that path
(`src/Prayer.cpp` holds no `random(` at all), so the change has no meaning there. `tools/check_creation_source_sites.sh` rule
`draw-transgress` demands that roll and goes red. Not edited: see the report.

## post.patch (edits outside the hunks; applied before the mover and the regeneration)

Every digit-bearing line it adds is on a side of the merge or is named in the allowance file.

- `inc/Creature.h`: the epic's two size asserts keep their values (the compiler agrees); `FIELD_SKIP(LastFeatGranted);`.
- `tools/retired_field_names.txt`, `inc/SaveRetiredNames.h`: master's `Character Anger`, `FavPenalty`, `PrayerTimeout`, `AngerThisTurn` are retired names (names only), so a master fixture save that carries them still loads.
- `src/Dump.cpp`: the planter's `anger` field writes `HateLev`; `-dump` takes the canonical-dump port made for this merge (`docs/evidence/inc-10v7f/epic-d71c1823/dump-port-d71c1823.patch`): four weapon sets, the epic's religion fields, `GodlessXP=`.
- `src/DamageClassProbe.cpp`: `Anger` becomes `HateLev`; `FavPenalty` is gone, so the penalty readback is 0.
- `src/Debug.cpp`, `src/VMachine.cpp`, `src/Create.cpp`: the edits named above (`case 46`/`case 47`, the held-creature skip, `ScriptDiceRoll`, `ForceScriptRandom`, `CreationCandidates`, the godless pick row).
- 24 `// no-family` / `// end no-family` pairs (comment only) around constants the epic added outside any family; 42 bare `// family: NAME` marks in `inc/Defines.h` get a class (table below), and widths (below).
- `tools/check_player_fields.sh`: the rows of the four retired fields go; rows for the epic's `GiftsGiven`, `HateLev`, `AidWaitEnd`, `exAidWaitStart`, `exFavPenalty`, `exPrayerTimeout`, `GodlessXP` and `Player skip:LastFeatGranted` are added (all `excluded`). The check already failed on master alone (`hpRollsRow`, `Macros[i]` and others); that is left.
- `tools/pressure/family_coverage.txt`: lines for the epic's families `gpr` and `tg`. (`pa` is uncovered on master alone; left.)
- `docs/specs/2026-11-06-fixture-builder-sites.md`: `<!-- stale-quote-ok: ... -->`, the check's own marker, for two quotes of a god-menu literal the epic removed.

## Widths (a type, not a chosen number)

- `stati` is `u16` on every one of its marks. The epic's `WELDED` = 339 and `WEAPON_SIZE_UP` = 332 do not fit `u8`; the epic stores the high byte in `natureHi`.
- `sp_flag` is `u32`: `SP_PINNATE` = 0x10000, and `Character::Spells[]` is a `uint32` array.

## Families the epic added without a class (decided by code)

A family whose value is saved takes a `stored` class; one that is never saved is `internal`.

| Family | Class | Evidence |
|---|---|---|
| tg | `stored ordinal i16 val-of TERRAIN_FREE` | The group is the Val of the `TERRAIN_FREE` stati row: `src/Skills.cpp`, `src/Status.cpp`. |
| gpr | `stored ordinal i16 mag-of HUNG_PULSE` | The pending request is a `HUNG_PULSE` stati, reason in Mag: `src/Creature.cpp`. |
| gs (3 marks) | `stored bits u16 elem-of Character.godFlags` | Master's own class for the family. |
| stati (3 marks) | `stored ordinal u16` | Master's family, widened. |
| list_id, const_id, ev | master's `internal` | Copied from master's marks of the same name. |
| subspell_band, list_id_hate, price_mode, gcc, grc, fav_state, fav_col, fav_val, choose_god, bcap, const_id_favour, align_break, exp_bits, expel_trigger, monmem, flight_kind, purse_cause, favsrc, msg_band | internal | Switch arguments, module reads, return values computed on demand, in-memory indexes, function arguments and message bands; none is written to a save. |

## Verification in the clone (inc-ac9m worktree)

See the report of the E1 run: build, `check_define_dups.py`, `check_stored_values.py`, `check_save_names.py`,
`check_field_names.sh` all pass; `ac9.sh values1` compares master's fixtures.

## E2 fit work (all folded into this resolution set; `ac9.sh merge1` makes the commit)

| What | Where |
|---|---|
| `draw-transgress` rule, `char_convert.sh` oracle-dump option, `ranger-gains-fasting` row, bard-song and innate-status key fits, `check_damage_class.sh` FIX, `check_undeath_to_death_pool.sh` absolute run dir | `post.patch` (digit lines named in `allowances-merge1.txt`, kind `fit`) |
| 44 epic `.char` fixtures converted from the epic's own saves against the oracle dumps, replacing master's `.char` where master has one; old `.sav`/`.keys`/sheet/MANIFEST rows and `chars/<name>.sav` references retired | driver substep `tools/pressure/ac9_fixtures.sh` (tool output; its added lines are attributed like the mover's) |
| 19 names `char_convert.sh` cannot convert, and `orc-priest-seed1-opt0822` | stand-ins, `tools/pressure/ac9/standins.txt` (inc-6jqgz, inc-xgs1x): the epic's own `.sav` stays |
| owner rulings: `god: No god` for elf-rogue-bluff, orc-barbarian-ce (and its `script_yn [Orc;EV_150]: yes` line removed), wood-elf-rogue-seed7; orc-paladin-cannibal absent from the clone's master; orc-priest-seed1 domain Planning for Fate | same substep |
| `check_damage_class.sh --freeze` (only `DC case=god type=13` moved: `out=50 penalty=1` to `out=100 penalty=0`) | same substep |
| values1 pairs the epic renamed in place | `tools/pressure/ac9/renames.txt` |
