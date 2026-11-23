/* inc-n3eni: opt-in oracle for "a creature holds at most one WAS_FRIENDLY per
   attacker", enabled by INCURSION_WAS_FRIENDLY_PROBE=1. Stages a victim whose
   32 target slots hold priority-30 enemies, so TargetSystem::addTarget refuses
   the attacker, then calls ItHitMe 20 times. Prints one WAS_FRIENDLY_PROBE
   line to logs/errors.log. See tools/check_was_friendly_once.sh. */
#define protected public
#include "Incursion.h"
#undef protected

/* Place a no-gear monster on the nearest free floor square to the player.
   NULL when none is free within 4 squares. */
static Monster *wfMake(Player *pl, rID mID) {
    Map *m = pl->m;
    for (int r = 1; r <= 4; r++)
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

void WasFriendlyProbe(Player *pl) {
    if (!getenv("INCURSION_WAS_FRIENDLY_PROBE")) return;
    rID kob = FIND("kobold");
    if (!pl || !pl->m || !kob) {
        Error("WAS_FRIENDLY_PROBE: setup INCONCLUSIVE missing player/map/resource");
        return;
    }
    Monster *victim = wfMake(pl,kob), *attacker = wfMake(pl,kob),
            *filler = wfMake(pl,kob);
    if (!victim || !attacker || !filler) {
        Error("WAS_FRIENDLY_PROBE: setup INCONCLUSIVE no free squares");
        return;
    }
    /* The attacker is neutral to everyone, so the victim is neither hostile
       nor allied to it and ItHitMe reaches the WAS_FRIENDLY grant. */
    attacker->GainPermStati(NEUTRAL_TO,NULL,SS_MISC,-1);

    TargetSystem &ts = victim->ts;
    for (int i = 0; i < NUM_TARGETS; i++) {
        Target f = {};
        f.type = TargetEnemy;
        f.priority = 30;
        f.why.Set(TargetDefault);
        f.data.Creature.c = filler->myHandle;
        ts.t[i] = f;
    }
    ts.tCount = NUM_TARGETS;

    /* A priority-20 target must be refused by the full table (a refused
       addTarget changes nothing). */
    Target probeT = {};
    probeT.type = TargetEnemy;
    probeT.priority = 20;
    probeT.why.Set(TargetHitMe);
    probeT.data.Creature.c = attacker->myHandle;
    const bool addFail = !ts.addTarget(probeT);

    for (int i = 0; i < 20; i++)
        ts.ItHitMe(victim,attacker,1);

    int count = 0;
    StatiIterNature(victim,WAS_FRIENDLY)
        if (S->h == attacker->myHandle) count++;
    StatiIterEnd(victim)
    const bool recorded = ts.GetTarget(attacker) != NULL;
    Error("WAS_FRIENDLY_PROBE count=%d tcount=%d addfail=%s recorded=%s",
          count,(int)ts.tCount,addFail ? "yes" : "no",recorded ? "yes" : "no");
}
