# Brief — phase 2b of inc-30ps: a shot aimed at a square, not at a creature

A correction to phase 2, which is already in the tree and green. Read
`docs/specs/2026-09-21-line-of-fire-spec.md`, section "A shot with no chosen
creature" — it is normative and it is short. Do not change anything phase 2
got right.

## What is wrong

`Creature::RAttack` in `src/Fight.cpp` can be entered with no intended
creature: the shooter aimed at a square. `Q_LOC` targeting does this, and so
does throwing a flask down a corridor.

Before this epic, such a shot attacked whatever it passed through, with
certainty and with no roll at all. Phase 2 wrapped the whole resolution in
`if (Intended)`, so the shot now passes every body untouched. Neither is right.
Brian ruled the replacement on 2026-09-21; his exact words are in the notes of
bead `inc-30ps.2`.

## The rule to build

**One creature in the whole path: it IS the target.** Resolve normally against
it, with **no penalty at all**. It is the only thing there is to shoot at, so
the shooter is aiming at it whether or not they named it.

**More than one: roll once.** Compare that single roll, at a **flat −4**,
against the head creature of each square along the path, in order from the
shooter. **The first square whose comparison is a hit takes the hit.** If no
comparison hits, the shot reaches its maximum range and strikes nothing.

Four things to get exactly right:

1. **Count first, then decide.** The lone-creature case takes no penalty; the
   many-creature case takes −4 on every comparison. Count the candidates — the
   head creature of each occupied square — before resolving anything.
2. **One roll, not one per square.** The same `e.vRoll` is reused for every
   comparison. Only the defender changes.
3. **The −4 is flat and does not accumulate.** The second square is −4, not
   −8. The shooter aimed at none of these creatures, so none of them is
   standing in front of another as far as this shot is concerned.
4. **Head creature only**, as everywhere else in this epic: the first creature
   in the square's contents chain, `At(x,y).Contents` walked by `Map::GetAt`.
   A square with four bodies exposes one.

Stop the walk at the first hit. Do not keep going and do not roll again.

**Precise Shot does not help here.** The feat exists to let a shooter hit the
creature they meant, and this shooter meant a square. This is an assumption
rather than Brian's ruling, so state in your report that you implemented it
that way; he may reverse it.

## Reuse, do not duplicate

Phase 2 built the line walk, the head-creature collection, and the forced-roll
probe. Use them. This is a second way of consuming the same recorded line, not
a second walk.

## The check

Extend `tools/check_line_of_fire.sh` rather than writing a new one. Add cases
that fire at an **empty square** and assert:

- **with exactly one creature anywhere in the path**: it is hit on a roll that
  meets its own defence with **no** penalty, and missed on a roll one below
  that. This is the case Brian corrected, so test both sides of the boundary.
- with several creatures, a roll that clears the first square's head defence
  by 4 or more strikes that first creature and nothing else;
- a roll that fails the first but clears the second strikes the second;
- a roll that fails every one of them strikes nothing;
- exactly one creature loses hit points in each hitting case.

**Prove the new cases RED before your change and GREEN after**, and report both
outputs. The existing nine cases must still pass — if any of them goes red, you
have broken phase 2 and must stop and say so.

## Hard rules

- Build ONLY with `BACKEND=posix ./build_macos.sh`. Never run `./incursion`.
- Run NO git commands. Run NO `bd` commands.
- Never delete or weaken an existing guard, bounds check, invariant, assertion
  or test to make new code fit. If one blocks you, STOP and report it with its
  file and line.
- Stay in `src/Fight.cpp` and `tools/check_line_of_fire.sh`, plus
  `tools/keys/line-of-fire.keys` only if genuinely needed. Do not touch
  `src/Magic.cpp`, `inc/Creature.h` or any `lib/*.irh` file.
- No unrelated whitespace or formatting changes.
- **Report what you REMOVED**, listed separately from what you added.
