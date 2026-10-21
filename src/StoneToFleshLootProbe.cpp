/* inc-8rrt: prove the real random-potion generator can produce a potion of
   Stone to Flesh, and that the potion flavour table is not short. Caller:
   Game::Play (src/Main.cpp). Reader: tools/check_stone_to_flesh_loot.sh.
   It draws DungeonItems potion rows through Item::GenItem -- the same call the
   level generator makes (src/MakeLev.cpp:1348) -- at Depth 10 and Luck 10, the
   depth where a Level 6 potion effect is admitted: GenItem sets
   maxlev = max(3, Depth), and GetEffectID (src/Res.cpp:646) drops any effect
   whose LevelAdjust(Level,0,1) exceeds maxlev. Stone to Flesh is Level 6, so
   Depth 6 would already admit it; 10 leaves room and is reachable in the
   Goblin Caves (DUN_DEPTH 10). */
#include "Incursion.h"

/* inc-8rrt: one line per effect kind produced, then the STONE_FLESH_LOOT
   summary. hits counts potions whose effect is Stone to Flesh. Kinds are
   keyed by effect id, so a name that collides with another (or renders oddly)
   still counts once. */
void StoneToFleshLootProbe(Player *p) {
    if (!getenv("INCURSION_STONE_FLESH_LOOT_PROBE")) return;
    if (!p || !p->m) {
        Error("STONE_FLESH_LOOT INCONCLUSIVE no live map or player"); return;
    }
    rID want = FIND("stone to flesh");
    const int draws = 5000, level = 10;
    rID ids[512];
    int counts[512], kinds = 0, hits = 0, first_hit = 0;
    for (int i = 0; i < draws; i++) {
        Item *it = Item::GenItem(0, p->m->dID, (int16)level, 10, DungeonItems);
        if (!it) continue;
        if (it->isType(T_POTION) && it->eID) {
            int k;
            for (k = 0; k < kinds; k++)
                if (ids[k] == it->eID) break;
            if (k == kinds && kinds < 512) { ids[kinds] = it->eID; counts[kinds] = 0; kinds++; }
            if (k < kinds) {
                counts[k]++;
                if (want && it->eID == want) {
                    if (!hits) first_hit = i + 1;
                    hits++;
                }
            }
        }
        delete it;
    }
    for (int k = 0; k < kinds; k++)
        Error("STONE_FLESH_LOOT kind=%s count=%d", (const char*)NAME(ids[k]), counts[k]);
    Error("STONE_FLESH_LOOT draws=%d first_hit=%d hits=%d kinds=%d level=%d",
        draws, first_hit, hits, kinds, level);
}
