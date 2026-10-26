/* inc-4reo: opt-in AutoPickupFloor reproduction; no ordinary-play effects.
   See tools/check_autopickup_packs.sh for controls and expected results. */
#define protected public
#include "Incursion.h"
#undef protected

static Container *appBag(Player *pl, int slot, const char *name) {
    Container *bag = (Container*)Item::Create(FIND(name));
    if (slot) {
        pl->Inv[slot] = bag->myHandle;
        bag->SetOwner(pl->myHandle);
    }
    return bag;
}

static bool appInsert(Player *pl, Container *bag, Item *it) {
    EventInfo e; e.Clear(); e.EActor = pl; e.EItem = bag; e.EItem2 = it;
    return bag->Insert(e, true) == DONE && it->GetParent() == bag;
}

static Item *appStack(Player *pl, Container *bag) {
    Item *it = Item::Create(FIND("long sword"));
    it->MakeKnown(0xff); it->Quantity = 3;
    return appInsert(pl, bag, it) ? it : NULL;
}

void AutoPickupPacksProbe(Player *pl) {
    const char *mode = getenv("INCURSION_AUTOPICKUP_PACKS_PROBE");
    static bool ran = false;
    if (!mode || ran) return;
    ran = true;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/autopickup-packs.log", (const char*)T1->IncursionDirectory);
    FILE *lg = fopen(path, "w");
    if (!lg) return;
    auto stop = [&](const char *why) {
        fprintf(lg, "INCONCLUSIVE %s\n", why); fclose(lg);
    };
    const char cs = *mode;
    fprintf(lg, "CASE %c\n", cs);
    if (!pl || !pl->m || cs < 'a' || cs > 'g' || mode[1]) {
        stop("invalid setup"); return;
    }
    Map *mp = pl->m;
    if (!mp->InBounds(10,10)) { stop("map too small"); return; }
    Thing *obj; int index;
    for (;;) {
        Thing *remove = NULL;
        MapIterate(mp,obj,index)
            if (obj != pl) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    mp->WriteTerra(10,10,FIND("floor"));
    pl->PlaceAt(mp,10,10);
    mp->At(10,10).Lit = true;
    for (int s=0; s<SL_LAST; ++s)
        if (pl->InSlot(s)) pl->InSlot(s)->Remove(false);
    pl->Options[OPT_AUTOPICKUP] = 2;
    pl->Options[OPT_AUTOMORE] = 1;
    Container *A = appBag(pl,SL_PACK,"medium backpack"), *B = NULL, *C = NULL;
    Item *sa = NULL, *sb = NULL, *sc = NULL;
    if (cs == 'c') {
        B = appBag(pl,0,"medium backpack");
        if (!appInsert(pl,A,B)) { stop("nested bag setup"); return; }
    } else if (cs != 'd' && cs != 'g')
        B = appBag(pl,SL_LSHOULDER,cs == 'e' ? "small backpack" : "medium backpack");
    if (cs == 'e') C = appBag(pl,SL_RSHOULDER,"medium backpack");
    const bool magic = cs == 'f' || cs == 'g';
    if (!magic) {
        if (cs == 'd') sa = appStack(pl,A);
        else sb = appStack(pl,B);
        if (C) sc = appStack(pl,C);
        if ((cs == 'd' && !sa) || (cs != 'd' && !sb) || (C && !sc)) {
            stop("stack setup"); return;
        }
    }
    if (cs == 'b') B->GainPermStati(LOCKED,B,SS_MISC);
    if (cs == 'f') {
        Item *ballast = Item::Create(FIND("long sword"));
        ballast->Quantity = 100;
        if (!appInsert(pl,A,ballast)) { stop("ballast setup"); return; }
    }
    Item *floor = Item::Create(FIND(magic ? "potion" : "long sword"));
    if (magic) { floor->MakeMagical(FIND("healing")); floor->Known = 0; }
    else floor->MakeKnown(0xff);
    floor->Quantity = 1;
    floor->PlaceAt(mp,10,10);
    const bool packrat = pl->HasFeat(FT_FASTER_THAN_THE_EYE);
    int fa = A->FitsNormal(floor,packrat);
    int fb = B ? B->FitsNormal(floor,packrat) : -1;
    int fc = C ? C->FitsNormal(floor,packrat) : -1;
    fprintf(lg,"SETUP fitsA=%d fitsB=%d fitsC=%d lockedB=%d nestedB=%d magic=%d known=%d weight=%d\n",
        fa,fb,fc,B && B->HasStati(LOCKED),B && B->GetParent()==A,
        floor->eID != 0,floor->isKnown(),floor->Weight(false));
    if (pl->isThreatened() || pl->HasStati(RAGING) || pl->HasMFlag(M_NOHANDS) ||
        floor->Weight(false)>1000 || floor->Weight()>pl->MaxPress() ||
        floor->HasStati(DROPPED,-1,pl) || floor->isIllusion() ||
        (sa && !(*sa == *floor)) || (sb && !(*sb == *floor)) || (sc && !(*sc == *floor)) ||
        (cs == 'e' ? (fb != Container::FITS_SIZE || fc != Container::FITS) : (B && fb != Container::FITS)) ||
        (cs == 'f' ? fa != Container::FITS_WEIGHT : fa != Container::FITS) ||
        (magic && (!floor->eID || floor->isKnown() || floor->PItemLevel(pl)<0 ||
            floor->isFlavorGodMark() || TEFF(floor->eID)->HasFlag(EF_MUNDANE)))) {
        stop("pickup prerequisites or candidate limits"); return;
    }
    const hObj fh = floor->myHandle;
    const bool wasPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    pl->Timeout = 0;
    pl->AutoPickupFloor();
    Item *remaining = (Item*)theRegistry->GetQuiet(fh);
    bool onFloor = remaining && remaining->m == mp && !remaining->Owner() &&
        remaining->x == 10 && remaining->y == 10;
    const char *where = onFloor ? "floor" : "other";
    if (sa && sa->Quantity == 4) where = "bagA";
    else if (sb && sb->Quantity == 4) where = "bagB";
    else if (sc && sc->Quantity == 4) where = "bagC";
    else if (remaining && remaining->GetParent() == A) where = "bagA";
    else if (remaining && B && remaining->GetParent() == B) where = "bagB";
    else if (remaining && C && remaining->GetParent() == C) where = "bagC";
    fprintf(lg,"RESULT where=%s stackA=%u stackB=%u stackC=%u floor=%d\n",where,
        sa ? (unsigned)sa->Quantity : 0,sb ? (unsigned)sb->Quantity : 0,
        sc ? (unsigned)sc->Quantity : 0,onFloor);
    fprintf(lg,"COMPLETE\n"); fclose(lg);
    theGame->PlayMode = wasPlay;
}
