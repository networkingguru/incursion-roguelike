# Brief — phase 3 of inc-30ps: the cover-and-band rule for spell bolts

Normative spec: `docs/specs/2026-09-21-line-of-fire-spec.md`. Read "The rule",
including its worked example, "Touch defence", and "Phase 3". Implement phase 3
ONLY. Do not touch any `lib/*.irh` file — the effect declarations are phase 5.

Phases 1 and 2 must be in the tree before you start. **Phase 2 built the band
logic for `src/Fight.cpp`. Read that code first and reuse it.** If phase 2 left
a helper, call it. If the logic is inline there, lift it into a shared function
rather than writing it twice — two copies of this rule will drift, and the
whole point of the epic is that the game has one rule instead of two.

## What is there today

`Magic::ABallBeamBolt`, `src/Magic.cpp:1632`, walks the line. At
`src/Magic.cpp:1940-1946`:

    for (cr = m.FCreatureAt(cx/2,cy/2); cr; cr = m.NCreatureAt(cx/2,cy/2))
      if (cr != e.EActor || e.vChainCount != 0)
        {
          if (cr != e.EVictim) { ADD_TARGET(cr); }
          if (!isMulti) goto OuterBreak;
        }

The first creature in the line is added to the target list and the walk stops.
The chosen victim is never reached. `DoHits` at `:2121` then applies the effect
to everything in that list with no friend filter, so an ally takes it in full.

## What to build

Change the `!isMulti` case only. **Beams are unchanged**: `isMulti` means the
effect strikes everything in the line by design, and that stays true.

Two paths, decided by whether the effect carries `EF_ATTACK`:

**With `EF_ATTACK`** — the effect rolls to hit (`Magic::MagicStrike`,
`src/Magic.cpp:916-923`). Apply the band rule exactly as phase 2 does for
arrows: −4 per square in the line holding a creature, −4 more if the target is
not the head of its own square, one roll, and on a miss the band selects which
square's head creature is struck. A natural 20 hits the target.

**The defence it rolls against is the touch defence from phase 1, not
`A_DEF`.** `src/Magic.cpp:921` currently sets `e.vDef = e.EVictim->GetAttr(A_DEF)`.
A spell's ranged touch attack must use `TouchDef`. A weapon attack keeps
`A_DEF`.

**Without `EF_ATTACK`** — the effect makes no roll at all, so it has no bands.
It passes every creature in the line and reaches the chosen target. Nothing in
between is touched. This is what makes Magic Missile behave as its own
description promises.

**Precise Shot does NOT apply to spells.** The SRD feat names ranged weapons.
Do not read the feat here.

## Two traps

**The static iterator.** `Map::GetAt` keeps its cursor in static locals
(`src/Display.cpp:1439-1440`), so one iterator serves the whole game and a
nested scan corrupts both walks. Copy a square's creatures into a local array
before moving on, the way `src/Fight.cpp:1036-1039` does.

**The monster aiming predictor.** `Magic::PredictVictimsOfBallBeamBolt`,
`src/Magic.cpp:2159`, walks the same path separately so the AI can judge a
shot. It MUST change with the real walk. If you leave it alone, monsters will
aim by a rule the game no longer uses, and nothing will fail to tell you.

## The check

Reuse phase 2's forced-roll probe. Assert, for a bolt fired along a line with a
known number of occupied squares:

- with `EF_ATTACK`: which creature is struck at each band's two boundaries, at
  a natural 20, and at a roll below the bare touch defence;
- without `EF_ATTACK`: an ally standing directly in the line is **unharmed**
  and the chosen target takes the effect;
- a beam still strikes everything in the line.

**Prove the check RED before the change and GREEN after.** The ally-unharmed
case must be red against today's code — that is the defect this epic exists to
fix.

## Marking

The bolt's hard stop at the first body is **upstream's defect**, not the port's.
The path walk depends on no integer width, no typedef and no platform; it
behaves identically on Win32 with the original types. Leave an `upstream:`
comment at the fix site stating four things and nothing else: what must be
true, the evidence tier, the tracking id `inc-30ps.3`, and that it has not been
sent. Keep it under 30 lines — `tools/check_comment_budget.sh` enforces that.
The reproduction and the argument belong in the bead, not the source.

The cover rule itself is NOT a base-code bug. It is a deliberate rules change
and MUST NOT be marked `upstream:`.

## Rules for this run

- Build ONLY with `BACKEND=posix ./build_macos.sh`. Never run `./incursion`.
- Run NO git commands. Run NO `bd` commands.
- Never delete or weaken an existing guard, bounds check, invariant or
  assertion to make new code fit. If one blocks you, STOP and report it with
  its file and line.
- Stay in scope. No unrelated whitespace or formatting changes.
- **Report what you REMOVED**, listed separately from what you added.
- If you believe this brief is wrong, say so with evidence and do not implement
  what you believe is wrong.
