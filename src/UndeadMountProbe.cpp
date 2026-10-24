/* inc-u1xj: drive Map::enUndeadMount for an undead rider on two mounts, then
   build each mount as Map::enBuildMon does and report whether the chosen
   template stuck. Off unless INCURSION_UNDEAD_MOUNT_PROBE is set. */
#include "Incursion.h"

static void UndeadMountCase(Player *pl, FILE *log, const char *name,
    rID mountID, rID riderID, rID zombieID, rID encID)
{
    EventInfo e;
    e.Clear();
    e.enID = encID;
    e.ep_mID = riderID;
    e.eimXCR = 1000000;
    pl->m->enCalcCurrPartXCR(e);
    pl->m->enAddTemp(e, zombieID);
    e.ep_hmID = mountID;
    pl->m->enUndeadMount(e);

    /* Build the mount as enBuildMon does: CalcValues before each AddTemplate. */
    const bool kept = e.ep_hmID != 0;
    const rID chosen = e.ep_htID;
    bool built = true;
    Monster *mt = new Monster(mountID);
    if (chosen && chosen > 0x01000000) {
        mt->CalcValues();
        mt->AddTemplate(chosen);
        built = mt->HasEffStati(TEMPLATE, chosen);
    }
    delete mt;

    const char *tname = "none";
    if (chosen)
        tname = XPrint("<Res>", chosen);
    fprintf(log, "mount=%s kept=%d htID=%s built=%d\n", name, (int)kept,
        tname, (int)built);
}

void UndeadMountProbe(Player *pl)
{
    if (!getenv("INCURSION_UNDEAD_MOUNT_PROBE")) return;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/undead-mount.log",
        (const char*)T1->IncursionDirectory);
    FILE *log = fopen(path, "w");
    if (!log) return;

    const rID riderID = FIND("goblin");
    const rID zombieID = FIND("zombie");
    const rID spiderID = FIND("giant spider");
    const rID ponyID = FIND("pony");
    const rID encID = FIND("Vault Monster");
    if (!pl->m || !riderID || !zombieID || !spiderID || !ponyID || !encID ||
        RES(riderID)->Type != T_TMONSTER || RES(spiderID)->Type != T_TMONSTER ||
        RES(ponyID)->Type != T_TMONSTER || RES(zombieID)->Type != T_TTEMPLATE ||
        RES(encID)->Type != T_TENCOUNTER) {
        fprintf(log, "INCONCLUSIVE: missing map or resource\n");
        fclose(log);
        return;
    }

    UndeadMountCase(pl, log, "giant spider", spiderID, riderID, zombieID, encID);
    UndeadMountCase(pl, log, "pony", ponyID, riderID, zombieID, encID);
    fprintf(log, "DONE\n");
    fclose(log);
}
