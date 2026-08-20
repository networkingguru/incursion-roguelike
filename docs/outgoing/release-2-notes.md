**Release 2 fixes a crash that kills you at the bottom of the dungeon.** If you
play release 1, update. Download `Incursion-macOS-arm64.dmg` below, open it,
drag **Incursion.app** to Applications, and double-click.

Your existing characters still load. The save format did not change.

## The one that matters

Dig to the deepest level of the dungeon, press `>`, and release 1 dies. No
wizard mode, no weird setup — just the ordinary climb-down. Same thing if you
fall into a chasm on the bottom level, or levitate down. It has been there the
whole time and I never hit it because I never got that deep.

That's fixed, along with two more crashes: a hiding monster that could delete
itself in the middle of casting a spell, and a room-builder that occasionally
put doors inside solid rock.

## Also new

- **The targeting cursor works properly now.** Arrow keys used to score
  candidates on one axis only, so pressing RIGHT would jump past the nearest
  thing to something further away, and you could get stuck in spots where most
  presses did nothing at all. It now steps around a ring of targets by bearing.
- **Shop lists scroll.** They never did. The selection just walked off the
  bottom of the page and stayed there.
- **`<` and `>` work on the overview map**, and send the cursor to the *nearest*
  staircase — ranked by what it actually costs to walk there, so the square it
  picks is the square `R` will really reach. Press again to cycle.
- **Read a save without loading the game.** `Incursion.app/Contents/MacOS/Incursion -dump yoursave.sav`
  prints the full character sheet, inventory and effects to the terminal, then
  exits. Nothing is written; the save is opened read-only.
- **A failed save no longer takes the game with it.** Neither does a file the
  game refuses to load.
- **Natural Weapon Speed**, a new option. Every weapon in the game carries a
  speed rating and natural attacks carried none, so a monk punched slower than
  the nunchaku sitting in his pack. Switched on for new installs; existing
  setups keep the old behaviour until you flip it in the options screen.
- **Twenty prestige-class descriptions are now true.** Each one was a place
  where a class promised something its own script never did — the Twilight
  Huntsman shipped sixty spells that nothing could reach, the Blackguard
  couldn't use a shield, the Master Archer's ranged sneak attack fired with a
  sling.

## Install

Saves, options and logs live in `~/Library/Application Support/Incursion/`.
Deleting the app leaves them; delete that folder too for a clean sweep.

macOS will ask once whether you're sure you want to open an app downloaded from
the Internet. That's normal and it only happens the first time. If you ever see
"unidentified developer" or "modified or damaged", that's a real problem and I
want to hear about it.

**Requires macOS on Apple Silicon.** Intel and Linux are next.

## Known limits

- Apple Silicon only for now.
- This is a fork of a 0.6.9 codebase and inherits its open defects. It is not a
  finished game and never claimed to be.
- Sixty-three issues are closed so far. The full engineering record, including
  the claims that had to be retracted, is in
  [docs/FIXED.md](https://github.com/networkingguru/incursion-roguelike/blob/master/docs/FIXED.md).

---

*These notes were drafted with AI assistance and edited by me before posting.*
