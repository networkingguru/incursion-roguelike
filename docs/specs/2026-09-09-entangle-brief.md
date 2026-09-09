# Brief: entangled and anchored

Goal: give the engine the SRD's two conditions where it has one, and give each
entangling hazard its own difficulty and governing attribute.
Spec: `docs/specs/2026-09-09-entangle-spec.md`. Requirement numbers below are
that file's.
Beads: inc-18q6 (this), inc-jwm0 (closes at the end).
Stack: C++ engine (`src/`, `inc/`) plus module data (`lib/`), so phases 4 and 5
need `BACKEND=posix ./build_macos.sh`, which rebuilds `mod/Incursion.Mod`.

## Files touched

| File | What changes |
|---|---|
| `inc/Defines.h` | `ENTANGLED` at 237, `LAST_STATI` to 238, `STUCK_WEB` at 7. |
| `src/Tables.cpp` | Three rows for `ENTANGLED`: `StatiNames`, `StatiLineStats`, `StatiLineShorts`. |
| `src/Status.cpp` | A `StatiMessage` arm for `ENTANGLED`, gain and loss. |
| `src/Values.cpp` | −2 `A_HIT` and −4 `A_DEX` while entangled; `STUCK` leaves the `grappling` expression so a shield still counts. |
| `src/Creature.cpp` | `MoveAttr` halves while entangled; the −7 Reflex block for `STUCK` goes. |
| `src/Magic.cpp` | Entangled −20, anchored −40, grapple keeps −60. |
| `src/Fight.cpp` | Nine non-movement prohibitions deleted; `STUCK` out of `noDexDefense`; `AD_STUK` passes the attack's DC as `Mag`; entangling weapons keep `STUCK_WEAPON`. |
| `src/Move.cpp` | The escape branch reads the R14 table instead of `15 + Mag`; the sticky-terrain path sets a real `saveDC` and a finite duration; the sprint and jump refusals stay. |
| `src/Inv.cpp` | Picking an item up is allowed; armour stays refused. |
| `src/Skills.cpp` | Ascend and descend stay refused; nothing else. |
| `lib/dungeon.irh` | "Webbing" declares `STUCK_WEB`. Slime and rubble already declare theirs. |
| `lib/alchemy.irh` | Tanglefoot strands declare `STUCK_BONDED`. |
| `lib/mon1.irh` | Ettercap Webbing gains the Strength alternative (R18a). |
| `tools/check_entangle_escape.sh` | Extended for the per-hazard DC. |
| `tools/check_entangled_acts.sh`, `check_stuck_fights.sh`, `check_sticky_save.sh` | New, with their `tools/keys/*.keys` fixtures. |
| `README.md`, `docs/REPORTING-GATE.md` | A row per new check; a ledger row per upstream defect fixed. |

## Phases, one commit each

1. **Implement.** The two new constants and every table that names a stati:
   `ENTANGLED`, `LAST_STATI`, `STUCK_WEB`, the three `Tables.cpp` rows and the
   `StatiMessage` arm. Nothing grants `ENTANGLED` yet, so behaviour is
   unchanged. **Verify:** both builds compile; the gate is not run yet.

2. **Implement.** What entangled costs, and who grants it. R2 in `Values.cpp`,
   R3 in `MoveAttr`, R4's no-run and no-charge, R5 in `Magic.cpp`, and R17's
   grant path: a hazard grants `ENTANGLED` on a PASSED save and removes it when
   the creature leaves the square. The grant must land in this phase, because
   without it nothing can be observed to be entangled and the check has no
   subject. **Verify:** `tools/check_entangled_acts.sh`, proved red by
   reverting the `Values.cpp` block.

3. **Implement.** Anchored stops being a lockdown: R7's nine deletions, R9
   (`noDexDefense`), R10 (`grappling`), R11 (the −7), R12 (the −60).
   **Verify:** `tools/check_stuck_fights.sh`, proved red on the tree before this
   phase, asserting both halves — the anchored creature attacks AND is still
   refused movement.

4. **Implement.** Per-hazard escape: the R14 table in one place, `Move.cpp`
   reading it, R16's `Mag` from the monster attack, R18's `lib/` kind
   declarations, R18a's Strength alternative for Ettercap Webbing. **Verify:**
   the extended `tools/check_entangle_escape.sh` shows the paladin facing
   Strength DC 17 in tanglefoot, not 14; module rebuilt.

5. **Implement.** The two ride-along defects: R19's real `saveDC` and R20's
   finite duration in the sticky-terrain path. **Verify:**
   `tools/check_sticky_save.sh`, proved red by restoring either.

6. **Implement.** The paperwork the repo's own checks enforce: an `upstream:`
   comment at each fix site, a ledger row per defect in
   `docs/REPORTING-GATE.md`, a `README.md` row per new check. **Verify:**
   `tools/check_upstream_marks.sh`, `check_ledger_rows.sh`,
   `check_readme_checks.sh`, then `tools/nightly_verify.sh --compare`.

## Test plan

* **Adversarial.** A creature that is both entangled and anchored pays each
  penalty once, not twice. A creature freed from anchoring keeps entangled while
  it stands in the hazard, and loses it on leaving. An `AD_STUK` attack with no
  declared kind still gets the default row rather than DC 0. A monster whose
  attack DC is 13 does not become harder to escape than one whose DC is 20.
* **User.** The paladin fixture of `entangle-strength-escape.keys` still gets
  out, and now faces DC 17 rather than 14. A rogue in a web faces Escape Artist
  20 before Strength 25. A stuck character can swing at what stuck him.
* **Live data.** `INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
  tools/headless.sh tools/keys/dive.keys` on a seed that meets a web, watched
  for the new condition appearing and clearing rather than persisting.
* **Regression.** `tools/nightly_verify.sh --compare` at the end. Sneak attack
  and coup-de-grace change behaviour by design (R9), so any check that asserts
  them against a stuck target is expected to move; if one does, it is read
  before it is changed.

## Known consequences, accepted

Monsters gain everything the player gains, so a webbed monster now fights back.
Rogues lose sneak attack against stuck targets (R9, Brian's ruling). The ice
wand at `lib/m_items.irh:1902` becomes a debuff rather than a disable and is
left alone.
