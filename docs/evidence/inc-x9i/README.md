# Evidence for inc-x9i

`Player::MoveDepth` dereferences `RES(BELOW_DUNGEON)` without a zero check, on
the down path only. The up path reads its constant thirteen lines
earlier and tests it (`Feature.cpp:873-875` against `:886`, upstream numbering). Falling through a chasm
on the deepest level of a dungeon reaches it, because nothing below exists and
the constant is 0.

Captured 2026-08-17 on macOS 15 (arm64), from `incursion-headless` built at
`b6cf76f` plus two temporary probes.

## Reproduce

```
BACKEND=posix ./build_macos.sh
INCURSION_STACK_PROBE=1 INCURSION_DEPTH_PROBE=1 \
    tools/headless.sh tools/keys/dive.keys 3362
```

The session exits 139. It is deterministic; it has been reproduced twice from a
clean run directory.

## Files

### `crash-seed3362.ips`

The macOS crash report. The parts that matter:

```
"type": "EXC_BAD_ACCESS", "signal": "SIGSEGV",
"subtype": "KERN_INVALID_ADDRESS at 0x0000000000000000"

Player::MoveDepth(short, bool)              <- faults
Creature::TerrainEffects()
Thing::PlaceAt(Map*, short, short, bool)
Player::MoveDepth(short, bool)
Player::WizardOptions()
```

Address zero is `RES(0)`. `Game::Get` returns NULL for a zero id
(`src/Res.cpp:312`), and the branch reads `RES(mID)->Type` with no test.

The two `Player::MoveDepth` frames are the re-entry: the outer call moved the
player to depth 10, `PlaceAt` fired the arrival square's terrain, the square was
chasm, and `TerrainEffects` called `MoveDepth(11)`.

### `stackprobe-seed3362.log`

One line per entry to `Player::MoveDepth`. The final line is the crash:

```
MoveDepth nest=2 map_depth=10 frame=0x16d394460 per_level=2416
```

`nest=2` is a call entered while another was still open. `map_depth=10` is the
level the player stood on, the bottom of The Goblin Caves. Nothing is logged
after it.

`per_level` is the distance from the frame of the call above, so it is the cost
of one level descended. **2416 includes 16 bytes contributed by the probe
itself** — a build carrying the probe allocates `sub sp, sp, #0x240` where the
shipping build allocates `#0x230`. The shipping figure is 2400 bytes per level.
Lines with `nest=1` show `per_level=0`, which is not a measurement: there is no
open frame above to measure against.

### `depthprobe-seed3362.log` and `depthprobe-8seeds.log`

One line per generated level: its depth, the dungeon's declared depth, the count
of squares whose terrain carries `TF_FALL`, and the number of down-stairs the
generator was asked to place.

```
gen depth=10 dun_depth=10 fall_squares=282 stairs_down=0
```

The bottom level has 282 squares a player can fall through and no way down. Only
`$"chasm"` carries `TF_FALL`, so the count is chasm squares exactly.

`depthprobe-8seeds.log` is the wider run: seeds 3362, 4242, 111, 555, 777, 888,
999 and 1234, **each in its own run directory** (see inc-uh0 — runs that start in
the same second otherwise share a directory and their logs merge). 60 generated
levels:

| depth | levels generated | levels with chasm | down-stairs |
|---|---|---|---|
| 1 | 8 | 3 | 4 |
| 2 | 8 | 2 | 4 |
| 3 | 8 | 6 | 4 |
| 4 | 7 | 5 | 4 |
| 5 | 7 | 2 | 4 |
| 6 | 6 | 4 | 4 |
| 7 | 6 | 6 | 4 |
| 8 | 4 | 4 | 4 |
| 9 | 3 | 2 | 4 |
| 10 | 3 | **3** | **0** |

Every session that reached the bottom level found chasm there — 16, 282 and 21
squares — and on each the generator was asked for no down-stairs
(`stairs_down=0`). Sixteen of the 31
generated levels shallower than `MIN_CHASM_DEPTH` (5) carry chasm as well.

## Why the author's own guard does not prevent this

`src/MakeLev.cpp:1452` (upstream numbering) reads *"No chasms on the last
dungeon level, because there is nowhere to fall to!"* and the test below it does
exactly that. It is in the **streamer** picker, and so is the `MIN_CHASM_DEPTH`
test at `:1449`.

Chasm floor also arrives as an ordinary **room**. The room picker at
`src/MakeLev.cpp:2397-2404` applies neither rule; its gates are `RoomTypes`, then `DepthCR`
against the region's own `Depth`, then `MIN_VAULT_DEPTH`, then `RF_CORRIDOR`,
then a scan of what has already been used on this level.
Three shipped regions place chasm — `"Twisting Chasm"` (`lib/dungeon.irh:3497`,
`Depth: 2`), whose `Floor:` is `$"chasm"`; `"Floating Rock;1"` (`:3660`,
`Depth: 3`), whose floor is obsidian but whose grid tiles `'X'` to `$"chasm"`;
and `"Jagged Chasm"` (`:3644`), which sets `* BLOB_WITH $"chasm"` and declares
no `Depth:` at all, so that gate passes for it at every level. None is
`RF_NOGEN`, and no dungeon defines a `ROOM_WEIGHTS` list, so `Resource::GetList`
falls through to its default (`src/Annot.cpp:365`) and puts every `RF_ROOM`
region that is not `RF_NOGEN` into every dungeon's pool (`:371-372`).

Measured across 8 seeded sessions and 60 generated levels, one run directory
each: chasm appears on 16 of the 31 levels generated shallower than `MIN_CHASM_DEPTH`,
and on the bottom level in all three sessions that reached it. Down-stairs stop
at level 9, which the `Depth < Con[DUN_DEPTH]` gate at `src/MakeLev.cpp:1878`
intends. An earlier version of this file said "7 sessions and 51 levels"; those
runs shared directories (inc-uh0) and the totals were unreliable.

## Challenge difficulty really does make the dungeon 15 deep

Measured 2026-08-18. `Annot.cpp:468-470` returns 15 for `DUN_DEPTH` on an
annotated resource once difficulty reaches `DIFF_CHALLENGE`. That is a source
reading; this is the run.

`OPT_DIFFICULTY` is byte 117 of `Options.Dat`. The shipped file here holds 2
(`DIFF_BASELINE`). Copy it, set byte 117 to 3, and point the harness at the
copy:

```
INCURSION_OPTIONS=<copy> INCURSION_DEPTH_PROBE=1 \
    tools/headless.sh tools/keys/dive.keys 3362
```

`depthprobe-challenge-seed3362.log` reports `dun_depth=15` on every generated
level, and levels 11, 12, 13 and 14 generate -- depths the same script cannot
reach at baseline, because wizard Ascend/Descend refuses any depth above
`DUN_DEPTH` (`Debug.cpp:804-808`). At baseline the same script stops at 10.

The session ran out of keys before it asked for 15, so the deepest level in the
log is 14. The figure that matters is `dun_depth=15`, which the game reports at
run time on every line.

## Other ways chasm reaches the bottom level

Generated chasm is measured above. Two more routes are read from the source and
not yet observed:

- **Trapdoor traps.** `"small trapdoor trap"` (`lib/threats.irh:799`) and
  `"large trapdoor trap"` (`:1085`) are `EA_TERRAFORM` effects with
  `xval: TERRA_FLOOR; rval: $"chasm"`, flagged `EF_MUNDANE`. They turn real
  floor into real chasm. The generator places traps itself, picking a random
  `AI_TRAP` effect for the level's `DepthCR` (`src/MakeLev.cpp:2171` and
  `:2184`, upstream numbering), so a trapdoor trap can be sitting on the bottom
  level from the moment it is generated. Tracked as inc-8b8.
- **Scripted `MoveDepth`.** Every scripted call runs with `safe=false`, because
  the script API takes one parameter (`inc/Api.h:226`) and the binding passes
  one (`lib/dispatch.h:680`). `lib/religion.irh:2992-2993` moves the player as
  deep as 10. Tracked as inc-3i3.

Hallucinatory Terrain does **not** belong on this list. It sets perceived
terrain, and `Creature::TerrainEffects` re-points at the real terrain for an
illusory square (`src/Move.cpp:1303-1305`) before testing `TF_FALL` at `:1348`.

## Relationship to inc-upw.15 and PR #43

Seed 3362 is the crash that PR #43's original description could not explain: it
segfaulted identically with and without that patch's `static` removal, and wrote
no `errors.log`. This is why. `Error()` never runs because nothing detects the
condition, so the empty log pointed the first diagnosis at memory corruption
that was never there. The follower array is unrelated to this fault.
