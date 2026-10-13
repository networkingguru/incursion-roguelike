/* inc-6w5x: observe Creature::RAttack when the line-of-fire code strikes a
   creature other than the aimed one. Off unless INCURSION_RANGED_ILLUSION_PROBE
   is set to aim-illusion | aim-real | control | loc-illusion.
   RangedIllusionProbe (called once from Main.cpp, needs a live player and map)
   places a cover creature at distance 2 and a target at distance 4 on a clear
   line, pins the band so the shot lands on the cover creature, and fires one
   dagger. RangedIllusionDamageProbe (Damage, before the disbelief test) logs
   which creature took the hit and the e.vicIllusion flag. Writes
   logs/ranged-illusion.log. No combat rule lives here. */
#include "Incursion.h"

extern void LOFSetForcedRoll(int8 r);
extern int8 LOFGetLastVHit();
extern void LOFSetForcedSave(int8 failAt);
extern void LOFClearForcedSave();

static FILE *RangedIllusionLog()
{
    static FILE *log = NULL;
    if (!log) {
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/ranged-illusion.log",
            (const char*)T1->IncursionDirectory);
        log = fopen(path, "a");
    }
    return log;
}

static Creature *riCover = NULL, *riTarget = NULL;
static bool riArmed = false;

void RangedIllusionDamageProbe(Creature *victim, bool vicIllusion)
{
    if (!riArmed || !victim || !getenv("INCURSION_RANGED_ILLUSION_PROBE"))
        return;
    FILE *log = RangedIllusionLog();
    if (!log) return;
    fprintf(log, "DAMAGE role=%s victimIsIllusion=%d vicIllusionFlag=%d\n",
        victim == riCover ? "cover" : victim == riTarget ? "target" : "other",
        (int)victim->HasStati(ILLUSION), (int)vicIllusion);
    fflush(log);
}

static Monster *RIPlace(Map *mp, int16 x, int16 y)
{
    mp->At(x,y).Lit = 1; /* keep the unlit wild-miss branch out of the way */
    Monster *mn = new Monster(FIND("giant rat"));
    TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    mn->PlaceAt(mp, x, y, true);
    mn->Initialize(true);
    mn->mHP = mn->cHP = 10000;
    return mn;
}

static void RIMakeIllusion(Creature *actor, Creature *c)
{
    /* As Encounter.cpp EN_ILLUSION does; eID Phantasmal Force reads yval 0. */
    c->GainPermStati(ILLUSION, actor, SS_ENCH, 15, 0,
        FIND("Phantasmal Force"), 5);
}

void RangedIllusionProbe(Player *shooter)
{
    const char *mode = getenv("INCURSION_RANGED_ILLUSION_PROBE");
    if (!mode || !*mode) return;
    FILE *log = RangedIllusionLog();
    if (!log || !shooter || !shooter->m) return;
    const rID dagID = FIND("dagger");
    Map *mp = shooter->m;
    const int16 px = shooter->x, py = shooter->y;
    static const int16 DX[4] = {1,-1,0,0}, DY[4] = {0,0,1,-1};
    int16 dx = 0, dy = 0;
    bool found = false;
    for (int dir = 0; dir < 4 && !found; dir++) {
        bool ok = true;
        for (int16 d = 1; d <= 4; d++) {
            int16 tx = px + DX[dir]*d, ty = py + DY[dir]*d;
            if (!mp->InBounds(tx,ty) || mp->SolidAt(tx,ty) ||
                mp->FCreatureAt(tx,ty)) { ok = false; break; }
        }
        if (ok && mp->LineOfFire(px, py, px+DX[dir]*4, py+DY[dir]*4, shooter)) {
            dx = DX[dir]; dy = DY[dir]; found = true;
        }
    }
    if (!found || !dagID) {
        fprintf(log, "NOSETUP no clear line or no dagger\n");
        fflush(log);
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;

    const bool loc = !strcmp(mode, "loc-illusion");
    Monster *cover = loc ? NULL : RIPlace(mp, px + dx*2, py + dy*2);
    Monster *target = RIPlace(mp, px + dx*4, py + dy*4);

    if (!loc && strcmp(mode, "control")) {
        /* Calibration shot, before any illusion exists: it leaves
           LOFGetLastVHit holding the real to-hit bonus. */
        LOFSetForcedRoll(10);
        Item *d0 = new Weapon(dagID, TITEM(dagID)->IType);
        Throw(EV_RATTACK, shooter, target, NULL, d0);
        cover->mHP = cover->cHP = 10000;
        target->mHP = target->cHP = 10000;
    }
    const int16 vHit = LOFGetLastVHit();
    int8 roll = 20;
    if (!loc && strcmp(mode, "control")) {
        /* Target defence D = vHit+roll-1, so total = D+1: a miss by
           arithmetic, band 0 = the cover creature's square (N = 1). */
        roll = 10;
        target->Attr[A_DEF] = (int8)(vHit + roll - 1);
        LOFSetForcedSave(1);
    }
    Creature *illus = !strcmp(mode, "aim-real") ? (Creature*)cover :
        (Creature*)target;
    if (strcmp(mode, "control"))
        RIMakeIllusion(shooter, illus);
    riCover = cover; riTarget = target;
    fprintf(log, "SETUP mode=%s vHit=%d roll=%d targetDef=%d coverIsIllusion=%d "
        "targetIsIllusion=%d\n", mode, (int)vHit, (int)roll,
        (int)target->Attr[A_DEF], cover ? (int)cover->HasStati(ILLUSION) : -1,
        (int)target->HasStati(ILLUSION));
    fflush(log);

    LOFSetForcedRoll(roll);
    if (!loc && strcmp(mode, "control"))
        target->Attr[A_DEF] = (int8)(vHit + roll - 1); /* re-pin */
    riArmed = true;
    Item *dag = new Weapon(dagID, TITEM(dagID)->IType);
    if (loc)
        ThrowXY(EV_RATTACK, target->x, target->y, shooter, NULL, NULL, dag);
    else
        Throw(EV_RATTACK, shooter, target, NULL, dag);
    riArmed = false;
    LOFClearForcedSave();
    LOFSetForcedRoll(0);
    fprintf(log, "SHOT returned coverHP=%d targetHP=%d\n",
        cover ? (int)cover->cHP : -1, (int)target->cHP);
    fflush(log);
    theGame->PlayMode = wasInPlay;
}
