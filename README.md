# iNCURSION

Julian Mensch's D&D 3.5 roguelike, running natively on the Mac.

Incursion is one of the deepest roguelikes ever written — a real 3.5 ruleset with
feats, classes, prestige paths, spell schools and a tactical combat model that
rewards knowing the rules. It has only ever run on Windows. This fork brings it
to macOS, and it is meant to be played, not built.

![iNCURSION release 1 running on macOS](docs/media/incursion-macos.png)

---

## Get it

Download the disk image from
[Releases](https://github.com/networkingguru/incursion-roguelike/releases), open
it, and drag the folder anywhere you like. Double-click `incursion` and play.

There is no installer, no dependency to fetch, and no compiler. The image is
signed and notarised by Apple, so it opens without a Gatekeeper warning and
without right-click gymnastics.

**Requires** macOS on Apple Silicon. Intel and Linux builds are coming; see
*What's next*.

Your saves, options and logs live in the folder beside the game, so moving the
folder moves everything, and deleting it leaves nothing behind.

---

## What playing it is like

You roll a character through a long, opinionated creation flow — race, subrace,
class, attributes, alignment, feats, skills, a god — and then you go down into
the Halls of the Goblin King. Combat is turn-based and genuinely tactical:
positioning, attacks of opportunity, two-weapon fighting, spell components and
saving throws all matter, and the game will happily kill you for ignoring them.

Every monster, item, spell and class carries its own written description in the
game, so the ruleset is readable from inside it rather than requiring a manual.

What works today: character creation, exploration, the full combat model, magic,
shops, saving and loading. The game builds its own 82,768-line ruleset into a
data module, so what you are playing is the real thing and not a subset.

**Three ways to run it.** A windowed SDL build (the way to play), a plain
terminal build that needs no graphics at all and works over ssh, and a headless
mode that plays from a script — which is how this fork finds its own bugs.

---

## Why this fork

**It runs on a Mac.** That is the headline, and it took fixing four defects in
the base code before a POSIX build would even link.

**Your saves survive an update.** Save compatibility is keyed on a digest of the
actual data layout rather than on a version number, so shipping a new release
does not hide your characters. Previously any version change made every save
silently vanish from the load menu.

**Your species finally works.** Eight racial feats across six races were never
being granted to players at all — a Dragonkin never had Mantis Leap, a dwarf
never had Loadbearer. They do now.

**Bare-handed monks are no longer punished.** Two empty hands produced one attack
per swing while two weapons produced two, so a monk was better off holding
nunchaku than using his fists. Fixed to match the 3.5 rules.

**It is measurably more stable.** The game plays itself unattended, thousands of
sessions at a time, and each defect that finds is fixed against a control run
rather than against a hunch.

The full engineering record — every defect, how it was verified, and the one
claim that had to be retracted — is in [`docs/FIXED.md`](docs/FIXED.md).

---

## What's next

- **Linux and Steam Deck.** The concrete target. The work that gated it is done.
- **Intel and universal Macs**, so this runs on hardware older than Apple Silicon.
- **Finish the content that is already written.** Incursion ships with a great
  deal that is described but not built: eight races have subrace sections marked
  *(Unimplemented)* in the game's own help, and whole feat trees carry the same
  label. Because every entity's description sits beside its implementation, a
  mismatch between them is a provable bug — which makes this the richest seam in
  the project.
- **Play over ssh**, using the terminal build.
- **More than was shipped** — world mode, new dungeons — but only after the above.

---

## Building from source

You do not need this to play. It is here for people who want to change something.

```
brew install sdl2 pkg-config
./build_macos.sh
./incursion
```

Two minutes from a clean checkout. `BACKEND=posix ./build_macos.sh` builds the
terminal and headless binary instead.

To produce a release image the way one is actually shipped:

```
DMG=yes tools/package_macos.sh
```

That builds twice on purpose — a developer binary to compile the game module,
then a shipping binary without the resource compiler, because the compiler
carries a GPLv2 runtime that must not be distributed. It then bundles SDL2,
signs, notarises and staples the result, and refuses to produce an image that
fails its own checks.

Development notes live in [`docs/PORT-STATUS.md`](docs/PORT-STATUS.md), and work
is tracked in the repository with [Beads](https://github.com/gastownhall/beads)
(`bd ready`).

---

## Windows

The original build still works and is unchanged by this fork. Pre-compiled
dependencies are checked in; `build_sdl2.bat`, `build_libtcod.bat` and
`build_pdcurses.bat` rebuild them if needed, and `build.bat` produces
`IncursionLibtcod.exe` and `IncursionCurses.exe`.

**Why the dependencies are checked in, in Richard Tew's words:** bug fixes to
gameplay require a save game, and a save game only loads in the build that wrote
it. Character creation is varied enough that a player often cannot remember what
they picked, so reproducing a report without their save is a wild goose chase.
Keeping every binary and every source version is what makes an old save
debuggable at all.

---

## Credits

Incursion is **Julian Mensch's** work, with additional concepts and material by
**Westley Weimer**. This fork changes nothing about that.

- **Richard Tew** has maintained it since, and vendored the dependencies that
  make old builds reproducible. His
  [rmtew/incursion-roguelike](https://github.com/rmtew/incursion-roguelike)
  remains the parent project, and defects belonging to the base game are sent
  back there rather than kept here.
- **Kyle Benesch** (HexDecimal) did substantial modernisation work in 2024 —
  standard types, `std::min`/`max`, dead-code removal, CI. A sibling fork worth
  reading before writing anything new.

This release is iNCURSION release 1, forked from rmtew 0.6.9Y19 at commit
`961c54b` (2025-06-28).

## Links

- [Incursion website](http://incursion-roguelike.net)
- [RogueBasin page](http://www.roguebasin.com/index.php?title=Incursion)
- [Bay12 thread](http://bay12forums.com/smf/index.php?topic=139289) — the old
  discussion home

## Licence

See [LICENSE](LICENSE).
