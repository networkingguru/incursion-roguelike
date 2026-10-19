/* inc-f99j: opt-in reproduction, enabled by INCURSION_AUTOLOOT_PACKS_PROBE=a|b|c|d.
   Stages containers in inventory slots, drops a long sword at the player's
   feet and runs the AutoLoot macro twice. The key script supplies the menu
   keys (SPACE ENTER) and escapes any inventory screen. See
   tools/check_autoloot_packs.sh. */
#define protected public
#include "Incursion.h"
#undef protected

static Item *alpBag(Player *pl, int slot, const char *name, bool locked) {
    Item *old = pl->InSlot(slot);
    if (old) old->Remove(false);
    Item *bag = Item::Create(FIND(name));
    pl->Inv[slot] = bag->myHandle;
    bag->SetOwner(pl->myHandle);
    if (locked) bag->GainPermStati(LOCKED, bag, SS_MISC);
    return bag;
}

static const char *alpWhere(Player *pl, Item *it, Item *a, Item *b, Item *c) {
    if (!it->Owner()) return "floor";
    if (pl->InSlot(SL_INAIR) == it) return "inair";
    if (a && it->GetParent() == a) return "bagA";
    if (b && it->GetParent() == b) return "bagB";
    if (c && it->GetParent() == c) return "bagC";
    return "other";
}

void AutoLootPacksProbe(Player *pl) {
    const char *mode = getenv("INCURSION_AUTOLOOT_PACKS_PROBE");
    static bool ran = false;
    if (!mode || ran) return;
    ran = true;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/autoloot-packs.log", (const char*)T1->IncursionDirectory);
    FILE *lg = fopen(path, "w");
    if (!lg) return;
    const char cs = *mode;
    fprintf(lg, "CASE %c\n", cs);
    if (!pl || !pl->m || cs < 'a' || cs > 'd') {
        fprintf(lg, "INCONCLUSIVE invalid setup\n"); fclose(lg); return;
    }
    Map *mp = pl->m;
    int X = -1, Y = -1;
    for (int y = 1; y < mp->SizeY()-1 && X < 0; ++y)
        for (int x = 1; x < mp->SizeX()-1 && X < 0; ++x)
            if (!mp->SolidAt(x,y) && !mp->FFeatureAt(x,y) && !mp->FirstAt(x,y)) {
                bool near = false; Thing *t; int i;
                MapIterate(mp,t,i)
                    if (t->isCreature() && t != pl && abs(t->x-x) <= 8 && abs(t->y-y) <= 8)
                        near = true;
                if (!near) { X = x; Y = y; }
            }
    if (X < 0) { fprintf(lg, "INCONCLUSIVE no isolated floor\n"); fclose(lg); return; }
    /* No container the character carries may be a candidate but ours. */
    for (int s = 1; s < SL_LAST; ++s)
        if (pl->InSlot(s) && pl->InSlot(s)->isType(T_CONTAIN)) pl->InSlot(s)->Remove(false);
    Item *A = NULL, *B = NULL, *C = NULL;
    A = alpBag(pl, SL_PACK, "small backpack", false);
    if (cs == 'a') B = alpBag(pl, SL_BELT1, "medium backpack", false);
    if (cs == 'b') {
        B = alpBag(pl, SL_BELT1, "medium backpack", true);
        C = alpBag(pl, SL_BELT2, "medium backpack", false);
    }
    if (cs == 'c') {
        B = Item::Create(FIND("medium backpack"));
        EventInfo e; e.Clear(); e.EActor = pl; e.EItem = A; e.EItem2 = B;
        ((Container*)A)->Insert(e, true);
    }
    if (cs == 'd') B = alpBag(pl, SL_BELT1, "small backpack", false);
    Item *sword = Item::Create(FIND("long sword"));
    pl->PlaceAt(mp, X, Y);
    sword->PlaceAt(mp, X, Y);
    mp->At(X,Y).Lit = true;
    pl->Options[OPT_AUTOMORE] = 1;
    const bool wasPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    fprintf(lg, "SETUP sword_size=%d bagA_maxsize=%d locked_B=%d\n", (int)sword->Size(),
        (int)TITEM(A->iID)->u.c.MaxSize, (int)(B && B->HasStati(LOCKED)));
    TextTerm *term = (TextTerm*)pl->MyTerm;
    term->MsgHistory[0] = 0;
    pl->Timeout = 0;
    // The same start-up the F8 key performs (Player.cpp), then the same
    // per-turn call Creature::ChooseAction makes while ACTING holds.
    RES(FIND("AutoLoot"))->PEvent(EV_INITIALIZE, pl, FIND("AutoLoot"), 0);
    pl->GainPermStati(ACTING, NULL, SS_MISC, EV_MACRO, 0, FIND("AutoLoot"));
    for (int n = 0; n < 6 && pl->HasStati(ACTING); ++n) {
        pl->Timeout = 0;
        if (ThrowEff(EV_MACRO, FIND("AutoLoot"), pl) == ABORT)
            pl->RemoveStati(ACTING);
    }
    pl->RemoveStati(ACTING);
    fprintf(lg, "MESSAGES_BEGIN\n%sMESSAGES_END\n", term->MsgHistory);
    fprintf(lg, "RESULT where=%s taken=%d toolarge=%d canonlyhold=%d locked=%d\n",
        alpWhere(pl, sword, A, B, C),
        strstr(term->MsgHistory, "taken.") != NULL,
        strstr(term->MsgHistory, "too large") != NULL,
        strstr(term->MsgHistory, "can only hold") != NULL,
        strstr(term->MsgHistory, "locked") != NULL);
    fprintf(lg, "COMPLETE\n");
    fclose(lg);
    theGame->PlayMode = wasPlay;
}
