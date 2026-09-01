# Close comment for networkingguru/incursion-roguelike issue #2

Status: DRAFTED 2026-08-31. Brian has read this text. NOT YET POSTED --
waiting on his explicit go. Post as a comment, then close the issue as
completed.

Command when approved:
    gh issue comment 2 -R networkingguru/incursion-roguelike -F docs/outgoing/gh2-close.md
(strip this header block first -- post only the text below the line)

---

Fixed in 2092592, "Let a swallowed player off the monster before he takes the stairs".

**Root cause.** `Player::MoveDepth` called a bare `RemoveStati(ENGULFED)`. That dropped the player out of the engulfed state but left him exactly where `Creature::DoEngulf` had put him: still in `m->Things`, in no square's Contents chain, standing on the engulfer's square, with the matching ENGULFER stati still on the monster. The `PlaceAt` further down then called `Thing::Remove`, which took the ordinary path because the stati was gone, could not find him in that square's chain, printed this error and returned early — skipping the rest of its own work.

So the answer to "what puts a creature on a map without registering it" is being swallowed. Being engulfed and then taking a staircase is enough; it is not wizard-mode only.

The fix hands the pair to the engulfer's own `DropEngulfed(this)`, which removes both halves of the stati pair and places the victim back on the map properly.

**Evidence.** `tools/soak.sh 24 1 tools/keys/dive.keys` went from one error line and one map-audit finding to none, twice. A 40-seed run lost both of its "Contents list wierdless" sessions and both "orphan: claims this map but is in neither list" audit findings.

Diagnosis and fix assisted by AI (Claude); the measurements and this text reviewed by me.
