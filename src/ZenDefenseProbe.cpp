/* inc-0t9ol probe: the insight bonus Zen Defense adds to A_DEF, read after
   CalcValues, in several states. Off unless INCURSION_ZEN_DEFENSE_PROBE is set;
   called from Game::Play (src/Main.cpp). Reader: tools/check_zen_defense.sh.
   One line per case: ZEN_DEFENSE case=<name> enc=<n> armtype=<n> insight=<n>
   wis=<n>. Encumbrance is driven by the stack size of a real weapon in the
   ready hand; Mage Armour is the real effect's ADJUST_ARM stati. */
#define protected public
#include "Incursion.h"
#undef protected

static void zdEmit(Player *p, const char *name) {
    p->CalcValues();
    Error("ZEN_DEFENSE case=%s enc=%d armtype=%u insight=%d wis=%d", name,
        (int)p->Encumbrance(), (unsigned)p->getArmourType(true),
        (int)Creature::AttrAdj[A_DEF][BONUS_INSIGHT], (int)p->Mod(A_WIS));
}

/* Grow the stack until Encumbrance() reaches `want`; false if it never does. */
/* Put a real armor item in SL_ARMOUR (no wield prompt), as the ready-hand
   stack below is placed. Returns the item, or NULL. */
static Item *zdWear(Player *p, const char *name) {
    const rID id = FIND(name);
    Item *it = id ? Item::Create(id) : NULL;
    if (!it)
        return NULL;
    p->Inv[SL_ARMOUR] = it->myHandle;
    it->SetOwner(p->myHandle);
    return p->InSlot(SL_ARMOUR) == it ? it : NULL;
}

static bool zdLoad(Player *p, Item *it, int want) {
    for (int q = 1; q < 20000; q++) {
        it->SetQuantity(q);
        p->CalcValues();
        if ((int)p->Encumbrance() == want)
            return true;
        if ((int)p->Encumbrance() > want)
            return false;
    }
    return false;
}

void ZenDefenseProbe(Player *p) {
    /* inc-0t9ol */
    if (!getenv("INCURSION_ZEN_DEFENSE_PROBE"))
        return;
    if (!p || !p->HasFeat(FT_ZEN_DEFENSE) || p->InSlot(SL_ARMOUR)) {
        Error("ZEN_DEFENSE INCONCLUSIVE no Zen Defense feat or armor worn");
        return;
    }
    const rID magID = FIND("Mage Armour"), swID = FIND("long sword");
    if (!magID || !swID) {
        Error("ZEN_DEFENSE INCONCLUSIVE missing resource");
        return;
    }
    /* The fixture starts Light. Drop the whole pack so the control is None. */
    for (Item *o = p->FirstInv(); o; o = p->FirstInv())
        o->Remove(true);
    zdEmit(p, "bare");
    p->GainPermStati(ADJUST_ARM, NULL, SS_ENCH, A_ARM, 4, magID);
    zdEmit(p, "mage_armour");
    p->RemoveEffStati(magID);
    zdEmit(p, "bare_again");

    Item *it = Item::Create(swID);
    if (!it) {
        Error("ZEN_DEFENSE INCONCLUSIVE no item");
        return;
    }
    /* Wield asks the player a question, so place the stack as BeltPotionProbe
       does. The pack was emptied above, so the ready hand is free. */
    p->Inv[SL_READY] = it->myHandle;
    it->SetOwner(p->myHandle);
    if (p->InSlot(SL_READY) != it) {
        Error("ZEN_DEFENSE INCONCLUSIVE sword not in ready hand");
        return;
    }
    static const struct { const char *name; int enc; } steps[] = {
        { "light", EN_LIGHT }, { "moderate", EN_MODERATE },
        { "heavy", EN_HEAVY } };
    for (int i = 0; i < 3; i++) {
        if (!zdLoad(p, it, steps[i].enc)) {
            Error("ZEN_DEFENSE INCONCLUSIVE cannot reach %s", steps[i].name);
            return;
        }
        zdEmit(p, steps[i].name);
    }
    /* Armor cases. The fixture's Wis modifier is +1, where full and half are
       equal, so raise the BASE Wisdom to 20 (modifier +5): full 5, half 3. */
    it->Remove(true);
    p->BAttr[A_WIS] = 20;
    const rID spID = FIND("Spirit Armour");
    if (!spID) {
        Error("ZEN_DEFENSE INCONCLUSIVE missing Spirit Armour");
        return;
    }
    zdEmit(p, "bare_wis5");
    p->GainPermStati(ADJUST_ARM, NULL, SS_ENCH, A_ARM, 4, spID);
    zdEmit(p, "spirit_armour");
    p->RemoveEffStati(spID);
    p->GainPermStati(ADJUST_ARM, NULL, SS_ENCH, A_ARM, 4, magID);
    zdEmit(p, "mage_armour_wis5");
    p->RemoveEffStati(magID);
    Item *ar = zdWear(p, "cord armour");
    if (!ar) {
        Error("ZEN_DEFENSE INCONCLUSIVE no light armor worn");
        return;
    }
    zdEmit(p, "worn_light");
    p->GainPermStati(ADJUST_ARM, NULL, SS_ENCH, A_ARM, 4, magID);
    zdEmit(p, "worn_light_plus_mage");
    p->RemoveEffStati(magID);
    ar->Remove(true);
    ar = zdWear(p, "hide armour");
    if (!ar) {
        Error("ZEN_DEFENSE INCONCLUSIVE no medium armor worn");
        return;
    }
    zdEmit(p, "worn_medium");
    Error("ZEN_DEFENSE COMPLETE");
}
