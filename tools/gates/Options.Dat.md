# tools/gates/Options.Dat -- what it is and why

Binary, 900 bytes (`OPT_LAST` from inc/Defines.h), one signed byte per option
constant, read/written raw by `Player::LoadOptions`/`UpdateOptions`
(src/Player.cpp). This is not a copy of anyone's live play file. It is the
harness's own settings, built and documented under inc-loa.4 (2026-08-16/17)
so a scripted `-keys` session interacts with as few unplanned prompts as
possible. See that issue for the full history; this file is the short version
that lives next to the binary it describes.

## Why this exists

`-keys` feeds keystrokes from a file blind -- it cannot see the screen. Any
game prompt the script did not plan for eats a keystroke (or, worse, every
remaining keystroke -- see inc-loa.5) and the rest of the run plays a
different game than the script intended. Several of those prompts are
switched on or off by options. This file switches off every one that is.

## Provenance: not built from game defaults

Tried first: start from `Player::ResetOptions()`'s own defaults (computed
directly from the `Default` field of every live entry in `OptionList[]`,
src/Tables.cpp) and layer overrides on top. Rejected: `tools/keys/chargen.keys`
line 14 (`y # Your options will place the game in Explore Mode. Continue?`)
assumes several chargen switches -- `OPT_BEGINKIT`, `OPT_MAX_HP`,
`OPT_MAX_MANA`, `OPT_POWER_STATS` among them -- are already turned up enough
to trigger Explore Mode. Pure game defaults do not trigger it, so that prompt
would not appear and the script's scripted 'y' would land on whatever comes
next instead -- exactly the failure this issue exists to prevent.

**Actual base: the previous `tools/gates/Options.Dat`** (the file inc-w43
pinned by copying Brian's live file, proven 2026-08-15 to complete
`chargen.keys` and reach a map in 40 of 40 sessions). Only the overrides below
are applied on top of it. Nothing else changed.

## Overrides applied (index, old -> new, why)

| Option | idx | old | new | Why |
|---|---|---|---|---|
| `OPT_GENDER` | 107 | 2 | 2 (no-op here; was already fixed in the base file) | Create.cpp:157 asks "Is this character male or female?" only when this is 0 (ASK). Any other value skips it. MALE chosen over RANDOM for a deterministic harness. |
| `OPT_AUTOMORE` | 201 | 0 | 1 | The `--more--` suppressor named directly in inc-loa.4. Off by default: any message-window overflow becomes a keystroke-eating prompt. |
| `OPT_STOP_INTER` | 303 | 1 | 0 | The one `OPT_STOP_*` run-interrupter that defaulted ON. Stopping a running character mid-script leaves the next scripted key landing somewhere unplanned. |
| `OPT_LOWHP_WARN` | 307 | 3 | 0 | Suppresses the low-HP message outright, per "cut off all warnings about everything." Not itself blocking (`OPT_LOWHP_AGG`, already off, is the blocking one) but still unrequested output. |
| `OPT_WARN_EMPTY_HAND` | 309 | 1 (SMART) | 0 (NEVER) | Its own Tables.cpp comment calls it "an aggressive warning"; SMART still fires whenever unarmed and not polymorphed. |
| `OPT_WARN_DEQU` | 310 | 1 | 0 | Confirm-before-attacking-equipment-destroyers is a real `yn()` prompt, on by default. |
| `OPT_AUTODISARM` | 205 | 0 | 1 | auto-* family (204-215): without this, walking into a known trap fails the move or needs an explicit command instead of continuing. |
| `OPT_AUTOOPEN` | 206 | 0 (NEVER) | 2 (YES) | NEVER makes a scripted walk bump silently into every closed door; ASK(1) is itself a prompt. YES passes through. |
| `OPT_AUTOCHEST` | 207 | 0 | 1 | Opens chests on contact instead of leaving them as an obstacle the script has no command queued for. |
| `OPT_AUTOKNOCK` | 208 | 0 | 1 | Auto-casts a known Unlock spell on a failed lockpick instead of stalling at a locked door. |
| `OPT_AUTOKICK` | 209 | 0 | 1 | Kicks a door in after a failed pick instead of stalling; pairs with `OPT_REPEAT_KICK`, already on. |
| `OPT_KILL_CHEST` | 211 | 0 | 1 (no-op here; base already had it) | Destroys an empty chest for free on contact instead of leaving a standing obstacle. |
| `OPT_DWARVEN_AUTOFOCUS` | 214 | 0 | 1 (no-op here; base already had it) | Only affects dwarves; picks a target automatically instead of prompting. |

## Explicitly NOT touched -- the death-semantics boundary

inc-loa.4's scope boundary, verbatim: "DO NOT touch OPT_NODEATH... Decide
deliberately whether a soak wants an immortal character or an honest one...
and make the harness count deaths either way." That naming is extended here
to cover both of Fight.cpp's "escape hatches" (its own words, src/Fight.cpp
comment above `NoteCharacterDied`), because both govern the exact "You
die... Die? [yn]" prompt inc-loa.3 instrumented:

* `OPT_NODEATH` (idx 801): **0** (NO), unchanged. Named explicitly in scope.
* `OPT_ELUDE_DEATH` (idx 119): **3** (SEVEN free deaths), unchanged. Not
  named by inc-loa.4's text, but it is the mechanism actually firing the
  prompt here since `OPT_NODEATH` is 0 -- see `if (thisp->Opt(OPT_NODEATH))
  ... else if (Opt(OPT_ELUDE_DEATH))` at src/Fight.cpp:7194-7219. Left as
  pinned rather than defaulted (game default is 0/NO) because changing it
  changes whether a soak character can die at all, which is exactly the
  decision the boundary reserves for Brian.

## What this does NOT fix, and why

* **"Invalid depth."** (Debug.cpp:807) -- refused wizard depth-jumps past
  `DUN_DEPTH`. Not gated by any option; it is `tools/keys/dive.keys` asking
  for depths the dungeon does not have. inc-loa.2's territory.
* **"Abort, Flee or Disengage?"** (Move.cpp:841) -- confirmed by reading
  every `Opt(OPT_` check in Move.cpp that no option gates it. Worse than a
  single eaten keystroke: `ChoicePrompt`'s input loop (Term.cpp:2460) blocks
  on every keystroke until one of `a`/`f`/`d`/`?`/ESC arrives, none of which
  `dive.keys` contains, so once this fires a session is frozen for the rest
  of its run. See inc-loa.5, filed tonight with the repro.
* **"Request aid or seek insight?"** (Prayer.cpp:105) -- also ungated; fires
  whenever a mundane `EV_PRAY` reaches an altar. `dive.keys` never presses a
  pray key on purpose, so on the seeds where this still appears it is a
  downstream symptom of an earlier desync landing a 'p' outside wizard mode,
  not something this file can prevent directly. The overrides above cut its
  occurrence from 15 of 40 seeds (old file) to 1 of 40 (this file) -- see
  inc-loa.4's bd notes for the full sweep.

## Verification

40-seed sweep, `tools/keys/dive.keys`, seeds 1-40, old file vs this file
(methodology: first `@dump` screen, header stripped, byte-identical to the
session's last screen -- the point past which a session produced no more
game state, same measure inc-dhc's re-verification used):

| | old (inc-w43) | this file |
|---|---|---|
| "male or female" prompt | 0/40 (already fixed in old file) | 0/40 |
| "Request aid or seek insight" | 15/40 | 1/40 |
| "Invalid depth" | 7/40 | 6/40 (inc-loa.2, unchanged by design) |
| "Abort, Flee or Disengage" | 5/40 | 7/40 (inc-loa.5, unchanged by design) |
| reached deep/varied gameplay (frozen at screen >=8 of 11) | 2/40 | 2/40 |
| froze by screen 5 | 38/40 | 37/40 |
| death-prompt STUCK | 12/40 | 24/40 |

The headline "reached deep gameplay" number did not move. Read alongside the
STUCK count nearly doubling, the story is consistent, not contradictory:
removing the gender/`--more--`/prayer-prompt blockers lets more sessions
survive long enough to reach real combat, where they now run into the two
remaining ungated prompts (inc-loa.5's disengage freeze and the
already-tracked death prompt) more often than before, not less. This file is
a real, verified fix for everything in inc-loa.4's scope; it is not, on its
own, enough to make `dive.keys` reach deep gameplay reliably -- that needs
inc-loa.5 and the OPT_NODEATH/ELUDE_DEATH product decision resolved too.
