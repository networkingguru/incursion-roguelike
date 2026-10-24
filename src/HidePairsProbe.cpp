/* inc-yp23: controlled pair-scan inputs; never sets or reads a dice verdict.
   The checker counts calls logged inside HidePairsFor, not inside this probe. */
#include "Incursion.h"
#include "HideCheck.h"

static void hpScan(const char *name, Creature *c, bool turn = false) {
    Error("HIDE_PAIRS BEGIN case=%s",name);
    if (turn) HideTurnStart(c); else HidePairsFor(c);
    Error("HIDE_PAIRS END case=%s",name);
}

void HidePairsProbe(Player *p) {
    if (!getenv("INCURSION_HIDE_PAIRS_PROBE")) return;
    if (!p || !p->m) { Error("HIDE_PAIRS INCONCLUSIVE no player"); return; }
    Map *mp = p->m;
    int dx = 0, dy = 0;
    static const int dirs[][2] = {{1,0},{-1,0},{0,1},{0,-1}};
    for (int k = 0; k < 4; ++k) {
        int i;
        for (i = -1; i <= 3; ++i) {
            int x = p->x + dirs[k][0]*i, y = p->y + dirs[k][1]*i;
            if (!mp->InBounds(x,y) || mp->SolidAt(x,y) ||
                (i && (mp->FCreatureAt(x,y) || mp->FFeatureAt(x,y)))) break;
        }
        if (i == 4) { dx = dirs[k][0]; dy = dirs[k][1]; break; }
    }
    if (!dx && !dy) { Error("HIDE_PAIRS INCONCLUSIVE no scene space"); return; }
    const int hx = p->x, hy = p->y;
    const long savedTurn = theGame->Turn;
    const bool playing = theGame->PlayMode;
    const int8 autoMore = p->Options[OPT_AUTOMORE];
    theGame->PlayMode = true;
    p->Options[OPT_AUTOMORE] = 1;
    Creature *c; int idx;
    MapIterate(mp,c,idx)
        if (c->isCreature() && c != p) c->GainPermStati(ASLEEP,NULL,SS_MISC);
    Monster *watch[2];
    for (int k = 0; k < 2; ++k) {
        watch[k] = new Monster(FIND("giant rat"));
        watch[k]->PlaceAt(mp,hx+dx*(k+2),hy+dy*(k+2));
        watch[k]->Initialize(true);
        watch[k]->RemoveStati(ASLEEP);
        watch[k]->RemoveStati(SLEEPING);
        watch[k]->RemoveStati(BLIND);
        watch[k]->SightRange = 10;
        watch[k]->GainPermStati(HIDING,NULL,SS_CLAS,HI_SHADOWS,1);
        HideStarted(watch[k],false);
        if (!HideCanWatch(watch[k],p)) {
            Error("HIDE_PAIRS INCONCLUSIVE watcher cannot see hider"); return;
        }
    }
    Creature *w = watch[0], *w2 = watch[1];
    p->RemoveStati(HIDING);
    p->GainPermStati(HIDING,NULL,SS_CLAS,HI_SHADOWS,1);
    p->SightRange = 10;
    HideStarted(p,false);
    Error("HIDE_PAIRS SCENE h=%d w=%d w2=%d",(int)p->myHandle,(int)w->myHandle,(int)w2->myHandle);
    hpScan("1_turn",p,true);
    hpScan("1_pairs",p);
    hpScan("1_watcher",w);
    hpScan("2",w);
    p->PlaceAt(mp,hx-dx,hy-dy);
    hpScan("3a",w);
    HideStarted(p,false);
    hpScan("3b",w);
    w->PlaceAt(mp,hx+dx,hy+dy);
    w->SightRange = 10;
    hpScan("3c",w);
    w->SightRange = 9;
    hpScan("3d_range",w);
    w->GainPermStati(BLIND,NULL,SS_MISC);
    w->SightRange = 9;
    hpScan("3d_blind",w);
    w->RemoveStati(BLIND);
    w->SightRange = 9;
    HidePairsFor(w);
    w->GainPermStati(ASLEEP,NULL,SS_MISC);
    w->SightRange = 9;
    hpScan("3d_asleep",w);
    w->RemoveStati(ASLEEP);
    w->SightRange = 9;
    HidePairsFor(w);
    HidePairsFor(w2);
    p->PlaceAt(mp,hx,hy);
    HidePairsFor(w2);
    hpScan("3e",w);
    theGame->Turn += HIDE_ROUND_TICKS;
    hpScan("4",w);
    /* inc-yp23: create both notes through real scans; either verdict counts. */
    w->RemoveStati(HIDING);
    w->CalcValues();
    HidePairsFor(w);
    const bool beforeFar = w->HasStati(TRIED,HK_SPOT_RESULT,p);
    const bool beforeNear = w->HasStati(TRIED,HK_SPOT_RESULT,w2);
    int fx = -1, fy = -1;
    for (int y = 0; y < mp->SizeY() && fx == -1; ++y)
        for (int x = 0; x < mp->SizeX(); ++x)
            if (!mp->SolidAt(x,y) && !mp->FCreatureAt(x,y) &&
                !mp->FFeatureAt(x,y) && dist(w->x,w->y,x,y) > w->SightRange+5) {
                fx = x; fy = y; break;
            }
    if (fx == -1) { Error("HIDE_PAIRS INCONCLUSIVE no far square"); return; }
    p->PlaceAt(mp,fx,fy);
    Error("HIDE_PAIRS SETUP far_dist=%d near_dist=%d range=%d",dist(w->x,w->y,p->x,p->y),dist(w->x,w->y,w2->x,w2->y),w->SightRange);
    Error("HIDE_PAIRS BEGIN case=5");
    HideTurnStart(w);
    Error("HIDE_PAIRS END before_far=%d before_near=%d after_far=%d after_near=%d",
        beforeFar,beforeNear,w->HasStati(TRIED,HK_SPOT_RESULT,p),w->HasStati(TRIED,HK_SPOT_RESULT,w2));
    p->PlaceAt(mp,hx,hy);
    theGame->Turn = savedTurn;
    p->Options[OPT_AUTOMORE] = autoMore;
    theGame->PlayMode = playing;
    Error("HIDE_PAIRS COMPLETE");
}
