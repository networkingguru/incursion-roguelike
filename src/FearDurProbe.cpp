/* inc-4hk3: opt-in probe for the AD_FEAR fear duration. Off unless
   INCURSION_FEAR_DUR_PROBE is set. Called from Game::Play (src/Main.cpp);
   graded by tools/check_fear_duration.sh. The fear lasts the amount converted
   from rounds to two-round units, with cause SS_ATTK and val FEAR_MAGIC.
   Output goes to errors.log through Error(), one FEAR_DUR_PROBE line per fact. */
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

void FearDurProbe(Player *pl) {
    if (!getenv("INCURSION_FEAR_DUR_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("FEAR_DUR_PROBE: INCONCLUSIVE -- no live player and map");
        return;
    }
    const rID koboldID = FIND("kobold");
    if (!koboldID) {
        Error("FEAR_DUR_PROBE: INCONCLUSIVE -- missing resource");
        return;
    }
    extern void LOFSetForcedSaveThrowRoll(int8 r);
    extern void LOFClearForcedSaveThrowRoll();

    /* One open floor square adjacent to the player, so the kobold can stand
       next to the caster and take the damage. */
    static const int16 DX[4] = {1,-1,0,0}, DY[4] = {0,0,1,-1};
    Map *mp = pl->m;
    int dir = -1;
    for (int k = 0; k < 4 && dir < 0; ++k) {
        const int16 x = pl->x + DX[k], y = pl->y + DY[k];
        if (mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FCreatureAt(x, y))
            dir = k;
    }
    if (dir < 0) {
        Error("FEAR_DUR_PROBE: INCONCLUSIVE -- no open square adjacent to the player");
        return;
    }

    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    Monster *kobold = MakeKobold(mp, koboldID, pl, pl->x + DX[dir], pl->y + DY[dir], true);

    static const int amounts[2] = {3, 9};
    bool pass = true;
    for (int i = 0; i < 2; ++i) {
        const int amount = amounts[i];
        kobold->RemoveStati(AFRAID);
        LOFSetForcedSaveThrowRoll(1);
        ThrowDmg(EV_DAMAGE, AD_FEAR, amount, "fear probe", pl, kobold);
        LOFClearForcedSaveThrowRoll();
        const int afraid = kobold->HasStati(AFRAID) ? 1 : 0;
        const int dur = afraid ? kobold->GetStatiDur(AFRAID) : 0;
        const int cause = afraid ? kobold->GetStatiCause(AFRAID) : 0;
        const int val = afraid ? kobold->GetStatiVal(AFRAID) : -1;
        int lo = amount / 2, hi = (amount + 1) / 2;
        if (lo < 1) lo = 1;
        if (hi < 1) hi = 1;
        if (lo > hi) { const int t = lo; lo = hi; hi = t; }
        Error("FEAR_DUR_PROBE: amount=%d afraid=%d dur=%d cause=%d val=%d want=%d..%d",
            amount, afraid, dur, cause, val, lo, hi);
        if (!(afraid == 1 && dur >= lo && dur <= hi && cause == SS_ATTK && val == FEAR_MAGIC))
            pass = false;
    }
    if (pass) Error("FEAR_DUR_PROBE: PASS");
    else Error("FEAR_DUR_PROBE: FAIL -- see amount lines above");

    kobold->Remove(true);
    theGame->PlayMode = wasInPlay;
}
