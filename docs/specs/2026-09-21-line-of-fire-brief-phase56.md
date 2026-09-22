# Brief — phases 5 and 6 of inc-30ps: the effect declarations

Both phases edit `lib/*.irh` and nothing else, so they run together. Read
`docs/specs/2026-09-21-line-of-fire-spec.md`, sections "Scope: the 33 bolt and
ray effects", "Phase 5" and "Phase 6". Phases 1, 2, 2b and 3 are already in the
tree with four green checks; do not break them.

**Do not touch `src/` at all.** The engine work is finished.

## Phase 5 — fifteen effects gain an attack roll

Add `EF_ATTACK` to the primary block of each. The flag is what makes
`Magic::MagicStrike` (`src/Magic.cpp:916`) roll to hit; without it the effect
lands automatically or is resisted only by a saving throw.

**Converting from a saving throw.** Each of these describes one projectile
striking one creature, and each resolves on a Reflex save its own text calls
dodging. A save that represents dodging a single projectile is an attack roll
with the die on the wrong side of the table. Add `EF_ATTACK` and **remove the
saving throw that governs the damage**:

    Caustic Vitae      lib/pspells.irh:1368
    Chill Blood        lib/wspells.irh:1541
    Fire Bolts         lib/m_items.irh:1875
    Thunderbolts       lib/m_items.irh:2180
    Striking;wand      lib/m_items.irh:2354
    Venom of Khasrach  lib/religion.irh:3089

**Where a save governs a rider rather than the damage, the rider keeps it.**
Thunderbolts is the worked example: its Fortitude save against being stunned
stays, and only the Reflex save against the damage goes. Read each block before
you cut anything — several have `and EA_INFLICT` riders with their own `sval`.

**Because the SRD says so.** Add `EF_ATTACK`, leave the rest alone:

    Acid Arrow             lib/wspells.irh:2744
    Disintegrate           lib/wspells.irh:8582   (keeps its Fortitude save --
                           the SRD spell needs the attack roll AND the save)
    Telekinesis;thrust     lib/wspells.irh:7908
    Telekinesis;psi-thrust lib/alchemy.irh:2283
    the Ram                lib/m_items.irh:4697

**Because their own prose already promises one.** Add `EF_ATTACK`:

    Force Bolt      lib/wspells.irh:1009
    Icelance        lib/wspells.irh:4634
    tongue of flame lib/m_items.irh:7368
    Alicorn Lance   lib/pspells.irh:1518

Two of those also need their text or values changed:

- **Icelance** `lib/wspells.irh:4634` — its description says *"It automatically
  hits"*. That clause is now false. Replace it with a ranged touch attack. Its
  Fortitude save against the stun rider stays.
- **Alicorn Lance** `lib/pspells.irh:1518` — becomes **3d6 force damage with a
  ranged touch attack and NO saving throw**, following the Silver Marches
  printing, whose damage ours already matches. Today it is `xval: AD_PIERCE`
  with `sval: REF` and `Flags: EF_PARTIAL`. Its description must match: it
  currently promises *"a saving throw for half damage"*, which will be a lie.
  Keep the ghost-touch sentence — that part is unchanged.

**DO NOT touch `Call Companions`, `lib/pspells.irh:757`.** It is not an attack.
It teleports the caster's allies onto a chosen empty square and carries
`aval: AR_BOLT` only to reach that square. It must not gain `EF_ATTACK` and its
`aval` must not change.

**DO NOT touch** Magic Missile, Force Missiles, Acid;wand (they stay unerring
and that is now correct), Dispelling, Bodak Death Gaze or Surtension (all
unchanged by the owner's ruling), or Vitriolic Sphere (tracked separately as
`inc-e2p7`).

## Phase 6 — Minor Drain becomes a touch spell

`lib/wspells.irh:1502`. It deals damage at range and heals the caster the same
amount, for one mana, at first level. The owner judged that too strong at range.

Change `aval: AR_BOLT` to `aval: AR_TOUCH` and drop its
`qval: Q_DIR|Q_TAR|Q_LOC` entirely, matching Chill Touch at
`lib/wspells.irh:1516`. Rewrite the description to say it is delivered by
touch.

**No engine change is needed.** `Magic::ATouch` (`src/Magic.cpp:2365`) arms a
`TOUCH_ATTACK` stati and `src/Fight.cpp:5234` discharges it inside an ordinary
melee attack, so the attack roll comes free from the existing melee path. Do
not add `EF_ATTACK` here.

Its `On Event EV_MAGIC_HIT` handler, which heals the caster, is unchanged.

## The checks

**Phase 5 — a structural check over `lib/`.** Assert the flag and save fields
of all fifteen, so the set cannot drift back. Assert also that Call Companions
has neither `EF_ATTACK` nor a changed `aval`, and that Magic Missile, Force
Missiles and Acid;wand still carry no `EF_ATTACK`. Follow the shape of the
project's existing structural checks in `tools/`.

**Phase 6 — a behaviour check.** Minor Drain cannot be cast at a distant target
or at a bare square, and its heal still fires on a successful touch.

**Prove each check RED before the change and GREEN after** and report both.

## Rules for this run

- The module must be rebuilt: `BACKEND=posix ./build_macos.sh`. Never run
  `./incursion`.
- Run NO git commands. Run NO `bd` commands.
- Never delete or weaken an existing guard, bounds check, invariant, assertion
  or test. If one blocks you, STOP and report it with file and line.
- No unrelated whitespace or formatting changes. These are data files and a
  reformat hides the real diff completely.
- **Before you finish, run all four existing checks** —
  `tools/check_line_of_fire.sh`, `tools/check_line_of_fire_spell.sh`,
  `tools/check_touch_defence.sh`, `tools/check_comment_budget.sh` — and report
  each result. A data change can move a spell out from under an engine check.
- **Report what you REMOVED**, listed separately. Every deleted `sval` counts.
