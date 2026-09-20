# Class abilities on the My Character page

Bead: inc-nbjf. Branch: `inc-nbjf`. Lane: `fix:`.

## The defect

A character who holds a class ability is told its name and nothing else.

The character sheet prints the name. `Creature::DisplaySheet` walks every `CA_`
id and asks `AbilityLevel(i)`; for each non-zero it looks the name up in the
`ClassAbilities` table (`src/Sheet.cpp:392-395`, `src/Tables.cpp:3543`). So the
sheet shows "Devouring" and stops.

The My Character help page does not mention class abilities at all.
`HelpCustom` (`src/Help.cpp:1264`) builds eight sections: My Race, My Class, My
Alignment, My God, My Domains, My Feats, My Skills, My Spell Access, My Spells.
The feat section loops `FT_FIRST..FT_LAST` and asks `HasFeat`. A class ability
is not a feat, so no loop on that page reaches one.

No description exists anywhere. The engine has `DescribeFeat`
(`src/Help.cpp:4547`) and `DescribeSkill` (`src/Help.cpp:993`). It has no
equivalent for abilities, and no `CA_` carries prose.

## What upstream left behind

Upstream declared the structure this needs and never wrote the table.

    inc/Creature.h:56   struct AbilityInfoStruct { uint8 ab; const char *name;
                                                   const char *desc; };
    inc/Globals.h:242   extern struct AbilityInfoStruct AbilInfo[];

`AbilInfo` is declared once and never defined. `grep -rn AbilInfo src/ inc/
lib/ tools/` returns that one line. Nothing reads it. The comment inside the
struct -- "ww: we might put a 'cost' or 'balance factor' here at some point" --
shows the authors were designing the ability table and stopped.

This is upstream's defect, not the port's. The declaration and the missing
definition contain no platform typedef, no width assumption and no
compiler-dependent construct; a Win32 build of 0.6.9 omits the table in exactly
the same way. Evidence tier: Traced.

## Scope: which abilities get a description

`ClassAbilities` carries 135 live name rows. `CA_LAST` is 143. Brian's ruling on
2026-09-20 was to describe only the abilities that work now, not all 135.

**The live list is 96 abilities.**

An ability is live when both of these hold, counting only uncommented lines:

1. Something in `lib/` grants it to a player, through `Ability[CA_X]` in a class,
   prestige class, race, subrace, domain or religion gain table, or through
   `ABILITY(CA_X, level)`, the macro for `Stati[EXTRA_ABILITY,CA_X,level]`
   (`lib/defines.irh:25`), or through a spell in `lib/pspells.irh`,
   `lib/wspells.irh` or `lib/abilities.irh`.
2. The engine names it in live code in `src/*.cpp`, outside the name tables.

The derivation, run in the worktree, which the check regenerates rather than
trusting a pasted list:

    # granted to a player
    grep -hE "Ability\[CA_[A-Z_]+|ABILITY\(CA_[A-Z_]+" \
        lib/classes.irh lib/prestige.irh lib/races.irh lib/subraces.irh \
        lib/domains.irh lib/religion.irh lib/pspells.irh lib/wspells.irh \
        lib/abilities.irh \
      | grep -vE "^[[:space:]]*(//|/\*|\*)" \
      | grep -ohE "CA_[A-Z_]+" | sort -u

    # named in live engine code
    grep -rhE "CA_[A-Z_]+" src/*.cpp --exclude=Tables.cpp \
      | grep -vE "^[[:space:]]*(//|/\*|\*)" \
      | grep -ohE "CA_[A-Z_]+" | sort -u

The intersection is 97. `CA_GRANT_ITEM` comes out of it, leaving 96: it is not
an ability a character holds but a delivery mechanism, and
`Player::GainAbility` zeroes it the moment it fires (`src/Create.cpp:3584-3589`,
`Abilities[ab] = 0;`). It has no `ClassAbilities` name row, so it never reaches
the sheet or the page. Every other one of the 97 has a name row.

**Why the first measurement was wrong, and it matters for the check.** Testing
for `HasAbility()` or `AbilityLevel()` gave 85. That test misses the largest
read path in the engine: `Player::GainAbility` (`src/Create.cpp:3379-3592`) is a
switch that converts a granted ability into a stati at grant time, and the rest
of the engine then reads the stati and never the ability. `CA_SMITE` becomes
`SMITE_ABILITY`, `CA_FAV_ENEMY` becomes `FAV_ENEMY`, `CA_SPECIALIST` becomes
`SPECIALTY_SCHOOL`. A second path, the invoke-ability switch in
`src/Skills.cpp`, acts on the ability directly when the player uses it. So the
check MUST NOT test for `HasAbility`/`AbilityLevel` call sites. It tests for the
constant's presence in live engine code, which catches all three paths.

**The three dead abilities.** `CA_BANKED_SHOT`, `CA_DISARM_MAGIC_TRAP` and
`CA_WEATHER_SENSE` are granted nowhere and read nowhere: each one's only grant
line is commented out (`lib/prestige.irh:2408`, `lib/classes.irh:2580`,
`lib/domains.irh:947`), and `CA_DISARM_MAGIC_TRAP`'s name row and its
`src/Sheet.cpp:601` case are commented out as well. Two independent methods
agreed on all three -- a per-ability audit of the code, and the set subtraction
above. They go in the exempt file.

**The 39 that stay bare.** 135 named minus 96 live leaves 39 abilities with a
name row and no description. They are almost all monster-only, granted by
`ABILITY()` in `lib/mon*.irh`. A polymorphed player can hold one and will see a
bare name, exactly as today. That is what Brian's ruling accepts, and the exempt
file records each one so the decision is visible rather than implied.

## The design

### 1. Define the table upstream declared

Define `AbilInfo[]` in `src/Tables.cpp`, beside `ClassAbilities`, in the shape
`inc/Creature.h:56` already gives it: `{ CA_X, "Name", "description" }`.

`ClassAbilities` stays. `Lookup(ClassAbilities, i)` is called from
`src/Sheet.cpp` and from `DescribeFeat`'s `FP_ABILITY` prerequisite printer
(`src/Help.cpp:4610`), and a `TextVal` table is read by the generic `Lookup`
helper. Replacing it is a wider change than this bead needs.

Two name tables can drift, so the check in section 4 asserts they agree.

### 2. Add `DescribeAbility`

Add `String & DescribeAbility(int16 ca)` to `src/Help.cpp`, shaped like
`DescribeFeat` at `src/Help.cpp:4547`: the name as a coloured heading, then the description
under a `Benefit:` label. Declare it in `inc/Globals.h` beside `DescribeFeat`
at `:244`.

An ability with no `AbilInfo` row returns its `ClassAbilities` name and no
benefit line, so an undescribed ability degrades to today's behaviour rather
than printing nothing.

### 3. Add the My Abilities section

Add a section to `HelpCustom` (`src/Help.cpp:1264`), placed after My Domains
and before My Feats, which is where it belongs in the character's own order:
race, class, alignment, god, domains, abilities, feats, skills, spells.

    helpText += BoxIt("My Abilities {B}",YELLOW,GREY);
    for (i=0;i!=CA_LAST;i++)
      {
        if (!p->AbilityLevel(i))
          continue;
        helpText += XPrint(DescribeAbility(i));
        helpText += "\n";
      }

`AbilityLevel` is the test the character sheet already uses, so the page and the
sheet list the same abilities. The letter `B` is free: the page uses R, C, A, G,
D, F, K, S and P.

### 4. Add the check

Add `tools/check_ability_descs.sh`, marked `# gate: cheap` in its first 40
lines so `tools/check_gate_membership.sh` admits it, and give it a row in the
checks table of `tools/README.md` so `tools/check_readme_checks.sh` passes. It
reads the source tables and needs no build and no game.

It asserts four things:

1. Every ability named in `tools/ability_descs.live` has an `AbilInfo` row with
   a non-empty description.
2. Every `AbilInfo` row's name string is identical to that ability's
   `ClassAbilities` name. This is the anti-drift assertion.
3. Every `AbilInfo` row names an ability that exists in `ClassAbilities`.
4. Every ability granted in `lib/*.irh` appears either in
   `tools/ability_descs.live` or in `tools/ability_descs.exempt`. A newly added
   ability therefore fails the check until somebody decides which file it goes
   in. This is the ratchet: the exempt file holds the abilities that do not work
   yet, and it only shrinks.

`--selftest` proves each of the four assertions red against a mutated copy of
the tables, then restores. A check that cannot be shown to fail is not evidence
(`docs/VERIFICATION.md`).

### 5. Devouring's own text

Read from `Creature::DevourMonster` (`src/Skills.cpp:2963-3116`) and
`Creature::Devour` (`src/Skills.cpp:3119`), and from the call site at `src/Item.cpp:1963`.
The description must state:

- It triggers when you finish eating a corpse, not when you start one
  (`src/Item.cpp:1955`, `Eaten >= 100`).
- Undead flesh gives nothing (`src/Skills.cpp:3021`).
- You gain a permanent point of resistance for each damage type the victim
  resisted more strongly than you do (`src/Skills.cpp:3026-3060`).
- You gain a permanent inherent attribute point when the victim's own matching
  attribute beats yours, capped at five plus your Inherent Potential level
  (`src/Skills.cpp:3065-3075`). The mapping is giants to Strength, cats to Dexterity, trolls
  to Constitution, illithids to Intelligence, nagas to Wisdom, faeries to
  Charisma and mythic beasts to Luck (`AttrMTypes`, `src/Skills.cpp:2971-2999`, against
  `A_STR..A_LUC`, `inc/Defines.h:1766-1772`).
- Dragon flesh raises inherent Mana instead (`src/Skills.cpp:3077-3103`).
- You gain experience scaled by the corpse's challenge rating against your own
  (`src/Skills.cpp:3106-3110`).
**It does NOT cost divine standing, and an earlier draft of this spec was wrong
to say it did.** The transgressions against Mara, Erich, Immotian, Xavias and
Hesani, the favour with Khasrach and Zurvash, and the non-lawful act all fire at
`src/Skills.cpp:3001-3014`, ABOVE the `if (!HasAbility(CA_DEVOURING)) return;` gate at
`src/Skills.cpp:3018`. They are the price of eating a corpse at all, which any character can
do. Attributing them to the ability would tell a player that giving up
Devouring would spare him them, and it would not. Keep them out of this
description.

## Verification

This is a `fix:` a player feels, so it needs a before/after observation of the
thing that changed, which is the rendered page (`AGENTS.md`, "Classifying a
change").

- **Oracle.** The My Character page, reached from the help menu, for a character
  who holds at least one class ability. Captured with `tools/headless.sh` from a
  frozen character under `tools/fixtures/chars/`, so no module change can
  rewrite the character out from under the check.
- **Before.** The page shows the eight existing sections and no abilities.
- **After.** The page shows My Abilities, listing every ability the character
  holds, each with its benefit text.
- **Mutation.** `tools/check_ability_descs.sh --selftest` proves the four
  assertions red.
- **Regression.** `tools/nightly_verify.sh --compare` against a `--record`
  snapshot taken before the change.

## Marking

Three obligations, because the defect is upstream's:

1. An `upstream:` comment at the fix site in `src/Tables.cpp`, stating that the
   defect is upstream's and why, the evidence tier (Traced), the tracking id
   (inc-nbjf), and that it has not been sent.
2. A row in the "Base-code bugs fixed locally" table of
   `docs/REPORTING-GATE.md`.
3. `bd label add inc-nbjf upstream`, without which `tools/sync_issues.sh`
   refuses to run and the gate reports UNMEASURED.
