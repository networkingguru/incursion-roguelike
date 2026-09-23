# Frozen fixtures

## Dated options fixtures

These 900-byte files preserve the settings that scripted checks originally ran
against. Each is the exact `Options.Dat` blob from the named repository commit:

| Fixture | Source commit | Contents |
|---|---|---|
| `options-2026-08-13.dat` | `41df62b` | The settings present on 2026-08-13. |
| `options-2026-08-18.dat` | `2f58be3` | The 2026-08-13 settings plus the 21-byte character-generation profile described below. |
| `options-2026-08-22.dat` | `2092592` | The 2026-08-18 settings with `OPT_AUTOOPEN` changed from 0 to 2. |
| `options-sneak-invis.dat` | n/a (derived) | `tools/gates/Options.Dat` with `OPT_AUTOHIDE` (518) forced to 0. `tools/check_sneak_invis.sh` uses it: with Automatic Hide in Shadows on, a rogue auto-hides in the dark and every blow counts as an unseen attack even without a spell, which spoils the visible control. |

The 21 changed bytes in the 2026-08-18 fixture include `OPT_BEGINKIT` and
`OPT_REROLL` enabled, `OPT_MAX_HP` and `OPT_MAX_MANA` set to 2,
`OPT_ELUDE_DEATH` set to 3, `OPT_GENDER` set to 2, and `OPT_SUBRACES` enabled.
These are historical harness inputs, not recommended player defaults.

A fixture is frozen. If a check needs different settings, add a new fixture
with its own provenance and date; never edit an existing fixture.

## Character fixtures

`chars/<name>.sav`, `chars/<name>.keys` and `chars/<name>.sheet.txt` are one
fixture, and a `.sav` on its own is not enough. The `.sav` is the frozen
character. The `.keys` is the key script that generated him, copied in, because
a save-format change will one day make remaking every fixture compulsory and the
`.sav` cannot be remade without it. The `.sheet.txt` is the engine's own dump of
the character under a provenance header — seed, settings, key script, commit,
and the sha256 of both the `.sav` and `mod/Incursion.Mod` — so a reader can see
what is in the `.sav` without loading it, and so a check can read its
expectations out of the fixture instead of out of numbers typed into the check.
`tools/make_char_fixture.sh` rewrites the whole sheet on every regeneration, so
the header cannot drift away from the `.sav` beside it.

**Why a character is frozen at all.** A character built by a key script is not
reproducible across module changes. An rID in this engine is a POSITION, so one
resource added to `lib/` shifts every id above it. Measured 2026-09-12: commit
`bef32c3` added one Effect to `lib/m_items.irh`, and the seed-1 Lizardfolk monk
went from STR 18 holding a long sword +3 to STR 14 holding a quarterstaff, on
byte-identical attribute dice. About seventeen checks were red on master that
day, and at least four of them were red from this cause alone. A character LOADED from a save
does not move, because the v1 save schema converts every saved rID through that
save's own per-module manifest (`v1ConvertManifestRid`, `src/SaveV1.cpp`);
measured the same day, byte-identical across the same module change. So a check
that wants a character who stays himself must load one. The defect is bd
`inc-sls0` and this machinery is bd `inc-1fjk`.

**Using one.** `INCURSION_LOAD` names the save, and `tools/headless.sh` starts
the session from that character instead of from the title menu:

```sh
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/lizardfolk-monk-seed1.sav \
    tools/headless.sh tools/keys/load-char-sheet.keys 1
```

A loaded run still MUST name its settings, and it still takes a seed: the
character comes from the file, but the seed pins everything the session does
after the load. `tools/keys/load-char-sheet.keys` builds no character of its
own, so it reads any fixture; run it with no `INCURSION_LOAD` and the game sits
in its title menu and the run reports NO GAMEPLAY.

**The save is COPIED into the run's sandbox, and that is the point.** A loaded
session owns its save file and writes back to it, so a fixture handed to the
game by path would be rewritten by the very run that read it.
`tools/headless.sh` copies the file into the run's own `save/` and passes the
bare name to `-load`, so nothing a session does reaches the path
`INCURSION_LOAD` named. `tools/check_char_fixture.sh` asserts both halves of
that: the fixture is byte-identical after a run that loaded AND saved it, and
the run's sandbox holds its own copy.

**Making one.** `tools/make_char_fixture.sh <name> <keyscript> <seed> <options>`:

| Argument | What it is |
|---|---|
| `name` | What the fixture is called. It becomes `chars/<name>.sav` and its two companions, and also a `-load` argument, so letters, digits, dot, dash and underscore only. |
| `keyscript` | The script that builds the character AND SAVES HIM. It must end with the System Menu's `[b]` Save and Continue — `ESC b` — which is the only save the game offers that does not also end the session. `tools/keys/lizardfolk-monk-save.keys` is the worked example. |
| `seed` | The seed to generate under. Not optional: an unseeded run rolls different attributes, so it would freeze a different character. |
| `options` | A settings file from this directory. Settings change what a seeded session does, so a fixture is only meaningful with the one that made it, and that name goes into the sheet header. |

The script generates the character, copies the `.sav` into place, and then LOADS
that copy back through `tools/headless.sh` to write the sheet. It costs a second
session and buys one guarantee: no fixture is published without having been
loaded once, so a `.sav` that cannot be read back fails there rather than in
somebody else's check a month later.

**Regenerating one.** Add `--force`. Without it the script refuses to touch an
existing fixture, because overwriting one silently retires every check built on
it. The regenerating command is written into the sheet's own header, so a
save-format change years from now is a matter of running what the file already
says.

**A regeneration is always a real git diff, and the bytes are not the oracle.**
The same name, key script, seed, settings and binary, run three times on
2026-09-12, gave `.sav` files whose sha256 began `2b5fb59c`, `603f109b` and
`94c4c2a8`, and `tools/check_char_fixture.sh` passed on each: same name, race,
class and Strength. A save carries clocks and counters that no second run
repeats. Judge a regeneration by what the sheet says, never by the size of the
diff.

**When a fixture stops loading: read the drift message, and look at
`lib/main.irc`.** A fixture that has worked for weeks and suddenly reports
`Error reading saved game (File is Corrupt).` has almost certainly not been
corrupted. A resource was added to the MIDDLE of an array instead of the end,
and the loader refused the save rather than hand back the wrong character. The
engine says so precisely, on stderr, and the run keeps it:

```
incursion: module slot 0 Effect array slid at position 354: the save's manifest
recorded "Endure Cold" there and the loaded module has "Endure Fire" -- a
resource was inserted in the middle of the array, which the append-only rule
forbids
```

`SaveV1_ResolveNames` throws `ECORRUPT` from `v1ManifestDrift`
(`src/SaveV1.cpp`) after the save itself has read cleanly, so the probe log
shows `load: after read` and the failure comes later. Grep the run directory for
`array slid` or `was reordered` before suspecting anything else.

The fix is never to regenerate the fixture. It is to move the new declaration to
the END of `lib/main.irc`, which is the end of parse order and where that file's
own APPEND-ONLY note says new resources go. `4ba035b` is the worked example: it
declared a resource in the middle of `m_items.irh`, pushed 862 Effects down one
place, and a save written before it read its owner's Robe of Blending back as a
Hat of Disguise.

**The end of a lib file is NOT the end of the array.** `lib/main.irc`
`#include`s the lib files in a fixed order and `m_items.irh` sits in the middle
of it, so a resource appended to the bottom of `m_items.irh` still lands around
Effect position 354 of roughly 860. Measured 2026-09-17: appending there made
every character fixture in this directory unloadable, while the same Effect
appended to the end of `lib/main.irc` left all 41 of them loading and their
characters unchanged.

A character fixture is frozen too. If a check needs a different character, add a
new fixture with its own key script and its own name; never edit an existing
one, and never hand-edit a `.sheet.txt`, which would leave it describing a
character the `.sav` beside it does not hold.
