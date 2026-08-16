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

**This table is incomplete, and knowingly so.** The convention dates from
2026-08-16; every defect this port fixed before that is unmarked and unlisted.
`tools/check_upstream_marks.sh` cannot find them, because nothing tells it which
past diffs were bug fixes. Closing that gap is inc-iqh.

## Current status of our issues

### Sent to rmtew

| PR | Tier when sent | Status as of 2026-08-16 |
|---|---|---|
| [#42](https://github.com/rmtew/incursion-roguelike/pull/42) zero-initialise `Target` at its eight construction sites | **Observed** -- 89,545 asserts to 0 over 250 seeds, against a build differing in nothing else | **MERGED** 2026-08-15 |
| [#41](https://github.com/rmtew/incursion-roguelike/pull/41) bounds-check `Map::GetAt()` | **Observed** -- 444 errors in 13s, then 0 across 877 turns | open, no comment or review since 2026-08-14 |
| [#43](https://github.com/rmtew/incursion-roguelike/pull/43) `MoveDepth` re-entrancy | **Reasoned** -- sent as hardening, explicitly NOT as a crash fix, after the crash claim was retracted | open |

**Read the pattern before sending anything else.** The one that merged is the one
whose evidence was a number that moved on both sides of a controlled run. The
other two have sat without a word. That is exactly what this document predicts,
and it is the first real-world confirmation the gate has had -- so the answer for
#41 and #43 is better evidence, not a reminder email.

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
