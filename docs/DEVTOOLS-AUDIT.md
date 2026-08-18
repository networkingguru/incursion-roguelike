# Dev-tool audit

inc-4pt asked for one thing before anything is moved or deleted: a list of
every instrument in this tree with a verdict on each, so the judgement is not
re-made from scratch in a month. This is that list.

**What this covers.** Steps 1 to 3 of inc-4pt: find every instrument, judge it,
and flag the ones that are actively misleading. Nothing has been moved to
`devtools/` and `src/Dump.cpp` has not been touched. Those are steps 4 and 5 and
they need a decision that is not recorded here.

Two things have been deleted since, each on Brian's explicit decision as he went
through the list item by item: `FLICKER_PROBE` and `tools/run_probe.sh`. Both
are recorded in place below.

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

So the list below marks anything introduced in the last 24 hours as **ACTIVE**
and gives it no verdict. Judging a colleague's in-flight instrument as
"discard" is how an audit destroys work. Re-run the dating command before any
move:

```sh
git log --format='%ad %s' --date=short -S<SYMBOL> -- src/ inc/ | tail -1
```

---

## 1. Compile-time probes

Nine symbols, 672 guarded lines. None is compiled into any shipped binary; each
needs an explicit `EXTRA_CXXFLAGS=-D<SYMBOL>` build, which is the mechanism
`build_macos.sh:23-25` documents.

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
| `INCURSION_OOB_PROBE` | 157 | uncommitted | — | **ACTIVE.** Appeared in the working tree during this audit. No verdict. |

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
- `docs/PORT-STATUS.md:288` -- was a "do not reach for this" entry in the list of
  live diagnostics; now records the deletion and points here.
- `tools/README.md` -- the lesson paragraph is kept word for word, because the
  lesson outlives the instrument. Only its tense changed.
- `docs/PORT-STATUS.md:180` and `:71` are pre-fix history and were left alone.
  Rewriting a record of what was investigated is worse than a stale tense.

`strings ./incursion | grep -i flicker` now finds only four lines of game prose
about blinking, and no probe symbols -- the same check `docs/PORT-STATUS.md:71`
used to confirm the objects were clean.

## 2. Environment-gated diagnostics

Twenty-four names. `getenv` costs nothing when the variable is unset, so unlike
the compile-time probes these ship in every binary. That is the reason to be
stricter about the ones that are finished.

**Infrastructure, not dev tools. These stay exactly where they are.**

| Name | Why it is not a candidate |
|---|---|
| `INCURSIONPATH`, `INCURSIONLIBPATH`, `INCURSIONFONTPATH` | The game's own directory overrides. `tools/app_launcher.c` drives the release through `INCURSIONPATH`, and `tools/headless.sh` depends on it. Removing any of them breaks the shipped bundle. |
| `INCURSION_SEED` | Determinism. Every measurement in this project rests on it. |
| `INCURSION_MAX_KEYS` | The headless key budget. |
| `INCURSION_MAP_AUDIT` | Armed by `headless.sh` on every run and reported in its summary. A feature now, not a probe. |
| `STRING_QUEUE_SIZE` | A `-D` override, not a `getenv`. `tools/check_strqueue.sh` builds against it. |

**Finished, and self-marked for deletion.**

| Name | Added | Verdict |
|---|---|---|
| `INCURSION_DEPTH_PROBE` | 2026-08-17 | Its own comment says *"Delete once inc-x9i is settled"*. inc-x9i is still open (P1) and is the parallel session's current work. **HOLD** — the instruction is clear, the condition is not met. |

**Candidates with a verdict.**

| Name | Added | The question it answers | Verdict |
|---|---|---|---|
| `INCURSION_SAVE_PROBE` | 2026-08-13 | Records the player's map position on both sides of the save/load boundary. Tells apart "never written" from "written and not read back". | **KEEP.** It settled the save-corruption defect that made every loaded character die at (0,0). Small, and the placement on both sides of the boundary is the whole trick. |
| `INCURSION_CHAR_PROBE` | 2026-08-14 | Writes a readable character sheet beside every save. | **KEEP.** See the correction below: it does *not* compete with `src/Dump.cpp`. |
| `INCURSION_MAP_PROBE` | 2026-08-13 | Counts remembered against unseen glyphs per draw. | **KEEP.** Ten lines, and it is the only thing that distinguishes "the map is wrong" from "the map is right and the drawing is wrong". |
| `INCURSION_ERROR_PROMPT` | — | Makes `Error()` stop and wait instead of logging and continuing. | **KEEP.** A developer convenience with no cost, and the modal-freeze defect it was written around is in `docs/FIXED.md`. |

**ACTIVE — introduced 2026-08-17 or 2026-08-18, no verdict given.**

`INCURSION_STACK_PROBE`, `INCURSION_FOLLOWER_PROBE`, `INCURSION_GOWITH_PROBE`,
`INCURSION_FALL_CHAIN`, `INCURSION_FALL_CHAIN_SKIP`, `INCURSION_CHASM_WALK`,
`INCURSION_LEVITATE_CHASM`, `INCURSION_DUNGEONMAP_PROBE`,
`INCURSION_DESCEND_PROBE`, `INC6D5_PROBE_NAMES`.

All belong to the crash and chasm investigations that are open right now.

### Correction: `src/Dump.cpp` and `INCURSION_CHAR_PROBE` do not compete

An earlier draft of this audit said one of the two should survive and the other
should go. That was written before either was read properly, and it is wrong.
Acting on it would have removed a capability.

- `INCURSION_CHAR_PROBE` (`src/Registry.cpp:841-848`, eight lines) hooks
  `Game::SaveGame`. It fires automatically, needs no one to remember it, and
  describes only the save just written, overwriting the last report.
- `src/Dump.cpp` (268 lines, `-dump`, bd inc-loa.1) loads *any* existing save
  read-only, with no play at all, and adds current HP, position, depth,
  equipped slots and each object's own stati and raw ids.

Neither is a superset of the other in access, so both stay.

**What the audit did miss.** `src/Dump.cpp` compiles into every binary the
project builds, but until 2026-08-18 only `src/Wposix.cpp:538` parsed `-dump`.
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

`tools/README.md` already carries the full 41-file table with a LIVE / BUILD
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

- Nothing moved. Two deletions so far, both on Brian's explicit decision:
  `FLICKER_PROBE` and `tools/run_probe.sh`. Nothing else has been removed.
- `src/Dump.cpp` — settled 2026-08-18. See the section below.
- No `devtools/README.md` was written. That is step 6 and it describes a
  directory that does not exist yet.
- The verdicts above are recommendations. Acting on them means editing files
  that a parallel session is writing to, which is why they stop here.
