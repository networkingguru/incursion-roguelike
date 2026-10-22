/* inc-6qmk: opt-in oracle for exact-monster encounters. Off unless
   INCURSION_EXACTMON_PROBE is set. Called from Game::Play (src/Main.cpp);
   read by tools/check_exact_monster_depth.sh. It holds no rule: it calls
   Map::thEnGenMonXY the way the vrock staff calls thEnGenMonSummXY, and
   logs to <IncursionDirectory>logs/exactmon.log what appeared on the map.
   case=exact: "exact monster" naming a monster deeper than the map.
   case=ordinary: 60 single-monster encounters constrained by type
   (MA_UNDEAD), not by monster; enChooseMID's depth limit must still hold.
   Unconstrained encounters are NOT used: they reach deeper monsters by
   other paths, with or without the fix (drow, ghast seen on level 1). */
#include "Incursion.h"

static FILE *emLog;

static int16 countCreatures(Map *mp) {
    int16 n = 0, i; Thing *t;
    MapIterate(mp, t, i)
        if (t->isCreature() && t != (Thing*)theGame->GetPlayer(0))
            n++;
    return n;
}

/* Collect first, remove after: Remove edits the array MapIterate walks. */
static void clearCreatures(Map *mp) {
    Creature *list[512]; int n = 0, i; Thing *t;
    MapIterate(mp, t, i)
        if (t->isCreature() && t != (Thing*)theGame->GetPlayer(0) && n < 512)
            list[n++] = (Creature*)t;
    for (i = 0; i < n; i++)
        list[i]->Remove(true);
}

void ExactMonProbe(Player *pl) {
    if (!getenv("INCURSION_EXACTMON_PROBE")) return;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/exactmon.log",
        (const char*)T1->IncursionDirectory);
    emLog = fopen(path, "w");
    if (!emLog) return;
    if (!pl || !pl->m) {
        fprintf(emLog, "INCONCLUSIVE: no live player and map\nDONE\n");
        fclose(emLog); return;
    }
    Map *mp = pl->m;
    const rID encID = FIND("exact monster"), ghastID = FIND("ghast");
    if (!encID || !ghastID || RES(ghastID)->Type != T_TMONSTER) {
        fprintf(emLog, "INCONCLUSIVE: missing exact monster or ghast\nDONE\n");
        fclose(emLog); return;
    }
    int16 tx = -1, ty = -1;
    for (int d = 2; d <= 6 && tx < 0; ++d)
        for (int dx = -d; dx <= d && tx < 0; ++dx)
            for (int dy = -d; dy <= d && tx < 0; ++dy) {
                const int16 nx = pl->x + dx, ny = pl->y + dy;
                if (!mp->InBounds(nx, ny) || mp->SolidAt(nx, ny)) continue;
                if (mp->FCreatureAt(nx, ny)) continue;
                tx = nx; ty = ny;
            }
    if (tx < 0) {
        fprintf(emLog, "INCONCLUSIVE: no open floor\nDONE\n");
        fclose(emLog); return;
    }
    fprintf(emLog, "level depth=%d ghast_depth=%d\n", (int)mp->Depth,
        (int)TMON(ghastID)->Depth);

    /* case 1: one exact ghast, like thEnGenMonSummXY in the vrock staff. */
    int16 before = countCreatures(mp), i; Thing *t;
    mp->thEnGenMonXY(encID, ghastID, EN_SINGLE, 36, 0, tx, ty);
    int16 got = 0, ghasts = 0;
    MapIterate(mp, t, i)
        if (t->isCreature() && t != (Thing*)theGame->GetPlayer(0)) {
            got++;
            if (((Monster*)t)->mID == ghastID) ghasts++;
        }
    fprintf(emLog, "case=exact new=%d ghasts=%d\n", (int)(got - before),
        (int)ghasts);
    clearCreatures(mp);

    /* case 2: type-constrained encounters on the same level. */
    int made = 0, tooDeep = 0, maxDepth = 0;
    for (int k = 0; k < 60; k++) {
        mp->thEnGenMonXY(0, MA_UNDEAD, EN_SINGLE, (int8)(2 + (k % 10)), 0, tx, ty);
        MapIterate(mp, t, i)
            if (t->isCreature() && t != (Thing*)theGame->GetPlayer(0)) {
                const int dp = TMON(((Monster*)t)->mID)->Depth;
                made++;
                if (dp > maxDepth) maxDepth = dp;
                if (dp > mp->Depth) {
                    tooDeep++;
                    fprintf(emLog, "deep k=%d %s depth=%d\n", k,
                        NAME(((Monster*)t)->mID), dp);
                }
            }
        clearCreatures(mp);
    }
    fprintf(emLog, "case=ordinary made=%d too_deep=%d max_depth=%d\n",
        made, tooDeep, maxDepth);
    fprintf(emLog, "DONE\n");
    fclose(emLog);
}
