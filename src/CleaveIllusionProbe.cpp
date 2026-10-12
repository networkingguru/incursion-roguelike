/* inc-k0e1: observe Creature::WAttack when Cleave carries on from a killed
   illusion. Off unless INCURSION_CLEAVE_ILLUSION_PROBE=illusion|real is set.
   Phase 0 (top of the attack, once): gives the player the Cleave feat, holds
   the first victim at 1 hit point and, in "illusion" mode, gives it ILLUSION
   stati as Encounter.cpp EN_ILLUSION does (eID = Phantasmal Force, so
   getIllusionFlags reads yval 0). Phase 1 (just before goto DoCleave): logs
   the cleave. Phase 2 (Damage, before the disbelief test): logs the victim. Writes logs/cleave-illusion.log. No combat rule lives here. */
#include "Incursion.h"

static FILE *CleaveIllusionLog()
{
    static FILE *log = NULL;
    if (!log) {
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/cleave-illusion.log",
            (const char*)T1->IncursionDirectory);
        log = fopen(path, "a");
    }
    return log;
}

/* vicIllusion is e.vicIllusion at the call (phase 1 only). */
void CleaveIllusionProbe(Creature *actor, Creature *victim, int phase,
    bool vicIllusion)
{
    const char *mode = getenv("INCURSION_CLEAVE_ILLUSION_PROBE");
    if (!mode || !actor || !victim || !actor->isPlayer()) return;
    if (!victim->isCreature()) return;
    FILE *log = CleaveIllusionLog();
    if (!log) return;
    static bool armed = false;
    if (phase == 0) {
        if (armed) return;
        armed = true;
        if (!actor->HasFeat(FT_CLEAVE))
            actor->GainPermStati(EXTRA_FEAT, NULL, SS_MISC, FT_CLEAVE);
        victim->cHP = 1;
        if (!strcmp(mode, "illusion"))
            victim->GainPermStati(ILLUSION, actor, SS_ENCH, 15, 0,
                FIND("Phantasmal Force"), 5);
        /* A real hostile bugbear on a free square beside the player. */
        Monster *mn = NULL;
        Map *mp = actor->m;
        for (int dx = -1; mp && !mn && dx <= 1; dx++)
            for (int dy = -1; !mn && dy <= 1; dy++) {
                int xx = actor->x + dx, yy = actor->y + dy;
                if ((!dx && !dy) || !mp->InBounds(xx, yy)) continue;
                if (mp->SolidAt(xx, yy) || mp->FCreatureAt(xx, yy)) continue;
                mn = new Monster(FIND("bugbear"));
                TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
                TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
                mn->PlaceAt(mp, xx, yy);
                mn->Initialize(true);
            }
        fprintf(log, "SETUP mode=%s cleave=%d first=%s isIllusion=%d cHP=%d\n",
            mode, (int)actor->HasFeat(FT_CLEAVE),
            (const char*)victim->Name(0), (int)victim->HasStati(ILLUSION),
            (int)victim->cHP);
    } else if (phase == 2) {
        if (!armed) return;
        fprintf(log, "DAMAGE victim=%s victimIsIllusion=%d vicIllusionFlag=%d\n",
            (const char*)victim->Name(0), (int)victim->HasStati(ILLUSION),
            (int)vicIllusion);
    } else {
        fprintf(log, "CLEAVE next=%s nextIsIllusion=%d vicIllusionFlag=%d\n",
            (const char*)victim->Name(0), (int)victim->HasStati(ILLUSION),
            (int)vicIllusion);
    }
    fflush(log);
}
