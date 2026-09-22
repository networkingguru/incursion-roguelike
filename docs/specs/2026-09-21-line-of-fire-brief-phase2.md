# Brief — phase 2 of inc-30ps: the cover-and-band rule for weapon attacks

Normative spec: `docs/specs/2026-09-21-line-of-fire-spec.md`. Read "The rule",
including its worked example, and "Phase 2". Implement phase 2 ONLY. Do not
touch `src/Magic.cpp` or any `lib/*.irh` file.

Phase 1 (`TouchDef` on `Creature`) must be in the tree before you start.
Weapon attacks roll against `A_DEF`, not the touch defence, so you do not read
`TouchDef` here. It exists for phase 3.

## What is there today

`src/Fight.cpp:1036-1116` walks the line from shooter to target. On each
square it collects the creatures into `ptList[16]`, then:

- **`:1047-1051`** — if the target's own square holds more than one creature,
  a d100 roll picks the intended one, 95% with Precise Shot and 60% without.
  On a fail it takes `ptList[random(ptc)]`, a random creature on that square.
- **`:1071-1074`** — if the chosen creature is not the intended target, a d100
  roll decides whether to skip it: 75% skip with Precise Shot, 25% without. So
  without the feat the arrow attacks the wrong body three times in four.
- A hit stops the arrow (`if (e.isHit) break;`). A miss restores the event
  (`e = oe`) and the walk continues.

Both d100 tests are **deleted**. The hit-stops-miss-continues behaviour is
replaced too: the new rule rolls once.

## What to build

**Walk the line first and record it, before any strike.** For each square
between shooter and target, in order from the shooter, record the square and
its **head creature** — the first creature in that square's contents chain —
ignoring the shooter itself. Then record the target's own square if the target
is not the head of it.

**Copy each square's creatures into a local array before moving on.**
`Map::GetAt` keeps its cursor in static locals (`src/Display.cpp:1439-1440`),
so one iterator serves the whole game and a nested scan corrupts both walks.
The existing code at `:1036-1039` already copies for this reason. Keep doing
it.

**Then resolve one strike.** Let `N` be the number of recorded squares. Set
`e.vDef` to the target's defence plus `4 * N`. Resolve the strike as the code
does today.

**On a miss, choose the victim by band.** The raw d20 is `e.vRoll`
(`src/Fight.cpp:4203`) and the attack total is `e.vHit + e.vRoll`; the hit test
is at `:4490`. Let `D` be the target's unmodified defence. Walk downward:

    total >= D + 4*N          the target was hit (not a miss)
    D + 4*(N-1) <= total      the LAST recorded square's head creature
    D + 4*(N-2) <= total      the one before it
    ...
    D <= total                the FIRST recorded square's head creature
    total < D                 nothing is struck

"Last recorded" means nearest the target, because a better roll travels
further. The worked example in the spec is normative; make your code agree with
it exactly.

Strike the chosen creature with a normal attack against its own defence — it is
hit by construction, so do not roll again for it.

**A natural 20 hits the target** whatever `N` is. The existing
`|| e.vRoll == 20` at `:4490` must keep that true.

**Precise Shot skips everything.** With the feat, `N` is zero, there are no
bands, and the shot can never strike a body in the way. It still rolls against
the target's unmodified defence.

## The feat's description MUST be rewritten

`src/FeatTab.cpp:1633-1638` describes the deleted 25%/75% test in the player's
own words. It will be a lie the moment you delete that test. Rewrite it to
describe the new rule. Keep it to the same register and length as its
neighbours, and remember `~` is the game's percent escape.

## The check

The band boundaries cannot be tested without controlling the die. Add a probe
hook in the style this project already uses — an environment variable read
once, like `INCURSION_STACK_PROBE` and its siblings — that forces `e.vRoll` to
a given value. Gate it so it costs nothing when unset.

Then assert, for a line with a known number of occupied squares, which creature
is struck at: each band's lower boundary, each band's upper boundary, a natural
20, and a roll below the bare defence. Also assert that with Precise Shot the
target's square is the only one that can be hit.

**Prove the check RED before the change and GREEN after.** Report both.

## Rules for this run

- Build ONLY with `BACKEND=posix ./build_macos.sh`. Never run `./incursion`.
- Run NO git commands. Run NO `bd` commands.
- Never delete or weaken an existing guard, bounds check, invariant or
  assertion to make new code fit. If one blocks you, STOP and report it with
  its file and line. This is the single most damaging thing you can do here,
  because everything stays green afterwards and the loss is invisible.
- Stay in scope. No unrelated whitespace or formatting changes.
- **Report what you REMOVED**, listed separately from what you added. The two
  d100 tests are expected removals; list anything else.
- If you believe this brief is wrong, say so with evidence and do not
  implement what you believe is wrong. The last phase's brief was wrong about
  how armour works, and saying so was the right call.
