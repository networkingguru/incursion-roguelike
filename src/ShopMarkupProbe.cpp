/* inc-nel5: Roark's asking price at every Diplomacy index. Off unless
   INCURSION_SHOP_MARKUP_PROBE is set; called from Game::Play (src/Main.cpp).
   Reader: tools/check_shop_markup.sh. Lines go through Error():
   "SHOP_MARKUP_PROBE item=<label> index=<i|natural> list=<n> ask=<n>". */
#include "Incursion.h"

extern int32 ShopIndexOverride; /* src/Social.cpp, the probe hook */

static Item *mk(const char *label, const char *base, const char *eff, int plus) {
    rID bID = FIND(base);
    Item *it = bID ? Item::Create(bID) : NULL;
    if (!it) {
        Error("SHOP_MARKUP_PROBE INCONCLUSIVE no item %s", base);
        return NULL;
    }
    if (eff) {
        rID eID = FIND(eff);
        if (!eID) {
            Error("SHOP_MARKUP_PROBE INCONCLUSIVE no effect %s", eff);
            delete it;
            return NULL;
        }
        it->MakeMagical(eID);
    }
    if (plus) it->SetInherentPlus(plus);
    it->SetQuantity(1);
    (void)label;
    return it;
}

void ShopMarkupProbe(Player *p) {
    const char *s = getenv("INCURSION_SHOP_MARKUP_PROBE");
    if (!s || !*s) return;
    if (!p) {
        Error("SHOP_MARKUP_PROBE INCONCLUSIVE no player");
        return;
    }
    rID roarkID = FIND("Roark Ironbeard");
    if (!roarkID) {
        Error("SHOP_MARKUP_PROBE INCONCLUSIVE no Roark");
        return;
    }
    Creature *roark = InitShopkeeper(roarkID, 100000);

    struct { const char *label, *base, *eff; int plus; } C[] = {
        { "dagger",        "dagger",     NULL,           0 },
        { "long_sword+1",  "long sword", NULL,           1 },
        { "scroll_identify","scroll",    "Identify;scroll", 0 },
        { "potion_true_healing","potion","True-Healing", 0 },
        { "ring_mail+5",   "ring mail",  NULL,           5 },
    };
    int natural = p->SkillLevel(SK_DIPLOMACY) + p->getSocialMod(roark, false);
    natural = max(natural, -10);
    natural = min(natural, +30);
    Error("SHOP_MARKUP_PROBE natural index=%d", natural);

    for (size_t c = 0; c < sizeof(C) / sizeof(C[0]); c++) {
        Item *it = mk(C[c].label, C[c].base, C[c].eff, C[c].plus);
        if (!it) continue;
        int32 list = it->getShopCost(NULL, NULL);
        for (int i = -10; i <= 30; i++) {
            ShopIndexOverride = i;
            int32 ask = it->getShopCost(p, roark);
            ShopIndexOverride = -999;
            Error("SHOP_MARKUP_PROBE item=%s index=%d list=%d ask=%d",
                C[c].label, i, (int)it->getShopCost(NULL, NULL), (int)ask);
        }
        Error("SHOP_MARKUP_PROBE item=%s index=natural list=%d ask=%d",
            C[c].label, (int)list, (int)it->getShopCost(p, roark));
        delete it;
    }
    roark->Remove(true);
}
