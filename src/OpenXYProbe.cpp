/* inc-upw.3 diagnostic: count empty queries, inspect the solid corner's
   Contents after PlaceOpen, and test every placement's own square.
   No RNG calls and no game-state writes: Map::At, Map::InBounds and
   Registry::Exists are read-only, and nothing here calls random().
   INCURSION_OPENXY_PROBE=1 writes logs/openxyprobe.log; every event writes
   flushed totals, so a crashed session retains its last completed sample.
   Build with -DINCURSION_OPENXY_PROBE; add -DINCURSION_OPENXY_UNGUARDED
   for upstream's ASSERT, zero return and unchecked placement.
   Not wired into a normal build. tools/check_open_xy.sh is the only caller
   and reads the last line; that script says what each field must be. */
#include "Incursion.h"

#ifdef INCURSION_OPENXY_PROBE
#include <cstdlib>
static unsigned long empty = 0, disposed = 0, placed = 0, stranded = 0;
static unsigned long peak = 0, invalid = 0, badsq = 0, inband = 0;
static bool enabled() {
    const char *e = getenv("INCURSION_OPENXY_PROBE");
    return e && *e && *e != '0';
}
static void totals(unsigned long corner) {
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/openxyprobe.log", (const char*)T1->IncursionDirectory);
    FILE *f = fopen(path, "a");
    if (f) {
        fprintf(f, "empty=%lu disposed=%lu placed=%lu stranded=%lu corner=%lu "
                   "peak=%lu invalid=%lu badsq=%lu inband=%lu\n",
                empty, disposed, placed, stranded, corner, peak, invalid,
                badsq, inband);
        fclose(f);
    }
}
#endif

#ifdef INCURSION_OPENXY_PROBE
/* Length of the solid corner's Contents list; sets *found when thing is on it.
   invalid counts a list that could not be walked, once per walk. */
static unsigned long CornerWalk(Map *map, Thing *thing, bool *found) {
    unsigned long n = 0;
    bool broke = false;
    if (!map || !map->At(0,0).Solid)
        return 0;
    hObj h = map->At(0,0).Contents;
    while (h && n < 100000) {
        if (!theRegistry->Exists(h)) { ++invalid; broke = true; break; }
        ++n;
        if (thing && h == thing->myHandle) *found = true;
        h = oThing(h)->Next;
    }
    if (h && !broke) ++invalid;
    return n;
}
#endif

#ifdef INCURSION_OPENXY_PROBE
void OpenXYProbe(Map *map, Thing *thing, int event) {
    if (!enabled()) return;
    bool found = false;
    unsigned long corner = CornerWalk(map, thing, &found);
    /* The sentinel must be out of band on THIS map. NO_OPEN_XY decoding to a
       real square is the defect it replaces. */
    if (map && map->InBounds(NO_OPEN_XY % 256, NO_OPEN_XY / 256)) ++inband;
    if (corner > peak) peak = corner;
    if (event == 0) ++empty;
    if (event == 2 && thing && (thing->Flags & F_DELETE) && !thing->m && !found) ++disposed;
    if (event == 1 && found) ++stranded;
    /* badsq counts a placement that landed off the map or in rock ANYWHERE;
       stranded is the (0,0) special case of the same fault. */
    if (event == 1 && thing && thing->m == map && thing->x >= 0 && thing->y >= 0
        && !(thing->Flags & F_DELETE)) {
        if (!map->InBounds(thing->x,thing->y) || map->At(thing->x,thing->y).Solid)
            ++badsq;
        else
            ++placed;
    }
    totals(corner);
}
#endif
