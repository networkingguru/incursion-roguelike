<!-- citations: this-port -->

# tools/ — what is here and which parts matter

This directory holds the unattended-testing harness for the macOS/Linux port of
Incursion. Read this page before you run anything in it.

**A few files carry almost all of the value.** Learn these and you can ignore the
rest until you need them.

| File | Why it matters |
|---|---|
| `headless.sh` | Runs one scripted game session in a sandbox. Everything else that plays the game calls it. |
| `check_dequ_dice.sh` | Declared A_DEQU dice must roll without tripling (inc-m2zi AC8). |
| `check_dequ_dc.sh` | Only the four named SRD A_DEQU monsters retain DCs (inc-m2zi AC8). |
| `check_fire_hardness.sh` | Ordinary combustible materials lose fire hardness; enchanted materials keep it (inc-m2zi AC8). |
| `check_item_hardness.sh` | Every Item gets modifiers once, after preserving immunity (inc-m2zi AC8). |
| `check_item_owner_resist.sh` | Gear inherits blanket soak/rust defences and otherwise only flagged grants (inc-w26h). |
| `check_item_flag_protection.sh` | Flagged acid immunity keeps an iron maul undamaged against acid-blob retaliation (inc-w26h). |
| `check_xprint_tokens.sh` | Ratchet literal __XPrint object-token vararg overruns (inc-upw.30); Python 3 only. |
| `check_gaze_reflect_message.sh` | A reflected gaze must name the gazing monster once, on screen (inc-upw.30); needs the POSIX build. |
| `check_buckler_size.sh` | A buckler costs -1 to Balance on both Medium and enlarged Large bearers (inc-drmm). |
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

`build_macos.sh:84` defaults `BACKEND` to `libtcod`; `:87` maps that to
`OUT=incursion` and `:88` maps `posix` to `OUT=incursion-headless`. Either line
also compiles `mod/Incursion.Mod`, because both builds carry the resource
compiler by default. An ordinary build recompiles it every time; a build with
`EXTRA_CXXFLAGS` set compiles it only when the file is absent (`build_macos.sh:375-385`).

The `posix` build compiles `src/Wposix.cpp` and links `-lz -lncurses`
(`build_macos.sh:243-252`). ncurses ships with macOS and with every Linux
distribution, so it adds nothing to install, and it draws only to a real
terminal — a headless run never calls into it
(`build_macos.sh:249-251`). The `libtcod` build links SDL2 and OpenGL instead
(`build_macos.sh:254-259`), and needs `sdl2` and `pkg-config` from Homebrew.

**The harness needs the second line.** `headless.sh:82` defaults its binary to
`./incursion-headless`, and `:85-88` refuses to run without it, printing that
exact build command. `soak.sh:33-35`, `check_race_feats.sh:23-26` and
`check_load_corrupt.sh:62-65` all say the same.

Requirements: Xcode command line tools, plus `sdl2` and `pkg-config` from
Homebrew (`build_macos.sh:4-5`). The POSIX build needs neither SDL nor libtcod
(`build_macos.sh:34-35`).

---

## 2. How the pieces fit

`headless.sh` is the harness. It plays one session of a key script from
`tools/keys/` inside its own directory under `logs/runs/`, with its own `save/`
and `logs/`, and with `mod/` and `lib/` symlinked in (`headless.sh:13-16`). It
exists so that an unattended run cannot destroy a real character. Use it and
never the binary directly (`headless.sh:55-58`).

The harness takes two environment variables as inputs beside the key script and
the seed. `INCURSION_OPTIONS` is mandatory and names the settings file (Trap 2
below). `INCURSION_LOAD` is optional and names a save file, and the session then
starts from that character instead of from the title menu. It exists because a
character built by a key script is not reproducible across module changes, while
one loaded from a save is; the harness COPIES the save into the run's own
`save/` first, so a loaded session cannot rewrite the file it read.
`tools/fixtures/README.md` holds the argument, the three files a character
fixture is made of, and the commands that make and regenerate one.

Both backends read `-keys` scripts. The SDL/libtcod build accepts the shared
movement subset: literal and named keys, `*N` repeats, comments, `@include`,
`@pause MS` and `@quit`. It does not accept the POSIX-only screen-scrape
directives `@choose`, `@expect`, `@cursorto`, `@while` or `@until`. `@pause MS`
holds the SDL frame for that many milliseconds while the light keeps animating;
the headless build treats it as a no-op so replay stays instant. In SDL, `@quit`
or consuming the last key exits the game; put `@pause` before the end to hold
the final frame. Both backends also accept `-load <save>`, which loads the named save
straight into play without visiting the title menu. For example:

```sh
./incursion -load save/<character>.sav -keys tools/keys/trailer-demo.keys
```

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
(`src/Wposix.cpp` `TokenToKey`, `src/Tables.cpp:4754`/`4874`).

`[M] Create Altar` is there for the harness. A sacrifice needs the player to
be standing on an altar, and the only other source of one is `MakeLev`'s
random assignment (`src/MakeLev.cpp:2107-2123`), which picks from seven gods
and cannot be asked for a particular one. The command prompts for a god name
and builds the feature exactly as `MakeLev.cpp:1143-1145` does.
`check_sacrifice.sh` is the first thing to use it.

The Watery Double fixtures use seed `20260905` and
`INCURSION_OPTIONS=tools/gates/Options.Dat` through `tools/headless.sh`:
`keys/watery-death.keys` covers target death and `keys/watery-nocast.keys` is
its no-cast control. `keys/watery-cancel.keys` deliberately cancels the spell;
`keys/watery-expire.keys` measures its lifetime and gives only the original
target the earthen template after casting so combat cannot end the spell first.
Both assert collapse, surviving target and pony bystander, and player HP 47/47.
`keys/watery-caster-death.keys` self-casts Disintegrate and confirms real
player death with the pony still alive, without a crash. The double itself is
still `B aqueous giant` on the death screen: a player caster's death does not
enqueue removal before `Game::Play` exits, so this fixture proves the crash is
gone but does NOT observe caster-loss removal. `keys/watery-monster-caster.keys`
covers that gap with a MONSTER caster instead: a paragon nereid AI-casts
Watery Double on a giant tortoise, in view of a pony bystander, then the player
kills the nereid with Disintegrate (two rays are needed at seed `20260905` --
the first is turned aside by the nereid's magic resistance) while the tortoise
and pony are both still alive. The nereid's death fires "The nereid
disintegrates!" and "The aqueous giant tortoise collapses back to inanimate
water!" together: the double leaves no live entry and no corpse, and the
target and bystander both survive. This is the fixture that actually observes
caster-loss removal (inc-q3r5, `docs/REPORTING-GATE.md`). None of these four
fixtures (`watery-cancel`, `watery-expire`, `watery-caster-death`,
`watery-monster-caster`) use a genocide command.

Everything else is a diagnostic, a packaging step, or superseded.

---

## 3. Glossary of what the harness prints

`headless.sh` prints a fixed report after every session. The words are not
self-explanatory.

**`ended: NO GAMEPLAY`** — the run never entered a map, so it measured nothing.
`Game::Play` writes `logs/session.log` on the first completed turn, so that file
exists if and only if the session reached gameplay (`headless.sh:230-231`). When
it is missing and the run would otherwise have exited 0 or 3, `headless.sh:232-234`
rewrites the exit code to 5. Do not count such a run as a pass. Screens are not
a substitute test: `@dump` lines fire even in a session that never entered a map,
and one vacuous run left 11 of them (`headless.sh:224-226`).

**`ended: ASSERT`** — the engine logged an `ASSERT failed` whose condition is
not listed in `tools/known_asserts.txt`, and the run would otherwise have
exited 0 or 3, so `headless.sh` rewrites the exit code to 7 and prints the
condition. The list holds upstream's standing asserts (the `InBounds` spam and
four others) so every check does not go red on them; add a line only for a
tracked assert, and remove it when the fix lands. Added 2026-08-30 after the
controller `?` screen crashed on the Ally: the harness had logged the very
assert, and the check that drove the session read only the screen dump.

**`ended: WATCHDOG`** — exit 4. The game stopped asking for keystrokes, which is
the signature of a hang (`headless.sh:38-39`). `SIGALRM` fires in
`src/Wposix.cpp:450-458`, which writes `incursion: watchdog timeout, no key read
in time` and exits with `EXIT_OUT_OF_TIME`, defined as 4 at `src/Wposix.cpp:85`.
The alarm is 300 seconds (`src/Wposix.cpp:80`) and it measures the GAP between
keystrokes, not the length of the run, so a long honest session is safe
(`src/Wposix.cpp:1595-1599`). It is never armed when a person is at the keyboard
(`src/Wposix.cpp:580-584`).

**`death: STUCK`** — the run ended with `Die? [yn]` still on the last screen,
unanswered (`headless.sh:321-324`). The pinned settings run with `OPT_NODEATH`
on, so a killing blow asks that question instead of ending the game, and a key
script answers it blind with whatever token comes next
(`headless.sh:290-293`). If no `y` or `n` remains in the script, every later
keystroke is swallowed and the run still reports `ended: cleanly`
(`headless.sh:303-306`). A confirmed death prints `death: N confirmed` instead
and is logged to `logs/death.log`. Neither gets its own exit code, on purpose:
whether a death should fail a run is a product decision the script does not make
(`headless.sh:44-49`).

**`stuck-prompt: threat-disengage`** — the run ended with `You are in a
threatened area. Abort, Flee or Disengage?` still on screen
(`headless.sh:344-347`). That prompt has no option gate at all and fires
whenever a player-controlled creature moves away from a hostile creature that
perceives it (`src/Move.cpp:941`, quoted at `headless.sh:330-331`).
`f7ff2d7` (2026-08-28) gave ChoicePrompt arrow+ENTER navigation, so
`tools/keys/dive.keys` can now select `a`, `f` or `d` -- but it can also land
on `?` and open the combat manual, which has no ESC out, so the script still
stalls there. Measured on 7 of 40 seeds (`headless.sh:339-341`).

**`map audit: armed, no inconsistencies found`** — the audit ran and found
nothing. `src/MapAudit.cpp:64` writes an `=== map audit armed ... ===` header
whenever the audit is on, so the log carries a line even on a clean run. That is
what lets `headless.sh:404-405` tell "clean" apart from "never ran". A missing
log is reported three different ways depending on why (`headless.sh:396-403`),
because merging them is the exact defect this code used to have.

---

## 4. Traps that have already produced a false measurement

**Trap 1 — every script resolves the repo root itself.** The idiom is
`ROOT="$(cd "$(dirname "$0")/.." && pwd)"` followed by `cd "$ROOT"`
(`headless.sh:52-53`, `soak.sh:24-25`, `gate_record.sh:17-18`,
`check_headless.sh:38-39`, and most other scripts here). So you may call any of
them from any working directory, and the path arguments they take are relative
to the REPO ROOT, not to where you are standing. `gate_lib.sh:43` uses `BASH_SOURCE` instead
because it is sourced, not executed.

**Trap 2 — every `headless.sh` run must choose its settings.** Set
`INCURSION_OPTIONS` to one of the frozen files in `tools/fixtures/`, or to a
purpose-built file such as `tools/gates/Options.Dat`. The harness refuses an
unset variable or a path that is not a file (`headless.sh:105-113`). This keeps
checks independent of the repository-root `Options.Dat`, which belongs to the
player and is rewritten every session. Settings change the game: on 2026-08-15
the same binary, seed and key script gave different screens either side of a
rewrite, and the gate's finding count moved 4386 to 4416 with no code change.

This matters more than it sounds, because the key scripts choose menu items by
FIXED LETTERS. One extra prompt slides every later keystroke out of step. Two
seeds died exactly that way when a god offered a domain prompt the stream had no
answer for (`tools/keys/chargen-priest.keys:24-28`). Anything that compares one
run against another MUST pass `INCURSION_OPTIONS`. The gate pins
`tools/gates/Options.Dat` and records its checksum in the baseline
(`gate_lib.sh:43-44`, `gate_record.sh:28-34`). A run that does not choose a
file, or names one it cannot have, is an error (`headless.sh:105-113`).

**Trap 3 — the map audit is ON by default and it is expensive.**
`headless.sh:169` sets `INCURSION_MAP_AUDIT` to 1 unless you override it. A
sample of a headless run on 2026-08-15 put 75 percent of the run inside
`AuditMap`, so a session with the audit on measures the audit and not the game
(`headless.sh:165-168`). **Anything timing the engine MUST set
`INCURSION_MAP_AUDIT=0`. Anything hunting defects MUST leave it on.**

**Trap 4 — a key script longer than the budget stops early and exits 3, and
that looks like a short run rather than a failure.** The budget is
`DEFAULT_MAX_KEYS 20000` (`src/Wposix.cpp:79`, applied at `:150`). It counts keys
READ, one per `GetChar` call (`src/Wposix.cpp:1592`), and when it runs out
the game dumps a screen named `maxkeys` and exits with `EXIT_OUT_OF_KEYS`, which
is 3. Raise it with `INCURSION_MAX_KEYS` (`src/Wposix.cpp:574-575`).

**Correction, 2026-08-17: `marathon.keys` does NOT need a raised cap, and the
usage line in its own header was wrong.** That header told everyone to run
`INCURSION_MAX_KEYS=60000` and said the file "exceeds" the 20000 default "on
purpose". It does not. Expanding every `TOKEN*N` gives 10780 keystrokes, and the
`chargen.keys` it includes gives 111, so a session reads at most 10891 — about
half the default. The header contradicted itself, because its own line 12 already
said "roughly 10500 keystrokes", which was the count on that date. The budget has
been 20000 since the harness was added (commit `058ba87`). I corrected the header
and left the counting one-liner in it. The file has grown since: it counted 10500
until `cd25032` on 2026-08-22 stamped the turn on every screen dump, and the
figures below were re-taken on 2026-09-05. Count, do not guess:

```sh
python3 -c "import re,sys; print(sum(int(m.group(2)) if (m:=re.match(r'^(.+?)\*(\d+)$',t)) else 1 for l in open(sys.argv[1]) if not l.lstrip().startswith('@') for t in l.split('#')[0].split() if not t.startswith('@')))" tools/keys/marathon.keys
```

Measured with that line: `marathon.keys` 10780, `explore.keys` 1259,
`dive.keys` 886, `chargen.keys` 111. The `marathon.keys` header also described
`explore.keys` as "about 500" and `dive.keys` as "about 400"; both were low by a
factor of about 2.5, and both are now the measured numbers.

**Trap 5 — two runs started in the same second used to SHARE a run directory.
Fixed; the history is here because the number it corrupted was published.**
`headless.sh:97` now names the default run directory
`logs/runs/$(date +%Y%m%d-%H%M%S)-<pid>-<script>`. The stamp alone resolves to
the SECOND, so before the process id joined it, a loop that started several
sessions inside one second gave them all the same directory, and any probe that
APPENDS to a log wrote into the same file. The result was one directory whose
log read like a single long session, and every per-seed figure drawn from it was
wrong. This produced a false count on 2026-08-17: a 7-session, 51-level survey
figure had to be withdrawn and re-measured at 60 levels over eight isolated
seeds (commit `0b5b59b`, bd `inc-uh0`). `dump_save.sh:79` carried the same
defect and got the same fix. `check_headless.sh` assertion 11 is what stops it
coming back: it starts two sessions at once with no `INCURSION_RUN_DIR` and
fails if they report one path.

**The rule still holds: pass a unique `INCURSION_RUN_DIR` for every run in a
loop, then count the run directories and confirm the count equals the number of
runs before you believe any per-seed number.** A name you chose says what the
run was for, which a pid does not, and the count is the only thing that proves
the runs stayed apart. `soak.sh:59` does this, and so does every check that
drives more than one session (`check_headless.sh:258`, `:282`, `:292`, `:305`,
`:327`; `check_layout.sh:89`; `check_dump_save.sh:56`;
`check_load_corrupt.sh:76`). `check_race_feats.sh:29-30` does NOT — it takes the
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

## 6. The files that matter in tools/

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
| `make_char_fixture.sh` | How do I freeze one generated character so a check can load him instead of re-rolling him? Writes the three files of a character fixture into `tools/fixtures/chars/` — the `.sav`, the key script that made it, and the engine's own sheet with its provenance header — and proves the `.sav` loads by reading it back before it publishes. `--force` regenerates an existing fixture. | LIVE |

`run_probe.sh` was **deleted on 2026-08-18**. Its own header said "Delete this
script once the saved-game position bug is fixed", and that bug is fixed:
`docs/REPORTING-GATE.md:427` records `*((long*)&hm)` destroying the player's
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
| `nightly_verify.sh` | The wrapper a branch must clear: both builds, the Linux cross-build, the layout sweep, `gate_compare.sh`, then every check that declares a gate tier, ratcheted against a recorded base. `--selftest` drives its own verdict table over made-up checks. A full pass leaves `nightly-verify-pass.txt` beside the base. `--reuse-pass`, which `finish_bead.sh` runs, re-runs only the cheap tier when that record matches the files on disk, the base and the toolchain and is under 24 hours old; otherwise it is `--compare`. | LIVE |

### The shared library for new checks

| File | The question it answers | Status |
|---|---|---|
| `check_lib.sh` | Sourced, not run. Holds the scaffolding every behavioural check repeats -- the seeded sandboxed session, the screen assertions, the build -- and makes `docs/VERIFICATION.md` step 2 one line: `<check> --prove-red` breaks the fix, rebuilds, re-runs the check, restores the source and reports whether the check went red. Proves itself with `--selftest`. | LIVE |

Written for new checks only (bd inc-le1m). The checks already in this
directory are not migrated: rewriting checks that work risks quietly breaking
one that guards a real defect, and buys no behaviour. Read the header of
`check_lib.sh` for a whole check written with it, which is about a dozen lines.

### The regression checks

A new check adds its row to this table, in alphabetical order.
`check_readme_checks.sh` fails the gate on a check that has no row here.

| File | The question it answers | Status |
|---|---|---|
| `check_abi.sh` | Did any save-format type width move, and does anything cast a handle to a pointer? | LIVE |
| `check_ability_descs.sh` | Does every live class ability have a description, do the two ability-name tables still agree, and does every newly granted ability land in `tools/ability_descs.live` or `tools/ability_descs.exempt`? | LIVE |
| `check_abs_path.sh` | Does the game still resolve `argv[0]` to an absolute path? **Unsafe, see §7.** | LIVE |
| `check_activate_stack.sh` | Does activating one item out of a stack leave the stack whole, and still fire the effect? | LIVE |
| `check_air_ring_spell.sh` | Does the Elemental Command (Air) ring description name the granted staff-spell "gaseous form", rather than the phantom "wind column" that exists nowhere in `lib/`? | LIVE |
| `check_alienist_drain.sh` | Does each Alienist summoning drain the held mana its page names (Summoned Creature's CR x 2), the mana that never regenerates? | LIVE |
| `check_alienist_live.sh` | Does the Alienist's Surreal Presence field exist and speak? A kobold summoned beside her must read "seems unsettled". | LIVE |
| `check_animal_kinship_prose.sh` | Does the Ring of Animal Kinship description drop its false "+3 or higher" untrained-use threshold, stating plainly that it lets you use Animal Empathy with no ranks -- which its skill bonus and the `SkillLevel` use-gate already permit? | LIVE |
| `check_api_arity.py` | Does any script API declaration in `inc/Api.h` bind an argument to the wrong C++ parameter? | LIVE |
| `check_app.sh` | Can a stranger download `Incursion.app` and open it? | LIVE |
| `check_armour_model.sh` | Does the armour model penetrate coverage by grade and subtract from damage, with natural armour and a worn suit penetrated independently? | LIVE |
| `check_bead_new_gate.sh` | Does `tools/bead_new.sh` actually refuse a bead that is not fit to publish, and pass one that is? Both `bd` and the checker are stubbed on `PATH`, so the run files nothing and deletes nothing -- a deliberately broken bead filed by a test would block the next commit in the tree exactly as a real one does. Also asserts that the wrapper checks the id it just filed, and that `--dry-run` checks nothing. | LIVE |
| `check_bead_publish.py` | Does every bead created since the last commit have a non-empty description and carry exactly one of `public` or `internal`, and does a new `public` one carry the sections a stranger needs to reproduce it? Wired into `.beads/hooks/pre-commit`, so it blocks a commit, except on the overnight harness's own `nightly/` branch, where it warns. `tools/sync_issues.sh` publishes the description and never the notes, so an undescribed bead reaches the tracker with an empty body; the label decides whether it is shown at all, so an unlabelled bead is an invisible one. | LIVE |
| `check_bloodspear_bane.sh` | Does the Bloodspear carry bane against all five races its page names? | LIVE |
| `check_bloodspear_lizardfolk.sh` | Does a lizardfolk wielder get the Bloodspear's +3 wounding tier, as its page promises? | LIVE |
| `check_bloodspear_orc_save.sh` | Is the Bloodspear's +4 saving throw versus spells restricted to an orc wielder, rather than granted to anyone who holds it? | LIVE |
| `check_bloodspear_regen.sh` | Does the Bloodspear start regeneration at 20 turns per critical-hit damage and extend it at 5 turns per later hit? | LIVE |
| `check_bloodspear_regen_duration.sh` | Does a Bloodspear critical grant the orc wielder regeneration for amt*20 turns rather than amt*5? | LIVE |
| `check_boots_providence.sh` | Do the Boots of Providence pay their Luck bonus while carried, not only while worn? | LIVE |
| `check_bracers_defense_page.sh` | Does the Bracers of Defense page state the two distinct rates: Defense Class equal to the magical plus and Coverage equal to twice the plus? | LIVE |
| `check_brawl_weapon.sh` | Does a fist still borrow the sword? An elf ranger holds his bow and carries his sword on his back, where the sheet will show both the Brawl and the Melee block, and the Brawl block must name no weapon at all. | LIVE |
| `check_brazier_prose.sh` | Does the Brazier Commanding Fire Elementals description say it can be lit three times per day, matching its `EF_3PERDAY` flag, rather than the "Once per day" it claimed before? | LIVE |
| `check_breath_dice.sh` | Does a breath weapon deliver the dice its statblock declares, and does a dragon's age still scale them? `Creature::SAttack` built the count from the declared dice plus twice the breather's Power and then assigned `max(1,e.Dmg.Number)` over the sum, and `e.Dmg` is zero for every caller on that path, so every breath in the game threw one die. Two sessions read a probe log, because each half alone can be passed by a wrong fix: a hell hound declares 2d6 and has no age template, and a red dragon declares 0d12 and takes every die from the template's Power. Unfixed 1d6 and 1d12, fixed 2d6 and, at Power 5, 10d12. The die sides never move, which is the control. | LIVE |
| `check_broken_door.sh` | Does a door still lie about being broken? Asserts the one predicate every reader asks, and runs a generated level to prove no door ends it closed and branded broken in a readable doorframe. | LIVE |
| `check_buckler_size.sh` | A buckler costs -1 to Balance on both Medium and enlarged Large bearers (inc-drmm). | LIVE |
| `check_char_fixture.sh` | Does a frozen character fixture still load, and is he still the character his own sheet claims? Loads `tools/fixtures/chars/lizardfolk-monk-seed1.sav` and reads his name, race, class and Strength off the character sheet. The oracle is the fixture's own `.sheet.txt`, so regenerating the fixture moves the expectations with it. Two structural assertions ride along: the `.sav` is byte-identical after a run that loaded AND saved it, and the run played its own copy. | LIVE |
| `check_chargen_escape.sh` | Does ESC at a character-creation menu offer to abandon the character, restore the same menu unchanged when that offer is refused, and return to the main menu rather than entering play with a half-made character? | LIVE |
| `check_circle_creator_death.sh` | When the player kills one of two overlapping archons, does the survivor stay lit? Fixed: survivor alive and white count 1. Unfixed: survivor alive and white count 0 -- alive in the dark, the reported symptom. | LIVE |
| `check_circle_no_stack.sh` | Do overlapping magic circles refuse to stack? An evil player between two archons must take -3, not -6, while still holding both status rows, because the leave path needs one row per granting field. Fixed `Hit:-2/-4`, unfixed `Hit:-5/-7`. | LIVE |
| `check_circlet_blasting_prose.sh` | Does the Circlet of Blasting description scope its base 5d8 damage to living creatures, matching its base `EA_BLAST` `tval: MA_LIVING` code and its Searing Light twin, rather than the "everything else" it claimed before? | LIVE |
| `check_citations.sh` | Does every code citation in an outgoing document resolve in the tree it claims to cite? | LIVE |
| `check_cleanup_removal_event.sh` | Does reference cleanup narrow removal to the rows referring to the dying source, and keep the inline fallback that guarantees forward progress? The `EV_REMOVED` event on this path is not new -- the base code already delivered it, measured on a clean HEAD build. Structural only: the narrowing's behavioural oracles are `check_circle_creator_death.sh` and `check_overlapping_modifier_fields.sh`, and the fallback guards a restart loop nobody has reproduced. | LIVE |
| `check_cloak_resistance.sh` | Does a +3 Cloak of Resistance grant resistance rather than magic? One session reads all three saving throws with the cloak alone and with auspicious +2 armour; the control stays fixed and the smaller same-type bonus must not stack. | LIVE |
| `check_clock_advance.sh` | Does the game-time oracle still catch a scripted run that burns keys while no game time passes? | LIVE |
| `check_command_leader_link.sh` | Does a creature the player charms, dominates or commands keep the summoner link `MakeCompanion` gives it, and do two such companions leave each other alone? Dominates two kobolds in turn, reads the game's own Examine dump for the link and for both hostility directions, then unfreezes monsters for 40 turns and reads the message log for one striking the other. | LIVE |
| `check_command_menu_gating.sh` | Do the Combat (C) and YUse (Y) menus still hide every verb with no implementation, and every verb whose character prerequisite is unmet? It dumps both menus before and after a wielded Quickblade grants Whirlwind Attack: the gated combat row appears only after the feat, and the dead Yuse rows stay absent either way. | LIVE |
| `check_command_prose.sh` | Does Command's description leave out the CR/level limit the code deliberately removed, rather than still promising "does not affect creatures whose CR is more than 2/3rds your level"? | LIVE |
| `check_comment_budget.sh` | Did a comment or `_PROBE` block in `src/` or `inc/` appear over the 30-line ceiling, or grow past its recorded size? Ratcheted against `tools/comment_budget.baseline`; `comment_budget.py` does the measuring. | LIVE |
| `check_commit_lane.sh` | Does every commit after `tools/commit_lane.since`, except the ones `tools/commit_lane.exempt` forgives by name, open with one of the seven lanes, and does every `rules:` commit name a design bead? | LIVE |
| `check_consumable_abort.sh` | Does a consumable survive an action the character refused to complete? Answers yes to the game's own "Stop reading?" offer and asserts the scroll stack did not move, then drinks a potion and asserts that one still goes. Reports a session whose Will save never produced the offer as INCONCLUSIVE. | LIVE |
| `check_convert_guard.sh` | Does `-convert` refuse the committed evidence fixtures and leave them byte-identical, while still converting a scratch copy? | LIVE |
| `check_cowl_warding_prose.sh` | Does the Cowl of Warding description state that its save-versus-spells and armour-luck bonuses scale with the magical plus -- +3 and +5 plus the plus -- rather than the flat "+4"/"+6" it claimed before, matching its `PLUS_ADD3`/`PLUS_ADD5` code? | LIVE |
| `check_cure_critical.sh` | Does the Cure Critical Wounds effect roll the `4d8 + LEVEL_MAX20` its own description promises, rather than the `3d8` it paid before? | LIVE |
| `check_death_attack.sh` | Does the Assassin's Death Attack gate only on the assassin's own out-of-combat state, so it can strike a target that is already fighting? | LIVE |
| `check_deepseek.sh` | Does `tools/deepseek.py` refuse to spend once its ledger says the budget is gone or poisoned, bill exactly one row per success, bill nothing on an HTTP failure, and never let the DeepInfra key reach stdout, stderr or the ledger (inc-3dgz)? | LIVE |
| `check_dequ_dc.sh` | Do exactly the four SRD monsters retain A_DEQU save DCs in the thirteen-monster roster? | LIVE |
| `check_dequ_dice.sh` | Does A_DEQU roll its declared dice without tripling? | LIVE |
| `check_dequ_magic_hardness.sh` | Against a monster whose A_DEQU carries no save DC, is a plain weapon's hardness bypassed while a magical weapon's is kept? Two sessions strike acid blobs, one with an ordinary long sword and one with a Holy Avenger, and read each sword's own description page before and after. | LIVE |
| `check_dequ_owner_immunity.sh` | Does a character's rust immunity shield his gear? Wearing Gauntlets of Rust, his iron maul stays at 262/262 hit points after five small mud elemental retaliations. | LIVE |
| `check_dequ_reach.sh` | Does a glaive user striking from two squares away now take the equipment retaliation he used to escape? The map shows the two-square gap, the message shows the blow landing, and the glaive's page shows the acid damage. | LIVE |
| `check_dequ_save_message.sh` | Does the equipment-save message name the character and reach him, rather than naming the item twice and speaking to the item? | LIVE |
| `check_dequ_sunder.sh` | Does sundering an armed equipment-destroyer damage the striker's weapon rather than the monster's own? A caryatid column's cursed long sword is sundered with a maul, and the maul's page is the oracle. | LIVE |
| `check_devour_negative_cr.sh` | Does devouring a corpse of negative challenge rating leave experience alone, while an ordinary corpse still pays? | LIVE |
| `check_devour_template_source.sh` | Does `Creature::Devour(Corpse*)` read the TEMPLATE stati off the corpse rather than off the eater, with the iteration opening and closing on the same object? | LIVE |
| `check_dig_zero_skill.sh` | Does a dig by a miner with zero Mining skill finish cleanly, rather than dividing by zero? | LIVE |
| `check_distant_light_vision.sh` | Does a self-luminous cell within sight range but past the player's own light/shadow range become visible, rather than being dropped when the vision ray dies on the dark cells before it? | LIVE |
| `check_divination_staff_prose.sh` | Does the Staff of Divination description name the granted spell "true seeing", rather than the phantom "true sight" that exists nowhere in `lib/`? | LIVE |
| `check_divine_aspect_prose.sh` | Does the Lesser Divine Aspect description state that its disease/poison saves and its acid/cold/electricity resistances scale per magical plus, matching its `PLUS_2PER1`/`PLUS_5PER1` code, rather than the flat "+2" and "resistance of 5" it claimed before? | LIVE |
| `check_divine_feat_gear.sh` | Does Divine Resistance protect a priest's gear while he is channeling? At Charisma 18 his plain iron warhammer holds 45 of 45 hit points through five firebat retaliations. | LIVE |
| `check_divine_power.sh` | Does Divine Power grant `FT_POWER_ATTACK` when the caster has STR 18 and no Power Attack, yet still grant `FT_KNOCK_PRONE` when he already has Power Attack, as its description promises? | LIVE |
| `check_doc_citations.sh` | Did any document a change touched gain a citation defect above its recorded baseline? | LIVE |
| `check_doc_freshness.sh` | Which documents did a range of commits leave stale, and does every line citation in them and in the source they touched still resolve? | LIVE |
| `check_dragonshield_hostility.sh` | Does the Dragonshield anger only chromatic (evil) dragons, matching its description, rather than every dragon including the metallic (good) ones? | LIVE |
| `check_dragonshield_plus_prose.sh` | Does the Dragonshield description state a "+2 (or higher)" enhancement floor, matching its `INITIAL_PLUS +2` constant, rather than the unreachable "+1 (or higher)" it claimed before? | LIVE |
| `check_dragonshield_prose.sh` | Does the Dragonshield description list the colour names the shield can actually display (yellow, not brown), matching its `EV_GETNAME` name table? | LIVE |
| `check_drain_selfaim.sh` | Does a monster's drain spell hit an enemy rather than the caster? Minor and Major Drain reach a monster only through the injury-remedy action, which carries no target, and the untargeted fallback used to aim them at the caster -- one feyr drained itself 120 times in thirty turns. Reads the cast probe for a monster attack with no direction and no location, and stops rather than passes if the session never landed the player's control cast. | LIVE |
| `check_dump_save.sh` | Does `-dump` still walk a real save and report the right fields, from BOTH backends? | LIVE |
| `check_dungeonmap_bounds.sh` | Does a levitating character on the bottom level still stay on it? `Game::GetDungeonMap` answered a request for one level past its own allocation by reading past the end of the array, and `Creature::Descend`'s levitation branch makes that request from depth 10. Loads `tools/fixtures/chars/levitate-bottom-seed1.sav`, a character frozen levitating on a depth-10 chasm (a generated depth 10 is not reproducible across an unrelated change, so this check loads one rather than walking to it fresh), presses `>`, and expects the climb-down prompt and a 100m depth reading. | LIVE |
| `check_dup_names.sh` | Does the resource compiler reject a same-case duplicate resource name, with its own duplicate-name diagnostic? | LIVE |
| `check_dwarven_thrower_throwable.sh` | Is the Dwarven Thrower's base item a throwable, non-generated hand-copy of the ordinary warhammer, so the artifact can actually be thrown? | LIVE |
| `check_earth_ring_prose.sh` | Does the Ring of Elemental Command (Earth) description name the wearer's own ring "the ring of earth" in its curse clause, rather than the "ring of air" it copied from the Air ring? | LIVE |
| `check_earthsinger_live.sh` | Does the Earthsinger admit the rock gnome its own refusal message names? | LIVE |
| `check_enchant_graceful.sh` | Do seven compiled item pages advertise their own qualities, caster-level gates, spells and bonus type? | LIVE |
| `check_entangle_escape.sh` | Can a character in heavy armour tear out of glue? A paladin in full plate and a kite shield sits at Escape Artist -11 against a DC of 14, so his ceiling of 9 is five below the floor and no roll closes it. The check requires a *Strength* check that succeeded, not merely an escape, because `src/Skills.cpp:1600` already frees him on a natural 20 while no hostile is within sixteen squares. | LIVE |
| `check_entangled_acts.sh` | Does passed-save entanglement penalize without disabling? Requires an unanchored rogue, Dexterity 17 to 13 and melee to-hit +2 to +0 on the sheet, then a melee attack and a half-speed move while still entangled, measured against the same subject's own post-combat floor-move cost. | LIVE |
| `check_erich_speaks.sh` | Are the five `MSG_CUSTOM1` through `MSG_CUSTOM5` messages Erich's own script (`lib/religion.irh`) calls still live in his `GODSPEAK_LIST`, rather than sitting disabled inside its `#if 0` block? | LIVE |
| `check_error_handling.sh` | Did anyone reintroduce the `Error()` buffer overflow or the modal freeze? | LIVE |
| `check_escape_sweep.sh` | Does any string literal still spell a C escape with a forward slash, the way the port's path sweep wrote `/n` for `\n`? | LIVE |
| `check_eyes_soul_prose.sh` | Does the Eyes of the Soul description name the Necrophysiology feat the item grants via `EXTRA_FEAT FT_NECROPHYSIOLOGY` -- the feat that lets its holder crit, sneak attack and coup de grace undead -- rather than omitting it as the prose did before? | LIVE |
| `check_favour_awards.sh` | Do the five favour awards the engine makes in C++ reach the god? `Creature::gainFavour` took an int16 amount and `Character::gainFavour` an int32 one, so the character's version hid the base instead of overriding it, and the favoured-skill, Khasrach and Zurvash devour, and Semirath trap awards all landed in an empty base body. Four sessions from frozen characters read the patron's favour off the character sheet either side of each award, and require it to rise by the amount the code computes from the printed roll or the creature's challenge rating. | LIVE |
| `check_favour_int32.sh` | Does a favour total over 32767 survive the round trip through `EV_CALC_FAVOUR`, instead of wrapping negative? The script view of `EventInfo::EParam` was int16 while the field is int32, so favour levels 7, 8 and 9 were unreachable. | LIVE |
| `check_feat_toggle.sh` | Do two presses of the feat toggle key toggle twice without spending a pick? | LIVE |
| `check_field_day_duration.sh` | Does a permanent (`Dur -1`) field still survive a day change? It places a torch archon on depth 2, rests one night on the same map with lowercase `z`, and counts the map's fields either side; the rise in creatures proves `Map::DaysPassed` actually ran. Fixed 1 -> 1, unfixed 1 -> 0. | LIVE |
| `check_field_grant_readers.sh` | Do all five families of modifier reader still route through the shared redundant-field-grant predicate, rather than one of them drifting back to summing duplicates? | LIVE |
| `check_field_modifier_duration.sh` | Does a living, directly placed torch archon retain both its permanent white light field and its Magic Circle vs. Evil status after the broken 12-turn countdown would have expired many times over? | LIVE |
| `check_fiendish_servant.sh` | Does the Blackguard's Fiendish Servant summon a creature when cast from the spell manager, rather than printing "Nothing happens"? | LIVE |
| `check_fire_hardness.sh` | Do wood, leather and cloth have zero fire hardness while ironwood, darkwood and dragon hide retain theirs? | LIVE |
| `check_fire_ring_resist.sh` | Does the Ring of Elemental Command (Fire) grant the Fire Resistance of 10 its page promises, rather than the 12 its grant was coded? | LIVE |
| `check_flame_strike.sh` | Does Flame Strike's description state `1d6` points of damage per caster level, matching its SRD-authentic `(LEVEL_SCALED)d6` script rather than the `1d8` prose it carried before? | LIVE |
| `check_flame_tongue_large.sh` | Does the flame tongue sword's tongue-of-flame lash yank a Large corporeal creature, matching its page's "a Large or smaller corporeal creature", rather than excluding Large by an off-by-one `>= SZ_LARGE` size gate? | LIVE |
| `check_flame_tongue_range_prose.sh` | Does the flame tongue sword description state its Tongue of Flame reach as a 30-foot base plus 10 feet per point of Charisma modifier (minimum 30 feet), matching its `e.vRange = 3 + max(0, Mod(A_CHA))` squares code at 10 feet per square, rather than the "Charisma modifier times ten in feet (minimum 20)" it claimed before? | LIVE |
| `check_flame_tongue_undead.sh` | Does a flame tongue sword set a corporeal undead alight for the 3d6/2d6/1d6 fire its page promises? | LIVE |
| `check_flavor_stability.sh` | Does a v1 save's per-player flavour memory -- appearances and their Known/Tried flags -- survive a module rebuild that adds a resource? | LIVE |
| `check_fork_release.sh` | Does the release number the game prints on its title page match the release actually cut? `FORK_RELEASE` (`inc/Defines.h`) is compiled in and nothing derives it, so it only changes when somebody remembers; release 4 was signed and notarised still saying "release 3". The oracle is the highest `release-N` git tag. | LIVE |
| `check_format_strings.sh` | Does every printf-style format string in the engine agree with its arguments, or has the warning count risen above the baseline? | LIVE |
| `check_gate_membership.sh` | Does every check in this directory declare whether the gate should run it? Each carries `# gate: cheap`, `# gate: live` or `# gate: none <why not>` in its first 40 lines, and `nightly_verify.sh` reads those markers instead of a hand-written list. `gate_membership.baseline` excuses the 206 checks that predate the rule and only shrinks. Proves itself with `--selftest`. | LIVE |
| `check_gaze_reflect_message.sh` | When a gaze attack is turned back on the monster that made it, does the sentence on screen name that monster once and read as English? A mage casts Gaze Reflection on himself, the character sheet's Specials column is photographed as proof he carries it, a bodak is summoned, and the message area is read: "The bodak's gaze is reflected back at it!". It is the live twin of `check_xprint_tokens.sh`, which counts tokens in source text and cannot see what a player is shown. | LIVE |
| `check_gcc_o2_char_create.sh` | Does a GCC `-O2` build still play character creation into a map, or has the `Item` constructor's uninitialised-member miscompile (inc-nw0v) returned? Needs Docker and builds with GCC, the converse of `check_linux_build.sh`. | LIVE |
| `check_gear_bypass_survives.sh` | Does a resistance spell still protect a plain weapon, where the attack bypasses the metal's own hardness? Under Protection from Acid a mundane iron maul holds 262 hit points through twelve magma creeper retaliations. | LIVE |
| `check_gear_item_exclusion.sh` | Does an item ruled wearer-only leave gear exposed? The Amulet of Bile grants acid resistance and the same warhammer still corrodes. | LIVE |
| `check_gear_protection_roster.sh` | Does `lib/` still match the whole `EF_PROTECTS_ITEMS` ruling table? Holds the 36 effects the repo owner ruled protect carried gear, the 22 grants he ruled wearer-only, and his two general rules -- spells are `y`, domains and gods and races and subraces are `n`. `gear_protection_roster.py` does the measuring; `--prove-red` breaks each part in turn and demands that part's own verdict line turn red. Red today on part C1, which names two unflagged priest spells for his ruling. | LIVE |
| `check_gear_spell_protection.sh` | Does a spell protect the caster's gear? Under Endure the Elements his silvered warhammer holds 78 hit points through twelve magma creeper retaliations. | LIVE |
| `check_generated_merge.sh` | Does Git conflict on independent edits to `lib/dispatch.h` with the shipped merge guard, but cleanly merge both edits without it? Uses throwaway repositories; tests Git, not the compiler (inc-m1wb). | LIVE |
| `check_geomancy.sh` | Does the Earthsinger's Geomancy roll the 5d12 its page names, rather than the 5d12+12 copied from the Mana potion? | LIVE |
| `check_goblin_queen_prose.sh` | Does the Staff of the Goblin Queen description scope its +4 bonuses and -4 penalties to goblinoid wielders, matching the all-or-nothing goblinoid gate that governs every effect? | LIVE |
| `check_gravestone.sh` | Does the death screen render the epitaph's corrected wording and columns, and the date the stone is carved with? | LIVE |
| `check_grounded_stance_live.sh` | Does the Earthsinger's Grounded Stance add its damage term to a landed blow when every condition it names is met? | LIVE |
| `check_headless.sh` | Do the five properties every unattended run depends on still hold? | LIVE |
| `check_heal_maladies.sh` | Does the priest spell Heal remove the maladies its own description promises? It promised poison, disease and stunning and removed nothing at all. A test god afflicts the player with nine maladies at once; he then learns Heal in wizard mode and casts it on himself. A second measurement has him paralyse a kobold with Hold Person and cure that, because a paralysed character cannot cast on himself. The unfixed declaration leaves all ten standing. | LIVE |
| `check_hide_carried_light.sh` | Can a creature carrying a lit light source still hide in shadows (it must not)? | LIVE |
| `check_hide_dynamic_light.sh` | Does a creature hiding in a cell lit only by a dynamic external source -- magma, a live wall torch, or another creature's torch, with no static `.Bright` and no carried light -- get its hide broken and warned? | LIVE |
| `check_holy_avenger_dispel_cl.sh` | Does the Holy Avenger's on-hit dispel use the wielder's paladin level as its caster level, rather than a hardcoded 12? | LIVE |
| `check_holy_undead.sh` | Does a Holy weapon, and holy damage, smite an undead creature that is not evil? Seed 4 gives a neutral zombie-templated black bear as the subject, an evil mummy as the positive control and a living neutral brown bear as the negative one. | LIVE |
| `check_horn_goodness_radius.sh` | Does the Horn of Goodness' Magic Circle vs. Evil field have its promised 60-foot (six-square) radius? | LIVE |
| `check_horn_madness.sh` | Does the Horn of Madness drain and stun a bystander while sparing its blower from both halves? | LIVE |
| `check_horn_panic.sh` | Can the Horn of Panic frighten a failed-save bystander while sparing its blower? | LIVE |
| `check_horn_plenty_prose.sh` | Does the Horn of Plenty entity declare exactly one description, and does it name the fatigue cost its `LoseFatigue(4)` code charges, rather than the duplicate fatigue-less second description it carried before? | LIVE |
| `check_horn_sewers_cr.sh` | Does the Horn of the Sewers' description state its summoned rodents have CR twice its magical plus? | LIVE |
| `check_hornblade_roaring.sh` | Does the Hornblade carry no noise-making `WQ_ROARING` quality, which would contradict the concealment design its description and `EF_HIDEQUAL` flag build? | LIVE |
| `check_hunger_penalty.sh` | Does getting hungrier still make a character stronger? Photographs one Dragonkin fed, Hungry and Starving, and refuses an order in which Hungry costs more than Starving. | LIVE |
| `check_huntsman_live.sh` | Does the Twilight Huntsman reach his own spell list, smite Law rather than Good, and track at the ranger's rate, serving the ranger's opening bonus once rather than twice? | LIVE |
| `check_illus_refund.sh` | Does the illusory-damage refund still clamp to the maximum, instead of paying above it and stranding a character at 58/56? | LIVE |
| `check_illusion_flags.sh` | Does an illusion's declared IL_IMPROVED flag decide who pierces it, rather than the parity of its save DC? | LIVE |
| `check_item_flag_protection.sh` | Do Bracers of Neutralization keep an iron maul at 262/262 HP against acid-blob retaliation through EF_PROTECTS_ITEMS? | LIVE |
| `check_item_hardness.sh` | Does Item apply hardness modifiers once after preserving immunity, with QItem delegating? | LIVE |
| `check_item_owner_resist.sh` | Does item damage use its own defences without owner resistance or immunity? | LIVE |
| `check_item_type_id.sh` | Does identifying one item teach its kind for every flavoured type, so the next of that kind arrives already named? | LIVE |
| `check_javelin_lightning_savedc.sh` | Does the Javelin of Lightning's Reflex save use the DC its description promises? | LIVE |
| `check_key_directives.sh` | Do the screen-driven key-script directives `@choose`, `@cursorto`, `@cursorto:mark` and `@expect` reach a menu entry that counting could not? | LIVE |
| `check_ki_strike_live.sh` | Does the module grant a Monk Ki Strike? One session photographs the character sheet's Special Abilities block at 1st level and again at 4th: nothing, then `Ki Strike +1`. Reads a compiled module, so a red run after editing `lib/` usually means `./incursion -compile main.irc` was not run. | LIVE |
| `check_killing_hands.sh` | Do Bracers of Killing Hands pay two points per plus to both unarmed accuracy and damage? Equips a known, identified +2 pair and requires +4 on both lines of the sheet's Brawl block. | LIVE |
| `check_kobold_horn.sh` | Does the Horn of the Kobolds, blown by a non-kobold wielder, summon hostile kobolds as its page promises, rather than the friendly ones the bare `EA_SUMMON` always gave? | LIVE |
| `check_layout.sh` | Does this build play the same game when its objects sit at different addresses? | LIVE |
| `check_layout_sweep.sh` | The same question over many seeds and key scripts, which is the only form of it that can close the inc-dhc class. Builds the probe binary itself and runs with the builds in `nightly_verify.sh`. A seed whose session bought too little game time is reported as unmeasured, never as a pass. | LIVE |
| `check_ledger_rows.sh` | Does every ledger row in `docs/REPORTING-GATE.md` sit under the heading whose column shape it has, so no tracking id is dropped? | LIVE |
| `check_libtcod_mode_change.sh` | Does libtcod recalculate its copy rectangle after a display mode change, so the console is not left clipped to the size of the window before it? Needs a real display and takes over the screen for a moment, so it runs with the builds and not in the ratchet. | LIVE |
| `check_life_stealing_prose.sh` | Does the ball Wand of Life Stealing description state that its necromantic damage scales per plus, matching its `pval: (PLUS_1PER1)d6` code, rather than the flat "1d6 points of necromantic damage" it claimed before? | LIVE |
| `check_light_averse.sh` | Does a light-averse creature take its -4 combat penalty and squint in a cell lit only by a dynamic external source, and neither in a merely dim cell? | LIVE |
| `check_light_filter.sh` | Does light lose strength and colour crossing an ice wall? Two sessions differ by one terrain letter, and the cell two steps beyond must read dimmer through the ice than through open air. | LIVE |
| `check_light_fog.sh` | Does light pass through a cloud of fog, dimmed, instead of stopping at it? One session dumps the same cell before and after a Stinking Cloud is cast across it, and the cell must fall from `3` to `1` — it fails both if the cell does not dim and if it goes dark, because a dark cell means the light map is again asking whether an eye could see through rather than whether light passes. | LIVE |
| `check_light_trim.sh` | Do the two display-only lighting options, `OPT_LIGHT_EXPLORED` and `OPT_LIGHT_BRIGHT`, draw exactly the old picture at Normal and move it at every other setting? Also that neither shifts a cell's hue, that brightening cannot clip a channel, and that a corrupt option byte falls back to Normal. Links a probe against the built `Light.o`, so it measures the shipped arithmetic and needs no seeded session. | LIVE |
| `check_lightmap.sh` | Does the light map obey line of sight — no lit cell that no source can reach through walls — and does a carried light light its bearer? | LIVE |
| `check_line_of_fire.sh` | Does the saving-throw cover-and-band rule for a weapon shot hold -- a -4 penalty per occupied square between shooter and target, a further -4 for the target's own square when the target is not its head, one roll, and a miss resolved by a per-square Reflex save walking the band in contents-chain order? Oracle is `LineOfFireProbe` (`src/Fight.cpp`) under `INCURSION_LOF_PROBE`, throwing a forced-roll dagger down a five-rat line. | LIVE |
| `check_line_of_fire_effects.sh` | Do the 15 bolt/ray effects the line-of-fire rework touches carry `EF_ATTACK` and the right save field, while Call Companions gains neither and Magic Missile, Force Missiles and Acid;wand still carry no `EF_ATTACK`? Pure text over `lib/*.irh` via `tools/line_of_fire_effects.py`, no build needed. | LIVE |
| `check_line_of_fire_spell.sh` | Does the same cover-and-band rule apply to an `EF_ATTACK` spell bolt rolled against touch defence, while an effect with no `EF_ATTACK` (Magic Missile) passes every body in the line unerring and a beam still strikes everyone? Oracle is `LOFSpellProbe` (`src/Magic.cpp`) under `INCURSION_LOF_SPELL_PROBE`, casting Eldritch Bolt down the same five-rat line `check_line_of_fire.sh` uses. | LIVE |
| `check_linux_build.sh` | Do both backends still build on Linux, and does a seeded run still play with no errors? Needs Docker; so does `check_gcc_o2_char_create.sh` below, and no other check. | LIVE |
| `check_load_corrupt.sh` | Does the real binary refuse ten hand-corrupted saves cleanly and still load two genuine ones? | LIVE |
| `check_logrotate.sh` | Does log rotation keep the right archives and prune only names it made itself? | LIVE |
| `check_loremaster_live.sh` | Does the Loremaster's Bibliographic Insight add its extra attribute points when he reads a tome? | LIVE |
| `check_luckblade_plus.sh` | Does the Luckblade keep its magical plus when the wish it would charge for is refused, rather than grinding down first? | LIVE |
| `check_lz_uncompress.sh` | Can the LZ77 and RLE decoders be made to write past their output buffer? | LIVE |
| `check_mana_regen_cast.sh` | Under real play, no forced state: a mage casts Burning Hands 35 times to bring mana into the 35-80% band the regen floor cares about, waits about 75 turns without resting, and stays at the same mana -- rather than rising, which is what the un-fixed floor would let happen. | LIVE |
| `check_mana_regen_floor.sh` | Does the player mana-regen floor start high and fall with Concentration, rather than starting low and rising? Forces Concentration low then high on a live loaded player and drives 50 real ticks through `Creature::DoTurn`. | LIVE |
| `check_masterarcher_live.sh` | Does the Master Archer's Ranged Sneak Attack fire only with a long bow or a short bow, and not with every launcher? | LIVE |
| `check_menu_overflow.sh` | Does a menu with more than 52 options still draw and select every row, rather than losing the ones past the alphabet? | LIVE |
| `check_menu_page_arrows.sh` | Does the RIGHT arrow page a long selection menu forward, so a Steam Deck player who has a stick but no Tab key can reach a row on the second page and still pick it? | LIVE |
| `check_menu_value.sh` | Does a script menu give back the same object handle it was handed, above the 16-bit line? | LIVE |
| `check_minor_drain_touch.sh` | Does Minor Drain, now a touch spell, refuse a distant target and a bare square, and still fire its heal on a successful touch? `tools/keys/minor-drain-touch.keys` places a goblin out of melee reach, casts, then closes and bump-attacks until the touch-only `A_TUCH` message lands; the no-prompt refusal itself is proved structurally by `check_line_of_fire_effects.sh`. | LIVE |
| `check_mirrored_lane.sh` | Does a `mirrored` bead stay off everything that WRITES to GitHub, while its open or closed state is still reconciled? Drives the real `sync_issues.sh` with `bd` and `gh` stubbed, then reads the id list handed to `bd github sync`. A regression here silently replaces an outside reporter's issue body with ours. `--selftest` proves the check bites. | LIVE |
| `check_module_rebuild.sh` | Does an ordinary build put this tree's scripts into the game, while an instrumented build still leaves the module alone? | LIVE |
| `check_monster_memory.sh` | Does the game record what the player has met, and show him only that? Recalls one creature's entry from a character who has met nobody, then from one who has killed ten, and reads the save's own `MonMem` rows through `tools/dump_save.sh` to keep Seen, Fought and Kills apart -- a kobold only looked at, an ogre struck once, ten humans killed. Before inc-q98a nothing wrote any of those fields and `Monster::Describe` read a hardwired perfect record, so every creature's complete entry was visible from turn one. | LIVE |
| `check_mundane_autopickup.sh` | Does autopickup keep an EF_MUNDANE item -- holy water, tanglefoot bags, the alchemy line -- out of the pack, while still stowing the same drop's unidentified potion? | LIVE |
| `check_natural_save.sh` | Does a natural 20 on a saving throw always succeed, and a natural 1 always fail, regardless of Bonus + roll vs DC? Reads the printed `Save: 1d20 (roll) ... [success\|failure]` line from many seeded sessions -- DC 15 tanglefoot strands for volume, DC 27 guardian runes (a level 1 paladin's own bonus cannot reach it) for the edge case a modest DC can never supply. | LIVE |
| `check_natural_speed.sh` | Has the hard-coded brawl-speed floor drifted from the fastest weapon in `lib/weapons.irh`? Reads the data; runs nothing. | LIVE |
| `check_natural_speed_live.sh` | Does flipping one byte of `Options.Dat` really move the Brawl row on the character sheet, 100% to 175%? Refuses to pass if a run never entered a map. | LIVE |
| `check_nonnormal_invariant.sh` | Is non-normal detection (an infravision character in darkness) byte-identical across the inc-jcg4 unified-light change over seeds 1-10? | LIVE |
| `check_open_xy.sh` | Does `Map::GetOpenXY` refuse when no square is open, instead of answering (0,0)? Requires the `NO_OPEN_XY` sentinel to be returned and `Thing::PlaceOpen` to drop the Thing rather than place it in the map's solid outer edge. Three static greps plus a probe build (`EXTRA_CXXFLAGS=-DINCURSION_OPENXY_PROBE BACKEND=posix ./build_macos.sh`, binary named by `INCURSION_BIN`) that counts refusals, disposals and a successful-placement control -- the greps alone once passed a fix that tested the sentinel and then placed at (0,0) anyway. | LIVE |
| `check_opencode_ds.sh` | Does `tools/opencode_ds.sh` refuse to launch once the DeepSeek ledger says the budget is gone or poisoned, refuse the shared checkout, bill exactly one row for a successful harness run (cost summed from its `step_finish` events, steps counted), poison the ledger when opencode quotes tokens but no usable cost, keep the DeepInfra key out of every file it writes, and confine opencode to the worktree with the Seatbelt profile (inc-h1bq)? | LIVE |
| `check_options_migrate.sh` | Does an options file written before an option existed come up on that option's real default rather than its first menu choice, and does a setting the player chose on purpose survive? The file has no header, so `OPT_SETTINGS_GEN` is the only thing separating "never chosen" from "deliberately set to the first choice". Links against `OptionsGen.o`, which has no undefined symbols, so it needs no stubs and no session. | LIVE |
| `check_orphan_branches.sh` | Is every finished fix actually on master? It lists each branch master has not merged beside its bead's status and age. It fails on a branch whose bead is closed — the shape that stranded b855fe2 for days — and on a branch whose name is not a bead id, because nobody can then say what it was for. | LIVE |
| `check_overlapping_modifier_fields.sh` | Do two torch archons that each stand inside the other's magic circle both keep their light field when they separate, and does each end up holding exactly one circle row? Fixed 2 lit, unfixed 0. | LIVE |
| `check_package.sh` | Is the packaged folder free of ACCENT symbols and Homebrew paths, and does it carry its data? | LIVE |
| `check_package_parity.sh` | Does every packager ship every directory the game reads at run time? `graphics/logo.png` landed in only `package_linux.sh`, so release 4's macOS downloads fell back to the ASCII title while Linux, the Deck and Windows showed the real logo, and nothing failed: the fallback is silent by design. This reads the packager scripts rather than a built folder, so it also speaks for the platforms this machine cannot build, and a new packager that is not listed in it is itself a failure. | LIVE |
| `check_pad_help.sh` | Does the `?` screen name the pad control beside each key (`Look ... D-pad > (l)`) when a controller is in front of the game, fit on the screen without an assertion, and stay keyboard-only when none is? The headless build forces the pad screen with `INCURSION_PAD_HELP=1`. | LIVE |
| `check_palettes.py` | Do the colour palettes hold sixteen distinct entries, does each colour share a hue with its `BRIGHT_MASK` partner, and do `src/Wlibtcod.cpp` and `src/Wcurses.cpp` agree on every palette they both carry? The curses backend compiles on neither macOS build, so this is the only guard on its copy. | LIVE |
| `check_pass_record.sh` | Does a landing reuse a full gate pass on the same files, and only then? Copies `nightly_verify.sh`, `finish_bead.sh` and `docs_only_change.sh` into a scratch repository beside a fake build that counts its calls, then lands scratch beads: an interrupted landing and a gate run before the commit must build nothing, while one changed byte, a master that moved, a changed base or toolchain, and a stale, malformed or missing record must build twice (inc-689z); a landing driven from inside its own worktree must also land and delete both the branch and the worktree (inc-5b76). | LIVE |
| `check_periapt_closure_prose.sh` | Does the Periapt of Wound Closure description drop its false "removes infections" claim, keeping only the two effects the entity truly provides -- stop bleeding and speed healing? | LIVE |
| `check_periapt_poison_prose.sh` | Does the Periapt of Proof against Poisons description state that its saving-throw-versus-poison bonus scales per magical plus, matching its `PLUS_2PER1` code, rather than the flat "+2" it claimed before? | LIVE |
| `check_periodic_interval.sh` | Does a PERIODIC status effect fire every Val rounds, not Val-1? Two synthetic gods grant Val 3 and Val 5 timers; fixed, both fire on an even 180- and 300-turn beat across at least three firings apiece, where an unfixed build reads 120 and 240. | LIVE |
| `check_planes_sword_prose.sh` | Does the Sword of the Planes description scope its +3 enhancement tier to outsiders generally, matching its `EV_WATTACK` handler's `MA_OUTSIDER` branch, rather than the narrower "denizens of the ethereal or astral planes" it claimed before? | LIVE |
| `check_portal_reach.sh` | Does every portal on a generated level share one door-aware passable component with every other portal, so a staircase never lands the player inside a sealed pocket? Sweeps 20 seeded dives, judging only the KEPT level per depth after `Map::RepairStrandedPortals`' corridor search and `src/Feature.cpp`'s discard-and-regenerate retry have had their say. Measured: 9 of 156 generated levels stranded a portal before the fix, 0 of 157 after. `--prove-red` runs the same measurement with `INCURSION_PORTAL_REPAIR_OFF=all` and PASSES only when the check FAILS -- proof this guard can be shown red, not only green. | LIVE |
| `check_pray_aid_int32.sh` | Does praying for divine aid still grant anything above 32767 favour? `Character::Pray` took the total into an int16 local, so every `AID_CHART` threshold comparison failed past the wrap and the follower got nothing. Sibling of the row above, and a different narrowing: that one is the script view of `EParam`, this one is a C++ local. | LIVE |
| `check_precision_prose.sh` | Does the Eyes of Precision description state that its lowlight-vision bonus scales at 20 feet (2 squares) per magical plus, matching its CA_LOWLIGHT `PLUS_2PER1` code, rather than the flat "20 feet" it claimed before? | LIVE |
| `check_prestige_hidden.sh` | Are the eight unfinished prestige classes kept out of every class list, rather than offered and then refused after the pick? | LIVE |
| `check_prestige_profs.sh` | Does a prestige class grant the weapon and armour proficiencies its own prose promises? | LIVE |
| `check_prestige_tables.sh` | Does each prestige class print the save columns and the defence track its own fields give? | LIVE |
| `check_probe_hooks.sh` | Does every debugging hook shipped in the game name a bead, or has an undeclared hook appeared outside the baseline? | LIVE |
| `check_ptr_sweep.sh` | Does `sweep_ptr_order.sh` still find a pointer ordering, and still ignore a pointer equality? | LIVE |
| `check_python_rod_prose.sh` | Does the Rod of the Python carry a description at all, and does it name its per-plus poison-save bonus, its per-plus Constitution bonus and its three-times-daily transformation into a boa constrictor, matching its `SN_POISON`, `A_CON` and boa-summoning code? | LIVE |
| `check_quality_self_immune.sh` | Is an armour with a resistance quality immune to that element, while its wearer still gets the resistance? A +0 leather suit of fire resistance holds 56 hit points where the plain one is left mildly burnt. | LIVE |
| `check_quiet_lookup.sh` | Does a dead object handle resolve silently where silence is correct, and still complain where a complaint is correct? | LIVE |
| `check_race_feats.sh` | Does a Dragonkin get Mantis Leap on the character sheet? | LIVE |
| `check_readline_overflow.sh` | Does `TextTerm::ReadLine` refuse the 161st character of a text prompt instead of writing past the end of its 160-byte `Input` buffer? Content half: the longest run typed into the character sheet's dump filename stays at 159 (`sizeof(Input) - 1`) rather than reaching the full 161 typed. Structural half, when `./incursion-ubsan` is built: UndefinedBehaviorSanitizer reports no out-of-bounds write to `Input[]`. | LIVE |
| `check_readme_checks.sh` | Was a regression check added with no row in the `README.md` check table? Ratcheted against `tools/readme_checks.baseline`, which holds the 58-row backlog. | LIVE |
| `check_reapply_single_grant.sh` | Does a worn item keep granting exactly one copy of its bonus when the game re-applies it? Magic Weapon on an orc's Bloodspear, the boost wearing off, Storycraft raising a periapt's plus and a dispel ending must all leave one copy: the Bloodspear read `+4 vs. spells`, then +8, then +12 before the fix. The same run proves the fix keeps an activated Nine Lives Stealer active, loses no unrelated condition to Dispel Magic, and cannot kill a bard at 7 HP. | LIVE |
| `check_retributive_mirror.sh` | Does Retributive Mirror reflect one third of incoming damage (`e.vDmg / 3`), the fraction its own description promises, rather than the one fifth it paid before? | LIVE |
| `check_reveal_delete.sh` | Can a monster still delete itself inside `Reveal()` and leave the caller holding a dangling map pointer? | LIVE |
| `check_rider_corpse.sh` | Does a natural attack's rider clause stop when its victim is dead, rather than striking a corpse and dangling a map pointer? | LIVE |
| `check_ring_command_level.sh` | Do the Rings of Elemental Command grant the 12th-level, +6 command power their pages promise, not 10th level and +5? | LIVE |
| `check_ring_fire_curse.sh` | Does the Ring of Elemental Command (Fire) curse amplify cold damage alone, rather than rewriting every wound its wearer takes to cold? | LIVE |
| `check_ring_fire_terrain.sh` | Can a Ring of Fire Resistance wearer cross magma while the same character without the ring is still refused? | LIVE |
| `check_ring_preservation_page.sh` | Does the Ring of Item Preservation's page describe the ward the ring actually is, rather than the extradimensional transport that never happens? | LIVE |
| `check_ring_water_command.sh` | Does the Ring of Elemental Command (Water) grant command of water creatures, its page's element, rather than fire? | LIVE |
| `check_rng_split.sh` | Does a random draw made for the screen leave the gameplay stream where it was? Burns 37 draws off the cosmetic stream and requires the seeded session to be byte-identical; then burns ONE off the gameplay stream and requires it to differ, so the comparison cannot pass by being blind. Guards `cosmetic_int32` (`src/Base.cpp`), which exists because `Character::GodMessage` once drew once per character of its message text and rewording a line of flavour text changed what a seed meant. | LIVE |
| `check_robe_eyes.sh` | Does the Robe of Eyes grant the 60 feet of infravision its page promises? | LIVE |
| `check_rod_longsword_plus.sh` | Does the Rod of Lordly Might's labeled +1 flaming long sword grant exactly +1 to real to-hit and damage? | LIVE |
| `check_rod_lordly_might.sh` | Does the Rod of Lordly Might's paralyzing touch grant the three charges its page promises, rather than seven? | LIVE |
| `check_rules_channel.sh` | Does the rules channel that replaced the truncating SessionStart hook still actually deliver the rules? A hook payload the host judges too large is replaced by a 2 KB preview and written to a file nobody reads, so the project's rules never reach the session; the failure is silent and sits on the delivery side, not in the content. It runs and measures every registered SessionStart hook against a 9,000-character budget, and asserts that `CLAUDE.md` imports `AGENTS.md`, that `.claude/rules/` holds at least one `*.md` file, and that no instruction file exceeds the memory loader's own 4 MiB skip threshold. | LIVE |
| `check_sacrifice.sh` | Does a god's altar read the rows BELOW `MA_ALL`, and refuse what it should refuse? | LIVE |
| `check_sanctuary_strike.sh` | Does Sanctuary end when the creature it wards throws a melee blow, and survive a turn spent on anything else? | LIVE |
| `check_save_fail.sh` | Does a save that fails part-way leave the game playable? Stages the throw with `INCURSION_SAVE_FAIL_AT` at a chosen object or data block. It does not drive a real disk-full, and cannot: every write goes into a memory `CFile` and the disk is untouched until `CommitCompressed`, so a full disk can only fail once every object is already converted. That case was reproduced by hand instead. | LIVE |
| `check_save_pad_rows.sh` | Does every `SchemaPad` row in `src/SaveV1.cpp` still match what the compiler actually lays out, rather than what was hand-measured last time a member moved? Runs `tools/save_pad_rows.py`'s own compiler-derived measurement and compares it array by array against the source; `--selftest` inserts an unarchived member into a scratch copy of `inc/Creature.h` and confirms the check goes red naming `Creature` and its descendants. | LIVE |
| `check_schema_roundtrip.sh` | Does each class group of the v1 save schema round-trip field for field, and write a byte-identical second file? | LIVE |
| `check_school_focus_dc.sh` | Does School Focus (Illusion) still raise the DC to disbelieve an illusion? The same mage casts Phantasmal Force at a goblin, and the printed `Will Save: ... vs DC 13` line is the oracle -- the only place a player can read that DC. Unfocused it is 11. | LIVE |
| `check_school_focus_menu.sh` | Is a school the character already focuses on kept off the School Focus menu? One orc mage takes the feat twice: Illusion is on the first menu and must be gone from the second, and the character sheet must list both schools, because School Focus is worth nothing taken twice in one school. A second run makes an elf, whose menu must still be short of Necromancy -- the other rule living in the same line. | LIVE |
| `check_sentinel_live.sh` | Does the Sentinel's engine-side save track match the table it prints? Makes one, four levels deep. | LIVE |
| `check_shadow_shifting.sh` | Does the Cloak of Shadow Shifting require darkness at both ends without charging a refused activation? Statically guards the source-before-charge and both destination paths until a headless behavioral scenario can replace it. | LIVE |
| `check_shadowstone_page.sh` | Does the Shadowstone page name the stone and state that its Hide bonus is twice its magical plus? | LIVE |
| `check_shared_checkout_gate.sh` | Does `.beads/hooks/pre-commit` still refuse new work in the shared checkout, and still let the overnight harness commit on its own `nightly/` branch? Ten cases run against a scratch repository under `TMPDIR`, six that must be refused and four that must be allowed, so a hook that never runs fails as loudly as a hook that refuses everything. The harness is admitted only when `NIGHTLY_BRANCH` names the branch HEAD is actually on, which is a variable one process tree holds and no second session in that directory has. When the publish check finds an unfit bead, the hook warns the harness and refuses everyone else. | LIVE |
| `check_sharp_senses.sh` | Does the Sharp Senses bonus reach Search, and not only Spot and Listen? | LIVE |
| `check_shield_penalty.sh` | Does a shield's armour check penalty come from the shield, or only from its size beside yours? Puts every shield in a Medium paladin's hand one at a time and reads its cost twice off the character dump -- the skill term and the movement rate -- then does the two a Small halfling can hold, whose figures must be double. | LIVE |
| `check_shift_opcodes.sh` | Does the VM's BSHL shift left while Rect member codegen still uses BSHR for reads and BSHL for writes, and does a script-coloured field cast red rather than black light? | LIVE |
| `check_sigpipe_status.sh` | Does any `tools/*.sh` pipe into an early-exit reader (`grep -q`/`grep -m`/`head`) whose exit status a conditional then reads, the shape whose SIGPIPE race reported real data as a miss on 2026-09-22? Ratcheted against `tools/sigpipe_status.baseline`. | LIVE |
| `check_skill_manager_reset.sh` | Does an unrecognised key still wreck the Skill Manager? Presses END and HOME -- the left stick's two left diagonals -- in both of the screen's modes: character generation, where the ranks were wiped, and level-up, where the manager silently closed. Two sessions. | LIVE |
| `check_snowstrike.sh` | Does the Snowstrike blast carry `EF_CASTER_IMMUNE` and `EF_ALLIES_IMMUNE`, so the caster and her allies are immune as its description promises, rather than freezing them? | LIVE |
| `check_spell_god_drift.sh` | Does a v1 save refuse a reloaded module only on positive evidence that entries moved, while a pure rename still loads? | LIVE |
| `check_spook_ally.sh` | Does Spook spare its caster's own side, and does a creature made immune inside a field still shed the stati when it leaves? | LIVE |
| `check_spook_mount.sh` | Does a mount keep the aura it emits across being ridden and carried between levels, and keep owning it? | LIVE |
| `check_springblade.sh` | Does deploying the Springblade Bracers require a Handle Device check, and does its free off-guard strike fire only once per combat? | LIVE |
| `check_springblade_label.sh` | Does the Springblade Bracers type-3 pair name both of its +2 elemental blades accurately? Seed 6 reads the rolled suffix from the activation menu. | LIVE |
| `check_stacked_abilities.sh` | Do abilities whose prose says their levels stack across classes actually stack, charging one waiting period rather than one per class? Five characters: a Rogue 6 invariant, a Barbarian 3 / Rogue 3, a Bard 7 / Assassin 4, an Elf Rogue 7 / Assassin 3 and a control. | LIVE |
| `check_staff_abyss_alignment.sh` | Is the Staff of the Abyss inert in a good character's hands, and still whole in a non-good one's, as its page says? | LIVE |
| `check_staff_abyss_spell_list.sh` | Does the Staff of the Abyss's page name only the nine spells it actually grants, without the three that have nothing behind them? | LIVE |
| `check_staff_winter_grants.sh` | Does the Staff of Winter hand over all four powers its page promises -- the cold spells, and the Charisma, Intimidate and Appraise numbers? | LIVE |
| `check_staff_winter_quality.sh` | Does the Staff of Winter carry the weakening quality its page names, rather than the numbing quality the script gave it? | LIVE |
| `check_stair_cycle.sh` | Does the overview map's staircase search run, pick the cheapest, and wrap? | LIVE |
| `check_stair_warn.sh` | Does descending an ordinary staircase skip the false unsafe-terrain warning, rather than asking to confirm every descent? | LIVE |
| `check_sticky_save.sh` | Does walking onto a pool of slime roll a real Reflex save, and does the STUCK it grants lapse on its own? The DC must print above zero (`SavingThrow` prints nothing at all for `DC <= 0`), and the printed roll line must change after 100 turns of nothing but waiting -- proof a second roll fired, which requires the first grant to have expired, since the same hazard re-catches anyone still standing in it the instant an old grant lapses. | LIVE |
| `check_store_scroll.sh` | Does the shop list follow the selection in both directions, reached without wizard mode? | LIVE |
| `check_striking_wand_knockback.sh` | Does the Wand of Striking fold its knockback into the telekinetic bolt's single Reflex save, instead of rolling a second, independent one? | LIVE |
| `check_strqueue.sh` | Is the string queue's bound still tested before the write? | LIVE |
| `check_stuck_fights.sh` | Does anchoring stop being a lockdown while still stopping movement? A Stuck paladin must land a weapon attack and print its roll against an adjacent goblin, then fail an escape attempt (both Escape Artist and Strength) and remain Stuck in the same square. | LIVE |
| `check_sunblade_acc_crit.sh` | Does the Sunblade still carry a bastard sword's Acc +2 and Crit x2 while keeping its own damage, threat range and short-sword speed? | LIVE |
| `check_sunblade_cold.sh` | Does wielding a known +2 Sunblade raise the character sheet's Cold resistance by 2, the `PLUS_1PER1` mild rate, from the pre-wield control? | LIVE |
| `check_sunblade_light_range.sh` | Does the Sunblade's final, activated `FI_LIGHT` field use radius 6, matching its promised 60-foot range? Structural because headless screen dumps expose activation but not field extent. | LIVE |
| `check_sunblade_negative_plane.sh` | Does the Sunblade handler double damage for every undead plus spectral mold and mote of negative energy, while rejecting its old wraith-only `5d6` rider? Structural until a stable headless combat scenario replaces it. | LIVE |
| `check_surrender_lein.sh` | Does surrender to a hobgoblin print its 750 gold lein? Requires both the surrender sentence and the correct amount on screen (inc-ur9b). | LIVE |
| `check_sylvan_scimitar_prose.sh` | Does the Sylvan Scimitar description say elves are neutral toward its bearer, matching its `NEUTRAL_TO MA_ELF` grant and that grant's Neutral-quality resolution in `src/Target.cpp`, rather than the "friendly" it claimed before? | LIVE |
| `check_symbol_autopickup.sh` | Does autopickup keep a dead priest's holy symbol -- of any god, granting or not -- out of the pack while still stowing real unidentified magic and a granting god-marked shield? | LIVE |
| `check_take_twenty.sh` | When nothing threatens him, does a character take 20 on Escape Artist, Climb, Handle Device, Search or Balance -- reading the maximum result, but still adding his modifiers and still measured against the DC -- rather than an accidental natural 20 passing the check however far short of the DC the total lands? Reads the printed `Escape Artist Check: took 20 ... [success\|failure]` line from a frozen paladin in full plate, whose total cannot reach the DC. | LIVE |
| `check_tanglefoot_mount.sh` | Do tanglefoot strands catch the MOUNT and leave the rider free? A level-1 paladin rides his sacred mount along a strip of strands until the mount fails its reflex save; wizard mode's "Examine Player Data" must then show `STUCK from SS ATTK` under the `----MOUNT----` banner and none in the rider's own stati list. | LIVE |
| `check_target_enter.sh` | Can a target prompt confirm a square that holds a staircase, including the one a character stands on the moment he enters a level? | LIVE |
| `check_target_order.sh` | Does the target cursor step round the ring instead of scoring one axis? | LIVE |
| `check_telepathy_prose.sh` | Does the Telepathy helm description state its scaling telepathy range -- 50 feet plus 10 feet per magic plus -- rather than the flat "60 feet" it claimed before, matching its `pval: PLUS_ADD5` code? | LIVE |
| `check_touch_defence.sh` | Does `Creature::TouchDef` (`src/Values.cpp`) equal `A_DEF` less floored `BONUS_ARMOUR` and floored `BONUS_SHIELD`, leaving `BONUS_NATURAL`'s flat racial base untouched? Reads `logs/touchdef.log`, written by `TouchDefProbeNote` under `INCURSION_TOUCHDEF_PROBE`, and recomputes the formula from the probe's own arm/shield values. | LIVE |
| `check_trip_aoo.sh` | Does a trip still make the tripper attack himself? Four goblins are summoned around a level 1 orc warrior and tripped one at a time, and a probe records the actor and victim of every attack of opportunity the engine accepts. Any line whose actor and victim are one creature fails. The check also demands a goblin answering a trip, because deleting the call would remove the self-attack as surely as fixing it. | LIVE |
| `check_true_sight.sh` | Does True Seeing let a character SEE an invisible creature, and see through darkness, out to its own range -- rather than only striking the creature at full accuracy while it stays invisible? `TRUE_SIGHT` was named beside `SEE_INVIS` in the combat miss-chance test and appeared nowhere in `src/Vision.cpp`, so sight and combat disagreed about the same spell. A probe grants a player `TRUE_SIGHT` and no `SEE_INVIS`, places one invisible creature 5 squares away in a lit square, 9 squares away in a square it first unlights, and beyond the range, and asserts `Creature::Perceives` at each; it then removes the stati and repeats the first case as a control. | LIVE |
| `check_two_fist_feats_live.sh` | Do the two-weapon feats reach two empty hands? A Monk 1 / Warrior 10 buys Two-Weapon Tempest and the sheet's Brawl row moves 125% to 175%; the 1st-level sidebar must still read two equal fists at full Strength. | LIVE |
| `check_underdark_live.sh` | Does the Underdark Warrior check the race it requires, and give the Reflex save it advertises? | LIVE |
| `check_unearthly_harmonies_prose.sh` | Does the Wand of Unearthly Harmonies description state that its Intelligence damage scales per plus, matching its second `EA_BLAST` `pval: (PLUS_1PER1)d2` code, rather than the flat "1d2 points of Intelligence damage" it claimed before? | LIVE |
| `check_unholy_blight.sh` | Does Unholy Blight's inflict segment carry one `xval` (`ADJUST_CIRC`) and `yval: A_AID`, so the sicken lands, rather than the doubled `xval` that made it inert? | LIVE |
| `check_uninit_reads.sh` | Does the shipping build carry no high-confidence uninitialised-variable reads (`-Wuninitialized`, `-Wsometimes-uninitialized`)? | LIVE |
| `check_upstream_label.sh` | Does every bead the reporting ledger lists as a base-code defect carry the beads-label `upstream`, so `sync_issues.sh` publishes its GitHub issue with that tag? Reads all ids in each row, so a shared row is not skipped. | LIVE |
| `check_upstream_marks.sh` | Is every base-code fix marked, marked well-formed, and matched to a row in the reporting table? | LIVE |
| `check_v1_adversarial.sh` | Does the v1 save reader refuse every crafted corruption, yet still load the case that merely deletes a known tag? | LIVE |
| `check_v1_append_survives.sh` | Does a save written before a resource is appended to `lib/` still load to the same character afterward? | LIVE |
| `check_v1_full_roundtrip.sh` | Does a real session write a v1 save that reloads to the same character and reaches a save-load-save byte fixpoint? | LIVE |
| `check_v1_manifest_parse.sh` | Does the v1 module manifest's load-side parser refuse a manifest corrupted in one field, by name? | LIVE |
| `check_vdf_tokens.sh` | Does every `key_press` token in the Steam Input config use a spelling Steam recognises? An unrecognised token neither rejects the config nor logs anything -- the activator silently never fires -- which is how `key_press MINUS` left the R3-hold Exchange Weapons binding dead in a shipped release. | LIVE |
| `check_virtual_override.sh` | Does every derived class member function track the base declaration it redeclares -- parameter types, arity, const, return type, virtual-ness and default arguments -- across `inc/*.h` and the terminals in `src/W*.cpp`? A mismatch hides the base instead of overriding it, and calls through the base type silently reach the base body. The known cases are listed in `tools/virtual_override.baseline`, which only shrinks. | LIVE |
| `check_wall_opacity.sh` | Does a wall left behind where level generation removed a door still stop light, or does it stay solid but see-through? | LIVE |
| `check_wand_acid_type.sh` | Does the Wand of Acid's residual burn damage a fire-immune victim? | LIVE |
| `check_wand_animal.sh` | Does a Wand of Animal Summoning summon an animal, rather than a dragon from the line copied above it? | LIVE |
| `check_wand_cleansing.sh` | Does a Wand of Cleansing Light roll the damage its own inventory line prints, rather than multiplying its plus twice? | LIVE |
| `check_water_ring_prose.sh` | Does the Ring of Elemental Command (Water) description introduce its staff-spells as "elemental water", matching its all-water spell list, rather than the "elemental fire" it copied from the Fire ring? | LIVE |
| `check_weapon_groups.sh` | Does every weapon-group bit hold a row in the name table, so a class's proficiency list names it rather than dropping it in silence? | LIVE |
| `check_weapon_immunity_live.sh` | Is a bare fist tested against Weapon Immunity, and does Ki Strike beat it? One wizard-mode-summoned lemure, punched by the same character at Monk 1 and at Monk 4: `Your weapon fails to penetrate.` then no such line. | LIVE |
| `check_xp_drain.sh` | Does restoring drained XP clear the drain once, rather than also crediting the same amount back onto XP -- so draining 500 and restoring it returns effective XP exactly to where it started, not 500 above? | LIVE |
| `check_xp_penalty.sh` | Can a character who holds only two classes read his own sheet? A Wood Elf Rogue 2 / Warrior 1, whose empty third class slot used to segfault `Character::XPPenalty`. | LIVE |
| `check_xp_penalty_rule.sh` | Does the multiclass experience penalty follow the rule? Favoured and prestige classes leave the comparison, then each remaining class two or more levels below the highest remaining class costs 20% and the costs add. Six characters: an Elf photographed at Barbarian 3, Barbarian 3 / Rogue 1, + Warrior 1 and Barbarian 3 / Rogue 2 / Warrior 2, plus an Elf Rogue 5 / Assassin 2 and a Wood Elf Rogue 2 / Warrior 1. | LIVE |
| `check_xprint_tokens.sh` | Ratchet literal __XPrint object-token vararg overruns (inc-upw.30); Python 3 only. | LIVE |
| `check_xsummon_live.sh` | Does a divine summoning spell (Holy Summoning, Summon Nature's Ally) cap its concurrent summons the way the wizard line does? | LIVE |
| `check_yuse_activate.sh` | Does activating a blast item from the `y` menu ask where to aim it, rather than resolving the beam on the activator? | LIVE |
| `check_zeal_strike.sh` | Does Zeal end when the paladin strikes a creature it did not choose, and survive both an ordinary turn and a blow at the target it did choose? | LIVE |

### Diagnostics

| File | The question it answers | Status |
|---|---|---|
| `sweep_ptr_order.sh` | Where does this codebase put two pointers in order? Drives clang's parse tree through `sweep_ptr_order.py`. | LIVE |
| `sweep_ptr_order.py` | The parse-tree reader `sweep_ptr_order.sh` pipes into. Not run directly. | LIVE |
| `save_pad_rows.py` | What are the actual `SchemaPad` rows for every archived class in `src/SaveV1.cpp`, measured from `clang++ -fdump-record-layouts` and cross-referenced against the `FIELD_*`/`FIELD_SKIP` lines in each class's `ARCHIVE_CLASS` chain, never from the save code's own runtime uncovered-byte list? Prints one pasteable C initializer per array, with a comment naming any member a row covers that carries no `FIELD_` line. `tools/check_save_pad_rows.sh` runs it and diffs the result against the source. | LIVE |
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
(`docs/PORT-STATUS.md:376`). `flickerscan.sh` still calls `flickerscan.py`,
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
play-test. `check_upstream_marks.sh:78-85` and `check_api_arity.py:66-70` each
state theirs.

### Instruments

All are off by default. The environment-gated ones cost nothing when unset, so
they ship in every binary; the compile-time ones need
`EXTRA_CXXFLAGS=-D<SYMBOL> ./build_macos.sh` and reach no shipped build.

| Switch | What it answers |
|---|---|
| `INCURSION_SEED` | Determinism. Every measurement rests on it. |
| `INCURSION_MAP_AUDIT=1` | Does every Thing appear both in `m->Things[]` and in the Contents chain of the square it claims? Runs every tenth turn and the instant an unlink fails. |
| `INCURSION_SAVE_PROBE=1` | Where was the player either side of the save/load boundary? Tells "never written" apart from "written and not read back". |
| `INCURSION_MAP_PROBE=1` | Remembered against unseen glyphs per draw. Distinguishes "the map is wrong" from "the map is right and the drawing is wrong". |
| `INCURSION_CHAR_PROBE=1` | Writes a readable character sheet beside every save, automatically. |
| `INCURSION_ERROR_PROMPT=1` | Restores the blocking error dialog instead of logging and continuing. |
| `INCURSION_TARGET_PROBE=1` | Records each target-cursor press and where it landed. Behind `check_target_order.sh`. |
| `INCURSION_STAIR_PROBE=1` | Logs the staircase candidate list and its ranking. Behind `check_stair_cycle.sh`. |
| `INCURSION_DOOR_PROBE=1` | Logs `DoorFlags` either side of `Door::SetImage`'s orientation branch, with the four neighbours' solidity. Behind `check_broken_door.sh`. |
| `INCURSION_TRIP_AOO_PROBE=1` | Logs the actor, the victim and whether they are one creature for every attack of opportunity `Creature::OAttack` accepts. Behind `check_trip_aoo.sh`. |
| `INCURSION_TRUESIGHT_PROBE=1` | Grants the player `TRUE_SIGHT`, places one invisible creature at three distances and two lighting states, and logs what `Creature::Perceives` returns for each. Behind `check_true_sight.sh`. |
| `INCURSION_QUIET_PROBE=1` | Logs whether a handle lookup spoke. Behind `check_quiet_lookup.sh`. |
| `INCURSION_PORTAL_PROBE=1` | Logs door-aware component reachability, corridor-search repairs and regenerations for every generated level. Behind `check_portal_reach.sh`. |
| `INCURSION_PORTAL_REPAIR_OFF` | `carve` skips the corridor search only, so the regeneration retry can be exercised for real; `all` also skips the retry, reproducing the unfixed defect. `check_portal_reach.sh --prove-red` sets it to `all`. |
| `INCURSION_SAVE_FAIL_AT=N` | Stages a save failure at a chosen point, throwing exactly what a short write throws. A real full disk cannot reach the interesting case, because both write loops write into memory first. |
| `INCURSION_STACK_PROBE=1` | Logs nested entries into depth changes. Found the bottom-of-dungeon crash. |
| `INCURSION_MAX_KEYS=N` | The headless key budget. |
| `-DDIVERGE_PROBE` | Counts every random number drawn. Two runs of one seed draw the same numbers in the same order unless something outside the generator changed a decision, so the first differing count is the first place two runs stopped playing the same game. |
| `-DINCURSION_LAYOUT` | Shifts every heap allocation by a seeded offset, so an address-dependent decision splits on demand instead of by luck. The other half of `DIVERGE_PROBE`. |
| `-DPATH_PROBE` | Pathfinding work per call. Showed one line to be 89% of a burst. |
| `-DPALETTE_LOG` | Separates "the game re-applied a palette" from "the game did nothing and the display changed the picture". |
| `-DINCURSION_TRIP_AOO_UNFIXED` | Restores the trip defect of inc-83dw -- `ProvokeAoO(e.EActor)` and no `c == this` guard -- so the measurement binary is the engine as it stood. The whole of `check_trip_aoo.sh`'s red side. |
| `-DINCURSION_OOB_PROBE` | Names the creature and code path behind each out-of-bounds map read. |

`docs/DEVTOOLS-AUDIT.md` carries a verdict on every one
of these, on two axes: did it settle something, and is it expensive to rebuild.
It also records the instrument that was deleted for failing a third test, which
overrides both — an instrument that answers confidently about the wrong thing
costs more than no instrument. Read that entry before adding one of your own.

### Build and release

| File | The question it answers | Status |
|---|---|---|
| `package_macos_app.sh` | Produces `Incursion.app` that Gatekeeper approves, inside a draggable disk image. | BUILD INFRASTRUCTURE |
| `package_macos.sh` | Produces `dist/Incursion-macOS-arm64/`, a plain folder with the game and its data. | BUILD INFRASTRUCTURE |
| `app_launcher.c` | The bundle's entry point. Redirects the game's single read-write directory to `~/Library/Application Support/Incursion/` so nothing writes inside the signed bundle. Compiled by `package_macos_app.sh`. | BUILD INFRASTRUCTURE |
| `setup_notary.sh` | Stores the notarisation credential in a mode-600 file so a release can be cut from a non-Terminal shell. Run once, by hand. | BUILD INFRASTRUCTURE |
| `sync_issues.sh` | Publishes every bead labelled `public` to the Issues tab, so a stranger about to report a bug sees it already filed. A bead labelled `mirrored` gets its state reconciled and its title and body left alone, because somebody outside wrote that issue. Reads the live bead database on this machine; `SYNC_REPO` retargets it at a throwaway repository. See "The ones you must not run casually". | PUBLISHES OUTWARD |

`package_macos.sh` is not superseded by `package_macos_app.sh`. They produce
different artefacts for different reasons: a bare executable in a folder cannot
be assessed by Gatekeeper at all, and a notarisation ticket cannot be stapled to
one (`package_macos_app.sh:5-13`).

### Not scripts

| Path | What it is |
|---|---|
| `keys/*.keys` | Key scripts read by both backends. `headless.sh` uses the full POSIX harness format; the SDL build uses only the shared movement subset. `keys/trailer-demo.keys` demonstrates SDL movement, `@pause` and `@quit`. Read the header of a script before using it. |
| `gates/dive.baseline` | The committed regression baseline. `gate_record.sh` overwrites it. |
| `gates/Options.Dat` | The pinned settings file every gate run plays with. Committed on purpose. |
| `gates/Options.Dat.md` | What is in that settings file and why. |
| `fixtures/options-*.dat` | Frozen, dated settings files that scripted checks select explicitly. |
| `fixtures/chars/<name>.{sav,keys,sheet.txt}` | One frozen character a check loads with `INCURSION_LOAD` instead of re-rolling him: the save, the key script that made it, and the engine's own sheet. Made and regenerated by `make_char_fixture.sh`. |
| `fixtures/README.md` | Origins, differences and immutability rule for the settings fixtures, and what a character fixture is, how to use one, and how to make or regenerate one. |
| `__pycache__/` | Python bytecode. Untracked build litter. |

---

## 7. Running the checks

There is no runner, no Makefile and no CI. Run them by hand, in this order.

### Tier 1 — safe from a clean clone, no build, seconds each

These read source or text and compile nothing that needs the game to have been
built.

```sh
tools/check_dequ_dice.sh # Declared A_DEQU dice must roll without tripling (inc-m2zi AC8).
tools/check_dequ_dc.sh # Only the four named SRD A_DEQU monsters retain DCs (inc-m2zi AC8).
tools/check_fire_hardness.sh # Ordinary combustible materials lose fire hardness; enchanted materials keep it (inc-m2zi AC8).
tools/check_item_hardness.sh # Every Item gets modifiers once, after preserving immunity (inc-m2zi AC8).
tools/check_item_owner_resist.sh # Gear inherits blanket soak/rust defences and otherwise only flagged grants (inc-w26h).
tools/check_gear_protection_roster.sh # The whole EF_PROTECTS_ITEMS ruling table: 36 flagged effects, 22 wearer-only grants, the two general rules (inc-w26h).
tools/check_xprint_tokens.sh    # Literal __XPrint object-token vararg backlog (inc-upw.30).
tools/check_error_handling.sh       # greps src/*.cpp for the unbounded writes
tools/check_upstream_marks.sh       # reads src/, inc/ and docs/REPORTING-GATE.md
tools/check_api_arity.py            # reads inc/Api.h against the C++ headers
tools/check_virtual_override.sh     # reads inc/*.h and src/W*.cpp for a redeclaration that hides its base
tools/check_generated_merge.sh      # scratch Git merges: conflict with guard, both edits without it
tools/check_gate.sh                 # feeds gate_lib.sh made-up logs
tools/check_escape_sweep.sh         # greps src/ and inc/ for a C escape spelled /n
tools/check_natural_speed.sh        # reads lib/weapons.irh against inc/Defines.h
tools/check_comment_budget.sh       # sizes comment and _PROBE blocks in src/, inc/
tools/check_commit_lane.sh          # reads git log against the seven lanes
tools/check_readme_checks.sh        # tools/check_*.sh against the table in this file
tools/check_gate_membership.sh      # tools/check_* against their own gate markers
tools/check_bead_publish.py         # reads the bead database against git HEAD
tools/check_bead_new_gate.sh        # watches tools/bead_new.sh refuse an unfit bead
tools/check_shared_checkout_gate.sh # commits in a scratch repo against .beads/hooks/pre-commit
tools/check_pass_record.sh          # lands scratch beads through finish_bead.sh
```

`tools/bead_new.sh` is not a check; it is how a bead should be filed.
It passes its arguments to `bd create`, then runs
`tools/check_bead_publish.py --bead <id>` on what it just filed, so an
undescribed or unclassified bead is caught by its author rather than by
whoever commits next. The pre-commit hook stays as the backstop, because a
wrapper only fires when somebody calls it.

These tools prove themselves against known-bad input on demand:

```sh
tools/check_upstream_marks.sh --selftest
tools/check_api_arity.py --selftest
tools/check_virtual_override.sh --selftest
tools/check_headless.sh --selftest
tools/check_citations.sh --selftest
tools/check_escape_sweep.sh --selftest
tools/check_lz_uncompress.sh --selftest
tools/check_comment_budget.sh --selftest
tools/check_commit_lane.sh --selftest
tools/check_readme_checks.sh --selftest
tools/check_gate_membership.sh --selftest
tools/nightly_verify.sh --selftest
tools/check_lib.sh --selftest
tools/check_bead_publish.py --selftest
python3 tools/flickerscan_selftest.py
```

Run the self-test when you change the checker. A check that has quietly stopped
checking anything looks exactly like a check that passes.

`tools/check_citations.sh <document>` also belongs in this tier, but it resolves
citations against the git refs `upstream/master` and `origin/master`
(`check_citations.sh:169-170`). Fetch those remotes first, or it reports failures
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
that binary afterwards (`check_strqueue.sh:95`). It copies the frozen
`fixtures/options-2026-08-13.dat` into its sandbox (`check_strqueue.sh:48`).

### Tier 3 — needs `BACKEND=posix ./build_macos.sh` first

```sh
BACKEND=posix ./build_macos.sh
tools/check_headless.sh             # run this one FIRST of the tier
tools/check_feat_toggle.sh
tools/check_buckler_size.sh          # Medium and enlarged Large buckler Balance penalty
tools/check_dump_save.sh
tools/check_char_fixture.sh         # a frozen character still loads as himself
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
tools/check_symbol_autopickup.sh
tools/check_target_order.sh
tools/check_key_directives.sh
tools/check_menu_value.sh
tools/check_favour_int32.sh         # favour over 32767 no longer wraps negative
tools/check_pray_aid_int32.sh       # and still buys the aid the AID_CHART grants
tools/check_favour_awards.sh        # the five favour awards made in C++ reach the god
tools/check_sharp_senses.sh
tools/check_skill_manager_reset.sh
tools/check_stacked_abilities.sh
tools/check_springblade_label.sh
tools/check_xp_penalty.sh
tools/check_xp_penalty_rule.sh
tools/check_prestige_profs.sh
tools/check_prestige_tables.sh
tools/check_alienist_live.sh
tools/check_earthsinger_live.sh
tools/check_huntsman_live.sh
tools/check_loremaster_live.sh
tools/check_masterarcher_live.sh
tools/check_monster_memory.sh       # what the player has met, and what the game therefore tells him
tools/check_sentinel_live.sh
tools/check_underdark_live.sh
tools/check_wand_acid_type.sh       # residual acid burn damages a fire-immune victim
tools/check_lightmap.sh             # the light map: no light through walls, a carried light lights its bearer
tools/check_light_filter.sh         # light dims and shifts colour crossing an ice wall
tools/check_light_fog.sh            # light passes through fog, dimmed, and is not stopped by it
tools/check_hide_carried_light.sh   # a creature carrying a lit source cannot hide
tools/check_hide_dynamic_light.sh   # a dynamic external light breaks hiding, with no static .Bright
tools/check_light_averse.sh         # light aversion bites in a dynamically lit cell, not a dim one
tools/check_shift_opcodes.sh        # a script `<<` shifts left, so a glowing creature's light keeps its colour
tools/check_holy_undead.sh          # a Holy weapon smites undead that are not evil
tools/check_dequ_magic_hardness.sh  # a no-save A_DEQU bypasses a plain weapon's hardness, not a magical one's
tools/check_dequ_reach.sh           # a blow struck at reach now takes the equipment retaliation
tools/check_dequ_sunder.sh          # a sunder's retaliation lands on the striker's weapon, not the victim's
tools/check_dequ_owner_immunity.sh  # rust immunity keeps the owner's maul undamaged
tools/check_item_flag_protection.sh # flagged acid immunity keeps the owner's maul undamaged
tools/check_gear_spell_protection.sh # a spell's SIBLING clause protects the caster's gear; the flag is shared across clauses
tools/check_gear_item_exclusion.sh  # the wearer-only Amulet of Bile leaves the bearer's gear exposed
tools/check_gaze_reflect_message.sh # a reflected gaze names the gazing monster once, in a sentence that parses
tools/check_dungeonmap_bounds.sh    # a levitating character on the bottom level stays on it
tools/check_tanglefoot_mount.sh     # tanglefoot catches the mount, not the rider on its back
tools/check_school_focus_menu.sh    # a school already focused on is off the School Focus menu
tools/check_school_focus_dc.sh      # School Focus (Illusion) raises the disbelief DC
tools/check_periodic_interval.sh    # a PERIODIC status effect fires every Val rounds, not Val-1
tools/check_xp_drain.sh             # RestoreXP clears the drain once, not once plus a matching XP credit
tools/check_portal_reach.sh         # every portal shares one door-aware component; --prove-red shows it failing
tools/check_mana_regen_floor.sh     # the mana-regen floor starts high and falls with Concentration, not the reverse
tools/check_mana_regen_cast.sh      # the same fix under real play: cast, wait without resting, mana does not rise
```

`check_gaze_reflect_message.sh` is the live twin of Tier 1's
`check_xprint_tokens.sh`. The static one counts vararg-consuming tokens in
source text; this one summons a bodak at a character carrying Gaze Reflection
and reads the sentence the reflection puts on the screen. Reverting the fix does
not merely reword that sentence -- the session dies inside `__XPrint` -- and
`check_lib.sh` fails a session the game killed, so the death is the
measurement.

The four `check_dequ_*` scripts, `check_item_flag_protection.sh`,
`check_gear_spell_protection.sh` and `check_gear_item_exclusion.sh` above are
the behavioural half of inc-m2zi and
inc-w26h; the five `check_dequ_dc.sh`-style scripts in Tier 1 are the static
half. Each drives one or two seeded sessions and reads the struck
weapon's own description page -- reached from the inventory with 'x' -- before
and after the blows. The last two add a second reading, because a RESIST is a
number rather than a yes or no: they read the hardness off the game's own
combat-numbers line, which `Item::Damage` prints AFTER adding the bearer's gear
resistance to it. Those two silver a magic warhammer for the ordering
`Item::Damage` used to have: a no-save A_DEQU sets `ignoreHardness` on a plain
item (`src/Fight.cpp:2152`), and the bearer's grant was added before the bypass
emptied it, so a resistance was unmeasurable on ordinary gear. inc-kapn
inverted that -- the bypass now empties only what `Hardness()` returned -- and
`check_gear_bypass_survives.sh` measures a resistance on a plain iron maul. The
warhammer stays because its silvered 12 is a hardness the creeper's 3d6 can
still beat, which is what makes the mutation bite. `check_dequ_magic_hardness.sh` runs two sessions, because
every retaliation that lands on the character rather than on his weapon costs
him 2d4 hit points and a level-one orc cannot pay for both halves in one life.

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

`check_load_corrupt.sh:47-58` prefers `./incursion-ubsan` when it exists and
falls back to `./incursion-headless`. It refuses an `./incursion-ubsan` when a
file in `src/` or `inc/` is newer, because that binary would test old code.
Build the sanitizer variant with the recipe at `build_macos.sh:142-143` if you
want the stronger run.

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

`check_layout_sweep.sh` sits here too, and builds that probe for you:

```sh
tools/check_layout_sweep.sh              # 12 seeds across four key scripts
tools/check_layout_sweep.sh --no-build   # reuse the probe binary already here
tools/check_layout_sweep.sh --selftest   # stubbed, seconds, needs no build
```

`check_libtcod_mode_change.sh` sits here as well. It links the vendored libtcod
archive that `./build_macos.sh` leaves at `build/libtcod_local.a`, and it is the
only check that needs a real display. Read the warning below before you run it.

```sh
./build_macos.sh && tools/check_libtcod_mode_change.sh
tools/check_libtcod_mode_change.sh --selftest   # proves the harness can fail
```

### Tier 5 — the gate, which needs a baseline

```sh
tools/gate_compare.sh               # re-runs every recorded baseline
```

`tools/nightly_verify.sh` runs this for you: since 2026-09-11 the soak sits with
the builds, so a full run costs its minute and reports a regression in the shape
no single check can -- a complaint appearing in several sessions at once, fewer
sessions reaching a map, more deaths or freezes.

`tools/gates/dive.baseline` is committed, so a clone can run `gate_compare.sh`
without recording anything. Do NOT run `gate_record.sh` unless you mean to
replace that baseline — see below.

### The ones you must not run casually

**`tools/check_distant_light_vision.sh` and `tools/check_nonnormal_invariant.sh`
are A/B checks that build both sides themselves.** Each one runs
`git worktree add --detach` for the before ref and the after ref
(`check_distant_light_vision.sh:66`, `check_nonnormal_invariant.sh:55`), builds
`BACKEND=posix ./build_macos.sh` inside each, and on exit runs
`git worktree remove --force` and `git worktree prune`
(`check_distant_light_vision.sh:48-50`, `check_nonnormal_invariant.sh:42-45`).
So they cost two full builds, not one run, and they touch this repository's
worktree list. They belong to Tier 3 by what they measure and to this section
by what they cost. `check_nonnormal_invariant.sh` sweeps seeds 1-10, so budget
for it accordingly. `tools/check_light_averse.sh` is milder but not free: if
`./incursion-headless` is missing it builds one itself (`check_light_averse.sh:27`)
instead of reporting INCONCLUSIVE.

**`tools/check_abs_path.sh` runs the real game from the repo root, and moves the
live `Options.Dat` aside.** Verified: `check_abs_path.sh:22-27` renames `Options.Dat` to
`Options.Dat.checktmp` and installs an `EXIT` trap to move it back; `check_abs_path.sh:32` runs
`./incursion` in the background from the repo root, and `check_abs_path.sh:34-35` sleep 8 seconds
and kill it. Two consequences. First, the game resolves the repo root as its own
directory, so it reads and can write the owner's real `save/`. Second, if the
script is killed with a signal the trap cannot catch, the live `Options.Dat`
stays parked at `Options.Dat.checktmp` and the game starts with defaults next
time. Recover by renaming it back. Do not run this while anyone is playing.

**`tools/check_libtcod_mode_change.sh` takes over the screen.** Its third phase
opens a real fullscreen window, because that is the only way to read the flag
and the copy rectangle libtcod uses for a fullscreen console; a key script
cannot reach the Alt-Enter branch and `@shot` photographs the console surface
before the faulty copy, so neither can see this defect. The window lives for
well under a second and the check closes it, but it steals focus while it is
up. Do not run this while anyone is playing, and do not put it in the ratchet.

**`tools/sync_issues.sh` WRITES TO A PUBLIC ISSUE TRACKER.** It sends every
bead labelled `public` to the Issues tab of
`networkingguru/incursion-roguelike`, creating an issue for each one that has
none and updating the rest. Creating a few hundred issues is not something you
can quietly undo: GitHub lets you close an issue, never un-file it, and
everybody watching the repository gets the mail. Run `tools/sync_issues.sh
--dry-run` first, always. Point `SYNC_REPO` at a throwaway repository to
rehearse. `tools/check_bead_publish.py` decides what the word `public` means,
and it is documented under "Every bead carries `public`, `internal` or
`mirrored`" in `AGENTS.md`.

A bead labelled `mirrored` is the exception the script makes for a report
somebody outside filed: it syncs the open or closed state of that person's
issue and never writes its title or body. Do not relabel a mirrored bead
`public` to get it published — that publishes this project's text over the
reporter's own words.

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
(`check_upstream_marks.sh:12-15`). Pass 2 is new and FAILS on a MALFORMED
marker — a comment shaped like a marker whose tag is not spelled as the
documented `upstream: ` and is therefore invisible to
`grep -rn "upstream:" src/ inc/`. `src/rle.c:270` and `src/lz.c:500` both wrote
it as `upstream (inc-l0t, Traced, not sent):` and were skipped in silence for
months (`check_upstream_marks.sh:17-23`). Both of those two sites are now spelled correctly, so reading
them today shows the fix and not the defect; the check is what keeps the next
one from happening. Pass 3 is new and checks the REVERSE direction: for every
row, at least one of the files it names as the fix site must carry a marker
mentioning that row's id, because the house convention is one mark at the
primary site (`check_upstream_marks.sh:36-40`, `:46-51`). Pass 3 WARNED rather than failed until
2026-08-23, because two rows were unmatched and resolving them is a provenance
judgement, not this script's call. Both were settled that day (bd inc-6s5), so
the pass now FAILS and `--strict` is the default (`check_upstream_marks.sh:70-76`,
`:102-108`). The flag is still accepted and does nothing, so an older caller does
not break (`check_upstream_marks.sh:75-76`). `--selftest` proves the detectors still
detect (`check_upstream_marks.sh:90`), and since 2026-08-23 that includes pass 3
itself: a synthetic table with one unmatched row, one matched row, one row
naming a file that is not there, and one row naming two files of which only one
carries the marker must produce exactly one WARN, one FAIL and no word about
either matched row.

**`check_api_arity.py` now has a checked-in baseline and can fail.** It used to
return 0 on every path, printing two MISALIGNED slots and exiting green, so
anything running it as a gate got a pass no matter what happened
(`check_api_arity.py:53-56`). It now compares what it finds against a `BASELINE`
dictionary held in the script itself at `:111`. Three outcomes
(`check_api_arity.py:58-61`):

- a MISALIGNED slot IN the baseline — reported as KNOWN, tolerated;
- a MISALIGNED slot NOT in it — FAIL, a new defect or a real change;
- a baseline entry that no longer misaligns, or whose types moved — **also
  FAIL**, because a stale suppression is how a gate rots.

The exit codes are 0 clean, 1 a failure of any of those three kinds, 2 the tool
could not parse `inc/Api.h` and so examined nothing
(`check_api_arity.py:72-77`). `--selftest` exercises all four branches with no
framework and no fixtures (`:369-370`, `:392-401`). Note the tool's own stated
limit: about a fifth of the declarations — 94 of 460 — find no C++ declaration
its parser can match, so a clean run is not a clean bill of health
(`:66-70`).

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
- **§6 is a curated guide, not a complete inventory.** It names 62 of the 187
  `check_*.sh` in the tree, and §7's tiers name 54; the rest are real checks
  that no page here lists. §6 documents the harness, the gate and the checks
  worth reading, because a row is only worth writing when someone has read the
  script. Counted 2026-09-04: `ls tools/check_*.sh | wc -l` against the scripts
  named in §6 and §7.
