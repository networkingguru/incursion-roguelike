/* inc-gzkn: opt-in elemental resistance potion reproduction
   (INCURSION_ELEM_RESIST_PROBE). Caller: Game::Play (src/Main.cpp). Reader:
   tools/check_elemental_resistance_potion.sh. Damage goes through the real
   EV_DAMAGE on the drinker and on a carried item; the statuses come from a
   real EV_DRINK. */
#include "Incursion.h"

static const int TRIALS = 400;
static const int8 TYPES[4] = { AD_FIRE, AD_COLD, AD_ACID, AD_ELEC };
static const char *TNAME[4] = { "fire", "cold", "acid", "elec" };

/* Mean damage per hit, in hundredths, over TRIALS hits of nd6 from 'actor'. */
static int MeanDamage(Player *p, Creature *actor, int8 dt, int nd) {
    long total = 0;
    int16 mHP = p->mHP;
    p->mHP += 2000;
    for (int i = 0; i < TRIALS; ++i) {
        int dmg = 0;
        for (int k = 0; k < nd; ++k) dmg += random(6) + 1;
        p->cHP = p->mHP;
        ThrowDmg(EV_DAMAGE, dt, dmg, "probe", actor, p);
        total += p->mHP - p->cHP;
    }
    p->mHP = mHP;
    p->cHP = p->mHP;
    return (int)((total * 100) / TRIALS);
}

/* One carried item takes one hit of 'dmg'. Returns 1 harmed (destroyed -- the engine marks it F_DELETE and
   frees it later -- or a unit or hit points lost), 0 untouched. *hard gets the item's own hardness. */
static int ItemHarmed(Player *p, Creature *actor, rID base, rID effect,
                      bool sword, int8 dt, int dmg, int *hard) {
    Item *it = Item::Create(base);
    if (sword) it->SetInherentPlus(0);
    else it->MakeKnown(0xFF);
    p->GainItem(it, true);
    hObj h = it->myHandle;
    int16 hp0 = it->GetHP();
    int32 q0 = it->GetQuantity();
    *hard = it->Hardness(dt);
    ThrowDmg(EV_DAMAGE, dt, dmg, "probe", actor, it);
    Item *r = oItem(h);
    int harmed = (!r || (r->Flags & F_DELETE) || r->GetHP() < hp0 || r->GetQuantity() < q0) ? 1 : 0;
    if (r && !(r->Flags & F_DELETE)) r->Remove(true);
    return harmed;
}

static void Gear(Player *p, const char *phase) {
    Error("ELEM_RESIST gear phase=%s fire=%d cold=%d acid=%d elec=%d", phase,
        (int)p->GearResistLevel(AD_FIRE), (int)p->GearResistLevel(AD_COLD),
        (int)p->GearResistLevel(AD_ACID), (int)p->GearResistLevel(AD_ELEC));
}

static void Damage(Player *p, Creature *actor, const char *phase) {
    for (int t = 0; t < 4; ++t)
        Error("ELEM_RESIST dmg phase=%s type=%s mean1d6=%d mean6d6=%d", phase, TNAME[t],
            MeanDamage(p, actor, TYPES[t], 1), MeanDamage(p, actor, TYPES[t], 6));
}

static void Items(Player *p, Creature *actor, const char *phase,
                  rID scroll, rID potion, rID sword, rID effect) {
    /* fire: paper, hardness 0; cold: liquid, 3; acid and electricity: the
       sword's own metal. Damage sits 1..10 above the hardness. */
    int h[4], r[4];
    r[0] = ItemHarmed(p, actor, scroll, effect, false, AD_FIRE, 5, &h[0]);
    r[1] = ItemHarmed(p, actor, potion, effect, false, AD_COLD, 8, &h[1]);
    r[2] = ItemHarmed(p, actor, sword, effect, true, AD_ACID, 15, &h[2]);
    r[3] = ItemHarmed(p, actor, sword, effect, true, AD_ELEC, 15, &h[3]);
    Error("ELEM_RESIST items phase=%s fire=%d cold=%d acid=%d elec=%d hard=%d,%d,%d,%d", phase,
        r[0], r[1], r[2], r[3], h[0], h[1], h[2], h[3]);
}

static void Drink(Player *p, rID potion, rID effect, int *ret) {
    p->RemoveStati(RESIST);
    Item *drink = Item::Create(potion);
    drink->MakeMagical(effect);
    drink->MakeKnown(0xFF);
    p->GainItem(drink, true);
    EventInfo de; de.Clear();
    de.EActor = p; de.EVictim = p; de.EItem = drink; de.eID = effect;
    *ret = (int)ReThrow(EV_DRINK, de);
}

/* inc-gzkn: off unless INCURSION_ELEM_RESIST_PROBE is set; run by tools/check_elemental_resistance_potion.sh. */
void ElementalResistanceProbe(Player *p) {
    if (!getenv("INCURSION_ELEM_RESIST_PROBE")) return;
    Error("ELEM_RESIST setup begin");
    rID potion = FIND("potion"), scroll = FIND("scroll"), sword = FIND("long sword");
    rID effect = FIND("elemental resistance"), roark = FIND("Roark Ironbeard");
    rID blows = FIND("true blows"), kob = FIND("kobold");
    if (!p || !p->m || !potion || !scroll || !sword || !effect || !roark || !blows || !kob) {
        Error("ELEM_RESIST INCONCLUSIVE missing scene/resource"); return;
    }
    int x = -1, y = -1;
    for (int dx = -1; dx <= 1 && x < 0; ++dx)
        for (int dy = -1; dy <= 1 && x < 0; ++dy) {
            int tx = p->x + dx, ty = p->y + dy;
            if (p->m->InBounds(tx,ty) && !p->m->SolidAt(tx,ty) &&
                !p->m->FCreatureAt(tx,ty) && !p->m->FFeatureAt(tx,ty)) {
                x = tx; y = ty;
            }
        }
    if (x < 0) { Error("ELEM_RESIST INCONCLUSIVE no free cell"); return; }
    bool playing = theGame->PlayMode;
    theGame->PlayMode = true;
    int8 more = p->Options[OPT_AUTOMORE];
    p->Options[OPT_AUTOMORE] = 1;
    p->RemoveStati(RESIST);

    Monster *actor = new Monster(kob);
    actor->PlaceAt(p->m, x, y);
    actor->Initialize(true);

    Gear(p, "before");
    Damage(p, actor, "before");
    Items(p, actor, "before", scroll, potion, sword, effect);

    int ret = -1;
    Drink(p, potion, effect, &ret);
    Error("ELEM_RESIST drink return=%d", ret);
    Gear(p, "after");
    /* Every RESIST status: type, magnitude, duration, source effect id. */
    {
        int n = 0; char buf[256]; buf[0] = 0;
        StatiIterNature(p, RESIST)
            snprintf(buf + strlen(buf), sizeof(buf) - strlen(buf), " [%d,%d,%d,%d]",
                (int)S->Val, (int)S->Mag, (int)S->Duration, (int)(S->eID == effect));
            n++;
        StatiIterEnd(p)
        Error("ELEM_RESIST stati n=%d types=%d,%d,%d,%d:%s", n, (int)TYPES[0], (int)TYPES[1],
            (int)TYPES[2], (int)TYPES[3], buf);
    }
    Damage(p, actor, "after");
    Items(p, actor, "after", scroll, potion, sword, effect);

    /* Price: Roark's own stock, priced for the player at Diplomacy 0 and high. */
    Creature *shop = InitShopkeeper(roark, 100000);
    Item *er = NULL, *ctl = NULL;
    for (Item *it = shop->FirstInv(); it; it = shop->NextInv()) {
        if (it->eID == effect && !er) er = it;
        else if (it->isType(T_POTION) && it->eID && it->eID != effect && it->eID != blows && !ctl &&
                 !TEFF(it->eID)->HasFlag(EF_FIXED_PRICE)) ctl = it;
    }
    if (!er || !ctl) {
        Error("ELEM_RESIST INCONCLUSIVE shop stock er=%d ctl=%d", er ? 1 : 0, ctl ? 1 : 0);
    } else {
        int32 qty = er->GetQuantity(), cq = ctl->GetQuantity();
        int d0 = p->SkillLevel(SK_DIPLOMACY);
        int32 e0 = er->getShopCost(p, shop) / qty, c0 = ctl->getShopCost(p, shop) / cq;
        p->GainPermStati(SKILL_BONUS,NULL,SS_MISC,SK_DIPLOMACY,30);
        int d1 = p->SkillLevel(SK_DIPLOMACY);
        int32 e1 = er->getShopCost(p, shop) / qty, c1 = ctl->getShopCost(p, shop) / cq;
        Error("ELEM_RESIST price stock=%d seller=%d dip_low=%d dip_high=%d er_low=%d er_high=%d ctl_low=%d ctl_high=%d nullnull=%d",
            (int)qty, shop->HasMFlag(M_SELLER) ? 1 : 0, d0, d1, (int)e0, (int)e1,
            (int)c0, (int)c1, (int)(er->getShopCost(NULL,NULL) / qty));
    }
    shop->Remove(true);

    /* Duration, many drinks: the four statuses share one roll; rolls 10..40. */
    int lo = 9999, hi = -1, unequal = 0, drinks = 300;
    for (int i = 0; i < drinks; ++i) {
        Drink(p, potion, effect, &ret);
        int d[4] = {-1,-1,-1,-1};
        for (int t = 0; t < 4; ++t)
            StatiIterNature(p, RESIST)
                if (S->Val == TYPES[t]) d[t] = S->Duration;
            StatiIterEnd(p)
        if (d[0] != d[1] || d[0] != d[2] || d[0] != d[3]) unequal++;
        if (d[0] < lo) lo = d[0];
        if (d[0] > hi) hi = d[0];
    }
    Error("ELEM_RESIST rolls drinks=%d lo=%d hi=%d unequal=%d", drinks, lo, hi, unequal);

    /* Duration, last unit: drive the live per-turn code. */
    Drink(p, potion, effect, &ret);
    int D = -1;
    StatiIterNature(p, RESIST)
        if (S->Val == AD_FIRE) D = S->Duration;
    StatiIterEnd(p)
    int present = -1, gone = -1;
    for (int t = 1; t <= D && !p->isDead(); ++t) {
        p->DoTurn();
        int n = 0;
        StatiIterNature(p, RESIST) n++; StatiIterEnd(p)
        if (t == D - 1) present = n;
        if (t == D) gone = n;
    }
    Error("ELEM_RESIST duration roll=%d present_stati_at_last_minus1=%d stati_at_last=%d dead=%d",
        D, present, gone, (int)p->isDead());
    Error("ELEM_RESIST done");
    actor->Remove(true);
    p->Options[OPT_AUTOMORE] = more;
    theGame->PlayMode = playing;
}
