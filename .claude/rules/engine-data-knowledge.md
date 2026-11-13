# Engine and save-data knowledge

## incursion-verify-disabled-content-with-program-i
To check whether a `lib/*.irh` definition is IN the game, grep `lib/program.i` (the preprocessed source; comments and `#if 0` are already gone from it). ALWAYS use a pattern accepting either keyword and the declaration colon, since a spell compiles to `Spell "X" : N` or `Effect "X" : N` unpredictably:

    grep -ciE '(Spell|Effect) "<name>" *:' lib/program.i

Sanity-check any zero: `grep -in '"<name>"' lib/program.i` — a name can appear as an undeclared list entry. Do NOT locate `.irh` comment boundaries by hand with an anchored pattern (`grep -n '^/\*$\|^\*/$'` misses trailing whitespace after `*/` and silently extends the range). If a hand scan is unavoidable, use `awk '/\/\*/ || /\*\//'` (no anchor). Prefer `program.i`.
Why: a grep is only empirical about the exact pattern typed — confirm it matches a known-present case before trusting a zero.
History: docs/rules-history/engine-data-knowledge.md#incursion-verify-disabled-content-with-program-i.

## save-schema-append-only-supersedes-name-keys
Normative text: `docs/SAVE-SCHEMA-SPEC.md` Amendment 1. A save reference is a plain rID, no bit packing. There are 21 resource arrays.
1. NEVER reorder. NEVER delete. Append only, no exception (arrays and array kinds alike).
2. A removal is a tombstone — the line stays, keeps its position.
3. A replaced slot loading as the new resource is KNOWN/EXPECTED/INTENDED when desired; MUST NOT be reported as a defect.

Format: a per-module manifest carries each array's length in fixed order plus every entry's NAME in position order (names, not just lengths, because alphabetising changes no length). Reader converts saved rID -> (array, position) via the manifest, then via the loaded module, deferred to `SaveV1_ResolveNames`. Drift detection refuses only on a SLIDE (2+ consecutive positions shifted one slot) or a SHUFFLE (same name set, different position) — a bare rename loads silently. The engine's `Module::__GetResource` (`src/Res.cpp:102-215`) is NOT touched; the save layer alone converts.
Why: lets a save survive `lib/*.irh` reordering (which shifts rIDs) without an engine-side rewrite.
History: docs/rules-history/engine-data-knowledge.md#save-schema-append-only-supersedes-name-keys.

## nothing-is-sellable-except-gems
A character in this game can sell NOTHING except gems. NEVER raise loot resale, selling gear, or a sell-for-gold loop as a design risk, an exploit, or a question, in god design or anywhere else. An item still has a gold value (`SacrificeValue()`); only selling does not exist.
Why: the owner ruled that selling is not a mechanic, and raising it wastes his time.
History: docs/rules-history/engine-data-knowledge.md#nothing-is-sellable-except-gems. Bead inc-vpf9.

## shared-numbers-take-a-name-or-a-frozen-value
A number that two branches can each take (a save field tag, a stored `#define` or enum value, a script variable slot, a migration) MUST NOT be allocated as "the next free number". A new save field MUST take a name unique in its scope (`FIELD_U16("weight", Weight)`); a numeric tag fails to compile. A retired or renamed field goes in `tools/retired_field_names.txt` and `inc/SaveRetiredNames.h`. A new `#define` family or enum MUST carry `// family: <name> internal` or `// family: <name> stored <ordinal|bits|enum> <u8|i8|u16|i16|u32|i32>` (`tools/check_define_dups.py` refuses an unclassified one). A stored value on master MUST NOT change (`tools/check_stored_values.py`). Off master, clear a collision with `python3 tools/move_branch_values.py`; NEVER edit a stored number by hand. A new `INCURSION_*` probe name MUST get a row in `tools/probe_names.txt` naming its bead; a change to `SCHEMA_REV` MUST update its `/* rev owner: <bead> */` comment. A new shared space of any other kind MUST be added to the inventory (`docs/SHARED-SPACES.md`), to a check, and to a planted-duplicate row of `tools/check_space_mutations.sh` in the commit that creates it.
Why: two branches took the same save tags and git merged both with no conflict, which broke 17 of 88 fixtures.
History: new rule, no prior narrative to archive. Bead inc-cjos0.

## epic-saves-are-disposable
Only saves from master matter: the other players build from master. A save written by an epic build (such as `inc-pu6v`) is a playtest save and is disposable, Brian's own play saves in `~/Games/Incursion/save` included. A change MAY break an epic save. When a change breaks Brian's epic play saves, delete them from `~/Games/Incursion/save` at once, without asking; this overrides `brian-plays-from-his-own-folder` for that deletion only. MUST NOT add a converter, choose a tag or resource position, keep a fixture, or ask Brian anything to keep an epic save loading. When an epic and master collide on a save number or resource position, the epic moves (see `inc-cjos0`).
Why: the owner playtests the epic only, and protecting its saves costs work and his time for nothing.
History: docs/rules-history/engine-data-knowledge.md#epic-saves-are-disposable. Bead inc-1macr.

## map-scale-is-ten-feet-per-square
One map square is 10 FEET, not d20's 5 feet. Convert every feet figure at 10 feet per square: in a Desc, a design number, a bead, or a proposal to Brian. Evidence: `src/Social.cpp:900` ("10 feet (1 square)"); a torch is `Light Range: 4` (40 feet) and a brass lantern `Light Range: 6` (60 feet), `lib/mundane.irh:628-638`, the d20 full reach (bright plus shadowy) of each; the Sunblade's 60-foot light is `lval: 6`. When a Desc gives feet and the script gives a square radius (`lval`, `NewField` radius, `Light Range`, `vRange`), the script's squares times 10 is the true reach.
Why: the d20 default of 5 feet per square halves or doubles every converted range, and sessions keep falling back to it.
History: docs/rules-history/engine-data-knowledge.md#map-scale-is-ten-feet-per-square. Bead inc-t5ex2.
