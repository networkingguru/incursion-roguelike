/* inc-2rws: opt-in Water Walking potion reproduction (INCURSION_WATER_WALKING_PROBE).
   Caller: Game::Play (src/Main.cpp). Reader: tools/check_water_walking_potion.sh.
   Each trial throws EV_MOVE at the water terrain's own handler (lib/dungeon.irh),
   the code a step into the water runs. The status comes from a real EV_DRINK. */
#include "Incursion.h"

static const int TRIALS = 200;

/* One step into the water. Outcome: 0 passed, 1 aborted with no harm (failed to
   make progress), 2 drowning branch (EXPOSED granted, damage thrown). */
static int StepInto(Player *p, rID terrain) {
    p->cHP = p->mHP;
    p->RemoveStati(EXPOSED);
    EvReturn r = TTER(terrain)->PEvent(EV_MOVE, p, terrain);
    int out = 0;
    if (p->HasStati(EXPOSED) || p->cHP < p->mHP) out = 2;
    else if (r == ABORT) out = 1;
    p->cHP = p->mHP;
    p->RemoveStati(EXPOSED);
    return out;
}

static void Measure(Player *p, const char *phase,
                    const char *name, rID terrain) {
    int n[3] = {0,0,0};
    for (int i = 0; i < TRIALS; ++i) n[StepInto(p, terrain)]++;
    Error("WATER_WALKING m phase=%s terrain=%s status=%d swim=%d trials=%d passed=%d failed=%d drowned=%d",
        phase, name, (int)p->HasStati(WATER_WALKING),
        (int)p->SkillLevel(SK_SWIM), TRIALS, n[0], n[1], n[2]);
}

static void MeasureAll(Player *p, const char *phase, rID deep, rID turb) {
    Measure(p, phase, "deep", deep);
    Measure(p, phase, "turbulent", turb);
}

static EvReturn Drink(Player *p, rID potion, rID effect) {
    Item *it = Item::Create(potion);
    it->MakeMagical(effect);
    it->MakeKnown(0xFF);
    p->GainItem(it,true);
    EventInfo de; de.Clear();
    de.EActor = p; de.EVictim = p; de.EItem = it; de.eID = effect;
    return ReThrow(EV_DRINK,de);
}

/* inc-2rws: off unless INCURSION_WATER_WALKING_PROBE is set; run by tools/check_water_walking_potion.sh. */
void WaterWalkingProbe(Player *p) {
    if (!getenv("INCURSION_WATER_WALKING_PROBE")) return;
    Error("WATER_WALKING setup begin");
    rID potion = FIND("potion"), effect = FIND("water walking;potion");
    rID deep = FIND("deep water"), turb = FIND("turbulent water");
    rID roark = FIND("Roark Ironbeard");
    if (!p || !p->m || !potion || !effect || !deep || !turb || !roark) {
        Error("WATER_WALKING INCONCLUSIVE missing scene/resource"); return;
    }
    bool playing = theGame->PlayMode;
    theGame->PlayMode = true;
    int8 more = p->Options[OPT_AUTOMORE];
    p->Options[OPT_AUTOMORE] = 1;
    p->RemoveStati(WATER_WALKING);

    MeasureAll(p, "before", deep, turb);

    EvReturn result = Drink(p, potion, effect);
    Error("WATER_WALKING drink return=%d status=%d duration=%d", (int)result,
        (int)p->HasStati(WATER_WALKING), (int)p->GetStatiDur(WATER_WALKING));
    MeasureAll(p, "after", deep, turb);

    /* Price: Roark's own stock, priced for the player at Diplomacy 0 and high. */
    Creature *shop = InitShopkeeper(roark, 100000);
    Item *ww = NULL, *ctlItem = NULL;
    for (Item *it = shop->FirstInv(); it; it = shop->NextInv()) {
        if (it->eID == effect && !ww) ww = it;
        else if (it->isType(T_POTION) && it->eID && it->eID != effect && !ctlItem &&
                 !TEFF(it->eID)->HasFlag(EF_FIXED_PRICE)) ctlItem = it;
    }
    if (!ww || !ctlItem) {
        Error("WATER_WALKING INCONCLUSIVE shop stock ww=%d ctl=%d", ww ? 1 : 0, ctlItem ? 1 : 0);
    } else {
        int32 qty = ww->GetQuantity(), cq = ctlItem->GetQuantity();
        int d0 = p->SkillLevel(SK_DIPLOMACY);
        int32 w0 = ww->getShopCost(p, shop) / qty, c0 = ctlItem->getShopCost(p, shop) / cq;
        p->GainPermStati(SKILL_BONUS,NULL,SS_MISC,SK_DIPLOMACY,30);
        int d1 = p->SkillLevel(SK_DIPLOMACY);
        int32 w1 = ww->getShopCost(p, shop) / qty, c1 = ctlItem->getShopCost(p, shop) / cq;
        Error("WATER_WALKING price stock=%d seller=%d dip_low=%d dip_high=%d ww_low=%d ww_high=%d ctl_low=%d ctl_high=%d nullnull=%d",
            (int)qty, shop->HasMFlag(M_SELLER) ? 1 : 0, d0, d1, (int)w0, (int)w1,
            (int)c0, (int)c1, (int)(ww->getShopCost(NULL,NULL) / qty));
    }
    shop->Remove(true);

    /* Range: many real drinks; the potion lasts until rest (Duration -2). */
    int lo = 9999, hi = -9999, persistent = 0;
    const int DRINKS = 400;
    for (int i = 0; i < DRINKS; ++i) {
        p->RemoveStati(WATER_WALKING);
        Drink(p, potion, effect);
        int d = p->GetStatiDur(WATER_WALKING);
        if (d < lo) lo = d;
        if (d > hi) hi = d;
        if (d == -2) persistent++;
    }
    Error("WATER_WALKING range drinks=%d persistent=%d min=%d max=%d", DRINKS, persistent, lo, hi);

    /* Timing: live per-turn code for 600 turns, then the call rest makes (Map::DaysPassed). */
    p->RemoveStati(WATER_WALKING);
    Drink(p, potion, effect);
    const int TURNS = 600;
    int turns = 0;
    for (; turns < TURNS && !p->isDead(); ++turns) p->DoTurn();
    int afterTurns = p->HasStati(WATER_WALKING) ? 1 : 0;
    theGame->Day++; /* Player::Rest advances the day first; DaysPassed returns when Day matches */
    p->m->DaysPassed();
    int afterRest = p->HasStati(WATER_WALKING) ? 1 : 0;
    Error("WATER_WALKING timing turns=%d after_turns=%d after_rest=%d dead=%d", turns,
        afterTurns, afterRest, (int)p->isDead());
    Error("WATER_WALKING done");
    p->Options[OPT_AUTOMORE] = more;
    theGame->PlayMode = playing;
}
