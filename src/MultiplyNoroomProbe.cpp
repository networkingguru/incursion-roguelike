/* inc-40l9: stage the INCURSION_MULTIPLY_NOROOM trigger independently of the
   random stream, so tools/check_multiply_noroom.sh measures the guard whatever
   the seed. On waves the check used to wait for encounter generation to place a
   water-adjacent gremlin, which moved with every RNG-shifting commit and left
   the check INCONCLUSIVE on seeds 1 and 7.

   A no-op unless INCURSION_MULTIPLY_STAGE is set. Caller: Game::Play
   (src/Main.cpp), beside the other hand-placed probes. It places a gremlin
   beside the player and a TF_WATER square beside the gremlin, then returns: the
   game's own main loop throws EV_TURN every sixty turns, the gremlin's
   `On Event EV_TURN` (lib/mon2.irh) sees the water and calls
   Creature::Multiply (src/Creature.cpp). The probe never calls Multiply: the
   check must exercise the game's trigger path. The INCURSION_MULTIPLY_NOROOM
   switch then refuses the copy. */
#include "Incursion.h"

/* The player's square is not a creature square we may take; find an open one
   at distance `want` from (px,py). Mirrors the other probes' helper. */
static bool mnOpen(Map *mp, int x, int y) {
    return mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FCreatureAt(x, y);
}

static bool mnNear(Map *mp, int px, int py, int want, int *ox, int *oy) {
    for (int dy = -want; dy <= want; dy++)
        for (int dx = -want; dx <= want; dx++) {
            if (dist(px, py, px + dx, py + dy) != want) continue;
            if (mnOpen(mp, px + dx, py + dy)) {
                *ox = px + dx; *oy = py + dy;
                return true;
            }
        }
    return false;
}

void MultiplyNoroomProbe(Player *pl) {
    /* inc-40l9: hook for tools/check_multiply_noroom.sh. */
    if (!getenv("INCURSION_MULTIPLY_STAGE")) return;
    if (!pl || !pl->m) { Error("MULTIPLY_STAGE INCONCLUSIVE no player"); return; }
    Map *mp = pl->m;
    const rID gremlin = FIND("gremlin");
    const rID water   = FIND("shallow water");
    if (!gremlin || !water) {
        Error("MULTIPLY_STAGE INCONCLUSIVE missing gremlin/water resources");
        return;
    }

    int gx, gy, wx, wy;
    if (!mnNear(mp, pl->x, pl->y, 1, &gx, &gy)) {
        Error("MULTIPLY_STAGE INCONCLUSIVE no room beside the player");
        return;
    }
    /* A water square beside the gremlin (its own square counts in the script's
       3x3, so this is enough) that is not the player's square. */
    if (!mnNear(mp, gx, gy, 1, &wx, &wy) || (wx == pl->x && wy == pl->y)) {
        Error("MULTIPLY_STAGE INCONCLUSIVE no room for water");
        return;
    }

    Monster *g = new Monster(gremlin);
    TMON(g->tmID)->GrantGear(g, g->tmID, true);
    TMON(g->tmID)->PEvent(EV_BIRTH, g, g->tmID);
    g->PlaceAt(mp, gx, gy);
    g->Initialize(true);
    /* Keep it put: an awake gremlin could walk off the water before the game's
       sixtieth turn reaches it. A sleeping creature still receives the EV_TURN
       the main loop throws at every thing on the map. */
    g->GainPermStati(ASLEEP, NULL, SS_MISC);
    g->RemoveStati(SLEEPING);
    g->mHP = g->cHP = 10000;

    mp->WriteTerra(wx, wy, water);
    mp->Update(wx, wy);
    Error("MULTIPLY_STAGE gremlin=%d,%d water=%d,%d", gx, gy, wx, wy);
}
