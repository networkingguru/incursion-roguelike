/* inc-pt7h: opt-in probe for the AD_STON petrification clock. Off unless
   INCURSION_STONING_DUR_PROBE is set. Called from Game::Play (src/Main.cpp);
   graded by tools/check_stoning_duration.sh. Output goes to errors.log through
   Error(), one STONING_DUR_PROBE line per fact. */
#include "Incursion.h"

static Monster *MakeKobold(Map *mp, rID id, Player *pl, int16 x, int16 y, bool foe) {
    mp->At(x, y).Lit = 1;
    Monster *mn = new Monster(id);
    TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    mn->PlaceAt(mp, x, y, true);
    mn->Initialize(true);
    mn->mHP = mn->cHP = 10000;
    if (foe) {
        mn->ts.addCreatureTarget(pl, TargetEnemy);
        pl->ts.addCreatureTarget(mn, TargetEnemy);
    }
    return mn;
}

void StoningDurProbe(Player *pl) {
    if (!getenv("INCURSION_STONING_DUR_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("STONING_DUR_PROBE: INCONCLUSIVE -- no live player and map");
        return;
    }
    const rID koboldID = FIND("kobold");
    if (!koboldID) {
        Error("STONING_DUR_PROBE: INCONCLUSIVE -- missing resource");
        return;
    }
    extern void LOFSetForcedSaveThrowRoll(int8 r);
    extern void LOFClearForcedSaveThrowRoll();

    static const int16 DX[4] = {1,-1,0,0}, DY[4] = {0,0,1,-1};
    Map *mp = pl->m;
    int dir = -1;
    for (int k = 0; k < 4 && dir < 0; ++k) {
        const int16 x = pl->x + DX[k], y = pl->y + DY[k];
        if (mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FCreatureAt(x, y))
            dir = k;
    }
    if (dir < 0) {
        Error("STONING_DUR_PROBE: INCONCLUSIVE -- no open square adjacent to the player");
        return;
    }

    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    Monster *kobold = MakeKobold(mp, koboldID, pl, pl->x + DX[dir], pl->y + DY[dir], true);

    kobold->RemoveStati(STONING);
    LOFSetForcedSaveThrowRoll(1);
    ThrowDmg(EV_DAMAGE, AD_STON, 3, "stoning probe", pl, kobold);
    LOFClearForcedSaveThrowRoll();
    const int stoning = kobold->HasStati(STONING) ? 1 : 0;
    const int dur = stoning ? kobold->GetStatiDur(STONING) : 0;
    const int cause = stoning ? kobold->GetStatiCause(STONING) : 0;
    Error("STONING_DUR_PROBE: stoning=%d dur=%d cause=%d want=dur 20 cause %d",
        stoning, dur, cause, (int)SS_ATTK);
    if (stoning == 1 && dur == 20 && cause == SS_ATTK)
        Error("STONING_DUR_PROBE: PASS");
    else
        Error("STONING_DUR_PROBE: FAIL -- see line above");

    kobold->Remove(true);
    theGame->PlayMode = wasInPlay;
}
