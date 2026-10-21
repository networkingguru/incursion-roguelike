/* inc-1qyv: opt-in True Blows reproduction (INCURSION_TRUE_BLOWS_PROBE).
   Caller: Game::Play (src/Main.cpp). Reader: tools/check_true_blows.sh.
   Every attack goes through the real Creature::Strike (EV_STRIKE), which holds
   the incorporeal pass-through gate and, via EV_DAMAGE, the 50% ignore gate and
   the weapon-immunity gate. The status comes from a real EV_DRINK. */
#include "Incursion.h"

static const int TRIALS = 200;

/* One attack. Outcome: 1 damaged, 2 ignored by the 50% incorporeal gate,
   3 stopped by weapon immunity, 0 none (passed clean through, or missed). */
static int StrikeOnce(Player *p, Monster *v, Item *w, int8 atype) {
    v->mHP = v->cHP = 10000;
    p->cHP = p->mHP; /* a glass golem retaliates for each blow */
    EventInfo e; e.Clear();
    e.EActor = p; e.EVictim = v; e.ETarget = v; e.EMap = p->m;
    e.EItem = w; e.AType = atype;
    e.Dmg = p->DmgVal(S_MELEE, false);
    e.vHit = 100; e.vDef = 0;
    e.DType = w ? (int8)w->DamageType(v) : AD_BLUNT;
    e.vThreat = w ? (int8)w->Threat(p) : 20;
    e.vCrit = w ? (int8)w->CritMult(p) : 2;
    e.Terse = true;
    ReThrow(EV_STRIKE, e);
    if (10000 - v->cHP > 0) return 1;
    if (e.Immune) return 2;
    if (e.isWImmune) return 3;
    return 0;
}

static void Measure(Player *p, const char *scene, const char *phase,
                    Monster *v, Item *w, int8 atype) {
    int n[4] = {0,0,0,0};
    for (int i = 0; i < TRIALS; ++i) n[StrikeOnce(p, v, w, atype)]++;
    Error("TRUE_BLOWS m scene=%s phase=%s plus=%d status=%d trials=%d damaged=%d ignored=%d wimmune=%d none=%d",
        scene, phase, w ? (int)w->GetPlus() : -1,
        (int)p->HasStati(IGNORES_WEAPON_IMMUNITY), TRIALS, n[1], n[2], n[3], n[0]);
}

struct Scene { const char *name; const char *mon; bool phased; int wil; };

void TrueBlowsProbe(Player *p) {
    if (!getenv("INCURSION_TRUE_BLOWS_PROBE")) return;
    Error("TRUE_BLOWS setup begin");
    rID sword = FIND("long sword"), potion = FIND("potion");
    rID effect = FIND("true blows"), roark = FIND("Roark Ironbeard");
    if (!p || !p->m || !sword || !potion || !effect || !roark) {
        Error("TRUE_BLOWS INCONCLUSIVE missing scene/resource"); return;
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
    if (x < 0) { Error("TRUE_BLOWS INCONCLUSIVE no free cell"); return; }
    bool playing = theGame->PlayMode;
    theGame->PlayMode = true;
    int8 more = p->Options[OPT_AUTOMORE];
    p->Options[OPT_AUTOMORE] = 1;
    p->RemoveStati(IGNORES_WEAPON_IMMUNITY);

    static const Scene scenes[3] = {
        { "incor", "kobold", true, 0 },
        { "wimm1", "glass golem", false, 1 },
        { "wimm2", "flesh golem", false, 2 },
    };
    Monster *mon[3] = {NULL,NULL,NULL};
    for (int i = 0; i < 3; ++i) {
        rID r = FIND(scenes[i].mon);
        if (!r) { Error("TRUE_BLOWS INCONCLUSIVE no monster %s", scenes[i].mon); return; }
        mon[i] = new Monster(r);
        mon[i]->PlaceAt(p->m, x, y);
        mon[i]->Initialize(true);
        if (scenes[i].phased) mon[i]->GainPermStati(PHASED,NULL,SS_MISC,PHASE_ETHEREAL);
        Error("TRUE_BLOWS scene=%s wil=%d plane=%d", scenes[i].name,
            (int)mon[i]->AbilityLevel(CA_WEAPON_IMMUNITY), (int)mon[i]->onPlane());
        mon[i]->Remove(false);
    }
    Item *w0 = Item::Create(sword); w0->SetInherentPlus(0);
    Item *w1 = Item::Create(sword); w1->SetInherentPlus(1);
    Item *w2 = Item::Create(sword); w2->SetInherentPlus(2);
    Item *ctl[3] = { w1, w1, w2 };

    Error("TRUE_BLOWS bonus phase=before hit=%d dmg=%dd%d+%d", (int)p->Attr[A_HIT_MELEE],
        (int)p->DmgVal(S_MELEE,false).Number, (int)p->DmgVal(S_MELEE,false).Sides,
        (int)p->DmgVal(S_MELEE,false).Bonus);
    for (int i = 0; i < 3; ++i) {
        mon[i]->PlaceAt(p->m, x, y);
        Measure(p, scenes[i].name, "before", mon[i], w0, A_SWNG);
        Measure(p, scenes[i].name, "control", mon[i], ctl[i], A_SWNG);
        if (i) Measure(p, scenes[i].name, "before-bare", mon[i], NULL, A_PUNC);
        mon[i]->Remove(false);
    }

    Item *drink = Item::Create(potion);
    drink->MakeMagical(effect);
    drink->MakeKnown(0xFF);
    p->GainItem(drink,true);
    EventInfo de; de.Clear();
    de.EActor = p; de.EVictim = p; de.EItem = drink; de.eID = effect;
    EvReturn result = ReThrow(EV_DRINK,de);
    Error("TRUE_BLOWS drink return=%d status=%d duration=%d",
        (int)result,(int)p->HasStati(IGNORES_WEAPON_IMMUNITY),
        (int)p->GetStatiDur(IGNORES_WEAPON_IMMUNITY));
    Error("TRUE_BLOWS bonus phase=after hit=%d dmg=%dd%d+%d", (int)p->Attr[A_HIT_MELEE],
        (int)p->DmgVal(S_MELEE,false).Number, (int)p->DmgVal(S_MELEE,false).Sides,
        (int)p->DmgVal(S_MELEE,false).Bonus);

    for (int i = 0; i < 3; ++i) {
        mon[i]->PlaceAt(p->m, x, y);
        Measure(p, scenes[i].name, "after", mon[i], w0, A_SWNG);
        if (i) Measure(p, scenes[i].name, "after-bare", mon[i], NULL, A_PUNC);
        mon[i]->Remove(true);
    }

    /* Price: Roark's own stock, priced for the player at Diplomacy 0 and high. */
    Creature *shop = InitShopkeeper(roark, 100000); /* what the cave entrance runs */
    Item *tb = NULL, *ctlItem = NULL;
    for (Item *it = shop->FirstInv(); it; it = shop->NextInv()) {
        if (it->eID == effect && !tb) tb = it;
        else if (it->isType(T_POTION) && it->eID && it->eID != effect && !ctlItem) ctlItem = it;
    }
    if (!tb || !ctlItem) {
        Error("TRUE_BLOWS INCONCLUSIVE shop stock tb=%d ctl=%d", tb ? 1 : 0, ctlItem ? 1 : 0);
    } else {
        int32 qty = tb->GetQuantity(), cq = ctlItem->GetQuantity();
        int d0 = p->SkillLevel(SK_DIPLOMACY);
        int32 tb0 = tb->getShopCost(p, shop) / qty, c0 = ctlItem->getShopCost(p, shop) / cq;
        p->GainPermStati(SKILL_BONUS,NULL,SS_MISC,SK_DIPLOMACY,30);
        int d1 = p->SkillLevel(SK_DIPLOMACY);
        int32 tb1 = tb->getShopCost(p, shop) / qty, c1 = ctlItem->getShopCost(p, shop) / cq;
        Error("TRUE_BLOWS price stock=%d seller=%d dip_low=%d dip_high=%d tb_low=%d tb_high=%d ctl_low=%d ctl_high=%d nullnull=%d",
            (int)qty, shop->HasMFlag(M_SELLER) ? 1 : 0, d0, d1, (int)tb0, (int)tb1,
            (int)c0, (int)c1, (int)(tb->getShopCost(NULL,NULL) / qty));
    }
    shop->Remove(true);

    /* Duration: drive the live per-turn code (Creature::DoTurn -> UpdateStati). */
    int present = 0;
    for (int t = 1; t <= 7200 && !p->isDead(); ++t) {
        p->DoTurn();
        if (t == 7199) present = p->HasStati(IGNORES_WEAPON_IMMUNITY) ? 1 : 0;
        if (t == 7200)
            Error("TRUE_BLOWS duration at7199=%d at7200=%d dead=%d", present,
                (int)(p->HasStati(IGNORES_WEAPON_IMMUNITY) ? 1 : 0), (int)p->isDead());
    }
    Error("TRUE_BLOWS done");
    delete w0; delete w1; delete w2;
    p->Options[OPT_AUTOMORE] = more;
    theGame->PlayMode = playing;
}
