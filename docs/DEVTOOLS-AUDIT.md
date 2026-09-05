<!-- citations: this-port -->

# Dev-tool audit

inc-4pt asked for one thing before anything is moved or deleted: a list of
every instrument in this tree with a verdict on each, so the judgement is not
re-made from scratch in a month. This is that list.

**What this covers.** Steps 1 to 3 of inc-4pt: find every instrument, judge it,
and flag the ones that are actively misleading. Nothing has been moved to
`devtools/` and `src/Dump.cpp` has not been touched. Those are steps 4 and 5 and
they need a decision that is not recorded here.

Three things have been deleted since. Brian decided the first two himself, as
he went through the list item by item: `FLICKER_PROBE` and
`tools/run_probe.sh`. The third, `INCURSION_DEPTH_PROBE`, was deleted on
2026-08-23 by an unattended run working `bd inc-loa.8`, whose whole content is
this document's own recommendation plus the probe's own comment. All three are
recorded in place below.

**Updated 2026-08-20.** The investigations that owned the ACTIVE items have
mostly closed, so those items now carry a status. Nothing further has been moved
or deleted: the verdicts here stay recommendations, and acting on one is still
Brian's call. Instruments added after the audit was written are listed in their
own section at the end.

**The two axes**, both from inc-4pt, and an item must score on both to be worth
keeping:

- **Useful** — did it settle something, or was it built and never used?
- **Expensive to rebuild** — Brian's rule, in his words: *"don't save something
  you can build in 10 minutes"*.

**A third test, which overrides both.** An instrument that answers confidently
about the wrong thing costs more than no instrument. `FLICKER_PROBE` is the
worked example and it is marked accordingly below.

---

## The tree moves. Read this before acting on the list.

Six of the environment-gated probes were added on 2026-08-18, and two source
files gained a seventh **while this audit was being written** — `src/Display.cpp`
and `src/Monster.cpp` were clean at 09:12 and dirty with a new
`INCURSION_OOB_PROBE` by 09:53, from a session running in parallel.

So the list below marked anything introduced in the last 24 hours as **ACTIVE**
and gave it no verdict. Judging a colleague's in-flight instrument as
"discard" is how an audit destroys work. Those items were re-judged on
2026-08-20, once the investigations that owned them had closed. The rule stands
for the next instrument that appears mid-audit. Re-run the dating command before
any move:

```sh
git log --format='%ad %s' --date=short -S<SYMBOL> -- src/ inc/ | tail -1
```

---

## 1. Compile-time probes

None is compiled into any shipped binary; each needs an explicit
`EXTRA_CXXFLAGS=-D<SYMBOL>` build, which is the mechanism `build_macos.sh:23-25`
documents.

| Symbol | Lines | Added | The question it answers | Verdict |
|---|---|---|---|---|
| `DIVERGE_PROBE` | 126 | 2026-08-15 | Counts every random number drawn. Two runs of one seed draw the same numbers in the same order unless something outside the generator changed a decision, so the first differing count is the first place two runs stopped playing the same game. | **KEEP.** Useful: it settled inc-qik, the `TargetSort` pointer comparison, which is one of the four changes sent upstream. Expensive: the idea is subtle and the counter has to sit in the one place every draw passes through. |
| `INCURSION_LAYOUT` (paired) | — | 2026-08-15 | The other half of the same instrument: shifts every heap allocation by a seeded offset so an address-dependent decision splits on demand instead of by luck. | **KEEP**, same reason. `tools/check_layout.sh` already depends on it, so it is no longer optional. |
| `INC6D5_PROBE` | 179 | 2026-08-17 | Names the creature and the code path behind each entry a map audit reports as orphaned. | **KEEP.** Largest of the set and inc-6d5 is still open, so it has not finished its job. |
| `PALETTE_LOG` | 90 | 2026-08-14 | Separates "the game re-applied a palette" from "the game did nothing and the display changed the picture itself" for the whole-screen brighten/dim. | **KEEP, with the limit stated.** It settled which of the two explanations was true. It cannot say anything about a frame the game never presented — the same blind spot that makes `FLICKER_PROBE` dangerous, but here it is not the question being asked. |
| `FLICKER_PROBE` | ~~53~~ | 2026-08-13 | Nominally: what the game was about to present. | **DELETED 2026-08-18 on Brian's decision. It was worse than nothing.** It samples inside libtcod's `actual_rendering()`, so it fires only when the game presents — and the game *not* presenting was the defect it was built for. Its flat 8.99 reading was true and irrelevant. Anyone who finds it will trust it. |

| `PATH_PROBE` | 39 | 2026-08-15 | Counts pathfinding work per call: terrain events, distinct terrains, live cells against the 65,536 cleared, and consider-cache hits against misses. | **KEEP.** It is what showed one line to be 89% of a pathfinding burst. Cheap to re-add in principle, but the counters are placed exactly where they have to be, and getting that wrong gives a confident wrong number. |
| `TARGET_PROBE` | 15 | 2026-08-14 | Names the target type behind every bad handle that reaches the failing branch — the difference between "the code says this could happen" and "this is what happens". | **KEEP.** Fifteen lines, and it settled inc-zmk, the only change this fork has had merged upstream. Cheap to rebuild, but the value of keeping fifteen lines is higher than the cost. |
| `RETARGET_PROBE` | 3 | 2026-08-15 | Three lines beside `TARGET_PROBE`. | **KEEP** with it; separating them is not worth a decision. |
| `INCURSION_OOB_PROBE` | 157 | 2026-08-18 | Names the creature and the code path behind each out-of-bounds map read. | **KEEP, and read its own history first.** It settled the level-builder cause behind the withdrawn `Map::At()` report (inc-upw.37, inc-65j), and the fix shipped in `3208aa7`. Two of its own early readings were wrong in ways that read as measurements: one recorded a call's arguments and was quoted as its effect, the other counted its own out-of-bounds reads into the totals it reported. Both are recorded beside the results. It is the worked example of a probe that was useful *and* produced two false numbers on the way. |

### `FLICKER_PROBE`, and what its deletion touched

It was the only probe the build script mentioned. `build_macos.sh:25` used it as
the worked example for `EXTRA_CXXFLAGS`, so the first instrument a newcomer met
was the one that could not see the thing it was built for -- the same shape as
the AddressSanitizer trap in inc-nha, where the build script recommends a flag
that deadlocks on this machine.

Deleted 2026-08-18. The flicker defect itself closed on 2026-08-14 (`c564e6d`,
inc-4bh), so the probe was finished as well as blind. What went with it:

- `src/Wlibtcod.cpp` -- the 52-line body and its 3-line registration call.
- `build_macos.sh:25` -- the example now names `-DPATH_PROBE`, and says why it
  changed. Verified by building it: `EXTRA_CXXFLAGS=-DPATH_PROBE
  OUT=incursion-path ./build_macos.sh` links.
- `docs/PORT-STATUS.md`, under *Diagnostic instrumentation* -- was a "do not
  reach for this" entry in the list of live diagnostics; now records the deletion
  and points here. That section was rewritten on 2026-08-20, so this reference
  names the heading rather than a line, which is what the line citation used to
  do and no longer could.
- `tools/README.md` -- the lesson paragraph is kept word for word, because the
  lesson outlives the instrument. Only its tense changed.
- The flicker row under *Known open* in `docs/PORT-STATUS.md`, and the
  "Stale `-DFLICKER_PROBE` objects" row under *Ruled out on 2026-08-14*, are
  pre-fix history and were left alone. Rewriting a record of what was
  investigated is worse than a stale tense.

`strings ./incursion | grep -i flicker` now finds only four lines of game prose
about blinking, and no probe symbols -- the same check the "Stale
`-DFLICKER_PROBE` objects" row used to confirm the objects were clean.

## 2. Environment-gated diagnostics

Thirty-five distinct names, re-derived 2026-09-05 from the tree with

```sh
grep -rho 'getenv *( *"[A-Za-z_0-9]*"' src/ inc/ | sort -u | wc -l
```

Run it and it prints the number; without `sort -u` the same grep prints 43,
which is call sites and not names. The figure was *Twenty-eight, counted
2026-08-20*, and the command beside it stopped at the `grep`, so it printed no
number and nobody could tell the count had moved. Three names arrived after
that date (`INCURSION_HANDLE_BASE`, `INCURSION_RIDER_PROBE`,
`INCURSION_STAIR_WARN_PROBE`) and `INCURSION_DEPTH_PROBE` left on 2026-08-23,
which was 28 + 3 - 1 = 30. Six more have arrived since -- `INCURSION_ARMOUR_PROBE`,
`INCURSION_DEQU_FORCE_SAVE`, `INCURSION_LIGHT_PROBE`, `INCURSION_PAD_HELP`,
`INCURSION_V1_RAW`, and `SteamGameId`, which is Steam's own variable rather than
ours (`src/Wlibtcod.cpp:808`) -- and `INCURSION_DESCEND_PROBE` left in `ccf91de`,
which is 30 + 6 - 1 = 35.

`getenv` costs nothing when the variable is unset, so unlike the compile-time
probes these ship in every binary. That is the reason to be stricter about the
ones that are finished.

**Infrastructure, not dev tools. These stay exactly where they are.**

| Name | Why it is not a candidate |
|---|---|
| `INCURSIONPATH`, `INCURSIONLIBPATH`, `INCURSIONFONTPATH` | The game's own directory overrides. `tools/app_launcher.c` drives the release through `INCURSIONPATH`, and `tools/headless.sh` depends on it. Removing any of them breaks the shipped bundle. |
| `INCURSION_SEED` | Determinism. Every measurement in this project rests on it. |
| `INCURSION_MAX_KEYS` | The headless key budget. |
| `INCURSION_MAP_AUDIT` | Armed by `headless.sh` on every run and reported in its summary. A feature now, not a probe. |
| `STRING_QUEUE_SIZE` | A `-D` override, not a `getenv`. `tools/check_strqueue.sh` builds against it. |

**Finished, self-marked for deletion, and now deleted.**

| Name | Added | Verdict |
|---|---|---|
| `INCURSION_DEPTH_PROBE` | 2026-08-17 | **DELETED 2026-08-23 (inc-loa.8).** Its own comment said *"Delete once inc-x9i is settled"*. inc-x9i closed on 2026-08-19, fixed in `a8f298a`, and `INCURSION_STACK_PROBE` rather than this one carried the before/after evidence. What went with it: the `getenv` block and its 21-line comment in `Map::Generate`, and the `probeStairsDown` local that existed only to feed it. The generator is unchanged — `tools/headless.sh tools/keys/dive.keys` on seeds 2, 3, 4, 5, 6 and 7 gave byte-identical screen dumps before and after, and all twelve runs reached gameplay. The readings it made are kept in `docs/evidence/inc-x9i/README.md`. |

**Candidates with a verdict.**

| Name | Added | The question it answers | Verdict |
|---|---|---|---|
| `INCURSION_SAVE_PROBE` | 2026-08-13 | Records the player's map position on both sides of the save/load boundary. Tells apart "never written" from "written and not read back". | **KEEP.** It settled the save-corruption defect that made every loaded character die at (0,0). Small, and the placement on both sides of the boundary is the whole trick. |
| `INCURSION_CHAR_PROBE` | 2026-08-14 | Writes a readable character sheet beside every save. | **KEEP.** See the correction below: it does *not* compete with `src/Dump.cpp`. |
| `INCURSION_MAP_PROBE` | 2026-08-13 | Counts remembered against unseen glyphs per draw. | **KEEP.** Ten lines, and it is the only thing that distinguishes "the map is wrong" from "the map is right and the drawing is wrong". |
| `INCURSION_ERROR_PROMPT` | — | Makes `Error()` stop and wait instead of logging and continuing. | **KEEP.** A developer convenience with no cost, and the modal-freeze defect it was written around is in `docs/FIXED.md`. |

**Was ACTIVE on 2026-08-18. Status re-taken 2026-08-20.**

The crash and chasm investigations these belonged to have closed. None has been
moved or deleted.

| Name | What it did | Status |
|---|---|---|
| `INCURSION_STACK_PROBE` | Logged nested entries into depth changes, with the nesting level and map depth. | **KEEP.** It carried the before/after for inc-x9i: seed 3362, exit 139 to exit 0, with the same nested bottom-level entry on both runs, which is what proved the branch was entered and not avoided. That is the whole shape this document asks for. |
| `INCURSION_FOLLOWER_PROBE`, `INCURSION_GOWITH_PROBE` | Follower loss across a level change. | **KEEP.** They measured the follower loss properly after the first count was withdrawn — and the withdrawal was caused by five runs sharing one directory, not by the probes. |
| `INCURSION_FALL_CHAIN`, `INCURSION_FALL_CHAIN_SKIP`, `INCURSION_CHASM_WALK`, `INCURSION_LEVITATE_CHASM` | The chasm and falling routes into `MoveDepth`. | **KEEP for now.** They are how the four routes into the bottom-of-dungeon crash were each shown to be reachable without a debugger. Cheap, and the routes are still the ones anyone re-testing that fix would use. |
| `INCURSION_DUNGEONMAP_PROBE`, `INCURSION_DESCEND_PROBE` | Dungeon and descent structure. | **CANDIDATE for deletion.** Neither is cited in the evidence that closed inc-x9i. Confirm against `bd show inc-x9i` before removing either. `INCURSION_DESCEND_PROBE` has since gone, in `ccf91de`; `INCURSION_DUNGEONMAP_PROBE` is still in the tree at `src/Feature.cpp:1563`. |
| `INC6D5_PROBE_NAMES` | Names the creatures `INC6D5_PROBE` follows. | **KEEP** with `INC6D5_PROBE`. inc-6d5 is still open. |

## Added after this audit was written

The instruments below arrived with the fixes of 2026-08-19 and 2026-08-20. Each
was built to drive one check, which is the pattern this document argues for: an
instrument whose only consumer is a committed check cannot quietly rot into a
confident wrong number, because the check fails when it does.

| Name | The question it answers | Its check |
|---|---|---|
| `INCURSION_TARGET_PROBE` | Which candidate did each target-cursor press land on? | `tools/check_target_order.sh` |
| `INCURSION_STAIR_PROBE` | What was the staircase candidate list, and how was it ranked? | `tools/check_stair_cycle.sh` |
| `INCURSION_DOOR_PROBE` | What did `Door::SetImage` do to this door's flags, and what geometry did it read? | `tools/check_broken_door.sh` |
| `INCURSION_QUIET_PROBE` | Did this handle lookup speak, and should it have? | `tools/check_quiet_lookup.sh` |
| `INCURSION_HANDLE_BASE` | Does a defect appear only once an object handle stops fitting in sixteen bits? It starts the handle counter at a chosen number instead of at 128 (`src/Registry.cpp:250-272`), so a one-second session reaches a state that otherwise needs an evening of play. | `tools/check_menu_value.sh` |
| `INCURSION_SAVE_FAIL_AT` | Not a probe but a fault injector: it stages a save failure at a chosen point, throwing exactly what a short write throws, and fires once per process. It exists because a real full disk cannot reach the case the design turns on — both write loops write into memory and the disk is untouched until the commit. | `tools/check_save_fail.sh` |

`INCURSION_SAVE_FAIL_AT` is the one to look at twice. A fault injector ships in
every binary the same way a `getenv` probe does, and it changes behaviour rather
than only observing it. It is gated, it fires once, and it throws the same error
the real failure throws — but it belongs on any list of things that must never
be reachable by accident.

### Correction: `src/Dump.cpp` and `INCURSION_CHAR_PROBE` do not compete

An earlier draft of this audit said one of the two should survive and the other
should go. That was written before either was read properly, and it is wrong.
Acting on it would have removed a capability.

- `INCURSION_CHAR_PROBE` (`src/Registry.cpp:1109-1116`, eight lines) hooks
  `Game::SaveGame`. It fires automatically, needs no one to remember it, and
  describes only the save just written, overwriting the last report.
- `src/Dump.cpp` (268 lines, `-dump`, bd inc-loa.1) loads *any* existing save
  read-only, with no play at all, and adds current HP, position, depth,
  equipped slots and each object's own stati and raw ids.

Neither is a superset of the other in access, so both stay.

**What the audit did miss.** `src/Dump.cpp` compiles into every binary the
project builds, but until 2026-08-18 only `src/Wposix.cpp:556` parsed `-dump`.
The shipped graphical release therefore carried the save decoder and could not
reach it — `nm -C incursion | grep RunSaveDump` found the symbol at
`T RunSaveDump(char const*)` with no caller in that backend.

Brian's decision was to wire it up rather than remove it, since the code was
already paying its full cost in the release. `src/Wlibtcod.cpp`'s `main()` now
parses `-dump` the same way and for the same stated reason as the posix
backend: `TextTerm::RunOnCommandLine` caps an option value at 49 characters
(`src/TextTerm.cpp:39`), which silently truncates a real save path.

Observed, both sides. With the parse in place both binaries dump the same save
to a byte-identical report and `tools/check_dump_save.sh` prints *"Both backends
were checked and their reports are identical."* With the parse commented out and
the binary rebuilt, the same check exits 1 with *"./incursion could not run
-dump"* — the graphical build falls through to normal startup and looks for a
font. This is a port addition, not an upstream defect, so it carries no
`upstream:` mark.

## 3. Scripts under tools/

`tools/README.md` already carries the full file table with a LIVE / BUILD
INFRASTRUCTURE / SUPERSEDED status on every row, so it is not repeated here.
What that table does not answer is the `devtools/` question, and the boundary
inc-4pt asks to draw explicitly is this:

- **Stays in `tools/`** — anything the release pipeline or a gate invokes:
  `package_macos.sh`, `package_macos_app.sh`, `app_launcher.c`,
  `setup_notary.sh`, `check_app.sh`, `check_package.sh`, `gate_record.sh`,
  `gate_compare.sh`, `gate_lib.sh`, `headless.sh`, `soak.sh`, and every
  `check_*` script. These are build infrastructure. Moving them breaks a
  pipeline that expects a path.
- **Would move to `devtools/`** — the flicker family
  (`flickercapture.sh`, `flickerscan.py`, `flickerthumbs.py`,
  `flickerscan_selftest.py`), `sweep_ptr_order.sh` and `sweep_ptr_order.py`,
  and `craft_corrupt_saves.py`.
  Note the trap: `flickerscan_selftest.py` is a check on a diagnostic, and
  `craft_corrupt_saves.py` is *called by* `check_load_corrupt.sh`, so moving it
  means editing that check. Neither is free.
- **Already marked SUPERSEDED** — `run_probe.sh` and `flickerscan.sh`.
  `run_probe.sh` was **deleted 2026-08-18** on Brian's decision: its own header
  said it should have gone once its bug was fixed, the bug is fixed
  (`src/AbiCheck.cpp:11` now guards it at compile time), `play.sh` does
  everything it did and more, and nothing invoked it. `flickerscan.sh` is still
  present and is item 3 of this walkthrough.

## 4. What this audit did not do

- Nothing moved. Three deletions so far: `FLICKER_PROBE` and
  `tools/run_probe.sh`, both on Brian's explicit decision, and
  `INCURSION_DEPTH_PROBE` on 2026-08-23 under `bd inc-loa.8`. Nothing else has
  been removed.
- `src/Dump.cpp` — settled 2026-08-18. See the section below.
- No `devtools/README.md` was written. That is step 6 and it describes a
  directory that does not exist yet.
- The verdicts above are recommendations. Acting on them means editing files
  that a parallel session is writing to, which is why they stop here.
