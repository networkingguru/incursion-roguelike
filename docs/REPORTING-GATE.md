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

**Line 106 below is stale.** Material has since gone to the parent project; see
the top of `CLAUDE.md`, which records that two pull requests went out on
2026-08-15. As of 2026-08-16 three submitted items are awaiting a maintainer
response, and nothing further goes out until they are answered. Update this
table with the specifics when somebody has them to hand.


| Issue | Tier | Upstream? |
|---|---|---|
| gh-1 out-of-bounds map reads | **Observed** -- 444 errors in 13s, then 0 in 877 turns | eligible, not yet sent |
| gh-2 `Thing::Remove` corruption | **Observed** -- 57 occurrences logged; no diagnosis, so no patch | eligible as an observation |
| gh-3 `FI_SIZE` inconsistency | **Observed** once; not reproduced | eligible as an observation |
| gh-4 window flicker | **Reasoned** -- cause unknown, one hypothesis already disproved | no; also macOS-only |
| gh-5 `Magic::Augury`, 3 defects | **Traced** -- never executed | not until Observed |

Nothing has been sent to `rmtew` or `HexDecimal`. No issue, no pull request.
