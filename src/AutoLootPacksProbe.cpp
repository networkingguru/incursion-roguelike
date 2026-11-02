/* inc-f99j: opt-in reproduction, enabled by INCURSION_AUTOLOOT_PACKS_PROBE=a..h.
   Cases e-h (inc-j12i0): the Pack-slot bag has room and a second slot-held bag
   holds a matching long-sword stack (e floor item, f item taken out of a
   chest, g the matching bag refuses on weight, h no match anywhere).
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
    if (!pl || !pl->m || cs < 'a' || cs > 'h') {
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
    Item *stack = NULL, *chest = NULL;
    if (cs >= 'e') {
        A = alpBag(pl, SL_PACK, "medium backpack", false);
        B = alpBag(pl, SL_BELT1, "medium backpack", false);
        sword->MakeKnown(0xff);
        sword->Quantity = 1;
        stack = Item::Create(FIND(cs == 'h' ? "dagger" : "long sword"));
        stack->MakeKnown(0xff);
        stack->Quantity = (cs == 'g') ? 100 : 3;
        EventInfo e; e.Clear(); e.EActor = pl; e.EItem = B; e.EItem2 = stack;
        if (((Container*)B)->Insert(e, true) != DONE || stack->GetParent() != B) {
            fprintf(lg, "INCONCLUSIVE stack setup\n"); fclose(lg); return;
        }
        if ((cs != 'h') != (*stack == *sword) ||
            (cs == 'g' ? ((Container*)B)->FitsNormal(sword, pl->HasFeat(FT_FASTER_THAN_THE_EYE)) != Container::FITS_WEIGHT
                       : ((Container*)B)->FitsNormal(sword, pl->HasFeat(FT_FASTER_THAN_THE_EYE)) != Container::FITS) ||
            ((Container*)A)->FitsNormal(sword, pl->HasFeat(FT_FASTER_THAN_THE_EYE)) != Container::FITS) {
            fprintf(lg, "INCONCLUSIVE match or limits\n"); fclose(lg); return;
        }
    }
    pl->PlaceAt(mp, X, Y);
    if (cs == 'f') {
        chest = Item::Create(FIND("large oak chest"));
        EventInfo e; e.Clear(); e.EActor = pl; e.EItem = chest; e.EItem2 = sword;
        if (((Container*)chest)->Insert(e, true) != DONE || sword->GetParent() != chest) {
            fprintf(lg, "INCONCLUSIVE chest setup\n"); fclose(lg); return;
        }
        chest->PlaceAt(mp, X, Y);
    } else
        sword->PlaceAt(mp, X, Y);
    const hObj swh = sword->myHandle;
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
    /* A merged item lingers flagged for deletion until the turn ends, and the
       macro would take it again, so cases e-h run one macro call. */
    for (int n = 0; n < (cs >= 'e' ? 1 : 6) && pl->HasStati(ACTING); ++n) {
        pl->Timeout = 0;
        if (ThrowEff(EV_MACRO, FIND("AutoLoot"), pl) == ABORT)
            pl->RemoveStati(ACTING);
    }
    pl->RemoveStati(ACTING);
    fprintf(lg, "MESSAGES_BEGIN\n%sMESSAGES_END\n", term->MsgHistory);
    if (cs >= 'e') {
        Item *cur = (Item*)theRegistry->GetQuiet(swh);
        const char *w = (cs != 'h' && stack->Quantity > (cs == 'g' ? 100u : 3u)) ? "bagB" :
            (cur ? alpWhere(pl, cur, A, B, NULL) : "gone");
        fprintf(lg, "RESULT where=%s taken=%d stackB=%u\n", w,
            strstr(term->MsgHistory, "taken.") != NULL, (unsigned)stack->Quantity);
        fprintf(lg, "COMPLETE\n");
        fclose(lg);
        theGame->PlayMode = wasPlay;
        return;
    }
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
