/* inc-n0ie: observe real template eligibility and alignment; off unless
   INCURSION_TEMPLATE_ALIGNMENT_PROBE is set. No eligibility rules live here. */
#include "Incursion.h"

struct TemplateCase { const char *monster; const char *tmpl; };

void TemplateAlignmentProbe(Player *pl)
{
    if (!getenv("INCURSION_TEMPLATE_ALIGNMENT_PROBE")) return;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/template-alignment.log",
        (const char*)T1->IncursionDirectory);
    FILE *log = fopen(path, "w");
    if (!log) return;

    static const TemplateCase cases[] = {
        { "sahuagin", "paladin;template" },
        { "kobold",   "zombie" },
        { "dwarf",    "vampire" },
        { "dwarf",    "paladin;template" },
        { "sahuagin", "blackguard;template" },
    };
    const int nCases = (int)(sizeof(cases)/sizeof(cases[0]));

    for (int i = 0; i < nCases; i++) {
        const rID monsterID = FIND(cases[i].monster);
        const rID templateID = FIND(cases[i].tmpl);
        if (!monsterID || !templateID ||
            RES(monsterID)->Type != T_TMONSTER ||
            RES(templateID)->Type != T_TTEMPLATE) {
            fprintf(log, "INCONCLUSIVE: missing resource %s or %s\n",
                cases[i].monster, cases[i].tmpl);
            fclose(log);
            return;
        }
        Monster *mn = new Monster(monsterID);
        mn->CalcValues();
        const bool accepted = mn->CanAddTemplate(templateID);
        if (accepted)
            mn->AddTemplate(templateID);
        fprintf(log,
            "case=%s+%s accepted=%d evil=%d good=%d lawful=%d chaotic=%d\n",
            cases[i].monster, cases[i].tmpl, (int)accepted,
            (int)mn->HasMFlag(M_EVIL), (int)mn->HasMFlag(M_GOOD),
            (int)mn->HasMFlag(M_LAWFUL), (int)mn->HasMFlag(M_CHAOTIC));
        delete mn;
    }
    fprintf(log, "DONE\n");
    fclose(log);
}
