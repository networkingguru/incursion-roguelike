# Fixtures

## Dated options fixtures

These 900-byte files preserve the settings that scripted checks originally ran
against. Each is the exact `Options.Dat` blob from the named repository commit:

| Fixture | Source commit | Contents |
|---|---|---|
| `options-2026-08-18.dat` | `2f58be3` | The 2026-08-13 settings plus the 21-byte character-generation profile described below. Changed by inc-rt8l: `OPT_BEGINKIT` (101) is 0, the Beginner's Kit off. |
| `options-2026-08-22.dat` | `2092592` | The 2026-08-18 settings with `OPT_AUTOOPEN` changed from 0 to 2. Changed by inc-rt8l: `OPT_BEGINKIT` (101) is now 0, the Beginner's Kit off. This keeps a change to Roark's NECESSITIES list from shifting seed-pinned checks. |
| `options-sneak-invis.dat` | n/a (derived) | `tools/gates/Options.Dat` with `OPT_AUTOHIDE` (518) forced to 0. `tools/check_sneak_invis.sh` uses it: with Automatic Hide in Shadows on, a rogue auto-hides in the dark and every blow counts as an unseen attack even without a spell, which spoils the visible control. Changed by inc-rt8l: `OPT_BEGINKIT` (101) is 0, the Beginner's Kit off. |
| `options-sneak-invis-maxhp.dat` | n/a (derived) | `options-sneak-invis.dat` with `OPT_MON_MAX_HP` (108) forced from 0 to 3 (DOUBLE), so a summoned monster has fixed hit points. `tools/check_sneak_invis.sh` and the fixture `orc-rogue-sneak-seed1` use it (bead inc-b4l3g.30). |
| `options-2026-08-22-maxhp.dat` | n/a (derived) | `options-2026-08-22.dat` with `OPT_MON_MAX_HP` (108) forced from 0 to 3 (DOUBLE), so a summoned monster has fixed hit points. `tools/check_dequ_reach.sh` and the specimen `orc-warrior-dequ-seed5-maxhp` use it (bead inc-drr0). |
| `options-2026-08-22-freeadv.dat` | n/a (derived) | `options-2026-08-22.dat` with `OPT_FREE_ADV` (803) forced to 1. `tools/keys/levelup-caster-sheet.keys` uses it to buy a real level through the character sheet's `G`/`A` command (Player::AdvanceLevel) on a frozen XP-0 fixture; the inc-ngku no-study control otherwise gets its level-up through `INCURSION_LEVELUP_PROBE`. Changed by inc-rt8l: `OPT_BEGINKIT` (101) is 0, the Beginner's Kit off, as in the base file. |
| `options-2026-08-22-noroomdesc.dat` | n/a (derived) | `options-2026-08-22.dat` with `OPT_DESC_ROOM` (407) forced from 2 to 0. `tools/check_crowd_turn_cost.sh` uses it: with the default, the first room a ghostwalking sweep enters opens a description box that eats keys. `OPT_MON_DJIKSTRA` (114) stays 1, which that check requires. Changed by inc-rt8l: `OPT_BEGINKIT` (101) is 0, the Beginner's Kit off, as in the base file. |
| `options-2026-08-22-kit.dat` | n/a (derived) | `options-2026-08-22.dat` with `OPT_BEGINKIT` (101) forced to 1. `tools/check_beginner_kit.sh` runs each build with it and with `options-2026-08-22.dat` (kit off), and reads the Beginner's Kit as the difference. |
| `options-2026-08-22-b17.dat` | n/a (derived) | `options-2026-08-22.dat` with `OPT_BEGINKIT` (101) forced to 1, `OPT_MAX_HP` (105) and `OPT_MAX_MANA` (106) forced from 2 to 0 (rolled), and `OPT_GENDER` (107) forced from 2 to 3 (random). These are the four creation settings the dated file turns off. `tools/check_fixture_equivalence.sh` walks characters under it (spec B17, bead inc-10v7f). |
| `options-2026-08-22-noautohide.dat` | n/a (derived) | `options-2026-08-22.dat` with `OPT_AUTOHIDE` (518) forced from 1 to 0. `tools/check_build_seeds.sh`, `tools/compare_creation_walks.sh` and `tools/check_fixture_equivalence.sh` use it: a monk, rogue, bard or kobold hides in the first turn of play otherwise. |
| `options-2026-08-22-b17-noautohide.dat` | n/a (derived) | `options-2026-08-22-b17.dat` with `OPT_AUTOHIDE` (518) forced from 1 to 0, as `options-2026-08-22-noautohide.dat` does: a monk, rogue, bard or kobold hides in the first turn of play otherwise, and a walk that saves at the end of creation then differs from its build. `tools/check_fixture_equivalence.sh --sweep` walks every race-by-class pair under it. |
| `options-dwarven-focus.dat` | n/a (derived) | `options-2026-08-22.dat` with `OPT_DWARVEN_AUTOFOCUS` (214) set to 0. `tools/check_dwarven_focus_manual.sh` uses it, so the manual Dwarven Focus command runs instead of Auto-Focus. |

The historical 21-byte profile in the 2026-08-18 fixture enabled
`OPT_BEGINKIT`; inc-rt8l now sets it to 0. The profile also has
`OPT_REROLL` enabled, `OPT_MAX_HP` and `OPT_MAX_MANA` set to 2,
`OPT_ELUDE_DEATH` set to 3, `OPT_GENDER` set to 2, and `OPT_SUBRACES` enabled.
These are historical harness inputs, not recommended player defaults.

A fixture is frozen. If a check needs different settings, add a new fixture
with its own provenance and date; never edit an existing fixture.

`options-2026-08-22.dat` and the two files derived from it were edited once by
inc-rt8l to turn the Beginner's Kit off. `options-2026-08-18.dat` and
`options-sneak-invis.dat` were edited the same way, once, by inc-rt8l. With the kit on, a fixture's result
depended on Roark's NECESSITIES list in `lib/dungeon.irh`, which changes. With
the kit off, a fixture depends only on its bytes and the game code. A fixture
MUST NOT turn on an option whose result depends on a game-data list that changes.

## Character fixtures

### What a fixture is

A character fixture is one text file, `chars/<name>.char`. The file states every
choice that made the character: race, class, attributes, feats, skill ranks,
hit point and mana rolls, kit items. Each decision is one line,
`<key> [context]: <value>`. The line `options:` names the options file. The line
`seed:` names the seed. Lines that start with `#` are comments.

The `.char` file is the only committed part. The game builds the character from
it with `tools/build_fixture.sh`. The `.sav` and the sheet are build products in
`logs/fixture-cache/`. Nobody edits them and nobody commits them.

Before this system, a fixture was a frozen `.sav` with a key script and a sheet
beside it. Each `.sav` was tied to the save format and to the map it was made
on. A `.char` file has neither tie. Git history holds the old files.

### Loading one in a check

Set `INCURSION_LOAD=<name>` and run `tools/headless.sh`:

    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=kobold-rogue-seed1 \
        tools/headless.sh tools/keys/load-char-sheet.keys 1

`tools/headless.sh` asks `tools/fixture_cache.sh` for the cached `.sav`. The
cache builds it when it has no entry. `tools/headless.sh` copies the `.sav` into
the run's own `save/`, so a run never writes the cache. The path form
`INCURSION_LOAD=tools/fixtures/chars/<name>.char` means the same.
`tools/fixture_sheet.sh <name>` prints the path of the cached sheet.

A cached `.sav` that fails to load ends the run with exit 8 and the line
`FIXTURE LOAD FAILED`. That is a loader or writer defect. The cache does not
rebuild the entry, because a rebuild would hide the defect.

A fixture holds only the created character. It holds no map and no position.
A check that reads a map waits for bead inc-9s4u0, which gives it a test map.

### Setup scripts

A state reached after creation belongs to the check, not to the fixture. A
check that needs the character wounded, in wizard mode, or without his weapon
includes a setup script. The name is `tools/keys/setup-<fixture>.keys`:

    @include setup-kobold-rogue-seed1.keys

The first lines of each setup script say which state the old `.sav` held.
Three chained characters have no `.char`: `alignment-drain-level1`,
`alignment-drain-level2` and `alignment-drain-warrior`. Their checks derive each
one from `quality-item-magic-seed5-opt0822` with a
`tools/keys/setup-alignment-drain-*.keys` script.

### Specimens

`specimens/` holds old `.sav` files that stay as files. Nothing rebuilds them.
There are two kinds of user.

1. Checks that read a map. They wait for bead inc-9s4u0. Each such check names
   its specimen in its `# fact:` lines. When the check moves to a test map, its
   specimen goes.
2. Checks that test old save-format bytes: `tools/check_script_var_recovery.py`,
   `tools/check_spellflag_migrate.sh`, `tools/check_spellflag_migrate6.sh`,
   `tools/check_spells_widen.sh`, `tools/check_racial_cannibalism.sh` and
   `tools/check_mage_loadout.sh`. Each names its specimen in its `# fact:` lines.

`tools/check_vararg_format_live.sh` belongs to kind 1: it reads a map.

`tools/char_convert.sh`, `tools/char_attribute.sh` and
`tools/check_char_convert.sh` also read specimens. They convert an old `.sav`
into a `.char`. They stay until the epic conversion (bead inc-pu6v.369) lands.
`specimens/MANIFEST` holds the rows they need: the key script, seed and options
file that made each old save. When the epic conversion lands, delete those
rows and the tools.

Conversion compares choices, not results. A conversion passes when every
choice the build makes equals the choice the old save recorded. A computed
value may still differ (a hit roll, a derived attribute, a feat a later rule
grants), and each `.char` header lists those lines under `result:`. Three
rulings from phase 13 of inc-10v7f shape this: a perk is not a choice, so
perks are left out of the comparison; the Beginner's Kit is left out of it
too; and the 11 fixtures that no check loaded were dropped instead of
converted.

### Old fixtures that have no `.char`

Two old fixtures keep their `.sav`, `.keys` and `.sheet.txt` in `chars/`. Both
wait for bead inc-3117y. A check loads each `.sav` by path. Delete a row when
its fixture gets a `.char`.

| Fixture | Key script and seed that made it | Settings file |
|---|---|---|
| `human-priest-mage-dual-seed4-gate` | `tools/keys/chargen-human-priest-mage-dual-save.keys`, seed 4 | `options-2026-08-22.dat` |
| `levitate-bottom-seed1` | `tools/keys/levitate-bottom-save.keys`, seed 1 | `options-2026-08-22.dat` |

### Adding a fixture

Record a walk, or write the file by hand.

To record a walk, run a key script that walks character creation. Set
`INCURSION_RECORD_CHAR` to the output path:

    INCURSION_RECORD_CHAR=$PWD/logs/new.char \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        tools/headless.sh tools/keys/chargen-default-save.keys 1

The recorder writes one line for each decision the walk made. Copy the file to
`tools/fixtures/chars/<name>.char`. Then build it and read the sheet:

    tools/build_fixture.sh tools/fixtures/chars/<name>.char
    tools/fixture_sheet.sh <name>

A build stops at 2048 MB of memory and fails with a `BUILD FAILED:` line that names the cap. `INCURSION_BUILD_MEM_CAP_MB` changes the cap.

To write the file by hand, start from a recorded file and change the lines.
`tools/check_handwritten_fixture.sh` shows the method: it builds a hand-written
`.char` and compares its dump with the dump of an old save. A wrong file does
not build a wrong character. The build fails and names the line, with
`missing line`, `surplus` or `stated value rejected by the game`.

Use only letters, digits, `.`, `_` and `-` in the name. Say race, class and the
reason for the fixture. Run `tools/check_fixture_build.sh` after you add a file.
It builds every `.char` and checks the cache.

### Adding a decision

A decision is a draw or a prompt in character creation that the dice or the
player answers. To add one:

1. Wrap the draw or prompt in one of three primitives from `inc/CreationSource.h`:
   `SourcedRoll(key, ...)` for a number, `SourcedPick(key, candidates)` for a
   choice among named resources, `SourcedItem(key, ...)` for a generated item.
   Add one line to the key table (the `X(name, kind, default, reach, seen)`
   macro) in the same header. Give the key a new name and a default.
2. Rebuild the game: `BACKEND=posix ./build_macos.sh`.
3. Run `tools/fill_chars.sh`. A `.char` that lacks a line fails to build with
   `missing line in <file>; add: <line>`. The tool appends the printed line,
   with its default, to each file. It builds again until the file builds.
4. Commit the C++ change and the filled `.char` files together. Read the diff
   of the `.char` files. Each file should gain only the new lines.

If you skip step 3, `tools/check_fixture_build.sh` fails and names the files.
To rename a key or a value later, use `tools/char_rekey.sh <old> <new>`. It
changes every `.char` and refuses a rename onto a name that exists.

`tools/fill_chars.sh` and `tools/char_rekey.sh` hold no list of keys. They read
the line from the build, or the key table from `inc/CreationSource.h`.
`tools/check_char_tools.sh` proves both tools on a copy of one `.char`.
`tools/check_add_decision.sh` plays steps 3 and 4 on a copy of every fifth `.char` (all with `ADD_DECISION_STEP=1`)
under `logs/`. It removes all lines of one key from each file, runs
`tools/fill_chars.sh`, and builds every file. It goes red when one file stays
unfilled.

A creation draw that no decision states must sit in an `unstatedDraw("<reason>")`
scope, and each scope is one row of `tools/fixtures/unstated_draws.baseline`.
`tools/check_fixture_tripwires.sh` states the rule in its header and checks the
rows. Run it after step 1. `tools/census_creation_draws.sh` lists the draws of
a walk.

### How the cache key works

The cache key is a SHA-256 over four hashes: the `.char` file, the options file
that its `options:` line names, the `incursion-headless` binary in use, and
`mod/Incursion.Mod`. A change to any one of the four gives a new key, and the
cache builds the fixture again. The entry is
`logs/fixture-cache/<key>/<name>.sav` with `<name>.sheet.txt`. The first three
lines of the sheet name the key. The three newest keys of each name stay.
`tools/fixture_cache.sh --key <name>` prints a key and builds nothing.

The header of `tools/fixture_cache.sh` states the rest: the lock, the build log
`logs/fixture-builds.tsv`, `INCURSION_FIXTURE_CACHE` and `INCURSION_FIXTURE_PIN`.
`tools/check_fixture_repair.sh` proves that the cache repairs a stale entry and
stops where repair would hide a defect.

## Tool-check fixtures

| Fixture | Contents |
|---|---|
| `bead-dupes-offline-proof.json` | Two small fake beads, `bd list --json` shape, no real bead text. `tools/check_bead_dupe_wiring.sh` hands this to `tools/bead_dupes.py check-draft` so it has a candidate to rank before the keyless path exits 3. |
| `opencode-loop/loop.jsonl` | A trimmed opencode `events.jsonl` extract from a run that fell into a DeepSeek repetition loop: one real loop step (its `text` parts and `step_finish`, 3689 output tokens with 17 short lines repeated three or more times) plus a few normal steps. `tools/opencode/loop_check.py` exits 1 on it. Tool outputs are shortened, so the fixture is under 20 KB. |
| `opencode-loop/clean.jsonl` | A trimmed extract pairing the 10786-token `bsqm` step whose text is mostly repeated ```` ``` ```` and `{ }` lines inside code fences -- the false-positive trap the fence-stripping rule exists for -- with several normal `twr9` steps. `tools/opencode/loop_check.py` exits 0 on it. Under 51 KB. |
| `../opencode/fixtures/markup-dsml.jsonl` | The failing step (its `step_start`, `text` and `step_finish`) of capture `docs/evidence/inc-w431/20261001T120122Z-44048`: the model printed its native tool-call markup as text (`DSML`), so opencode got no tool call and the run ended with no report (157 output tokens). `tools/opencode/loop_check.py` exits 1 with a `markup ` line. ~1.6 KB. |
| `../opencode/fixtures/one-line-loop.jsonl` | The failing step (its `step_start`, `text` and `step_finish`) of capture `docs/evidence/inc-w431/20261001T120943Z-92370`: the model repeated one 48-char line (`<budget:token_budget>200000</budget:token_budget>`) and `Viewing.` many times in one 2875-token step. `tools/opencode/loop_check.py` exits 1 with a `loop ... same_line=` line. ~10 KB. |
