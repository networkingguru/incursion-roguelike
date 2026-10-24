/* inc-07y9: opt-in column-zero reproduction through the live globe path. */
#include "Incursion.h"

void TerraformEdgeProbe(Player *pl) {
    if (!getenv("INCURSION_TERRAFORM_EDGE_PROBE")) return;
    const rID effect = FIND("Grease"), floor = FIND("floor"),
        grease = FIND("pool of grease");
    if (!pl || !pl->m || !effect || !floor || !grease ||
        pl->m->SizeX() < 16 || pl->m->SizeY() < 28) {
        Error("TERRA_EDGE_PROBE: FAIL -- missing map or resources");
        return;
    }
    Map *mp = pl->m;
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    const rID region = mp->RegionAt(pl->x, pl->y);
    Thing *obj; int index;
    for (;;) {
        Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != pl) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    Rect rect(0, 0, mp->SizeX()-1, mp->SizeY()-1);
    for (int y = 5; y <= 25; ++y)
        for (int x = 0; x <= 12; ++x) {
            mp->RemoveTerraXY(x, y);
            mp->WriteAt(rect, x, y, floor, region, PRIO_MAX, true);
        }
    pl->PlaceAt(mp, 10, 20);
    if (pl->x != 10 || pl->y != 20 || mp->TerrainAt(0,20) != floor ||
        mp->TerrainAt(0,10) != floor || mp->TerrainAt(10,20) != floor) {
        Error("TERRA_EDGE_PROBE: FAIL -- arena setup");
        theGame->PlayMode = wasInPlay;
        return;
    }
    /* B first preserves the silent-case evidence when A crashes. */
    const rID before = mp->TerrainAt(pl->x, pl->y);
    ThrowEffXY(EV_EFFECT, effect, 1, 20, pl, pl);
    const bool colB = mp->TerrainAt(0,20) == grease;
    const bool targetChanged = mp->TerrainAt(pl->x,pl->y) != before;
    Error("TERRA_EDGE_PROBE: B col0=%d target_sq=%d",
        (int)colB, (int)targetChanged);
    Error("TERRA_EDGE_PROBE: BEGIN A ETarget=NULL centre=(1,10)");
    ThrowEffXY(EV_EFFECT, effect, 1, 10, pl, NULL);
    const bool colA = mp->TerrainAt(0,10) == grease;
    Error("TERRA_EDGE_PROBE: A col0=%d target_sq=na", (int)colA);
    Error("TERRA_EDGE_PROBE: %s", colA && colB && !targetChanged ? "PASS" : "FAIL");
    theGame->PlayMode = wasInPlay;
}
