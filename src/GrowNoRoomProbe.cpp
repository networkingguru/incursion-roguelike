/* inc-o37m / inc-7giv probe: growth with no room, and a stale size after a
   shape change. A no-op unless INCURSION_GROW_NOROOM_PROBE is set ("hp" also
   logs the polymorph HP measurements for a monster and the player). Caller:
   Game::Play (src/Main.cpp). Reader: tools/check_grow_noroom.sh. */
#include "Incursion.h"

extern int GrowBlockedMsgCount; /* src/Values.cpp */

static const int R = 8; /* box half-width: PlaceNear radius 6 + bulk 1, +1 */

static bool freeBox(Player *pl, int cx, int cy) {
    Map *mp = pl->m;
    for (int x = cx - R; x <= cx + R; x++)
        for (int y = cy - R; y <= cy + R; y++) {
            if (!mp->InBounds(x, y) || mp->FCreatureAt(x, y) ||
                mp->FFeatureAt(x, y) || mp->FallAt(x, y))
                return false;
            if (TTER(mp->TerrainAt(x, y))->HasFlag(TF_WARN))
                return false;
        }
    return true;
}

static bool hasBulk(Map *mp, Creature *c) {
    for (int i = 0; mp->Fields[i]; i++)
        if (mp->Fields[i]->Creator == c->myHandle &&
            (mp->Fields[i]->FType & FI_SIZE))
            return true;
    return false;
}

void GrowNoRoomProbe(Player *pl) {
    const char *mode = getenv("INCURSION_GROW_NOROOM_PROBE");
    if (!mode) return;
    if (!pl || !pl->m) {
        Error("GROW_NOROOM_PROBE INCONCLUSIVE no live player and map");
        return;
    }
    Map *mp = pl->m;
    const rID ogre = FIND("ogre"), dwarf = FIND("dwarf"),
              spider = FIND("phase spider");
    if (!ogre || !dwarf || !spider) {
        Error("GROW_NOROOM_PROBE INCONCLUSIVE missing ogre, dwarf or phase spider");
        return;
    }
    int cx = -1, cy = -1;
    for (int x = R; x < 256 && cx < 0; x++)
        for (int y = R; y < 256; y++)
            if (freeBox(pl, x, y)) { cx = x; cy = y; break; }
    if (cx < 0) {
        Error("GROW_NOROOM_PROBE INCONCLUSIVE no free %dx%d box", 2*R+1, 2*R+1);
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;

    /* Wall the box in, leaving one open column at x == cx. */
    static bool oSolid[2*R+1][2*R+1], oOpaque[2*R+1][2*R+1];
    for (int x = cx - R; x <= cx + R; x++)
        for (int y = cy - R; y <= cy + R; y++) {
            oSolid[x-cx+R][y-cy+R] = mp->At(x, y).Solid;
            oOpaque[x-cx+R][y-cy+R] = mp->At(x, y).Opaque;
            bool open = (x == cx);
            mp->At(x, y).Solid = !open;
            mp->At(x, y).Opaque = !open;
        }

    /* Scene a: a Large creature in the corridor gains Enlarge. */
    Monster *og = new Monster(ogre);
    og->PlaceAt(mp, cx, cy, true);
    og->Initialize(true);
    og->Timeout = 0;
    hObj ogH = og->myHandle;
    int sizeBefore = og->GetAttr(A_SIZ);
    int msg0 = GrowBlockedMsgCount;
    Error("GROW_NOROOM_PROBE FIRE box=%d,%d size=%d", cx, cy, sizeBefore);
    og->GainPermStati(ADJUST, pl, SS_ENCH, A_SIZ, 1);
    og->CalcValues();
    og->CalcValues();
    bool alive = theRegistry->Exists(ogH) && og->m == mp;
    Error("GROW_NOROOM_PROBE a alive=%d size=%d bulk=%d msgs=%d",
        (int)alive, alive ? (int)og->GetAttr(A_SIZ) : -1,
        alive ? (int)hasBulk(mp, og) : -1, GrowBlockedMsgCount - msg0);
    if (!alive) {
        theGame->PlayMode = wasInPlay;
        return;
    }

    /* Scene b: the walls come down, a recalculation retries the growth. */
    for (int x = cx - R; x <= cx + R; x++)
        for (int y = cy - R; y <= cy + R; y++) {
            mp->At(x, y).Solid = false;
            mp->At(x, y).Opaque = false;
        }
    msg0 = GrowBlockedMsgCount;
    og->CalcValues();
    alive = theRegistry->Exists(ogH) && og->m == mp;
    Error("GROW_NOROOM_PROBE b alive=%d size=%d bulk=%d msgs=%d",
        (int)alive, alive ? (int)og->GetAttr(A_SIZ) : -1,
        alive ? (int)hasBulk(mp, og) : -1, GrowBlockedMsgCount - msg0);
    if (alive)
        og->Remove(true);

    /* Scene c: a Medium monster with Enlarge polymorphs into a Large form.
       Enlarge (+1) on the form: Large 5 + 1 = Huge 6, read at once. */
    Monster *dw = new Monster(dwarf);
    dw->PlaceAt(mp, cx, cy, true);
    dw->Initialize(true);
    dw->Timeout = 0;
    hObj dwH = dw->myHandle;
    dw->GainPermStati(ADJUST, pl, SS_ENCH, A_SIZ, 1);
    int hpB = dw->cHP, mhpB = dw->mHP, thB = dw->Attr[A_THP];
    int szB = dw->GetAttr(A_SIZ);
    dw->Shapeshift(spider, false, NULL);
    alive = theRegistry->Exists(dwH) && dw->m == mp;
    Error("GROW_NOROOM_PROBE c alive=%d before=%d after=%d",
        (int)alive, szB, alive ? (int)dw->GetAttr(A_SIZ) : -1);
    if (alive && !strcmp(mode, "hp"))
        Error("GROW_NOROOM_PROBE hp monster cHP %d->%d mHP %d->%d THP %d->%d",
            hpB, (int)dw->cHP, mhpB, (int)dw->mHP, thB, (int)dw->Attr[A_THP]);
    if (alive)
        dw->Remove(true);

    if (!strcmp(mode, "hp")) {
        int pc = pl->cHP, pm = pl->mHP, pt = pl->Attr[A_THP];
        pl->Shapeshift(spider, false, NULL);
        Error("GROW_NOROOM_PROBE hp player cHP %d->%d mHP %d->%d THP %d->%d",
            pc, (int)pl->cHP, pm, (int)pl->mHP, pt, (int)pl->Attr[A_THP]);
    }

    for (int x = cx - R; x <= cx + R; x++)
        for (int y = cy - R; y <= cy + R; y++) {
            mp->At(x, y).Solid = oSolid[x-cx+R][y-cy+R];
            mp->At(x, y).Opaque = oOpaque[x-cx+R][y-cy+R];
        }
    Error("GROW_NOROOM_PROBE COMPLETE");
    theGame->PlayMode = wasInPlay;
}
