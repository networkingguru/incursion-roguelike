/* inc-nm59: opt-in probe. Off unless INCURSION_OWNER_DAMAGE_PROBE is set.
   Called from Game::Play (src/Main.cpp); graded by
   tools/check_owner_damage_immune.sh. The player owns two items and damages
   each with AD_ACID, as EActor, with isTrap false and eID 0. Glass is immune
   to acid (MaterialHardness -1); iron is not. One OWNER_DMG_PROBE line per
   fact goes to errors.log through Error(). */
#include "Incursion.h"

struct OwnerDmgCase { const char *role; const char *base; bool sword; };

static int OwnerDmgRun(Player *pl, const OwnerDmgCase &c, int dmg, bool wantImmune) {
    Item *it = Item::Create(FIND(c.base));
    if (!it) {
        Error("OWNER_DMG_PROBE: INCONCLUSIVE -- no item %s", c.base);
        return -1;
    }
    if (c.sword) it->SetInherentPlus(0);
    pl->GainItem(it, true);
    hObj h = it->myHandle;
    const int hard = it->Hardness(AD_ACID);
    const int hp0 = it->GetHP();
    if (wantImmune && hard != -1) {
        Error("OWNER_DMG_PROBE: INCONCLUSIVE -- %s Hardness=%d, want -1", c.base, hard);
        return -1;
    }
    if (!wantImmune && (hard < 1 || hp0 <= dmg)) {
        Error("OWNER_DMG_PROBE: INCONCLUSIVE -- %s Hardness=%d hp=%d dmg=%d", c.base, hard, hp0, dmg);
        return -1;
    }
    ThrowDmg(EV_DAMAGE, AD_ACID, dmg, "owner damage probe", pl, it);
    Item *r = oItem(h);
    const bool gone = !r || (r->Flags & F_DELETE);
    const int hp1 = gone ? 0 : r->GetHP();
    const int lost = hp0 - hp1;
    const bool ok = wantImmune ? (!gone && lost == 0) : (!gone && lost == dmg);
    Error("OWNER_DMG_PROBE: role=%s item=%s hardness=%d vDmg=%d hp_before=%d hp_after=%d gone=%d lost=%d",
        c.role, c.base, hard, dmg, hp0, hp1, gone ? 1 : 0, lost);
    Error("OWNER_DMG_PROBE: %s %s", ok ? "PASS" : "FAIL",
        wantImmune ? "immune item HP unchanged" : "ordinary item lost the full vDmg");
    if (r && !(r->Flags & F_DELETE)) r->Remove(true);
    return ok ? 1 : 0;
}

void OwnerDamageProbe(Player *pl) {
    /* inc-nm59: off unless INCURSION_OWNER_DAMAGE_PROBE is set. */
    if (!getenv("INCURSION_OWNER_DAMAGE_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("OWNER_DMG_PROBE: INCONCLUSIVE -- no live player and map");
        return;
    }
    const OwnerDmgCase immune = { "immune", "viewing lens", false };
    const OwnerDmgCase plain  = { "ordinary", "long sword", true };
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    int a = OwnerDmgRun(pl, immune, 5, true);
    int b = OwnerDmgRun(pl, plain, 5, false);
    theGame->PlayMode = wasInPlay;
    if (a < 0 || b < 0) Error("OWNER_DMG_PROBE: INCONCLUSIVE");
    else if (a == 1 && b == 1) Error("OWNER_DMG_PROBE: ALL PASS");
    else Error("OWNER_DMG_PROBE: ALL FAIL");
}
