/* inc-qt2c: sample the real generator; the independent oracle never reads
   effect flags. build_macos.sh registers this through src/*.cpp. */
#include "Incursion.h"

static bool PlusScaled(int q, bool armour) {
    if (!armour) return q == WQ_DEFENDING;
    switch (q) {
        case AQ_MIGHT: case AQ_AGILITY: case AQ_ENDURANCE:
        case AQ_SHADOW: case AQ_SILENT: case AQ_SLICK:
        case AQ_MAGIC_RES: case AQ_RESISTANT: case AQ_AUSPICIOUS:
        case AQ_HEALING: case AQ_FIRE_RES: case AQ_ACID_RES:
        case AQ_COLD_RES: case AQ_LIGHT_RES: case AQ_SONIC_RES:
        case AQ_POISON_RES: case AQ_COMMAND: case AQ_LIFEKEEPING:
            return true;
        default: return false;
    }
}

void QualityPlusProbe(Player *p) {
    const char *enabled = getenv("INCURSION_QUALITY_PLUS_PROBE");
    if (!enabled || strcmp(enabled, "1")) return;
    if (!p || !p->m) {
        Error("QUALITY_PLUS INCONCLUSIVE no live player or map");
        return;
    }
    const unsigned seeds[] = {1, 17, 101, 2026};
    const int types[] = {T_ARMOUR, T_SHIELD, T_WEAPON, T_BOW, T_MISSILE};
    const char *names[] = {"armor", "shield", "weapon"};
    struct Counts { int items, any, scaled, bad, positive, negative; } counts[3] = {};
    int printed = 0, skipped = 0;
    for (unsigned s = 0; s < sizeof(seeds)/sizeof(seeds[0]); ++s) {
        srand(seeds[s]);
        for (int depth = 1; depth <= 10; ++depth)
            for (int kind = 0; kind < 5; ++kind) {
                ItemGen gen[2] = {};
                for (int row = 0; DungeonItems[row].Prob; ++row)
                    if (DungeonItems[row].Type == types[kind]) {
                        gen[0] = DungeonItems[row]; break;
                    }
                if (!gen[0].Prob) {
                    Error("QUALITY_PLUS INCONCLUSIVE missing generation row type=%d", types[kind]);
                    return;
                }
                for (int draw = 0; draw < 1000; ++draw) {
                    // This loop does not draw frames, which normally purge temporaries.
                    if (draw % 100 == 0) PurgeStrings();
                    Item *it = Item::GenItem(0, p->m->dID, depth, 10, gen);
                    if (!it) { ++skipped; continue; }
                    int category = it->isType(T_ARMOUR) ? 0 :
                        it->isType(T_SHIELD) ? 1 :
                        (it->isType(T_WEAPON) || it->isType(T_BOW) ||
                         it->isType(T_MISSILE)) ? 2 : -1;
                    if (category < 0) {
                        if (!skipped)
                            Error("QUALITY_PLUS skipped name=%s type=%d",
                                (const char*)Decolorize(it->Name(NA_IDENT)), (int)it->Type);
                        ++skipped;
                        delete it;
                        continue;
                    }
                    Counts &c = counts[category];
                    bool any = false, scaled = false;
                    String qualities;
                    for (int q = 1; q <= WQ_TRUELAST; ++q) {
                        if (!it->HasQuality(q)) continue;
                        any = true;
                        scaled |= PlusScaled(q, category < 2);
                        if (qualities.GetLength()) qualities += ",";
                        qualities += Format("%d", q);
                    }
                    int plus = it->GetPlus();
                    ++c.items;
                    c.any += any;
                    c.scaled += scaled;
                    c.positive += scaled && plus >= 1;
                    c.negative += scaled && plus < 0;
                    c.bad += scaled && plus == 0;
                    if (scaled && plus == 0 && printed < 20) {
                        String name = Decolorize(it->Name(NA_IDENT));
                        Error("QUALITY_PLUS offender category=%s seed=%u depth=%d name=%s qualities=%s plus=%d",
                            names[category], seeds[s], depth, (const char*)name,
                            (const char*)qualities, plus);
                        ++printed;
                    }
                    delete it;
                }
            }
    }
    Error("QUALITY_PLUS sampling seeds=1,17,101,2026 depths=1-10 attempts=200000 skipped=%d", skipped);
    int positive = 0, any = 0;
    for (int k = 0; k < 3; ++k) {
        Counts &c = counts[k];
        Error("QUALITY_PLUS summary category=%s items=%d any=%d scaled=%d zero=%d negative=%d",
            names[k], c.items, c.any, c.scaled, c.bad, c.negative);
        positive += c.positive;
        any += c.any;
    }
    Error("QUALITY_PLUS control positive_scaled=%d any=%d", positive, any);
    Error("QUALITY_PLUS done");
}
