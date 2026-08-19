**Incursion runs natively on the Mac.** Download `Incursion-macOS-arm64.dmg`
below, open it, drag **Incursion.app** to Applications, and double-click. No
right-click, no security override, no dependencies.

Incursion is one of the deepest roguelikes ever written — a real D&D 3.5 ruleset
with feats, classes, prestige paths and a combat model that rewards knowing the
rules. It has only ever run on Windows. This is it running natively on the Mac.

## Install

Saves, options and logs live in `~/Library/Application Support/Incursion/`.
Deleting the app leaves them; delete that folder too for a clean sweep.

**Requires macOS on Apple Silicon.** Intel and Linux builds are next.

## What's in this one

- **It runs on a Mac at all.** Four defects in the base code had to be fixed
  before a POSIX build would even link.
- **Saves survive updates.** Compatibility is now keyed on a digest of the real
  data layout instead of a version number. Previously any version change made
  every character silently disappear from the load menu.
- **Racial feats are actually granted.** Eight feats across six races were never
  reaching players — a Dragonkin never had Mantis Leap, a dwarf never had
  Loadbearer.
- **Bare-handed monks are no longer punished.** Two empty hands gave one attack
  per swing while two weapons gave two, so a monk was better off holding
  nunchaku than using his fists. Now matches the 3.5 rules.
- Roughly 1,100 unattended self-play sessions behind it, with each fix verified
  against a control run.

The full engineering record, including a claim that had to be retracted, is in
[docs/FIXED.md](https://github.com/networkingguru/incursion-roguelike/blob/master/docs/FIXED.md).

## About that first broken download — fixed 17 Aug 2026

Y'all, making shit for Mac is hard. I thought I had this licked by signing the
thing, but nope, Apple has POLICIES and they must be FOLLOWED. It is sorted now,
and the file on this page is the rebuilt one. For the details, here is what my
handy IT Oompa-Loompa had to say:

> The first image was correctly signed and notarised and still refused to launch,
> because it shipped a bare executable in a folder. Gatekeeper cannot approve a
> bare executable — it answers "the code is valid but does not seem to be an app" —
> and a notarisation ticket can only attach to a disk image, an installer or an
> app bundle, never to a loose binary. So nothing carried an approval that applied
> to the game itself.
>
> It is now an app bundle with its own stapled ticket, which means it keeps working
> after you drag it out of the image. Verified on a second Mac, downloaded and
> quarantined the way you will get it, not just built locally — that distinction is
> exactly what hid the bug.

## Known limits

- Apple Silicon only for now.
- This is a fork of a 0.6.9 codebase and inherits its open defects. It is not a
  finished game and never claimed to be.
