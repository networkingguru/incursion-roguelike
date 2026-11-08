# Fixture builder: characters built from a text file (inc-10v7f)

Version 2. Version 1 was reviewed by two independent reviewers (bead notes,
2026-11-06); every Critical and Major finding is folded in below, and the
section that answers it names the finding (R = resilience review, K =
code-grounded review).

## Problem

A character fixture (`tools/fixtures/chars/<name>.sav`) is made today by
walking the character creation screens with a key script on a seed
(`tools/make_char_fixture.sh`). When the save format or the game code
changes, the only repair is to walk the screens again, and the walk then
rolls differently. In the inc-pu6v.369 merge, 16 epic fixtures stopped
loading after a save-tag move; regenerating them gave 6 different
characters, lost the drow fixture's Call Companions perk, and broke 12
checks. The automatic rebuild in the epic's `tools/headless.sh` (inc-zto3q)
reruns the same walk and has the same flaw.

## Goals (owner's rulings, 2026-11-06, bead notes)

- G1. A fixture is a committed text file (`.char`) that states the
  character. The `.sav` is a build product.
- G2. The builder MUST run the same functions character creation runs and
  MUST NOT copy creation logic.
- G3. A change MUST be repaired quickly and automatically, or MUST fail
  loudly with a one-line fix. Nothing may change a character silently.
- G4. A fixture holds only the character. A check that needs a map scene
  builds it after loading.
- G5. Every fixture converts, on master and on the epic.

## Non-goals

- Testing the creation screens (their own key-script checks stay).
- Keeping epic saves loading (rule `epic-saves-are-disposable`, inc-1macr).
- Cross-branch number collisions (inc-cjos0, another session).

## 1. One creation source (K-M6, R-M-1)

Creation already has one place where each decision is made or replayed: the
`MO_CREATE` / `MO_RECREATE` switch sites that reincarnation uses
(`RollAttributes` `src/Create.cpp:2287`, `GrantGear` `src/Annot.cpp:588-642`,
skill ranks `:1223-1233`, the prompt primitives `src/Term.cpp:2895, 3421`,
`src/TextTerm.cpp:1015, 1424, 1868`). The builder MUST NOT add a second
layer beside it. Instead those sites call ONE interface, `CreationSource`,
with three backends:

| backend | used by | each decision comes from |
|---|---|---|
| `Live` | normal play | the screen and `random()`, exactly as today |
| `Replay` | gallery reincarnation | `RInf`, exactly as today; `gallery.dat` format unchanged, because master players' galleries must keep working |
| `File` | the builder | a `.char` file, by key and name |

`Live` can also RECORD: it writes every decision it made, in `.char` form,
to a file. Recording is how a new fixture is made by playing (section 8),
and it is the oracle of the equivalence check (C2).

Every site that today branches on `MO_RECREATE` MUST branch on the source
instead, and the old branch MUST be deleted, so there is one code path per
decision. A site is "a decision" when it asks the player or draws a random
number that decides a character fact.

## 2. Decisions that must be sourced

Each decision site calls the source with a stable KEY that the call site
passes as a constant (an enum), never the prompt's display text (R-M-2,
K-m5). Rewording a prompt therefore changes nothing.

Prompts (K-C1): `LMenu`, `LMultiSelect`, `ChoicePrompt`, `yn`, the
spell table `TextTerm::LearnTable` (`src/TextTerm.cpp:1824`), the attribute
screen in `RollAttributes` (direct key reads `src/Create.cpp:2477, 2583`),
the skill screen `TextTerm::SkillManager` (`src/Managers.cpp:2110-2228`; its
commit at `:2215-2218` becomes a function both the screen and the source
call), the creation option screen `OptionManager(OPC_CHARGEN)` (`:866`), and
every prompt a creation-time script raises (`lib/races.irh` EV_BIRTH yn,
the epic god menu with its "No god" and CG_FEAT "Cancel" rows).

Random draws that decide a character fact (R-C-2, K-C3, K-M3): gender
(`:916`), name (`PickName :72`), attribute sets and rerolls, perk type and
details (`CreatePerk`, rolls at `:1828-2030`), hit points and mana per level
(`AdvanceLevel`), `formulaSeed` (`:885`, which also decides the Multitude
domain pool `:2686`), `storeSeed` (`:1454`), and inside `GrantGear` every
draw: inclusion chance, `GF_RANDOM_ITEM` (`src/Annot.cpp:661-677`),
`GF_RANDOM_EFFECT` (`:679-712`), item level (`:720-735`), `Amount.Roll()`
(`:743`), plus `GrantBeginnerKit` (`src/Create.cpp:549-598`), and the
missile, thrown and ammo counts (`:1281-1311`).

### Two tripwires (the resilience backbone)

With the `File` backend active, from the start of `Player::Create` to the
end of the last post-creation key:

- T1, key reads. `GetCharRaw`, `GetCharCmd`, `GetKey` and `ReadLine` fail
  the build when called outside a sourced decision, naming the screen title
  and the calling function. A new screen can never hang a build or be
  answered by accident (K-C1).
- T2, random draws. `random()` and the dice functions fail the build when
  called outside a sourced decision, naming the calling function. A draw
  that truly decides no character fact (a cosmetic draw) goes through an
  explicit `unstatedDraw("<reason>")` wrapper, so every exemption is
  written at its site (R-C-2).

Both turn every unforeseen change (new prompt, new screen, new random draw,
an RNG stream shift) from silent into a named build failure.

## 3. The character file

`tools/fixtures/chars/<name>.char`: `key: value` lines, `#` comments.

- Every value is a NAME (race, class, god, feat, skill, spell, item,
  effect, perk field), never an rID or menu index. Labels are normalized
  (color codes and markup stripped, case kept); a value matching two
  options fails the build; spells are `<spell> [source]` (K-m4).
- A key that repeats is an ordered queue, consumed in the order the game
  asks (feats, domains, spell pages) (K-M5).
- Every stated value MUST be consumed. A surplus value, an unknown key, a
  duplicate single key, or a value out of range fails the build (R-M-2,
  R-M-6, K-M5).
- A repeated identical request (the game rejected the answer and asked
  again, for example the epic's god loop `src/Create.cpp:1197-1210`) fails
  with "stated value rejected by the game" (K-M4).
- `options:` names the settings file. `seed:` seeds only draws that went
  through `unstatedDraw` and everything after creation that the file does
  not cover (flavors, the depth-1 map).
- Perks (K-M2): one block per perk, every field of the Perk struct by name
  (type, item, effect, plus, the seven qualities, bane, resist, immune, feat,
  ability, spell). `GrantPerks` (`:2213`) becomes non-static and applies the
  block. A check fails if a Perk struct field has no `.char` field.
- Keys for creation facts the sheet records (K-C2, K-M3): `stat_method`,
  `rerolls`, `rerolled_perks`, `xp`, `deaths`, `explore`, skill ranks by
  pool (`skills: <pool> <skill>: <ranks>`).
- `kit:` is the full granted-item list: item, effect, plus, quantity, each
  answering one `GrantGear`/`GrantBeginnerKit` draw (K-C3).
- An `expect:` block, written by a person, lists the facts the fixture's
  checks rely on, compared at build. A wrong hand edit fails here (R-M-6).
- Chained fixtures (made today by loading another fixture) are flattened
  into one full `.char`; there is no `from:` (K-m6).

## 4. Post-creation keys

Withdrawn by section 15 (V7-1). A fixture holds only the created character.

## 5. Build mode

`tools/build_fixture.sh <name>` (K-m3) builds in a sandbox like
`tools/headless.sh` (own `save/` and `logs/`, links to `mod/` and `lib/`) by
running `incursion-headless -build <name>.char`. It:

1. Loads modules and options and seeds from `seed`.
2. Installs the `File` source and calls `Game::NewGame` unchanged; no split
   is needed (K-m1). Creation's gallery write is skipped when the source is
   `File`; `TouchGallery` then returns early (K-m2, tested).
3. Verifies (section 6), then saves through `Game::SaveGame` and writes the
   sheet through the engine's `DumpCharacter`.

## 6. Verification

- V1. Every stated value was consumed and every `expect:` fact holds.
- V2. The sheet's provenance header records the cache key. A cached `.sav`
  is used only under its own key, so a stale `.sav` cannot be loaded (K-C5,
  R-M-4).
- V3. Seed independence: the build runs twice with two different `seed`
  values; the full canonical dump of the character (save dump of the Player
  and its inventory, clocks and the map excluded) MUST be identical (R).

## 7. The fixture cache and automatic repair (K-C4, R-M-4, R-M-5)

Owner's ruling D1 (2026-11-06, after measuring 0.10-0.19 s per creation and
save, 0.14-0.15 s per load and sheet): the `.sav` and `.sheet.txt` are NOT
tracked. Only the `.char` is.

- The cache is `logs/fixture-cache/<key>/<name>.sav` and `.sheet.txt` in
  the worktree, where `<key>` is a hash of the `.char`, its options file and
  the `incursion-headless` binary. Any change to any of the three is a cache
  miss, so a fixture always matches the current code, module and save format.
- `INCURSION_LOAD=<name>` (or the old path form, mapped by name) makes
  `tools/headless.sh` build on a miss, then copy the cached `.sav` into the
  run's sandbox as today. A build takes a per-fixture lock
  (`logs/fixture-locks/<name>`), builds into a temporary directory and
  renames into place, so concurrent runs never see a half-written file.
- A freshly built fixture that then fails to load is a loader or writer
  defect: exit 8, `FIXTURE LOAD FAILED`, never rebuilt again.
- Derived sheet lines (a rules change moving AC, to-hit, speed) change with
  the code. A check MUST NOT assert on a derived value read from a
  `.sheet.txt`; it reads the live value from the engine.
- The existing tracked `.sav`, `.sheet.txt`, `.keys` and `MANIFEST` files are
  removed from git when their fixture converts.

## 8. Making and converting fixtures

- New fixture: play or key-script to the character with the `Live` source
  recording; the recorded `.char` is committed; or write the `.char` by hand.
- Conversion (K-M6, R-S-2): for each existing fixture, run its key script
  with recording on the current binary to get a `.char` skeleton, then set
  each value that differs from the OLD fixture to the old value, then build.
  The oracle is the OLD `.sav`: its full canonical dump, taken with the
  binary it loads in (master fixtures: current master; epic fixtures: the
  epic at d71c1823, before the 449-451 tag move), MUST equal the new build's
  dump outside an explicit allowlist (provenance, clocks, map, flavors,
  gallery slot). Any other difference fails that fixture's conversion. The
  helper that fills old values stays until the epic conversion lands.
- Every fixture converts (G5). None is deleted (R-S-1).
- Scenes (G4, K-M8): `engaged-hostile` and `orc-barbarian-seed1-opt0818-store`
  become character fixtures; their checks build the scene with the wizard
  monster summon and a stated `storeSeed`. `levitate-bottom-seed1` becomes a
  character fixture; owner's ruling D2 (2026-11-06): `check_dungeonmap_bounds.sh`
  jumps to depth 10 with the wizard depth command, and the test hook
  `INCURSION_LEVITATE_CHASM` (`src/Feature.cpp:1681`), set by the check, ALWAYS
  sets the square under the player and the square directly east of him to
  chasm terrain on arrival at the bottom level and grants levitation. The
  hook's chasm search is removed, so nothing depends on the seed's map.
- Old-format specimens. Some tools read a fixture `.sav` as a FILE in the
  save format it was written in, not as a character: they test recovery or
  conversion of old formats (`check_script_var_recovery.py`,
  `check_convert_guard.sh`, `check_spell_source_bits.sh`, and on both
  branches `check_linux_save_roundtrip.sh`, `check_vararg_format_live.sh`,
  `swarm_theft_results.py`, epic `repro_inc_pu6v239_innate_status.sh`). The
  plan MUST classify each use. A use that needs the old bytes moves that
  exact `.sav` to `tools/fixtures/specimens/`, tracked and never rebuilt; a
  use that only needs a character switches to the cache.
- `tools/make_char_fixture.sh`, `MANIFEST`, `tools/sync_char_fixtures.sh`
  and every key script used only to make a fixture are retired;
  `tools/fixtures/README.md` describes the new system.

## 9. Checks (each shown red by its named mutation)

- C1 `check_fixture_build.sh`: builds every `.char`; V1-V3 hold; editing a
  `.char` changes the cache key. Red: a cache lookup that ignores the
  `.char` hash serves the old `.sav`.
- C2 `check_fixture_equivalence.sh`: walks characters through the real
  screens with `Live` recording, builds the recorded `.char`, and compares
  full canonical dumps both ways. Coverage: every decision key MUST be hit by
  at least one walk (a list generated from the enum fails on a key no walk
  hits); the gate runs a fixed subset, the nightly run sweeps every race and
  class. Red: (a) a creation step the `File` path skips; (b) a new random
  draw; (c) a new prompt; (d) a new raw-key screen (K-M7, R-C-3).
- C3 `check_fixture_tripwires.sh`: T1 and T2 fire, with their messages, on
  an inserted `yn`, an inserted raw-key screen and an inserted `random()`.
- C4 `check_fixture_repair.sh`: in a scratch build, move a save tag; the
  next run misses the cache, rebuilds, and loads the same character (V3 dump
  identical); a truncated cached `.sav` is NOT rebuilt and exits 8; two
  concurrent runs of one fixture build it once.
- C5 `check_perk_fields.sh`: every Perk struct field has a `.char` field.
- Every check that loads a fixture passes `tools/seed_sweep.sh` and carries
  `# fact: character -- fixture <name>`; it reads no map, flavor or derived
  sheet value (VERIFICATION.md seed rule, R).
- The "no copied logic" property is a review item: the code reviewer
  confirms it and the sign-off goes in the bead notes.

## 10. Order of work

1. Master (inc-10v7f): the source interface and its backends, tripwires,
   moved bodies, build mode, checks, conversion of master's 74 fixtures.
   Early proof on two fixtures common to both branches (R-S-3).
2. Land. Merge master into inc-pu6v through inc-pu6v.369; the supply sites
   are one-line calls, to keep the merge surface small; C2 and C3 MUST pass
   on the epic before .369 lands (R-S-3).
3. In inc-pu6v.369: convert the epic's fixtures against the d71c1823 dumps,
   then the proof below.

## Proof on the current failure

With the epic's tags at 453-455: every epic fixture rebuilds from its
`.char` and its dump equals the d71c1823 dump outside the allowlist;
`tools/check_innate_status_source.sh` case C passes (Call Companions stated
as a perk block), and the 11 checks that failed after the walk regeneration
pass: check_semirath_crown, check_semirath_joining, check_essiah_playtest,
check_reapply_single_grant, check_storycraft, check_semirath_income,
check_betrayed_mark, check_wand_skill_check, check_cursor_left_on,
check_wildshape_gray, check_wildshape_cheetah_desc.

## 11. Version 3 amendments (second review, 2026-11-06)

A third reviewer checked v2 against the code (findings N1-N12, m1-m7 in the
bead notes). Each amendment below overrides the section it names.

- A1 (N1, sec 2 and 5). The T2 window is `Player::Create` alone, plus each
  post-creation key body on its own. The span from `Create` returning to the
  first key (map generation, placement, `InitCompanions`, `NoteArrival`) is
  outside it. `Game::NewGame` is split at the `Create` return by MOVING the
  tail into a function the old path calls, so K-m1 ("no split") is
  withdrawn. C3 adds: a draw inserted in map generation does NOT trip T2;
  one inserted in `AdvanceLevel` does.
- A2 (N2). Script draws during creation events (`EV_BIRTH`, `EV_ADVANCE`;
  80 hooks in `lib/`, e.g. `lib/classes.irh:1441, 2908`) go through the
  source, keyed by (resource name, event, ordinal within the event). Kit
  entries gain `quality:`. The plan sweeps all 80 hooks.
- A3 (N3, sec 7). Cache key = hash of the `.char`, its options file, the
  binary AND `mod/Incursion.Mod`. A build runs under a clean environment: an
  allowlist of `INCURSION_*` variables, the seed from the file only. A
  cached `.sav` that fails to load with a module-slide message rebuilds once;
  any other load failure is exit 8.
- A4 (N4, sec 3). Each `GrantGear` draw is keyed by (granting resource,
  annotation ordinal, draw kind: chance, random item, random effect, level,
  amount). An annotation with no entry fails the build and prints the line
  to add; an entry with no annotation fails as surplus.
- A5 (N5). Every sourced decision declares a default. A build never uses a
  default silently: a missing key fails and prints the exact `key: value`
  line. `tools/fill_chars.sh` writes every missing line, using defaults, into
  every `.char`, as a reviewed diff in the bead that added the decision;
  `tools/char_rekey.sh <old> <new>` renames a key or value in every `.char`.
  Neither runs inside a check, which never writes a tracked file.
- A6 (N6, sec 1). Plan step 1 produces a grep-complete list of every
  `MO_RECREATE`, `MO_CREATE`, `reincarnate` and `RInf` site on BOTH branches
  (master's list includes `src/Create.cpp:862, 882, 887-889, 962, 965, 1012,
  1015, 1088, 1091, 1122, 1199, 1202, 1223, 1456-1463, 3774, 3777` and
  `src/MultiSelectProbe.cpp:48-76`). One recorder with two serializers
  (`RInf` for the gallery, `.char` for fixtures); the recorder pops a
  decision on back-navigation as `RInf.nRsp--` does today. Replay returns
  NOT_RECORDED for every decision `RInf` does not hold, and the site then
  behaves as `Live`, so reincarnation behaves exactly as today. A grep check
  fails on any new `MO_RECREATE` or `reincarnate` branch outside the source.
- A7 (N7, sec 8). The canonical dump is `-dump` with every rID printed as a
  resource name (`SafeResName`, `src/Dump.cpp:128`), handles dropped, and
  extended with per-level hit and mana rolls, skill ranks per pool, perk
  blocks, kit with qualities, spell lists and stati by name; the tool is
  `tools/char_dump.sh`. What it does not print is not compared, so gaps are
  closed by extending the dump. The epic oracle: build the epic at d71c1823
  in a scratch worktree and store the canonical dumps of its 82 fixtures in
  `~/Scripts/Incursion/docs/evidence/inc-10v7f/epic-d71c1823/` before .369
  converts them. d71c1823 stays in git, so this has no deadline.
- A8 (N8, sec 2). T1 sits in ONE non-virtual wrapper in the shared `TextTerm`
  layer that every key read passes, not in the three backends. Acknowledgment
  reads (`[MORE]`, message boxes) are answered by the builder and logged, not
  failed. The build forces `OPT_AUTOMORE`.
- A9 (N9, sec 2 and 6). Plan step 0 runs T2 in log-only mode over a full
  race-by-class creation sweep to count every `random()` caller before the
  tripwire is armed. Draws after an `srand` from a stated value
  (`formulaSeed`, `storeSeed`) count as stated. `NextSeed()` calls are
  sourced. The cosmetic stream (`cosmetic_random`) needs no exemption.
  `unstatedDraw` sites are listed in a tracked baseline that may only shrink.
  V3 uses 8 seeds, not 2.
- A10 (N10). `tools/fixture_sheet.sh <name>` prints the cached sheet path.
  The plan classifies the 33 tools that read a `.sheet.txt` and the other
  callers of `check_char_fixture.sh` and `make_char_fixture.sh`.
  `INCURSION_FIXTURE_PIN=<key>` serves the entry the baseline binary built,
  and the gate's record and compare scripts set it, so a before/after holds
  the characters fixed. Every build appends name, key and dump hash to
  `logs/fixture-builds.tsv`; `tools/finish_bead.sh` reports each fixture
  whose dump hash changed, so no character change is silent.
- A11 (N11). One `.char` per fixture name per branch. They are text and merge
  like code; at the .369 merge each common name keeps the epic's god and
  creation keys.
- A12 (N12). D2: the hook grants levitation first, then sets the chasm under
  the player and to the east (in bounds), and the check's oracle text and its
  obsolete "do not shorten" note are re-derived and its red re-proved; the
  hook lands on both branches. The retire list adds the epic-only
  `tools/check_fixtures_load.sh`, `tools/repro_zto3q_rebuild.sh`, the
  inc-zto3q block of `tools/headless.sh` and its references in
  `tools/finish_bead.sh` and `tools/check_lib.sh`. The `File` path sets
  `GallerySlot = -1` explicitly, and a test covers it.
- A13 (minor). The cache keeps the last 3 keys per worktree; a lock older
  than 30 minutes is stale, as on the epic; script-raised prompts are keyed
  by (resource, event, ordinal); C7 `check_player_fields.sh` lists every
  serialized Player field as stated, derived or excluded, and fails on an
  unlisted one; C4 also proves a module slide rebuilds exactly once.

## 12. Version 4 amendments (third review, 2026-11-06)

A fourth reviewer (Fable) checked v3 and the plan against the code on both
branches (findings in the bead notes). Each amendment below overrides the
section or amendment it names.

- B1 (C1, overrides A9's srand clause). A draw after an `srand` does NOT
  count as stated, whatever fed the `srand`. T2 stays armed after every
  `srand` inside its window. Under `File`, the `srand(NextSeed() % 100)` in
  `GrantGear` (`src/Annot.cpp:584-591`) is skipped, and each draw after it
  is answered by its A4 key. The Multitude domain pick (`src/Create.cpp:2686`,
  `srand(formulaSeed)` then `possDom[random(max)]`) is answered by eight
  `domain_pool: <domain>` lines, by name. `formulaSeed` stays a stated value
  for what reads it after creation. C2 adds mutation (e): a draw inserted
  after a re-seed.
- B2 (M1, extends A4). A `GrantGear` call of `Item::GenItem` (`src/Annot.cpp:719-738`,
  gear "of random N to M", for example `lib/races.irh:61-65`) is ONE decision.
  The stated kit entry answers it in full through `GenItemForced`
  (`src/Encounter.cpp:3199-3237`), extended to set qualities. Kit entries
  gain `charges:`, which answers the charge and quantity draws of
  `Item::Create` (`src/Item.cpp:92-94, 131-167`). T2 never runs inside
  `GenItem` under `File`.
- B3 (M3, overrides A3 and A13 in part). The module-slide "rebuild once"
  path is removed: the module is in the cache key, so a slide is always a
  miss. C4 drops the tag-move case and the slide case. C4 proves a miss by
  editing the `.char`, by editing the options file, and by substituting a
  different file as the binary; it keeps the truncated-`.sav` exit 8 and the
  concurrency case. The epic tag move is proved by AC6.
- B4 (M4, overrides the K-M4 clause of section 3). A repeated identical
  request fails with "stated value rejected by the game" only when that
  key's queue is empty. The epic god loop (epic `src/Create.cpp:1185-1203`)
  states the god once per request, in order.
- B5 (m1, section 1). Recording is opt-in: `INCURSION_RECORD_CHAR=<path>`.
  With it unset, normal play writes no file.
- B6 (m2, extends A2). The (resource, event, ordinal) key also covers
  `EV_PREREQ` (`src/Create.cpp:935, 992`), `EV_ISTARGET` (`:1101`) and
  `EV_STARTING_ITEM` (`:1371-1373`). Plan step 0 censuses all of them.
- B7 (m3, section 10). The early proof moves forward: phase 7's
  verification builds one hand-written `.char` of a fixture common to both
  branches and compares its dump with the old `.sav`'s dump.
- B8 (m4, A10). The base of `tools/finish_bead.sh`'s changed-fixture report
  is the `INCURSION_FIXTURE_PIN` record. The `docs/VERIFICATION.md` controls
  catalog row for `INCURSION_LOAD` is updated with AC7.
- B9 (m5, C2). C2's header names inc-10v7f on its seed control, and its
  walks select every menu entry by name with `@choose`.
- B10 (m6, A7). If the dump commit does not apply at d71c1823, the dump
  extension is ported by hand in the scratch worktree, and the two-loads
  test re-checks it there.
- B11 (m7, section 2). Under `File`, the `OptionManager(OPC_CHARGEN)` yn is
  answered "no" and creation options come from `options:`. A recorded walk
  that changed options writes the changed options file beside the `.char`.
- B12 (m8, section 2). `PickName`'s two draws for races with surnames
  (`src/Create.cpp:1031-1036`) are keyed `name` and `surname`.
- B13. Rejected: replacing section 4's moved bodies with key-script lines
  run through the menus (finding M2). Owner's ruling, 2026-11-06: it ties
  every fixture to the menu layout, and a menu change would need a hand edit
  of each fixture, which G3 forbids. Section 4 stands.

## 13. Version 5 amendments (draw census, 2026-11-06)

Plan step 0 walked 99 characters (every race by class pair, rerolls, the
Multitude god, level-ups, default options) and logged every draw; results in
the bead notes. B14-B17 close what it found. B18 is the owner's ruling
(2026-11-06): new decision kinds will keep arriving, so adding one MUST be a
small, mechanical step, not a redesign.

- B14. Craft formulas: `Character::RecalcCraftFormulas` (`src/Skills.cpp:4108`)
  runs in `Create` and in every `AdvanceLevel`; it seeds from `formulaSeed`,
  picks formulas by list position and sets `SP_CREATE` (saved). Each pick is
  a sourced pick answered by spell name (B18).
- B15. An item that a script or event generates inside the T2 window
  (`EV_GENITEM`, `EV_BIRTH` scripts; `src/Encounter.cpp` `GenItem`,
  `NumQualities :3078`, `MakeMagicWeaponArmour :3149`) is ONE decision,
  answered by a complete stated item exactly as B2.
- B16. Plan step 1 classifies every `Magic::CalcEffect` and `TEffect::Power`
  draw in the window: one that decides a saved character fact is sourced;
  any other goes in the `unstatedDraw` baseline with its reason.
- B17. C2's gate set includes walks with rolled hit points and mana, random
  gender and the Beginner's Kit on, under an options file committed for it
  (`options-2026-08-22.dat` turns all four off).
- B18. Room for new decisions. Overrides every per-site key and field list in
  sections 2-3, A2, A4, B1, B2, B12, B14 and B15, which become instances:
  - Every decision goes through one of three primitives: `SourcedRoll(key,
    ...)` for a number, `SourcedPick(key, candidates)` for a choice among
    resources, answered by name, and `SourcedItem(key, ...)` for a generated
    item, answered by a complete stated item. A prompt is a `SourcedPick`
    over its labels. No other decision type exists.
  - A key is an enum name plus an automatic context: the resource whose
    script or event is running, any event (not a fixed list), and the
    ordinal within that context. A new event or a new script draw needs no
    code change.
  - The `.char` grammar is generic: `<key> [context]: <value>`. The parser,
    the recorder, `tools/fill_chars.sh`, `tools/char_rekey.sh` and C2's
    coverage list read the enum and the three primitives, so none has a
    per-key branch. A check fails on any per-key branch in them.
  - Adding a decision is: wrap the draw or prompt in a primitive with a new
    enum name and a default; run `tools/fill_chars.sh`; commit both. T1 or T2
    names the site when this is forgotten. `tools/fixtures/README.md` states
    this procedure.
  - `tools/census_creation_draws.sh` stays, run by the nightly harness; it
    reports any draw in the window that is neither sourced nor in the
    baseline, before a fixture build meets it.

## 14. Version 6 amendments: scenes (2026-11-07, revision 2)

Moved to inc-9s4u0 by section 15 (V7-2). Kept here as that bead's design;
nothing in this section is work for inc-10v7f.

A built fixture gets a fresh, random level 1, so a check that read the map a
`.sav` once froze loses it. Research (bead notes 2026-11-07,
`logs/sites/map31-needs.md`) read the 31 checks marked as map-dependent: 9
need nothing specific from the map, 21 need placed monsters, items, features
or terrain, and 1 needs depth 10 (ruling D2, section 8, unchanged). None
needs the level generator. Owner's ruling (2026-11-07): a check that reads
the map runs on a fixed test map and places what it needs by name. The level
is not made stable; it is not used. Revision 2 folds in two reviews (engine
findings E1-E10, verification findings V1-V10, bead notes). Each amendment
below overrides the section it names.

- S1 (overrides the "reads no map" clause of section 9). A check MAY read
  the map only when it states a scene. It then reads only the test map and
  the things its scene placed.
- S2. The test map. A new Region "Fixture Test Chamber", appended to
  `lib/dungeon.irh` (append-only rule), with a `Grid`. `Map::Generate` loads
  a Region rID as the whole level through `Map::LoadFixedMap`
  (`src/MakeLev.cpp:1485, 1536`), so the map size is the grid size and no
  random draw places a room. The grid MUST give:
  - 41 by 41 squares. `Map::WriteMap` flips a grid at random on both axes
    (`src/MakeLev.cpp:1176-1186`); an odd size puts the center square on
    itself under every flip (E1).
  - A one-square border of "Indestructable Rock" (the resource's own
    spelling, `lib/dungeon.irh:546`), so square (0,0) is rock.
  - Open floor everywhere inside the border, of a new lit floor terrain
    "Fixture Lit Floor" that carries `TF_LOCAL_LIGHT`. `calcLight` lights
    only such terrain on a fixed map (`:167-176`); `RF_ALWAYS_LIT` is read
    only by room generation and does nothing here (E2, V1).
  - A `Tiles` entry for the start tile with `TILE_START` at (20,20) (E7).
  The scene applier clears `isVault` on every square after the map is
  written, because `WriteMap` sets it on every grid square (`:1187`) and
  rest, teleport and spawn code treat vault squares differently (E3). No
  monster arrives on the test map except by a scene line: the applier turns
  off the map's wandering-monster arrival (`DaysPassed` path) (E7).
- S3. The scene file. `tools/fixtures/scenes/<name>.scene`, the section 3
  grammar (`key: value`, names only, every line consumed, a bad line fails
  with its line number). Keys:
  - `map: <region>`: optional; the default is "Fixture Test Chamber".
  - `monster: <name> at <dx> <dy> [hostile|peaceful|ally] [asleep]`
  - `item: <section 3 item value> at <dx> <dy> [count <n>]`; a corpse or
    statue names its monster with `of <monster>`. Offset 0 0 puts the item
    on the player's own square.
  - `terrain: <name> at <dx> <dy> [to <dx2> <dy2>]`: one square, or a
    filled rectangle. Terrain MAY replace open floor (inner walls, plain
    unlit "Floor" for a dark patch) (V2, V7).
  - `feature: <name> at <dx> <dy>`: doors, portals, altars, traps.
  Offsets are from the player's start square. A name MUST be written in
  full, with any `;tag` suffix ("stinking cloud;terrain"). A new typed
  finder resolves it: it takes the key's resource type, counts every exact
  match across all modules, and fails on zero or on more than one.
  `Game::Find` cannot serve: it takes no type, returns the first match in
  type order, and caches 31 characters of the name (`src/Res.cpp:358`)
  (E5). A square outside the map, or a monster or item put on a square that
  is not open floor, fails the run.
- S4. Applying a scene. A check sets `INCURSION_SCENE=<name>`;
  `tools/headless.sh` passes it to the run. The scene applies at the first
  arrival on a map, whether the character was loaded from a fixture or made
  in the run (V3). The applier:
  1. Builds the test map and moves the player, the player's companions and
     mount onto it, through ONE helper extracted from `Player::MoveDepth`'s
     companion gathering (`src/Feature.cpp:1448`). `MoveDepth` itself
     refuses a non-dungeon `dID`, and a portal move takes the player only
     (`:481`) (E4). The old level 1 stays in memory and in the save, as
     after any portal trip.
  2. Applies the scene lines in file order.
  Placement reuses engine bodies, moved, never copied (section 4, G2):
  monster creation and placement from wizard summon (`src/Debug.cpp:674`),
  which keeps honoring `INCURSION_SUMMON_NO_GEAR` (`:686`) (V6); attitude,
  sleep and ally status from the bodies `WriteMap` (`src/MakeLev.cpp:1286-1296`)
  and wizard "Make Player Master of Monster" (case 28) use; floor items and
  features from `WriteMap`'s item and feature branches (`:1260-1296`).
  Item Acquisition is not reused: it puts the item in the pack through
  `EV_PICKUP` (E6). The plan lists each extraction.
- S5. A scene MUST state every map fact its check reads. Facts it does not
  state (a summoned monster's hit points, an item's flavor) stay random.
  `tools/seed_sweep.sh` varies them (`INCURSION_SEED_OVERRIDE`) and catches a
  check whose result changes with them. It cannot catch a fact that happens
  to hold on every swept seed; the reviewer of each converted check confirms
  that its scene states every fact the check reads (V6).
- S6. New check C8 `check_scene.sh`: one scene that uses every key. It
  asserts the map size, rock at (0,0), every interior square open and lit
  (`BrightAt`), `isVault` clear, the player at (20,20) (`EnterX`/`EnterY`),
  each companion and the mount on the test map, each placed thing on its
  square with its attitude and sleep, no monster the scene did not place
  after 100 turns of rest, and the same state after a save and a reload (E9).
  Red, one mutation each: (a) an offset applied with the wrong sign; (b) a
  `terrain:` line skipped; (c) an unknown name accepted; (d) an ambiguous
  name accepted; (e) the scene not applied at all; (f) placement on the old
  level 1 instead of the test map; (g) companions left behind; (h) a monster
  accepted on a wall square; (i) lines applied in reverse order; (j) an even
  grid size (V4).
- S7. Fact lines. A check that states a scene carries
  `# fact: map -- scene <name>`. `docs/VERIFICATION.md`'s controls catalog
  gains a row for `INCURSION_SCENE` in the same commit as C8, so
  `tools/check_fact_lines.py` accepts the line (V5).
- S8. Conversion of the 31 checks. 5 drop stale "arrival map" fact lines
  and state no scene. 4 build their scene in a source probe; they state
  `map:` alone, so the probe runs on the test map. 21 get a scene file; a
  check with two sessions on different scenes (`check_natural_save.sh`)
  gives each session its own scene. A converted check drops any
  "Genocide Everything" step it used to clear the random level, because the
  test map holds only what the scene placed (V7). `check_vararg_format_live.sh`
  reads a `.sav` as a file; section 8's specimen rule decides it, not a
  scene (V7). `check_dungeonmap_bounds.sh` keeps ruling D2. Section 8's
  three scene fixtures stay as section 8 states; where one of them serves a
  check in the 31, S8 wins and that check gets a `.scene` file.
- S9. Open: no feature named "rune" exists in `lib/` (E10). The plan's first
  conversion step finds the resource names `check_natural_save.sh` reads
  (its runes and tanglefoot strands) and writes them into its scenes.

## 15. Version 7 amendments: scope (2026-11-08)

Owner's rulings, 2026-11-08 (bead notes). The builder regenerates the
created character and nothing else. Each amendment overrides the sections
it names.

- V7-1. Every step after game load belongs to the check that needs it, in
  that check's own key script. Withdrawn: section 4, section 5 step 3, C6,
  A1's "plus each post-creation key body" clause, and B13. The tripwire
  window ends where `-build` exits.
- V7-2. Section 14 (S1-S9), ruling D2 and A12 move to inc-9s4u0, which
  depends on this bead. Of the 31 map-flagged checks
  (`logs/sites/map31-needs.md`), the 9 that need nothing from the map switch
  to built fixtures in this bead. The 22 that need a placed map keep their
  old `.sav` as a specimen until inc-9s4u0 converts them. Section 8's scene
  bullet applies only to fixtures whose checks are not among the 22.
