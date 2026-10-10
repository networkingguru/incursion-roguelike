/* inc-u3dp: ChooseAction drives the real turn hook; placement only changes
   the scene. No probe call rolls or updates a hide result. */
#include "Incursion.h"
#include "HideCheck.h"

#define HP_ROUNDS 60
#define HP_MOVES  60

static bool hpLine(Map *mp, int px, int py, int need, int *rx, int *ry) {
    static const int DX[4] = {1,-1,0,0}, DY[4] = {0,0,1,-1};
    for (int dir = 0; dir < 4; dir++)
        for (int d = 1; d <= need; d++) {
            const int tx = px + DX[dir]*d, ty = py + DY[dir]*d;
            if (!mp->InBounds(tx,ty) || mp->OpaqueAt(tx,ty)) break;
            if (d == need) {
                if (mp->SolidAt(tx,ty) || mp->FCreatureAt(tx,ty)) break;
                *rx = tx; *ry = ty;
                return true;
            }
        }
    return false;
}

static int hpAsk(Creature *obs, Player *pl) {
    return (obs->Perceives(pl) & PER_VISUAL) ? 1 : 0;
}

void HideProbe(Player *pl) {
    if (!getenv("INCURSION_HIDE_PROBE")) return;
    if (!pl || !pl->m) {
        Error("HIDE_PROBE INCONCLUSIVE no live player and map");
        return;
    }
    const rID ratID = FIND("giant rat");
    if (!ratID) { Error("HIDE_PROBE INCONCLUSIVE no giant rat"); return; }
    Map *mp = pl->m;
    int ox, oy, fx, fy;
    if (!hpLine(mp, pl->x, pl->y, 4, &ox, &oy)) {
        Error("HIDE_PROBE INCONCLUSIVE no open line to place the rat");
        return;
    }
    /* a free square far from the rat: the hider's way out of sight */
    fx = fy = -1;
    for (int yy = 0; yy < mp->SizeY() && fx < 0; yy++)
        for (int xx = 0; xx < mp->SizeX(); xx++)
            if (dist(pl->x,pl->y,xx,yy) >= 25 && !mp->SolidAt(xx,yy) &&
                !mp->FCreatureAt(xx,yy)) { fx = xx; fy = yy; break; }
    if (fx < 0) { Error("HIDE_PROBE INCONCLUSIVE no far square"); return; }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    Monster *rat = new Monster(ratID);
    TMON(rat->tmID)->GrantGear(rat, rat->tmID, true);
    TMON(rat->tmID)->PEvent(EV_BIRTH, rat, rat->tmID);
    rat->PlaceAt(mp, ox, oy);
    rat->Initialize(true);
    rat->RemoveStati(SLEEPING);
    rat->RemoveStati(ASLEEP);
    const bool wasLit = mp->At(pl->x,pl->y).Lit;
    mp->At(pl->x,pl->y).Lit = 1;
    pl->CalcVision();

    // The normal stand-still order prevents walking without disabling actions.
    rat->ts.giveOrder(rat, NULL, OrderStandStill);
    const int gap = pl->SkillLevel(SK_HIDE) + HiderModifiers(pl)
                  - rat->SkillLevel(SK_SPOT) - SpotModifiers(rat, pl);
    rat->GainPermStati(SKILL_BONUS, NULL, SS_MISC, SK_SPOT, gap);
    const int watcher = rat->SkillLevel(SK_SPOT) + SpotModifiers(rat, pl);
    const int hider = pl->SkillLevel(SK_HIDE) + HiderModifiers(pl);
    Error("HIDE_PROBE setup hide=%d spot=%d hostile=%d control_unhidden=%d",
        hider, watcher, (int)rat->isHostileTo(pl), hpAsk(rat, pl));
    if (watcher != hider || !HideCanWatch(rat, pl)) {
        Error("HIDE_PROBE INCONCLUSIVE pair is not tied and in sight");
    } else {
        pl->GainPermStati(HIDING, NULL, SS_CLAS, HI_SHADOWS, 1);
        const uint32 savedTurn = theGame->Turn;
        for (int k = 0; k < HP_ROUNDS + 2 * HP_MOVES; k++) {
            const bool still = k < HP_ROUNDS;
            const bool away = !still && ((k - HP_ROUNDS) % 2 == 0);
            if (!still) rat->PlaceAt(mp, away ? fx : ox, away ? fy : oy);
            const int ax = rat->x, ay = rat->y;
            const bool canWatch = HideCanWatch(rat, pl);
            rat->Timeout = 0;
            rat->ChooseAction();
            if (rat->x != ax || rat->y != ay || rat->Timeout <= 0 ||
                !pl->HasStati(HIDING) || canWatch == away) {
                Error("HIDE_PROBE INCONCLUSIVE action/line-of-sight setup changed");
                break;
            }
            theGame->Turn += rat->Timeout;
            Error("HIDE_PROBE phase=%s round=%d current=%d spotted=%d perceived=%d",
                still ? "still" : away ? "away" : "moves",
                still ? k : (k - HP_ROUNDS) / 2,
                (int)HasCurrentResult(rat, pl), (int)IsSpotted(rat, pl), hpAsk(rat, pl));
        }
        theGame->Turn = savedTurn;
    }
    pl->RemoveStati(HIDING);
    mp->At(pl->x,pl->y).Lit = wasLit;
    rat->Remove(true);
    pl->CalcVision();
    theGame->PlayMode = wasInPlay;
    Error("HIDE_PROBE COMPLETE");
}
