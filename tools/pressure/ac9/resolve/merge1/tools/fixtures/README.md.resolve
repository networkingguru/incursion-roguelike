| `options-2026-08-22-descroom-no.dat` | n/a (derived 2026-10-08) | `options-2026-08-22.dat` with byte 407 (`OPT_DESC_ROOM`, Show Room Descriptions) changed from 2 (NEW) to 0 (NO). `tools/check_first_seen_region_live.sh` route 1 (inc-pu6v.138) uses it. |
| `options-2026-08-22-maxhp.dat` | n/a (derived) | `options-2026-08-22.dat` with `OPT_MON_MAX_HP` (108) forced from 0 to 3 (DOUBLE), so a summoned monster has fixed hit points. `tools/check_dequ_reach.sh` and the specimen `orc-warrior-dequ-seed5-maxhp` use it (bead inc-drr0). |
@@@ next hunk
A fixture has two reasons to be regenerated: a save-format change, and position
drift, where resource positions moved and the save no longer loads. The second
is automatic. `tools/headless.sh` rebuilds the fixture from that command,
records its name in `logs/fixture-rebuilds.log`, and `tools/finish_bead.sh`
commits the rebuilt files with the bead (bead inc-zto3q).
`tools/check_fixtures_load.sh` loads every fixture at landing. Any other load
refusal exits 8 with `FIXTURE LOAD FAILED` and rebuilds nothing.

**A regeneration is always a real git diff, and the bytes are not the oracle.**
The same name, key script, seed, settings and binary, run three times on
2026-09-12, gave `.sav` files whose sha256 began `2b5fb59c`, `603f109b` and
`94c4c2a8`, and `tools/check_char_fixture.sh` passed on each: same name, race,
class and Strength. A save carries clocks and counters that no second run
repeats. Judge a regeneration by what the sheet says, never by the size of the
diff.

### Setup scripts
