**SUPERSEDED 2026-11-07** by `docs/superpowers/specs/2026-11-07-names-in-the-file-design.md` and its plan (Brian chose names in the file). Not built past phase 0.

# Numbers land on master: implementation brief

Bead: inc-cjos0. Sized: Large. Spec (read it first, it is the authority):
`docs/superpowers/specs/2026-11-06-numbers-land-on-master-design.md`,
revision 3. Section numbers below (4.3, C2, AC4) refer to it.

**Goal:** two branches can never give one stored number two meanings, and
nobody edits a number by hand. A bead that needs a number writes a name in
`inc/landed-<bead>.num`; the build numbers it; landing on master writes the
literal.

**Architecture:** one generator (`tools/gen_numbers.py`) that every build
and every hook runs; one master ledger (`tools/number.ledger`) that only the
finalizer writes; one finalizer (`tools/finalize_numbers.py`) that
`tools/finish_bead.sh` runs when the base is master.

**Stack:** Python 3 (stdlib only), bash, git hooks, the script compiler
(`lang/Grammar.acc`, `src/RComp.cpp`), the headless build
(`BACKEND=posix ./build_macos.sh`).

**Execution:** route each phase by the coding row of
`.claude/rules/codex-dispatch-and-orchestration.md`. Run
`tools/claude_budget.py` and `bd memories out-until` before EACH coding
dispatch (2026-11-06: `sonnet-first`). Work happens in the worktree
`~/Scripts/Incursion-inc-cjos0`. Claude reviews each diff and commits it
before the next phase. Every new check carries a `--selftest`, a `# fact:`
header per AGENTS.md, and is shown red before green. Phases 1-3 MUST change
no evaluated value: each ends with the value diff of phase 0 at zero.

## Files touched

| File | Change |
|---|---|
| `tools/number_values.py` | New (phase 0). Dumps every evaluated integer define, enum member and tag literal with its file:line, for before/after diffs. Becomes the parser core of the generator. |
| `src/SaveV1.cpp`, `inc/*.h` with `ARCHIVE_CLASS`/`FieldsV1` | Scope markers, `v1PutTag`, tag-family defines (phase 1). |
| `inc/Defines.h`, `inc/*.h`, `src/*.cpp` | Family marks, explicit enum values, feat chain literals, sentinel rows (phase 2). |
| `src/Tables.cpp` | Positional tables converted to keyed rows (phase 3). |
| `tools/number_spaces.txt` | New. Every space (4.3). |
| `tools/gen_numbers.py` | New. Generator and checks C1-C5, ledger guard, `--check`, `--value` (phase 4). |
| `tools/number.ledger` | New. The harvest (phase 4). |
| `inc/Defines.h`, `.gitignore` | Include and ignore `inc/Numbers.h` (phase 5). |
| `build_macos.sh`, `tools/linux_docker.sh`, `tools/package_linux.sh`, every direct `inc/` compiler | Run the generator first; python3 and new image tags (phase 5). |
| `tools/check_shadow_shifting.sh`, `tools/check_auto_terms.sh`, `tools/check_dump_save.sh`, `tools/check_v1_full_roundtrip.sh` | Read values through `--value` (phase 5). |
| `.beads/hooks/pre-commit`, `.beads/hooks/pre-merge-commit`, `.beads/hooks/pre-push` | The checks (phase 6). |
| `tools/finalize_numbers.py`, `tools/finish_bead.sh` | Finalizer and landing steps (phase 7). |
| `tools/make_char_fixture.sh`, `tools/remake_stale_fixtures.sh` | Recorded names and the stale loop (phase 8). |
| `lang/Grammar.acc`, `src/RComp.cpp`, `tools/check_landed_files.py` | `Extend` and the frozen own-variable rule (phase 9). |
| `tools/convert_branch_numbers.py` | New (phase 10). |
| bands files, `docs/SAVE-SCHEMA-SPEC.md`, `docs/VERIFICATION.md`, `.claude/rules/`, `tools/README.md` §7 | Retire and document (phase 11). |
| `tools/pressure_numbers.sh` | New, the AC8 driver (phase 12). |

## Phases (one commit each, lane `tools:` unless stated)

0. **Value dump.** Write `tools/number_values.py`: evaluate C integer
   expressions in every integer `#define` in `inc/` and `src/`, every enum
   member, and every literal tag argument (with its scope once phase 1
   marks scopes). Output one sorted line per value, keyed on a stable
   identity: the define or enum name, or for a tag the scope and the 4.2
   normalized label (or the call site for a non-`FIELD_*` tag); file:line is
   a printed column that the diff ignores. A tag that phase 1 turns into a
   family define keeps its identity through a mapping the dump prints. Write
   master's dump to `logs/number-values-master.txt` (a specimen, not
   tracked). Red: a planted `#define` value change shows in the diff; a
   line-only shift gives diff zero. This is the oracle for AC2.
1. **Tag sites** (lane `port:`; no behavior change). Add a
   `/* tag-scope: <space> */` marker to every `ARCHIVE_CLASS` body,
   `FieldsV1` body, `V1EmbedBegin` site and helper body holding a
   tag-taking call (4.3). Turn raw `v1PutU16` tag writes into `v1PutTag`
   (a one-line inline, same bytes). Give every non-`FIELD_*` tag literal a
   tag-family define (`// family: tag-<space>`, 4.2). Oracle: phase 0 diff
   zero; `-schematest` round-trips; the 88 character fixtures load
   (`tools/check_char_fixture.sh` plus the fixture consumers in the fast
   tier).
2. **Families, enums, sentinels** (lane `port:`), in three runs, each with
   the oracle phase 0 diff zero and `tools/check_define_dups.py` green:
   - 2a. Extend `// family:` marks (a mark covers the block below it) to
     every integer define: one run each for `inc/Defines.h`, the rest of
     `inc/`, and `src/` (about 4500 numeric defines, 205 marks today); a
     no-family block carries a reason.
   - 2b. Give every stored enum explicit values; rewrite the feat chain to
     absolute literals (`FT_FIRST` 50).
   - 2c. Write `tools/number_spaces.txt` with every space, the
     `stored`/`internal` flag, `<storage>`, runs, the tag-taking call list
     and the `derived` sentinel rows (skill high 48, 4.3).
3. **Keyed tables** (lane `port:`). Convert every positional table in
   `src/Tables.cpp` indexed by a space value to keyed rows indexed at
   startup; a missing or duplicate key aborts at startup. Oracle: a startup
   dump of each table before and after is identical; the gate's fast tier
   green. Red: a planted duplicate key aborts.
4. **Generator**, `tools/gen_numbers.py` on the phase 0 parser, in three
   runs, each with its own selftest red cases:
   - 4a. Inputs, 4.1 order, assignment, output with `static_assert`,
     `<ENUM>_LANDED` and `<TABLE>_LANDED` macros, `--value NAME`, the
     harvest into `tools/number.ledger`. Oracle: the harvest reproduces the
     phase 0 dump exactly (AC2).
   - 4b. C1 and C5, the master-branch refusal (4.4). Red per AC1.
   - 4c. C2-C4 and the ledger guard (4.6), with its bootstrap: while
     `master:tools/number.ledger` does not exist, the guard accepts a tree
     ledger only when it equals a fresh harvest of the tree. Red per AC3
     (build level), plus a hand-edited harvest row refused.
5. **Build wiring.** `inc/Defines.h` includes `inc/Numbers.h`; add it to
   `.gitignore`. Then insert what needs the header: `<ENUM>_LANDED` at the
   end of every stored enum, `<TABLE>_LANDED` at the end of the 43
   `*_CONSTNAMES` tables and `STATI_CONSTNAMES`, the `/* landed: <space> */`
   anchors, the 4.5 conversions (sentinels to `NUM_` names, revisions 1-6 to
   `REV_` literals, `SCHEMA_REV` and `OPT_GEN_CURRENT` derived). Oracle for
   the insertions: phase 0 diff zero, and an empty `.num` set gives macros
   that expand to nothing. Run the generator first in `build_macos.sh` and every
   direct compiler the sweep finds (`grep -l` for `-Iinc` and `inc/` in
   `tools/`); python3 in both Docker images with new image tags; module
   freshness counts `inc/landed-*.num`; the four tools read through
   `--value`. Oracle: SDL and headless builds, `tools/linux_docker.sh` build,
   each converted tool green; a planted `.num` with a full space fails the
   build naming the space.
6. **Hooks.** pre-commit runs `gen_numbers.py --check`; new
   pre-merge-commit runs only that; pre-push refuses a `.num` on master.
   Red per AC3 in a scratch repo under `logs/`: a planted collision refused
   at commit, at a clean merge, and at push.
7. **Finalizer and landing.** Write `tools/finalize_numbers.py` (4.7) and
   wire it into `tools/finish_bead.sh` after STEP 3: `PRE_FINAL`, the trap
   guard, the allowance export, `gen_numbers.py --check` in STEP 3b and
   STEP 4b, the STEP 5 ancestry refusal (4.9). One-time step for this bead's
   own landing: after STEP 3, re-run the harvest, commit it, and refuse with
   the list of unclassified sites when C1 fails (master moved after phase
   4). Selftest on `selftest_merge_repo` scratch repos: AC4 (one name per
   space kind, one `retire`, one `rename`), AC5 (gate fails after
   finalizing; master moves during a landing), and a collision refused at
   STEP 3b (AC3, landing). Separately, in
   `~/Scripts/nightly-harness` (its own repository, own commit): its master
   merge takes the landing lock.
8. **Fixtures.** `tools/make_char_fixture.sh` records the provisional
   `(space, NAME, value)` list in `.sheet.txt`; write
   `tools/remake_stale_fixtures.sh` (4.12) and call it from
   `tools/finish_bead.sh` before the gate and from the merge-bead path; it
   commits re-made fixtures on the bead branch. Oracle: AC9 in a scratch
   repo, both halves (moved number re-made; unmoved number untouched,
   landing on master included).
9. **Extend** (lane `port:`, no player-visible change). Add `Extend` to the grammar with the pre-pass
   (4.10); extend `tools/check_landed_files.py` to refuse an own variable
   appended to an existing resource. Oracle: AC6, and the module compiles
   byte-identical before and after on master.
10. **Conversion.** Write `tools/convert_branch_numbers.py` (section 5).
    Besides names and `retire` lines, it adds family marks, explicit enum
    values and scope markers to branch-only code, so C1 passes with no hand
    edit. Run it in a scratch worktree of inc-pu6v at d71c1823 merged with
    the inc-cjos0 head (which contains e94c7d4b and these tools) (AC7): C1
    and the build are green with zero edits outside the converter, and
    Character tags 439 and 441-443 become new names plus `retire` lines. Run it unchanged on one god branch. The
    real conversion runs later, in the master-into-epic merge bead.
11. **Retire and document.** Delete the bands files and their pre-commit
    block (4.11); update `docs/SAVE-SCHEMA-SPEC.md`, `docs/VERIFICATION.md`,
    a `.claude/rules/` entry in rule-entry format, `tools/README.md` §7, and
    one line in `tools/opencode/brief_preamble.md`: a new number is a name in
    `inc/landed-<bead>.num` (AC10). Lane `docs:` for the prose part.
12. **Pressure test.** An independent adversarial agent (Opus, research
    label, no tracked edits) designs the AC8 cases; an implementer writes
    them into `tools/pressure_numbers.sh`; the main session runs it and
    records each case and result in the bead.

## Acceptance criteria to phase

| AC | Phase |
|---|---|
| AC1 | 4b |
| AC2 | 0, 1, 2a-2c, 3, 4a, 5 |
| AC3 | 4c, 6, 7 |
| AC4, AC5 | 7 |
| AC6 | 9 |
| AC7 | 10 |
| AC8 | 12 |
| AC9 | 8 |
| AC10 | 11 |
