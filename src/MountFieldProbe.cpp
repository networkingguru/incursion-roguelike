/* inc-h5v6o: opt-in oracle for "a ridden mount gets the field events its
   rider gets from Map::NewField, MoveField and RemoveField", enabled by
   INCURSION_MOUNT_FIELD_PROBE=1. Mounts a kobold on a pony, moves a Globe of
   Shadow (made by a third creature) over and off the rider 20 times, then
   creates and removes it over the rider. Prints one MOUNT_FIELD_PROBE line to
   logs/errors.log. See tools/check_mount_field.sh. */
#define protected public
#include "Incursion.h"
#undef protected

/* Place a no-gear monster on the free floor square nearest the player at
   least minR squares away. NULL when none is free within 8 squares. */
static Monster *mfMake(Player *pl, rID mID, int minR) {
    Map *m = pl->m;
    for (int r = minR; r <= 8; r++)
        for (int dx = -r; dx <= r; dx++)
            for (int dy = -r; dy <= r; dy++) {
                int x = pl->x + dx, y = pl->y + dy;
                if (!m->InBounds(x,y) || m->SolidAt(x,y) || m->FCreatureAt(x,y))
                    continue;
                Monster *mn = new Monster(mID);
                TMON(mn->tmID)->PEvent(EV_BIRTH,mn,mn->tmID);
                mn->PlaceAt(m,x,y);
                mn->Initialize(true);
                return mn;
            }
    return NULL;
}

/* Stati on c that the field effect eID granted. */
static int mfCount(Creature *c, rID eID) {
    int n = 0;
    StatiIter(c)
        if (S->eID == eID) n++;
    StatiIterEnd(c)
    return n;
}

static Field *mfLast(Map *m) {
    int i = 0;
    while (m->Fields[i]) i++;
    return i ? m->Fields[i-1] : NULL;
}

void MountFieldProbe(Player *pl) {
    if (!getenv("INCURSION_MOUNT_FIELD_PROBE")) return;
    rID kob = FIND("kobold"), pony = FIND("pony"), globe = FIND("Globe of Shadow");
    if (!pl || !pl->m || !kob || !pony || !globe) {
        Error("MOUNT_FIELD_PROBE: setup INCONCLUSIVE missing player/map/resource");
        return;
    }
    Map *m = pl->m;
    Monster *rider = mfMake(pl,kob,1), *mount = mfMake(pl,pony,1),
            *maker = mfMake(pl,kob,3);
    if (!rider || !mount || !maker) {
        Error("MOUNT_FIELD_PROBE: setup INCONCLUSIVE no free squares");
        return;
    }
    rider->GainPermStati(EXTRA_SKILL,NULL,SS_MISC,SK_RIDE);
    rider->CalcValues();
    mount->GainPermStati(ANIMAL_COMPANION,pl,SS_MISC);
    mount->MakeCompanion(pl,PHD_FREEBIE);
    rider->MakeCompanion(pl,PHD_FREEBIE);
    Throw(EV_MOUNT,rider,mount);
    bool mounted = rider->GetStatiObj(MOUNTED) == mount &&
                         mount->GetStatiObj(MOUNT) == rider;
    bool onlist = false;
    Thing *t; int i;
    MapIterate(m,t,i)
        if (t == mount) onlist = true;
    if (!mounted) {
        Error("MOUNT_FIELD_PROBE: setup INCONCLUSIVE mounted=no onlist=%s ride=%d mountable=%d hostile=%d ts=%d",
              onlist ? "yes" : "no",(int)rider->HasSkill(SK_RIDE),
              (int)mount->HasMFlag(M_MOUNTABLE),(int)mount->isHostileTo(rider),
              (int)(rider->GetAttr(A_SIZ)));
        return;
    }

    /* A one-square field starts far from the rider. Each cycle the rider
       walks into it with Thing::Move (which throws to the mount), then
       MoveField takes the field away (which must reach the mount too). */
    const int rx = rider->x, ry = rider->y;
    int dx2 = 0, fx = rx, fy = ry;
    for (int r = 2; r <= 4 && dx2 == 0; r++)
        for (int sgn = -1; sgn <= 1 && dx2 == 0; sgn += 2)
            if (m->InBounds(rx+sgn*r,ry) && !m->SolidAt(rx+sgn*r,ry) &&
                    !m->FCreatureAt(rx+sgn*r,ry))
                dx2 = sgn*r;
    for (int r = 6; r <= 9 && fx == rx; r++)
        if (m->InBounds(rx+r,ry) && !m->SolidAt(rx+r,ry) && rx+r != rx+dx2) { fx = rx+r; fy = ry; }
    if (!dx2 || fx == rx) {
        Error("MOUNT_FIELD_PROBE: setup INCONCLUSIVE no square for the field");
        return;
    }
    const int dxs = rx+dx2, dys = ry;
    const int FT = FI_SHADOW|FI_MODIFIER;
    Glyph g = GLYPH_VALUE(GLYPH_FLOOR2, WHITE);
    m->NewField(FT,dxs,dys,0,g,-1,globe,maker);
    Field *f = mfLast(m);
    if (!f) { Error("MOUNT_FIELD_PROBE: setup INCONCLUSIVE no field"); return; }
    /* Park the field away from the rider before the first cycle. */
    m->MoveField(f,fx,fy,false);

    int maxcount = 0, afterleave = 0;
    for (int k = 0; k < 20; k++) {
        m->MoveField(f,dxs,dys,false);
        rider->Move(dxs,dys,false);
        int c = mfCount(mount,globe);
        if (c > maxcount) maxcount = c;
        m->MoveField(f,fx,fy,false);
        afterleave = mfCount(mount,globe);
        if (afterleave > maxcount) maxcount = afterleave;
        rider->Move(rx,ry,false);
    }
    m->RemoveField(f);
    const bool home = rider->x == rx && rider->y == ry &&
                      mount->x == rx && mount->y == ry;

    m->NewField(FT,rx,ry,1,g,-1,globe,maker);
    const int afternew = mfCount(mount,globe);
    f = mfLast(m);
    if (f) m->RemoveField(f);
    const int afterremove = mfCount(mount,globe);

    onlist = false;
    MapIterate(m,t,i)
        if (t == mount) onlist = true;
    if (!home || rider->GetStatiObj(MOUNTED) != mount) mounted = false;
    Error("MOUNT_FIELD_PROBE mounted=%s onlist=%s maxcount=%d afterleave=%d afternew=%d afterremove=%d",
          mounted ? "yes" : "no",onlist ? "yes" : "no",maxcount,afterleave,
          afternew,afterremove);
}
