# Evidence for inc-x9i

`Player::MoveDepth` dereferences `RES(BELOW_DUNGEON)` without a zero check, on
the down path only. The up path four lines earlier guards the identical case.
Falling through a chasm on the deepest level of a dungeon reaches it, because
nothing below exists and the constant is 0.

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

### `depthprobe-seed3362.log`

One line per generated level: its depth, the dungeon's declared depth, the count
of squares whose terrain carries `TF_FALL`, and the number of down-stairs the
generator was asked to place.

```
gen depth=10 dun_depth=10 fall_squares=282 stairs_down=0
```

The bottom level has 282 squares a player can fall through and no way down. Only
`$"chasm"` carries `TF_FALL`, so the count is chasm squares exactly.

## Why the author's own guard does not prevent this

`src/MakeLev.cpp:1452` (upstream numbering) reads *"No chasms on the last
dungeon level, because there is nowhere to fall to!"* and the test below it does
exactly that. It is in the **streamer** picker, and so is the `MIN_CHASM_DEPTH`
test at `:1449`.

Chasm floor also arrives as an ordinary **room**. The room picker at `:2398`
applies neither rule; it gates only on the region's own `Depth`. Two shipped
regions are chasm-floored — `"Twisting Chasm"` (`lib/dungeon.irh:3497`,
`Depth: 2`) and `"Floating Rock;1"` (`:3660`, `Depth: 3`) — neither is
`RF_NOGEN`, and no dungeon defines a `ROOM_WEIGHTS` list, so `Resource::GetList`
falls through to its default (`src/Annot.cpp:365`) and puts every `RF_ROOM`
region into every dungeon's pool.

Measured across 7 seeded sessions and 51 generated levels: chasm squares appear
on levels 1 through 4 routinely, and on depth 10 in both sessions that reached
it (282 and 16 squares). Down-stairs stop at level 9, which `:1879` intends.

## Relationship to inc-upw.15 and PR #43

Seed 3362 is the crash that PR #43's original description could not explain: it
segfaulted identically with and without that patch's `static` removal, and wrote
no `errors.log`. This is why. `Error()` never runs because nothing detects the
condition, so the empty log pointed the first diagnosis at memory corruption
that was never there. The follower array is unrelated to this fault.
