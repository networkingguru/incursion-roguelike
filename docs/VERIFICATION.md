# Verification

This project uses local, deterministic verification instead of hosted CI. This
page states the rule, names the tools that carry it out, and says what the method
cannot prove. The short public form is in `README.md` under "For developers".

## The rule

Every change that alters behaviour follows five steps, in this order.

1. **Add or update one check.** It defends the new behaviour and nothing else.
   Put it in `tools/` as `check_<subject>.sh`, and give it a header that says
   which defect it defends.
2. **Prove it goes red.** Mutate the fix, or the check's own oracle, rebuild, and
   watch the check fail. A check that has never failed has never been tested.
   Record what you mutated and what the failing run printed.
3. **Rebuild every target the change reaches.** `./build_macos.sh` and
   `BACKEND=posix ./build_macos.sh` are separate `main()`s. A change can break
   one while the other compiles.
4. **Run the check and the gate.** `tools/nightly_verify.sh --compare`.
5. **Record it.** The commands, the mutation and the result go in the commit body
   or in the bead the commit names.

Step 2 is the step that gets skipped, and it is the step that matters. Steps 1,
3, 4 and 5 prove that a check passes. Only step 2 proves the check is measuring
anything.

## The tools

`tools/headless.sh` plays one key script with no display and no keyboard, inside
its own directory under `logs/runs/`, with its own `save/` and `logs/` and with
`mod/` and `lib/` symlinked in. Everything that plays the game calls it. Never
run the binary directly: a bare run reads and can write the owner's real `save/`.

`INCURSION_SEED` pins the run, so two runs of one seed play the same game. Every
measurement in this project rests on that.

`tools/soak.sh` runs many seeds and groups the complaints by message rather than
by session.

The gate is three files. `tools/gate_lib.sh` reduces a finished soak directory to
a few numbers. `tools/gate_record.sh` writes those numbers to a committed
`tools/gates/<script>.baseline`. `tools/gate_compare.sh` re-runs the recorded
seeds and fails on a message the baseline never saw — but only when it appears in
several sessions at once, because the engine is not fully deterministic and a
gate that cries wolf gets switched off. `tools/check_gate.sh` proves the gate
still bites, by feeding it made-up logs.

The gate measures error volume and message-set membership. Screen dumps and
crashing-seed identity were both tried and both failed: screens diverge from the
first changed decision onward, so a gate built on them goes red on every correct
fix.

`tools/nightly_verify.sh` is the wrapper. `--record` freezes what already fails.
`--compare` re-measures and reports what this work broke. It exits 0 for safe to
merge, 1 for broke something or failed to build, 2 for could not measure.

`tools/README.md` §7 groups every check into five tiers, by whether it needs a
clean clone, a compiler, a POSIX build, a built artefact or a recorded baseline.
It also names the two checks you must not run casually:
`tools/check_abs_path.sh`, which moves the live `Options.Dat` aside and runs the
real game from the repo root; and `tools/gate_record.sh`, which overwrites a
committed baseline.

## Rules the harness enforces on itself

**No gameplay is not a pass.** A run that never entered a map exits `NO GAMEPLAY`
rather than passing. That rule exists because a measurement once passed on two
runs that both did nothing.

**A ratchet, not a clean sweep.** `nightly_verify.sh` compares against a base
recorded before the work started. A check that already failed is not this
change's fault. A check that passed before and fails after stops the merge. The
builds are exempt from the ratchet: a tree that does not compile is never safe.

**Checks prove themselves on demand.** `--selftest` exists on
`check_upstream_marks.sh`, `check_api_arity.py`, `check_headless.sh`,
`check_citations.sh`, `check_escape_sweep.sh`, `check_lz_uncompress.sh` and
`flickerscan_selftest.py`. Run it when you change the checker. A check that has
quietly stopped checking anything looks exactly like a check that passes.

## What this cannot prove

Git records results, not process. The tree at a commit shows that a check exists.
It cannot show which commands ran, whether the check was mutated, or whether the
gate was run. That is why step 5 exists: the commit body is the only record of
the process, and it is a claim by the author, not a machine's attestation.

A reader who does not trust the claim can re-run it. The seeds are pinned, the
options are pinned, the key scripts are committed, and the checks are in the
tree. That is the substitute this project offers for a green badge.

The method also does not cover what no check defends. `tools/README.md` §9 lists
the known gaps in the directory.
