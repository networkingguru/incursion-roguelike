# AC9: the clone's master (inc-cjos0 + clone-prep.patch) merged into the real branch inc-10v7f, then landed

Side names: HEAD = inc-10v7f (4e374de2); master = the clone's master (87d031e1 = f8a70246 plus the mode change of
`tools/check_family_cases.py`). The merge commit passes the hooks and the numbers-by-hand check (0 merge-made lines with a
digit). `ac9.sh land10` then landed it on the clone's master with `INCURSION_FINISH_GATE=tools/pressure/ac9_cheapgate.sh`
(the fast checks that `tools/finish_bead.sh` runs itself, the build, and the cheap tier of the real landing gate, green in the
2026-11-13 run): for THIS landing only, because inc-10v7f's real
landing runs its own real gate. The merge-bead landing keeps the real gate.

| File | Hunks | Choice | Reason |
|---|---|---|---|
| src/Annot.cpp | 1 | both | inc-10v7f's creation scope, then master's `DamageClassHandler(xID, e)`. |
| src/Create.cpp | 6 | 1, 2 HEAD; 3-6 mixed | 1, 2: inc-10v7f's sourced skill screen (`SourcedRoll(CK_SKILL_RANKS...)`, `CommitSkillRanks`) and its gallery/seed decisions replace master's `reincarnate` code, which master changed only by `SK_LASTSKILL` -> `SK_COUNT`. 3-6: master's banded loops (`for(int k...SK_COUNT)`, `i = SkillByIndex(k)`, `SkillInfo[k]`) with inc-10v7f's `pl.Clear()` and `pl.Add(SkillInfo[k].name, i)`. |
| src/Dump.cpp | 1 | both | The canonical-dump branch (`INCURSION_DUMP_CANONICAL`) and the planter branch (`INCURSION_PLANT`), one after the other. |
| src/Managers.cpp | 1 | HEAD, plus master's loop for banded skills | inc-10v7f commits the first `SK_LAST` ranks through `CommitSkillRanks`; master's `p->SkillRanks[i] += Alloc...` line then runs for the banded indexes `SK_LAST` .. `SK_COUNT`, so a banded skill keeps its allocation. |

`post.patch` holds comment lines only: `// no-family` / `// end no-family` around five constants inc-10v7f added outside any
family (`src/CharFile.cpp` EXIT_BUILD_FAILED; `src/CreationSource.cpp` CKU_SEEN/CKU_UNSEEN, FIND_ITEM/FIND_EFFECT,
CreationPerkFieldCount; `inc/CreationSource.h` CKIND_*), which master's `tools/check_define_dups.py` refuses.

Known gap, not fixed: the sourced skill screen carries `SK_LASTSKILL` ranks (`src/Create.cpp` CK_SKILL_RANKS,
`Player::CommitSkillRanks`, `src/CreationSource.cpp` Bind). No banded skill (800-999) is defined yet, so nothing is lost today.

## Landing fixes (post.patch, applied after the hunks)

Both fail on the clone's master alone, so inc-10v7f's own landing makes them when it merges inc-cjos0:
- `docs/specs/2026-11-06-fixture-builder-sites.md`: the two bare `Creature.h:149` / `Creature.h:1512` citations name `inc/Creature.h`
  (master also holds a copy under `tools/pressure/cases/G27-conflict/resolve/inc/`, so the bare name resolved to two files).
- `tools/check_player_fields.sh`: reads the calls inc-cjos0 saves with: `FIELD_ARRAY_ROWS` and the other `FIELD_*` names with underscores, and the
  element calls `FIELD_RID_AT` / `V1Str_AT` (member in the third argument, `ClassID[i]`). The table gains the four row counters
  (`hpRollsRow`, `manaRollsRow`, `GainAttrRow`, `SacValsRow`). Its selftest mutates the name-keyed `FIELD_` lines. Red once by
  renaming `manaRollsRow` back in the table: `C7 Character field manaRollsRow is saved and not listed`.
