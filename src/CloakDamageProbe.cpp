/* inc-7s7n: opt-in cursed cloak damage reproduction (INCURSION_CLOAK_DMG_PROBE).
   Caller: Game::Play (src/Main.cpp). Reader: tools/check_cloak_damage_live.sh.
   A real cloak carrying the real effect is worn through EV_WIELD; fixed hits
   go through the real EV_DAMAGE and the HP lost is logged. */
#include "Incursion.h"

static const int HIT = 20;

/* HP lost to one hit of 'dmg' of type 'dt'. */
static int Hit(Player *p, Creature *actor, int8 dt) {
    int16 mHP = p->mHP;
    p->mHP += 2000;
    p->cHP = p->mHP;
    ThrowDmg(EV_DAMAGE, dt, HIT, "probe", actor, p);
    int lost = p->mHP - p->cHP;
    p->mHP = mHP;
    p->cHP = p->mHP;
    return lost;
}

static void Measure(Player *p, Creature *actor, const char *phase) {
    p->RemoveStati(RESIST);
    int cold = Hit(p, actor, AD_COLD), fire = Hit(p, actor, AD_FIRE);
    Error("CLOAK_DMG dmg phase=%s hit=%d cold=%d fire=%d", phase, HIT, cold, fire);
}

/* Wear a new cloak with 'effect'; logs whether the TRAP_EVENT stati arrived. */
static Item *Wear(Player *p, rID base, rID effect, const char *phase) {
    Item *c = Item::Create(base);
    c->MakeMagical(effect);
    c->MakeKnown(0xFF);
    c->IFlags &= ~IF_CURSED;   /* so the probe can take it off; the stati grant is unchanged */
    p->GainItem(c, false);
    SetSilence();
    ThrowVal(EV_WIELD, SL_CLOAK, p, NULL, c);
    UnsetSilence();
    int worn = (p->InSlot(SL_CLOAK) == c) ? 1 : 0;
    int n = 0, match = 0;
    StatiIterNature(p, TRAP_EVENT)
        n++;
        if (S->eID == effect && S->Mag == EVICTIM(EV_DAMAGE)) match++;
    StatiIterEnd(p)
    Error("CLOAK_DMG setup phase=%s worn=%d trap_stati=%d victim_damage_stati=%d", phase, worn, n, match);
    return c;
}

/* Destroying the worn cloak runs EV_LOSEITEM, which removes the granted stati. */
static void Doff(Player *p, Item *c) {
    hObj h = c->myHandle;
    c->Remove(true);
    int n = 0;
    StatiIterNature(p, TRAP_EVENT) n++; StatiIterEnd(p)
    Error("CLOAK_DMG doff gone=%d trap_stati=%d", oItem(h) ? 0 : 1, n);
    if (n) Error("CLOAK_DMG INCONCLUSIVE stati outlived the cloak");
}

/* inc-7s7n: off unless INCURSION_CLOAK_DMG_PROBE is set. */
void CloakDamageProbe(Player *p) {
    if (!getenv("INCURSION_CLOAK_DMG_PROBE")) return;
    Error("CLOAK_DMG setup begin");
    rID cloak = FIND("cloak"), frost = FIND("Frostbite"), fire = FIND("Fireburn"), kob = FIND("kobold");
    if (!p || !p->m || !cloak || !frost || !fire || !kob) {
        Error("CLOAK_DMG INCONCLUSIVE missing scene/resource"); return;
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
    if (x < 0) { Error("CLOAK_DMG INCONCLUSIVE no free cell"); return; }
    bool playing = theGame->PlayMode;
    theGame->PlayMode = true;
    int8 more = p->Options[OPT_AUTOMORE];
    p->Options[OPT_AUTOMORE] = 1;
    if (Item *old = p->InSlot(SL_CLOAK)) {
        EventInfo t; t.Clear(); t.EActor = p; t.EItem = old;
        p->TakeOff(t);
    }
    if (p->InSlot(SL_CLOAK)) { Error("CLOAK_DMG INCONCLUSIVE slot not empty"); return; }

    Monster *actor = new Monster(kob);
    actor->PlaceAt(p->m, x, y);
    actor->Initialize(true);

    Measure(p, actor, "none");
    Item *c = Wear(p, cloak, frost, "frostbite");
    Measure(p, actor, "frostbite");
    Doff(p, c);
    c = Wear(p, cloak, fire, "fireburn");
    Measure(p, actor, "fireburn");
    Doff(p, c);
    Error("CLOAK_DMG done");
    actor->Remove(true);
    p->Options[OPT_AUTOMORE] = more;
    theGame->PlayMode = playing;
}
