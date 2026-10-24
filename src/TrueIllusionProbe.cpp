/* inc-yam9: test-only setup for tools/check_true_illusions.sh. Off unless
   INCURSION_TRUE_ILLUSION_PROBE=r3|r4 is set; called once from Main.cpp at the
   start of Game::Play, like RangedIllusionProbe. Writes logs/true-illusion.log.
   r3: a rat two squares away becomes an illusion of the spell named by
       INCURSION_TRUE_ILLUSION_SPELL; the player throws a dagger at it (the
       attack roll comes from INCURSION_LOF_FORCE_ROLL) and
       the hit lands in Creature::Damage.
   r4: a goblin beside the player becomes an illusion of that spell and strikes
       a real kobold standing next to it. The kobold has 3 hit points, so the
       illusion's damage makes it collapse, which is Creature::PDamage.
   No combat rule lives here. */
#include "Incursion.h"

static FILE *TIL()
{
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/true-illusion.log",
        (const char*)T1->IncursionDirectory);
    return fopen(path, "a");
}

static Monster *TIPlace(Map *mp, const char *name, int16 x, int16 y)
{
    mp->At(x,y).Lit = 1;
    Monster *mn = new Monster(FIND(name));
    TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    mn->PlaceAt(mp, x, y, true);
    mn->Initialize(true);
    return mn;
}

void TrueIllusionProbe(Player *pl)
{
    const char *mode = getenv("INCURSION_TRUE_ILLUSION_PROBE");
    const char *spell = getenv("INCURSION_TRUE_ILLUSION_SPELL");
    if (!mode || !*mode || !spell || !*spell) return;
    FILE *log = TIL();
    if (!log || !pl || !pl->m) return;
    Map *mp = pl->m;
    const int16 px = pl->x, py = pl->y;
    static const int16 DX[4] = {1,-1,0,0}, DY[4] = {0,0,1,-1};
    int16 dx = 0, dy = 0;
    bool found = false;
    for (int dir = 0; dir < 4 && !found; dir++) {
        bool ok = true;
        for (int16 d = 1; d <= 3; d++) {
            int16 tx = px + DX[dir]*d, ty = py + DY[dir]*d;
            if (!mp->InBounds(tx,ty) || mp->SolidAt(tx,ty) ||
                mp->FCreatureAt(tx,ty)) { ok = false; break; }
        }
        if (ok && mp->LineOfFire(px, py, px+DX[dir]*3, py+DY[dir]*3, pl)) {
            dx = DX[dir]; dy = DY[dir]; found = true;
        }
    }
    rID eID = FIND(spell);
    if (!found || !eID) {
        fprintf(log, "NOSETUP found=%d spell=%s eID=%d\n", (int)found, spell, (int)eID);
        fclose(log);
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    fprintf(log, "SETUP mode=%s player=%s spell=%s flags=%d\n", mode,
        (const char*)pl->Name(), spell, (int)TEFF(eID)->ef.yval);
    fflush(log);
    if (!strcmp(mode, "r3")) {
        const rID dagID = FIND("dagger");
        Monster *target = TIPlace(mp, "giant rat", px + dx*2, py + dy*2);
        target->mHP = target->cHP = 10000;
        target->GainPermStati(ILLUSION, pl, SS_ENCH, 15, 0, eID, 5);
        Item *dag = new Weapon(dagID, TITEM(dagID)->IType);
        Throw(EV_RATTACK, pl, target, NULL, dag);
        fprintf(log, "SHOT targetIsIllusion=%d targetHP=%d\n",
            (int)target->HasStati(ILLUSION), (int)target->cHP);
    } else if (!strcmp(mode, "r4")) {
        Monster *attacker = TIPlace(mp, "goblin", px + dx*1, py + dy*1);
        Monster *victim = TIPlace(mp, "kobold", px + dx*2, py + dy*2);
        attacker->GainPermStati(ILLUSION, pl, SS_ENCH, 15, 0, eID, 5);
        victim->cHP = 3;
        Throw(EV_WATTACK, attacker, victim);
        fprintf(log, "STRIKE victimAsleep=%d victimHP=%d attackerIsIllusion=%d\n",
            (int)victim->HasStati(ASLEEP), (int)victim->cHP,
            (int)attacker->HasStati(ILLUSION));
    }
    fclose(log);
    theGame->PlayMode = wasInPlay;
}
