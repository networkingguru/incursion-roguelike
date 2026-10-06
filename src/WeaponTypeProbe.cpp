/* inc-f38k probe: places that test isType(T_WEAPON) exactly treat a bow
   (T_BOW) or ammunition (T_MISSILE) as a non-weapon. Off unless
   INCURSION_WEAPONTYPE_PROBE is set; called from Game::Play (src/Main.cpp).
   Reader: tools/check_weapon_types.sh, which says what each line must hold.
   Every case drives the real code that holds the changed test and logs one
   line through Error(): "WEAPONTYPE_PROBE case=<c> item=<name> key=value ...".
   The value picks a mode: 1 (log cases), kysul, augment, screen-bow,
   screen-sword. */
/* Character::GodID and Character::FavourLev are protected, and TextTerm keeps
   its view list there too. This free function reads them, so they are opened
   here and nowhere else. */
#include <set>
#include <vector>
#define protected public
#include "Incursion.h"
#undef protected

static const char *gMode() {
    const char *s = getenv("INCURSION_WEAPONTYPE_PROBE");
    return (s && *s) ? s : "";
}

static Item *mk(const char *name, int plus = 1) {
    rID iID = FIND(name);
    Item *it = iID ? Item::Create(iID) : NULL;
    if (!it) {
        Error("WEAPONTYPE_PROBE INCONCLUSIVE no item %s", name);
        return NULL;
    }
    it->SetInherentPlus(plus);
    it->SetQuantity(1);
    return it;
}

static bool freeCell(Map *mp, int x, int y) {
    return mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FFeatureAt(x, y) &&
        !mp->FCreatureAt(x, y) && !mp->FItemAt(x, y);
}

/* Magic Weapon, Brand of Hatred: EV_ISTARGET, EV_RATETARG, and for the brand
   EV_MAGIC_HIT. */
static void spellCases(Player *p) {
    static const double defCost[] = {
        500, 1000, 2000, 3000, 4000, 6000, 8000,
        12000, 16000, 24000, 36000, 48000, 56000,
        75000, 102000, 128000, 256000, 512000,
        1000000, 1500000, 2000000 };
    const rID mwID = FIND("Magic Weapon"), bohID = FIND("Brand of Hatred");
    const char *names[4] = { "short bow", "long sword", "crossbow bolt", "dagger" };
    rID holderID = FIND("kobold");

    for (int c = 0; c < 4; c++) {
        Item *it = mk(names[c]);
        if (!it || (c < 3 && (!mwID || !bohID || !holderID))) {
            Error("WEAPONTYPE_PROBE case=%s INCONCLUSIVE missing resource", names[c]);
            delete it;
            continue;
        }
        if (c < 3) {
            EventInfo e;
            e.Clear();
            e.EActor = p;
            e.ETarget = it;
            e.EItem = it;
            e.eID = mwID;
            e.isSpell = true;
            int16 ist = TEFF(mwID)->Event(e, mwID, EV_ISTARGET);
            bool tgt = (ist == CAN_CAST_IT || ist == SHOULD_CAST_IT);
            bool rate = (ThrowEff(EV_RATETARG, mwID, it, it, it, it) != ABORT);
            Error("WEAPONTYPE_PROBE case=magicweapon item=%s type=%d istarget=%d ratetarg=%d",
                names[c], (int)it->Type, (int)tgt, (int)rate);

            /* Brand of Hatred: EV_ISTARGET walks the caster's pack, so the
               caster is a bare monster holding only this item. */
            Monster *mn = new Monster(holderID);
            mn->GainItem(it, true);
            int qualok = it->QualityOK(WQ_BANE);
            EventInfo b;
            b.Clear();
            b.EActor = mn;
            b.eID = bohID;
            int16 bist = TEFF(bohID)->Event(b, bohID, EV_ISTARGET);
            bool btgt = (bist == SHOULD_CAST_IT);
            bool brate = (ThrowEff(EV_RATETARG, bohID, it, it, it, it) != ABORT);
            EventInfo h;
            h.Clear();
            h.EActor = mn;
            h.ETarget = it;
            h.eID = bohID;
            TEFF(bohID)->Event(h, bohID, EV_MAGIC_HIT);
            Error("WEAPONTYPE_PROBE case=brand item=%s type=%d qualok=%d istarget=%d ratetarg=%d magichit=%d",
                names[c], (int)it->Type, qualok,
                (int)btgt, (int)brate, (int)it->HasQuality(WQ_BANE));
            mn->Remove(true);
            continue;
        }
        delete it;
    }

    /* Item::getShopCost prices a plussed missile in the high bracket. */
    for (int c = 1; c < 4; c++) {
        Item *it = mk(names[c]);
        if (!it) continue;
        int32 cost = it->getShopCost(NULL, NULL);
        int lvl = max(0, min(20, (int)it->ItemLevel(false)));
        double base = (double)TITEM(it->iID)->Cost;
        int32 hi = (int32)(max(1.0, (base + defCost[lvl] * 160L) / 100) / 3);
        int32 lo = (int32)(max(1.0, (base + defCost[lvl] * 70L) / 100) / 3);
        const char *br = (cost == hi) ? "hi" : (cost == lo) ? "lo" : "unknown";
        Error("WEAPONTYPE_PROBE case=price item=%s type=%d plus=%d cost=%d lvl=%d hi=%d lo=%d bracket=%s",
            names[c], (int)it->Type, (int)it->GetInherentPlus(), (int)cost,
            lvl, (int)hi, (int)lo, br);
        delete it;
    }
}

/* QItem::PurgeAllQualities (bane cleared) and Item::Damage (energy: no harm). */
static void itemCases(Player *p) {
    const char *names[3] = { "short bow", "crossbow bolt", "long sword" };
    for (int c = 0; c < 3; c++) {
        Item *it = mk(names[c]);
        if (!it) continue;
        it->SetBane(7);
        int before = it->GetBane();
        it->PurgeAllQualities();
        Error("WEAPONTYPE_PROBE case=purge item=%s type=%d bane_before=%d bane_after=%d",
            names[c], (int)it->Type, before, (int)it->GetBane());
        delete it;

        for (int en = 1; en >= 0; en--) {
        if (en == 0 && c != 2) continue;
        it = mk(names[c]);
        if (!it) continue;
        if (en) it->AddQuality(WQ_ENERGY);
        EventInfo e;
        e.Clear();
        e.EActor = p;
        e.DType = AD_FIRE;
        e.vDmg = 1;
        e.ignoreHardness = true;
        int hp0 = it->GetHP();
        it->Damage(e);
        Error("WEAPONTYPE_PROBE case=energy item=%s%s type=%d energy=%d hp_before=%d hp_after=%d unhurt=%d",
            names[c], en ? "" : "-plain", (int)it->Type,
            (int)it->HasQuality(WQ_ENERGY), hp0, (int)it->GetHP(),
            (int)(it->GetHP() == hp0));
        delete it;
        }
    }
}

/* Hezrou EVICTIM(EV_DAMAGE) halves slash and pierce from a weapon in either
   hand; the arrow is the attack, the bow is the launcher. */
static void hezrouCases() {
    rID hez = FIND("hezrou");
    const char *names[3] = { "sheaf arrow", "short bow", "long sword" };
    for (int c = 0; c < 3; c++) {
        Item *it = mk(names[c]);
        if (!hez || !it) {
            Error("WEAPONTYPE_PROBE case=hezrou item=%s INCONCLUSIVE missing resource", names[c]);
            delete it;
            continue;
        }
        EventInfo e;
        e.Clear();
        e.DType = AD_PIERCE;
        e.vDmg = 20;
        if (c == 1) e.EItem2 = it; else e.EItem = it;
        TMON(hez)->Event(e, hez, EVICTIM(EV_DAMAGE));
        Error("WEAPONTYPE_PROBE case=hezrou item=%s type=%d dmg_in=20 dmg_out=%d",
            names[c], (int)it->Type, (int)e.vDmg);
        delete it;
    }
}

/* Resource::GrantGear gives an NPC FT_EXOTIC_WEAPON for an exotic weapon, bow
   or hand crossbow. The drow carries a hand crossbow; the githzerai may carry
   a spiked chain, so it is tried up to 40 times. */
static void grantCases() {
    struct { const char *mon, *what; } C[2] = { { "drow", "hand crossbow" },
                                                { "githzerai", "spiked chain" } };
    for (int c = 0; c < 2; c++) {
        rID mid = FIND(C[c].mon);
        if (!mid) {
            Error("WEAPONTYPE_PROBE case=grant item=%s INCONCLUSIVE missing resource", C[c].what);
            continue;
        }
        int tries = 0, got = 0;
        for (; tries < (c ? 40 : 1) && !got; tries++) {
            Monster *mn = new Monster(mid);
            TMON(mid)->GrantGear(mn, mid, true);
            got = mn->HasStati(EXTRA_FEAT, FT_EXOTIC_WEAPON) ? 1 : 0;
            mn->Remove(true);
        }
        Error("WEAPONTYPE_PROBE case=grant item=%s exotic_feat=%d tries=%d",
            C[c].what, got, tries);
    }
}

/* The ground list sorts a mundane bow as junk, below a gem that lies farther
   off. The bow and the sword lie next to the player, the gem three or more
   squares away. ShowViewList is the real call: it rebuilds the list from the
   map with the true distances and sorts it, so the probe reads where each
   item landed. */
static void viewListCases(Player *p) {
    Map *mp = p->m;
    const char *names[3] = { "short bow", "long sword", "gold nugget" };
    const char *label[3] = { "bow", "sword", "gem" };
    Item *it[3] = { NULL, NULL, NULL };
    int n = 0;
    for (int r = 1; r <= 8 && n < 3; r++)
        for (int dy = -r; dy <= r && n < 3; dy++)
            for (int dx = -r; dx <= r && n < 3; dx++) {
                int x = p->x + dx, y = p->y + dy;
                if (max(abs(dx), abs(dy)) != r || !freeCell(mp, x, y))
                    continue;
                if (n < 2 ? r > 2 : r < 3)
                    continue;
                if (!(it[n] = mk(names[n], 0)))
                    continue;
                it[n]->PlaceAt(mp, x, y);
                p->CalcVision();
                if (!(p->Perceives(it[n], false) & ~PER_SHADOW)) {
                    it[n]->Remove(true);
                    it[n] = NULL;
                    continue;
                }
                n++;
            }
    if (n < 3) {
        Error("WEAPONTYPE_PROBE case=viewlist item=list INCONCLUSIVE only %d items placed in view", n);
        for (int i = 0; i < n; i++) it[i]->Remove(true);
        return;
    }
    TextTerm *t = (TextTerm *)p->MyTerm;
    t->ShowViewList();
    int pos[3] = { -1, -1, -1 }, listed = 0;
    for (int i = 0; i < t->WViewListCount; i++)
        for (int k = 0; k < 3; k++)
            if (t->WViewList[i].t == it[k]) {
                pos[k] = i;
                listed++;
            }
    int dist[3];
    for (int k = 0; k < 3; k++)
        dist[k] = max(abs(it[k]->x - p->x), abs(it[k]->y - p->y));
    for (int i = 0; i < 3; i++) it[i]->Remove(true);
    t->ResetWViewList();
    Error("WEAPONTYPE_PROBE case=viewlist item=list listed=%d pos_%s=%d pos_%s=%d pos_%s=%d dist_%s=%d dist_%s=%d dist_%s=%d gem_before_bow=%d gem_before_sword=%d",
        listed, label[0], pos[0], label[1], pos[1], label[2], pos[2],
        label[0], dist[0], label[1], dist[1], label[2], dist[2],
        (int)(pos[2] >= 0 && pos[0] >= 0 && pos[2] < pos[0]),
        (int)(pos[2] >= 0 && pos[1] >= 0 && pos[2] < pos[1]));
}

/* Kysul's gift check flags a bow the follower cannot use. The gift is random,
   so the real EV_GODPULSE runs many times and every gifted bow or missile is
   counted by whether the follower is proficient with it. */
static void kysulCases(Player *p) {
    rID kys = FIND("Kysul");
    if (!kys) {
        Error("WEAPONTYPE_PROBE case=kysul item=gift INCONCLUSIVE missing resource");
        return;
    }
    rID oldGod = p->GodID;
    int16 gn = theGame->GodNum(kys), oldFav = p->FavourLev[gn];
    const int8 autoMore = p->Options[OPT_AUTOMORE];
    p->Options[OPT_AUTOMORE] = 1;
    /* Kysul's messages blast the follower's INT unless INT is sustained. */
    p->GainPermStati(SUSTAIN, NULL, SS_MISC, A_INT, 3);
    p->GodID = kys;
    p->FavourLev[gn] = 9;
    std::set<hObj> had;
    for (Item *i = p->FirstInv(); i; i = p->NextInv()) had.insert(i->myHandle);
    int pulses = 2000, ranged = 0, notprof = 0, melee = 0, meleeNP = 0;
    for (int n = 0; n < pulses; n++) {
        EventInfo e;
        e.Clear();
        e.EActor = p;
        e.eID = kys;
        TGOD(kys)->Event(e, kys, EV_GODPULSE);
        for (Item *i = p->FirstInv(); i; i = p->NextInv()) {
            if (had.count(i->myHandle)) continue;
            had.insert(i->myHandle);
            if (i->isType(T_BOW) || i->isType(T_MISSILE)) {
                ranged++;
                if (p->WepSkill(i->iID) == WS_NOT_PROF) notprof++;
            } else if (i->isType(T_WEAPON)) {
                melee++;
                if (p->WepSkill(i->iID) == WS_NOT_PROF) meleeNP++;
            }
        }
    }
    p->GodID = oldGod;
    p->FavourLev[gn] = oldFav;
    p->RemoveStati(SUSTAIN, SS_MISC, A_INT, 3);
    p->Options[OPT_AUTOMORE] = autoMore;
    Error("WEAPONTYPE_PROBE case=kysul item=gift pulses=%d bow_gifts=%d notprof_bow_gifts=%d weapon_gifts=%d notprof_weapon_gifts=%d",
        pulses, ranged, notprof, melee, meleeNP);
}

/* Augment's menus are key-driven: the key script answers each prompt. Every
   other item in the pack is made unidentified for the call, so the item under
   test is the only candidate and its menu letter is always [a]. */
static void augmentCases(Player *p) {
    p->GainPermStati(INNATE_KIT, NULL, SS_MISC, SK_CRAFT);
    const char *names[3] = { "short bow", "crossbow bolt", "long sword" };
    for (int c = 0; c < 3; c++) {
        Item *it = mk(names[c]);
        if (!it) continue;
        it->MakeKnown(0xFF);
        std::vector<std::pair<Item *, uint16> > others;
        for (Item *o = p->FirstInv(); o; o = p->NextInv()) {
            others.push_back(std::make_pair(o, o->Known));
            o->Known = 0;
        }
        p->GainItem(it, true);
        EvReturn r = p->CraftItem(CA_WEAPONCRAFT + ABIL_VAL);
        for (size_t i = 0; i < others.size(); i++)
            others[i].first->Known = others[i].second;
        Error("WEAPONTYPE_PROBE case=augment item=%s returned=%d", names[c], (int)r);
        it->Remove(true);
    }
}

/* The sidebar prints ShowDamage lines for the wielded weapon. */
static void screenCases(Player *p, bool bow) {
    Item *it = mk(bow ? "short bow" : "long sword");
    if (!it) return;
    it->AddQuality(WQ_FLAMING);
    it->MakeKnown(0xFF);
    p->GainItem(it, true);
    /* A bow takes both hands: put down whatever is in them first. A sword
       is wielded over the pack's own weapon, so it asks no question. */
    for (int sl = SL_WEAPON; bow && sl >= SL_READY; sl--)
        if (Item *old = p->InSlot(sl)) {
            EventInfo t;
            t.Clear();
            t.EActor = p;
            t.EItem = old;
            p->TakeOff(t);
        }
    EventInfo e;
    e.Clear();
    e.EActor = p;
    e.EItem = it;
    e.EParam = SL_WEAPON;
    p->Wield(e);
    Error("WEAPONTYPE_PROBE case=screen item=%s wielded=%d flaming_known=%d",
        bow ? "short bow" : "long sword", (int)(p->InSlot(SL_WEAPON) == it),
        (int)it->KnownQuality(WQ_FLAMING));
}

void WeaponTypeProbe(Player *p)
{
    const char *mode = gMode();
    if (!*mode)
        return;
    if (!p) {
        Error("WEAPONTYPE_PROBE INCONCLUSIVE no player");
        return;
    }
    if (!strcmp(mode, "augment"))
        augmentCases(p);
    else if (!strcmp(mode, "kysul"))
        kysulCases(p);
    else if (!strcmp(mode, "screen-bow"))
        screenCases(p, true);
    else if (!strcmp(mode, "screen-sword"))
        screenCases(p, false);
    else {
        spellCases(p);
        itemCases(p);
        hezrouCases();
        grantCases();
        viewListCases(p);
    }
}
