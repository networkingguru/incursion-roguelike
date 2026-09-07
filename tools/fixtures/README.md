# Dated options fixtures

These 900-byte files preserve the settings that scripted checks originally ran
against. Each is the exact `Options.Dat` blob from the named repository commit:

| Fixture | Source commit | Contents |
|---|---|---|
| `options-2026-08-13.dat` | `41df62b` | The settings present on 2026-08-13. |
| `options-2026-08-18.dat` | `2f58be3` | The 2026-08-13 settings plus the 21-byte character-generation profile described below. |
| `options-2026-08-22.dat` | `2092592` | The 2026-08-18 settings with `OPT_AUTOOPEN` changed from 0 to 2. |

The 21 changed bytes in the 2026-08-18 fixture include `OPT_BEGINKIT` and
`OPT_REROLL` enabled, `OPT_MAX_HP` and `OPT_MAX_MANA` set to 2,
`OPT_ELUDE_DEATH` set to 3, `OPT_GENDER` set to 2, and `OPT_SUBRACES` enabled.
These are historical harness inputs, not recommended player defaults.

A fixture is frozen. If a check needs different settings, add a new fixture
with its own provenance and date; never edit an existing fixture.
