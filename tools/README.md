# tools/ — what is here and which parts matter

This directory holds the unattended-testing harness for the macOS/Linux port of
Incursion. Read this page before you run anything in it.

**A few files carry almost all of the value.** Learn these and you can ignore the
rest until you need them.

| File | Why it matters |
|---|---|
| `headless.sh` | Runs one scripted game session in a sandbox. Everything else that plays the game calls it. |
| `check_headless.sh` | The regression check for that harness. If this fails, no other measurement means anything. |
| `soak.sh` | Runs many sandboxed sessions over many seeds and groups what they complained about. |
| `gate_record.sh` + `gate_compare.sh` + `gate_lib.sh` | The regression gate. `gate_record.sh` freezes a build's behaviour into `tools/gates/*.baseline`; `gate_compare.sh` re-runs the same seeds and says what got worse. |
| `package_macos_app.sh` + `check_app.sh` | Builds `Incursion.app` and then verifies that a stranger who downloads it can open it. |

Every claim on this page cites a file and a line. Check the citation before you
trust the sentence. About a third of this project's older citations have rotted.

---

## 1. Build first

Two build lines exist. They differ only in the terminal backend, and only one
backend can be linked at a time, because each defines `main()`, `Error()` and
`Fatal()` (`build_macos.sh:31-32`).

```sh
./build_macos.sh                 # -> ./incursion           the SDL/libtcod game
BACKEND=posix ./build_macos.sh   # -> ./incursion-headless  the POSIX/ncurses build
```

`build_macos.sh:36` defaults `BACKEND` to `libtcod`; `:39` maps that to
`OUT=incursion` and `:40` maps `posix` to `OUT=incursion-headless`. Either line
also writes `mod/Incursion.Mod` when that file is absent (`build_macos.sh:189-199`),
because both builds carry the resource compiler by default.

The `posix` build compiles `src/Wposix.cpp` and links `-lz -lncurses`
(`build_macos.sh:108-117`). ncurses ships with macOS and with every Linux
distribution, so it adds nothing to install, and it draws only to a real
terminal — a headless run never calls into it
(`build_macos.sh:114-116`). The `libtcod` build links SDL2 and OpenGL instead
(`build_macos.sh:119-124`), and needs `sdl2` and `pkg-config` from Homebrew.

**The harness needs the second line.** `headless.sh:75` defaults its binary to
`./incursion-headless`, and `:78-81` refuses to run without it, printing that
exact build command. `soak.sh:33-35`, `check_race_feats.sh:23-26` and
`check_load_corrupt.sh:47-48` all say the same.

Requirements: Xcode command line tools, plus `sdl2` and `pkg-config` from
Homebrew (`build_macos.sh:4-5`). The POSIX build needs neither SDL nor libtcod
(`build_macos.sh:34-35`).

---

## 2. How the pieces fit

`headless.sh` is the harness. It plays one session of a key script from
`tools/keys/` inside its own directory under `logs/runs/`, with its own `save/`
and `logs/`, and with `mod/` and `lib/` symlinked in (`headless.sh:7-10`). It
exists so that an unattended run cannot destroy a real character. Use it and
never the binary directly (`headless.sh:48-51`).

`soak.sh` calls `headless.sh` once per seed, several at a time, and reports the
errors grouped by message rather than by session (`soak.sh:19-21`).

The gate trio measures one build against another. `gate_lib.sh` reduces a
finished soak directory to a few numbers. `gate_record.sh` writes those numbers
to `tools/gates/<script>.baseline`, a committed file. `gate_compare.sh` re-runs
the recorded seeds and fails on a message the baseline never saw, but only when
it appears in SEVERAL sessions at once; one or two sessions is printed and not
failed, because the engine is not fully deterministic and a gate that cries wolf
gets switched off (`gate_compare.sh:10-33`). The chosen metric is error volume and message-set
membership, because screen dumps and crashing-seed identity were both tried and
both failed (`gate_lib.sh:5-19`).

The `check_*` scripts are the regression checks. Each defends one defect or one
property that was lost by accident at least once.

Some game state cannot be walked to. Wizard mode is how a key script reaches
it: send lowercase `w`, answer `y`, and the wizard menu is a plain `LMenu`
whose letters a script can select. Two things about that menu bite. Its
letters run `a`..`z` then `A`..`Z` in the order `Player::WizardOptions` adds
them (`src/Debug.cpp`), so adding an option renumbers everything after it —
dump the menu and read the letter rather than counting. And `w`, not `W`: an
uppercase token sets SHIFT, and both key tables bind `KY_CMD_WIZMODE` with
modifier flags of 0, so `W` is a different keystroke that reaches nothing
(`src/Wposix.cpp` `TokenToKey`, `src/Tables.cpp:4641`/`4761`).

`[M] Create Altar` is there for the harness. A sacrifice needs the player to
be standing on an altar, and the only other source of one is `MakeLev`'s
random assignment (`src/MakeLev.cpp:2107-2123`), which picks from seven gods
and cannot be asked for a particular one. The command prompts for a god name
and builds the feature exactly as `MakeLev.cpp:1143-1145` does.
`check_sacrifice.sh` is the first thing to use it.

Everything else is a diagnostic, a packaging step, or superseded.

---

## 3. Glossary of what the harness prints

`headless.sh` prints a fixed report after every session. The words are not
self-explanatory.

**`ended: NO GAMEPLAY`** — the run never entered a map, so it measured nothing.
`Game::Play` writes `logs/session.log` on the first completed turn, so that file
exists if and only if the session reached gameplay (`headless.sh:149-151`). When
it is missing and the run would otherwise have exited 0 or 3, `headless.sh:174-178`
rewrites the exit code to 5. Do not count such a run as a pass. Screens are not
a substitute test: `@dump` lines fire even in a session that never entered a map,
and one vacuous run left 11 of them (`headless.sh:168-170`).

**`ended: WATCHDOG`** — exit 4. The game stopped asking for keystrokes, which is
the signature of a hang (`headless.sh:32-33`). `SIGALRM` fires in
`src/Wposix.cpp:471-479`, which writes `incursion: watchdog timeout, no key read
in time` and exits with `EXIT_OUT_OF_TIME`, defined as 4 at `src/Wposix.cpp:84`.
The alarm is 300 seconds (`src/Wposix.cpp:79`) and it measures the GAP between
keystrokes, not the length of the run, so a long honest session is safe
(`src/Wposix.cpp:1593-1597`). It is never armed when a person is at the keyboard
(`src/Wposix.cpp:576-580`).

**`death: STUCK`** — the run ended with `Die? [yn]` still on the last screen,
unanswered (`headless.sh:245-249`). The pinned settings run with `OPT_NODEATH`
on, so a killing blow asks that question instead of ending the game, and a key
script answers it blind with whatever token comes next
(`headless.sh:214-217`). If no `y` or `n` remains in the script, every later
keystroke is swallowed and the run still reports `ended: cleanly`
(`headless.sh:224-230`). A confirmed death prints `death: N confirmed` instead
and is logged to `logs/death.log`. Neither gets its own exit code, on purpose:
whether a death should fail a run is a product decision the script does not make
(`headless.sh:37-42`).

**`stuck-prompt: threat-disengage`** — the run ended with `You are in a
threatened area. Abort, Flee or Disengage?` still on screen
(`headless.sh:268-271`). That prompt has no option gate at all and fires
whenever a player-controlled creature moves away from a hostile creature that
perceives it (`src/Move.cpp:841`, quoted at `headless.sh:254-257`).
`tools/keys/dive.keys` contains none of `a`, `f`, `d`, `?` or ESC, so once the
prompt fires the rest of the script is swallowed. Measured on 7 of 40 seeds
(`headless.sh:263-265`).

**`map audit: armed, no inconsistencies found`** — the audit ran and found
nothing. `src/MapAudit.cpp:64` writes an `=== map audit armed ... ===` header
whenever the audit is on, so the log carries a line even on a clean run. That is
what lets `headless.sh:296-297` tell "clean" apart from "never ran". A missing
log is reported three different ways depending on why (`headless.sh:288-295`),
because merging them is the exact defect this code used to have.

---

## 4. Traps that have already produced a false measurement

**Trap 1 — every script resolves the repo root itself.** The idiom is
`ROOT="$(cd "$(dirname "$0")/.." && pwd)"` followed by `cd "$ROOT"`
(`headless.sh:45-46`, `soak.sh:24-25`, `gate_record.sh:17-18`,
`check_headless.sh:38-39`, and most other scripts here). So you may call any of
them from any working directory, and the path arguments they take are relative
to the REPO ROOT, not to where you are standing. `gate_lib.sh:43` uses `BASH_SOURCE` instead
because it is sourced, not executed.

**Trap 2 — `headless.sh` copies the LIVE `Options.Dat` unless you say
otherwise.** `headless.sh:107` defaults `INCURSION_OPTIONS` to `$ROOT/Options.Dat`
and `headless.sh:112` copies it into the session. The default is deliberate: a session with
no options file never finishes character generation, which produced two false
passes on 2026-08-14 (`headless.sh:94-96`). But the live file is whatever the
owner last played with, and the game rewrites it every session. Settings change
the game. On 2026-08-15 the same binary, seed and key script gave different
screens either side of a rewrite, and the gate's finding count moved 4386 to
4416 with no code change (`headless.sh:98-101`, `gate_lib.sh:31-41`).

This matters more than it sounds, because the key scripts choose menu items by
FIXED LETTERS. One extra prompt slides every later keystroke out of step. Two
seeds died exactly that way when a god offered a domain prompt the stream had no
answer for (`tools/keys/chargen-priest.keys:12-16`). Anything that compares one
run against another MUST pass `INCURSION_OPTIONS`. The gate pins
`tools/gates/Options.Dat` and records its checksum in the baseline
(`gate_lib.sh:43-44`, `gate_record.sh:28-34`). A file you name and cannot have is
an error, never a silent fall back to the live one (`headless.sh:105-111`).

**Trap 3 — the map audit is ON by default and it is expensive.**
`headless.sh:119` sets `INCURSION_MAP_AUDIT` to 1 unless you override it. A
sample of a headless run on 2026-08-15 put 75 percent of the run inside
`AuditMap`, so a session with the audit on measures the audit and not the game
(`headless.sh:114-118`). **Anything timing the engine MUST set
`INCURSION_MAP_AUDIT=0`. Anything hunting defects MUST leave it on.**

**Trap 4 — a key script longer than the budget stops early and exits 3, and
that looks like a short run rather than a failure.** The budget is
`DEFAULT_MAX_KEYS 20000` (`src/Wposix.cpp:78`, applied at `:171`). It counts keys
READ, one per `GetChar` call (`src/Wposix.cpp:1590`), and when it runs out
the game dumps a screen named `maxkeys` and exits with `EXIT_OUT_OF_KEYS`, which
is 3. Raise it with `INCURSION_MAX_KEYS` (`src/Wposix.cpp:570-571`).

**Correction, 2026-08-17: `marathon.keys` does NOT need a raised cap, and the
usage line in its own header was wrong.** That header told everyone to run
`INCURSION_MAX_KEYS=60000` and said the file "exceeds" the 20000 default "on
purpose". It does not. Expanding every `TOKEN*N` gives 10500 keystrokes, and the
`chargen.keys` it includes gives 111, so a session reads at most 10611 — about
half the default. The header contradicted itself, because its own line 12 already
said "roughly 10500 keystrokes". The budget has been 20000 since the harness was
added (commit `058ba87`). I corrected the header and left the counting one-liner
in it. Count, do not guess:

```sh
python3 -c "import re,sys; print(sum(int(m.group(2)) if (m:=re.match(r'^(.+?)\*(\d+)$',t)) else 1 for l in open(sys.argv[1]) if not l.lstrip().startswith('@') for t in l.split('#')[0].split() if not t.startswith('@')))" tools/keys/marathon.keys
```

Measured with that line: `marathon.keys` 10500, `explore.keys` 1259,
`dive.keys` 886, `chargen.keys` 111. The `marathon.keys` header also described
`explore.keys` as "about 500" and `dive.keys` as "about 400"; both were low by a
factor of about 2.5, and both are now the measured numbers.

**Trap 5 — two runs started in the same second used to SHARE a run directory.
Fixed; the history is here because the number it corrupted was published.**
`headless.sh:90` now names the default run directory
`logs/runs/$(date +%Y%m%d-%H%M%S)-<pid>-<script>`. The stamp alone resolves to
the SECOND, so before the process id joined it, a loop that started several
sessions inside one second gave them all the same directory, and any probe that
APPENDS to a log wrote into the same file. The result was one directory whose
log read like a single long session, and every per-seed figure drawn from it was
wrong. This produced a false count on 2026-08-17: a 7-session, 51-level survey
figure had to be withdrawn and re-measured at 60 levels over eight isolated
seeds (commit `0b5b59b`, bd `inc-uh0`). `dump_save.sh:74` carried the same
defect and got the same fix. `check_headless.sh` assertion 11 is what stops it
coming back: it starts two sessions at once with no `INCURSION_RUN_DIR` and
fails if they report one path.

**The rule still holds: pass a unique `INCURSION_RUN_DIR` for every run in a
loop, then count the run directories and confirm the count equals the number of
runs before you believe any per-seed number.** A name you chose says what the
run was for, which a pid does not, and the count is the only thing that proves
the runs stayed apart. `soak.sh:59` does this, and so does every check that
drives more than one session (`check_headless.sh:255`, `:278`, `:287`, `:299`,
`:320`; `check_layout.sh:88`; `check_dump_save.sh:46`;
`check_load_corrupt.sh:60`). `check_race_feats.sh:28-29` does NOT — it takes the
timestamped default and parses the `run:` line out of the harness output. That
is now safe in a loop as well, because the default name is unique, but it still
tells you nothing about which run was which.

---

## 5. The depth ceiling: no session reaches depth 11

Wizard mode's `Ascend / Descend Depth` refuses any depth above the dungeon's
`DUN_DEPTH` constant. `src/Debug.cpp:805-808` reads:

```c
if (i < 1 || RES(m->dID)->Type != T_TDUNGEON ||
    i > (int16)TDUN(m->dID)->GetConst(DUN_DEPTH))
{
    IPrint("Invalid depth.");
```

The starting dungeon, The Goblin Caves, declares `DUN_DEPTH 10`
(`lib/dungeon.irh:17`). So depth 10 is the floor of every scripted session, and
every request for 11 or more prints `Invalid depth.` and generates nothing.

Two key-script headers claimed otherwise. Both are now corrected in place.

| Key script | The claim that was false | What is true |
|---|---|---|
| `tools/keys/dive.keys` | "Roughly 45 levels per session, down to depth 25 and back up." | It asks for 36 depth jumps: 2 down to 25, then 24 back up to 2. Only 14 are accepted, and it visits at most 10 distinct levels. |
| `tools/keys/dive12.keys` | "straight down to depth 12, and stop" | It asks for depths 2 to 12. 11 and 12 are refused. It stops at depth 10. |

The other key scripts under `tools/keys/` make no depth claim, and I checked
each one. `find-altar-scout.keys` says only "dive through several levels", which
is true. `explore*.keys`, `chargen*.keys`, `smoke.keys`, `followers.keys`,
`marathon.keys`, `modcheck.keys`, `dragonkin-*.keys` and `find-altar-diag.keys`
name no depth, and neither does any of the `prestige-*`, `sacrifice-*`,
`save-*`, `underdark-*` or single-purpose scripts added since. Re-check with
`grep -il depth tools/keys/`, which names five files: `dive.keys`,
`dive12.keys`, `followers.keys`, `find-altar-scout.keys` and
`find-altar-diag.keys`.

Evidence, tier Observed. A `dive12.keys` run leaves four screen dumps, and their
own status lines settle it:

| Dump | Status line | Depth |
|---|---|---|
| `0001-arrival` | `The Goblin Caves: Entry Chamber    010m` | 1 |
| `0002-depth6` | `The Goblin Caves: Underground River  060m` | 6 |
| `0003-depth12` | `The Goblin Caves: Maze              100m` | **10**, and the top line reads `Invalid depth.` |
| `0004-shutdown` | `The Goblin Caves: Maze              100m` | 10 |

The status line prints ten units per depth, which the first two rows prove
without reading any code. The screen labelled `depth12` is a depth 10 screen
carrying the refusal message. Seen in four independent sandboxes at
`logs/layout/20260817-201245-27731/{a1,a2,b1,b2}/logs/screens/`.
`logs/` is gitignored (`.gitignore:29`), so that path exists only on the machine
that ran it; re-derive it by running `dive12.keys` yourself. Corroboration from
committed history: commit `0b5b59b` reports "all three sessions that reached
depth 10" as the deepest result over eight seeds.

**Consequence.** Anything that sizes a measurement by counting the depth-jump
lines in a key script overcounts by about 2.5 times. Anything looking for a
defect that needs depth 11 or deeper cannot find it with these scripts at all.

---

## 6. Every file in tools/

Not every file here is alive. Statuses: **LIVE** — use it.
**BUILD INFRASTRUCTURE** — part of producing or shipping a binary, not a
diagnostic. **SUPERSEDED** — something else does the job better; kept for
history. **DEAD** — its reason to exist is gone.

No file is marked DEAD today. Nothing marked SUPERSEDED is deleted: marking is
the job, and each still explains an older log or an older commit.

### The harness

| File | The question it answers | Status |
|---|---|---|
| `headless.sh` | What did one scripted session of this build do? | LIVE |
| `soak.sh` | What do N sessions over N seeds complain about? | LIVE |
| `play.sh` | Interactive launcher for a real session, with the map audit, save probe and character probe on. Uses the real `save/`, by design. | LIVE |
| `dump_save.sh` | What is in this `.sav`, without playing the game? Wraps the binary's `-dump` in the same sandbox `headless.sh` uses. Defaults to `./incursion-headless`; `INCURSION_BIN=./incursion` works too since 2026-08-18 and gives a byte-identical report. | LIVE |

`run_probe.sh` was **deleted on 2026-08-18**. Its own header said "Delete this
script once the saved-game position bug is fixed", and that bug is fixed:
`docs/REPORTING-GATE.md:239` records `*((long*)&hm)` destroying the player's
position as a closed fix, and `src/AbiCheck.cpp:11` now gates the type widths it
depended on. It was also redundant — `play.sh` sets the same two probes and more
(`play.sh:41-49`) and prints a report afterwards, which `run_probe.sh` did not.
Nothing invoked it; the only references were documentation. See
`docs/DEVTOOLS-AUDIT.md` for the audit that removed it.

### The regression gate

| File | The question it answers | Status |
|---|---|---|
| `gate_lib.sh` | Sourced, not run. Turns a soak directory into the numbers the gate compares, and pins the settings file. | LIVE |
| `gate_record.sh` | What does this build complain about, recorded as the thing later builds are measured against? | LIVE |
| `gate_compare.sh` | Did anything get worse since the baseline? | LIVE |
| `check_gate.sh` | Does the gate actually bite? Feeds it made-up logs in about a second. | LIVE |

### The regression checks

| File | The question it answers | Status |
|---|---|---|
| `check_headless.sh` | Do the five properties every unattended run depends on still hold? | LIVE |
| `check_abi.sh` | Did any save-format type width move, and does anything cast a handle to a pointer? | LIVE |
| `check_abs_path.sh` | Does the game still resolve `argv[0]` to an absolute path? **Unsafe, see §7.** | LIVE |
| `check_alienist_live.sh` | Does the Alienist's Surreal Presence field exist and speak? A kobold summoned beside her must read "seems unsettled". | LIVE |
| `check_api_arity.py` | Does any script API declaration in `inc/Api.h` bind an argument to the wrong C++ parameter? | LIVE |
| `check_app.sh` | Can a stranger download `Incursion.app` and open it? | LIVE |
| `check_brawl_weapon.sh` | Does a fist still borrow the sword? An elf ranger holds his bow and carries his sword on his back, where the sheet will show both the Brawl and the Melee block, and the Brawl block must name no weapon at all. | LIVE |
| `check_broken_door.sh` | Does a door still lie about being broken? Asserts the one predicate every reader asks, and runs a generated level to prove no door ends it closed and branded broken in a readable doorframe. | LIVE |
| `check_citations.sh` | Does every code citation in an outgoing document resolve in the tree it claims to cite? | LIVE |
| `check_consumable_abort.sh` | Does a consumable survive an action the character refused to complete? Answers yes to the game's own "Stop reading?" offer and asserts the scroll stack did not move, then drinks a potion and asserts that one still goes. Reports a session whose Will save never produced the offer as INCONCLUSIVE. | LIVE |
| `check_dump_save.sh` | Does `-dump` still walk a real save and report the right fields, from BOTH backends? | LIVE |
| `check_earthsinger_live.sh` | Does the Earthsinger admit the rock gnome its own refusal message names? | LIVE |
| `check_error_handling.sh` | Did anyone reintroduce the `Error()` buffer overflow or the modal freeze? | LIVE |
| `check_escape_sweep.sh` | Does any string literal still spell a C escape with a forward slash, the way the port's path sweep wrote `/n` for `\n`? | LIVE |
| `check_hunger_penalty.sh` | Does getting hungrier still make a character stronger? Photographs one Dragonkin fed, Hungry and Starving, and refuses an order in which Hungry costs more than Starving. | LIVE |
| `check_huntsman_live.sh` | Does the Twilight Huntsman reach his own spell list, smite Law rather than Good, and track at the ranger's rate, serving the ranger's opening bonus once rather than twice? | LIVE |
| `check_key_directives.sh` | Do the screen-driven key-script directives `@choose`, `@cursorto`, `@cursorto:mark` and `@expect` reach a menu entry that counting could not? | LIVE |
| `check_ki_strike_live.sh` | Does the module grant a Monk Ki Strike? One session photographs the character sheet's Special Abilities block at 1st level and again at 4th: nothing, then `Ki Strike +1`. Reads a compiled module, so a red run after editing `lib/` usually means `./incursion -compile main.irc` was not run. | LIVE |
| `check_layout.sh` | Does this build play the same game when its objects sit at different addresses? | LIVE |
| `check_load_corrupt.sh` | Does the real binary refuse ten hand-corrupted saves cleanly and still load two genuine ones? | LIVE |
| `check_logrotate.sh` | Does log rotation keep the right archives and prune only names it made itself? | LIVE |
| `check_loremaster_live.sh` | Does the Loremaster's Bibliographic Insight add its extra attribute points when he reads a tome? | LIVE |
| `check_lz_uncompress.sh` | Can the LZ77 and RLE decoders be made to write past their output buffer? | LIVE |
| `check_masterarcher_live.sh` | Does the Master Archer's Ranged Sneak Attack fire only with a long bow or a short bow, and not with every launcher? | LIVE |
| `check_menu_value.sh` | Does a script menu give back the same object handle it was handed, above the 16-bit line? | LIVE |
| `check_natural_speed.sh` | Has the hard-coded brawl-speed floor drifted from the fastest weapon in `lib/weapons.irh`? Reads the data; runs nothing. | LIVE |
| `check_natural_speed_live.sh` | Does flipping one byte of `Options.Dat` really move the Brawl row on the character sheet, 100% to 175%? Refuses to pass if a run never entered a map. | LIVE |
| `check_package.sh` | Is the packaged folder free of ACCENT symbols and Homebrew paths, and does it carry its data? | LIVE |
| `check_prestige_profs.sh` | Does a prestige class grant the weapon and armour proficiencies its own prose promises? | LIVE |
| `check_prestige_tables.sh` | Does each prestige class print the save columns and the defence track its own fields give? | LIVE |
| `check_ptr_sweep.sh` | Does `sweep_ptr_order.sh` still find a pointer ordering, and still ignore a pointer equality? | LIVE |
| `check_quiet_lookup.sh` | Does a dead object handle resolve silently where silence is correct, and still complain where a complaint is correct? | LIVE |
| `check_race_feats.sh` | Does a Dragonkin get Mantis Leap on the character sheet? | LIVE |
| `check_reveal_delete.sh` | Can a monster still delete itself inside `Reveal()` and leave the caller holding a dangling map pointer? | LIVE |
| `check_sacrifice.sh` | Does a god's altar read the rows BELOW `MA_ALL`, and refuse what it should refuse? | LIVE |
| `check_save_fail.sh` | Does a save that fails part-way leave the game playable? Stages the throw with `INCURSION_SAVE_FAIL_AT` at a chosen object or data block. It does not drive a real disk-full, and cannot: every write goes into a memory `CFile` and the disk is untouched until `CommitCompressed`, so a full disk can only fail once every object is already converted. That case was reproduced by hand instead. | LIVE |
| `check_sentinel_live.sh` | Does the Sentinel's engine-side save track match the table it prints? Makes one, four levels deep. | LIVE |
| `check_sharp_senses.sh` | Does the Sharp Senses bonus reach Search, and not only Spot and Listen? | LIVE |
| `check_stacked_abilities.sh` | Do abilities whose prose says their levels stack across classes actually stack, charging one waiting period rather than one per class? Five characters: a Rogue 6 invariant, a Barbarian 3 / Rogue 3, a Bard 7 / Assassin 4, an Elf Rogue 7 / Assassin 3 and a control. | LIVE |
| `check_stair_cycle.sh` | Does the overview map's staircase search run, pick the cheapest, and wrap? | LIVE |
| `check_store_scroll.sh` | Does the shop list follow the selection in both directions, reached without wizard mode? | LIVE |
| `check_strqueue.sh` | Is the string queue's bound still tested before the write? | LIVE |
| `check_target_order.sh` | Does the target cursor step round the ring instead of scoring one axis? | LIVE |
| `check_two_fist_feats_live.sh` | Do the two-weapon feats reach two empty hands? A Monk 1 / Warrior 10 buys Two-Weapon Tempest and the sheet's Brawl row moves 125% to 175%; the 1st-level sidebar must still read two equal fists at full Strength. | LIVE |
| `check_underdark_live.sh` | Does the Underdark Warrior check the race it requires, and give the Reflex save it advertises? | LIVE |
| `check_upstream_marks.sh` | Is every base-code fix marked, marked well-formed, and matched to a row in the reporting table? | LIVE |
| `check_weapon_immunity_live.sh` | Is a bare fist tested against Weapon Immunity, and does Ki Strike beat it? One wizard-mode-summoned lemure, punched by the same character at Monk 1 and at Monk 4: `Your weapon fails to penetrate.` then no such line. | LIVE |
| `check_xp_penalty.sh` | Can a character who holds only two classes read his own sheet? A Wood Elf Rogue 2 / Warrior 1, whose empty third class slot used to segfault `Character::XPPenalty`. | LIVE |
| `check_xp_penalty_rule.sh` | Does the multiclass experience penalty follow the rule? Favoured and prestige classes leave the comparison, then each remaining class two or more levels below the highest remaining class costs 20% and the costs add. Six characters: an Elf photographed at Barbarian 3, Barbarian 3 / Rogue 1, + Warrior 1 and Barbarian 3 / Rogue 2 / Warrior 2, plus an Elf Rogue 5 / Assassin 2 and a Wood Elf Rogue 2 / Warrior 1. | LIVE |

### Diagnostics

| File | The question it answers | Status |
|---|---|---|
| `sweep_ptr_order.sh` | Where does this codebase put two pointers in order? Drives clang's parse tree through `sweep_ptr_order.py`. | LIVE |
| `sweep_ptr_order.py` | The parse-tree reader `sweep_ptr_order.sh` pipes into. Not run directly. | LIVE |
| `flickercapture.sh` | Captures the game window and the frontmost app as fast as stills allow, into one dated directory. | LIVE |
| `flickerscan.py` | Crops those captures to the game window and correlates brightness against repaints. | LIVE |
| `flickerscan_selftest.py` | Does `flickerscan.py` still refuse to reach a verdict on black frames? | LIVE |
| `flickerthumbs.py` | Downscales a capture directory to attachable thumbnails. | LIVE |
| `flickerscan.sh` | Samples the WHOLE composited screen every 500ms. | **SUPERSEDED** |
| `craft_corrupt_saves.py` | Builds the ten corrupt saves `check_load_corrupt.sh` feeds the binary. Not run directly. | LIVE |
| `lz_uncompress_selftest.c` | The guard-buffer harness `check_lz_uncompress.sh` compiles against the real `src/lz.c` and `src/rle.c`. Not run directly. | LIVE |

**`flickerscan.sh` versus `flickercapture.sh`.** `flickercapture.sh` won. Both
sample the screen while the instrumented game runs, and they differ in three
ways that all favour the newer one. `flickerscan.sh:1-9` samples the whole
composited screen, at a fixed 500ms (`flickerscan.sh:32`);
`flickercapture.sh:1-4` starts the game itself, so its
clock and the capture clock share a known anchor, and then crops to the game
window through `flickerscan.py`. The game window covers about half the screen,
so averaging the whole desktop halves any real signal and lets unrelated windows
swamp it (`flickerscan.py:5-8`). `flickerscan.py` also refuses to reach a verdict
on black frames, which is the failure that had the older scan confidently
reporting results from captures macOS had blocked
(`docs/PORT-STATUS.md:366`). `flickerscan.sh` still calls `flickerscan.py`,
so it is not broken — it is the weaker instrument, and it is kept only so its
older logs stay interpretable.

**What no flicker tool can tell you, and the general lesson.** There used to be
a compile-time `-DFLICKER_PROBE`. It was deleted on 2026-08-18 and the reason is
the lesson. It sampled luminance only inside libtcod's `actual_rendering()`,
so it fired only when the game PRESENTED a frame. The game presenting at about
2 per second, with gaps to 3.4 seconds, WAS the bug. The instrument was
structurally blind to the defect it was built for, and its flat 8.99 reading was
true and irrelevant (`docs/DEVTOOLS-AUDIT.md`). Read every diagnostic in
this directory the same way: ask what it samples before you trust what it says.
An instrument that answers confidently about the wrong thing costs more than no
instrument. `gate_lib.sh:27-29` states its own version of this limit — the gate
detects only regressions that produce log output, and never replaces a
play-test. `check_upstream_marks.sh:49-56` and `check_api_arity.py:65-69` each
state theirs.

### Build and release

| File | The question it answers | Status |
|---|---|---|
| `package_macos_app.sh` | Produces `Incursion.app` that Gatekeeper approves, inside a draggable disk image. | BUILD INFRASTRUCTURE |
| `package_macos.sh` | Produces `dist/Incursion-macOS-arm64/`, a plain folder with the game and its data. | BUILD INFRASTRUCTURE |
| `app_launcher.c` | The bundle's entry point. Redirects the game's single read-write directory to `~/Library/Application Support/Incursion/` so nothing writes inside the signed bundle. Compiled by `package_macos_app.sh`. | BUILD INFRASTRUCTURE |
| `setup_notary.sh` | Stores the notarisation credential in a mode-600 file so a release can be cut from a non-Terminal shell. Run once, by hand. | BUILD INFRASTRUCTURE |

`package_macos.sh` is not superseded by `package_macos_app.sh`. They produce
different artefacts for different reasons: a bare executable in a folder cannot
be assessed by Gatekeeper at all, and a notarisation ticket cannot be stapled to
one (`package_macos_app.sh:5-13`).

### Not scripts

| Path | What it is |
|---|---|
| `keys/*.keys` | The key scripts `headless.sh` plays. Read the header of one before you use it. |
| `gates/dive.baseline` | The committed regression baseline. `gate_record.sh` overwrites it. |
| `gates/Options.Dat` | The pinned settings file every gate run plays with. Committed on purpose. |
| `gates/Options.Dat.md` | What is in that settings file and why. |
| `__pycache__/` | Python bytecode. Untracked build litter. |

---

## 7. Running the checks

There is no runner, no Makefile and no CI. Run them by hand, in this order.

### Tier 1 — safe from a clean clone, no build, seconds each

These read source or text and compile nothing that needs the game to have been
built.

```sh
tools/check_error_handling.sh       # greps src/*.cpp for the unbounded writes
tools/check_upstream_marks.sh       # reads src/, inc/ and docs/REPORTING-GATE.md
tools/check_api_arity.py            # reads inc/Api.h against the C++ headers
tools/check_gate.sh                 # feeds gate_lib.sh made-up logs
tools/check_escape_sweep.sh         # greps src/ and inc/ for a C escape spelled /n
tools/check_natural_speed.sh        # reads lib/weapons.irh against inc/Defines.h
```

These tools prove themselves against known-bad input on demand:

```sh
tools/check_upstream_marks.sh --selftest
tools/check_api_arity.py --selftest
tools/check_headless.sh --selftest
tools/check_citations.sh --selftest
tools/check_escape_sweep.sh --selftest
tools/check_lz_uncompress.sh --selftest
python3 tools/flickerscan_selftest.py
```

Run the self-test when you change the checker. A check that has quietly stopped
checking anything looks exactly like a check that passes.

`tools/check_citations.sh <document>` also belongs in this tier, but it resolves
citations against the git refs `upstream/master` and `origin/master`
(`check_citations.sh:162-163`). Fetch those remotes first, or it reports failures
that are only missing refs. It is read-only on git.

### Tier 2 — needs a compiler but no prior build

Each of these compiles what it needs, in a temporary directory, and cleans up.

```sh
tools/check_abi.sh                  # compiles src/AbiCheck.cpp
tools/check_logrotate.sh            # compiles src/ErrorLog.cpp standalone
tools/check_lz_uncompress.sh        # compiles lz_uncompress_selftest.c under UBSan
tools/check_ptr_sweep.sh            # compiles a five-line fixture
tools/check_strqueue.sh             # builds its own probe binary, then deletes it
```

`check_strqueue.sh:36-38` calls `./build_macos.sh` itself with
`OUT=incursion-strqueue`, so it costs a full build the first time. It removes
that binary afterwards (`check_strqueue.sh:95`). It copies the LIVE `Options.Dat`
into its sandbox (`check_strqueue.sh:48`), so Trap 2 applies to it.

### Tier 3 — needs `BACKEND=posix ./build_macos.sh` first

```sh
BACKEND=posix ./build_macos.sh
tools/check_headless.sh             # run this one FIRST of the tier
tools/check_dump_save.sh
tools/check_load_corrupt.sh
tools/check_race_feats.sh
tools/check_ki_strike_live.sh
tools/check_weapon_immunity_live.sh
tools/check_two_fist_feats_live.sh
tools/check_sacrifice.sh
tools/check_natural_speed_live.sh
tools/check_quiet_lookup.sh
tools/check_reveal_delete.sh
tools/check_save_fail.sh
tools/check_stair_cycle.sh
tools/check_broken_door.sh
tools/check_store_scroll.sh
tools/check_target_order.sh
tools/check_key_directives.sh
tools/check_menu_value.sh
tools/check_sharp_senses.sh
tools/check_stacked_abilities.sh
tools/check_xp_penalty.sh
tools/check_xp_penalty_rule.sh
tools/check_prestige_profs.sh
tools/check_prestige_tables.sh
tools/check_alienist_live.sh
tools/check_earthsinger_live.sh
tools/check_huntsman_live.sh
tools/check_loremaster_live.sh
tools/check_masterarcher_live.sh
tools/check_sentinel_live.sh
tools/check_underdark_live.sh
```

Run `check_headless.sh` before the rest of the tier. They all drive
`headless.sh`, and if the harness itself is broken their results are
meaningless.

`check_natural_speed.sh` is Tier 1, not Tier 3: it reads `lib/weapons.irh` and
`inc/Defines.h` and runs nothing. Its live twin,
`check_natural_speed_live.sh`, is the one that needs a build.

`check_sacrifice.sh` runs three sessions, not one, and each later one is the
point: `sacrifice-wildcard.keys` proves the changed row now matches,
`sacrifice-goblinoid.keys` proves a row that already matched still behaves
identically, and `sacrifice-aiswin.keys` proves the rows BELOW `MA_ALL` are
read at all. Without the second, the check cannot tell a fixed wildcard from a
loop that matches everything. Without the third, it cannot see a loop that
stops one row too early.

`check_load_corrupt.sh:37-41` prefers `./incursion-ubsan` when it exists and
falls back to `./incursion-headless`. Build the sanitizer variant with the line
in `build_macos.sh:80-84` if you want the stronger run.

### Tier 4 — needs an artefact you built on purpose

```sh
tools/package_macos.sh      && tools/check_package.sh dist/Incursion-macOS-arm64
tools/package_macos_app.sh  && tools/check_app.sh dist/Incursion.app
```

`check_layout.sh` also sits here. It needs `lldb` on `PATH` and a probe build
(`check_layout.sh:61`, `:65-66`):

```sh
EXTRA_CXXFLAGS=-DDIVERGE_PROBE OUT=incursion-probe BACKEND=posix ./build_macos.sh
tools/check_layout.sh 3 tools/keys/dive12.keys
```

### Tier 5 — the gate, which needs a baseline

```sh
tools/gate_compare.sh               # re-runs every recorded baseline
```

`tools/gates/dive.baseline` is committed, so a clone can run `gate_compare.sh`
without recording anything. Do NOT run `gate_record.sh` unless you mean to
replace that baseline — see below.

### The ones you must not run casually

**`tools/check_abs_path.sh` runs the real game from the repo root, and moves the
live `Options.Dat` aside.** Verified: `check_abs_path.sh:22-27` renames `Options.Dat` to
`Options.Dat.checktmp` and installs an `EXIT` trap to move it back; `check_abs_path.sh:32` runs
`./incursion` in the background from the repo root, and `check_abs_path.sh:34-35` sleep 8 seconds
and kill it. Two consequences. First, the game resolves the repo root as its own
directory, so it reads and can write the owner's real `save/`. Second, if the
script is killed with a signal the trap cannot catch, the live `Options.Dat`
stays parked at `Options.Dat.checktmp` and the game starts with defaults next
time. Recover by renaming it back. Do not run this while anyone is playing.

**`tools/gate_record.sh` OVERWRITES a committed baseline.** Verified:
`:37-38` build `OUT="$ROOT/tools/gates/$NAME.baseline"` from the key script's
name, and `:71-80` truncate that path with `>`. The default key script is
`tools/keys/dive.keys` (`gate_record.sh:21`), so a bare `tools/gate_record.sh` replaces
`tools/gates/dive.baseline`. Record a baseline only from a build you believe in:
a baseline taken from a broken build makes the gate defend the breakage
(`gate_record.sh:13-14`). `git diff tools/gates/` afterwards, always.

---

## 8. Two checks were repaired on 2026-08-17

This section exists so nobody describes their old behaviour.

**`check_upstream_marks.sh` now runs three passes, not one.** Pass 1 is the
original: every well-formed `upstream:` marker states its four required things
and its tracking id reaches the table in `docs/REPORTING-GATE.md`
(`check_upstream_marks.sh:11-15`). Pass 2 is new and FAILS on a MALFORMED
marker — a comment shaped like a marker whose tag is not spelled as the
documented `upstream: ` and is therefore invisible to
`grep -rn "upstream:" src/ inc/`. `src/rle.c:270` and `src/lz.c:500` both wrote
it as `upstream (inc-l0t, Traced, not sent):` and were skipped in silence for
months (`check_upstream_marks.sh:16-23`). Both of those two sites are now spelled correctly, so reading
them today shows the fix and not the defect; the check is what keeps the next
one from happening. Pass 3 is new and checks the REVERSE direction: for every fix
site the table names, the named file must carry a marker mentioning that row's
id (`check_upstream_marks.sh:35-39`). Pass 3 WARNED rather than failed until
2026-08-23, because two rows were unmatched and resolving them is a provenance
judgement, not this script's call. Both were settled that day (bd inc-6s5), so
the pass now FAILS and `--strict` is the default (`check_upstream_marks.sh:41-47`,
`:73-79`). The flag is still accepted and does nothing, so an older caller does
not break (`check_upstream_marks.sh:60`). `--selftest` proves the detectors still
detect (`check_upstream_marks.sh:61`), and since 2026-08-23 that includes pass 3
itself: a synthetic table with one unmatched row, one matched row and one row
naming a file that is not there must produce exactly one WARN, one FAIL and no
word about the matched row.

**`check_api_arity.py` now has a checked-in baseline and can fail.** It used to
return 0 on every path, printing two MISALIGNED slots and exiting green, so
anything running it as a gate got a pass no matter what happened
(`check_api_arity.py:52-55`). It now compares what it finds against a `BASELINE`
dictionary held in the script itself at `:110`. Three outcomes
(`check_api_arity.py:56-63`):

- a MISALIGNED slot IN the baseline — reported as KNOWN, tolerated;
- a MISALIGNED slot NOT in it — FAIL, a new defect or a real change;
- a baseline entry that no longer misaligns, or whose types moved — **also
  FAIL**, because a stale suppression is how a gate rots.

The exit codes are 0 clean, 1 a failure of any of those three kinds, 2 the tool
could not parse `inc/Api.h` and so examined nothing
(`check_api_arity.py:71-77`). `--selftest` exercises all four branches with no
framework and no fixtures (`:368-369`, `:391-398`). Note the tool's own stated
limit: about a fifth of the declarations — 94 of 460 — find no C++ declaration
its parser can match, so a clean run is not a clean bill of health
(`:65-69`).

---

## 9. Known gaps in this directory

- **The issue ids in these headers cannot be resolved from a clone.** Count them
  with:

  ```sh
  grep -rhoE "inc-[a-z0-9]{3}(\.[0-9]+)?" tools/ \
      --include='*.sh' --include='*.py' --include='*.keys' --include='*.c' |
      sort -u
  ```

  That returns 52, of which 6 are self-test fixtures (`inc-000`, `inc-aaa`,
  `inc-abc`, `inc-bbb`, `inc-ccc`, `inc-ddd`), leaving 46 real ids. The
  tracker's export `.beads/issues.jsonl` is neither present nor tracked
  (`git ls-files .beads/`). Run `bd show <id>` on a machine that has the local
  Dolt database, or the reasoning behind the harness is unreachable.
- **The run directories these headers cite do not survive a clone either.**
  `logs/` is gitignored (`.gitignore:29`), so every `logs/gate/...` citation is
  a pointer to one machine. Committed evidence lives under `docs/evidence/`.
- **There is no runner.** No Makefile, no CI, no `check_all.sh`. §7 is the
  substitute. Adding a runner is deliberate scope for a later change, not an
  oversight to fix in passing.
- **One key script's assertion has no automated check.**
  `tools/keys/dragonkin-ration.keys` cited a `tools/check_dragonkin_ration.sh`
  that has never existed. Its header is corrected; the assertion is still
  enforced by a person reading the dumps.
