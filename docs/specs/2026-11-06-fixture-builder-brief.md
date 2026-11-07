# Fixture builder: plan brief (inc-10v7f)

Goal, design and rulings: `docs/specs/2026-11-06-fixture-builder-spec.md` v5
(cited as "spec §N", "A<n>" for the section 11 amendments and "B<n>" for the
section 12-13 amendments; B18 (three generic primitives) governs every
decision site; an amendment overrides the section it names). Stack: C++ engine, `BACKEND=posix
./build_macos.sh`, shell and Python checks run through `tools/headless.sh`.
Sized: Large. Every phase is one commit on branch `inc-10v7f`, lane `tools:`
(a build mode and its harness; no player-visible behavior).

## Acceptance criteria (bead) and where each is proved

| AC | Criterion (short) | Proved in |
|---|---|---|
| AC1 | Every master fixture is a `.char` plus a `.sav` built from it | Phase 13 |
| AC2 | Builder calls creation's own functions; reviewer confirms nothing is copied | Phases 4-8; `tools/check_creation_source_sites.sh`; code review sign-off in bead notes (phase 15) |
| AC3 | A check builds through creation and builder, fails on a sheet difference, red by mutation | Phase 10 (C2) |
| AC4 | A check fails when a `.sav` differs from what its `.char` builds | Phase 9 (C1, V2) |
| AC5 | `tools/headless.sh` rebuilds a fixture from its `.char` | Phase 9 |
| AC6 | Epic proof on the inc-pu6v.369 merge | inc-pu6v.369, after this bead lands (spec §10 step 3). Before landing, add a line naming inc-10v7f AC6 to the inc-pu6v.369 description, so `tools/check_bead_evidence.py` accepts the AC6 line as a named follow-up |
| AC7 | `tools/fixtures/README.md` describes the new system | Phase 13 |

## Standing constraint: `Live` MUST NOT change normal play

The source refactor (phases 3-6) touches every creation decision site. The
`Live` backend MUST make the same `random()` calls, in the same order, as the
code it replaces. Each of phases 3-6 verifies this two ways, inputs fixed:
(a) `tools/char_dump.sh` dumps of characters walked by a fixed set of
creation key scripts on fixed seeds and options, old binary against new, MUST
be identical; (b) `tools/nightly_verify.sh --compare` against a record made at
the phase's base commit. A difference stops the phase.

## Files touched

| File | Change |
|---|---|
| `inc/CreationSource.h`, `src/CreationSource.cpp` (new) | The interface, the decision-key enum, the `Live`/`Replay`/`File` backends, the recorder with its `RInf` and `.char` serializers (spec §1, A6). |
| `src/CharFile.cpp` (new) | `.char` parser and validator: names, queues, surplus, duplicates, ranges, defaults, `expect:` (spec §3, A5). |
| `src/Create.cpp` | Every decision site of the phase-1 list calls the source; the `MO_RECREATE` branches are deleted; `GrantPerks` non-static; `Game::NewGame` tail moved into a function (A1); `GallerySlot = -1` under `File` (A12). |
| `src/Annot.cpp` | `GrantGear` draws keyed by (resource, annotation ordinal, draw kind) (A4). |
| `src/Term.cpp`, `src/TextTerm.cpp` | Prompt primitives and `LearnTable` call the source; the single T1 key-read wrapper (A8). |
| `src/Managers.cpp` | `SkillManager` commit extracted (spec §2); level gate and multiclass bodies moved into functions (spec §4). |
| `src/Debug.cpp` | Wizard bodies moved into functions: learn, item, join/rung/altar (spec §4). |
| `src/Event.cpp` or the script dispatch site of the phase-1 list | Creation-event script draws and prompts keyed by (resource, event, ordinal) (A2). |
| `src/Main.cpp` | `-build <file>` and `-dump` extension entry points (spec §5, A7). |
| `src/Dump.cpp` | Canonical dump: rIDs as names, handles dropped, per-level rolls, skill pools, perks, kit qualities, spells, stati (A7). |
| `src/Feature.cpp` | `INCURSION_LEVITATE_CHASM`: grant levitation, then chasm under and east of the player; search removed (D2, A12). |
| `src/MultiSelectProbe.cpp` | Its `MO_RECREATE` sites call the source (A6). |
| `tools/char_dump.sh`, `tools/build_fixture.sh`, `tools/fixture_sheet.sh`, `tools/fill_chars.sh`, `tools/char_rekey.sh`, `tools/char_convert.sh` (new) | Spec §5, §8, A5, A7, A10. `char_convert.sh` stays until the epic conversion lands. |
| `tools/headless.sh`, `tools/finish_bead.sh`, `tools/gate_record.sh`, `tools/gate_compare.sh` | Cache lookup, lock, exit 8, module-slide rebuild, pin, build log report (spec §7, A3, A10, A13). |
| `tools/check_fixture_build.sh`, `_equivalence.sh`, `_tripwires.sh`, `_repair.sh`, `check_perk_fields.sh`, `check_moved_bodies.sh`, `check_player_fields.sh`, `check_creation_source_sites.sh` (new) | C1-C7 and the A6 grep check. Each carries its `# fact:` lines. |
| `tools/fixtures/unstated_draws.baseline` (new) | `unstatedDraw` sites; may only shrink (A9). |
| `tools/fixtures/chars/*.char` (new, 74) | The converted fixtures. Tracked `.sav`, `.sheet.txt`, `.keys`, `MANIFEST` removed (spec §7). |
| `tools/fixtures/specimens/` (new) | Old-format `.sav` files that phase 2 classifies as "needs the bytes" (spec §8). |
| Every tool phase 2 lists as a fixture reader | Switched to `INCURSION_LOAD=<name>`, `tools/fixture_sheet.sh` or a specimen path. |
| `tools/make_char_fixture.sh`, `tools/sync_char_fixtures.sh`, `tools/check_char_fixture.sh`, fixture-only key scripts | Retired (spec §8). |
| `tools/check_dungeonmap_bounds.sh` | Depth-10 jump, new hook, oracle text re-derived, red re-proved (D2, A12). |
| `tools/fixtures/README.md`, `.gitignore` | New system described; `logs/fixture-cache/` ignored (spec §8). |

## Phases (one commit each)

0. **Draw census (A9).** Add T2 in log-only mode (`INCURSION_DRAW_CENSUS`):
   every `random()` and dice call inside `Player::Create` and inside
   `AdvanceLevel` logs its caller, including draws after every `srand`
   (B1) and inside script events `EV_BIRTH`, `EV_ADVANCE`, `EV_PREREQ`,
   `EV_ISTARGET`, `EV_STARTING_ITEM` (A2, B6). Write `tools/census_creation_draws.sh`,
   which walks one character per race-by-class pair through the screens on a
   fixed seed and options and writes one TSV of (caller, count) under `logs/`.
   Verify: the TSV names every site of spec §2, or the phase reports each
   missing one; a draw inserted in `RollAttributes` appears in the TSV.
   Result summary into the bead notes.
1. **Site list (A6, A2).** Research, no tracked source change. Produce
   `docs/specs/2026-11-06-fixture-builder-sites.md`: every `MO_RECREATE`,
   `MO_CREATE`, `reincarnate` and `RInf` site on master AND on inc-pu6v, every
   creation-event script hook in `lib/` that draws or prompts (about 80), and
   every census caller from phase 0, each with its primitive and enum name
   (B18); every `Magic::CalcEffect` and `TEffect::Power` draw classified as
   sourced or baseline with its reason (B16). Verify: a
   second independent grep pass finds no site missing from the list.
2. **Tool classification (spec §8, A10).** Research. Add a section to the
   sites file that classifies every tool, check and script on master that
   reads `tools/fixtures/chars/` (sheet reader, loader, specimen user,
   `make_char_fixture.sh`/`check_char_fixture.sh` caller), each with its
   target: cache name, `tools/fixture_sheet.sh`, specimen, or retire. Also
   list each check that asserts on a derived sheet value (spec §7). Verify:
   `grep -rl fixtures/chars tools` minus the list is empty.
3. **Canonical dump (A7).** Extend `-dump` and write `tools/char_dump.sh`.
   Verify: two loads of one fixture dump identically; a hand-changed perk
   field, kit quality, skill rank and per-level hit roll each change the dump.
   This dump is the oracle of every later phase.
4. **Source interface, `Live` and `Replay` at `src/Create.cpp` sites (spec
   §1, A6).** Interface, key enum, recorder with both serializers, back-nav
   pop; the three primitives `SourcedRoll`, `SourcedPick`, `SourcedItem`
   with automatic context (B18); craft-formula picks (B14); recording only when `INCURSION_RECORD_CHAR` is set (B5); `name` and
   `surname` keys (B12); `domain_pool:` by name (B1). Every listed
   `Create.cpp` site calls the source; its `MO_RECREATE`
   branch is deleted. Add `tools/check_creation_source_sites.sh` (A6 grep).
   Verify: the standing constraint; the existing reincarnation checks (phase
   1 names them) pass; a reincarnated character's dump equals the old
   binary's; the recorder's `RInf` output equals the old `RInf` bytes for the
   same walk.
5. **`GrantGear`, `GrantBeginnerKit`, missile counts, script-generated
   items (A4, B1, B2, B15).** Under
   `File` the `NextSeed()` re-seed is skipped; each `GenItem` call is one
   decision answered through `GenItemForced` with qualities; `charges:`.
   Verify: standing constraint; recorder `.char` lists every kit draw with
   its key; the drow fixture's "of random 3 to 4" weapons build from their
   stated entries.
6. **Prompts, screens and script events (spec §2, A2, A8).** Prompt
   primitives, `LearnTable`, `RollAttributes` key reads, `SkillManager`
   commit function, `OptionManager(OPC_CHARGEN)`, creation-event script draws
   and prompts. Verify: standing constraint; a walk recorded on every phase-0
   race-by-class pair yields a `.char` with no decision key missing.
7. **`File` backend, tripwires, build mode (spec §3, §5, A1, A5, A8, A12).**
   Generic parser with no per-key branch (B18), defaults that fail with the
   exact missing line, T1 wrapper, T2
   armed with the baseline, `NewGame` tail moved, `GallerySlot = -1`,
   gallery write skipped, `-build`, `tools/build_fixture.sh`. Add the B18
   no-per-key-branch check over parser, recorder and tools. Add C3
   (`check_fixture_tripwires.sh`, including the A1 cases), C5, C7. Verify:
   each of C3, C5, C7 red by its named mutation; a `File` build leaves no
   gallery entry and `GallerySlot` is -1, red when the early return in
   `TouchGallery` is removed; a recorded `.char` builds
   and its dump equals the walked character's dump; V3 on 8 seeds; one
   hand-written `.char` of a fixture common to both branches builds and its
   dump equals the old `.sav`'s dump (B7); the `OptionManager` yn is
   answered "no" (B11); a repeated god request with a non-empty queue
   passes, with an empty queue fails (B4).
8. **Post-creation keys and moved bodies (spec §4).** Move each inline body
   into a function the UI calls; add the keys; add C6. Verify: C6 red when
   one moved body is changed only on the builder side; the wizard menus give
   the same dumps as before the move, old binary against new.
9. **Cache and automatic repair (spec §7, A3, A10, A13).** Cache key,
   clean environment, `tools/headless.sh` lookup with lock and temporary
   rename, exit 8, one module-slide rebuild, keep 3 keys, 30-minute stale
   lock, `INCURSION_FIXTURE_PIN` in the gate scripts, `logs/fixture-builds.tsv`
   and its report in `tools/finish_bead.sh` against the pin record (B8), `tools/fixture_sheet.sh`. Add C1
   and C4. Verify: C1 red when the lookup ignores the `.char` hash (AC4); C4
   cases (B3: an edited `.char`, an edited options file and a substituted
   binary each miss; a truncated `.sav` exits 8; two concurrent runs build
   once);
   AC5 shown by a run with an empty cache.
10. **Equivalence check C2 (AC3).** Gate subset plus nightly full sweep;
    coverage list generated from the key enum; gate set includes the B17
    walks under a committed options file; walks select by `@choose`
    name; the seed control names inc-10v7f (B9). Verify: red on each of the
    mutations of spec §9 (a)-(d) and B1 (e), one at a time; AC3's mutation
    in a shared creation function's caller.
11. **Fill, rekey and conversion tools (A5, spec §8).** `tools/fill_chars.sh`,
    `tools/char_rekey.sh`, and the conversion helper `tools/char_convert.sh`
    (record the fixture's key script, set each value that differs from the
    old `.sav`'s dump to the old value, build, compare dumps outside the
    allowlist). Verify: a new decision with a default makes every build fail
    with its line; `fill_chars.sh` writes the line and the builds pass; a
    rekey round trip leaves every `.char` byte-identical; `char_convert.sh`
    on one fixture gives a dump equal to the old `.sav`'s dump, and fails
    when one old value is withheld.
12. **Early proof of the conversion procedure (R-S-3).** Convert two
    fixtures that exist on master and on inc-pu6v with `tools/char_convert.sh`.
    Verify: both dumps equal their old `.sav` dumps outside the allowlist.
    Stop and report before phase 13 if not. This proves the procedure on
    master only; epic compatibility is proved by C2 and C3 on the epic in
    inc-pu6v.369 (spec §10 step 2).
13. **Convert all 74 master fixtures (spec §8, G4, D2).** Record each
    fixture's key script on the current binary, fill old values with the
    conversion helper, build, compare the full dump with the old `.sav`'s
    dump on current master outside the allowlist. Scenes become character
    fixtures with their scene built by the check; the D2 hook change and
    `check_dungeonmap_bounds.sh` re-derived; specimens moved; every phase-2
    tool switched; old files and retired tools removed; README rewritten;
    the `docs/VERIFICATION.md` catalog row for `INCURSION_LOAD` updated (B8);
    README states the add-a-decision procedure (B18); a test adds a dummy
    decision by that procedure alone and every build passes after
    `fill_chars.sh`. The nightly census run is wired in
    `~/Scripts/nightly-harness` as a separate commit in that repository.
    Verify: per-fixture comparison table in the bead notes (AC1); every check
    phase 2 lists passes and passes `tools/seed_sweep.sh`; AC7. Large
    enough to split across several implementer runs; one commit at the end.
14. **Epic oracle dumps (A7).** No commit on this branch. Make a scratch
    worktree at d71c1823 with a detached HEAD (no branch, so
    `tools/check_orphan_branches.sh` stays green), apply the phase-3 dump
    commit there (if it does not apply, port the dump extension by hand there,
   B10), build headless, and write the canonical dumps of its 82
    fixtures to `~/Scripts/Incursion/docs/evidence/inc-10v7f/epic-d71c1823/`,
    untracked, with a README naming the commit and command. Verify: 82
    dumps; two loads of one fixture dump identically. Remove the scratch
    worktree.
15. **Review and land.** Code review (independent reviewer, the bead's
    ruling) with the "no copied logic" sign-off in the bead notes (AC2);
    fix every real finding. Add to the inc-pu6v.369 description: it carries
    inc-10v7f AC6, uses the phase-14 dumps as its oracle, and MUST show C2
    and C3 passing on the epic before it lands (spec §10 step 2). Commit
    message with AC1-AC7 lines; the AC1 line states that the `.sav` is the
    untracked cache build of ruling D1. `tools/finish_bead.sh inc-10v7f`.

## Implementers

`tools/claude_budget.py` said `sonnet-first` at 19:29 on 2026-11-06 (day 5,
39% of 55%). Coding phases (0, 3-11, 13) go to `sonnet` with label `budget:`
while it says so, else DeepSeek in phases of about 40 steps, then Haiku 5.5+,
`sonnet`, `opus`, per `always-implement-via-codex`. Re-run the budget tool
before each dispatch. Research phases (1, 2) go to an agent with label
`research:`. Phases 3-11 build the binary, so one implementer at a time in
the worktree. Claude reviews each diff and re-runs each phase's verification
before the next dispatch.

## Test plan

- Adversarial: a `.char` with an unknown key, a surplus value, a duplicate
  single key, an ambiguous label, a name that is not in the module, an
  out-of-range rank; a rejected god answer (the epic loop); a back-navigation
  in a recorded walk; a `[MORE]` during creation; two concurrent builds; a
  truncated cached `.sav`; a stale lock; a moved save tag; a module slide; an
  inserted prompt, raw-key screen and `random()` (each named by its
  tripwire); a stray `INCURSION_*` variable in the caller's environment.
- User: make a new fixture by playing with recording on, commit the
  `.char`, run a check that loads it; edit one feat in a `.char` and see the
  next run rebuild.
- Live data: all 74 master fixtures converted and compared with their old
  `.sav` dumps; every check that loads a fixture passes; a reincarnation from
  a real gallery behaves as before.
- Gate: `tools/nightly_verify.sh --compare` at each source phase, and
  `tools/finish_bead.sh` at landing.
