# inc-wn6m: Dispel Evil check reproduction (diagnosis only)

No check or game fix is included. This is a record of the existing check's
controlled historical comparison, not a new seed-independent check.

## Result

Tip `7236a4354a53726ae55b5d0f1f3fad8bf1f701e4`, normal POSIX build,
`tools/check_dispel_evil.sh`, exit 1:

```text
building ./incursion-dispel-evil ... ok
Dispel Evil touch scene: 1 landed touch(es), first touch=1/1 defl=1, mid touch=0/0 defl=0 any=0
Dispel Evil deflection scene: 0 DispEv attack line(s) found
FAIL: no attack line named DispEv in the deflection scene's message log -- the caster was never attacked by the evil creature before any touch, or the bonus never applied. This check cannot see what it exists to check.
```

Failing assertion: `tools/check_dispel_evil.sh:271`.

| Source/module | Whole-check exit | DispEv lines |
|---|---:|---:|
| `47936e42^1` = `6643f217cfc0466570c22ad46f3e3cabfea19866` | 0 | 2 |
| `47936e42` | 1 | 0 |
| `47936e42`, only Dispel Evil's `EF_DROUND` removed | 0 | 2 |

All three touch scenes have one touch, before `1/1 defl=1`, mid
`0/0 defl=0 any=0`. All three use identical check, included keys, headless
launcher, options bytes and seed 1. No inherited INCURSION_* overrides were
present. SHA256s and the exact one-line intervention are in
`logs/inc-wn6m/input-comparison.txt`. Tip's options differ from the historical
options; the A/B/intervention comparisons use the historical options unchanged.

**Observed cause:** the new duration flag at `lib/pspells.irh:4716` invalidates
the check's assumption that a level-1 casting remains active until the goblin
attacks. The landing's flag is at the same line. Removing only that flag in
the archived landing restores the whole check, without changing its inputs or
the C++ executable. This is a diagnostic intervention, not a recommended fix.

**Traced mechanism:** `src/Magic.cpp:548` gives EF_DROUND at CL1 duration 1
status unit, versus the prior default 12 (`10 + 2*CL`, line 561).
`Game::Play` dispatches EV_TURN on multiples of 60 (`src/Main.cpp:819`);
`Creature::DoTurn` calls UpdateStati (`src/Creature.cpp:1829`), which
decrements/removes duration 1 (`src/Status.cpp:59`). The script starts casting
at tick 198000, a status-update boundary. By the post-cast screen at 198021,
the landing has returned to Melee mode while the parent and duration-only
intervention still show Brawl (the touch is active). It is already too late
before the script summons the goblin. The final wait is at 198069.

Parent/intervention combat text includes:

```text
Goblin's Attack: 1d20 (10) +1 = 11 vs. Def 14 -1 noDex -3 noDodge +4 DispEv = 14 [miss]
Goblin's Attack: 1d20 (4) +1 = 5 vs. Def 14 +2 parry +4 DispEv = 20 [miss]
```

Landing combat text includes:

```text
Goblin's Attack: 1d20 (6) +1 = 7 vs. Def 14 -1 noDex -3 noDodge = 10 [miss]
```

The landing's approved duration specification explicitly lists Dispel Evil
under EF_DROUND (`docs/specs/2026-10-22-spell-durations-spec.md`, the `EF_DROUND` row of its flag table). This
comparison establishes an obsolete scenario assumption, not grounds to undo
the duration rule. Whether global update-boundary timing warrants a separate
engine change is outside this reproduction.

The brief mentions a second-pass suspicion, previously unmeasured because of
a revert conflict. No second cause is needed for this measured seed-1 A/B:
one flag restores every assertion. This does not exclude other setup failures
on other seeds or revisions.

## Every fact the existing check reads

The existing check has no `# fact:` inventory. These are its direct inputs,
oracle inputs, and scenario prerequisites; controls refer to VERIFICATION.md.

- Character/fixture: no INCURSION_LOAD fixture. `chargen-priest.keys` generates
  male standard Orc/Priest/Aiswin/Lawful Good; attribute set c; positional
  feats, domains, skills, personality and first available starting spells.
  Stats, kit, feats, name and map are seed-dependent. Control for replacement:
  a saved character fixture, not another seed.
- Keys: `dispel-evil-touch.keys` includes `dispel-evil-touch-setup.keys`, which
  includes `chargen-priest.keys`; deflection includes `chargen-priest.keys`.
  The setup raises the touch caster to CL11 via ten G commands, Free
  Advancement, Infinite Mana, Freeze Monsters and Ignore Spell Failure.
  Deflection stays CL1 and toggles only Infinite Mana; monsters remain active.
  Wizard switch row positions are assumed. Use named choices where supported;
  a fixture fixes level-up choices, not random HP (HP is not an oracle).
- Menus/text consumed by key directives: Orc, Orc (Standard), Priest, Aiswin,
  Choose a skill, Lawful Good, Choose a Domain, `|  *`, Learn Spells: Level,
  Wizard Mode Switches, Bonus To Which Attribute, Choose a feat, Choose a
  bonus, Focus on which Weapon, You feel, `more --`, Learn Any Spell,
  Dispel Evil, Monster Summoning, Goblinkin, goblin, Confirm attack, Messages.
  The literal commands/positional answers are in the four unchanged key files.
- World: dungeon entry geometry and ambient creatures are generated. Neither
  scene genocides the map. Wizard summoning selects an evil, non-outsider
  goblin; touch places it two squares east, deflection one east. Terrain must
  permit these placements and movement. Catalog controls: Genocide Everything,
  named summoning, explicit terrain. Existing code does not fix all of these.
- Gear/rolls: goblin gear, caster equipment/deflection stacking, touch attack
  success within six attempts, survivability and spell-cast success are
  prerequisites. No forced attack/save/damage roll or SUMMON_NO_GEAR is set.
  Controls: fixture, INCURSION_SUMMON_NO_GEAR, INCURSION_LOF_FORCE_ROLL,
  INCURSION_FORCE_SAVE_ROLL where applicable. Damage control has documented
  limits. The check does not assert numeric HP or a particular rolled d20.
- Timing: one spell must still be active when an evil goblin attacks during
  three waits; no prior touch may consume it. CL1 duration and global update
  phase were not controlled. Monster AI choosing an attack has **no catalog
  control**. A replacement must close this hole before writing a new check.
- Seed: literal 1; headless also honors INCURSION_SEED_OVERRIDE and optional
  INCURSION_SEED_LOG. Both were unset. A pinned seed is not a fact control.
- Options: tools/gates/Options.Dat, copied into each isolated run. Among the
  dependencies are wizard/explore access, character creation/menu settings,
  no-death behavior, and OPT_STORE_ROLLS for the combat-message oracle.
- Build/env: BACKEND=posix normal developer binary/module; the check builds
  OUT=incursion-dispel-evil with EXTRA_CXXFLAGS=-DDISPEL_EVIL_PROBE each run.
  It sets INCURSION_BIN, INCURSION_OPTIONS and INCURSION_RUN_DIR. Headless sets
  INCURSIONPATH and INCURSION_SEED, defaults MAP_AUDIT and SAVE_PROBE to 1,
  and also accepts LOAD and LAUNCHER (unset here). No runtime environment
  switch arms DispelEvilProbeNote. TMPDIR only relocates temporary evidence.
- Harness output: absence of `NO GAMEPLAY` and exit status zero for each
  scene; these depend on session.log, key execution/watchdog and unknown
  asserts (tools/known_asserts.txt). Missing measurement is treated as failure.
- Probe file: nonempty `logs/dispel-evil-touch.log`; count of `^before ` is
  exactly 1; first before has touch=1/1 and defl=1; first `^mid ` exists and
  has touch=0/0, defl=0, any=0. The check does NOT assert `after`, effect name,
  evil, trapany, eval, xval or aval tokens, although the probe emits them.
- Screen oracle: first `*messages-top*.txt`, produced by v then PGUP*100;
  other captured pages are not inspected. The sed expression keeps text
  between the first and last pipe per row and joins rows. `%d` anywhere fails.
  Python requires `Attack: 1d20 (digits) ... = integer vs. Def integer`,
  signed named terms, total integer and bracketed word result. It counts
  lines with term name DispEv, requires label +4 or +6, and checks that label
  equals total minus base minus every other term. At least one line must
  match. UI wrapping, pipe borders and message pagination are therefore facts.

The landing changed the spell's duration fact; it did not change the checked
probe name, probe file, these keys, launcher or options. Its monster edits
concern Dominate Reptile and Cause Blindness; no goblin definition changed.

## Reproduction commands

Run from this worktree. All output paths below are under its logs/ directory.
Use fresh archive directories; do not create git worktrees or run bd.

```sh
ROOT="$PWD"
mkdir -p "$ROOT/logs/inc-wn6m" /tmp/inc-wn6m-a /tmp/inc-wn6m-b
git archive 47936e42^1 | tar -x -C /tmp/inc-wn6m-a
git archive 47936e42 | tar -x -C /tmp/inc-wn6m-b
ln -s "$ROOT/logs/inc-wn6m/a-build" /tmp/inc-wn6m-a/logs
ln -s "$ROOT/logs/inc-wn6m/b-build" /tmp/inc-wn6m-b/logs
mkdir -p "$ROOT/logs/inc-wn6m/a-build" "$ROOT/logs/inc-wn6m/b-build"
for side in a b; do
  (
    cd "/tmp/inc-wn6m-$side"
    BACKEND=posix ./build_macos.sh > "$ROOT/logs/inc-wn6m/$side-build.log" 2>&1
    TMPDIR="$ROOT/logs/inc-wn6m" bash -x tools/check_dispel_evil.sh \
      > "$ROOT/logs/inc-wn6m/$side-check.log" 2>&1
  )
done
```

For the isolated intervention, in **only** `/tmp/inc-wn6m-b/lib/pspells.irh`,
inside `Priest Spell "Dispel Evil"`, change this one line:

```diff
-    Purpose: EP_BUFF; Flags: EF_GOOD, EF_DROUND;
+    Purpose: EP_BUFF; Flags: EF_GOOD;
```

In that archive run `./incursion-headless -compile main.irc`, logging to
`$ROOT/logs/inc-wn6m/b-duration-only-compile.log`, then run the same check
with the same TMPDIR and bash -x, logging to `b-duration-only-check.log`.
Restore the archived source with
`git show 47936e42:lib/pspells.irh > /tmp/inc-wn6m-b/lib/pspells.irh`
from the real worktree and recompile the archive module. This restoration was
performed after the measurement; no diagnostic game change is retained.

To retain a scene's raw screens, from the corresponding tree run:

```sh
INCURSION_OPTIONS=tools/gates/Options.Dat \
INCURSION_RUN_DIR="$ROOT/logs/inc-wn6m/a-deflection" \
tools/headless.sh tools/keys/dispel-evil-deflection.keys 1 \
  > "$ROOT/logs/inc-wn6m/a-deflection.log" 2>&1
```

Choose a distinct label for each condition. The standalone scene uses the
normal headless binary; whole-check logs use the check's probe binary.

## Recommended check design (not implemented)

Change the scenario at `tools/keys/dispel-evil-deflection.keys:27` and `:41`,
not the duration rule. Load a verified priest fixture (candidate:
`tools/fixtures/chars/orc-priest-seed4-gate.sav`), explicitly raise caster level
as needed and establish a clear map, named target and gear. Use a deterministic
strike driver immediately after the cast, before a global status update, so
the oracle observes the deflection while it exists. Such an attack/timing
driver is a missing control and must be supplied before making a new check;
merely waiting longer, picking another seed or forcing d20 cannot control AI
or revive an expired effect. The touch scene should separately load a fixture
and force the attack roll. Preserve the current arithmetic and mid-handler
discharge oracles. Do not claim seed independence until the replacement
passes the required sweep and relevant mutation tests.

## Written paths

- Added this reproduction record only; no existing tracked file changed.
- Evidence: `logs/inc-wn6m/` (build/check logs, input comparison, retained
  scene directories with options/screens/session/audit logs, and write inventory).
- Generated build outputs in this worktree: `build/obj-incursion-headless/`,
  `build/obj-incursion-dispel-evil/`, `incursion-headless`,
  `incursion-dispel-evil`, `mod/Incursion.Mod`, plus compiler-generated files
  listed in `logs/inc-wn6m/written-paths.txt`.
- Scratch archives/builds: `/tmp/inc-wn6m-a/`, `/tmp/inc-wn6m-b/`; their logs/
  symlinks point into this worktree's logs/. B's sole source intervention was
  restored. No state-changing git command or bd was run.
- Deletions: no tracked-file deletions. The existing check's EXIT trap removed
  its temporary run directories under logs/inc-wn6m/; xtrace check logs retain
  its parsed probe fields and message text, and separate scene runs retain
  raw screens.
