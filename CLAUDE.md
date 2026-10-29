@AGENTS.md

# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.


## Build & Test

```bash
./build_macos.sh                        # the SDL build, ./incursion
BACKEND=posix ./build_macos.sh          # the headless build, most checks need it
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    tools/headless.sh tools/keys/dive.keys   # one seeded session, sandboxed
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/lizardfolk-monk-seed1.sav \
    tools/headless.sh tools/keys/load-char-sheet.keys 1   # ...from a frozen character
tools/nightly_verify.sh --record        # freeze what already fails
tools/nightly_verify.sh --compare       # did this work break anything that passed?
```

Never run the binary directly. `tools/headless.sh` gives a run its own `save/`
and `logs/`, so an unattended session cannot destroy a real character.

Every harness run MUST name its settings. `tools/headless.sh` exits 2 when
`INCURSION_OPTIONS` is unset, because settings change what a seeded session
does: e4a6499 measured one flipped option byte taking `dive.keys` on seed 4242
from 254 turns to 2190. Frozen choices live in `tools/fixtures/` and are
described in `tools/fixtures/README.md`; gates use their own
`tools/gates/Options.Dat`.

Reach for `INCURSION_LOAD` when a check needs a character a module change cannot
rewrite: a seed-pinned character is not one, because an rID is a position.
`tools/fixtures/README.md` says why, and how to make and regenerate a fixture.

`tools/README.md` §7 groups every check into five tiers by what it needs, and
names the two you must not run casually.

## Verification

Read `docs/VERIFICATION.md` before you change behaviour. It states the rule this
project uses instead of hosted CI, and it is not optional.
