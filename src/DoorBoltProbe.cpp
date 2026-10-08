/* inc-a9m3 probe: a natural-attack breath weapon through a closed door.
   A no-op unless INCURSION_DOOR_BOLT_PROBE is set. Caller: Game::Play
   (src/Main.cpp). Reader: tools/check_door_bolt.sh. */
#include "Incursion.h"

static bool floorAt(Map *mp, int x, int y) {
    return mp->InBounds(x, y) && !mp->At(x, y).Solid &&
        !mp->FCreatureAt(x, y) && !mp->FFeatureAt(x, y);
}

/* Lines up, along one axis: a closed door at p-d, the player at p, an empty
   square at p+d, a water mephit at p+2d (its A_BREA has A_ALSO riders,
   which Creature::Hit re-throws as plain EV_HIT). A closed door blocks line of fire, so
   the door goes BEHIND the player: a breath is a beam and runs on past its
   victim into the door. The mephit breathes at the player through Creature::SAttack (A_BREA), the real natural-attack path, which
   reaches Magic::ABallBeamBolt with isNAttack set. Logs, through Error():
     DOOR_BOLT_PROBE COMPLETE
   only if ThrowVal returns. */
void DoorBoltProbe(Player *pl) {
    if (!getenv("INCURSION_DOOR_BOLT_PROBE")) return;
    if (!pl || !pl->m) {
        Error("DOOR_BOLT_PROBE INCONCLUSIVE no live player and map");
        return;
    }
    Map *mp = pl->m;
    const rID mephit = FIND("water mephit"), oak = FIND("oak door");
    if (!mephit || !oak) {
        Error("DOOR_BOLT_PROBE INCONCLUSIVE missing water mephit or oak door");
        return;
    }
    static const int dirs[4][2] = { {1,0}, {-1,0}, {0,1}, {0,-1} };
    int dx = 0, dy = 0, k;
    for (k = 0; k < 4; k++) {
        dx = dirs[k][0]; dy = dirs[k][1];
        int i;
        for (i = -1; i <= 2; i++)
            if (i && !floorAt(mp, pl->x + dx * i, pl->y + dy * i)) break;
        if (i > 2) break;
    }
    if (k == 4) {
        Error("DOOR_BOLT_PROBE INCONCLUSIVE no 4 free squares in a line");
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    /* Walls either side, so Door::SetImage reads a frame and does not brand
       the door broken (a broken door is not F_SOLID). */
    for (int s = -1; s <= 1; s += 2) {
        int wx = pl->x - dx + dy * s, wy = pl->y - dy + dx * s;
        if (!mp->InBounds(wx, wy) || mp->FCreatureAt(wx, wy)) {
            Error("DOOR_BOLT_PROBE INCONCLUSIVE cannot wall the door");
            return;
        }
        mp->At(wx, wy).Solid = mp->At(wx, wy).Opaque = true;
    }
    Door *door = new Door(oak);
    door->PlaceAt(mp, pl->x - dx, pl->y - dy);
    door->DoorFlags = 0;
    door->Flags |= F_SOLID;
    door->SetImage();
    Monster *mn = new Monster(mephit);
    mn->PlaceAt(mp, pl->x + dx * 2, pl->y + dy * 2, true);
    mn->Initialize(true);
    mn->Timeout = 0;
    Error("DOOR_BOLT_PROBE FIRE actor=%s door_solid=%d", "water mephit",
        (int)((door->Flags & F_SOLID) != 0));
    EvReturn r = ThrowVal(EV_SATTACK, A_BREA, mn, pl);
    Error("DOOR_BOLT_PROBE COMPLETE ret=%d", (int)r);
    theGame->PlayMode = wasInPlay;
}
