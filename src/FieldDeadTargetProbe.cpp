/* inc-8vxk6: opt-in oracle for "a spell whose creature target dies in the
   caster's attack of opportunity does not run", enabled by
   INCURSION_FIELD_DEAD_TARGET_PROBE=1. A kobold invokes Call Light at a second
   kobold through EV_INVOKE; FieldDeadTargetKill, called right after
   ProvokeAoO in Creature::Invoke, kills the target there. Counts entries into
   Magic::AField and the fields on the map. Prints one FIELD_DEAD_TARGET_PROBE
   line to logs/errors.log. See tools/check_field_dead_target.sh. */
#define protected public
#include "Incursion.h"
#undef protected

static bool fdtArmed = false;   /* the next hook call kills the target */
static bool fdtKilled = false;
static int fdtAlive = -1;       /* target alive when the hook ran */
static int fdtDead = -1;        /* target dead after the hook */
static int fdtAField = 0;
static int fdtHook = 0;

void FieldDeadTargetEnter() {
    if (fdtArmed || fdtKilled) fdtAField++;
}

void FieldDeadTargetKill(EventInfo &e) {
    if (!fdtArmed) return;
    fdtArmed = false;
    fdtHook++;
    Creature *t = e.EVictim;
    if (!t) return;
    fdtAlive = !t->isDead() && t->m && t->x != -1;
    ThrowDmg(EV_DAMAGE, AD_BLUNT, 10000, "dead target probe", e.EActor, t);
    fdtDead = t->isDead() || !t->m || t->x == -1;
    fdtKilled = true;
}

static Monster *fdtMake(Player *pl, rID mID, int minR) {
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

static int fdtFields(Map *m) {
    int i = 0;
    while (m->Fields[i]) i++;
    return i;
}

void FieldDeadTargetProbe(Player *pl) {
    /* inc-8vxk6: off unless INCURSION_FIELD_DEAD_TARGET_PROBE is set. */
    if (!getenv("INCURSION_FIELD_DEAD_TARGET_PROBE")) return;
    rID kob = FIND("kobold"), light = FIND("Call Light");
    if (!pl || !pl->m || !kob || !light) {
        Error("FIELD_DEAD_TARGET_PROBE: setup INCONCLUSIVE missing player/map/resource");
        return;
    }
    Map *m = pl->m;
    Monster *caster = fdtMake(pl,kob,1), *target = fdtMake(pl,kob,2);
    if (!caster || !target) {
        Error("FIELD_DEAD_TARGET_PROBE: setup INCONCLUSIVE no free squares");
        return;
    }
    caster->mMana = 100;
    caster->uMana = caster->hMana = 0;
    const int before = fdtFields(m);
    fdtArmed = true;
    EvReturn r = ThrowEff(EV_INVOKE,light,caster,target);
    const int after = fdtFields(m);
    Error("FIELD_DEAD_TARGET_PROBE hook=%d alive=%d dead=%d afield=%d fieldsbefore=%d fieldsafter=%d ret=%d",
          fdtHook,fdtAlive,fdtDead,fdtAField,before,after,(int)r);
}
