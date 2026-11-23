# Test harness mechanics

## incursion-never-run-the-binary-from-the-repo-root
NEVER run `./incursion` or `./incursion-headless` directly from the repo root — it writes into Brian's real `save/`. Use `tools/headless.sh` (own `save/`/`logs/`, symlinks `mod/`/`lib/`); `--tty` for terminal-drawing tests. Back up `save/` before any experiment that might bypass the harness.
Why: prevents a scripted run from overwriting real saves.
History: docs/rules-history/test-harness-mechanics.md#incursion-never-run-the-binary-from-the-repo-root.

## brian-plays-from-his-own-folder
Brian plays from `~/Games/Incursion`, outside every repository and worktree. `~/Games/Incursion/play.sh` sets `INCURSIONPATH` to that folder and runs the epic's SDL binary, `~/Scripts/Incursion-inc-pu6v/incursion`. The folder holds Brian's real `save/` (gallery included), `logs/` and `Options.Dat`; `mod`, `lib`, `fonts`, `graphics` and `lang` are symlinks into `~/Scripts/Incursion-inc-pu6v`. "Rebuild my bins" means `./build_macos.sh` (SDL) in `~/Scripts/Incursion-inc-pu6v`; the play folder needs no change after a rebuild. When the epic lands or Brian names another build, repoint `play.sh` and the five symlinks. MUST NOT run any binary, check or script with `INCURSIONPATH` set to `~/Games/Incursion`, and MUST NOT write into that folder except to repoint it. A `save/` inside a repository or worktree holds no real character.
Why: test characters kept landing in the gallery of the folder Brian played from.
History: new rule, no prior narrative to archive. Bead inc-ew3sc.

## incursion-one-run-one-directory
Pass a unique `INCURSION_RUN_DIR` for every run in a loop; count run directories and confirm the count equals runs before trusting a per-seed number. `tools/check_headless.sh` assertion 11 is the one case that must NOT pass `INCURSION_RUN_DIR` (tests the shared-default guard).
Why: sessions sharing a run directory merge their logs into what reads as one session.
History: docs/rules-history/test-harness-mechanics.md#incursion-one-run-one-directory.

## incursion-worktree-ab-needs-live-options-dat
A soak/A-B run MUST use a settings file matching the KEY SCRIPT: `tools/gates/Options.Dat` is committed/pinned, `tools/headless.sh` takes `INCURSION_OPTIONS`, `gate_compare.sh` refuses on checksum mismatch. Check for "exit 5, NO GAMEPLAY" before trusting any soak number. "The script can't get through it" and "a player can't" are different claims.
Why: mismatched settings can desync a script while a human plays fine, giving a false failure.
History: docs/rules-history/test-harness-mechanics.md#incursion-worktree-ab-needs-live-options-dat.

## character-fixtures-load-dont-generate
LOAD a character, do NOT generate one: `INCURSION_LOAD=<name>` names `tools/fixtures/chars/<name>.char`, a committed text file of creation choices (the path form `tools/fixtures/chars/<name>.char` means the same). `tools/fixture_cache.sh <name>` builds and caches the `.sav` under `logs/fixture-cache/`; it is a build product, never committed. A state reached after creation belongs to the check: put it in `tools/keys/setup-<fixture>.keys`. An old `.sav` lives in `tools/fixtures/specimens/` only for a map-reading check that waits for inc-9s4u0 or for a save-format test; never rebuild one. Add a fixture per `tools/fixtures/README.md`; add a creation decision with `tools/fill_chars.sh`. Verify: `tools/check_fixture_build.sh`. Trap: a built fixture stands at the end of creation on today's level, so a check that needs a map or a post-creation state must make it itself.
Why: a key-script character's identity shifts under any module change, and a frozen `.sav` is tied to the save format and to its map; a `.char` rebuilt through creation's own functions has neither tie.
History: docs/rules-history/test-harness-mechanics.md#character-fixtures-load-dont-generate. Beads inc-1fjk (the .sav system), inc-10v7f (the .char system).

## probe-hooks-stay-if-a-repro-needs-them
Do NOT propose deleting `INCURSION_STACK_PROBE`, `INCURSION_GOWITH_PROBE`, `INCURSION_FALL_CHAIN`, `INCURSION_FALL_CHAIN_SKIP` — stays as long as a committed repro needs it (`tools/check_probe_hooks.sh` enforces). If reported HELD, keep the serving bead id (inc-x9i or inc-upw.15) as the LAST `inc-` id in the 40 lines above its `getenv`.
Why: deleting a hook a committed repro still calls breaks that repro silently.
History: docs/rules-history/test-harness-mechanics.md#probe-hooks-stay-if-a-repro-needs-them.

## prose-only-fixes-need-no-observation
A fix changing ONLY description text with no in-play value moved is tier Traced, needs NO gameplay oracle (grep guard + rebuild suffices). Exception: NOT prose-only if the text is a functional token (format-string escape, `$"symbol"` reference, anything the parser reads as behaviour) — test: would reverting change engine runtime behaviour? Still required: `upstream:` mark if applicable, `docs/REPORTING-GATE.md` ledger row, a structural grep check.
Why: a text-only change with no behavioural surface can't be measured by playing.
History: docs/rules-history/test-harness-mechanics.md#prose-only-fixes-need-no-observation.

## gate-invalid-object-handle-lines-are-our-noise
FIXED. "Registry::Get -- invalid object handle" lines were our own logging noise (`Target::GetThingOrNULL`), not a game defect. `Registry::GetQuiet()` is the silent lookup; `Registry::Get()` adds the log. Guarded by `tools/check_quiet_lookup.sh`/`INCURSION_QUIET_PROBE`.
History: docs/rules-history/test-harness-mechanics.md#gate-invalid-object-handle-lines-are-our-noise.

## layout-divergence-class-is-guarded
inc-dhc CLOSED — caused by comparing heap addresses across launches. Standing alarm: `tools/check_layout_sweep.sh` (needs lldb; `--selftest` needs no build). Red -> reopen inc-dhc with the failing seed. ASan is UNUSABLE on this Mac (deadlocks in its own init) — use UBSan. Build `incursion-probe` fresh or pass `--no-build` knowingly. `DUN_DEPTH` is 10 (`lib/dungeon.irh:17`) — no scripted session reaches depth 11.
History: docs/rules-history/test-harness-mechanics.md#layout-divergence-class-is-guarded.

## creation-uses-point-buy
Every scripted character creation (key script, `.char` fixture, check, probe) MUST take Point Buy at the attribute step (`p`, then spend every point), unless the check explicitly tests perks or attribute rolls. A rolled set carries random perks: a perk can open a prompt the script does not answer (Bonus Feat: Natural Aptitude asks "Choose a skill:"), and the perk rolls draw from the list of all effects, so any added Effect changes them. Prior art: `tools/keys/kit-warrior.keys`.
Why: Point Buy has no roll and no perk, so an added resource cannot change the character a script builds.
History: docs/rules-history/test-harness-mechanics.md#creation-uses-point-buy. Bead inc-xvsam.
