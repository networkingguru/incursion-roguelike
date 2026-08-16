# Reporting gate

Rules for claiming a bug is real and that a fix is the real fix. They apply to
anything public: an issue on `networkingguru/incursion-roguelike`, a comment on
one, and above all anything sent to `rmtew` or `HexDecimal`.

The point is narrow. Upstream has no reason to trust us. A single confident
report that turns out to be wrong, or a patch that moves a bug instead of
removing it, costs more credibility than five good reports earn.

## The four questions

Answer all four in writing before the claim goes public. A missing answer is a
blocking result, not a caveat to add later.

### 1. Reachability chain

State the call path from a user action to the defect, with file and line at
every hop. "This cast is wrong" is not a chain. This is:

```
MakeLev.cpp:1108   builds a Door
  -> ft->PlaceAt(...)
  -> Display.cpp:56   Thing::PlaceAt
  -> Display.cpp:162  m->Things.Add(myHandle)   (only T_MAP is excluded)
  => every dungeon with a door puts a Door* in the list Augury walks
```

You MUST build the chain before filing, not after somebody asks for it.

### 2. Provenance

Ask: would this misbehave on Win32, with the original typedefs, on the upstream
compiler?

- **No** -> the defect is ours. It MUST NOT go upstream. The save-corruption
  bug fails here: `*((long*)&hm)` was harmless on Windows, because `long` is 4
  bytes there. Our typedef narrowing created the overrun.
- **Yes** -> it is upstream's. Say what makes you certain. Best evidence is the
  codebase arguing against itself: `Map::besideWall()` carries a comment about
  the same out-of-bounds trap that `Monster::ChooseAction()` walks into.

### 3. Blast radius

Two checks, both after the fix compiles:

- **Siblings.** Grep every caller of the function you touched. Fixing the one
  call site named in the report, while a sibling has the same defect, is a
  band-aid. Prefer the funnel: guarding `Map::GetAt()` fixed every unguarded
  neighbour scan at once, not only `Monster::ChooseAction()`.
- **What is newly reachable.** A fix changes which branches run. Re-read the
  surrounding code and ask what now executes that did not before.

  This is not hypothetical. Adding the missing `isItem()` guard to `Magic::Augury`
  made a *second* defect more reachable: before the guard, any door set `o` to
  non-NULL, so the `o == NULL` branch rarely ran; after it, an item-free map
  reaches a backwards `goto` and hangs. Shipping only the cast fix -- the one the
  compiler found -- would have converted upstream's crash into a hang.

### 4. Confidence tier

Every report MUST carry one of these, stated in the report, in these words:

| Tier | Meaning |
|---|---|
| **Observed** | An oracle changed state. A log went quiet, a counter dropped, a crash stopped. Numbers before and after. |
| **Traced** | Reachability proved by reading code. Never executed. |
| **Reasoned** | Neither. A hypothesis, however well argued. |

**Only Observed goes to `rmtew` or `HexDecimal`.** Traced and Reasoned stay on
our fork, where being wrong costs nothing.

The tier is about evidence, not about how sure you feel. `Magic::Augury` holds
three defects that are certainly real, and it is still Traced, because that code
has never been seen to run.

## Titles

The title MUST NOT assert more than the body proves. This is the easiest rule
to break, because a title is written first and never revisited. A body that
carefully says "consistent with a present-timing artefact, though a single run
is weak evidence" under a title that says "(present-timing, not drawing)" is a
false claim, whatever the body says. A maintainer reads the title first.

## Separate the three things

Keep them apart, in the report and in your head:

- **An observation** -- something happened, here is the log. Always fileable.
- **A diagnosis** -- this is why. Needs the chain.
- **A patch** -- this fixes it. Needs the blast radius check.

Filing an observation as an observation is honest and useful. Filing an
observation dressed as a diagnosis is how you lose a maintainer's attention.

## Marking a base-code bug that we have fixed

The rules above govern what we SEND. This section governs what we KEEP. They are
different problems: a fix can sit in our tree for years without ever being
reported, and if nothing marks it, the knowledge that it was upstream's bug and
not our port's dies with the session that found it.

**Every fix to a base-code defect MUST carry an `upstream:` comment at the fix
site.** Lowercase tag, same shape as `ponytail:`. Greppable:

```
grep -rn "upstream:" src/ inc/
```

The comment MUST state four things, because a maintainer who wakes up years from
now has none of our context:

1. **That the defect is upstream's, and why.** Answer question 2 of the gate:
   would this misbehave on Win32, with the original typedefs, on the upstream
   compiler? If the answer is no, it is a port artefact and MUST NOT carry this
   marker -- mislabelling ours as theirs is exactly the credibility cost the top
   of this document is about.
2. **The evidence tier**, in the words of the table above: Observed, Traced or
   Reasoned.
3. **The tracking id**, so the full reasoning is recoverable.
4. **Whether it has been sent**, so nobody re-sends it and nobody assumes it
   went out when it did not.

Marking is NOT reporting, and marking creates no obligation to report. A marked
fix goes out only through the gate above, and only when Brian has read the
literal text that will be published.

### Base-code bugs fixed locally

| Fix | Tier | Sent? | Tracked |
|---|---|---|---|
| `Character::HasFeat` never read a race's Monster template, so players silently lost every racial feat that was not also an explicit `Grants:` entry -- 8 feats across 6 races (`src/Create.cpp`) | **Observed** -- same seed and key script; Dragonkin sheet had no Mantis Leap before, has it after | no | inc-2a0 |
| Two empty hands produced one strike per swing forever, while two weapons produced two. `AttackMode()` returns `S_BRAWL` before the `S_DUAL` test is reached, so no feat could ever apply to fists (`src/Creature.cpp`, `src/Fight.cpp`) | **Observed** -- same seed; `Hit:2 / -3` and one Punch before, `Hit:2 / 2` and two Punches after | no | inc-dzz |
| `Map::At()` answered an out-of-bounds query with the (0,0) square instead of failing, so monster AI read off the edge of the map 343 times in 13 seconds. Guarded at `Map::GetAt`, the funnel every accessor uses (`src/Display.cpp`) | **Observed** -- 444 error lines in 13s, then 0 across 877 turns | **yes**, rmtew#40 + #41, open | inc-f13 |
| `TargetSystem::giveOrder` built its `Target` uninitialised, so an escort read stack garbage as the handle of the creature to follow. Two of the eight sites also left `damageDoneToMe` uninitialised, turning escorts hostile to their own leaders (`src/Target.cpp`) | **Observed** -- 250 seeds against a build differing in nothing else; asserts 89,545 -> 0, error lines 139,948 -> 48,245 | **yes**, rmtew#42, **MERGED** | inc-zmk |
| `TargetSort` ordered targets tied on priority and type by subtracting the two objects' addresses, so the same seed played a different game on every launch. The only comparator in `src/` doing pointer arithmetic (`src/Target.cpp`) | **Observed** -- randomisation off: 30 of 30 runs identical; on: 4 of 15 diverged; p = 0.9% | **yes**, rmtew#44, open | inc-qik |
| The `Falling` global was a raw `Creature*` carried across a level change. A faller that died on the way left it dangling, and the next creature the allocator placed on that address paid 3d6 per level it never fell (`src/Move.cpp`) | **Observed** -- seed 3, two layouts, same 204,218 draws: one rolled 6d6, the other did not. 40 of 40 seeds pass after; seed 3 failed a dozen attempts before | no | inc-yml |
| `tmpstr` wrote one pointer past the end of the 64000-entry `StrBufDelQueue` before testing the bound, and the `ASSERT` meant to stop it only logs and returns (`src/Base.cpp`) | **Observed** -- A/B on a probe build with `STRING_QUEUE_SIZE=400`, same seed, reproducing then not reproducing the live crash's twelve assert lines | no | inc-upw.18 |
| `CurrentRoutine` was a 64-byte global filled by `strcpy` and two `strcat`s with no length check, on the hottest path in the engine (`src/VMachine.cpp`) | **Traced** for the overrun -- read out of the code, never seen to fire. The *speed* half of the same commit is NOT listed: that one is ours, because the breadcrumb is inside `#ifdef DEBUG` and reached players only because our build must pass `-DDEBUG` (inc-9df.3) | no | inc-upw.20 |
| `Magic::Augury` held three defects in six lines: a handle cast to a pointer, a missing `isItem()` guard, and a `goto` to a label above the scan that made an item-free map loop forever (`src/Effects.cpp`) | **Traced** -- never executed. Augury has therefore never worked, which is also why there is no regression risk | no | inc-upw.1 |
| `Player::MoveDepth` declared its follower array `static` in a function that re-enters itself (`src/Feature.cpp`) | **Reasoned** -- kept as hardening only. The crash claim made for it in b3b5351 was retracted in 668043c after a controlled A/B showed the same seed segfaulting identically with and without it | **yes**, rmtew#43, sent as hardening, open | inc-upw.15 |

### Fixes deliberately NOT listed, because they are ours and not upstream's

Recording these matters as much as the table above: claiming our port artefact
is upstream's bug is the credibility cost this document opens with.

| Fix | Why it is ours |
|---|---|
| `*((long*)&hm)` destroyed the player's position in every save | Harmless on Win32, where `long` is 4 bytes. Our typedef narrowing created the overrun. The gate's worked example. |
| `int32` etc. were 64-bit off Windows; `src/AbiCheck.cpp` now gates the widths | The typedefs were correct for LLP64. This is the port meeting the base code, not a defect in it. |
| `src/RComp.cpp` is inside `#ifdef DEBUG` while generated `yygram.cpp` calls it unconditionally | A build-configuration collision that only a non-Windows build reaches. |
| `argv[0]` resolved to an absolute path at startup | Visual Studio always supplied an absolute `argv[0]`, so Windows never saw it. Borderline -- a Win32 user launching from `cmd` in the game directory would get a bare filename -- but there is no evidence it misbehaves there, and no-evidence means do not claim it. |
| macOS window dimming, and the input failure traced to the machine | Platform-specific, and the second was not a code defect at all. |
| Saves keyed on the layout they were written with | A port-format problem that the base code cannot have. |
| The `#ifdef DEBUG` VM breadcrumb's *speed* cost | Upstream ships without `DEBUG` and never paid it. Only the unbounded write inside it is theirs. |
| The pathfinding terrain cache, and clearing only the map that exists | A performance improvement, not a defect fix. Nothing was incorrect before it. |

### Base-code fixes that arrived before this port

`esran` fixed three base-code defects in the `networkingguru` fork before this
port began, and they are in the tree unmarked: the god-abandonment bug
(961c54b, 2021), grey dwarves' missing racial weapons (ceceebf, 2021), and
`Race::HasSkill` reading only the first six skills (9cbc308, 2025). They are
upstream defects by the gate's test, but they are not this port's work and
carry no evidence we generated. They are listed here rather than marked in the
source, so the marker convention keeps meaning "this port found and fixed it".

**This table was completed by inc-iqh on 2026-08-16**, which swept the port's
history for base-code defects. It is complete as of that date for fixes made in
this repository. `tools/check_upstream_marks.sh` still cannot find an unmarked
fix on its own -- nothing tells it which diffs were bug fixes -- so the rule in
AGENTS.md and CLAUDE.md remains the only thing that keeps this table current.

## Current status of our issues

### Sent to rmtew

| PR | Tier when sent | Status as of 2026-08-16 |
|---|---|---|
| [#42](https://github.com/rmtew/incursion-roguelike/pull/42) zero-initialise `Target` at its eight construction sites | **Observed** -- 89,545 asserts to 0 over 250 seeds, against a build differing in nothing else | **MERGED** 2026-08-15 |
| [#41](https://github.com/rmtew/incursion-roguelike/pull/41) bounds-check `Map::GetAt()` | **Observed** -- 444 errors in 13s, then 0 across 877 turns | open, no comment or review since 2026-08-14 |
| [#43](https://github.com/rmtew/incursion-roguelike/pull/43) `MoveDepth` re-entrancy | **Reasoned** -- sent as hardening, explicitly NOT as a crash fix, after the crash claim was retracted | open |
| [#44](https://github.com/rmtew/incursion-roguelike/pull/44) compare handles, not addresses, in `TargetSort` | **Observed** -- seed 8 went 1 divergence in 6 runs to 18 identical in 18; randomisation off gave 30 of 30 identical against 4 of 15 diverging with it on | sent 2026-08-16 |

**Read the pattern before sending anything else.** The one that merged is the one
whose evidence was a number that moved on both sides of a controlled run. The
other two have sat without a word. That is exactly what this document predicts,
and it is the first real-world confirmation the gate has had -- so the answer for
#41 and #43 is better evidence, not a reminder email.

**Why #44 was the next one sent, and it is not only the tier.** #41 is Observed
too and has not moved, so meeting the evidence bar is necessary and not
sufficient. The sharper difference is how much work the patch asks of a
maintainer who does not know this fork. #42 changed nothing any caller could
observe except the bug, so it could be verified in isolation. #41 makes
`Map::GetAt()` return NULL where it used to return a square, which cannot be
accepted without auditing every accessor that funnels through it. #44 sits on
the #42 side: the comparator's contract is unchanged and only its tiebreak input
moves, so nothing outside the function needs re-reading. Whether that reading is
right is now a live prediction rather than a claim, and #44 is the test of it.

Note that #41's tier is Observed and it still has not moved. Meeting the bar buys
a fair hearing, not a merge. Nothing is owed by a maintainer who never asked for
our help.

### Not sent

| Issue | Tier | Why not |
|---|---|---|
| `Thing::Remove` corruption | **Observed** -- 57 occurrences logged | no diagnosis, so no patch; fileable as an observation |
| `FI_SIZE` inconsistency | **Observed** once; not reproduced | one sighting is not a report |
| window flicker | **Reasoned** -- cause unknown, one hypothesis already disproved | fails the gate; also macOS-only |
| `Magic::Augury`, 3 defects | **Traced** -- never executed | not until Observed |

Base-code defects fixed here but never submitted are marked in the source and
listed above under *Base-code bugs fixed locally*. Marking is not sending.
