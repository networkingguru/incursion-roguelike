# inc-wcf — the false unsafe-terrain warning on every descent

Brian pressed `>` on an ordinary down staircase on 2026-08-21 and the game
answered *"The stair leads to Dungeon Wall. Confirm unsafe action?"*. The
staircase led nowhere near a wall.

## What is in this directory

| File | What it shows |
|---|---|
| `save-portals.txt` | The fixture. `tools/dump_save.sh` on Brian's save: the character stands at (74,70) on depth 2, and a "down stairs" portal sits on that exact square, 0 steps away. |
| `prefix-descend-screen.txt` | The defect, on the build before the fix. The screen dumped one keystroke after `>`, with the prompt on it and the status line still reading `020m`. |
| `check-before.txt` | `tools/check_stair_warn.sh` against that build: FAIL, twice — the prompt appeared, and the character never left depth 2. |
| `check-after.txt` | The same check against the build carrying the fix: PASS, the character arrives on depth 3 (`030m`), and the probe records that the arrival square was refused and nobody was asked anything. |

Both builds differ in one file, `src/Feature.cpp`.

## Why the message was wrong, and not merely noisy

`Portal::Enter` read the player's own coordinates off the NEW map and named the
terrain there. `Player::MoveDepth` then refused that square, because it is
solid, and re-rolled a random open one — which is what it does for every
out-of-bounds, solid or vault square. A player therefore cannot arrive in a
wall, and a warning naming a wall cannot be true. The single terrain that makes
the message frightening is the one terrain that proves it false.

The prompt also fired on every descent, whatever the terrain, because the test
that decided whether the square was unsafe at all — the terrain's own
`EV_MON_CONSIDER` event — was commented out on the line directly above it
(rmtew, a731043, 2014-07-15). Nothing replaced it.

## The fixture is not in the repository

`Furious_Fox.sav` is Brian's own character and 900KB of binary. It lives at
`/Users/brianhill/Scripts/incursion-repro-stairwall/Furious_Fox.sav`, sha1
`b868277dbf5a78b016685367012d8c558d03905a`, and `tools/check_stair_warn.sh`
takes `INCURSION_WCF_SAVE` if it moves. Without it the check is INCONCLUSIVE
and never a pass.

### Converted to v1 on 2026-09-07 (bd inc-0idm)

The file above is a v0 save: bare rID numbers, no manifest. The first legal
resource append after it was captured (b369eb2, 2026-08-25) shifted every rID
it reads, so the check went red with the file's sha1 unchanged. Measured by
compiling the module from lib/ at three commits: before the append the check
passes, at the append it fails, at HEAD it fails further.

The check now runs `Furious_Fox.v1.sav`, sha1
`87ef129a953f0a57ed43acbc2388b57a0cc7d044`, in the same directory. It was
made with `incursion-headless -convert` on a copy of the v0 file, against a
module compiled from lib/ as of b932018 (the commit before b369eb2, the last
module that reads the v0 numbering correctly). Against today's module the
converted file restores the same world the 2026-08-21 dump records: The
Goblin Caves, the down staircase at (74,70), the descent to 030m. The v0
file stays beside it as provenance and is no longer opened by the check.
