/* inc-icp3: opt-in reproduction of Roark's necessities stock
   (INCURSION_ROARK_STOCK_PROBE=count|price|refill|craft|cost). Caller: Game::Play
   (src/Main.cpp). Reader: tools/check_roark_stock.sh.
   The table below is the ruled list, kept here on purpose and NOT read from
   Roark's resource: the probe must stay an independent oracle for it.
   Lines go through Error(), prefix "ROARK_STOCK". */
#include "Incursion.h"

struct Need { const char *label, *item, *eff; int tier; };

static const Need NEEDS[] = {
    { "healing kit",        "healing kit",    NULL, 1 },
    { "climbing rig",       "climbing rig",   NULL, 1 },
    { "mechanical tools",   "mechanical tools", NULL, 1 },
    { "alchemy set",        "alchemy set",    NULL, 1 },
    { "pickaxe",            "pickaxe",        NULL, 6 },
    { "craftsmans tools",   "craftsman's tools", NULL, 1 },
    { "brass lantern",      "brass lantern",  NULL, 1 },
    { "restoration",        "potion", "restoration", 3 },
    { "see invisibility",   "potion", "see invisibility;potion", 3 },
    { "stone to flesh",     "potion", "stone to flesh", 3 },
    { "restore strength",   "potion", "restore strength", 6 },
    { "restore dexterity",  "potion", "restore dexterity", 6 },
    { "restore constitution","potion", "restore constitution", 6 },
    { "restore intelligence","potion", "restore intelligence", 6 },
    { "restore wisdom",     "potion", "restore wisdom", 6 },
    { "restore charisma",   "potion", "restore charisma", 6 },
    { "restore luck",       "potion", "restore luck", 6 },
    { "cure disease",       "potion", "cure disease", 6 },
    { "antitoxin",          "potion", "antitoxin", 6 },
    { "remove curse",       "potion", "remove curse;potion", 6 },
    { "elemental resistance","potion", "elemental resistance", 6 },
    { "water walking",      "potion", "water walking;potion", 6 },
    { "valour",             "potion", "valour;potion", 6 },
    { "dimension door",     "potion", "dimension door", 6 },
    { "flask of oil",       "potion", "flask of oil", 6 },
    { "identify scroll",    "scroll", "identify;scroll", 12 },
    { "dispel magic scroll","scroll", "dispel magic", 3 },
    { "transmute rock to mud scroll","scroll", "transmute rock to mud", 6 },
    { "mana",               "potion", "mana", 12 },
    { "food ration",        "food ration", NULL, 12 },
    { "torch",              "torch",          NULL, 12 },
    { "true blows",         "potion", "true blows", 12 },
    { "hemp rope",          "hemp rope",      NULL, 20 },
    { "sheaf arrow",        "sheaf arrow",    NULL, 50 },
    { "flight arrow",       "flight arrow",   NULL, 50 },
    { "crossbow bolt",      "crossbow bolt",  NULL, 50 },
    { "hand crossbow dart", "hand crossbow dart", NULL, 50 },
    { "dart",               "dart",           NULL, 50 },
    { "sling stone",        "sling stone",    NULL, 50 },
};
static const int NN = sizeof(NEEDS) / sizeof(NEEDS[0]);

static bool Resolve(const Need &n, rID &iID, rID &eID) {
    iID = FIND(n.item);
    eID = n.eff ? FIND(n.eff) : 0;
    if (!iID || (n.eff && !eID)) {
        Error("ROARK_STOCK INCONCLUSIVE cannot resolve %s", n.label);
        return false;
    }
    return true;
}

static int Have(Creature *shop, rID iID, rID eID) {
    int have = 0;
    for (Item *it = shop->FirstInv(); it; it = shop->NextInv())
        if (it->iID == iID && it->eID == eID)
            have += (int)it->GetQuantity();
    return have;
}

static void CountMode(Player *p) {
    rID roark = FIND("Roark Ironbeard");
    for (int seed = 1; seed <= 20; seed++) {
        p->storeSeed = seed;
        Creature *shop = InitShopkeeper(roark, 100000);
        int short_ = 0, over = 0;
        for (int i = 0; i < NN; i++) {
            rID iID, eID;
            if (!Resolve(NEEDS[i], iID, eID)) { shop->Remove(true); return; }
            int have = Have(shop, iID, eID);
            if (have < NEEDS[i].tier) short_++;
            else if (have > NEEDS[i].tier) over++;
            Error("ROARK_STOCK count seed=%d item=%s have=%d need=%d",
                seed, NEEDS[i].label, have, NEEDS[i].tier);
        }
        /* mundane: every stack of a no-effect row has no effect and plus 0 */
        for (int i = 0; i < NN; i++) {
            if (NEEDS[i].eff) continue;
            rID iID = FIND(NEEDS[i].item);
            int plus = 0, eff = 0;
            for (Item *it = shop->FirstInv(); it; it = shop->NextInv()) {
                if (it->iID != iID) continue;
                if (it->eID) eff++;
                if (it->GetInherentPlus() > plus) plus = it->GetInherentPlus();
            }
            Error("ROARK_STOCK mundane seed=%d item=%s plus=%d eff=%d", seed, NEEDS[i].label, plus, eff);
        }
        Error("ROARK_STOCK seed=%d short=%d over=%d total=%d", seed, short_, over, NN);
        shop->Remove(true);
    }
    Error("ROARK_STOCK done");
}

static Item *Find(Creature *shop, rID iID, rID eID) {
    for (Item *it = shop->FirstInv(); it; it = shop->NextInv())
        if (it->iID == iID && it->eID == eID) return it;
    return NULL;
}

static void PriceMode(Player *p) {
    static const struct { const char *label; int gp; } FIXED[] = {
        { "cure disease", 200 }, { "antitoxin", 100 }, { "remove curse", 50 },
        { "valour", 50 }, { "identify scroll", 100 }, { "mana", 50 },
        { "true blows", 50 }, { "water walking", 50 }, { "elemental resistance", 50 },
    };
    static const char *CTLNAMES[] = { "restoration", "restore strength", "dimension door", "dispel magic scroll", "transmute rock to mud scroll", "pickaxe" };
    rID roark = FIND("Roark Ironbeard");
    p->storeSeed = 1;
    Creature *shop = InitShopkeeper(roark, 100000);
    int d0 = p->SkillLevel(SK_DIPLOMACY);
    int32 pLow[16], pHigh[16], pNull[16]; const char *names[16]; int nn = 0;
    Item *its[16];
    for (size_t f = 0; f < sizeof(FIXED) / sizeof(FIXED[0]); f++)
        for (int i = 0; i < NN; i++)
            if (!strcmp(NEEDS[i].label, FIXED[f].label)) {
                rID iID, eID;
                if (!Resolve(NEEDS[i], iID, eID)) { shop->Remove(true); return; }
                its[nn] = Find(shop, iID, eID);
                names[nn++] = FIXED[f].label;
            }
    int nfixed = nn;
    for (size_t c = 0; c < sizeof(CTLNAMES) / sizeof(CTLNAMES[0]); c++)
        for (int i = 0; i < NN; i++)
            if (!strcmp(NEEDS[i].label, CTLNAMES[c])) {
                rID iID, eID;
                if (!Resolve(NEEDS[i], iID, eID)) { shop->Remove(true); return; }
                its[nn] = Find(shop, iID, eID);
                names[nn++] = CTLNAMES[c];
            }
    for (int k = 0; k < nn; k++) if (!its[k]) {
        Error("ROARK_STOCK INCONCLUSIVE price: %s not in stock", names[k]);
        shop->Remove(true);
        return;
    }
    for (int k = 0; k < nn; k++) {
        int32 q = its[k]->GetQuantity();
        pLow[k] = its[k]->getShopCost(p, shop) / q;
        pNull[k] = its[k]->getShopCost(NULL, NULL) / q;
    }
    p->GainPermStati(SKILL_BONUS, NULL, SS_MISC, SK_DIPLOMACY, 30);
    int d1 = p->SkillLevel(SK_DIPLOMACY);
    for (int k = 0; k < nn; k++)
        pHigh[k] = its[k]->getShopCost(p, shop) / its[k]->GetQuantity();
    for (int k = 0; k < nn; k++)
        Error("ROARK_STOCK price item=%s kind=%s dip_low=%d dip_high=%d low=%d high=%d nullnull=%d",
            names[k], k < nfixed ? "fixed" : "control", d0, d1, (int)pLow[k], (int)pHigh[k], (int)pNull[k]);
    Error("ROARK_STOCK done");
    shop->Remove(true);
}

/* Refill: stock, spend some, then open the store (RestockShopDaily, which the
   cave entrance calls) at times inside and past the day of the last refill. */
static void SetHave(Creature *shop, const char *label, int want) {
    for (int i = 0; i < NN; i++) {
        if (strcmp(NEEDS[i].label, label)) continue;
        rID iID, eID;
        if (!Resolve(NEEDS[i], iID, eID)) return;
        int have = Have(shop, iID, eID);
        if (want < have) {
            /* spend: shrink or delete stacks until `have - want` units are gone */
            for (Item *it = shop->FirstInv(); it && have > want; it = shop->NextInv()) {
                if (it->iID != iID || it->eID != eID) continue;
                int take = min((int)it->GetQuantity(), have - want);
                have -= take;
                if (take == (int)it->GetQuantity()) { it->Remove(true); it = shop->FirstInv(); /* restart: list changed */ }
                else it->SetQuantity(it->GetQuantity() - take);
            }
        } else if (want > have) {
            Item *it = Item::Create(iID);
            if (eID) it->MakeMagical(eID, 0);
            it->SetQuantity(want - have);
            shop->GainItem(it, true);
        }
        return;
    }
    Error("ROARK_STOCK INCONCLUSIVE SetHave unknown %s", label);
}

static void Report(Creature *shop, const char *phase, int ret) {
    int short_ = 0, over = 0, anti = -1, mana = -1;
    for (int i = 0; i < NN; i++) {
        rID iID, eID;
        if (!Resolve(NEEDS[i], iID, eID)) return;
        int have = Have(shop, iID, eID);
        if (have < NEEDS[i].tier) short_++;
        else if (have > NEEDS[i].tier) over++;
        if (!strcmp(NEEDS[i].label, "antitoxin")) anti = have;
        if (!strcmp(NEEDS[i].label, "mana")) mana = have;
        Error("ROARK_STOCK refill phase=%s item=%s have=%d need=%d", phase, NEEDS[i].label, have, NEEDS[i].tier);
    }
    Error("ROARK_STOCK refill phase=%s ret=%d short=%d over=%d antitoxin=%d mana=%d",
        phase, ret, short_, over, anti, mana);
}

static void RefillMode(Player *p) {
    const uint32 DAY = 24 * HOUR_TURNS;
    rID roark = FIND("Roark Ironbeard");
    p->storeSeed = 1;
    uint32 saved = theGame->Turn;
    theGame->Turn = 5 * DAY + 1000;               /* day 5, early */
    Creature *shop = InitShopkeeper(roark, 100000);
    Report(shop, "init", -1);
    SetHave(shop, "healing kit", 0);
    SetHave(shop, "torch", 0);
    SetHave(shop, "mana", 4);
    SetHave(shop, "hemp rope", 5);
    SetHave(shop, "restore strength", 2);
    SetHave(shop, "stone to flesh", 1);
    SetHave(shop, "antitoxin", 9);                /* above the tier size of 6 */
    SetHave(shop, "sheaf arrow", 20);             /* ammunition: partly spent */
    SetHave(shop, "sling stone", 0);              /* ammunition: all spent */
    Report(shop, "spent", -1);
    theGame->Turn = 5 * DAY + DAY - 1;            /* last tick of day 5 */
    Report(shop, "sameday", RestockShopDaily(shop) ? 1 : 0);
    theGame->Turn = 6 * DAY;                      /* first tick of day 6 */
    Report(shop, "nextday", RestockShopDaily(shop) ? 1 : 0);
    SetHave(shop, "mana", 2);
    Report(shop, "spent2", -1);
    theGame->Turn = 6 * DAY + 100;
    Report(shop, "sameday2", RestockShopDaily(shop) ? 1 : 0);
    theGame->Turn = 8 * DAY;                      /* two days on */
    Report(shop, "day8", RestockShopDaily(shop) ? 1 : 0);
    Error("ROARK_STOCK done");
    shop->Remove(true);
    theGame->Turn = saved;
}

/* Craft cost: what CraftItem quotes (CraftCosts, src/Skills.cpp) for one item.
   xp is the acquire-by-XP cost, gp the crafting gold cost. */
static void CraftMode(Player *p) {
    static const struct { const char *label, *base, *eff; int plus; int16 type, src; } C[] = {
        { "mana",           "potion", "mana",       0, T_POTION, AI_POTION },
        { "identify scroll","scroll", "identify;scroll", 0, T_SCROLL, AI_SCROLL },
        { "true blows",     "potion", "true blows", 0, T_POTION, AI_POTION },
        { "cure disease",   "potion", "cure disease", 0, T_POTION, AI_POTION },
        { "control girdle+2 giant strength", "girdle", "giant strength", 2, -1, -1 },
    };
    (void)p;
    for (size_t c = 0; c < sizeof(C) / sizeof(C[0]); c++) {
        rID iID = FIND(C[c].base), eID = FIND(C[c].eff);
        if (!iID || !eID) { Error("ROARK_STOCK INCONCLUSIVE craft cannot resolve %s", C[c].label); return; }
        Item *it = Item::Create(iID);
        it->MakeMagical(eID, C[c].plus);
        int32 xp, gp, xp2, gp2;
        CraftCosts(it, C[c].type, C[c].src, ACQ_ACQUIRE, 1, &xp, &gp);
        CraftCosts(it, C[c].type, C[c].src, ACQ_CRAFT, 1, &xp2, &gp2);
        Error("ROARK_STOCK craft item=%s fixed=%d level=%d xp=%d gp=%d craft_gp=%d",
            C[c].label, TEFF(eID)->HasFlag(EF_FIXED_PRICE) ? 1 : 0, (int)it->ItemLevel(),
            (int)xp, (int)gp, (int)gp2);
        delete it;
    }
    Error("ROARK_STOCK done");
}

/* List cost: the base Cost field every shop price derives from
   (Item::getShopCost starts from TITEM(iID)->Cost), in hundredths of a gp. */
static void CostMode(Player *p) {
    static const char *NAMES[] = { "dart", "sling stone", "sheaf arrow", "crossbow bolt" };
    (void)p;
    for (size_t k = 0; k < sizeof(NAMES) / sizeof(NAMES[0]); k++) {
        rID iID = FIND(NAMES[k]);
        if (!iID) { Error("ROARK_STOCK INCONCLUSIVE cost cannot resolve %s", NAMES[k]); return; }
        Error("ROARK_STOCK cost item=%s list=%d", NAMES[k], (int)TITEM(iID)->Cost);
    }
    Error("ROARK_STOCK done");
}

/* inc-icp3: the hook below serves the Roark stock check, tools/check_roark_stock.sh. */
void RoarkStockProbe(Player *p) {
    const char *s = getenv("INCURSION_ROARK_STOCK_PROBE");
    if (!s || !*s) return;
    if (!p || !FIND("Roark Ironbeard")) {
        Error("ROARK_STOCK INCONCLUSIVE no player or no Roark");
        return;
    }
    if (!strcmp(s, "count")) CountMode(p);
    else if (!strcmp(s, "price")) PriceMode(p);
    else if (!strcmp(s, "refill")) RefillMode(p);
    else if (!strcmp(s, "craft")) CraftMode(p);
    else if (!strcmp(s, "cost")) CostMode(p);
    else Error("ROARK_STOCK INCONCLUSIVE unknown mode %s", s);
}
