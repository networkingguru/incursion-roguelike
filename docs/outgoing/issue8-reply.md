This work was done with AI assistance (Claude) — the harness, the seeded runs and the analysis, not only the prose. Every link below is pinned to commit `2f58be3` on my fork of this repo.

I built most of what this issue asks for, on a macOS port of the game, and it is how most of the defects I have found there were located. Rather than open a PR you did not ask for, here is what exists, what it measures, the one idea in this thread I tried and abandoned, and what I got wrong on the way.

## What is built

**A third terminal backend.** [`src/Wposix.cpp`](https://github.com/networkingguru/incursion-roguelike/blob/2f58be3a659a8e4b8e1b9f11d7b5982da7146df4/src/Wposix.cpp) sits beside `Wlibtcod.cpp` and `Wcurses.cpp` and implements the same `TextTerm` virtuals. It has two output modes. With a tty it draws through ncurses and is playable in a terminal. Without one, or with `-headless`, it draws nothing at all and the game runs with no window and no person. It links `-lz` and `-lncurses` and nothing else — no SDL, no libtcod. It keeps the screen as a plain `Glyph scr[48][80]` rather than in a graphics library's buffer, which makes `AGetChar` exact; the libtcod backend cannot do that, because it stores the character its glyph table produced, so a `GetGlyph` → `PutGlyph` round trip loses the glyph id.

**Keystrokes from a file.** `-keys FILE` reads a token stream: bare characters, `"strings"`, named keys (`ESC ENTER TAB UP PGDN F1`), `^D` for control, `TOKEN*12` to repeat, `@dump` to write the current screen out, `@quit` to leave at the next key read. An uppercase token also sets SHIFT, which is not cosmetic: `StandardKeySet` matches `toupper(ch)` and then compares the modifier flags exactly, so `a` and `A` reach different commands, and a script that ignored SHIFT would silently dispatch the wrong ones. A run ends four ways — the script runs out, `INCURSION_MAX_KEYS` is reached (default 20000), a `SIGALRM` watchdog fires because the game stopped asking for keys at all, or `Fatal()` fires — and each exits with its own status, so a soak can tally them without reading a log.

**`@dump` writes the screen as ASCII**: a header line naming the dump and the key count, then 48 screen rows with their trailing blanks stripped, and glyph ids mapped to `#`, `.` and `@`, because the consumer is grep and not a font. Dumps happen at the moment the game asks for a key, which is the moment the screen is settled, so a dump never catches a half-drawn frame.

**Determinism, which I underestimated.** Runs were not reproducible and the cause was bigger than one `srand`. The game reaches for the clock in six places: twice in `src/Main.cpp`, twice while a character is built in `src/Create.cpp`, once per equipment roll in `src/Annot.cpp`, and once after spell formulas are chosen in `src/Skills.cpp`. All six now call one function that returns `time(NULL)` unless `INCURSION_SEED` is set, and counts up from the given number when it is — so each call still sees a different value, as it did from the clock, but the series repeats exactly on the next run. Unset, nothing changes for a player. Without this the harness would have been a smoke test and never a regression test.

**A sandbox per session.** [`tools/headless.sh`](https://github.com/networkingguru/incursion-roguelike/blob/2f58be3a659a8e4b8e1b9f11d7b5982da7146df4/tools/headless.sh) runs each session in its own directory with its own `save/` and `logs/`, with `mod/` and `lib/` symlinked in. That was not in my plan and it should have been: the first run I made outside one wrote a scripted character into `save/` beside real ones. [`tools/soak.sh`](https://github.com/networkingguru/incursion-roguelike/blob/2f58be3a659a8e4b8e1b9f11d7b5982da7146df4/tools/soak.sh) calls it once per seed, several at a time, and groups the errors by message rather than by session.

**One small thing that paid for itself.** `Game::CheckConsistency` — the engine's own ruleset checker — now writes `logs/consistency.txt` as well as drawing its report on screen. It was usable only by a person scrolling a box, which defeats the point of a backend with no person in it.

The specification, including the reasoning and a "what was actually built" section listing what it got wrong, is [docs/HEADLESS-SPEC.md](https://github.com/networkingguru/incursion-roguelike/blob/2f58be3a659a8e4b8e1b9f11d7b5982da7146df4/docs/HEADLESS-SPEC.md). The key scripts are in [tools/keys/](https://github.com/networkingguru/incursion-roguelike/tree/2f58be3a659a8e4b8e1b9f11d7b5982da7146df4/tools/keys).

## Why I did not build the morgue-and-replay diff

I tried the screen-comparison form of it first, and it does not survive contact with a fix. Almost any correct change moves game state, so the two runs diverge from the first changed decision onward and every line after that is noise. A gate that goes red on every correct fix gets switched off within a week. Freezing balance and worldgen would hold it still, as you both suggest above, but the changes I most want a gate for are exactly the ones that move state — that is what makes them worth gating.

I also tried the identity of the crashing seed as a signal, on the theory that a fix should stop a specific seed from segfaulting. It is not an identity: the segfaulting seed moved between 3362 and 3387 depending on which of my fixes was present.

What held still is error volume and message-set membership. Reduce a finished soak to a handful of numbers — how many sessions reached a map, the tally of exit codes, total error lines, total findings from a map self-check I added, and then one row per distinct message with its session count and its occurrence count. A message that is not in the baseline is a regression; a message that has left it is a fix. Subset is the shape to test for. The worked example is the `Target` zero-initialisation fix you merged as #42: one assertion moved from 89,545 occurrences to none across 250 seeds, and the post-fix message set was a strict subset of the pre-fix one.

The known limit, which I would rather state than have found: this detects regressions that produce log output. A defect that quietly does the wrong thing and logs nothing passes clean. It does not replace a play-test. The record and compare scripts and the reasoning behind the metric are in [`tools/gate_lib.sh`](https://github.com/networkingguru/incursion-roguelike/blob/2f58be3a659a8e4b8e1b9f11d7b5982da7146df4/tools/gate_lib.sh).

## Three ways a measurement here lied to me

**Settings are an input, and I did not treat them as one.** The harness copies a settings file into each session, and left alone it copied the live `Options.Dat`, which the game rewrites every time somebody plays. Same binary, same seed, same key script, different screens under the old file and the new one — I built three sandboxes by hand to check. The gate's finding count moved 4386 to 4416 across a play session with no code change at all. The gate now plays with a committed settings file, records its checksum in the baseline, and refuses to compare when the two disagree.

**A baseline recorded from sessions that never played passes every later comparison, and it passes quietly.** 250 sessions that never entered a map became the evidence for a fix here on one occasion, and nothing complained. The recorder now refuses to write a baseline unless three-quarters of its sessions reached a map.

**A scripted dive cannot go as deep as its script asks.** Wizard mode's descend command refuses any depth above the dungeon's `DUN_DEPTH`, and The Goblin Caves declares 10, so a script asking for depth 25 stops at 10 and prints `Invalid depth.` for the rest. Two of my own key scripts carried headers claiming depths they had never reached. Anything that sizes a measurement by counting the depth-jump lines in a script overcounts — mine overcounted by about two and a half times. Related: because the harness drives the wizard menu to descend continuously, it exercises level generation far harder than play does, so its defect counts are not a rate at which a player would meet them.

## What I did not build

Nothing fuzzes. Random input, engine-guided input, and the run-with-NPCs-alone idea in the first comment are all untouched. The NPC-only variant looks like the cheapest of the three from here, but I have not tried it and I would not want that guess quoted back at me.

## If any of it is useful

`src/Wposix.cpp` is one new file, and no drawing code in either existing backend changed. What did touch shared code is small and separable: the six clock calls behind one function, `LogError` lifted out of `Wlibtcod.cpp` into its own file so two backends can share it, and one extra wizard-menu option that exists only so a script can reach state it cannot walk to. It is POSIX and ncurses, so it builds on macOS and should build on Linux. I have not tried it on Windows and I do not know whether it would be worth carrying there next to pdcurses.

I am not asking you to take any of this. If you want a piece of it as a PR, tell me which piece and I will prepare it against your tree rather than mine. If you would rather it stayed on the fork and this issue just recorded what the approach cost, that is an equally good answer and this comment is that record.
