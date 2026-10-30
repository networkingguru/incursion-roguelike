/* inc-946vn: opt-in KillXP loop scene, off unless INCURSION_KILLXP_PROBE is
   set. Builds its own creatures from fixed resource names, rolls no dice, and
   logs to logs/killxp-loop.log. See tools/check_killxp_loop.sh. */
#include "Incursion.h"

static const int MaxSeen = 8;
static hObj SeenH[MaxSeen];
static int SeenN[MaxSeen];
static int SeenCount = 0, Depth = 0;
static bool Active = false;
static FILE *Log = NULL;

/* Called from Creature::KillXP on entry (enter=true) and exit (false). */
void KillXPProbe(Creature *me, Creature *kill, bool enter)
{
    int i;
    if (!Active) return;
    if (!enter) { Depth--; return; }
    for (i = 0; i < SeenCount; i++)
        if (SeenH[i] == me->myHandle) break;
    if (i == SeenCount && SeenCount < MaxSeen) {
        SeenH[SeenCount] = me->myHandle;
        SeenN[SeenCount++] = 0;
    }
    if (i < SeenCount)
        SeenN[i]++;
    if (++Depth > 20) {
        fprintf(Log, "RECURSION depth>20\n");
        fclose(Log);
        abort();
    }
}

static int CallsTo(Creature *c)
{
    for (int i = 0; i < SeenCount; i++)
        if (SeenH[i] == c->myHandle) return SeenN[i];
    return 0;
}

/* back: A holds a DIPLOMACY_TAG whose source is B (the loop edge). */
static void Scene(Player *pl, const char *name, bool back)
{
    Monster *A = new Monster(FIND("kobold"));
    Monster *B = new Monster(FIND("kobold"));
    Monster *C = new Monster(FIND("goblin"));
    A->CalcValues(); B->CalcValues(); C->CalcValues();
    B->ts.addCreatureTarget(A, TargetLeader);
    A->GainPermStati(DIPLOMACY_TAG, pl, SS_MISC);
    if (back)
        A->GainPermStati(DIPLOMACY_TAG, B, SS_MISC);

    SeenCount = 0; Depth = 0; Active = true;
    uint32 before = pl->GetXP();
    B->KillXP(C, 100);
    Active = false;
    fprintf(Log, "scene=%s returned=1 gain=%ld callsA=%d callsB=%d\n", name,
        (long)((int32)pl->GetXP() - (int32)before), CallsTo(A), CallsTo(B));
    delete A; delete B; delete C;
}

/* inc-946vn: the scene behind tools/check_killxp_loop.sh. */
void KillXPLoopProbe(Player *pl)
{
    if (!getenv("INCURSION_KILLXP_PROBE")) return;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/killxp-loop.log",
        (const char*)T1->IncursionDirectory);
    Log = fopen(path, "w");
    if (!Log) return;
    setvbuf(Log, NULL, _IONBF, 0);

    /* direct: the player is credited with a kill at 100 percent. */
    Monster *C = new Monster(FIND("goblin"));
    C->CalcValues();
    uint32 before = pl->GetXP();
    pl->KillXP(C, 100);
    fprintf(Log, "scene=direct gain=%ld\n", (long)((int32)pl->GetXP() - (int32)before));
    delete C;

    Scene(pl, "control", false);
    Scene(pl, "loop", true);
    fprintf(Log, "DONE\n");
    fclose(Log);
    Log = NULL;
}
