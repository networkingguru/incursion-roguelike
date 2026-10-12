/* inc-c36o: observe the low-HP morale branch of Monster::ChooseAction.
   Off unless INCURSION_LOWHP_FEAR_PROBE=<monster name> is set. With
   INCURSION_LOWHP_FEAR_PROBE_PIN=1 it holds that monster at 1/4 of its hit
   points. Writes logs/lowhp-fear.log. No morale rule lives here. */
#include "Incursion.h"

static FILE *LowHpFearLog()
{
    static FILE *log = NULL;
    if (!log) {
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/lowhp-fear.log",
            (const char*)T1->IncursionDirectory);
        log = fopen(path, "a");
    }
    return log;
}

/* phase 0: top of the morale check; 1: the flee branch fired. */
void LowHpFearProbe(Monster *m, int phase)
{
    const char *want = getenv("INCURSION_LOWHP_FEAR_PROBE");
    if (!want || strcmp((const char*)NAME(m->mID), want)) return;
    FILE *log = LowHpFearLog();
    if (!log) return;
    const int maxHP = m->mHP + m->Attr[A_THP];
    if (phase == 0 && getenv("INCURSION_LOWHP_FEAR_PROBE_PIN"))
        m->cHP = max(1, maxHP / 4);
    fprintf(log, "%s mon=%s cHP=%d maxHP=%d lowhp=%d psycho=%d mindless=%d "
        "fearRes=%d afraid=%d\n", phase ? "FLEE-BRANCH" : "ACT",
        (const char*)NAME(m->mID), (int)m->cHP, maxHP,
        (int)(m->cHP * 3 < maxHP), (int)m->HasMFlag(M_PSYCHO),
        (int)m->HasMFlag(M_MINDLESS), (int)m->ResistLevel(AD_FEAR),
        (int)m->HasStati(AFRAID));
    fflush(log);
}
