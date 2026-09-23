# Archived full text -- not auto-loaded. The loaded rule lives in .claude/rules/test-harness-mechanics.md.

# Test harness mechanics

## incursion-never-run-the-binary-from-the-repo-root
Never run ./incursion or ./incursion-headless directly from the repo root for a test: the game writes save/<name>.sav and appends to save/gallery.dat in whatever directory it resolves as its own, so a scripted throwaway character lands beside Brian's real saves. This happened on 2026-08-14 (Ulgen.sav plus a modified gallery.dat, both restored from a backup). Use tools/headless.sh, which sandboxes each session under logs/runs with its own save/ and logs/ and symlinks mod/ and lib/ in. To test terminal drawing use tools/headless.sh --tty, which runs the same sandbox under a pseudo-terminal. Back up save/ before any experiment that might bypass the harness.

## incursion-one-run-one-directory
GIVE EVERY HEADLESS RUN ITS OWN DIRECTORY, or the log lies.

FIXED 2026-08-19 (inc-uh0, commit 472adaa). tools/headless.sh:89 and tools/dump_save.sh:74 now name the run directory <stamp>-<pid>-<script>, so the DEFAULT name is unique per process. Before that the name came from a clock that resolves to the second, and two sessions started inside one second shared one directory, one save/, one logs/ and one append-mode probe log. The merged log then read as a single long session. That is how the first inc-90u follower count came out wrong: five runs, one directory, four lines, and the published figure had to be withdrawn.

THE RULE STILL HOLDS ANYWAY. Pass a unique INCURSION_RUN_DIR for every run in a loop, then count the run directories and confirm the count equals the number of runs before you believe any per-seed number. A pid does not say what the run was for; a name you chose does. tools/soak.sh:59 and every multi-session check already do this.

THE GUARD. tools/check_headless.sh assertion 11 starts two sessions at once with NO INCURSION_RUN_DIR and fails if they report one path. It is the only assertion there that must not pass INCURSION_RUN_DIR, because the defect lived in the default name. It was proved red against the old naming before it was trusted.

## incursion-worktree-ab-needs-live-options-dat
A soak or A/B run must be given a settings file that matches the KEY SCRIPT, or it measures nothing. As of 2026-08-16 the gate does this properly: tools/gates/Options.Dat is committed and pinned, tools/headless.sh takes INCURSION_OPTIONS, and gate_compare.sh refuses when the baseline's checksum disagrees. See inc-w43, fixed.

THE SIGNATURE OF A VACUOUS SESSION: 'exit 5, NO GAMEPLAY'. Always check that before trusting any soak number. This produced a false PASS on 2026-08-14 that was written into commit b3b5351 as proof a fix worked, and it reproduced across 500 sessions on 2026-08-15 before being caught.

CORRECTION 2026-08-16, and the earlier version of this memory was wrong about the cause. It said the committed Options.Dat means 'character generation never completes'. It does not. Proved by running dive.keys seed 1 against the committed file and reading the screens: the committed settings ask 'Is this character male or female? [mf]', a prompt Brian's own settings skip. tools/keys/chargen.keys chooses by fixed menu letters, so one extra prompt slides every later keystroke out of step and the run never reaches a map.

So it is a HARNESS DESYNC, not a broken game. A human creating a character with the committed file is fine. That matters for shipping: the committed Options.Dat is safe to package with a release, and I nearly recorded it as a blocker.

The general lesson is the same one as [[incursion-check-for-a-live-instance]]: 'the script cannot get through it' and 'a player cannot get through it' are different claims, and only one of them was tested.

## character-fixtures-load-dont-generate
LOAD A CHARACTER, DO NOT GENERATE ONE. tools/headless.sh takes INCURSION_LOAD=<save file> and starts the session from that character instead of the title menu. Frozen characters live in tools/fixtures/chars/ as three files: <name>.sav, <name>.keys (what generated it) and <name>.sheet.txt (the sheet, so a reader can audit the blob). Make or regenerate one with tools/make_char_fixture.sh <name> <keyscript> <seed> <options>. tools/check_char_fixture.sh proves a fixture still loads as the character it claims; it is 'gate: live'. Built 2026-09-12 under bd inc-1fjk.

WHY, and this is the part that matters: a character BUILT by a key script is not reproducible across module changes. An rID in this engine is a POSITION, so one resource added to lib/ shifts every id above it. Measured: bef32c3 added one Effect to lib/m_items.irh and the seed-1 Lizardfolk monk went from STR 18 with a long sword +3 to STR 14 with a quarterstaff, on byte-IDENTICAL attribute dice. Four monk checks went red from that alone. A LOADED character is protected, because the v1 save schema converts each saved rID through that save's own manifest (v1ConvertManifestRid, src/SaveV1.cpp); measured byte-identical across the same module change. The defect bead is inc-sls0.

TWO TRAPS. (1) The save is COPIED into the run's sandbox, because a loaded session writes back to its own save file -- a fixture handed over by path gets rewritten by the run that read it. (2) Regenerating a fixture gives a byte-DIFFERENT .sav holding the SAME character, because a save carries clocks and counters no second run repeats. Judge a regeneration by the sheet, never by the bytes.

WHEN NOT TO USE IT: a save pins the DUNGEON as well as the character, so a check that needs a fresh map cannot use one.

## probe-hooks-stay-if-a-repro-needs-them
STANDING RULE, Brian, 2026-09-07 (inc-loa.25), and he asked never to be shown it again: a probe/env hook STAYS as long as a committed reproduce command needs it. Do not propose deleting INCURSION_STACK_PROBE, INCURSION_GOWITH_PROBE, INCURSION_FALL_CHAIN or INCURSION_FALL_CHAIN_SKIP. It is enforced, not remembered: tools/check_probe_hooks.sh cited_by() searches docs/REPORTING-GATE.md and docs/evidence for the hook name and classifies it IN USE. If you ever see these four reported HELD again, the cause is the bead attribution -- bead_for takes the LAST inc- id in the 40 lines above the getenv, so any comment you add near one MUST leave the serving bead (inc-x9i or inc-upw.15) as the last id, or the hook reclassifies as 'serving an open bead' and relapses when that bead closes.

## prose-only-fixes-need-no-observation
PURELY PROSE FIXES NEED NO GAMEPLAY OBSERVATION. Brian's rule, 2026-08-28, during the inc-tek.8.x prose-vs-script rule triage. A fix that changes ONLY human-readable description text (a Desc string, a help paragraph, a message's wording) and moves NO in-play value is graded tier Traced and requires NO gameplay oracle -- the grep guard + module rebuild is sufficient evidence, because there is nothing behavioural to observe. Examples already done this way: F1 was NOT prose-only (it moved the heal dice, so it got a check but a gameplay number was attempted); F2 Flame Strike Desc 1d8->1d6 IS prose-only (script d6 stays, SRD-correct) so no observation. THE ONE EXCEPTION: it is not 'purely prose' if the edited text is really a functional token -- a missing escape (e.g. an unescaped %% in a format string), or a $"symbol"/resource-name reference, or anything the parser or engine reads as behaviour. Those can change what the game does and still need the normal red-green + observation treatment. Test: if reverting the edit could change a single thing the engine does at runtime, it is NOT prose-only. Still required for every prose-only fix: the upstream: mark (if upstream's), the docs/REPORTING-GATE.md ledger row (marked prose-only, no in-play value moves), and a structural grep check as the mutation guard. See [[feedback-claude-dispatches-never-writes-code]] and the F48 Horn-of-the-Sewers prose-only precedent (commit ef90f99).

## gate-invalid-object-handle-lines-are-our-noise
FIXED 2026-08-20 (inc-upw.39). The 'Registry::Get -- invalid object handle' lines in the 40-seed gate were OURS, not a game defect, and are now gone.

Source was Target::GetThingOrNULL, src/Target.cpp. Commit f4ef5cb (the inc-upw.13 type-check fix) needs the object itself to test its type, so it replaced 'if (theRegistry->Exists(h)) return oCreature(h);' with a bare 'theRegistry->Get(h)'. Exists() answers 'no' in silence; Get() prints the message first. Both return NULL. Behaviour unchanged, noise added.

A dead handle there is NORMAL: a target keeps the handle of whatever the monster was interested in, nothing clears it when that thing dies, and TargetSystem::Retarget just rebuilds the list later.

THE FIX IS NOT Exists()-then-Get(). That is correct but slow: both walk the same hash chain, and inc/Defines.h records upstream profiling Registry::Get as the second-hottest function in the game (they spent 480KB widening the table for it), while GetThingOrNULL runs inside a qsort comparator. Instead Registry::Get was SPLIT: Registry::GetQuiet() is the lookup, Registry::Get() is GetQuiet() plus the complaint. GetThingOrNULL calls GetQuiet. Same single walk, no log line, type check intact.

Guarded by tools/check_quiet_lookup.sh, driven by INCURSION_QUIET_PROBE and Registry::QuietProbe() at the top of Game::Play(). It asserts Get and GetQuiet agree on a live handle, that GetQuiet logs nothing for a dead one, and that Get logs it exactly once. Verified red in both directions.

Two general lessons. (1) tools/headless.sh already writes a call stack on a message's FIRST occurrence, and soak directories survive under logs/gate/ -- grep those before proposing a bisect. That turned a 19-commit bisect into one grep. (2) A guard that is silent and a guard that logs are not interchangeable, even when they return the same value; swapping one for the other is a visible change to every log-based gate.

## layout-divergence-class-is-guarded
inc-dhc (same seed, different game) is CLOSED as of 2026-09-08. It was never uninitialised contents: the engine compared two heap ADDRESSES and the allocator moved objects each launch. Two sites fixed: 2f0100b (monster target list sorted by memory position) and 949f73b (fall charged to whichever creature Creature::TerrainEffects' three globals still named).

THE STANDING ALARM IS tools/check_layout_sweep.sh. It runs in tools/nightly_verify.sh with the BUILDS, not in the ratchet, because it builds the DIVERGE_PROBE binary and needs lldb. Exit 0/1/2; no lldb means skip, not fail. --selftest proves all three verdicts in seconds with no build. If it goes red, reopen inc-dhc with the failing seed.

TRAPS THAT COST TIME HERE:
- AddressSanitizer is UNUSABLE on this Mac (deadlocks in its own initialiser, macOS 26.5.2 arm64). UBSan works. Do not retry ASan.
- A STALE incursion-probe lies. It is not rebuilt by build_macos.sh's normal path, so always build it or pass --no-build knowingly.
- Key scripts differ 200x in how much game they buy: explore.keys ~38,000 turns, marathon.keys ~10,800, dive.keys 198-6,714 (it stalls after about key 219, inc-loa.2). dive12.keys is a prefix of dive.keys and adds nothing. Keep a long script in any sweep.
- No scripted session reaches depth 11. DUN_DEPTH is 10 (lib/dungeon.irh:17), src/Debug.cpp:805-808 refuses more. inc-dhc's 'depth 12' was the depth the script ASKED for.
