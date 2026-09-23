# Test harness mechanics

## incursion-never-run-the-binary-from-the-repo-root
NEVER run `./incursion` or `./incursion-headless` directly from the repo root — it writes into Brian's real `save/`. Use `tools/headless.sh` (own `save/`/`logs/`, symlinks `mod/`/`lib/`); `--tty` for terminal-drawing tests. Back up `save/` before any experiment that might bypass the harness.
Why: prevents a scripted run from overwriting real saves.
History: docs/rules-history/test-harness-mechanics.md#incursion-never-run-the-binary-from-the-repo-root.

## incursion-one-run-one-directory
Pass a unique `INCURSION_RUN_DIR` for every run in a loop; count run directories and confirm the count equals runs before trusting a per-seed number. `tools/check_headless.sh` assertion 11 is the one case that must NOT pass `INCURSION_RUN_DIR` (tests the shared-default guard).
Why: sessions sharing a run directory merge their logs into what reads as one session.
History: docs/rules-history/test-harness-mechanics.md#incursion-one-run-one-directory.

## incursion-worktree-ab-needs-live-options-dat
A soak/A-B run MUST use a settings file matching the KEY SCRIPT: `tools/gates/Options.Dat` is committed/pinned, `tools/headless.sh` takes `INCURSION_OPTIONS`, `gate_compare.sh` refuses on checksum mismatch. Check for "exit 5, NO GAMEPLAY" before trusting any soak number. "The script can't get through it" and "a player can't" are different claims.
Why: mismatched settings can desync a script while a human plays fine, giving a false failure.
History: docs/rules-history/test-harness-mechanics.md#incursion-worktree-ab-needs-live-options-dat.

## character-fixtures-load-dont-generate
LOAD a character, do NOT generate one: `INCURSION_LOAD=<save file>`. Fixtures in `tools/fixtures/chars/`: `<name>.sav`/`.keys`/`.sheet.txt`. Make/regenerate: `tools/make_char_fixture.sh <name> <keyscript> <seed> <options>`; verify: `tools/check_char_fixture.sh`. Traps: (1) the save is COPIED into the run's sandbox — a fixture handed by path gets rewritten by the run reading it; (2) regenerating gives a byte-different `.sav` for the SAME character — judge by the sheet, never bytes. Don't use a loaded fixture when a check needs a fresh map (a save pins the dungeon too).
Why: an rID is a position, so a key-script character's identity shifts under any module change; a loaded save converts through its own manifest and is immune.
History: docs/rules-history/test-harness-mechanics.md#character-fixtures-load-dont-generate.

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
