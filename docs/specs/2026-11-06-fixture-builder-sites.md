# Fixture builder: decision sites and fixture tools (inc-10v7f)
<!-- citations: this-port -->

Phases 1 and 2 of `docs/specs/2026-11-06-fixture-builder-brief.md`. Part A is the
phase-1 site list (every `MO_RECREATE`, `MO_CREATE`, `reincarnate` and `RInf` site,
every creation-event script hook that draws or prompts, every census caller, and
the B16 classification). Part B is the phase-2 classification of every file that
reads `tools/fixtures/chars/`. Both are read-only surveys; each states its own
base commit and evidence tier.

# Part A
## Decision sites for inc-10v7f (phase 1, read-only)

Trees: master = `~/Scripts/Incursion-inc-10v7f` (HEAD 1e5ddcf2). Epic = `~/Scripts/Incursion-inc-pu6v` (HEAD d71c1823).
Evidence tiers: Traced = read in code on the named branch. Reasoned = inferred, not seen to run. Nothing here was run.
Key naming: proposed enum names use the prefix `CK_`. Per B18 a key is the enum plus an automatic context (resource, event, ordinal), so script sites share one enum per primitive.
Line numbers are master unless a column says epic. `draws.tsv` line numbers (2-64) name census rows.

### 1. MO_CREATE / MO_RECREATE / reincarnate / RInf occurrences

Commands (run from each tree root):

    grep -rnwE "MO_RECREATE" src inc        master 17   epic 18
    grep -rnwE "MO_CREATE"   src inc        master 30   epic 35
    grep -rnw  "reincarnate" src inc        master 11   epic 11
    grep -rnw  "RInf"        src inc        master 122  epic 122   (per file: Globals.h 1, Annot 9, Create 48, MultiSelectProbe 5, Term 10, TextTerm 49, both branches)
    (grep "reincarnat" without -w adds 5 comment lines and 2 string literals; none is a branch.)

#### 1a. Decision sites (a branch on the source that has to become one `CreationSource` call)

Same 15 sites exist on both branches. Master line / epic line.

| ID | Master | Epic | What it decides | Primitive | Proposed enum |
|---|---|---|---|---|---|
| D1 | Create.cpp:883-890 (`reincarnate==false` reset; replay copies `formulaSeed`, `CharGenOpts`) | 944-951 | seed that drives the craft-formula picks and the Multitude pool; creation options | SourcedRoll (seed); options come from `options:` (B11) | CK_FORMULA_SEED |
| D2 | Create.cpp:863-875 (`!reincarnate` guards the two option yn) | 924-936 | whether the option screen opens; Explore Mode confirm | SourcedPick (yes/no) | CK_ALTER_OPTIONS, CK_EXPLORE_CONTINUE |
| D3 | Term.cpp:2895 replay, 2944 record (ChoicePrompt) | 2910, 2959 | any ChoicePrompt answer | SourcedPick over the prompt letters | per call site (section 2) |
| D4 | Term.cpp:3421 replay, 3447 record (yn) | 3436, 3462 | any yn answer | SourcedPick (y/n) | per call site |
| D5 | TextTerm.cpp:1015 replay; 1285, 1295, 1358 record (LMenu); the 31-char title is the replay key | 1085; 1423, 1433, 1496 | any LMenu answer incl. ESC (-1) | SourcedPick over labels | per call site |
| D6 | TextTerm.cpp:1424 replay, 1771 record (LMultiSelect) | 1562, 1909 | no creation caller on either branch (only `MultiSelectProbe.cpp:48-76` and script-callable `inc/Api.h:660`) | SourcedPick (multi) | CK_MULTI_SELECT (latent) |
| D7 | TextTerm.cpp:1868 replay, 2095 and 2253 record (LearnTable; three replay keys at Create.cpp:6460-6466) | 2006; 2233, 2391 | starting spells and level-up spells | SourcedPick (multi), "spell [source]" | CK_SPELL_LEARN |
| D8 | Create.cpp:963-967 race, 1013-1017 subrace, 1089-1093 class, 1200-1204 alignment, 3775-3779 god (abandon bypass and `RInf.nRsp--` pop) | 1024-1028, 1074-1078, 1154-1158, 1304-1308, 4825-4829 | back-navigation after ESC then "no" | recorder pop, not a primitive (A6) | none |
| D9 | Create.cpp:2288-2291 RollAttributes replay of `BAttr`; 2550-2551 `RInf.Perks`, `usedPerks`; 2640-2643 record `Attr`, `rerollCount`, `rerolledPerks`, `statMethod` | 2468-2471; 2799-2800; 2920-2923 | attribute set, retained perk set, reroll facts | SourcedRoll x7 (attributes), perk blocks (D10) | CK_ATTR_STR..CK_ATTR_LUC, CK_STAT_METHOD, CK_REROLLS |
| D10 | Create.cpp:1123-1124 `GrantPerks(RInf.Perks)` | 1214-1215 | the three perks | SourcedPick/SourcedItem per perk field | CK_PERK_* (section 3) |
| D11 | Create.cpp:1224-1235 SkillManager skipped, `SkillRanks` copied from `RInf.SkillRanks` | 1328-1339 | skill ranks per pool | SourcedRoll per skill | CK_SKILL_RANKS |
| D12 | Create.cpp:1457-1465 replay of `Named`, `WizardMode`, `ExploreMode`, `storeSeed`, `rerolledPerks`, `rerollCount`, `statMethod` | 1561-1569 | name override, flags, store seed | SourcedPick (name), SourcedRoll (seed) | CK_NAME, CK_STORE_SEED |
| D13 | Create.cpp:1467-1523 record: RInf fill (1470-1482) and gallery.dat write (1483-1523, `GallerySlot`) | 1571-1624 | Recording; `GallerySlot`; File path must skip the write (A12) | recorder, not a primitive | none |
| D14 | Annot.cpp:586-598 `GrantGear` per-resource seed: MO_CREATE stores `NextSeed()%100` in `EquipRolls`, `srand(seed)`; MO_RECREATE reads it | 729-741 | the stream every later gear draw uses | SourcedRoll (skipped under File, B1) | CK_GEAR_STREAM |
| D15 | Annot.cpp:631-649 chance roll (`random(100)+1`; stored in `EquipRolls` under MO_CREATE; default branch does not store) | 773-790 | whether a `NN%` gear line is granted | SourcedRoll | CK_GEAR_CHANCE |

Notes: D14 and D15 read `T1->GetMode()`, not `MyTerm`. Under `File` the global mode MUST still read MO_CREATE for D14/D15, or the default branch draws unstored (Traced, Annot.cpp:586, 633).

#### 1b. Non-decision uses and declarations (account for every remaining hit)

| Master | Epic | Kind |
|---|---|---|
| inc/Term.h:205 (MO_CREATE), 207 (MO_RECREATE) | same lines | declarations |
| inc/Globals.h:310 `extern RInf` | 358 | declaration |
| Create.cpp:58 `ReincarnationInfo RInf;` | 63 | definition |
| Create.cpp:835 `Create(bool reincarnate)`; Main.cpp:129 `NewGame`; Creature.h:1512; Res.h:1346 | 895; 132; 1832; 1367 | declarations |
| Main.cpp:160 `if (reincarnate)` -> `pp->Reincarnate()` | 163 | dispatch to Reincarnate (not a decision) |
| Main.cpp:136 `T1->SetMode(MO_CREATE)` | 139 | mode set |
| Create.cpp:862 `SetMode(MO_PLAY)` is not a hit; 870, 884, 888 (`SetMode(MO_CREATE/RECREATE)`), 2645 (after RollAttributes) | 931, 945, 949, 2945; 2940 (epic bounce branch) | mode set |
| Create.cpp:1543, 1591 (strings "reincarnate a character", "suitable for reincarnation") | 1683, 1731 | string literals |
| Create.cpp:1613 `memcpy(&RInf,&ri[i])`, 1634 `RInf.Count` (inside `Reincarnate()`, 1532-1639) | 1753, 1774 | gallery load before `Create(true)`; the LMenu at 1596 "Choose a character:" picks WHICH RInf, outside the T2 window |
| Skills.cpp:4483-4486 (comment) | 4669-4672 | comment |
| TextTerm.cpp:1420, 1768, 1865-1866, 2091 (comments) | 1558, 1906, 2003-2004, 2229 | comments |
| MultiSelectProbe.cpp:43-76 (`RInf` save/restore, `SetMode(MO_CREATE)` 48, `SetMode(MO_RECREATE)` 66, comments 47, 59) | same | test hook, off unless `INCURSION_MULTISELECT_PROBE` |
| Create.cpp:3772 (ChooseGod window), 4139 (GainFeat window) | 4822, 5276 | choose a screen window, not a decision |
| Term.cpp:71, 319, 380; Managers.cpp:721 | same | display gating on `Mode` |
| (none) | Create.cpp:3401 comment, 3410 `creating=(Mode==MO_CREATE)` in ChooseDomains; 6215 FeatPrereq refuses a `FF_CREATION_ONLY` feat unless `Mode==MO_CREATE`; Creature.h:149 comment; Create.cpp:4833 comment | epic: behavior that depends on the mode value |
| Create.cpp:1457-1464 etc. | (counted in D12) | |
| RInf in TextTerm.cpp (49 hits) and Term.cpp (10) | TextTerm 49, Term 10 | the recorder/replayer bodies of D3-D7 (ranges: TextTerm 1016-1018, 1286-1298, 1359-1361, 1421, 1429-1437, 1776-1789, 1872-1880, 2100-2114, 2258-2272; Term 2897-2898, 2946-2948, 3423-3424, 3449-3451; epic +69 to +140) |
| Annot.cpp:43 `extern RInf` and 586-642 (9 hits) | 43, 729-785 | D14, D15 plus the extern |

Design constraint found: the mode value `MO_CREATE` is read by non-decision code (display windows, `Term.cpp` display gates, epic `FeatPrereq` 6215 and `ChooseDomains` 3410). The `File` backend has to keep `Mode == MO_CREATE`, or those branches change.

### 2. Prompts reached from Player::Create or AdvanceLevel

Columns: master line / epic line. "C" = reached while a level-1 character is built; "A" = reached in AdvanceLevel after creation (a `level:` key); "T" = TrainAs/addclass.

| # | Master | Epic | Prompt | Reach | Primitive | Enum |
|---|---|---|---|---|---|---|
| P1 | Create.cpp:864 | 925 | yn "Alter the character generation options?" (Mode is MO_PLAY here, so it is NOT recorded in RInf) | C | SourcedPick | CK_ALTER_OPTIONS (File: "no", B11) |
| P2 | 867 -> Managers.cpp:2284 OptionManager; raw reads Managers.cpp:2404, yn 2512, LMenu 2529 | 928 | creation option screen | C | none (File skips it) | none |
| P3 | 873 | 934 | yn "Your options will place the game in Explore Mode. Continue?" | C | SourcedPick | CK_EXPLORE_CONTINUE |
| P4 | 903 (ChoicePrompt "mf"; loops while -1 = ESC) | 964 | gender, only when `OPT_GENDER==0` | C | SourcedPick | CK_GENDER (shared with draw S1, case `OPT_GENDER==3`) |
| P5 | 950 | 1011 | race LMenu (rows from `EV_PREREQ`) | C | SourcedPick | CK_RACE |
| P6 | 1006 | 1067 | subrace LMenu (only if `OPT_SUBRACES` and subraces exist) | C | SourcedPick | CK_SUBRACE |
| P7 | 1072 | 1137 | class LMenu | C | SourcedPick | CK_CLASS |
| P8 | 1099, 1102 (`Message`, then `goto RepeatClass`) | 1163, 1168 | "not implemented" / "do not meet the requirements" acknowledgment, then the class menu repeats | C | repeated request (B4) | none (T1 acknowledgment) |
| P9 | 3771 ChooseGod "Choose a God:" (only `CF_RELIGIOUS` class, `required=true`) | 4821 (every class: `CG_ALL` for religious, `CG_NATIVE` with a "No god" row for others; `CG_FEAT` with "Cancel" row) | god LMenu | C (A for epic feat) | SourcedPick | CK_GOD |
| P10 | 105 AbandonCreation yn, reached after ESC at P5-P7, P11, P9 | 129 | abandon | C | SourcedPick; File MUST fail on it | CK_ABANDON |
| P11 | 1185 | 1288 | alignment LMenu (epic adds an "unavailable" text param) | C | SourcedPick | CK_ALIGNMENT |
| P12 | Create.cpp:2478 GetCharRaw (set a-e, `x` reroll, `w`, `p`, `?`, Up/Down/Enter, redraw) | 2702 | attribute set pick, 4d6 or perk method | C | SourcedPick over sets is impossible (sets are drawn): answered as 7 attributes plus perk blocks | CK_ATTR_*, CK_STAT_METHOD, CK_REROLLS |
| P13 | 2498 HelpTopic ("?"), reads Help.cpp:2026 | 2740 | help overlay | C | acknowledgment | none |
| P14 | 2504 `Box` perk warning on first `x` | 2746 | pause | C | acknowledgment | none |
| P15 | 2516 (inside a comment: dead) | 2758 | dead yn | - | - | - |
| P16 | 2584 GetCharCmd (point buy: arrows, +/-) | 2854 | point buy | C | SourcedRoll x7 | CK_ATTR_* with method 2 |
| P17 | 2625 yn "Are these your final stats?" | 2905 | point-buy confirm | C | SourcedPick | CK_POINTBUY_CONFIRM |
| P18 | 3812 LMenu "Which class do you wish to advance in?" (only `ClassID[1] && Level[0]`) | 4872 | class to advance | A | SourcedPick | CK_LEVEL_CLASS |
| P19 | 3893 LMenu attribute bonus (`OPT_ATTR_ON_LEVEL`, level 4,8,...) | 4987 | attribute | A | SourcedPick | CK_LEVEL_ATTR |
| P20 | GainFeat 4228 feat LMenu (row value -1 "(Show All/Hide Unavailable Feats)" toggles; reached at TotalLevel 1 twice, level 3,6,..., plus bonus lists FT_WIZARD_LIST, FT_WARRIOR_LIST) | 5365 | feat | C, A | SourcedPick | CK_FEAT |
| P21 | 4238, 4240 `Box` "isn't implemented" / "prerequisites" then re-pick | 5375, 5377 | rejected answer, repeats | C, A | repeated request (B4) | none |
| P22 | 4280 "Choose a skill:" (Skill Focus) | 5453 | skill | C, A | SourcedPick | CK_SKILL_FOCUS |
| P23 | 4304 "Choose a skill:" (Natural Aptitude; ALSO fired at race pick for a race with `SK_ANY`: Create.cpp:1039-1045) | 5477 | skill | C (race stage), A | SourcedPick | CK_NATURAL_APTITUDE |
| P24 | 4323 "Choose an area to improve:" (Intensive Study) | 5496 | area | A | SourcedPick | CK_STUDY_AREA |
| P25 | 4369 "Choose a focus school:" | 5542 | school | A | SourcedPick | CK_SCHOOL_FOCUS |
| P26 | 4467 "Choose a Weapon for Improved Critical:" | 5640 | weapon | A | SourcedPick | CK_IMPCRIT_WEAPON |
| P27 | 4535 weapon proficiency/focus/specialist/mastery (one LMenu, title varies by feat) | 5708 | weapon | C (human bonus feats), A | SourcedPick | CK_FEAT_WEAPON |
| P28 | 4586 "Choose a weapon:" (Exotic Weapon) | 5759 | weapon | A | SourcedPick | CK_EXOTIC_WEAPON |
| P29 | 4114, 4121 `CheckWeapon` yn "That weapon is too large..." / "You lack that weapon's Minimum Strength..." | 5251, 5258 | confirm | C, A | SourcedPick (y/n), repeats on "n" | CK_WEAPON_UNFIT_CONFIRM |
| P30 | 6735 ChooseInherentSpell "Choose an inherent spell:" | 7958 | spell | A (feat FT_INHERANT_SPELL) | SourcedPick | CK_INHERENT_SPELL |
| P31 | 6864 ChooseLucubrationBook "Choose a spellbook to study:" | 8087 | book | A | SourcedPick | CK_LUCUBRATION_BOOK |
| P32 | AddAbilities -> GainAbility CA_DOMAINS -> ChooseDomains 2713 "Choose a Domain:" (3 times, Multitude 2) | 3448 (title varies; epic `ChooseDomains(n,isSwap)` 3392; call 5848) | domain | C (priest, others with CA_DOMAINS), A | SourcedPick | CK_DOMAIN |
| P33 | GainAbility CA_TATTOOS 4727 | 5900 | tattoo | A | SourcedPick | CK_TATTOO |
| P34 | GainAbility CA_FAV_ENEMY 4839 (MA_CHOICE1-5) | 6012 | favored enemy | C (ranger), A | SourcedPick | CK_FAV_ENEMY |
| P35 | GainAbility CA_SPECIALIST 4870 | 6043 | wizard school | C (mage) | SourcedPick | CK_SPECIALIST_SCHOOL |
| P36 | SkillManager Managers.cpp:1922-2283: GetCharCmd 2110, GetCharRaw 2198 (confirm yn), 2228 (abort yn); commit loop 2215-2217; `Reset` loop until pools spent (2270) | 1329 call | skill ranks | C | SourcedRoll per skill (`skills: <pool> <skill>: <ranks>`) | CK_SKILL_RANKS |
| P37 | EV_BIRTH yn races.irh:913 "Do you wish to worship Ekliazeh?" (Dwarf, no god, not chaotic) | REMOVED on epic (races.irh:918) | worship | C | SourcedPick (script yn) | CK_SCRIPT_YN, ctx (Dwarf;race, EV_BIRTH, 1) |
| P38 | EV_BIRTH yn races.irh:1884 "Do you wish to worship Khasrach?" (Orc, no god) | REMOVED on epic (1871) | worship | C | same | CK_SCRIPT_YN |
| P39 | Create.cpp:1397 Personality LMenu (no MENU_ESC) | 1501 | personality | C | SourcedPick | CK_PERSONALITY |
| P40 | LearnSpell(true) at Create.cpp:1440 -> LearnTable 6475 (+ internal reads TextTerm.cpp:2005, 2241) | 1544; 7698 | starting spells | C | SourcedPick (multi) | CK_SPELL_LEARN |
| P41 | EV_ADVANCE ChoicePrompt classes.irh:1926 "Do you want to turn or command undead?" (Priest, no god flag decides) | classes.irh:1940 | turn/command | C | SourcedPick (script) | CK_SCRIPT_CHOICE |
| P42 | EV_ADVANCE ChoicePrompt classes.irh:2204 "Combat style: archery, skirmish or two-weapon?" (Ranger level 1) | 2218 | style | C | SourcedPick (script) | CK_SCRIPT_CHOICE |
| P43 | EV_ADVANCE LMenu classes.irh:2675 "Choose a Rogue special ability:" (rogue level 6,9,12,15,18) | 2689 | ability | A | SourcedPick (script) | CK_SCRIPT_MENU |
| P44 | Character::TrainAs 5795, 5800 yn, 5805 ChoicePrompt "[1] [2] [n]" (3rd class) | 7018, 7023, 7028 | replace a class | T | SourcedPick | CK_TRAIN_REPLACE |
| P45 | TextTerm acknowledgment reads: CWrite `[MORE]` TextTerm.cpp:260; Message `-- more --` 362 (skipped when `autoMore`); Box 536 | same | acknowledgments | C, A | T1 wrapper answers and logs (A8) | none |
| P46 | LMenu/ChoicePrompt/yn internals: TextTerm.cpp:1211, 1213; Term.cpp:2926, 3437; LMultiSelect 1638-1640; LearnTable 2005, 2241 | epic same bodies | the key reads inside the primitives | C, A | T1 passes them (they are inside a sourced decision) | none |

Epic-only prompt rows are in section 5. Prompt not reachable in the window (checked): Player::Reincarnate LMenu 1596 (before Create), `Term.cpp:3230` acquisition prompt, Debug.cpp ReadLines (wizard keys), SpellManager (Managers.cpp:409), InventoryManager (772).

### 3. Every census row (draws.tsv) mapped

Window "AdvanceLevel" or "Create" as in the file. "sourced" gives primitive and enum. "baseline" gives the reason. Rows are by draws.tsv line.

| Line | Row | Disposition |
|---|---|---|
| 2, 3 | AdvanceLevel srand@Skills.cpp:4117, 4195 RecalcCraftFormulas (1554 each) | baseline for the srand itself: stream control, not a fact. Under File the 4117 reseed (`formulaSeed`) is skipped (B1) and each pick (line 4) is sourced. 4195 `srand(NextSeed())` is skipped; its `NextSeed` tick is a counter, stated by `seed:` |
| 4 | AdvanceLevel random Skills.cpp:4187 (138, 19 runs) | sourced: SourcedPick over spell names, ctx = craft source (Alchemy, Potion, Scroll); result is `Spells[] SP_CREATE`, saved. CK_CRAFT_FORMULA. Traced |
| 5 | AdvanceLevel EV_ADVANCE Barbarian dice (32, 12) | sourced: SourcedRoll, two `GainInherentBonus(A_STR/A_CON, 1d2)` at classes.irh:215-216 (saved ADJUST_INH). CK_SCRIPT_ROLL, ctx (Barbarian, EV_ADVANCE, 1-2). Traced. Note `1d3` in the same block is not the count; see section 7 |
| 6 | AdvanceLevel random Create.cpp:2689 ChooseDomains (8, 1 run) | sourced: SourcedPick, eight domain names (`domain_pool`). CK_DOMAIN_POOL. Master only (epic removed it, section 5) |
| 7, 8 | AdvanceLevel random Create.cpp:4014 (hp), 4021 (mana) | sourced: SourcedRoll per class per level into `hpRolls`, `manaRolls` (saved). CK_HP_ROLL, CK_MANA_ROLL. The `max(random(HD)+1, HD/2)` clamp stays in code. Traced |
| 9 | AdvanceLevel srand@Create.cpp:2687 ChooseDomains | baseline: stream control, skipped under File (B1) |
| 10 | Create random Create.cpp:1729 AttrDice (10,984,848, 99) | sourced at the pick: SourcedRoll x7 (CK_ATTR_*); the draws that generate the 5 offered sets are bypassed with RollAttributes (4 sets unchosen). Traced |
| 11 | Create CreatePerk:2031 (37,052) | sourced: SourcedPick effect name (PERK_SPELL, PERK_TALENT). CK_PERK_SPELL, CK_PERK_TALENT. Only the retained set is a fact |
| 12 | Create dice Magic::CalcEffect +0xd08 (14,405, 59) | baseline, reason "description": `CalcEffect` is reached from `TEffect::Power` (Magic.cpp:253) which is reached from `Item::Name(NA_LONG)` (Message.cpp:1349); in the window the only `NA_LONG` caller in Create.cpp is CreatePerk:1898 (a name-length redo test). The rolled value feeds a display string. Traced for the Power route; Reasoned for the other callers (none of Magic.cpp:898, 1410, 1628 run in creation). Recommend routing it to the cosmetic stream |
| 13 | CreatePerk:1981 (7,114) | sourced: SourcedPick feat name. CK_PERK_FEAT |
| 14 | RollAttributes:2417 (5,110) | sourced: SourcedPick perk type. CK_PERK_TYPE |
| 15-22, 26, 29, 30, 31, 46, 49, 50 | GenItem Encounter.cpp:3438, 3344, 3275, 3284, 3510, 3554, 3283, 3485, 3425, 3496, 3511, 3390, 3392; MakeMagical Item.cpp:666 | sourced as ONE decision: SourcedItem (B15). In the window GenItem is called at Create.cpp:1892 (PERK_ITEM, observed) and Annot.cpp:733 (`random_depth_effect`, not observed). CK_PERK_ITEM, CK_KIT_ITEM. Traced |
| 23 | GetEffectID Res.cpp:699 (2,057) | sourced inside SourcedItem (callers Encounter.cpp:3448-3455 GenItem, Annot.cpp:699, 701 GF_RANDOM_EFFECT) |
| 24 | Create dice TEffect::Power +0x65c (1,597, 10) | baseline, reason "description" (same trace as row 12; `Power` calls `d.Roll()` at Magic.cpp ~304 only to build a string). Traced |
| 25 | GetItemID Res.cpp:470 (1,560) | sourced: inside SourcedItem (GenItem 3360/3362) or the GF_RANDOM_ITEM item pick in `GrantGear` (Annot.cpp:664-678): CK_KIT_ITEM |
| 27 | NumQualities Encounter.cpp:3078 | sourced inside SourcedItem (qualities) |
| 28 | Create dice Resource::GrantGear +0xe90 (1,221, 90) | sourced: `Amount.Roll()` at Annot.cpp:767 (spec says :743, wrong). SourcedRoll CK_KIT_QUANTITY. Traced |
| 32 | Item.cpp:92 (838, 38) | sourced inside SourcedItem (wand/staff charges `Item::Create`; B2 `charges:`) |
| 33 | EV_BIRTH Mage dice CalcEffect (811, 11) | baseline "description". Reasoned: Mage EV_BIRTH (classes.irh:940-986) only creates spellbooks; CalcEffect arrives through an item name (likely the UI redraw `ShowStatus`/message path `Term.cpp:2318`). Not traced to the exact `Name` call |
| 34 | GrantGear chance Annot.cpp:636 (795, 90) | sourced: SourcedRoll CK_GEAR_CHANCE (A4, keyed by granting resource and annotation ordinal) |
| 35, 36 | srand@Skills.cpp:4117/4195 (Create) | as rows 2, 3 |
| 37 | CreatePerk:1872 resist (590) | sourced: SourcedPick (damage or save name). CK_PERK_RESIST |
| 38 | CreatePerk:2009 ability (496) | sourced: SourcedPick. CK_PERK_ABILITY |
| 39 | QualityOK Item.cpp:2622 featherlight `random(20)` (438, 39) | sourced inside SourcedItem (quality choice) |
| 40 | srand@Annot.cpp:591 (285, 90) | baseline: stream control, skipped under File (B1) |
| 41 | PickName Create.cpp:83 (208, **100** runs) | sourced: SourcedPick name/surname. CK_NAME, CK_SURNAME (B12). Run count 100 against 99 walks is unexplained, see section 7 |
| 42 | CreatePerk:1829 immune (202, 15) | sourced: SourcedPick. CK_PERK_IMMUNE. (The redo test compares `p.immune` after writing `p.resist`: a union alias, see section 7) |
| 43 | Skills.cpp:4187 (Create) (178, 45) | sourced CK_CRAFT_FORMULA as row 4 |
| 44 | EV_BIRTH fountain;effect dice (176, 19) | sourced inside SourcedItem (dungeon.irh:2564 `SetCharges(4+1d6)`); the item is generated inside CreatePerk's rejection loop (T_FOUNTAIN is redone) so this draw reaches no saved field unless a kit item is a fountain. Traced |
| 45 | EV_BIRTH Mage dice TEffect::Power (129, 6) | baseline "description" as row 12 |
| 47 | Create.cpp:1312 (56, 50) | sourced: SourcedRoll ammo quantity. CK_AMMO_QUANTITY |
| 48 | EV_BIRTH Universal Gear dice CalcEffect (50, 49) | baseline "description" (Reasoned). races.irh:113 creates and `MakeKnown(0xFF)` a holy symbol, with no draw in the script |
| 51 | EV_BIRTH Drow;race dice CalcEffect (19, 2) | baseline "description" (Reasoned) |
| 52 | EV_BIRTH Monk dice (18, 9) | sourced: SourcedRoll x2 (1d20, 1d20) plus a sex pick at classes.irh:1439-1486; the result is `EActor->Named`, which overrides `PickName`. CK_SCRIPT_ROLL. See section 7 (name ownership) |
| 53 | EV_GENITEM small glass vial GetEffectID (18, 9) | sourced inside SourcedItem (mundane.irh:1011-1015 poison effect pick) |
| 54 | EV_GENITEM small glass vial dice (18, 9) | sourced inside SourcedItem: `1d4+1` poison duration (a stati). Kit entry fields in B2 name no stati: see section 7 |
| 55 | EV_BIRTH Warrior CallMemberFunc random (18, 9) | sourced: SourcedRoll, `random(3)` per armor piece, classes.irh:2909. Result: `AQ_LIGHT_FOR` quality or +1 plus. CK_SCRIPT_ROLL, ctx (Warrior, EV_BIRTH, n) |
| 56 | Create dice VMachine no event (14, 11) | sourced (Reasoned). Candidate: a gear `Condition` script run by `GrantGear` at Annot.cpp:658, which runs with no event on the census stack. Resource not identified: section 7 |
| 57 | Create.cpp:1284 (12, 11) | sourced: SourcedRoll thrown-weapon quantity. CK_THROWN_QUANTITY |
| 58 | ChangeIID Item.cpp:131 (12, 1) | sourced inside SourcedItem (group quantity `10+random(10)`) |
| 59 | EV_BIRTH Drow;race dice VM (9, 9) | sourced: SourcedRoll `4d2` poison duration of the elfshot vial, races.irh:1273. Stati on a kit item: section 7 |
| 60 | EV_BIRTH Identify;wand dice (6, 1) | sourced inside SourcedItem: `SetCharges(10+1d10)`, m_items.irh:2945 (`charges:`) |
| 61 | RandomBane Item.cpp:2983 (4, 1) | sourced inside SourcedItem (bane) |
| 62 | Create.cpp:917 gender (3, 3) | sourced: SourcedPick male/female. CK_GENDER (same key as P4) |
| 63 | Create dice Player::Create +0x242c (3, 3) | sourced: SourcedRoll `Dice::Roll(3,2,4)` food ration quantity, Create.cpp:596 (inlined `GrantBeginnerKit`). CK_BEGINKIT_FOOD |
| 64 | EV_BIRTH Elf;race Transgress Prayer.cpp:1727 (3, 3) | sourced: SourcedRoll `random(60)` gate. Decides `Anger[]` of a saved god field when an elf follows another god. CK_TRANSGRESS_ROLL. Traced |

Row count: draws.tsv has 63 data rows (lines 2-64). All 63 appear above (rows 15-22 etc. grouped).

B16 classification (CalcEffect and Power): rows 12, 24, 33, 45, 48, 51. None reaches a saved field. Evidence: `TEffect::Power` is called only from `Message.cpp:1349` (`Item::Name`, NA_LONG), `Sheet.cpp:1481`, `Managers.cpp:308, 320` (display); the dice go into `Format()` strings (Magic.cpp ~295-312). Tier: Traced for rows 12 and 24 via CreatePerk:1898; Reasoned for rows 33, 45, 48, 51 (the `Name` call that fires inside those EV_BIRTH contexts was not located). Side effect that matters: these draws use the MAIN stream, so each screen redraw that names an item changes every later gameplay draw. A9 says the cosmetic stream needs no exemption: moving `Power`'s `d.Roll()` and its `CalcEffect` call to the cosmetic stream removes 6 of the 63 rows from the T2 baseline.

### 4. Creation-time script hooks (lib/*.irh and lib/*.irc)

Scan: a brace-matched pass over every `EV_BIRTH`, `EV_ADVANCE`, `EV_GENITEM`, `EV_STARTING_ITEM`, `EV_PREREQ`, `EV_ISTARGET` handler, matching `random(`, dice literals, `yn(`, `Prompt`, `LMenu`, `Roll`. Counts: master EV_BIRTH 45, EV_ADVANCE 35 (80 total, matches A2), EV_GENITEM 1, EV_PREREQ 15, EV_ISTARGET 183, EV_STARTING_ITEM 9. Epic: 53, 40, 1, 11, 184, 9. EV_PREREQ and EV_ISTARGET handlers: none holds a draw or prompt token (both branches). `lib/main.irc:298` EV_BIRTH is the stress-test monster; `landed.irc`, `module-example.irc` have none.

Hooks with a draw or prompt that can fire in the window (resource; file:line master / epic):

| Resource, event | Master | Epic | Draw or prompt | Primitive |
|---|---|---|---|---|
| Class Barbarian, EV_ADVANCE | classes.irh:204 | 204 | `1d2` x2 `GainInherentBonus` (TotalLevel 1) | SourcedRoll |
| Class Monk, EV_BIRTH | 1439 | 1455 | `1d20`, `1d20`, sex branch: sets `Named` | SourcedRoll x2 |
| Class Priest, EV_ADVANCE | 1890 | 1904 | ChoicePrompt turn/command | SourcedPick |
| Class Ranger, EV_ADVANCE | 2191 | 2205 | ChoicePrompt style | SourcedPick |
| Class Rogue, EV_ADVANCE | 2592 | 2606 | LMenu ability (level 6+, AdvanceLevel only) | SourcedPick |
| Class Warrior, EV_BIRTH | 2903 | 2917 | `random(3)` per armor | SourcedRoll |
| Race Dwarf;race, EV_BIRTH | races.irh:911 | 918 (no yn) | yn Ekliazeh | SourcedPick (master only) |
| Race Orc;race, EV_BIRTH | 1879 | 1871 (no yn) | yn Khasrach | SourcedPick (master only) |
| Race Elf;race, EV_BIRTH | 1146 | 1146 | `Transgress` `random(60)` when god is not Maeve | SourcedRoll |
| Race Drow;race, EV_BIRTH | 1268 | 1260 | `4d2` | SourcedRoll |
| Race Female Drow;race, EV_BIRTH | subraces.irh:608 | 608 | `4d2` | SourcedRoll |
| Item small glass vial, EV_GENITEM | mundane.irh:1011 | 1011 | `GetEffectID(PUR_POISON,...)`, `1d4+1` | inside SourcedItem |
| Effect/Spell Identify;wand, EV_BIRTH | m_items.irh:2945 | 2945 | `10+1d10` charges | inside SourcedItem |
| Effect fountain;effect, EV_BIRTH | dungeon.irh:2564 | 2640 | `4+1d6` charges | inside SourcedItem |
| Effects reachable only if a generated or stated kit/perk item carries them: Springblade Bracers (m_items.irh:4292, 1d6 type), Spell Storing (5320), Lesser Helm of Brilliance (5894, `random(10)`, `random(5)`), Hornblade (6788, `1d3`), Dragonshield (7469, `1d7`), Rod of Lordly Might (6228, no draw) | as listed | 4290, 5318, 5892, 6226, 6786, 7467 (epic, -2) | draw per item birth | inside SourcedItem; none observed in the census |
| Monster "Universal Gear", EV_BIRTH | races.irh:113 | 113 | none (holy symbol) | - |
| Class Mage, EV_BIRTH | classes.irh:940 | 956 | none (spellbooks) | - |

Hooks with no draw or prompt token but in the window (checked, no action): Druid, Paladin, Priest EV_BIRTH, Ranger EV_BIRTH, Human, Kobold, Gnome, Dwarf, Drow, Lizardfolk, Deep Gnome, Grey Dwarf, Black Orc, Female Drow EV_ADVANCE; Domain Evil, Knowledge, War EV_ADVANCE; prestige-class EV_ADVANCE (Alienist, Assassin, Blackguard, Earthsinger, Loremaster, Master Archer: AdvanceLevel after creation only); EV_STARTING_ITEM on Dwarf, Elf, Drow, Orc, Grey Dwarf, Grey Elf, Wood Elf, Female Drow, Black Orc (call `QualityOK`, which draws only for `IQ_FEATHERLIGHT`, Item.cpp:2622 - not reachable from these handlers); God Aiswin and Asherath GODWATCH(EV_ADVANCE).
Not reachable in the window (Reasoned, no census row, no player path): EV_BIRTH on Monster/Region/Template (dungeon.irh, mon1-4.irh).

### 5. Epic-only sites

| Site | Epic file:line | What | Primitive / enum |
|---|---|---|---|
| God menu for every class | Create.cpp:1185-1201 `RepeatGodChoice`; ChooseGod 4733-4862 (LMenu 4821) | religious class: `ChooseGod(true, CG_ALL)`; others `ChooseGod(false, CG_NATIVE)` with row 0 "No god" | SourcedPick; value "No god" selects row 0, ESC returns -1 with `GodID` unchanged. CK_GOD |
| "Cancel" row | 4744, 4817, 5398 (`FT_RELIGIOUS_NONCONFORMIST` -> `ChooseGod(false, CG_FEAT)`) | feat god menu, row 0 "Cancel"; pick unspent on Cancel/ESC then the feat menu repeats | SourcedPick; CK_GOD_FEAT |
| Bounce loop | Create.cpp:1185-1215, `RollAttributes` returns false at 2941 | a picked stat set that fails the god sends creation back to the god menu a second time; `rollSkipped` skips the roller | the god queue needs two entries (B4); CK_GOD repeats |
| `CreationGodFit(Ex)` | 3000-3200 | sets `BAttr=18`, calls `CalcValues` twice: each call runs `RecalcCraftFormulas` -> `NextSeed()` tick (Skills.cpp:4263-4350) | no draw; shifts `NextSeed` ticks |
| `ForbidPromptAsk` | Event.cpp:437; Create.cpp:4889 (AdvanceLevel) | Box + yn "Advance anyway?" when god forbids the class | SourcedPick; CK_FORBID_CONFIRM (A) |
| BOUND_GOD join | Create.cpp (AdvanceLevel) `ReThrow(EV_CONVERT)` | an Alienist level without a god joins the bound god (may prompt via EV_CONVERT) | not yet traced |
| EV_BIRTH Semirath, Xel, Aiswin; EV_BIRTH Aiswin's Hunt effect | epic branch `inc-pu6v`, not in this tree: `lib/religion.irh` (epic lines 9763, 12547, 1118) and the epic's landed-god file (epic line 2520) | deterministic grants (Semirath's gift calls `CreateItem` + `Initialize`, no script draw) | none |
| Dwarf/Orc worship yn removed | races.irh:918, 1871 | | master-only prompts P37, P38 |
| Multitude `domain_pool` removed | Create.cpp:3392-3470 `ChooseDomains(nChoices,isSwap)` has no `srand`/`random` and no `Multitude` text | row 6 and row 9 of section 3 do not exist on the epic. B1's `domain_pool` lines apply to master only | - |
| `ChooseDomains` SwapDomains call | `ClassSuspend.cpp` on the epic branch `inc-pu6v`, not in this tree (epic line 1207) | mid-game domain swap | post-creation |
| `FT_PERK_LAST` | Create.cpp (CreatePerk PERK_FEAT) `random(FT_PERK_LAST - FT_FIRST)`; `FeatPerkRangeGuard` | the perk-feat range differs, so the same stated feat list is a different draw domain | no key change |
| Mode-dependent code | 3410, 6215 | `Mode==MO_CREATE` read outside a decision | File backend keeps the mode |
| Annot.cpp:729-790 | equal to master 586-649 | | D14, D15 |

### 6. Existing checks and key scripts that exercise gallery reincarnation (master)

grep: `grep -rliE "reincarnat|gallery|RInf" tools` -> 4 files.

| File | What it does |
|---|---|
| tools/keys/chargen-escape.keys + tools/check_chargen_escape.sh | ESC at the race menu, "no", ESC, "yes": exercises `AbandonCreation` and the `RInf.nRsp--` pop at Create.cpp:966. It does not reach `Reincarnate` or `MO_RECREATE` |
| tools/keys/multiselect-probe.keys (no `check_*.sh` calls it) | drives `MultiSelectProbe.cpp`, which sets MO_RECREATE by hand and replays an LMultiSelect |
| tools/craft_bad_v1_saves.py:268 | a comment about `GallerySlot` in a crafted bad save |
| tools/dump_save.sh:24 | comment: read only, never calls `TouchGallery` |
| tools/check_stale_quotes.sh | unrelated (grep word) |

No check, key script or gate drives `Player::Reincarnate`, `Create(true)`, MO_RECREATE through a real creation, or `gallery.dat`. So after D1-D15 become `CreationSource` calls, nothing in the repo shows reincarnation behaves as before. A new check is needed for "behaves exactly as today" (A6). Epic: same, plus a comment in the epic branch's `tools/check_xel_agent_ally.sh` (not in this tree; epic line 29).

### 7. Gaps and suspicions

1. Back-navigation leaves a stale -1 in RInf (Traced, not run). At ESC on the race menu the LMenu records -1 (TextTerm.cpp:1296-1298), then `AbandonCreation` records the yn answer (Term.cpp:3447), then Create.cpp:966 pops ONE entry (the yn). The -1 stays, so a later reincarnation reads -1 for the race question. Settles it: key script ESC, n, then complete creation, then `Reincarnate` and compare. A6 says the new recorder "pops a decision on back-navigation as `RInf.nRsp--` does today"; if it does only that, the recorded file gets the same stale entry.
2. `RInf.Rsp[128]` has an overflow guard only in LMultiSelect and LearnTable (TextTerm.cpp:1776, 2100, 2258), none in LMenu, ChoicePrompt, yn. The epic's extra god menus and a long feat sequence make it closer. Reasoned. Settles: count responses in the longest walk.
3. Gender ESC loops (Create.cpp:902-904 `while (ch == -1)`): each ESC records -1 into RInf, with no pop. Reasoned.
4. Kit entries (B2) list item, effect, plus, quantity, charges, qualities. The census shows item stati set by scripts: poison duration `4d2` (Drow, races.irh:1273), `1d4+1` (vial EV_GENITEM). Fields needed: `stati:` or one SourcedRoll per script draw. Not covered by B2 as written.
5. Name ownership: Monk EV_BIRTH sets `Named` after `PickName` (classes.irh:1486), then reincarnation overrides with `RInf.Name`. A `.char` `name:` line has to say which of the three wins. Settles: define `name:` as the final value written after EV_BIRTH.
6. Row 56 (VMachine dice with no event) resource unknown. Settles: add the running resource id to `CensusDice`, rerun the 99 walks.
7. Row 41 shows 100 runs from 99 walks; the file's header says 99 ok. Settles: check the walk list for a doubled creation.
8. CreatePerk PERK_IMMUNE writes `p.resist` but tests `p.immune` (Create.cpp:1829-1833): the Perk union aliases both, but the duplicate check depends on it. Reasoned. Possible upstream defect; no action here.
9. GrantGear draws not seen in the 99 walks: random item level (Annot.cpp:726), `Dice::Roll(1,4,1)` torch is Monster::GainItem (not player), Item.cpp:167 rope `random(2)`, Create.cpp:1282 missile-focus quantity (80+random(20)). They are decision-bearing; the census misses them because no walk takes the branch. Settles: C2 coverage list generated from the enum.
10. GainXP (`xp:` key) draws at Create.cpp:2989, 2998 (`random(10)`, `random(buffCount)`) with `hMana>=80` and active buffs. Post-creation key body; sourced or `unstatedDraw`.
11. TrainAs prompts (P44) and the epic `ForbidPromptAsk` / BOUND_GOD join are reachable from `addclass:` and `level:`; not walked by the census.
12. Title collisions: LMenu replay keys on the first 31 characters of the title. "Choose a skill:" is shared by Skill Focus and Natural Aptitude; "Choose a Domain:" by every domain pick. `ASSERT` only compares the prefix. Irrelevant under enum keys, relevant for the Replay backend.
13. NextSeed ticks: `RecalcCraftFormulas` ends with `srand(NextSeed())` on every `CalcValues` (1554 + 608 hits in 99 walks). Under `File` the number of `CalcValues` calls is the same as under `Live`, but any skipped call shifts the tick count that `seed:`-driven code after the window (flavors, map) sees only if those use the same counter. Settles: record the tick at window end for both backends in C2.

#### Spec contradictions (line drift or content)

- B1/A4 name `Amount.Roll()` at `src/Annot.cpp:743`; it is at 767 (743 is `Item::Create`).
- A6's master line list is stale by +1 on most entries (spec 862, 882, 887-889, 962, 965, 1012, 1015, 1088, 1091, 1122, 1199, 1202, 1223, 1456-1463, 3774, 3777 vs HEAD 863, 883, 888-890, 963, 966, 1013, 1016, 1089, 1092, 1123, 1200, 1203, 1224, 1457-1464, 3775, 3778). Section 1 here is the current list.
- Section 1 cites `src/Managers.cpp:2110-2228` for SkillManager: the function is 1922-2283 and those lines are its key reads; its commit is 2215-2217 (spec says 2215-2218).
- B1 requires eight `domain_pool` lines; the epic has no such draw (section 5). They are master-only until the merge.
- A9 says "NextSeed() calls are sourced". `NextSeed` is a tick counter (Main.cpp:48-55) read by 6 callers; none of them is a decision except `formulaSeed` (Create.cpp:886) and `storeSeed` (1455). The rest (Annot.cpp:584, Skills.cpp:4195, Main.cpp:122, 752) feed streams that File skips.
- Spec section 2 lists "attribute sets and rerolls" as random draws that decide a character fact. Only the chosen set is a fact; the 4 unchosen sets and their perks are 10,984,848 + 37,052 draws of discarded generation (census). RollAttributes has to be answered as a whole screen, not draw by draw.
- Spec section 1 says every `MO_RECREATE` branch MUST be deleted. The mode value is also read by non-decision code (section 1b); the mode itself stays.

### Second pass (different patterns)

Patterns: `srand(`, `random(`, `Dice::Roll|\.Roll\(`, `NextSeed`, `GetCharRaw|GetCharCmd|GetKey|ReadLine`, `LMenu` across `src/` and `lib/*.irh` for functions reachable from `Create`/`AdvanceLevel`.

Found, not in sections 1-4 as first written:

1. `src/Annot.cpp:606` `srand(p->storeSeed)` in `GrantGear` when `c->HasMFlag(M_SELLER)`: a shop-keeper gear run, not a player run. Not in the window. No action.
2. `src/Item.cpp:167` `Item::Initialize` rope `random(2)?20:6`; `Item.cpp:131-133` group quantities; `Item.cpp:92-94` charges: item creation draws (rope not in the census). Inside SourcedItem.
3. `src/Create.cpp:2989, 2998` GainXP draws (gap 10).
4. `src/Values.cpp:2424, 2443` `Dice::Roll` for monster HP/mana in `CalcValues`: monster path only (`OPT_MON_MAX_HP`), not a player. No action.
5. `src/Item.cpp:1044` `Exercise(random(6)+...)` in the scroll-read path: not in creation.
6. `src/Item.cpp:377` flavor pick (`SetFlavors`, called in `NewGame` before `Create`): outside the T2 window, controlled by `seed:` (spec says so).
7. `src/Prayer.cpp:1727` Transgress: found by the census, absent from spec section 2's list; sourced in row 64.
8. `src/Magic.cpp:712, 740` `e.Dmg.Roll()` and the `Power` roll at ~304 (rows 12, 24).
9. Key reads reachable and absent from spec: `TextTerm.cpp:260` `CWrite` `[MORE]`, `362` `Message` `-- more --`, `536` `Box`, `Help.cpp:2026` `HelpTopic` (reached by `?` in RollAttributes and in menus), `Term.cpp:3349` `ReadLine` (name prompt callers: none in creation). A8 covers acknowledgments; `HelpTopic` is not an acknowledgment (it loops until ESC) and needs T1 handling.
10. `lib/*.irh` prompts in non-creation resources (alchemy, pspells, wspells, dungeon, m_items): not in the window. The only creation-reachable script prompts are races.irh:913, 1884 and classes.irh:1926, 2204, 2675.
11. `src/Skills.cpp:4187` and `4117/4195` were already in the census; the grep shows no other `srand` in `src/` outside Main.cpp:122, 752 and probes.
12. `DrawCensus.cpp` identifies `Dice::Roll` callers by return-address offset only (`dice@+0x...`); line numbers for rows 12, 24, 28, 33, 45, 48, 51, 63 come from reading, not from the log.

# Part B
## Fixture tools survey (inc-10v7f phase 2)

Read-only survey of /Users/brianhill/Scripts/Incursion-inc-10v7f (master, HEAD 1e5ddcf2). Nothing was built or run. Evidence tier for every row: Observed by grep or read of the file, except where a row says Reasoned.

### 0. Corrections to the spec's premises

- `tools/sync_char_fixtures.sh` does not exist on master. Only `MANIFEST` (47 rows) and two doc mentions name it. `tools/check_fixtures_load.sh` and `tools/repro_zto3q_rebuild.sh` (spec A12) also do not exist here; they are epic-only.
- `MANIFEST` has 47 rows. The other 27 fixtures have no MANIFEST row; their recipe lives only in their `.sheet.txt` "regenerate with" line and key-script header.
- Spec A10 says 33 tools read a `.sheet.txt`. Code that reads a fixture `.sheet.txt` file is 7 files (section 3 and section 1). The rest of the 22 files that say `.sheet.txt` mention it in comments. Other hits for "sheet.txt" (`logs/sheet.txt`, `0001-sheet.txt`) are live run dumps, not fixture sheets.
- `docs/VERIFICATION.md:59` says "53 exist"; there are 74.
- Spec section 8 names six old-format specimen users. Five more tools need old bytes: `check_spellflag_migrate.sh`, `check_spellflag_migrate6.sh`, `check_spells_widen.sh`, `check_racial_cannibalism.sh`, and probably `check_weapon_sets.sh`. One named tool (`check_spell_source_bits.sh`) does not read any `.sav` at all.

### 1. Every file that references a fixture

Commands and counts (excluding `tools/fixtures/chars/` itself, which holds the 223 fixture files: 74 .sav, 74 .sheet.txt, 74 .keys, 1 MANIFEST). `.beads/hooks` and `tools/gates` have 0 hits.

```
grep -rl  'fixtures/chars'        tools docs .beads/hooks | grep -v '^tools/fixtures/chars/'   -> 337 files, 454 lines
grep -rlE 'make_char_fixture'     tools docs .beads/hooks | grep -v '^tools/fixtures/chars/'   ->  34 files,  68 lines
grep -rlE 'check_char_fixture'    tools docs .beads/hooks | grep -v '^tools/fixtures/chars/'   ->  13 files,  19 lines
grep -rlE 'sync_char_fixtures'    tools docs .beads/hooks | grep -v '^tools/fixtures/chars/'   ->   2 files,   2 lines (both specs)
grep -rlE 'MANIFEST'              tools docs .beads/hooks | grep -v '^tools/fixtures/chars/'   ->   6 files,   7 lines (4 are unrelated MANIFEST words)
grep -rlE '\.sheet\.txt'          tools docs .beads/hooks | grep -v '^tools/fixtures/chars/'   ->  22 files,  37 lines
union of the six                                                                              -> 356 files
plus files naming a fixture by name only (no path), found by grepping the 74 names           ->  20 files
plus 1 file with a false hit (tools/check_citations.sh, matched by "chars/" glob)              ->   1 file
table rows below                                                                              -> 377 files
```

Fixture-name-only files (not matched by any of the six greps): `tools/check_fact_lines.py`, `tools/keys/{align-treachery-play,druid-shoulder-metal,elf-rogue-bluff-save,elude-death-main,elude-death-rider,engaged-hostile-save,held-mana-cast,inh-wasteful,mounted-cast-time,paralyzed-sheet,phase-plane-name,quality-self-immune-setup,rest-poison,spell-manager-order,tanglefoot-mount,undeath-to-death-pool-setup,weapon-sets-fixture,wood-elf-rogue-save,xp-penalty-crash}.keys`.

Roll-up of the table's target column: cache loaders 180, key scripts that only name a fixture in comments 147, retire 27 (fixture-only key scripts) + 2 (`make_char_fixture.sh`, `check_char_fixture.sh`), specimen 6, scene 4, live-engine value 2, shared-stay 4, doc 5 (+ dated specs and history, no change), `headless.sh` modify 1.

"map-dep" marks (heuristic, by comment text such as "a save pins the dungeon", "player square", "arrival map") a check whose facts read the SAVED MAP. Under the new design a built fixture has a fresh level 1, so these 31 checks lose their map unless they are reworked (spec section 9 forbids reading the map). This is a larger conversion cost than the spec's three scene fixtures suggest.

Targets: "cache" = keep `INCURSION_LOAD=<path>` (spec maps the old path form by name) or switch to the name; "fixture_sheet.sh" = read the cached sheet path; "specimen" = tracked frozen `.sav` in `tools/fixtures/specimens/`.

| file | how it uses the fixture | fixture(s) | target | map-dep |
|---|---|---|---|---|
| `docs/ENGINE-SERIALISATION.md` | doc | - | unrelated hit (save MANIFEST, not fixtures MANIFEST); no change |  |
| `docs/REPORTING-GATE.md` | doc | druid-shoulder-metal-seed7-opt0822, prestige-geomancy-seed1-opt0822, human-priest-mage-seed4-gate (+11 more) | doc update (optional): ledger prose names fixtures; no tool reads it |  |
| `docs/SAVE-SCHEMA-SPEC.md` | doc | - | doc update: line 748 "Every tools/fixtures/chars/*.sav loads" -> specimens dir (section 2) |  |
| `docs/VERIFICATION.md` | doc | orc-barbarian-seed1-opt0822 | doc update: controls catalog row for INCURSION_LOAD (stale count 53; B8/AC7) |  |
| `docs/rules-history/engine-data-knowledge.md` | doc | - | no change (dated spec/history record) |  |
| `docs/rules-history/test-harness-mechanics.md` | doc | - | no change (dated spec/history record) |  |
| `docs/specs/2026-09-18-headless-prompt-fixtures-brief.md` | doc | engaged-hostile | no change (dated spec/history record) |  |
| `docs/specs/2026-09-20-ability-descriptions-spec.md` | doc | - | no change (dated spec/history record) |  |
| `docs/specs/2026-10-06-landing-gate-split-spec.md` | doc | - | no change (dated spec/history record) |  |
| `docs/specs/2026-10-13-number-bands-brief.md` | doc | - | no change (dated spec/history record) |  |
| `docs/specs/2026-10-16-spell-loadout-brief.md` | doc | orc-mage-seed1-opt0822 | no change (dated spec/history record) |  |
| `docs/specs/2026-11-06-fixture-builder-brief.md` | doc | - | no change (dated spec/history record) |  |
| `docs/specs/2026-11-06-fixture-builder-spec.md` | doc | orc-barbarian-seed1-opt0818-store, levitate-bottom-seed1, engaged-hostile | no change (dated spec/history record) |  |
| `tools/README.md` | doc (tools index; five fixture references, check_char_fixture row at line 507) | - | doc update: remove check_char_fixture row, describe cache |  |
| `tools/ability_descs.live` | false hit: "MANIFEST" means something else here | - | no change |  |
| `tools/check_act_overflow.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_aid_casting_bonus.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822, orc-mage-seed4-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_align_treachery_play.sh` | loader via INCURSION_LOAD | elf-rogue-bluff-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_alignment_drain.sh` | loader via INCURSION_LOAD | alignment-drain-warrior | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_alignment_drain_death.sh` | loader via INCURSION_LOAD | alignment-drain-level1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_alignment_drain_edges.sh` | loader via INCURSION_LOAD | alignment-drain-lawful-neutral, alignment-drain-warrior, alignment-drain-level1, alignment-drain-level2 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_area_radius.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_aura_of_menace.sh` | loader via INCURSION_LOAD | orc-barbarian-ce-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_auto_terms.sh` | loader via INCURSION_LOAD | human-paladin-seed4-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_autoknock.sh` | loader via INCURSION_LOAD | orc-mage-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_autoloot_packs.sh` | loader via INCURSION_LOAD | orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_autopickup_packs.sh` | loader via INCURSION_LOAD | orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_bane_radius.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_belt_potion_stack.sh` | loader via INCURSION_LOAD | orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_blasphemy_fatigue.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_bolas_entangle_expiry.sh` | loader via INCURSION_LOAD | kobold-rogue-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_bonus_order.sh` | loader via INCURSION_LOAD | lizardfolk-monk-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_bow_blessing.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_cannibal_alignment.sh` | loader via INCURSION_LOAD | human-paladin-seed4-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_cast_rules.sh` | loader via INCURSION_LOAD | human-priest-mage-dual-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_cast_version.sh` | loader via INCURSION_LOAD | human-priest-mage-dual-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_caustic_vitae_acid.sh` | loader via INCURSION_LOAD | orc-mage-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_char_fixture.sh` | checker (loads lizardfolk-monk-seed1, compares name/race/class to its .sheet.txt, asserts sandbox copy) | lizardfolk-monk-seed1 | retire |  |
| `tools/check_chasm_swap.sh` | loader via INCURSION_LOAD | human-paladin-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_citations.sh` | false hit: "fixtures" in a printf test fixture | - | no change |  |
| `tools/check_cleave_illusion.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_cloak_damage_live.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_companion_trap.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_concentration.sh` | loader via INCURSION_LOAD | elf-mage-illusions-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_convert_guard.sh` | copies a v1 .sav to a scratch dir and runs -convert on it | human-priest-mage-seed4-gate | cache (needs a .sav PATH, not INCURSION_LOAD) |  |
| `tools/check_crowd_turn_cost.sh` | loader via INCURSION_LOAD | lizardfolk-monk-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_defnote.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_dequ_magic_hardness.sh` | loader via INCURSION_LOAD | quality-item-magic-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_dequ_reach.sh` | loader via INCURSION_LOAD | orc-warrior-dequ-seed5-maxhp | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_dequ_save_dc.sh` | loader via INCURSION_LOAD | dequ-save-dc-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_dequ_sunder.sh` | loader via INCURSION_LOAD | dequ-save-message-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_detonate_null_target.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_dig_zero_skill.sh` | loader via INCURSION_LOAD | gnome-warrior-wis3-pickaxe-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_dispel_evil.sh` | loader via INCURSION_LOAD | orc-priest-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_dmgpost_once.sh` | loader via INCURSION_LOAD | lizardfolk-monk-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_door_axe_wizlock.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_door_bolt.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_door_lock_rate.sh` | loader via INCURSION_LOAD | orc-mage-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_door_pick_kick.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_druid_staff_clev.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822, orc-priest-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_dungeonmap_bounds.sh` | loader of scene fixture levitate-bottom-seed1 (via levitate-bottom-load.keys) | levitate-bottom-seed1 | scene: wizard depth 10 + INCURSION_LEVITATE_CHASM hook (D2/A12) | map |
| `tools/check_dwarven_focus_manual.sh` | loader via INCURSION_LOAD | dwarf-barbarian-focus | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_edge_target.sh` | loader via INCURSION_LOAD | human-paladin-seed4-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_elemental_resistance_potion.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_elude_death_followup.sh` | loader via INCURSION_LOAD | dequ-save-message-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_exact_monster_depth.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_exchange_no_false_fumble.sh` | loader via INCURSION_LOAD | lizardfolk-monk-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_fact_lines.py` | name only (a fact-line example) | orc-mage-seed1-opt0822 | no change |  |
| `tools/check_favour_awards.sh` | loader via INCURSION_LOAD | lizardfolk-monk-seed1, kobold-rogue-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_fear_duration.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_feed_upon_pain.sh` | loader via INCURSION_LOAD | orc-priest-pain-seed1-sneakopts | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_field_grant_readers.sh` | false hit: "MANIFEST" means something else here | - | no change |  |
| `tools/check_follower_cap.sh` | loader via INCURSION_LOAD | orc-mage-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_glory.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_gravestone.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_grease_srd.sh` | loader via INCURSION_LOAD | human-paladin-seed4-grease-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_grow_noroom.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_headless.sh` | loader of scene fixture engaged-hostile (assertions 8-10) | engaged-hostile | scene: build with wizard summon (spec 8) | map |
| `tools/check_heal_maladies.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_held_mana.sh` | loader via INCURSION_LOAD | human-priest-mage-wounded-seed4-gate, human-priest-mage-seed4-gate, orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_hide_distraction.sh` | loader via INCURSION_LOAD | orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_hide_god_event.sh` | loader via INCURSION_LOAD | orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_hide_pairs.sh` | loader via INCURSION_LOAD | orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_hide_search.sh` | loader via INCURSION_LOAD | orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_hide_triggers.sh` | loader via INCURSION_LOAD | orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_holy_symbol_slots.sh` | loader via INCURSION_LOAD | orc-priest-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_hunger_clock.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_illusion_flags.sh` | loader via INCURSION_LOAD | elf-mage-illusions-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_illusion_spotted.sh` | loader via INCURSION_LOAD | elf-mage-illusions-seed1, elf-mage-spotted-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_inc_klenx.sh` | loader via INCURSION_LOAD | human-paladin-seed4-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_inh_wasteful.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0818 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_inherent_lucubration.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822, orc-mage-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_intensive_study_play.sh` | loader via INCURSION_LOAD | prestige-geomancy-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_inv_cursor.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_killxp_loop.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_knowledge_domain_sp.sh` | loader; comment cites sheet domains | human-priest-mage-seed4-gate | cache; comment update |  |
| `tools/check_known_trap_prompt.sh` | loader via INCURSION_LOAD | kobold-rogue-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_learn_table.sh` | loader via INCURSION_LOAD | human-priest-mage-dual-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_legend_lore.sh` | loader via INCURSION_LOAD | orc-bard-reapply-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_linux_save_roundtrip.sh` | --load of the .sav in Docker; reads .sheet.txt for name/race/class | lizardfolk-monk-seed1 | cache (built on host) + fixture_sheet.sh |  |
| `tools/check_loot_claim.sh` | loader via INCURSION_LOAD | human-paladin-seed4-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_lost_enemy.sh` | loader via INCURSION_LOAD | orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_mage_cast_nobook.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822, orc-mage-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_mage_loadout.sh` | loader; comment names .sheet.txt (kit/spells) | orc-mage-seed1-opt0822 | cache; comment update |  |
| `tools/check_mana_regen_cast.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_mana_regen_floor.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_mark_of_punishment.sh` | loader via INCURSION_LOAD | human-paladin-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_monster_feats_live.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_monster_init_hp.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_monster_memory.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_monster_route_to_target.sh` | loader via INCURSION_LOAD | kobold-rogue-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_monwield_drain.sh` | loader via INCURSION_LOAD | orc-mage-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_mount_size.sh` | loader via INCURSION_LOAD | human-paladin-seed4-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_mounted_cast_time.sh` | loader via INCURSION_LOAD | orc-mage-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_music_choir.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_music_spheres_area.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_natural_healing.sh` | loader via INCURSION_LOAD | orc-mage-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_natural_one_attack.sh` | loader via INCURSION_LOAD | orc-mage-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_natural_save.sh` | loader via INCURSION_LOAD | human-paladin-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_newlevel_divine_spell.sh` | loader via INCURSION_LOAD | orc-priest-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_owner_damage_immune.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_paralyzed_sheet.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_peaceful_mindless.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_pray_aid_int32.sh` | loader via INCURSION_LOAD | dequ-save-message-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_quality_item_magic.sh` | loader via INCURSION_LOAD | quality-item-magic-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_quality_plus.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_quality_self_immune.sh` | loader via INCURSION_LOAD | orc-mage-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_racial_cannibalism.sh` | loader of characters "made BEFORE the change" (no Cannibalism feat); also greps .sheet.txt for Cannibalism | orc-barbarian-seed1-opt0822, dragonkin-sheet-seed1-opt0818 | specimen (+ sheet guard goes away) |  |
| `tools/check_rapid_reload.sh` | loader via INCURSION_LOAD | prestige-geomancy-seed1-opt0822, spook-ally-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_read_light.sh` | loader; comment says options/seed come from the .sheet.txt header | 3 fixtures | cache; comment update (header moves to .char) |  |
| `tools/check_readline_overflow.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_reapply_single_grant.sh` | loader via INCURSION_LOAD | orc-barbarian-reapply-seed4, orc-bard-reapply-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_remove_field_event.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_repair_cost.sh` | loader via INCURSION_LOAD | human-paladin-damaged-armour-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_rest_per_source.sh` | loader of 3 saves + greps .sheet.txt Inventory block for "book" | human-priest-mage-seed4-gate, orc-priest-seed4-gate, orc-bard-reapply-seed1 | cache + replace sheet grep with live inventory read |  |
| `tools/check_rest_poison.sh` | loader via INCURSION_LOAD | orc-barbarian-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_reverie_rest.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_roark_stock.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_route_unseen.sh` | loader via INCURSION_LOAD | kobold-rogue-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_runto_hazards.sh` | loader via INCURSION_LOAD | kobold-rogue-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_script_loops.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_script_map_read.sh` | loader via INCURSION_LOAD | orc-mage-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_script_var_recovery.py` | reads .sav bytes (glob of every chars/*.sav; IS1.3 rev-3 payloads) | 47 IS1.3 saves | specimen (IS1.3 set) |  |
| `tools/check_seneschal.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_seneschal_implemented.sh` | loader via INCURSION_LOAD | lizardfolk-monk-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_shop_markup.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_skc6_blast_text.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_sleep_quality.sh` | loader via INCURSION_LOAD | human-paladin-seed4-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_sneak_invis.sh` | loader via INCURSION_LOAD | orc-rogue-sneak-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_soak_torch.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_soften_stone_golem.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_spell_durations.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_spell_manager_order.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_spell_source_bits.sh` | name or path in comments/messages only | orc-priest-seed4-gate, orc-mage-seed4-gate | no change; comment update |  |
| `tools/check_spell_src_column.sh` | loader via INCURSION_LOAD | underdark-deepgnome-seed3-opt0818 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_spell_tags.sh` | loader via INCURSION_LOAD | human-priest-mage-dual-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_spellflag_migrate.sh` | loader of an IS1.3 file; asserts migrated=1 rev=3 | orc-mage-seed1-opt0822 | specimen |  |
| `tools/check_spellflag_migrate6.sh` | loader of two IS1.3 files; asserts migrated=1 and rev from the file stamp | orc-mage-seed1-opt0822, orc-priest-seed4-gate | specimen |  |
| `tools/check_spells_widen.sh` | python reader of retired tag 434 in a pre-change IS1.6 file, plus an IS1.3 loader | human-priest-mage-seed4-gate, orc-priest-seed4-gate | specimen |  |
| `tools/check_spook_mount.sh` | loader via INCURSION_LOAD | spook-mount-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_stale_death_prompt.sh` | loader via INCURSION_LOAD | low-dex-orc-barbarian-seed18-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_stinking_cloud_dc.sh` | loader + sheet reader (WIS/CHA modifier from .sheet.txt) | elf-mage-illusions-seed1 | live engine value (section 3) | map |
| `tools/check_stinking_cloud_prompt.sh` | loader via INCURSION_LOAD | elf-mage-illusions-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_stone_to_flesh.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_stone_to_flesh_statue.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_stoning_duration.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_store_find.sh` | loader of scene fixture (Roark visited once) | orc-barbarian-seed1-opt0818-store | scene: storeSeed (spec 8) |  |
| `tools/check_storycraft.sh` | loader via INCURSION_LOAD | orc-bard-reapply-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_study_slots.sh` | loader via INCURSION_LOAD | prestige-geomancy-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_stun_duration.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_summoned_inventory.sh` | loader via INCURSION_LOAD | orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_surrender_lein.sh` | loader via INCURSION_LOAD | kobold-rogue-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_swarm_theft.sh` | loader via INCURSION_LOAD | skill-by-name-seed1-opt0818, alignment-drain-warrior | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_tanglefoot_mount.sh` | loader via INCURSION_LOAD | human-paladin-seed4-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_target_order.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0818 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_template_alignment.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_template_pair_refused.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_terraform_edge.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_track_only_no_cast.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_trap_attack.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822, orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_trip_aoo.sh` | loader via INCURSION_LOAD | dequ-save-message-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_true_blows.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_true_illusions.sh` | loader via INCURSION_LOAD | elf-mage-illusions-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_two_fist_feats_live.sh` | loader; failure message names make_char_fixture.sh; literals 125/175 (derived speed) | lizardfolk-monk-barehand-seed1 | cache; edit failure message |  |
| `tools/check_undead_mount.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_undeath_to_death_pool.sh` | loader via INCURSION_LOAD | orc-priest-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_use_menu_skills.sh` | loader via INCURSION_LOAD | kobold-rogue-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_valour_ally_message.sh` | loader via INCURSION_LOAD | human-paladin-seed4-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_vararg_format_live.sh` | cp of the .sav into a scratch module run; -load direct (not INCURSION_LOAD) | lizardfolk-monk-seed1 | specimen (map content: corpses) - see section 2 | map |
| `tools/check_wake_all.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_water_walking_potion.sh` | loader via INCURSION_LOAD | orc-mage-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_weapon_sets.sh` | loader + contains a --make-fixture maker block (calls make_char_fixture.sh) | weapon-sets-old-defaults, lizardfolk-monk-seed1, dequ-save-message-seed5-opt0822 | cache; delete the --make-fixture block; weapon-sets-old-defaults old-defaults premise needs decision (section 2) | map |
| `tools/check_weapon_types.sh` | loader; fact line reads proficiencies from fixture sheet | orc-mage-seed4-gate | cache; derived proficiency fact (section 3) |  |
| `tools/check_wildshape_cheetah_desc.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_wildshape_gray.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_wrought_hardness.sh` | loader via INCURSION_LOAD | xsummon-priest-seed5-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_wrought_metal.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/check_xp_penalty.sh` | loader via INCURSION_LOAD | wood-elf-rogue-seed7-opt0818 | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_yuse_no_effect.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) | map |
| `tools/check_zen_defense.sh` | loader via INCURSION_LOAD | lizardfolk-monk-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/fixtures/README.md` | doc (fixture system) | - | rewrite for .char + cache + specimens |  |
| `tools/formend_hp.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/headless.sh` | loader implementation (INCURSION_LOAD copies the .sav into the run sandbox) | - | modify: build on miss, map name/path form, exit 8 |  |
| `tools/keys/align-treachery-play.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | elf-rogue-bluff-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/alignment-drain-fixture.keys` | fixture-only key script (maker) | alignment-drain-warrior, quality-item-magic-seed5-opt0822 | retire |  |
| `tools/keys/alignment-drain-lawneutral-save.keys` | fixture-only key script (maker) | alignment-drain-lawful-neutral | retire |  |
| `tools/keys/alignment-drain-level1-fixture.keys` | fixture-only key script (maker) | alignment-drain-level1, quality-item-magic-seed5-opt0822 | retire |  |
| `tools/keys/alignment-drain-level2-fixture.keys` | fixture-only key script (maker) | alignment-drain-level2, quality-item-magic-seed5-opt0822 | retire |  |
| `tools/keys/alignment-drain-wield.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | alignment-drain-warrior | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/aura-of-menace-hit.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-ce-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/aura-of-menace-save.keys` | fixture-only key script (maker) | orc-barbarian-ce-opt0822 | retire |  |
| `tools/keys/aura-of-menace.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-ce-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/auto-terms-natural.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-seed4-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/bolas-entangle-expiry.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | kobold-rogue-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/cannibal-human-other.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-seed4-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/cannibal-human-own.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-seed4-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/cast-version-dual.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-priest-mage-dual-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/caustic-vitae-acid.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/caustic-vitae-control.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/char-abilities-any.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | - | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/char-abilities.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/chargen-default-save.keys` | fixture key script AND shared: check_linux_save_roundtrip.sh Case A runs it (CHARGEN_KEYS) | several | stay (shared); drop from fixture recipe |  |
| `tools/keys/chargen-default-store-save.keys` | fixture-only key script (maker) | orc-barbarian-seed1-opt0818-store, orc-barbarian-seed1-opt0818 | retire |  |
| `tools/keys/chargen-mage-save.keys` | fixture key script AND shared: check_spell_source_bits.sh runs it (fresh chargen probe) | several | stay (shared); drop from fixture recipe |  |
| `tools/keys/chargen-paladin-save.keys` | fixture-only key script (maker) | - | retire |  |
| `tools/keys/chargen-priest-save.keys` | fixture key script AND shared: check_spell_source_bits.sh runs it (fresh chargen probe) | several | stay (shared); drop from fixture recipe |  |
| `tools/keys/chargen-rogue-save.keys` | fixture-only key script (maker) | - | retire |  |
| `tools/keys/cleave-illusion.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/concentration-core.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | elf-mage-illusions-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/death-confirm.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | engaged-hostile | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/death-freeze.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | engaged-hostile | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/defnote-blinding.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/defnote-combatmind.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/defnote-dispelevil.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/defnote-nemesis.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/defnote-shield-hit.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/defnote-shield.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/defnote-water-aerial.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/defnote-water.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/defnote-wrap.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/dequ-reach.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-warrior-dequ-seed5-maxhp | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/dequ-save-dc-save.keys` | fixture-only key script (maker) | dequ-save-dc-seed5-opt0822 | retire |  |
| `tools/keys/dequ-save-dc-setup-loaded.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | dequ-save-dc-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/dequ-save-message-loaded.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | dequ-save-message-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/dequ-setup-loaded.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | dequ-save-message-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/dig-zero-skill.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | gnome-warrior-wis3-pickaxe-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/dmgpost-chaos.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | lizardfolk-monk-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/druid-shoulder-metal.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | druid-shoulder-metal-seed7-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/edge-target.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-seed4-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/elf-mage-illusions-save.keys` | fixture-only key script (maker) | elf-mage-illusions-seed1 | retire |  |
| `tools/keys/elf-mage-spotted-save.keys` | fixture-only key script (maker) | elf-mage-illusions-seed1, elf-mage-spotted-seed1 | retire |  |
| `tools/keys/elf-rogue-bluff-save.keys` | fixture-only key script (maker) | elf-rogue-bluff-seed1-opt0822 | retire |  |
| `tools/keys/elf-search-loaded.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | elf-search-seed1-opt0818 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/elude-death-main.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | dequ-save-message-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/elude-death-rider.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | dequ-save-message-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/engaged-hostile-save.keys` | fixture-only key script (maker) | engaged-hostile | retire |  |
| `tools/keys/engulf-stale-prompt.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | low-dex-orc-barbarian-seed18-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/exchange-no-defaults.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | lizardfolk-monk-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/favour-devour-khasrach.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | lizardfolk-monk-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/favour-devour-zurvash.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | lizardfolk-monk-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/favour-insight.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | lizardfolk-monk-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/favour-trap.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | kobold-rogue-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/follower-cap.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/formend-hp.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | druid-shoulder-metal-seed7-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/gnome-warrior-pickaxe-save.keys` | fixture-only key script (maker) | gnome-warrior-wis3-pickaxe-seed1-opt0822 | retire |  |
| `tools/keys/gravestone.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/grease-srd-setup.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-seed4-grease-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/held-mana-cast.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-priest-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/held-mana-floor.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/holy-symbol-slot.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-priest-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/illusion-spotted-creature.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | elf-mage-spotted-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/illusion-spotted-force-goblin.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | elf-mage-spotted-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/illusion-spotted-force-vizier.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | elf-mage-spotted-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/inc-moh9-darkvision-scene.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | kobold-rogue-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/inh-wasteful.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-opt0818 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/intensive-study-caster-sheet.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | prestige-geomancy-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/knowledge-sp-mage.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-priest-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/knowledge-sp-priest.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-priest-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/known-trap-prompt.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | kobold-rogue-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/learn-table-check.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-priest-mage-dual-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/learn-table-summary.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-priest-mage-dual-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/legend-lore-item.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-bard-reapply-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/levelup-caster-sheet.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/levitate-bottom-load.keys` | key script run on the loaded scene fixture | levitate-bottom-seed1 | scene: rewrite with the D2 hook |  |
| `tools/keys/lizardfolk-monk-barehand-save.keys` | fixture-only key script (maker) | lizardfolk-monk-seed1 | retire |  |
| `tools/keys/lizardfolk-monk-save.keys` | fixture-only key script (maker) | - | retire |  |
| `tools/keys/load-char-sheet.keys` | shared loader key script (dumps arrival/played/sheet/saved); used by check_char_fixture and linux roundtrip | any | stay (comments update) |  |
| `tools/keys/lootclaim-b-thief-attack.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-seed4-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/lootclaim-b0-fleeing-control.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-seed4-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/lootclaim-d-claim-ends.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-seed4-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/low-dex-orc-barbarian-save.keys` | fixture-only key script (maker) | - | retire |  |
| `tools/keys/mage-cast-nobook.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/mage-loadout-rest.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/mana-regen-cast.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/mark-of-punishment.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/monk-ki-strike-loaded.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | monk-ki-strike-seed1-opt0818 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/monk-tempest.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | lizardfolk-monk-barehand-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/monk-weapon-immunity-loaded.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | monk-weapon-immunity-seed1-opt0818 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/monster-memory-kills.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/monster-memory-seen.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/monster-memory-unmet.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/mounted-cast-time.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/music-choir.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | xsummon-priest-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/natural-one-attack.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/newlevel-divine-mark.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-priest-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/pain-experiment.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-priest-pain-seed1-sneakopts | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/pain-giant.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-priest-pain-seed1-sneakopts | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/pain-priest-wounded-save.keys` | fixture-only key script (maker) | orc-priest-pain-seed1-sneakopts | retire |  |
| `tools/keys/paralyzed-sheet.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/phase-plane-name.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/priest-cast-nosymbol.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | xsummon-priest-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/priest-mage-wounded-save.keys` | fixture-only key script (maker) | human-priest-mage-wounded-seed4-gate | retire |  |
| `tools/keys/quality-item-magic-save.keys` | fixture-only key script (maker) | quality-item-magic-seed5-opt0822 | retire |  |
| `tools/keys/quality-self-immune-plain.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/quality-self-immune-quality.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/quality-self-immune-setup.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/readline-overflow.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/reapply-activation.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-reapply-seed4 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/reapply-barbarian-save.keys` | fixture-only key script (maker) | orc-barbarian-reapply-seed4 | retire |  |
| `tools/keys/reapply-bard-save.keys` | fixture-only key script (maker) | - | retire |  |
| `tools/keys/reapply-dispel.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-reapply-seed4 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/reapply-enchant.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-bard-reapply-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/reapply-hp.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-bard-reapply-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/reapply-magic-weapon.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-reapply-seed4 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/repair-cost-damage-save.keys` | fixture-only key script (maker) | human-paladin-damaged-armour-opt0822, human-paladin-seed4-opt0822 | retire |  |
| `tools/keys/repair-cost.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-damaged-armour-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/rest-per-source-restonly.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | - | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/rest-per-source-swap.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-priest-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/rest-poison.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/route-unseen.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | kobold-rogue-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/runto-effect.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | kobold-rogue-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/runto-hazard.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | kobold-rogue-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/runto-monster.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | kobold-rogue-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/seneschal-levelup-feat.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | lizardfolk-monk-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/sneak-invis-blindfight.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-rogue-sneak-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/sneak-invis-melee.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-rogue-sneak-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/sneak-invis-ranged.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-rogue-sneak-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/soften-stone-golem.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | druid-shoulder-metal-seed7-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/soften-stone-orc.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | druid-shoulder-metal-seed7-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/soften-stone-wall.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | druid-shoulder-metal-seed7-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/spell-manager-order.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/spell-tags.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-priest-mage-dual-seed4-gate | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/spellflag-migrate.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-mage-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/spook-ally-loaded.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | spook-ally-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/spook-mount-loaded.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | spook-mount-seed5-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/store-find.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-opt0818-store | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/storycraft-confirm.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-bard-reapply-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/storycraft-menu.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-bard-reapply-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/surrender-lein-message.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | kobold-rogue-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/tanglefoot-mount.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-seed4-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/target-ring.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-barbarian-seed1-opt0818 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/threat-freeze.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | engaged-hostile | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/touch-defence.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | elf-mage-illusions-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/undeath-to-death-pool-setup.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-priest-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/undeath-to-death-pool.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | orc-priest-seed1-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/use-menu-skills.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | kobold-rogue-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/valour-ally-message.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | human-paladin-seed4-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/weapon-sets-fixture.keys` | fixture-only key script (maker) | dequ-save-message-seed5-opt0822 | retire |  |
| `tools/keys/wildshape-cheetah-desc.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | druid-shoulder-metal-seed7-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/wildshape-gray.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | druid-shoulder-metal-seed7-opt0822 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/wood-elf-rogue-save.keys` | fixture-only key script (maker) | wood-elf-rogue-seed7-opt0818 | retire |  |
| `tools/keys/xp-penalty-crash.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | wood-elf-rogue-seed7-opt0818 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/yam9-disbelief-removal.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | elf-mage-spotted-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/yam9-removal.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | elf-mage-illusions-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/keys/yam9-spectral.keys` | key script run on a loaded fixture; names it in comments only (the check sets INCURSION_LOAD) | elf-mage-illusions-seed1 | no change (comment-only name); update comment if the path form is dropped |  |
| `tools/make_char_fixture.sh` | maker (key script to .sav + .keys copy + .sheet.txt) | all 74 | retire |  |
| `tools/measure_swarm_theft.sh` | loader via INCURSION_LOAD | alignment-drain-warrior | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/observe_hide_strike.sh` | loader via INCURSION_LOAD | orc-rogue-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/observe_monster_route.sh` | loader via INCURSION_LOAD | kobold-rogue-seed1 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/repro_concentration_orn8n.py` | name or path in comments/messages only | elf-mage-illusions-seed1 | no change; comment update |  |
| `tools/repro_d9gk_shoulder.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/repro_dispel_evil_inc_wn6m.md` | loader via INCURSION_LOAD | orc-priest-seed4-gate | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/repro_inc_b0ii.sh` | loader via INCURSION_LOAD | druid-shoulder-metal-seed7-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/repro_inc_gapb.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/repro_light_trap.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/repro_phase_plane_name.sh` | loader via INCURSION_LOAD | orc-barbarian-seed1-opt0822 | cache: INCURSION_LOAD=<name> (path form mapped by name) |  |
| `tools/swarm_theft_results.py` | sheet reader: level, BAB, STR/DEX mod, Pick Pockets from .sheet.txt | skill-by-name-seed1-opt0818, alignment-drain-warrior | live engine value (section 3); fixture_sheet.sh only for level |  |

The `tools/fixtures/chars/*.keys` copies (74 files) and `MANIFEST` and the `.sav`/`.sheet.txt` pairs are the fixture files themselves: all retire or move to the cache (specimens aside).

### 2. Old-format specimen users

Header stamps of the 74 saves: 47 IS1.3, 2 IS1.4, 25 IS1.6 (read from bytes 4-8 of each file).
IS1.4 files: druid-shoulder-metal-seed7-opt0822, orc-bard-reapply-seed1. The 25 IS1.6 files were regenerated recently; the IS1.3 and IS1.4 files are the only possible old-byte specimens.

Verdicts for the six the spec names:

| tool | needs old bytes? | deciding line |
|---|---|---|
| `check_script_var_recovery.py` | YES. Reads the bytes of every IS1.3 save | line 131 `files += sorted(d.glob('*.sav'))` over `SAVE_DIRS = [ROOT/'tools/fixtures/chars']` (line 28); docstring lines 9-14: "The expected values are built from the SAVE's own rev-3 payloads, with the documented pre-fix IS1.3 layout"; `is_is13` filter `p.read_bytes()[4:9] == b'IS1.3'`. Also reads two home saves (Keos, Zakfienal). A rebuilt save is IS1.6 and would drop out of the filter, so the check would go red or vacuous. Specimen set: all 47 IS1.3 files unless a run shows which carry nonzero script-variable units (I did not run it; line 20 names levitate-bottom-seed1.sav row 0 word0 0x174de8). |
| `check_convert_guard.sh` | NO. Needs a current v1 save, any content | lines 28-30: "A scratch copy of a committed v1 character fixture refuses with exit 2 and stays byte-identical"; line 47 `V1_FIX=.../human-priest-mage-seed4-gate.sav`; lines 127-134 copy it and `-convert` it. The old-v0 evidence saves are `docs/evidence/inc-upw.13/*.sav`, not fixtures. It needs a .sav PATH, so it needs a `fixture_sav` print tool or a cache-path helper (spec A10 gives only `fixture_sheet.sh`). Target: cache. |
| `check_spell_source_bits.sh` | NO. Reads no `.sav` | lines 24-32: "Two fresh characters, one keys script each, both at seed 4"; it runs `tools/keys/chargen-priest-save.keys` and `chargen-mage-save.keys` through `check_run`. The fixture `.keys` is mentioned only to say it is byte-identical. The probe fires "at the end of Player::Create so a freshly generated character can be probed with no save" (line 17), so a `.char` build would skip the code under test. Target: stays on key scripts; those two key scripts become shared, not retired. |
| `check_linux_save_roundtrip.sh` | NO for bytes; YES for "written by the macOS host" | lines 12-13: "Case B a save made on macOS (the frozen lizardfolk-monk-seed1.sav) is LOADED on Linux". Any save written by the host binary meets that, if the cache is built on the host before Docker takes it (`--load "$save"`, line 152). Name, race and class come from the sheet (`expected_from_sheet`, lines 130-136): those are creation values, so `fixture_sheet.sh` is acceptable. Reasoned. Target: cache + fixture_sheet.sh. |
| `check_vararg_format_live.sh` | NOT old format. Needs saved MAP content | header lines 9-10: "The handler sits on the corpse item: the fixture stands among corpses, and every map thing gets EV_TURN once per 60 game turns". Line 50 `cp "$FIX" "$W/save/"`, line 52 `-load` against a scratch-compiled module (line 47). A built fixture starts on a fresh level 1 with no corpse item, so the EV_TURN handler may never fire (the check then reports no gameplay/marker). Reasoned. Target: specimen of lizardfolk-monk-seed1.sav, or a scene that creates a corpse with the wizard. Also bypasses `INCURSION_LOAD` (uses `-load` directly). |
| `swarm_theft_results.py` | NO | line 40 reads `{name}.sheet.txt`; it needs a character, not bytes. It reads DERIVED values (section 3). `measure_swarm_theft.sh:12` and `check_swarm_theft.sh:39` load by `INCURSION_LOAD` (cache). |

Five more tools that need old bytes, not named by the spec:

| tool | deciding line |
|---|---|
| `check_spellflag_migrate.sh` | lines 17-19: "Run A loads tools/fixtures/chars/orc-mage-seed1-opt0822.sav and must report migrated=1 with the file's own revision. That fixture is IS1.3, so the expected line is migrated=1 rev=3." A rebuilt save is IS1.6: migrated=0. Specimen: orc-mage-seed1-opt0822. |
| `check_spellflag_migrate6.sh` | lines 27, 36: mage `orc-mage-seed1-opt0822.sav` "an IS1.3 save", priest `orc-priest-seed4-gate.sav` "also IS1.3"; line 119 and 254 read the `IS1.<n>` stamp with `dd skip=4 count=5`. Specimens: both. |
| `check_spells_widen.sh` | lines 32-41: IS1.6 `human-priest-mage-seed4-gate.sav` "written by master BEFORE this change" whose retired tag-434 array a python reader parses; IS1.3 `orc-priest-seed4-gate.sav` "whose flags ARE migrated on load". Lines 58, 60: `FIXTURE`, `LEGACY`. Specimens: both. |
| `check_racial_cannibalism.sh` | lines 21-24: cases 4 and 5 load `orc-barbarian-seed1-opt0822.sav` and `dragonkin-sheet-seed1-opt0818.sav`, "made BEFORE the change"; lines 55-60 return INCONCLUSIVE when the fixture sheet "already lists Cannibalism, so it is not a pre-change character". A rebuilt character always has the feat. Specimens: both; the sheet grep needs a frozen `.sheet.txt` beside each specimen. |
| `check_weapon_sets.sh` | fixture name `weapon-sets-old-defaults`; lines 159-163 `old()` expects hands `[('long sword','orcish dagger'), ('short bow','short bow'), ...]` and raises "old fixture did not start with sword + dagger". It tests that a character saved under the old two-set defaults keeps behaving. Reasoned: the fixture is a hand-arranged old-defaults state and a new build may seed new defaults. Probable specimen; a decision for the plan. |

Also noted: `check_auto_terms.sh` lines 58-60 say its fixture "was written before OPT_SETTINGS_GEN existed"; the stamp is in the options file the check patches (lines 91-94), not the save, so the cache is safe (cache).

`docs/SAVE-SCHEMA-SPEC.md:748` states "Every `tools/fixtures/chars/*.sav` loads": that requirement is a specimen requirement too.

### 3. Checks that assert on a derived sheet value

A = reads it from a fixture `.sheet.txt` at run time. B = literal in code. C = literal in a comment or fact line, with code depending on it.

| class | file:line | value | live engine source to read instead |
|---|---|---|---|
| A | `tools/check_stinking_cloud_dc.sh:59-65` (`sheet_mod`), used at 68-69 | WIS and CHA modifier from `WIS: 16/00 [+3/+2]` | `Creature::Mod(A_WIS)` / `Mod(A_CHA)` (`src/Creature.cpp:3461`); in a run, the live sheet dump of that session |
| A | `tools/swarm_theft_results.py:39-48` (`sheet()`), used at 93-96 | level, melee BAB (`Melee +toHit ... (Warrior +n)`), STR and DEX modifier, Pick Pockets rank//3 | `INCURSION_CHAR_PROBE=1` writes the live `logs/charprobe.txt` (`src/Registry.cpp:1094-1117`, `Dump.cpp`); the check already sets it (`check_swarm_theft.sh:40`); `Creature::Mod`; `Creature::SkillLevel` (`src/Create.cpp:32,5467`) |
| A (non-derived) | `tools/check_linux_save_roundtrip.sh:77,130-136` | name, race, class | creation values; `fixture_sheet.sh` is acceptable |
| A (borderline) | `tools/check_rest_per_source.sh:164` | Inventory block holds no "book" (kit contents come from creation rules) | read the run's own inventory dump instead |
| A (guard) | `tools/check_racial_cannibalism.sh:55-60` | feat list lacks Cannibalism | see section 2 (specimen) |
| B | `tools/check_known_trap_prompt.sh:42` `want=4` | Reflex save +4 (Rogue +2, Dex +4, encumbrance -2); feeds the % to-avoid compare at 43-50 | `Creature::SaveChance` (`src/Creature.cpp:3889`) via `INCURSION_CHANCE_PROBE` -> `logs/chance_probe.log` (`src/Skills.cpp:1675-1688`) |
| B | `tools/check_two_fist_feats_live.sh:61-63` `WANT_BEFORE=125`, `WANT_AFTER=175` | Brawl-row speed % (Monk 1 / Warrior 9/10) | the live sheet row in the run's own dump (the check already reads it); the literals derive from class tables, so read the pre-feat value and assert only the +50 delta |
| B | `tools/check_dequ_save_dc.sh:76,87` | all saves DC 11; predicted 45-60% (a function of the fixture's Reflex, DEX 13) | `chance_probe.log` lines `save <type> <DC> <pred%>`; assert the DC column only |
| B | `tools/check_stinking_cloud_prompt.sh:19,35-36,94,99` | base Fortitude +0, `WARN_SAVE_DC-1` / `WARN_SAVE_DC` boundary (`INCURSION_FORT_PROBE` adds N to the base, `src/Values.cpp:1137-1140`) | read the base Fortitude from the first live sheet dump of the session, then add the probe value |
| B | `tools/check_dig_zero_skill.sh:54,130-137` | Mining +0 (divisor 0): "0 ranks, -4 WIS, +2 train, +2 kit" | `Creature::SkillLevel(SK_MINING)`; or make the divisor 0 by construction (set the inputs the check controls) |
| B | `tools/check_sleep_quality.sh:12-13` (+ `src/SleepQualityProbe.cpp:112`) | "the fixture's own margin is 6, so the real margin is 4"; setup=0 unless margin exactly 4 | the probe already logs `margin=vRoll+vHit-vDef`; the check reads it and refuses the case; keep reading, drop the "fixture margin is 6" assumption |
| B | `tools/check_stale_death_prompt.sh:24,40` | DEX 7, Reflex -1; the engulf save DC 15 | `chance_probe.log` Reflex line; `Creature::Mod(A_DEX)` |
| B | `tools/check_grease_srd.sh:19-22` | Balance -1: "roll R gives total R-1" | `Creature::SkillLevel(SK_BALANCE)` via `chance_probe.log` skill lines (`INCURSION_CHANCE_PROBE`) |
| C | `tools/check_align_treachery_play.sh:24,34` | Bluff +7, Diplomacy +5, Intimidate +5 | `Creature::SkillLevel`; the run's sheet dump |
| C | `tools/check_caustic_vitae_acid.sh:27` | Wis mod 3 | `Creature::Mod(A_WIS)` |
| C | `tools/check_quality_self_immune.sh:10` | enchant limit = level 5 + Charisma modifier | `Creature::Mod(A_CHA)` and live level |
| C | `tools/check_entangled_acts.sh:18` (+205) | "Reflex +5 on seed 4, a 55% chance per roll" (a rolled-probability premise); 205: live `Melee +toHit +0 ... -2 status` regex | `chance_probe.log`; the live sheet |
| C | `tools/check_weapon_types.sh:36` | follower not proficient with bows/bolts: "the fixture's sheet (Long Blades, Staves, Impact...)" | `Creature::HasFeat` / weapon proficiency of the live creature |
| C | `tools/check_alignment_drain.sh:18-29,98-121` and `check_alignment_drain_edges.sh:25` | Fort/Ref/Will, Damage and Speed lines of the run's own sheets | already read live from run dumps, compared relatively to sheet-0; no `.sheet.txt` read. No change needed |
| C | `tools/keys/monster-memory-seen.keys:18` | "fixture sheet gives damage 1d3+5" | live sheet damage line |
| C | `tools/keys/touch-defence.keys:12-18` | "Defense Class breakdown is (base 10, +2 Dex, -1 encumbrance)" read from `elf-mage-illusions-seed1.sheet.txt` | the live sheet in the run |

Total: 5 A rows (2 derived values; 3 non-derived, borderline or guard), 8 B, 8 C (1 of which, alignment_drain, needs no change). Rows with no `.sheet.txt` read and no derived literal (relative or live reads) are left out.

### 4. The 74 fixtures

Columns come from each `.sheet.txt` header (seed, settings, key script) and the key script text (resolved through `@include`). "stamp" is the file's IS1.n header. Post-creation work is any key after the character is created and before the save. "SCENE" marks the three scene fixtures. Chained = made with `INCURSION_LOAD` of another fixture (stated in the key script header; the sheet's "regenerate with" line omits it).

Summary: 74 fixtures; 49 distinct fixture key scripts (plus 8 include-only helpers); 24 with post-creation work (including options alteration at creation); 5 chained (alignment-drain-level1, alignment-drain-level2, alignment-drain-warrior from quality-item-magic-seed5-opt0822; human-paladin-damaged-armour-opt0822 from human-paladin-seed4-opt0822; weapon-sets-old-defaults from dequ-save-message-seed5-opt0822); 3 scenes. 3 recipes depend on env vars the sheet cannot record: priest-mage-wounded and pain-priest (INCURSION_LOF_FORCE_ROLL=20, INCURSION_FORCE_DAMAGE_ROLL=3), levitate-bottom (INCURSION_LEVITATE_CHASM=1).

Dropped 2026-11-11 (inc-10v7f): 11 of these 74 were loaded by no check or key script, so their .sav, .keys and .sheet.txt files and their MANIFEST rows are removed instead of converted: circle-stack-adjust-seed20260905-gate, orc-barbarian-seed3-gate, orc-barbarian-seed4-gate, orc-barbarian-seed11-gate, orc-barbarian-seed3390-gate, orc-barbarian-seed20260905-gate, orc-barbarian-seed7-opt0818, orc-rogue-seed1-gate, orc-rogue-seed1-opt0818, prestige-earthsinger-seed3-opt0818, prestige-earthsinger-seed3-opt0822. The table below keeps their rows as the survey found them.

| # | fixture | stamp | key script | seed | options | post-creation work | chained from | scene |
|---|---|---|---|---|---|---|---|---|
| 1 | `alignment-drain-lawful-neutral` | IS1.6 | `alignment-drain-lawneutral-save.keys` | 1 | options-2026-08-22.dat | wizard on; Genocide Everything (clear level). Creation includes god pick (lawful neutral human warrior) | - | - |
| 2 | `alignment-drain-level1` | IS1.6 | `alignment-drain-level1-fixture.keys` | 5 | options-2026-08-22.dat | wizard on; Genocide Everything; sheet view only | quality-item-magic-seed5-opt0822 | - |
| 3 | `alignment-drain-level2` | IS1.6 | `alignment-drain-level2-fixture.keys` | 5 | options-2026-08-22.dat | wizard on; Genocide Everything; "Generate 50 XP Ticks" x20 (xp:) | quality-item-magic-seed5-opt0822 | - |
| 4 | `alignment-drain-warrior` | IS1.6 | `alignment-drain-fixture.keys` | 5 | options-2026-08-22.dat | wizard on; Genocide Everything; "Generate 50 XP Ticks" x200 (xp:); G level-up x4 to Warrior 5 (level:) | quality-item-magic-seed5-opt0822 | - |
| 5 | `circle-stack-adjust-seed20260905-gate` | IS1.3 | `circle-stack-adjust-save.keys` | 20260905 | tools/gates/Options.Dat | none (creation only) | - | - |
| 6 | `dequ-save-dc-seed5-opt0822` | IS1.6 | `dequ-save-dc-save.keys` | 5 | options-2026-08-22.dat | none (creation only) | - | - |
| 7 | `dequ-save-message-seed5-opt0822` | IS1.3 | `dequ-save-message-save.keys` | 5 | options-2026-08-22.dat | none (creation only) | - | - |
| 8 | `dragonkin-sheet-seed1-opt0818` | IS1.3 | `dragonkin-sheet-save.keys` | 1 | options-2026-08-18.dat | none (creation only) | - | - |
| 9 | `druid-shoulder-metal-seed7-opt0822` | IS1.4 | `druid-shoulder-metal-save.keys` | 7 | options-2026-08-22.dat | wizard on; Item Acquisition long sword (item:); place on L. Shoulder (place:); creation spell marks | - | - |
| 10 | `dwarf-barbarian-focus` | IS1.6 | `dwarven-focus-save.keys` | 1 | options-dwarven-focus.dat | none (creation only) | - | - |
| 11 | `elf-mage-illusions-seed1` | IS1.3 | `elf-mage-illusions-save.keys` | 1 | options-2026-08-22.dat | wizard on; Wizard Mode Switches x2 (switch:, Infinite Mana + Freeze Monsters per check facts); Learn Any Spell x4 (learn: ... wizard) | - | - |
| 12 | `elf-mage-spotted-seed1` | IS1.6 | `elf-mage-spotted-save.keys` | 1 | options-2026-08-22.dat | none (creation only) | - | - |
| 13 | `elf-rogue-bluff-seed1-opt0822` | IS1.6 | `elf-rogue-bluff-save.keys` | 1 | options-2026-08-22.dat | none (creation only) | - | - |
| 14 | `elf-search-seed1-opt0818` | IS1.3 | `elf-search-save.keys` | 1 | options-2026-08-18.dat | none (creation only) | - | - |
| 15 | `engaged-hostile` | IS1.3 | `engaged-hostile-save.keys` | 1 | options-2026-08-22.dat | wizard on; Monster Summoning bugbear one square east (SCENE) | - | YES |
| 16 | `gnome-warrior-wis3-pickaxe-seed1-opt0822` | IS1.6 | `gnome-warrior-pickaxe-save.keys` | 1 | options-2026-08-22.dat | inventory moves: wield pickaxe from pack (place:); creation by Point Buy (WIS 3) | - | - |
| 17 | `human-paladin-damaged-armour-opt0822` | IS1.6 | `repair-cost-damage-save.keys` | 2 | options-2026-08-22.dat | wizard on; Create Trap "minor decay trap" damages armour 81/86 (condition:); needs seed 2 trap roll | human-paladin-seed4-opt0822 | - |
| 18 | `human-paladin-seed4-gate` | IS1.3 | `chargen-paladin-save.keys` | 4 | tools/gates/Options.Dat | none (creation only) | - | - |
| 19 | `human-paladin-seed4-grease-opt0822` | IS1.6 | `chargen-paladin-save.keys` | 4 | options-2026-08-22.dat | none; SAME recipe (key script, seed 4, options) as human-paladin-seed4-opt0822 (only the file differs) | - | - |
| 20 | `human-paladin-seed4-opt0822` | IS1.3 | `chargen-paladin-save.keys` | 4 | options-2026-08-22.dat | none (creation only) | - | - |
| 21 | `human-priest-mage-dual-seed4-gate` | IS1.6 | `chargen-human-priest-mage-dual-save.keys` | 4 | options-2026-08-22.dat | sheet-view; wizard on + switch; M train Mage (addclass:); G gain Mage 1 (level:); Item Acquisition Mystic Aegis (item:); L mark spells (learn:); wizard depth jump to 2; Genocide; rest z | - | - |
| 22 | `human-priest-mage-seed4-gate` | IS1.6 | `chargen-human-priest-mage-save.keys` | 4 | tools/gates/Options.Dat | wizard on + switch (Free Advancement); M train Mage (addclass:); G gain Mage 1 (level:) | - | - |
| 23 | `human-priest-mage-wounded-seed4-gate` | IS1.6 | `priest-mage-wounded-save.keys` | 4 | tools/gates/Options.Dat | as priest-mage-seed4 + Wizard Mode Switches (Ignore Spell Failure); Monster Summoning giant rat bites, waits (hp_now:); Genocide; search. Recipe env INCURSION_LOF_FORCE_ROLL=20 INCURSION_FORCE_DAMAGE_ROLL=3 | - | - |
| 24 | `hunger-penalty-seed1-opt0822` | IS1.3 | `hunger-penalty-save.keys` | 1 | options-2026-08-22.dat | none (creation only) | - | - |
| 25 | `kobold-rogue-seed1` | IS1.3 | `kobold-rogue-save.keys` | 1 | options-2026-08-22.dat | drop the whip from weapon hand (place: floor) | - | - |
| 26 | `levitate-bottom-seed1` | IS1.3 | `levitate-bottom-save.keys` | 1 | options-2026-08-22.dat | wizard on; wizard depth jumps x9 to depth 10 with walk keys to the chasm (SCENE). Recipe env INCURSION_LEVITATE_CHASM=1 | - | YES |
| 27 | `lizardfolk-monk-barehand-seed1` | IS1.3 | `lizardfolk-monk-barehand-save.keys` | 1 | options-2026-08-18.dat | drop weapon from weapon hand (place: floor) | - | - |
| 28 | `lizardfolk-monk-seed1` | IS1.3 | `lizardfolk-monk-save.keys` | 1 | options-2026-08-22.dat | none (creation only) | - | - |
| 29 | `low-dex-orc-barbarian-seed18-gate` | IS1.6 | `low-dex-orc-barbarian-save.keys` | 18 | tools/gates/Options.Dat | none (creation only) | - | - |
| 30 | `monk-ki-strike-seed1-opt0818` | IS1.3 | `monk-ki-strike-save.keys` | 1 | options-2026-08-18.dat | none (creation only) | - | - |
| 31 | `monk-weapon-immunity-seed1-opt0818` | IS1.3 | `monk-weapon-immunity-save.keys` | 1 | options-2026-08-18.dat | none (creation only) | - | - |
| 32 | `orc-barbarian-ce-opt0822` | IS1.6 | `aura-of-menace-save.keys` | 1 | options-2026-08-22.dat | none (creation only) | - | - |
| 33 | `orc-barbarian-reapply-seed4` | IS1.6 | `reapply-barbarian-save.keys` | 4 | options-2026-08-22.dat | none (creation only) | - | - |
| 34 | `orc-barbarian-seed1-gate` | IS1.3 | `chargen-default-save.keys` | 1 | tools/gates/Options.Dat | none (creation only) | - | - |
| 35 | `orc-barbarian-seed1-opt0818-store` | IS1.6 | `chargen-default-store-save.keys` | 1 | options-2026-08-18.dat | visit Roark Ironbeard store once in town (STORE SCENE) | - | YES |
| 36 | `orc-barbarian-seed1-opt0818` | IS1.3 | `chargen-default-save.keys` | 1 | options-2026-08-18.dat | none (creation only) | - | - |
| 37 | `orc-barbarian-seed1-opt0822` | IS1.3 | `chargen-default-save.keys` | 1 | options-2026-08-22.dat | none (creation only) | - | - |
| 38 | `orc-barbarian-seed11-gate` | IS1.3 | `chargen-default-save.keys` | 11 | tools/gates/Options.Dat | none (creation only) | - | - |
| 39 | `orc-barbarian-seed11-opt0822` | IS1.3 | `chargen-default-save.keys` | 11 | options-2026-08-22.dat | none (creation only) | - | - |
| 40 | `orc-barbarian-seed20260905-gate` | IS1.3 | `chargen-default-save.keys` | 20260905 | tools/gates/Options.Dat | none (creation only) | - | - |
| 41 | `orc-barbarian-seed20260905-opt0822` | IS1.3 | `chargen-default-save.keys` | 20260905 | options-2026-08-22.dat | none (creation only) | - | - |
| 42 | `orc-barbarian-seed3-gate` | IS1.3 | `chargen-default-save.keys` | 3 | tools/gates/Options.Dat | none (creation only) | - | - |
| 43 | `orc-barbarian-seed3390-gate` | IS1.3 | `chargen-default-save.keys` | 3390 | tools/gates/Options.Dat | none (creation only) | - | - |
| 44 | `orc-barbarian-seed4-gate` | IS1.3 | `chargen-default-save.keys` | 4 | tools/gates/Options.Dat | none (creation only) | - | - |
| 45 | `orc-barbarian-seed5-opt0822` | IS1.3 | `chargen-default-save.keys` | 5 | options-2026-08-22.dat | none (creation only) | - | - |
| 46 | `orc-barbarian-seed7-opt0818` | IS1.3 | `chargen-default-save.keys` | 7 | options-2026-08-18.dat | none (creation only) | - | - |
| 47 | `orc-barbarian-seed7-opt0822` | IS1.3 | `chargen-default-save.keys` | 7 | options-2026-08-22.dat | none (creation only) | - | - |
| 48 | `orc-barbarian-seed99-opt0822` | IS1.3 | `chargen-default-save.keys` | 99 | options-2026-08-22.dat | none (creation only) | - | - |
| 49 | `orc-bard-reapply-seed1` | IS1.4 | `reapply-bard-save.keys` | 1 | options-2026-08-22.dat | creation rerolls x7 for a perk-free CON-12 set; wizard on; Wizard Mode Switches (Free Advancement); G x5 to Bard 6 with attribute bonus, feat, spell picks (level:); Genocide | - | - |
| 50 | `orc-mage-seed1-opt0822` | IS1.3 | `chargen-mage-save.keys` | 1 | options-2026-08-22.dat | none (creation only) | - | - |
| 51 | `orc-mage-seed4-gate` | IS1.3 | `chargen-mage-save.keys` | 4 | tools/gates/Options.Dat | none (creation only) | - | - |
| 52 | `orc-mage-seed4-opt0822` | IS1.3 | `chargen-mage-save.keys` | 4 | options-2026-08-22.dat | none (creation only) | - | - |
| 53 | `orc-mage-seed5-opt0822` | IS1.3 | `chargen-mage-save.keys` | 5 | options-2026-08-22.dat | none (creation only) | - | - |
| 54 | `orc-priest-pain-seed1-sneakopts` | IS1.6 | `pain-priest-wounded-save.keys` | 1 | options-sneak-invis.dat | wizard on; Monster Summoning giant rat; wait to be wounded (hp_now:); punch; Feed upon Pain tally 6 (stati:); Genocide; calm. Recipe env INCURSION_LOF_FORCE_ROLL=20 INCURSION_FORCE_DAMAGE_ROLL=3 | - | - |
| 55 | `orc-priest-seed1-opt0822` | IS1.6 | `chargen-priest-save.keys` | 1 | options-2026-08-22.dat | none (creation only) | - | - |
| 56 | `orc-priest-seed4-gate` | IS1.3 | `chargen-priest-save.keys` | 4 | tools/gates/Options.Dat | none (creation only) | - | - |
| 57 | `orc-rogue-seed1-gate` | IS1.3 | `chargen-rogue-save.keys` | 1 | tools/gates/Options.Dat | none (creation only) | - | - |
| 58 | `orc-rogue-seed1-opt0818` | IS1.3 | `chargen-rogue-save.keys` | 1 | options-2026-08-18.dat | none (creation only) | - | - |
| 59 | `orc-rogue-seed1-opt0822` | IS1.3 | `chargen-rogue-save.keys` | 1 | options-2026-08-22.dat | none (creation only) | - | - |
| 60 | `orc-rogue-seed4-opt0822` | IS1.3 | `chargen-rogue-save.keys` | 4 | options-2026-08-22.dat | none (creation only) | - | - |
| 61 | `orc-rogue-seed6-opt0822` | IS1.3 | `chargen-rogue-save.keys` | 6 | options-2026-08-22.dat | none (creation only) | - | - |
| 62 | `orc-rogue-sneak-seed1` | IS1.6 | `sneak-invis-rogue-save.keys` | 1 | options-sneak-invis-maxhp.dat | none (creation only) | - | - |
| 63 | `orc-warrior-dequ-seed5-maxhp` | IS1.6 | `dequ-save-message-save.keys` | 5 | options-2026-08-22-maxhp.dat | none (same key script as dequ-save-message-seed5-opt0822); only the options file differs (monster max HP DOUBLE) | - | - |
| 64 | `prestige-earthsinger-seed3-opt0818` | IS1.3 | `prestige-earthsinger-save.keys` | 3 | options-2026-08-18.dat | wizard on; switches Free Advancement + Show All Combat Rolls (switch:); G to Bard 7 (level:); S skill-rank spend (Craft) | - | - |
| 65 | `prestige-earthsinger-seed3-opt0822` | IS1.3 | `prestige-earthsinger-save.keys` | 3 | options-2026-08-22.dat | same as opt0818 | - | - |
| 66 | `prestige-geomancy-seed1-opt0822` | IS1.3 | `prestige-geomancy-save.keys` | 1 | options-2026-08-22.dat | same recipe shape as earthsinger (wizard on, switches, G to a prestige level, S skill ranks) | - | - |
| 67 | `quality-item-magic-seed5-opt0822` | IS1.6 | `quality-item-magic-save.keys` | 5 | options-2026-08-22.dat | creation only, but the creation OPTIONS are altered (Monsters Maximum Hit Points DOUBLE) -> options: | - | - |
| 68 | `skill-by-name-seed1-opt0818` | IS1.3 | `skill-by-name-save.keys` | 1 | options-2026-08-18.dat | none (creation only) | - | - |
| 69 | `spook-ally-seed5-opt0822` | IS1.3 | `spook-ally-save.keys` | 5 | options-2026-08-22.dat | none (creation only) | - | - |
| 70 | `spook-mount-seed5-opt0822` | IS1.3 | `spook-mount-save.keys` | 5 | options-2026-08-22.dat | none (creation only) | - | - |
| 71 | `underdark-deepgnome-seed3-opt0818` | IS1.3 | `underdark-deepgnome-save.keys` | 3 | options-2026-08-18.dat | wizard on; switch Free Advancement; G x2 with feats Toughness, Blind Fight to Rogue 6 (level:); S skill-rank spend | - | - |
| 72 | `weapon-sets-old-defaults` | IS1.6 | `weapon-sets-fixture.keys` | 1 | options-2026-08-22.dat | wizard on; Genocide; Item Acquisition long sword + short bow (item:); equip/stow/swap and weapon-set definitions via M/O/R/s keys (place: + WEAPON SETS, uncovered) | dequ-save-message-seed5-opt0822 | - |
| 73 | `wood-elf-rogue-seed7-opt0818` | IS1.6 | `wood-elf-rogue-save.keys` | 7 | options-2026-08-18.dat | none (creation only) | - | - |
| 74 | `xsummon-priest-seed5-opt0822` | IS1.3 | `xsummon-priest-save.keys` | 5 | options-2026-08-22.dat | none (creation only) | - | - |

### 5. Key scripts

Retire (code search shows no caller outside the maker flow; 46 files). Each is named in exactly the fixture(s) listed in section 4:
alignment-drain-fixture, alignment-drain-lawneutral-save, alignment-drain-level1-fixture, alignment-drain-level2-fixture, aura-of-menace-save, chargen-default-store-save, chargen-human-priest-mage-dual-save, chargen-human-priest-mage-save, chargen-paladin-save, chargen-rogue-save, circle-stack-adjust-save, dequ-save-dc-save, dequ-save-message-save, dragonkin-sheet-save, druid-shoulder-metal-save, dwarven-focus-save, elf-mage-illusions-save, elf-mage-spotted-save, elf-rogue-bluff-save, elf-search-save, engaged-hostile-save, gnome-warrior-pickaxe-save, hunger-penalty-save, kobold-rogue-save, levitate-bottom-save, lizardfolk-monk-barehand-save, lizardfolk-monk-save, low-dex-orc-barbarian-save, monk-ki-strike-save, monk-weapon-immunity-save, pain-priest-wounded-save, prestige-earthsinger-save, prestige-geomancy-save, priest-mage-wounded-save, quality-item-magic-save, reapply-barbarian-save, reapply-bard-save, repair-cost-damage-save, skill-by-name-save, sneak-invis-rogue-save, spook-ally-save, spook-mount-save, underdark-deepgnome-save, weapon-sets-fixture, wood-elf-rogue-save, xsummon-priest-save (all `tools/keys/<name>.keys`). `check_weapon_sets.sh` calls weapon-sets-fixture.keys only from its `--make-fixture` block, and `check_two_fist_feats_live.sh:73` names lizardfolk-monk-barehand-save.keys only in a failure message; both go with the maker.

Stay (shared with a live check, fixture recipe drops them):
- `tools/keys/chargen-default-save.keys`: run by `check_linux_save_roundtrip.sh:74` (Case A, a fresh Linux save). 14 fixtures use it today.
- `tools/keys/chargen-mage-save.keys` and `tools/keys/chargen-priest-save.keys`: run by `check_spell_source_bits.sh` (fresh-chargen probe, needs the key script and not a `.char`). 4 and 2 fixtures use them. The spec lists this check as a specimen user; it is not. Note it runs them at seed 4 with `tools/gates/Options.Dat`.
- `tools/keys/load-char-sheet.keys`: shared loader (dumps arrival, played, sheet, saved); `check_linux_save_roundtrip.sh:75` runs it; `check_char_fixture.sh` also did.

Stay (include-only helpers, shared widely): chargen.keys, chargen-mage.keys, chargen-paladin.keys, chargen-priest.keys, chargen-rogue.keys, chargen-elf-mage.keys, aura-of-menace-chargen.keys (included by aura-of-menace-approach.keys), sneak-invis-chargen.keys (named by blind-fight-miss.keys), dequ-setup-loaded.keys (included by 10+ keys scripts and by weapon-sets-fixture.keys). `tools/keys/levitate-bottom-load.keys` is a loader key script for the scene; it is rewritten with the D2 hook, not retired.

Retire with the maker: `tools/make_char_fixture.sh`, `tools/check_char_fixture.sh`, `tools/fixtures/chars/MANIFEST`, and the 74 `tools/fixtures/chars/*.keys` copies. Epic-only: `tools/sync_char_fixtures.sh` does not exist here.

### 6. Post-creation actions that spec section 4's key table does not cover

Spec section 4 covers: level, addclass, xp, learn, item, place, wizard/switch, join/rung/altar, companion, hp_now, stati, condition.

Found in the fixtures and not covered:
1. **Wizard "Genocide Everything"** (clear the level): alignment-drain x4, human-priest-mage-dual, -wounded, orc-bard-reapply, orc-priest-pain, weapon-sets-old-defaults. Not a character field; it empties the map. It is a scene step. If the builder needs a map free of monsters, the key table needs `clear:`; if a check does it itself, none.
2. **Wizard depth jumps** ("Ascend / Descend Depth", `p "N"`): human-priest-mage-dual (to depth 2), levitate-bottom (x9 to depth 10). Spec covers only the check's own jump (D2) for levitate-bottom, not the dual fixture.
3. **Wizard Monster Summoning, then wait to be wounded**: -wounded and orc-priest-pain use `hp_now` plus the forced-roll env vars; the summon and waits are replaced by `hp_now`, but `pain` also needs the carried "Feed upon Pain tally 6" (a `stati`) and a punched-hand state; spec lists `stati` as allowed only "for a check's own counter". The tally is the fixture's character state. Covered only if `stati` is accepted for it.
4. **Store visit** (orc-barbarian-seed1-opt0818-store): spec handles it as a scene with `storeSeed`; no key in the table.
5. **Skill-rank spending after level-up** (the `S` screen, "Unspent Skill Ranks"): prestige-earthsinger x2, prestige-geomancy, underdark-deepgnome. `level: <class> [choices]` may or may not carry rank spends; the table is silent.
6. **Weapon-set definitions** (M / O / R / s keys, "two-handed" prompt answers): weapon-sets-old-defaults. `place:` does not cover weapon sets.
7. **Rest (`z`)** after a book/spell mark: human-priest-mage-dual ends with a rest so selected spells become held. Not in the table.
8. **Spell-marking by the Learn Spells screen** (`L` + SPACE marks, then ENTER) in human-priest-mage-dual: `learn: <spell> <source>` is the wizard path or a source learn; the arcane-row marking screen is a third path.
9. **Creation OPTIONS altered** (quality-item-magic: Monsters Maximum Hit Points DOUBLE): spec B11 covers it as `options:`.
10. **Drop to floor / empty hands** (kobold-rogue, lizardfolk-monk-barehand): covered by `place: <item> floor`; confirm the drop tolerates the "stow refused for size" case the barehand script avoids.
11. **Forced-roll environment at build time** (INCURSION_LOF_FORCE_ROLL, INCURSION_FORCE_DAMAGE_ROLL, INCURSION_LEVITATE_CHASM): not a key; the `.char` has no field for them. The 2 wounded fixtures drop them if `hp_now` replaces the fight; levitate is the D2 hook.
12. **Single-seed dependence of a build step**: human-paladin-damaged-armour needs seed 2 (the trap roll). `condition: <item> <damage>` covers it.
13. **Free Advancement + Show All Combat Rolls switches**: `switch:` covers both; note "Show All Combat Rolls" is also a player option that changes the later run, so it must be in the saved character, not the options file.
14. **Reroll count at creation** (`x*7`, orc-bard-reapply): the creation attribute pick by rerolling to a given set is a creation decision; spec section 1/2 covers creation draws, not named here as verified.

### Verification of completeness

```
grep -rl fixtures/chars tools docs .beads/hooks | grep -v -e '^tools/fixtures/chars/' -e '^docs/specs/2026-11-06-fixture-builder-sites.md$' | sort > A.txt
grep -o '^| `[^`]*`' docs/specs/2026-11-06-fixture-builder-sites.md | sed 's/^| `//; s/`$//' | sort -u > B.txt
comm -23 A.txt B.txt        # must print nothing
```
