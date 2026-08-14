/* MAPAUDIT.H -- See the Incursion LICENSE file for copyright information.

     A consistency check on the map's two views of itself. Off unless
   INCURSION_MAP_AUDIT is set in the environment; writes logs/mapaudit.log.

     Every Thing on a map is recorded twice: once in the flat array m->Things[],
   and once in the linked list hanging off the Contents field of the square it
   stands on. Rendering reads the second. So the interesting question is not
   whether the screen matches the state -- it is whether the state matches
   itself, one level below the renderer, where a mismatch is exact rather than
   inferred from pixels.

     This exists because Thing::Remove reports "Contents list wierdless" and
   then returns early, skipping the rest of teardown. The Thing is left absent
   from both lists while still holding a map pointer and coordinates, never
   marked deleted and never destroyed. See bead inc-6d5.
*/

#ifndef INCURSION_MAPAUDIT_H
#define INCURSION_MAPAUDIT_H

class Map;

/* True when INCURSION_MAP_AUDIT is set. Cheap; call it before doing work. */
bool MapAuditEnabled();

/* Check `m` and append any violations to logs/mapaudit.log. `when` labels the
   call site, so a report says what the game was doing at the time. Safe to
   call with a NULL map. */
void AuditMap(Map *m, const char *when);

#endif
