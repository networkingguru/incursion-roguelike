# What has been fixed

This page is the engineering record. The [README](../README.md) is about playing
the game; this is about what was broken and what was done to it.

Every entry states how it was verified. Where a claim was wrong, the retraction
is here too — `docs/REPORTING-GATE.md` is the rule that requires it.

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

**Monster AI read off the edge of the map, 343 times in 13 seconds.**
`Map::At()` answered an out-of-bounds query by returning the square at (0,0)
rather than failing, so wrong answers looked real. Guarding the single function
every accessor funnels through took the error log from 444 entries in 13 seconds
to zero across 877 turns.

That last one is an upstream defect, not a port artefact, and it was sent back:
[rmtew#40](https://github.com/rmtew/incursion-roguelike/issues/40) and
[rmtew#41](https://github.com/rmtew/incursion-roguelike/pull/41).

---

## Found by the game playing itself

About 1,100 unattended sessions have run. The harness drives the game from a key
script with no display and no keyboard, so a defect that needs ten thousand turns
to show up can be found overnight.

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

**The game got slower the longer it ran.** Every VM event built a debug string,
and every macOS build was a DEBUG build. That single line was 89% of a
pathfinding burst.

**A string queue wrote past its own bound** before checking it, and the assert
that was supposed to stop it ran afterwards.

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

---

## A claim that was withdrawn

Making `Player::MoveDepth`'s follower array re-entrant was committed as a
segfault fix. It is not one. A controlled A/B showed the same seed segfaulting
identically with and without it, on the same stack. The re-entrancy it describes
is real and the stack proves it, so the change is kept as hardening — but the
crash claim was wrong and is retracted in the history.

The original measurement passed because the scratch worktree it ran in lacked
the modified `Options.Dat` this tree uses, so no session in either arm ever
entered a map. Two runs that both did nothing agreed perfectly. That is the
whole reason the harness now has a `NO GAMEPLAY` exit code: a session that
measured nothing must never be read as a pass.

---

## The full list

Work is tracked in [Beads](https://github.com/gastownhall/beads), in the
repository itself rather than in this file. To read it:

```
bd list --status closed     # everything fixed
bd ready                    # what is available to work on now
bd show <id>                # one issue, with its evidence
```

Twenty-three issues are closed as of iNCURSION release 1. Each carries the
evidence that closed it, including the controls that were run and, where one
exists, the regression check left behind.

## Fixes that belong to upstream

Defects that are the base game's rather than this port's are marked in the source
with an `upstream:` comment and listed in
[`REPORTING-GATE.md`](REPORTING-GATE.md), so they can be found and sent on if the
original maintainer ever wants them:

```
grep -rn "upstream:" src/ inc/
tools/check_upstream_marks.sh
```
