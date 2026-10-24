/* inc-yp23: scene setup for tools/observe_hide_strike.sh; a no-op unless
   INCURSION_HIDE_STRIKE_PROBE is "freeze", "act", "freeze-lone" or "act-lone".
   It only PLACES things: one awake hostile watcher, the player hiding one step
   out of its sight, and (unless "-lone") a second creature hiding far away. The step
   and the blow are real key-script commands. It never calls HidePairsFor,
   SpotCheck or any roll. "freeze" keeps the watcher from acting for 200 ticks;
   "act" lets it act 5 ticks in, during the step. Caller:
   Game::Play (src/Main.cpp). This file is identical in both observed trees. */
#include "Incursion.h"
#include "HideCheck.h"

void HideStrikeProbe(Player *p) {
    const char *mode = getenv("INCURSION_HIDE_STRIKE_PROBE");
    if (!mode) return;
    if (!p || !p->m) { Error("HIDE_STRIKE INCONCLUSIVE no player"); return; }
    Map *mp = p->m;
    /* Step EAST (dA), then strike NORTH-EAST (dB): the key script is fixed to
       that. A wall must block the watcher's line to the start square. */
    const int ax = 1, ay = 0, bx = 1, by = -1;
    int x0 = -1, y0 = -1;
    for (int y = 1; y < mp->SizeY() - 1 && x0 == -1; ++y)
        for (int x = 1; x < mp->SizeX() - 1; ++x) {
            const int x1 = x + ax, y1 = y + ay, wx = x1 + bx, wy = y1 + by;
            if (!mp->InBounds(x1,y1) || !mp->InBounds(wx,wy)) continue;
            const int xs[3] = {x, x1, wx}, ys[3] = {y, y1, wy};
            bool ok = true;
            for (int k = 0; k < 3; ++k)
                if (mp->SolidAt(xs[k],ys[k]) || mp->FCreatureAt(xs[k],ys[k]) ||
                    mp->FFeatureAt(xs[k],ys[k])) ok = false;
            if (ok) {   /* no other creature near: the watcher must have no other quarrel */
                Creature *o; int oi;
                MapIterate(mp,o,oi)
                    if (o->isCreature() && o != p && dist(o->x,o->y,x1,y1) < 14) ok = false;
            }
            if (!ok || mp->BrightAt(x,y) || mp->BrightAt(x1,y1)) continue;
            if (mp->LineOfFire(wx,wy,x,y,p)) continue;
            if (mp->LineOfVisualSight(wx,wy,x,y,p)) continue;
            if (!mp->LineOfVisualSight(wx,wy,x1,y1,p)) continue;
            x0 = x; y0 = y; break;
        }
    if (x0 == -1) { Error("HIDE_STRIKE INCONCLUSIVE no scene geometry"); return; }
    const int x1 = x0 + ax, y1 = y0 + ay, wx = x1 + bx, wy = y1 + by;
    const bool playing = theGame->PlayMode;
    theGame->PlayMode = true;
    Creature *c; int idx;
    MapIterate(mp,c,idx)
        if (c->isCreature() && c != p) c->GainPermStati(ASLEEP,NULL,SS_MISC);
    Monster *w = new Monster(FIND("giant rat"));
    w->PlaceAt(mp,wx,wy);
    w->Initialize(true);
    w->RemoveStati(ASLEEP);
    w->RemoveStati(SLEEPING);
    w->RemoveStati(BLIND);
    w->Timeout = !strncmp(mode,"act",3) ? 5 : 200;
    /* A hiding decoy far out of every sight range. The old HidePairsFor
       returned at once unless SOME OTHER creature on the map was hiding. */
    bool decoy = false;
    if (!strstr(mode,"lone")) {
        for (int y = mp->SizeY() - 2; y > 0 && !decoy; --y)
            for (int x = 1; x < mp->SizeX() - 1 && !decoy; ++x)
                if (!mp->SolidAt(x,y) && !mp->FCreatureAt(x,y) &&
                    !mp->FFeatureAt(x,y) && dist(x,y,x1,y1) > 40) {
                    Monster *d = new Monster(FIND("giant rat"));
                    d->PlaceAt(mp,x,y);
                    d->Initialize(true);
                    d->GainPermStati(ASLEEP,NULL,SS_MISC);
                    d->RemoveStati(HIDING);
                    d->GainPermStati(HIDING,NULL,SS_CLAS,HI_SHADOWS,1);
                    HideStarted(d,false);
                    decoy = true;
                }
        if (!decoy) { Error("HIDE_STRIKE INCONCLUSIVE no decoy square"); return; }
    }
    p->PlaceAt(mp,x0,y0);
    p->RemoveStati(HIDING);
    p->GainPermStati(HIDING,NULL,SS_CLAS,HI_SHADOWS,1);
    HideStarted(p,false);
    theGame->PlayMode = playing;
    const bool sees0 = HideCanWatch(w,p);
    p->PlaceAt(mp,x1,y1);
    const bool sees1 = HideCanWatch(w,p);
    p->PlaceAt(mp,x0,y0);
    Error("HIDE_STRIKE SCENE mode=%s p0=%d,%d p1=%d,%d w=%d,%d hostile=%d awake=%d "
          "sees_at_p0=%d sees_at_p1=%d light=%d hiding=%d timeout=%d decoy=%d",
          mode,x0,y0,x1,y1,wx,wy,(int)w->isHostileTo(p),
          (int)!w->HasStati(ASLEEP),(int)sees0,(int)sees1,(int)p->LightRange,
          (int)p->HasStati(HIDING),(int)w->Timeout,(int)decoy);
    if (sees0 || !sees1) Error("HIDE_STRIKE INCONCLUSIVE watcher geometry");
}
