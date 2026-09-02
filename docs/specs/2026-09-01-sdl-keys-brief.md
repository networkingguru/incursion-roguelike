# Build brief: `-keys` deterministic playback in the SDL/libtcod build

**For:** Codex (`codex exec -C /Users/brianhill/Scripts/Incursion -s workspace-write - < brief`). Codex implements and builds the posix half in the sandbox; it MUST NOT commit and MUST NOT run the SDL binary (`./incursion`) — the sandbox has no display. The Claude session reviews each phase's diff and runs the SDL build outside the sandbox.

**Goal.** Let an agent drive a scripted camera through a level in the graphical SDL build for trailer capture, with pauses that let the real-time light flicker breathe. Today `-keys` playback exists only in the posix/headless build (`src/Wposix.cpp`); the shipped binary is the libtcod one and cannot be scripted (`src/TextTerm.cpp:83-85` says so).

**Stack.** C++17, the fork's two backends: posix/headless (`src/Wposix.cpp`, `BACKEND=posix ./build_macos.sh`) and libtcod/SDL (`src/Wlibtcod.cpp`, `./build_macos.sh`). Same engine core; same `INCURSION_SEED` + module + options → identical simulation in both. Only the light shimmer is wall-clock.

**Design in one line.** Both backends already end their input path with the identical keyset-mapping tail (`ControlKeys = k.mods; ch = k.ch;` then the same lookup loop — posix `Wposix.cpp:1726-1743`, libtcod `Wlibtcod.cpp:1928-1941`). Playback = feed a `ScriptKey` into that seam. The pause primitive already exists: `libtcodTerm::SleepTicking()` (`Wlibtcod.cpp:1085`) sleeps while ticking `LightFrame()`.

**Scope guard.** The SDL build has NO screen-scrape harness (its `-dump` is a save-file dump, `RunSaveDump`, `Wlibtcod.cpp:573`, not a live screen read). So the SDL player supports the movement subset ONLY: literal-key strings, `KY_` tokens, `*N` repeat, `#` comments, `@include`, plus `@pause MS` and `@quit`. The posix scrape directives (`@choose/@expect/@cursorto/@while/@until`, `ScreenShows`, `FindMenuEntry`) stay posix-only and are NOT ported. The SDL parser MUST reject a scrape directive with a clear error rather than silently mishandle it.

**Hard constraint.** posix behaviour stays byte-identical. The mandatory guard is the `dive.keys` A/B parity test in the test plan. Do not change posix key handling except the additive `@pause`/`SK_PAUSE` recognition in phase 2.

---

## Files touched

| File | Change |
|---|---|
| `inc/KeyScript.h` (new) | The backend-neutral pieces: the `ScriptKey` struct, the `SK_*` constants both backends need (`SK_DUMP`, `SK_QUIT`, new `SK_PAUSE`), and the `TokenToKey` declaration. Add a `pauseMs` field (int32) to `ScriptKey` for `SK_PAUSE`. |
| `src/KeyScript.cpp` (new) | `TokenToKey` moved verbatim from `src/Wposix.cpp:1143` (pure function, mechanical extract). A `LoadKeyQueue(const char *fn, std::vector<ScriptKey>&, char *err, size_t errsz)` for the SDL build that parses the movement subset + `@include`/`@pause`/`@quit`, and returns false with a message on any posix-only scrape directive or unreadable token. Reuse the same token grammar as `Wposix.cpp` `LoadKeyScript` for the shared tokens so one script parses the same in both. |
| `src/Wposix.cpp` | Include `KeyScript.h`; delete the now-shared `ScriptKey`/`SK_*`/`TokenToKey` local definitions. Add `@pause MS` to `LoadKeyScript` → append an `SK_PAUSE` with `pauseMs`. In `NextKey`, treat `SK_PAUSE` as a no-op: advance `keyNext`, deliver no key, do NOT sleep (headless has no real time), so a scripted pause replays instantly. |
| `src/Wlibtcod.cpp` | Parse `-keys <file>` and `-load <save>` in `main()` beside `-dump` (~L544). New `libtcodTerm` members: the key queue, an index, a `pauseUntil` deadline, an `aborted` flag. In `GetCharCmd`'s `for(;;)` loop (L1727), before the live poll: if a script is active and not paused, pop the next `ScriptKey` — `SK_PAUSE` sets `pauseUntil = now + pauseMs` and `continue`s the loop (which already ticks `LightFrame`); `SK_QUIT` takes the existing `CtrlBreak` path; otherwise set `ch`/`ControlKeys` and fall into the keyset tail. A real `ESC` from the live poll sets `aborted` and returns to live input. Queue empty → stop injecting, return to live keyboard (final frame holds). |
| `src/Main.cpp` | Non-interactive load-into-play: if `-load <save>` is set, after startup call `LoadModules()`, load the named save, then `Play()`, bypassing the title menu — mirror the title dispatch's load case (`Main.cpp:2256-2261`, `LoadGame(false); Play()`). Add a filename-taking load (a `LoadNamedGame(const char*)` or a param on `LoadGame`, `inc/Res.h:1342`) rather than driving the save-picker menu. Both backends use this path. |
| `src/TextTerm.cpp` | Fix the comment at `:83-85`: `-keys` now exists in the libtcod build too. |
| `README.md`, `tools/README.md` | Update the `-keys` rows to say both backends support it, and document `@pause`/`@quit`/`-load`. |
| `tools/keys/trailer-demo.keys` (new) | A first movement + `@pause` sample script (pure player movement), per the discovery-of-distant-light shot. Header comment explaining the format. |

---

## Phases (each is a review gate; Codex does NOT commit — Claude verifies and commits)

1. **Extract the neutral core.** Move `ScriptKey`/`SK_*`/`TokenToKey` into `inc/KeyScript.h` + `src/KeyScript.cpp`; `Wposix.cpp` includes them. No behaviour change. GATE: posix build exits 0, `dive.keys` dump byte-identical to pre-change.
2. **Add `@pause`/`SK_PAUSE` + `@quit` to the shared grammar.** posix parses `@pause MS`, `NextKey` skips it with no sleep. GATE: posix build 0; `dive.keys` still byte-identical; a script with `@pause 500` parses and replays instantly in headless.
3. **SDL `-keys` player.** Parse `-keys`; load the queue via `LoadKeyQueue`; inject into the `GetCharCmd` seam; honour `@pause` by holding while `LightFrame` ticks; `ESC` aborts to live; end-of-queue returns to live. GATE (Claude runs the SDL build): SDL build 0; `-keys /nonexistent` prints "Cannot open key script" + nonzero exit; a sample script moves the player and a `@pause 2000` holds ~2 s with flicker continuing (≥~2000 ms gap in `palette.log`).
4. **Non-interactive `-load <save>` into play**, both backends. GATE: `-load <save>` boots straight into `MO_PLAY` on that save with no menu; posix build 0.
5. **Docs + sample.** `TextTerm.cpp:83` comment, README/`tools/README.md` rows, `tools/keys/trailer-demo.keys`. GATE: `tools/check_readme_checks.sh` (or the relevant doc check) green.

Dispatch phases 1–2 first (the posix-parity-critical refactor), review, then 3–5.

---

## Test plan

- **Adversarial:** `-keys` with an empty file, a comment-only file, an unknown token, a scrape directive (`@choose`), a deep `@include` chain, `@pause 0`, `@pause` with a huge value — each must fail loud or behave sanely, never crash or silently skip.
- **Parity (mandatory runnable check):** `dive.keys` produces a byte-identical dump before vs after the whole change (git-stash A/B). This is the guard that posix is untouched.
- **Regression:** `tools/nightly_verify.sh --compare` shows no new reds attributable to this work.
- **Live-data / end-to-end:** the SDL build plays a real `-keys` script through a loaded save; the player moves and pauses; `ESC` takes over; the window never blocks. Claude observes this in the SDL window (the look is Brian's oracle; the mechanics are in `palette.log`).

## Build notes for Codex
- Build posix with `BACKEND=posix ./build_macos.sh` (compiles `incursion-headless` + the module fully in the sandbox). The default SDL build FAILS in the sandbox (no display) — do not attempt it; leave the SDL build and its smoke test to Claude.
- Do NOT run `./incursion`, `tools/check_flavor_stability.sh`, or `tools/check_dump_save.sh` (they need the SDL binary). Every other `check_*.sh` runs in the sandbox.
- Do NOT commit. Leave the working tree dirty for Claude to review.
