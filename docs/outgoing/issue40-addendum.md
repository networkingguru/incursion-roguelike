This work was done with AI assistance (Claude) — the probes, the seeded runs and the analysis, not only the prose. No line numbers are cited below, deliberately: our tree has drifted from yours and function names travel better.

**Addendum: what we settled on in our fork.** Recording it here so it is on the issue. Nothing needed from you.

**The out-of-bounds reads.** We repaired a different site from the one I proposed above. That comment suggested reserving two squares in `PlaceWithinSafely`; we changed `Rect::PlaceWithin` instead.

When the requested size does not fit, `PlaceWithin` insets by one on each side. If the space is two squares across or less, that puts the far edge before the near one, and the function has no way to report failure — so it returns an inverted rectangle. Its only caller uses that rectangle as the wall ring of a room's inner chamber: it walks the four edges writing wall, then punches a door into one. An inverted ring gets walked backwards.

We built and measured two repairs. Collapsing to a single row is arithmetically fine but leaves a ring one square thick, which is a line of wall with a door onto nothing — and it slips past the caller's own too-thin corrector a few lines later, because that tests for a ring exactly two across and never sees a ring of one. Widening to the whole available area hands that corrector a two-row ring, which it recognises and expands into a real chamber. Collapsing is also wrong where the space is a single square: it returns a row outside the space entirely. So we widened.

On our reproducing seed, out-of-bounds `Map::At()` reads go from 47,954 to 0. One caveat we could not remove: changing the rectangle changes what the random stream is spent on, so that zero is measured on a different set of levels, not on the same levels minus the defect.

**A separate crash, found while testing the above.** The new layout parked a hiding Huge monster in a square with no room for it. Revealing the monster restores its real size, `CalcValues` re-seats it through `PlaceNear`, `PlaceNear` deletes any non-player thing it cannot seat — and `Creature::MakeNoise` then dereferences the map pointer that deleting had just set to null. `MakeNoise` does check that pointer; the check simply runs before the call that invalidates it. Three further callers of `Creature::Reveal` have the same shape. We added the re-check that `Creature::StatiOn` already performs against the same hazard.

This one is independent of the rectangle work — any change to level layout can expose it, and it is reachable in the stock game. Happy to open it as its own issue if that is more useful than a note here.
