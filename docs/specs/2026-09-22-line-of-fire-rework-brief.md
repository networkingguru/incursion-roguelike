# Brief — the band resolution is replaced by a saving throw

This reworks code that is already written and green. Read
`docs/specs/2026-09-21-line-of-fire-spec.md`, section **"The rule"**, first —
it was rewritten on 2026-09-22 and it is normative. Its "Worked example,
normative" is the acceptance test. The owner's exact words are in the notes of
bead `inc-30ps`.

Everything below is one change. Do it as one pass, not six.

## 1. The band now names a square, and a saving throw decides who is hit

What exists today: the band selects a square's **head creature** and strikes
it, unconditionally.

What must exist: the band selects a **square**. Every creature in that square,
in contents-chain order, makes a **Reflex save** at DC `10 + (total - D)`,
where `total` is `vHit + vRoll` and `D` is the intended target's **base**
defence, before any −4. **The first creature to FAIL takes the hit. If they all
save, the shot is a miss** — no other square is tried, and nothing else
happens.

Beating `D + 4N`, or rolling a natural 20, still hits the target with **no
save at all**. That part does not change.

This applies to both paths: `Creature::RAttack` in `src/Fight.cpp` and the
spell path reached through `Magic::MagicStrike`.

## 2. The band must fire only on a genuine roll-based miss

**This is a live defect and the most damaging one here.** The band is currently
gated on `!e.isHit`. `Creature::Strike` reports a miss down five paths that
never compare a roll to a defence: displacement and blur (`MISS_CHANCE`), the
25% tree-elevation cover, the 50% tower-shield cover, the 50% corner-cover roll
(`src/Fight.cpp:4808-4830`), and `FLAWLESS_DODGE` (`:4946`), which clears
`isHit` *after* a hit. `vRideCheck` does it too — the hit test is
`vHit + vRoll >= max(vDef, vRideCheck)`.

In every one of those the total is at or above `D + 4N`, so the band index
lands past the end and the "cannot happen" clamp fires, redirecting the shot
into the body nearest the target. **A natural 20 at a displaced target
currently shoots your own ally, every time.**

Gate the band on `total < D + 4N` — an arithmetic miss — never on `!e.isHit`.
Those five paths are misses outright and must leave the line alone.

## 3. The creature struck takes its OWN damage

Today `e.Dmg` is chosen from the **target's** size (`vicSize` from
`e.EVictim->GetAttr(A_SIZ)`) and `e.DType` from `DamageType(e.EVictim)`, and
the band victim inherits both. Shoot a Large ogre with a rat in the way and the
rat takes the ogre's large-weapon roll.

Recompute the damage dice and the damage type against the creature actually
struck.

## 4. The empty-square rule applies to spells too

`docs/specs/2026-09-21-line-of-fire-spec.md`, "A shot with no chosen creature",
was implemented for weapons only. `src/Magic.cpp` still routes a bolt with no
`e.EVictim` to the old branch, so a bolt aimed down a corridor kills the first
ally it meets with certainty.

Apply the same rule there: one creature in the whole path and it IS the target,
with no penalty; more than one and a single roll is compared at a flat −4
against each candidate's own defence in order, the first it beats being struck.
**No saving throw in this case** — there is no intended target to supply `D`,
so there is no DC. The spec says so and explains why.

## 5. Clamp the index

`src/Magic.cpp` fills `lofHeads[128]` under a guarded `i < 128` loop, then
passes the **unclamped** `lofCount` on as `N`. The band is clamped to `N-1`, so
a line crossing more than 128 occupied squares reads past the array.
`src/Fight.cpp` caps on write and is correct; copy that.

## 6. `MM_PROJECT` and `AR_RAY` fall into the new walk unintended

The dispatch in `Magic::ABallBeamBolt` sets `isBeam = true, isMulti = false`
for both a projected touch spell (`MM_PROJECT`) and `AR_RAY`, so both now take
the new `!isMulti` branch and pass every intervening body. Nobody specified
that.

Worse for `MM_PROJECT`: it carries `aval == AR_TOUCH`, so `MagicStrike`'s guard
(`aval == AR_BOLT || aval == AR_RAY`) never fires. **A projected touch spell is
currently unblockable and takes no cover penalty at all.**

`AR_RAY` has a second problem: the walk runs with `isBeam = true` — a range
break, and the `dist == 1` snap-to-target skipped because it is guarded
`!isBeam` — while `MagicStrike` asks the predictor with
`isBeam = (aval == AR_BEAM)`, which is **false**. The two disagree, so the
cover count can name squares the ray never crosses.

Make the cover count and the real walk use the same geometry, and decide
explicitly what a projected touch spell does rather than letting it fall
through. A ray is a bolt for this rule; say so in one comment at the site.

## 7. The predictor has side effects and is now called mid-spell

`Magic::PredictVictimsOfBallBeamBolt` calls `o.Activate()` on the map Overlay.
`Overlay::Activate` (`src/Display.cpp:1638`) **wipes every glyph slot and the
glyph count**, and its `DeActivate` leaves the overlay inactive. `MagicStrike`
now calls the predictor from inside `ABallBeamBolt`'s own active overlay
region, so the projectile animation's buffer is destroyed mid-flight and the
overlay stays off for the rest of the spell, including the next arc of a chain.

Cosmetic, but real. Either give the predictor a side-effect-free path for this
use, or save and restore the overlay around the call. Do not simply delete the
`Activate` — read why it is there first.

## The checks

Rework `tools/check_line_of_fire.sh` and `tools/check_line_of_fire_spell.sh`
rather than starting over. The existing forced-roll probe stays. You will also
need to force the **saving throw**, or the new rule cannot be tested at a
boundary — add a second forced-outcome hook in the same style, off by default.

Assert at least:

- the target is hit with no save at `D + 4N` and on a natural 20;
- in a band, the **second** creature of the square is struck when the first
  makes its save, and the **third** when the first two do;
- a square whose creatures all save produces a **miss**, and no other square is
  tried;
- the DC is `10 + (total - D)`: test at two different bands and confirm the DC
  the probe logs;
- a **displaced or blurred** target produces a clean miss and **no** bystander
  hit, including on a natural 20 — this is defect 2 and it must be red first;
- the struck bystander's damage uses **its own** size and type, not the
  target's — defect 3, also red first;
- a spell bolt aimed at an empty square past several creatures obeys the
  empty-square rule.

**Prove every new assertion RED before the change and GREEN after, and report
both.** A check that cannot fail is worse than no check; this project has
caught five of them.

**One existing hole to close while you are in there.** Both probes' `whoWasHit`
helpers return the *first* creature found below full hit points, in a fixed
order. So a case reports PASS even if a second creature was also damaged. Make
`whoWasHit` return `"MULTIPLE"` when more than one creature lost hit points,
and fail the case on it. Every case must assert exactly one casualty, not at
least one. This matters much more under the new rule, where a square is walked
creature by creature.

`tools/check_touch_defence.sh` and `tools/check_comment_budget.sh` must still
pass. Run them and report.

## Hard rules

- Build ONLY with `BACKEND=posix ./build_macos.sh`. Never run `./incursion`.
- Run NO git commands. Run NO `bd` commands.
- **Never delete or weaken an existing guard, bounds check, invariant,
  assertion or test to make new code fit.** If one blocks you, STOP and report
  it with its file and line. On this project that has re-opened a real
  out-of-bounds read once already, and everything stayed green afterwards.
- Do not touch `src/SaveV1.cpp` — another change is in flight there.
- Do not touch any `lib/*.irh` file.
- No unrelated whitespace or formatting changes.
- Keep any comment block at or under 30 lines; `tools/check_comment_budget.sh`
  enforces it and the detail belongs in the bead.

**Report, under 700 words:** what changed, file by file; **everything REMOVED,
listed separately**; the RED and GREEN output for each new assertion; the other
check results; and anything that surprised you or that you believe this brief
got wrong. Five briefs on this epic have each contained a real error and every
agent that flagged one was right.
