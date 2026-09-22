# Brief for Codex — phase 1 of inc-30ps: the touch defence

Normative spec: `docs/specs/2026-09-21-line-of-fire-spec.md`, section
"Touch defence" and "Phase 1". Read both before you start. Implement phase 1
ONLY. Do not start phases 2 to 6.

## What to build

A touch defence for a creature: its defence class with worn protection taken
out. It equals `A_DEF` less the contributions of three bonus slots:

    BONUS_NATURAL  23   natural armour
    BONUS_ARMOUR   24   worn armour
    BONUS_SHIELD   30   shield

The pattern to copy is `A_CDEF`, which already does exactly this subtraction
for a different set of slots. It is computed twice, once in each branch of
`Creature::CalcValues`, at `src/Values.cpp:1491` and `src/Values.cpp:1526`:

    Attr[A_CDEF] = Attr[A_DEF] -
        (max(0,AttrAdj[A_DEF][BONUS_WEAPON]) + max(0,AttrAdj[A_DEF][BONUS_INSIGHT])
       + max(0,AttrAdj[A_DEF][BONUS_DODGE]) + (HasFeat(FT_COMBAT_CASTING) ? 2 : 4));

Yours takes the same shape over the three slots above, with no feat term and no
constant term. Use `max(0, ...)` on each slot for the same reason that code
does: a negative adjustment must not raise the touch defence.

The first branch writes `thisc->KAttr[...]`; the second writes `Attr[...]`.
Both need the new value.

## The one hard constraint

**It MUST NOT be a new slot in the `Attr` array.** Do not raise `ATTR_LAST`.

`ATTR_LAST` (`inc/Defines.h:1809`, currently 41) sizes `Creature::Attr`
(`inc/Creature.h:226`), and that array is serialised whole as field 269:

    FIELD_ARRAY(269, Attr, sizeof(int16), ATTR_LAST);   inc/Creature.h:187

It is read back by four loops in `src/SaveV1.cpp` at lines 3540, 3640, 3795 and
3963. Raising `ATTR_LAST` changes that field's length, and every save on disk
carries the old length. `docs/SAVE-SCHEMA-SPEC.md` forbids it: append only,
never reorder, never resize in place.

So add a new `int16` member to `Creature` and give it **the next free
field-map id**, appended after the current highest id in that map. Find the
highest yourself; do not guess. Old saves then load unchanged and simply lack
the new field.

## What must NOT change

Nothing reads the touch defence in this phase. Do not wire it into
`Magic::MagicStrike`, do not touch `src/Fight.cpp`, and do not change any
`lib/*.irh` file. Those are phases 2, 3 and 5.

Do not remove or weaken any existing guard, bounds check, invariant or
assertion. If one blocks you, stop and report it with its file and line.

## The check

Leave one runnable check behind. The smallest thing that fails if the logic
breaks:

- an armoured creature's touch defence is lower than its `A_DEF` by exactly
  the armour, shield and natural-armour contributions;
- a creature wearing none of the three has a touch defence equal to its
  `A_DEF`.

Prove the check RED before the change and GREEN after. A check that cannot
fail is not evidence. Put it wherever the project's existing checks live and
follow their shape.

## Build

    BACKEND=posix ./build_macos.sh

That produces `incursion-headless` and compiles the module inside the sandbox.
Do NOT run `./build_macos.sh` without `BACKEND=posix`, and never invoke
`./incursion` — it is the SDL binary and it cannot run in your sandbox.

## Rules for this run

- Run NO git commands. Leave every change in the working tree.
- Run NO `bd` commands. Do not open, close or annotate any issue.
- Stay in scope. No unrelated whitespace or formatting changes.
- **Report what you REMOVED**, separately from what you added. List every
  deletion.
- If you believe this brief is wrong, say so in your report with evidence and
  do not implement what you believe is wrong.
