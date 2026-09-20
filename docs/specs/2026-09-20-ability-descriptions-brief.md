# Brief: class abilities on the My Character page

Goal: a character can read what each of his class abilities does, on the My
Character page and nowhere worse than the character sheet leaves him today.

Spec: `docs/specs/2026-09-20-ability-descriptions-spec.md`. Bead: inc-nbjf.
Branch `inc-nbjf`, worktree `~/Scripts/Incursion-inc-nbjf`. Lane `fix:`.

Stack: C++ engine, `BACKEND=posix ./build_macos.sh` for the headless binary,
`./build_macos.sh` for the SDL one. Checks are bash under `tools/`.

## Files touched

| File | What happens to it |
|---|---|
| `src/Tables.cpp` | Gains `AbilInfo[]`, the table `inc/Globals.h:242` declares and nothing defines. One row per described ability: id, name, description. Carries the `upstream:` marker. |
| `src/Help.cpp` | Gains `DescribeAbility(int16)`, shaped like `DescribeFeat` at `src/Help.cpp:4547`. `HelpCustom` at `src/Help.cpp:1264` gains the My Abilities section, between My Domains and My Feats. |
| `inc/Globals.h` | Declares `DescribeAbility` beside `DescribeFeat` at `:244`. |
| `tools/check_ability_descs.sh` | New. The four assertions of spec §4, plus `--selftest`. Marked `# gate: cheap`. |
| `tools/ability_descs.live` | New. The abilities that must carry a description. |
| `tools/ability_descs.exempt` | New. The abilities that do not work yet. Shrinks only. |
| `tools/README.md` | A row for the new check in the checks table. |
| `docs/REPORTING-GATE.md` | A row in "Base-code bugs fixed locally". |
| `docs/evidence/inc-nbjf/` | The audit verdicts, the before and after pages, the selftest transcript. Untracked unless a PR needs it. |

## Phases

Each phase is one commit. Codex implements; this session reviews the diff before
the next dispatch.

**0. Record the before.** Capture the My Character page for a fixture character
who holds class abilities, with `tools/headless.sh`. Run
`tools/nightly_verify.sh --record`. No source changes. This is the only phase
that must happen before any edit, because the before-state stops existing
afterwards.

**1. Wire the mechanism.** Define `AbilInfo[]` with rows for four abilities
only -- Devouring plus three whose implementation is already understood. Add
`DescribeAbility` and the My Abilities section. Build both backends. Verify the
page now shows those four with their text and every other held ability with its
bare name. The point of a four-row table is that the wiring is proved before
eighty more rows hide a fault in it.

**2. Pin the list and add the check.** Write `ability_descs.live` and
`ability_descs.exempt` from the audit in `docs/evidence/inc-nbjf/`. Write
`check_ability_descs.sh` with its four assertions. Prove each assertion red
with `--selftest`, then green. Register it: the `# gate: cheap` marker, the
`tools/README.md` row. The check fails at this point, because the table holds
four rows and the live list holds many. That failure is the ratchet working.

**3. Write the descriptions.** Research agents read each ability's
implementation and return prose; they touch no file. One Codex dispatch inserts
every returned row into `AbilInfo[]`. The check goes green. Devouring's text
follows spec §5 and states its cost in divine standing, which is the part no
player can currently discover.

**4. Observe and mark.** Capture the after page against the before from phase 0.
Add the `upstream:` comment at the table, the ledger row in
`docs/REPORTING-GATE.md`, and `bd label add inc-nbjf upstream`. Run
`tools/nightly_verify.sh --compare`.

## Test plan

- **Adversarial.** A character holding an ability with no `AbilInfo` row still
  renders, showing the bare name rather than an empty entry or a crash. A
  character holding no abilities at all renders the section empty rather than
  omitting the heading inconsistently. An `AbilInfo` row whose id is not in
  `ClassAbilities` is caught by assertion 3. A name that disagrees between the
  two tables is caught by assertion 2. The page for a character holding many
  abilities does not truncate.
- **User-focused.** Load a fixture character, open help, reach My Character,
  read the new section, and confirm the abilities listed match the ones the
  character sheet lists. The sheet and the page both test `AbilityLevel`, so a
  disagreement is a real fault.
- **Live data.** A seeded session through `tools/headless.sh` with a named
  `INCURSION_OPTIONS`, and the SDL binary opened on the same character so the
  section is read as a player sees it, not only as text.
- **Regression.** `tools/nightly_verify.sh --compare` against phase 0's record.
