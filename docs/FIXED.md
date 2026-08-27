# What has been fixed

This page is the engineering record. The [README](../README.md) is about playing
the game; this is about what was broken and what was done to it.

Every entry states how it was verified. Where a claim was wrong, the retraction
is here too — `docs/REPORTING-GATE.md` is the rule that requires it.

Every closed issue carries its evidence in Beads, including the controls that
were run and, where one exists, the check left behind.

## Index

| Section | What is in it |
|---|---|
| [The four defects that blocked a POSIX build](#the-four-defects-that-blocked-a-posix-build) | Why the port was stuck, and the one diagnosis that kept it stuck |
| [Found by the game playing itself](#found-by-the-game-playing-itself) | Defects the unattended harness reached that a player would not |
| [Crashes found by playing and by the harness](#crashes-found-by-playing-and-by-the-harness) | Three null dereferences and the level-builder defect behind one of them |
| [Robustness: a failure should not take the process with it](#robustness-a-failure-should-not-take-the-process-with-it) | Save and load failures that were survivable and were not |
| [Rules defects](#rules-defects) | Changes to how the game plays |
| [Magic-item descriptions made true](#magic-item-descriptions-made-true) | About thirty items corrected to behave as their own in-game text already promised |
| [Every Item member is initialised](#every-item-member-is-initialised) | A constructor that leaned on a `memset` the GCC `-O2` optimiser is free to drop |
| [Interface defects](#interface-defects) | Target cursor, shop list, overview map |
| [Two defects that shipped, and were found by a stranger](#two-defects-that-shipped-and-were-found-by-a-stranger) | The packaging failures, and why local checks could not see them |
| [Defects this port introduced, and then removed](#defects-this-port-introduced-and-then-removed) | Ours, not the base game's |
| [Claims that were withdrawn](#claims-that-were-withdrawn) | Two of them, with what replaced each |
| [Everything sent upstream](#everything-sent-upstream-and-what-became-of-it) | What went to the parent project, and where each submission stands |

---

## The four defects that blocked a POSIX build

The upstream README says a POSIX build *"just failed to find exported symbols it
should have been able to find"*. That diagnosis is wrong, and believing it is
what kept the port stuck for years.

**The real cause.** `src/RComp.cpp` is wrapped in `#ifdef DEBUG`, while the
generated `src/yygram.cpp` calls into it unconditionally. Build with `-DDEBUG`
and it links.

**`int32` was `typedef signed long`.** Windows is LLP64, so `long` is 4 bytes
there. macOS and Linux are LP64, where it is 8. Every "32-bit" type in the
codebase — `int32`, `uint32`, `rID`, `hObj`, `hText`, `hCode`, `hData` — was
silently 64-bit off Windows. Narrowing the typedefs dropped printf format
mismatches from 325 to 26.

**Narrowing the typedefs then destroyed every save.** `inc/Map.h` did
`*((long*)&hm)`, writing 8 bytes into what had become a 4-byte field. The
overrun covered the `int16 x,y` declared immediately after it, so every save
zeroed the player's position. Loading placed the character at (0,0) — the map's
solid outer corner — where the game crushed them to death on the first turn.
Now guarded at compile time by `src/AbiCheck.cpp`.

**`Map::At()` answered an out-of-bounds query by returning the square at (0,0)**
rather than failing, so wrong answers looked real. Guarded at `Map::GetAt`.

That last one is an upstream defect, not a port artefact, so it went to the
parent project as [rmtew#40](https://github.com/rmtew/incursion-roguelike/issues/40)
and [rmtew#41](https://github.com/rmtew/incursion-roguelike/pull/41).

**The size of that last claim is withdrawn, and the correction is public.** It
was first reported here as monster AI reading off the map 343 times in 13
seconds, and as an error log falling from 444 entries to zero across 877 turns.
Re-measured on 2026-08-18: the reads come from level generation, not from monster
AI, and the guard covers 8 of 47,962. There is no player-visible change and
screen dumps are byte-identical. The real cause was found and is in
[Crashes](#crashes-found-by-playing-and-by-the-harness) below. The correction was
posted to rmtew on 2026-08-19, and it offers to close the pull request unless he
prefers to keep the guard.

---

## Found by the game playing itself

About 1,100 unattended sessions had run by 2026-08-17, and the gate has added to
that on every change since. The harness drives the game from a key script with no
display and no keyboard, so a defect that needs ten thousand turns to show up can
be found overnight.

**Escorts followed the wrong creature.** `TargetSystem::giveOrder` built its
`Target` uninitialised, so an escort read stack garbage as the handle of the
creature to follow and walked toward an arbitrary object instead of its leader.
Two of the eight construction sites also left `damageDoneToMe` uninitialised,
which turned escorts hostile to their own leaders after a stray hit. Measured
over 250 seeds against a build differing in nothing else:

| | asserts at `Base.h:577` | total error lines |
|---|---|---|
| before | 89,545 | 139,948 |
| after | 0 | 48,245 |

That fix was sent upstream as
[rmtew#42](https://github.com/rmtew/incursion-roguelike/pull/42) and **merged on
2026-08-15** — the first change from this fork accepted into the parent project.
It is the only one of four submissions to have moved, and the only one whose
evidence was a number that changed on both sides of a controlled run.

**The game got slower the longer it ran.** Every VM event built a debug string,
and every macOS build is a DEBUG build. That single line was 89% of a
pathfinding burst.

**A string queue wrote past its own bound** before checking it, and the assert
that was supposed to stop it ran afterwards.

**A monster was charged for a fall a different creature took.**

**Targets were sorted by where they sat in memory**, so two runs of one seed
could play different games. Sent upstream as
[rmtew#44](https://github.com/rmtew/incursion-roguelike/pull/44). Found with
`-DDIVERGE_PROBE` and `-DINCURSION_LAYOUT`, which together make an
address-dependent decision split on demand instead of by luck.

---

## Crashes found by playing and by the harness

**The game died at the bottom of a dungeon.** `Player::MoveDepth` read the
dungeon below the current one without checking that there is one. `Game::Get`
returns NULL for a zero id and no dungeon in `lib/` defines `BELOW_DUNGEON`, so
every move down from the deepest level dereferenced NULL. The up path thirteen
lines above already guarded the identical case.

Four routes reach it and none needs a debugger: falling into a generated chasm on
the deepest level, the `>` climb-down, levitating down, and a scripted move. The
climb-down needs no wizard mode and no script.

Observed. One file between the two builds, seed 3362 under `dive.keys`: exit 139
before, exit 0 after, with `INCURSION_STACK_PROBE` showing the same nested
bottom-level entry on both runs, so the branch is entered and not avoided.

**A hiding monster deleted itself mid-spell.** `Creature::MakeNoise` checks that
the caster is still on the map, calls `Reveal(true)`, then dereferences its map
pointer. `Reveal` deletes the monster in between: removing the HIDING stati runs
`CalcValues`, which restores the size from LARGE to HUGE, and a HUGE creature
needs a 3×3 footprint that `PlaceNear` cannot find, so it deletes any non-player
thing it cannot seat. The guard was correct and simply ran before the call that
invalidates it. Three more callers of `Reveal` had the same shape, and
`MapIterate` guarded its map twice and then dereferenced it in its initialiser
anyway. All five now re-check.

Traced with a hardware watchpoint on the pointer as it went null; forensics in
`docs/evidence/inc-upw.37/`. `tools/check_reveal_delete.sh` is red on a tree
without the guards and green with them.

**A room-building rectangle inverted itself.** `Rect::PlaceWithin` insets by one
on each side when the wanted size does not fit, which inverts the rectangle in a
space two squares across or less. Its one caller uses that rectangle as the wall
ring of a room's inner chamber, so an inverted ring is walked backwards, and the
door loop then builds doors on squares the code never chose. Two of those landed
in solid rock. It now widens to the whole area instead of collapsing.

**This is the real cause behind the `Map::At()` report above**, and finding it is
what let the earlier monster-AI diagnosis be withdrawn. Measured on seed 3390
with pinned settings: exit 139 and 47,954 out-of-bounds reads before, exit 0 and
none after. The zero is measured on a different set of levels rather than the
same levels minus the defect, because changing the rectangle changes what the
random stream is spent on, and no way round that has been found.

The rectangle repair is also what exposed the self-deleting caster, by moving a
hiding HUGE monster into a square with no room for it. The crash was never the
repair's fault, which is why the two ship together.

---

## Robustness: a failure should not take the process with it

**A save that failed took the game with it.** `Registry::SaveGroup` turns every
object's data-block pointers into handles as it writes the object, and used to
swap them back by re-walking the whole object table after every write. Any throw
skipped that loop, so each object the writer had already reached kept a handle
where a pointer belongs, and `Game::Cleanup` dereferenced one.

It now records each object the instant it is converted and restores exactly that
record. It must be exactly that record: a throw part way through leaves the
objects not yet reached holding real pointers, and handing one of those to
`GetData()` would be a fresh corruption on top of the one being repaired. The
codebase argued against itself here, which is the provenance evidence —
`LoadGroup` already restored from a recorded list for this very reason.

Observed on both sides. A real full disk with 76 KB free: `EXC_BAD_ACCESS` in
`Game::Cleanup` and exit 139 before, the error reported and exit 0 after. A real
disk cannot reach the case the design turns on, because both write loops write
into memory and the disk is untouched until the commit, so `INCURSION_SAVE_FAIL_AT`
stages the failure instead and throws exactly what a short write throws. Eight
staged failure points: exit 139 at all eight before, exit 0 at all eight after.
Twenty-nine seed pairs saving three times per session and playing on, every screen
byte-identical to a control.

**A refused file could not be refused twice.** `Registry::LoadGroup` set
`loadMode` on entry and cleared it only where it succeeded, so every throw in
between — bad version, corrupt chunk, missing group, failed allocation — left the
registry claiming it was still loading, and leaked the memory file with it.
`Array<>` and `String` both return *without* initialising themselves while the
registry is loading, on purpose, so an object rebuilt from a file keeps what it
was saved with. The next `LoadGroup` therefore built its loaded-object list out of
stack garbage, and unwinding the next throw handed that garbage to `free()`.

Observed: a module with a patched version stamp and six load attempts gave exit
134 before and exit 0 after, with lldb reporting *"pointer being freed was not
allocated"* on the pristine build. Nine seeds A/B against the unchanged build gave
byte-identical screen dumps.

**Ported by hand from Eugene Archibald's fix** on his fork of this repository.
The fix, the root cause and the original evidence are his.

**A dead object handle no longer logs a defect.** A target keeps the handle of
whatever the monster was interested in, nothing clears it when that thing dies,
and the retarget pass simply rebuilds the list later — so a dead handle there is
the ordinary state of affairs. An earlier fix here had swapped a silent existence
test for a lookup that prints a message first, and the gate grew eight error
lines because of it. `Registry::Get` is now split: `GetQuiet` is the lookup, and
`Get` is `GetQuiet` plus the complaint, under exactly the condition the single
old function spoke under. Same single walk of the hash chain, which matters
because upstream's own profiling records `Registry::Get` as the second-hottest
function in the game.

The gate is back to 3 error lines against the baseline's 3, with all 40 seeds
reaching a map and every screen byte-identical to the pre-fix run.

---

## Rules defects

These change how the game plays, not whether it runs.

**Players never received their species' feats.** A `Race` has no feat field of
its own, so a racial feat can only live on the race's monster template — and
`Character::HasFeat` never read that template. Eight feats across six races were
silently lost: Dragonkin never got Mantis Leap, dwarves never got Loadbearer,
halflings and stouthearts never got Slipaway, female drow never got
Ambidexterity, grey dwarves lost three. Verified by running the game and reading
the character sheet before and after.

**Two bare fists were worse than two weapons.** `AttackMode()` returned
`S_BRAWL` the instant the weapon slot was empty, before the two-weapon test was
ever reached, so a bare-handed character got one strike per swing forever and no
feat could change it. The 3.5 SRD says an unarmed strike is always a light
weapon, which is precisely what qualifies two fists for two-weapon fighting. A
monk was strictly better off holding nunchaku than punching.

**A god's altar could not read the rows below `MA_ALL`.** The sacrifice check that
was supposed to catch this could not see it: both its runs used a god whose
sacrifice list ends in `MA_ALL` rows with nothing after them, so a loop stopping
one row early lost nothing. Aiswin exposes it — his handler sets a choice
parameter that switches off the type branch entirely, and the only row that can
match sits below both `MA_ALL` rows. Measured at seed 1 with one line of
`src/Prayer.cpp` different: *"Aiswin seems uninterested in your offering."*
before, *"A silky whisper mindspeaks: |Insufficient.|"* after. The first is what
Brian reported from play.

This proves correct **refusal** only. Correct acceptance needs a corpse that
wounded the player first, which a key script cannot reliably stage; Brian
confirmed that half in play on 2026-08-18.

**Natural weapons had no speed at all.** Every weapon in the data carries a speed
rating. Unarmed and natural attacks carry none and nothing ever supplied one, so
a monk punched at 100% while the nunchaku in his pack struck at 160%, and a
lizardfolk's claws were slower than the dagger the same hand could hold. Adding
the mass of a weapon to a limb cannot make that limb move faster, so the empty
limb is the upper bound and must never be the slower of the two.

This is a deliberate balance change and not a defect fix, so it is behind the
**Natural Weapon Speed** option and carries no `upstream:` mark. It floors a
weapon-capable creature's brawl speed at the fastest weapon in the data. The test
for "can hold a weapon" is the one the encounter builder already uses to decide
whether a monster gets equipment, so dragons and oozes are untouched and keep the
individual speeds their own entries specify.

Observed: the same level-1 lizardfolk monk from one seed, one byte of
`Options.Dat` different between the runs, reads 100% on the Brawl row with the
switch off and 175% with it on.

*A separate upstream defect is deliberately left alone here.* A missing `break`
lets brawl inherit the held weapon's speed. Fixing it would change what players
who leave this switch off already experience, so it is filed and not touched.

**Twenty prestige-class descriptions promised things their scripts did not do.**
These are findings PA-03-F1 through F20 of the prose-versus-script audit. Each is
a place where a class's own description tells the player one thing and the script
the engine runs does another. The rule used throughout: the prose wins unless the
script has two independent sources agreeing with it, and every ruling is recorded
with its evidence.

The mechanical failures. The Twilight Huntsman shipped sixty spells and a
"+1 caster level" column but no `SPELL_ACCESS` grant, so nothing ever read its
spell list; its Smite Law smote Good; and its Tracking advanced four times as
fast as the ranger's it claims to stack with. Sharp Senses gave its bonus to Spot
and Listen but not to Search, although the elf and the sentinel both name all
three — fixed in the engine rather than in `lib/`, because the bonus already
lived there for two of the three skills. The Master Archer's Ranged Sneak Attack
fired with anything, because `T_BOW` is not a discriminator: the sling and all
three crossbows are declared `T_BOW` too, so the three real bows are named
instead. The Blackguard could not use a shield and the Assassin could not use the
drow hand crossbow.

Five classes printed saves or a defence track their class does not grant. The
tables lose in each case, because the header line and the field the engine reads
agree against them.

Observed for five of the twenty, red-before and green-after on builds differing
in nothing else. `tools/check_sharp_senses.sh` reads an elf's Searching at +5
before and +7 after, with Spot and Listen unmoved as the control.
`tools/check_prestige_tables.sh` covers twenty table rows across five classes,
seventeen of which fail against a module built from the old prose.

The other fifteen are Traced, not Observed. Each needs a character who actually
holds the class, which needs the skill manager, which is not written yet. Where a
feature cannot be written now, the class description says so in its own text, and
the bead that eventually writes it must delete that line.

---

### Magic-item descriptions made true

About thirty magic items now behave as their own in-game description already
promised. Each fix closed a gap between what an item's description tells the
player and what the script the engine runs actually does. The rule throughout:
the prose wins unless the script has independent support, and where the two
genuinely conflicted the owner ruled which side is the truth, item by item.
Most corrections are to the shared item data in `lib/m_items.irh` and
`lib/main.irc`, or to a handler in `src/`. Where a fix touched `src/` and the
defect reads identically on Win32, it carries an `upstream:` comment at the fix
site and a row in the "Base-code bugs fixed locally" ledger of
[`REPORTING-GATE.md`](REPORTING-GATE.md). The holy-symbol autopickup exemption
is the fork's own code and carries no such mark.

The tier column follows the evidence, not how sure the fix is. A correction is
**Observed** only where a check ran the game and read a changed number or a
changed rendered screen — a character sheet, a hit-point trace, the item's own
description page, or the autopickup panel — with values on both sides. A
correction that a check guards only structurally — asserting a value in the
source or the compiled module, red before the fix and green after a rebuild — is
**Traced**, because that code has not been seen to run in play. This is stricter
than several of the commits' own self-labels, which is deliberate. One
correction has no check and is **Reasoned**.

| Item | Correction | Tier |
|---|---|---|
| Bloodspear | Its bane list gains the gnome its page promises: four races before, five now | Traced |
| Bloodspear | A lizardman wielder now reaches the +3 wounding tier the page grants; the branch tested only three creature types | Traced |
| Bloodspear | Regeneration now lasts 20 turns per hit point of the starting crit, and 5 per hit point for a hit landing at the maxed rate, as the page states | Traced |
| Bloodspear | The +4 saves versus spells now reach only an orc wielder, not everyone | Traced |
| Sunblade | Accuracy and crit now match the bastard sword the page names: +2 / ×2, not +3 / ×3 | Traced |
| Sunblade | The activated light burst now reaches 60 feet, radius six rather than five under the file's ten-feet-per-square convention | Traced |
| Sunblade | Double damage now strikes every creature tied to the Negative Material Plane, not wraiths alone; the multiplier had been commented out and replaced by a flat rider | Traced |
| Sunblade | It now grants the cold resistance its page always promised | Observed — a wielded +2 blade raised Cold resistance 0 → 2 on the sheet, Life Drain resistance unmoved at 4 as the control |
| Holy Avenger | Its on-hit dispel now fires at the wielder's paladin level, not a hardcoded caster level 12 | Traced |
| Dwarven Thrower | Its base item now carries the throwable flag, so the "throwing returning warhammer" can be thrown at all | Traced |
| Sword of Warning | Its description no longer prints a smiley in place of its percent sign; "50 percent" carries no `%` and so is correct on both render paths | Reasoned |
| Rod of Lordly Might | The long-sword form is now the +1 both its labels say, not +2 | Observed — the wielder's Hit / Dmg fell from 9 / 1d8+6 to 8 / 1d8+5 |
| Rod of Lordly Might | The paralysing touch grants the three touches its page states, not seven | Observed — a probe read the touch counter 3, 2, 1, then removal |
| Horns of Madness and Panic | Both can now be blown at all; neither carried an activation flag. Madness now spares its own blower and its page names Wisdom, the stat it drains | Observed — the target lost Wisdom and gained the stun/fear while the blower kept his and did not |
| Cloak of Shadow Shifting | Travel is now gated on darkness, as the page promised, and the page says seven uses a day rather than "at will" | Traced |
| Cloak of Resistance | It now grants a resistance bonus, as its name says, not a plain magic bonus. This moves live save numbers | Observed — with auspicious armour the saves changed type and the smaller bonus dropped, 8/6/8 to 6/4/6; the cloak alone was the control and did not move |
| Bracers of Defense | The page now states both of its unequal rates: defense class equal to the plus, coverage twice it | Traced |
| Bracers of Killing Hands | They now add the two points per plus their page promises to unarmed hit and damage, not one | Observed — the Brawl sheet block read +4 magic on both, not +2, at item plus +2 |
| Shadowstone | Its page now calls the item a stone, not a cloak, and states the twice-per-plus Hide bonus it grants | Traced |
| Staff of Wind and Water | Its page now names the circumstance bonus it grants, not an enhancement bonus; the two stack differently | Observed — the staff's own description page changed in game |
| Staff of Abjuration | Its page now offers the staff to a 3rd-level mage or priest, matching the gate that already accepted them | Observed — the staff's own description page changed in game |
| Staff of Exorcism | Its page now names the eighth spell it has always granted | Observed — all eight spell names read back off the page in game |
| Staff of the Goblin Queen | Its page now states the 3rd-level caster requirement its gate demands, not 1st | Observed — the staff's own description page changed in game |
| Wand of Acid | Its lingering burn is now dealt as acid, not fire, matching the wand and its own messages | Observed — a fire-immune target's hit points fell across the burn turns only after the type was corrected |
| Enchant Armour (graceful) scroll | Its page now names the graceful quality it bestows, not featherlight | Observed — the scroll's own description page changed in game against a featherlight control |
| Enchant Armour (life-keeping) scroll | Its page now names the life-keeping quality it bestows, not featherlight | Observed — the scroll's own description page changed in game against a featherlight control |
| Ring of Fire Resistance | Its wearer, and a mount, can now cross fiery terrain as the page promises; no ring's bonus had ever reached the threshold the terrain checked, and the terrain never named the ring | Observed — a wearer crossed magma the same character without the ring could not |
| Eyes of the Eagle | Its page now names the Acute Senses feat and its +50%, not a "Superior Senses" doubling it never grants | Traced |
| Springblade Bracers | The page no longer promises a fixed pair of +2 keen blades, since birth rolls one of six loadouts, and the type-3 label reads +2, not +3 | Label Observed (the activation menu name changed from +3 to +2); the two description edits Traced |
| Holy symbols | A god's holy symbol, a granting one included, is now exempt from unidentified-magic autopickup and is auto-identifiable, restoring the 0.6.4 changelog's own claim. This is the fork's own code, not upstream | Observed — a dropped symbol stays in view while other unidentified magic is stowed, red on the pre-fix binary |

---

### Every Item member is initialised

**The `Item` constructor read members, and left others, that only a `memset`
had zeroed.** `Item::Item(rID,int16)` read `eID` and `Plus` inside `MaxHP()`
before it assigned them, and never assigned `Parent`, `homeID`, `Flavor`,
`DmgType` or `swingCount` at all. It relied on the zero-fill that
`Object::operator new` performs with `memset` (`inc/Base.h`). Reading a
member the constructor leaves indeterminate is undefined, and an optimising
compiler need not preserve that fill. GCC `-O2` does not: a garbage `Plus` broke
`cHP` and tripped the `src/Item.cpp` ASSERT, and a wild `Parent` handle was
dereferenced during character creation and segfaulted before any map, reported
as `invalid object handle (1344285811)`. clang keeps the fill, so the macOS
build and the clang Linux build never saw it. The fix assigns each member before
use, which equals the zero clang already produced, so clang runs are
byte-unchanged.

Upstream, and marked as such. It is Richard Tew's code (commit 7b8504a, 2014)
and misbehaves the same way on the original Win32 compiler, so it carries an
`upstream:` comment at the fix site in `src/Item.cpp` with a row in the
[`REPORTING-GATE.md`](REPORTING-GATE.md) ledger. Not sent.

Observed. Debian 11 GCC `-O2`, seed 7: the unfixed constructor segfaulted at
character creation, exit 139 with no map reached, while clang and GCC `-O0` were
clean. Per-translation-unit then per-function bisection isolated it to this
constructor, and reverting the `Parent`-group line alone reproduces the exact
handle. The clang seed-7 run was unchanged, 362 turns with no errors, and a
release-1.3 save loaded clean. Guarded by `tools/check_gcc_o2_char_create.sh`,
the only check that builds at `-O2` with GCC; it fails on the handle signature
or on a run that never reaches a map. A follow-up (inc-uusj) audits the rest of
the object hierarchy for the same pattern.

---

## Interface defects

**The target cursor scored one axis and ignored the other.** A sideways arrow
summed the column gap and never looked at the row; an up or down arrow summed the
row gap and never looked at the column. So RIGHT meant "the nearest column to my
right", every row in that column tied at the same score, and the winner was
whichever thing happened to sit first in the map's list. The cursor moved
sideways while going up, skipped the nearest creature for a further one, and
reached places from which most presses did nothing.

Candidates now form a ring around the player ordered by bearing, and an arrow
steps one place round it. Which things are candidates is unchanged, and the
location cursor is untouched.

Observed on seed 1 with one file between the two builds, player at (111,110) and
nine corpses in view:

| Press | Before | After |
|---|---|---|
| RIGHT from the player | (112,107), the furthest of three the old sum scored identically | (112,108), the nearest thing to the right |
| UP from (116,107) | up one row and sideways five columns | the next place round the ring |
| twelve UP presses | two moves, then ten presses that moved nothing | nine distinct places, then the lap again |

The ring is this fork's own design rather than a minimal repair, so it must not be
offered upstream as one. The defect underneath it *is* upstream's: the arithmetic
is byte-identical before rmtew reformatted the file, and behaves the same on Win32
with the original typedefs.

**The shop list never scrolled.** The store menu's redraw label opens by zeroing
the scroll offset, and every arrow key jumps back to that label before the one
draw call, so whatever offset the up and down cases had just worked out was thrown
away. Row 0 was redrawn at the top of the page every time and the selection walked
off the page and stayed there.

The recorded diagnosis blamed a hardcoded 32 visible rows and predicted that
scrolling up still worked. Brian falsified that from play. The issue had named
that prediction as its own falsifier, which is the only reason the wrong cause did
not survive.

Two smaller defects in the same function went with it: the page height is now read
from the window instead of the constant 32, and the two manual-scroll keys were
gated on a flag the barter screen never assigns, so they worked or not according
to whether the inventory screen had been opened earlier in the same session.

`tools/check_store_scroll.sh` reaches the store without wizard mode, presses DOWN
forty times, and presses `[x]` at both ends so a session whose keys never reached
the menu cannot pass by accident.

**`<` and `>` did nothing on the overview map, and the search picked the wrong
staircase.** The overview loop reads keys in arrow mode, and arrow mode returns no
command outside the eight compass directions, so the keyset hit was dropped and
the raw character came back instead. No case matched it, so both keys fell through
to the branch that leaves the map. `,` and `.` worked the whole time, because
those *are* the raw characters. That defect is upstream's and is marked.

The search behind them scanned the map row by row from the cursor and took the
next match in reading order, so distance never entered it. Each remembered
staircase is now ranked by what the pathfinder says it costs to walk there, at the
same three danger settings the run-to command tries and in the same order — so one
reachable safely always sorts ahead of one needing the trap-ignoring search, and
the square the cursor lands on is the square `R` will really reach. Repeated
presses step down the ranked list and wrap; ties break on map index so none is
skipped.

`tools/check_stair_cycle.sh` re-derives every choice from the candidate list the
game logs, and is red on a build differing only in those two case labels. Its
ceiling is in its header: seed 1 knows one staircase of each kind, so it proves
the search runs, the choice is the cheapest and the cursor wraps, but not the
order of two candidates.

**The menu threw away the top half of every handle a script gave it.** AutoLoot
took nothing from a chest, said "finished looting", and named nothing it had
skipped. The first diagnosis was wrong: it blamed `Item::Owner()` walking up
through a chest that had kept the player as its parent, and a Parent/Owner probe
refuted that — the oak chest is `Parent=0` and every item in it is `Owner=0`,
exactly like the ground items that worked.

The handle was destroyed going *into* the menu, not read wrongly coming out.
`inc/Api.h` declares the script side of every engine call, and the resource
compiler turns those declarations into the virtual machine's dispatcher. The
declaration for `LOption` — the call every script uses to add one line to a menu
— said its value parameter was an `int16`. That value is the caller's own cookie
and AutoLoot puts the item's handle in it, but an `hObj` is a signed 32-bit
handle. `TextTerm::LOption` itself takes an `int32` and `Option::Val` is an
`int32`, so only the declaration was ever narrow.

Handles are handed out in order from 128, so the first 32,639 objects of a game
are untouched and the defect switches on partway through a character's life.
That is why the first chest looted and the second did not, and why the earlier
experiment pointed at "in a chest": the ground items it compared against were old
inventory objects carrying low handles. The same declaration also narrowed
AutoDrop and every resource id a script puts in a menu — the undead-form menus
put ids past sixteen million through it.

Observed twice. A probe on `TextTerm::FirstSelected` read the loss directly:
handle 44177 came back out of the menu as −21359, which is 44177 as a signed
16-bit number. No object answers to that, AutoLoot's own first guard is
`!isValidHandle`, and the macro walked past every marked item without a word.
Then on a sandboxed copy of a real save — never on `save/` itself — the keys that
printed "You stop AutoLoot (finished looting)" and took nothing now print
"? spellbook [Conjurations and Summonings] taken.", and four marked items come
across in four ticks.

`tools/check_menu_value.sh` is the check. No scripted run is long enough to reach
a wide handle, so `INCURSION_HANDLE_BASE` starts the counter wherever the caller
asks; the check sets it to 40,000 and drives AutoDrop through the same menu round
trip. Red on a build differing in nothing but that cast, green with it. The same
script at the ordinary base of 128 passes on both builds, which is the control —
without it, an AutoDrop broken for some other reason would fail this check and be
read as the truncation returning.

Upstream, and marked as such: `hObj` is 32 bits on Win32 too, the cast truncates
identically on the upstream compiler, and `inc/Api.h` has not been touched since
2014-2015. Not sent.

---

## Two defects that shipped, and were found by a stranger

Both of these were in the released download, both were invisible on the machine
that built it, and both were reported from outside
([networkingguru#6](https://github.com/networkingguru/incursion-roguelike/issues/6)).
They are recorded together because they share one cause: every check ran against
local files, and a file you build yourself is not the file a user gets.

**The release could not load its own module.** The game reported *"Error loading
module 'Incursion.Mod' (File Version Mismatch)"* on the first action. Module files
carry a digest of the memory layout that wrote them, and the release is built
twice — a developer binary to compile the module, a shipping binary without the
GPLv2 resource compiler. Those two disagreed, because `class Registry` had a data
member declared only in debug builds and `sizeof(Registry)` is one of the digest's
inputs. The developer binary stamped `SF0F7B6EDC`; the shipping binary demanded
`SFD3A51B74`.

Measured with one probe compiled against the headers twice, changing only
`-DDEBUG`:

| | `sizeof(Registry)` | stamp |
|---|---|---|
| developer build | 1,065,016 | `SF0F7B6EDC` |
| shipping build | 1,065,008 | `SFD3A51B74` |
| after the fix, both | 1,065,016 | `SF0F7B6EDC` |

The developer stamp did not move, so no existing save was invalidated. The guards
never even agreed: every *use* of that member is under `DEBUG_OBJECTS`, not
`DEBUG`, so a plain developer build carried the field and never touched it.

**The replacement release would not launch at all.** It was correctly signed and
correctly notarised, and macOS still refused it with *"the app has been modified
or damaged"*. Nothing was wrong with the signature — `codesign --verify --strict`
passed. The problem was the shape: a bare executable in a plain folder. Gatekeeper
cannot approve a bare executable, answering *"the code is valid but does not seem
to be an app"*, and a notarisation ticket can only be stapled to a disk image, an
installer or an app bundle — never to a loose binary. So the ticket covered the
image and nothing covered the game.

It now ships as `Incursion.app` with its own stapled ticket, which is what makes
it survive being dragged out of the image. Writable state moved to
`~/Library/Application Support/Incursion/`, because a bundle that writes inside
itself breaks its own signature and produces the same refusal by another route.

**What actually let both of these out.** The packaging gate inspected the
artifact's contents and never ran it, and it assessed unquarantined local files.
A downloaded file carries `com.apple.quarantine` and is judged differently, so the
failure was structurally invisible where it was built. `tools/check_app.sh` now
asks the binary for its own save-layout stamp and compares it to the module's,
assesses a **quarantined** copy, and asserts the signature survives a run. All
three would have failed on what shipped.

---

## Defects this port introduced, and then removed

These are ours, not the base game's. They carry no `upstream:` mark, because
claiming ours is theirs costs credibility.

**The path sweep ate six C escapes.** The port converted Windows path separators
by replacing backslashes with forward slashes, and the replacement could not tell
a path from an escape. Where the source said `\n` the sweep wrote `/n`, which is
no escape at all and reaches the reader as two visible characters. Three sites
were known; there are six, and three separate readings of the port diff by eye had
missed the other three.

The whole sweep is audited rather than only the listed sites: of the 123 removed
lines carrying a backslash, all but 20 are generated line markers, and of those 20
these six were the only damage still in the tree. `tools/check_escape_sweep.sh` is
the guard, and it was proved red against the pre-fix tree — printing all six sites
— before it was trusted.

**Two scripted runs could share one directory.** The default run-directory name
came from a clock that resolves to the second, so two sessions started inside one
second shared one `save/`, one `logs/` and one append-mode probe log holding both
sessions' lines. The merged log then reads as a single long session, which is how
a follower count came out wrong and had to be withdrawn. The process id is now in
the name.

`tools/check_headless.sh` gained the one assertion there that must *not* be handed
a directory, since the defect was in the default name: it starts two sessions at
once and fails if they report one path. Proved red against the old naming, where
both runs reported the same directory.

---

## Claims that were withdrawn

**The `MoveDepth` crash fix was not one.** Making the follower array re-entrant
was committed as a segfault fix. A controlled A/B showed the same seed segfaulting
identically with and without it, on the same stack. The re-entrancy it describes
is real and the stack proves it, so the change is kept as hardening — but the
crash claim was wrong and is retracted in the history.

The original measurement passed because the scratch worktree it ran in lacked the
modified `Options.Dat` this tree uses, so no session in either arm ever entered a
map. Two runs that both did nothing agreed perfectly. That is the whole reason the
harness now has a `NO GAMEPLAY` exit code: a session that measured nothing must
never be read as a pass.

**The `Map::At()` figures were far too large.** See
[the POSIX build section](#the-four-defects-that-blocked-a-posix-build) above. The
monster-AI cause was inferred from a single call stack, the guard is in a function
those reads do not arrive through, and the real cause was the level builder. Eight
reads of 47,962 are stopped, with no player-visible change. The correction was
posted to the maintainer rather than quietly dropped.

Three smaller claims from the level-builder investigation were retracted in the
evidence rather than dropped: a trim asymmetry that is not asymmetric, the loss of
a double room's inner chamber that is never built in any case, and "nothing is
logged" when the out-of-bounds read trips an assertion one line above the line
that sentence cited.

---

## Everything sent upstream, and what became of it

| PR | What it is | Status as of 2026-08-19 |
|---|---|---|
| [#41](https://github.com/rmtew/incursion-roguelike/pull/41) | bounds-check `Map::GetAt()` | open. The tier as sent is **withdrawn**; the correction was posted to issue #40 on 2026-08-19 and offers to close this unless he prefers to keep the guard |
| [#42](https://github.com/rmtew/incursion-roguelike/pull/42) | zero-initialise `Target` at its eight construction sites | **merged** 2026-08-15 |
| [#43](https://github.com/rmtew/incursion-roguelike/pull/43) | `MoveDepth` re-entrancy, sent as hardening | open. His three technical questions were answered 2026-08-18 |
| [#44](https://github.com/rmtew/incursion-roguelike/pull/44) | compare handles, not addresses, in `TargetSort` | open, sent 2026-08-16 |

The one that merged is the one whose evidence was a number that moved on both
sides of a controlled run, which is what
[`REPORTING-GATE.md`](REPORTING-GATE.md) predicted before there was any evidence
for it.

His issue #8, *"Simplest path to automated testing"*, open since 2024 and never
answered, was answered on 2026-08-19. It describes the headless backend, the key
scripts and the seeded runs, and says why the morgue-and-replay diff both
maintainers proposed was tried and abandoned: screens diverge from the first
changed decision onward, so a gate built on them goes red on every correct fix.

---

## The full list

Work is tracked in [Beads](https://github.com/gastownhall/beads), in the
repository itself rather than in this file. To read it:

```
bd list --status closed     # everything fixed
bd ready                    # what is available to work on now
bd show <id>                # one issue, with its evidence
```

Twenty-three of the closed issues were closed by iNCURSION release 1; the rest
came after it.

## Fixes that belong to upstream

Defects that are the base game's rather than this port's are marked in the
source with an `upstream:` comment, and listed in
[`REPORTING-GATE.md`](REPORTING-GATE.md), so they can be found and sent on if
the original maintainer ever wants them:

```
grep -rn "upstream:" src/ inc/
tools/check_upstream_marks.sh
```
