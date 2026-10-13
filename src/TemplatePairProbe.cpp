/* inc-pp9w: drive the real template chooser (Map::enTemplateOk) for a human
   that already holds "death knight", then build the monster the way
   Map::enBuildMon does and report whether the chosen second template stuck.
   Off unless INCURSION_TEMPLATE_PAIR_PROBE is set. No eligibility rules here. */
#include "Incursion.h"

void TemplatePairProbe(Player *pl)
{
    if (!getenv("INCURSION_TEMPLATE_PAIR_PROBE")) return;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/template-pair.log",
        (const char*)T1->IncursionDirectory);
    FILE *log = fopen(path, "w");
    if (!log) return;

    const rID monID = FIND("human");
    const rID t1 = FIND("death knight");
    const rID t2 = FIND("shadowdancer;template");
    const rID encID = FIND("Vault Monster");
    if (!pl->m || !monID || !t1 || !t2 || !encID ||
        RES(monID)->Type != T_TMONSTER ||
        RES(t1)->Type != T_TTEMPLATE || RES(t2)->Type != T_TTEMPLATE ||
        RES(encID)->Type != T_TENCOUNTER) {
        fprintf(log, "INCONCLUSIVE: missing map or resource\n");
        fclose(log);
        return;
    }

    EventInfo e;
    e.Clear();
    e.enID = encID;
    e.ep_mID = monID;
    e.eimXCR = 1000000;
    pl->m->enCalcCurrPartXCR(e);
    const bool ok1 = pl->m->enTemplateOk(e, t1);
    pl->m->enAddTemp(e, t1);
    const bool ok2 = pl->m->enTemplateOk(e, t2);

    Monster *mn = new Monster(monID);
    mn->CalcValues();
    mn->AddTemplate(t1);
    mn->CalcValues();
    mn->AddTemplate(t2);
    const bool stuck2 = mn->HasEffStati(TEMPLATE, t2);
    delete mn;

    fprintf(log, "pair=human+death knight+shadowdancer;template "
        "chooser_first=%d chooser_second=%d built_second=%d\n",
        (int)ok1, (int)ok2, (int)stuck2);
    fprintf(log, "DONE\n");
    fclose(log);
}
