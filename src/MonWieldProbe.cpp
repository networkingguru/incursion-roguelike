/* inc-qaav4: opt-in probe for Monster::Wield's alignment drain. Off unless
   INCURSION_MONWIELD_PROBE is set. Called from Game::Play (src/Main.cpp);
   graded by tools/check_monwield_drain.sh. No wizard path makes a monster
   wield a chosen item. Each monster is made good by an ALIGNMENT stati, so
   the unholy long sword opposes it. The troll survives the two
   levels; the kobold (CR below 2) dies of them. One Error() line each. */
#include "Incursion.h"

static void WieldUnholy(Player *pl, const char *name, const char *label)
{
    Monster *mn;
    Item *it;
    int before, after, dx, dy;
    int16 nx, ny, tx = -1, ty = -1;
    rID mid = FIND(name);

    if (!mid) {
        Error("MONWIELD_PROBE %s INCONCLUSIVE -- no monster %s", label, name);
        return;
    }
    for (dx = -2; dx <= 2 && tx < 0; ++dx)
        for (dy = -2; dy <= 2 && tx < 0; ++dy) {
            nx = pl->x + dx; ny = pl->y + dy;
            if (!pl->m->InBounds(nx, ny) || pl->m->SolidAt(nx, ny) ||
                pl->m->FCreatureAt(nx, ny))
                continue;
            tx = nx; ty = ny;
        }
    if (tx < 0) {
        Error("MONWIELD_PROBE %s INCONCLUSIVE -- no open floor", label);
        return;
    }
    mn = new Monster(mid);
    TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    mn->PlaceAt(pl->m, tx, ty, true);
    mn->Initialize(true);
    mn->GainPermStati(ALIGNMENT, NULL, SS_MISC, AL_GOOD);
    it = Item::Create(FIND("long sword"));
    it->AddQuality(WQ_UNHOLY);
    if (!mn->isMType(MA_GOOD) || !mn->opposesAlignmentOf(it)) {
        Error("MONWIELD_PROBE %s INCONCLUSIVE -- monster not opposed", label);
        return;
    }
    before = mn->SumStatiMag(ADJUST_DMG, A_AID);
    ThrowVal(EV_WIELD, SL_WEAPON, mn, NULL, it);
    after = mn->SumStatiMag(ADJUST_DMG, A_AID);
    Error("MONWIELD_PROBE %s before=%d after=%d died=%d", label, before,
        after, (int)mn->isDead());
}

/* Entry point; serves inc-qaav4. */
void MonWieldProbe(Player *pl)
{
    bool wasInPlay;

    if (!getenv("INCURSION_MONWIELD_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("MONWIELD_PROBE INCONCLUSIVE -- no live player and map");
        return;
    }
    wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    WieldUnholy(pl, "troll", "survivor");
    WieldUnholy(pl, "kobold", "victim");
    theGame->PlayMode = wasInPlay;
}
