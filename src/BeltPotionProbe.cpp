/* inc-s1m5: diagnostic only, enabled by INCURSION_BELT_POTION_PROBE=a|b|c|d.
   Follows DoorPickProbe's real-event technique. Each case gets a fresh process.
   No match fields of a natural potion are normalized. */
// Match DoorPickProbe's translation-unit-only access to diagnostic fields.
#define protected public
#include "Incursion.h"
#undef protected

static FILE *bpLog;

static void bpDump(const char *stage, const char *role, Item *it) {
    fprintf(bpLog, "ITEM stage=%s role=%s handle=%d Type=%d iID=%d eID=%d Plus=%d cHP=%d IFlags=%u Flavor=%d GenNum=%d Known=%u Quantity=%u\n",
        stage, role, (int)it->myHandle, (int)it->Type, (int)it->iID,
        (int)it->eID, (int)it->Plus, (int)it->cHP, (unsigned)it->IFlags,
        (int)it->Flavor, (int)it->GenNum, (unsigned)it->Known, (unsigned)it->Quantity);
    int n = 0;
    StatiIter(it)
        fprintf(bpLog, "STAT stage=%s role=%s Nature=%u Val=%d Mag=%d Duration=%d Source=%u CLev=%u Dis=%u Once=%u eID=%d h=%d\n",
            stage, role, S->Nature, S->Val, S->Mag, S->Duration, S->Source,
            S->CLev, S->Dis, S->Once, (int)S->eID, (int)S->h);
        ++n;
    StatiIterEnd(it)
    fprintf(bpLog, "STAT_END stage=%s role=%s count=%d\n", stage, role, n);
    fflush(bpLog);
}

static Item *bpPotion() {
    Item *it = Item::Create(FIND("potion"));
    it->MakeMagical(FIND("healing"));
    return it;
}

static void bpCompare(const char *stage, Item *belt, Item *floor) {
    bpDump(stage, "belt", belt);
    bpDump(stage, "floor", floor);
    fprintf(bpLog, "MATCH stage=%s equal=%d ignored_IFlags=%u LOOT_CLAIM=%d\n",
        stage, *belt == *floor, unsigned(IF_WORN|IF_INTUITED|IF_DECIPHERED), LOOT_CLAIM);
    // A detached copy tests the claim alone; the real floor item is untouched.
    if (floor->HasStati(LOOT_CLAIM)) {
        Item *copy = new Item(floor);
        copy->SetOwner(0);
        // Item's copy constructor copies stati but not their reverse links.
        StatiIter(copy)
            if (S->h && S->h != copy->myHandle)
                oThing(S->h)->backRefs.Add(copy->myHandle);
        StatiIterEnd(copy)
        copy->RemoveStati(LOOT_CLAIM);
        fprintf(bpLog, "COUNTERFACTUAL stage=%s without_claim_equal=%d\n", stage, *belt == *copy);
        copy->Remove(true);
    }
    fflush(bpLog);
}

void BeltPotionProbe(Player *pl) {
    // inc-s1m5: this reproduction never runs during ordinary play.
    const char *mode = getenv("INCURSION_BELT_POTION_PROBE");
    static bool ran = false;
    if (!mode || ran) return;
    ran = true;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/belt-potion.log", (const char*)T1->IncursionDirectory);
    bpLog = fopen(path, "w");
    if (!bpLog) return;
    const char c = *mode;
    fprintf(bpLog, "CASE %c\n", c);
    auto stop = [&](const char *reason) {
        fprintf(bpLog, "INCONCLUSIVE %s\n", reason);
        fclose(bpLog); bpLog = NULL;
    };
    if (!pl || !pl->m || c < 'a' || c > 'd') { stop("invalid setup"); return; }
    Map *mp = pl->m;
    Item *belt = NULL, *floor = NULL;
    if (c == 'd') {
        for (Item *it = pl->FirstInv(); it; it = pl->NextInv())
            if (it->Type == T_POTION && it->eID == FIND("healing")) { belt = it; break; }
        Thing *t; int i;
        MapIterate(mp, t, i)
            if (t->Type == T_POTION && !((Item*)t)->Owner() &&
                ((Item*)t)->eID == FIND("healing")) { floor = (Item*)t; break; }
        fprintf(bpLog, "ORIGIN belt=loaded_character_starting_gear floor=loaded_dungeon_floor depth=%d\n", mp->Depth);
        if (!belt || !floor) { stop("natural healing potion missing from inventory or map"); return; }
        fprintf(bpLog, "NATURAL floor_x=%d floor_y=%d\n", floor->x, floor->y);
    } else {
        belt = bpPotion(); floor = bpPotion(); belt->Quantity = 3;
        fprintf(bpLog, "ORIGIN belt=independent_Create_MakeMagical floor=independent_Create_MakeMagical\n");
    }
    // Relocate the scene only; preserve every potion match field.
    int X = -1, Y = -1;
    for (int y = 1; y < mp->SizeY()-1 && X < 0; ++y)
        for (int x = 1; x < mp->SizeX()-2 && X < 0; ++x) {
            if (mp->SolidAt(x,y) || mp->SolidAt(x+1,y) ||
                mp->FFeatureAt(x,y) || mp->FFeatureAt(x+1,y) ||
                mp->FirstAt(x,y) || mp->FirstAt(x+1,y)) continue;
            bool near = false; Thing *t; int i;
            MapIterate(mp,t,i)
                if (t->isCreature() && t != pl &&
                    abs(t->x-x) <= 8 && abs(t->y-y) <= 8) near = true;
            if (!near) { X=x; Y=y; }
        }
    if (X < 0) { stop("no isolated adjacent floor squares"); return; }
    belt->Remove(false);
    if (pl->InSlot(SL_BELT1)) pl->InSlot(SL_BELT1)->Remove(false);
    pl->Inv[SL_BELT1] = belt->myHandle; belt->SetOwner(pl->myHandle);
    floor->Remove(false);
    pl->PlaceAt(mp, X, Y);
    mp->At(X,Y).Lit = mp->At(X+1,Y).Lit = true;
    pl->Options[OPT_AUTOPICKUP] = 1;
    pl->Options[OPT_AUTOMORE] = 1;
    const bool wasPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    if (c == 'c') {
        Monster *mon = new Monster(FIND("kobold"));
        mon->PlaceAt(mp,X+1,Y); mon->Initialize(true);
        mon->GainItem(floor);
        ThrowDmg(EV_DAMAGE, AD_BLUNT, 10000, "belt potion reproduction", pl, mon);
        Thing *claimant = floor->GetStatiObj(LOOT_CLAIM);
        fprintf(bpLog, "KILL dead=%d claim=%d claimant=%d player=%d floor_on_map=%d\n",
            mon->isDead(), floor->HasStati(LOOT_CLAIM),
            claimant ? (int)claimant->myHandle : 0, (int)pl->myHandle,
            floor->m == mp && !floor->Owner());
        fprintf(bpLog, "DROP_ORIGIN probe_created_potion_carried_by_spawned_kobold_killed_by_player_EV_DAMAGE\n");
    } else floor->PlaceAt(mp,X+1,Y);
    const unsigned before = belt->Quantity, amount = floor->Quantity;
    const hObj fh = floor->myHandle;
    bpCompare("before",belt,floor);
    fprintf(bpLog, "GUARDS autopickup=%d threatened=%d raging=%d nohands=%d dropped=%d weight=%d\n",
        pl->Opt(OPT_AUTOPICKUP),pl->isThreatened(),pl->HasStati(RAGING),
        pl->HasMFlag(M_NOHANDS),floor->HasStati(DROPPED,-1,pl),floor->Weight(false));
    pl->Timeout = 0;
    TextTerm *term = (TextTerm*)pl->MyTerm;
    term->MsgHistory[0] = 0;
    EvReturn walk = ThrowDir(EV_MOVE,EAST,pl);
    pl->AutoPickupFloor();
    int messages = 0;
    for (const char *s = term->MsgHistory; (s = strstr(s,"AutoPickup:")); ++s) ++messages;
    fprintf(bpLog, "MESSAGES_BEGIN\n%sMESSAGES_END\n", term->MsgHistory);
    fprintf(bpLog, "AUTO walk=%d moved=%d messages=%d before=%u after=%u expected=%u inair=%d\n",
        walk, pl->x == X+1 && pl->y == Y, messages, before,
        (unsigned)belt->Quantity, before+amount, (int)pl->Inv[SL_INAIR]);
    if (c == 'b' || c == 'c' || c == 'd') {
        if (belt->Quantity == before+amount) {
            // A passing walk consumed the item. Use a fresh plain counterpart
            // to independently exercise manual pickup in case b.
            if (c == 'b') {
                floor = bpPotion(); floor->PlaceAt(mp,pl->x,pl->y);
                fprintf(bpLog, "MANUAL_ORIGIN fresh_independent_Create_MakeMagical_after_successful_auto\n");
            } else floor = NULL;
        } else floor = (Item*)theRegistry->GetQuiet(fh);
        if (floor) {
            bpCompare("manual",belt,floor);
            const unsigned mb = belt->Quantity, mq = floor->Quantity;
            pl->GainPermStati(ACTING,NULL,SS_MISC,EV_PICKUP,0,FIND("AutoLoot"));
            EvReturn pick = Throw(EV_PICKUP,pl,NULL,floor);
            pl->RemoveStati(ACTING);
            fprintf(bpLog, "MANUAL result=%d before=%u after=%u expected=%u inair=%d\n",
                pick,mb,(unsigned)belt->Quantity,mb+mq,(int)pl->Inv[SL_INAIR]);
            if (pl->InSlot(SL_INAIR)) bpCompare("inair",belt,pl->InSlot(SL_INAIR));
        }
    }
    bpDump("after","belt",belt);
    fprintf(bpLog, "COMPLETE\n");
    fclose(bpLog); bpLog = NULL;
    theGame->PlayMode = wasPlay;
}
