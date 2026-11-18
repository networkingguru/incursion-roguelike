/* inc-rk030: opt-in oracle for "eating restores fatigue", enabled by
   INCURSION_EAT_FATIGUE_PROBE=1. Feeds food to the loaded character through
   Food::Eat and prints one EATFAT_PROBE line per case. See
   tools/check_eat_fatigue.sh. Expected values come from the item's Nutrition
   in lib/, not from the code under test. */
#define protected public
#include "Incursion.h"
#undef protected

static bool eatfatArmed = false;

/* TextTerm::yn asks this first; 0 means "not mine". Armed only in the probe. */
int EatFatigueProbeKey(const char *msg) {
    if (!eatfatArmed) return 0;
    return strncmp(msg,"Stop eating",11) == 0 ? 'y' : 'n';
}

static Food *efFood(Player *pl, const char *name) {
    Food *f = (Food *)Item::Create(FIND(name));
    if (f) pl->GainItem(f,false);
    return f;
}

/* Eat one whole item (20 bites). The item is deleted when the meal finishes. */
static bool efTold = false; /* "You feel less tired." printed during the last meal */
static void efMeal(Player *pl, Food *f) {
    TextTerm *term = (TextTerm*)pl->MyTerm;
    term->MsgHistory[0] = 0;
    EventInfo e; e.Clear();
    e.EActor = pl; e.EItem = f; e.EMap = pl->m;
    for (int bite = 0; bite < 20; ++bite) f->Eat(e);
    efTold = strstr(term->MsgHistory,"You feel less tired.") != NULL;
}

static int efFails = 0;
static void efReport(const char *name, int before, int after, int expect) {
    /* the message is printed exactly when fatigue rose */
    const bool pass = after == expect && efTold == (after > before);
    if (!pass) ++efFails;
    Error("EATFAT_PROBE: %s before=%d after=%d expect=%d told=%d %s",
          name,before,after,expect,(int)efTold,pass ? "PASS" : "FAIL");
}

void EatFatigueProbe(Player *pl) {
    if (!getenv("INCURSION_EAT_FATIGUE_PROBE")) return;
    if (!pl || !pl->m || !FIND("food ration") || !FIND("apple")
        || !FIND("pile of fresh food")) {
        Error("EATFAT_PROBE: setup INCONCLUSIVE missing player/map/resources");
        return;
    }
    const bool oldPlay = theGame->PlayMode;
    const int oldFP = pl->cFP, oldOpt = pl->Options[OPT_NO_FATIGUE];
    const int oldHunger = pl->GetStatiDur(HUNGER);
    theGame->PlayMode = true;
    pl->Options[OPT_NO_FATIGUE] = 0;
    pl->CalcValues();
    const int mx = pl->Attr[A_FAT];
    if (mx < 6) {
        Error("EATFAT_PROBE: setup INCONCLUSIVE maximum fatigue %d is below 6",mx);
        theGame->PlayMode = oldPlay;
        return;
    }
    eatfatArmed = true;

    /* (a) started below satiated: restores max(1,nutrition/10). */
    struct { const char *label, *item; } rows[] = {
        {"restore-ration","food ration"}, {"restore-fresh-food","pile of fresh food"},
        {"restore-apple","apple"}};
    for (int i = 0; i < 3; ++i) {
        Food *f = efFood(pl,rows[i].item);
        const int nut = TITEM(FIND(rows[i].item))->Nutrition;
        pl->SetStatiDur(HUNGER,-1,NULL,500);
        pl->cFP = mx - 5;
        const int before = pl->cFP;
        efMeal(pl,f);
        efReport(rows[i].label,before,pl->cFP,min(mx,before + max(1,nut / 10)));
    }

    /* (b) the restore stops at the maximum, and at the maximum changes nothing. */
    {
        Food *f = efFood(pl,"food ration");
        pl->SetStatiDur(HUNGER,-1,NULL,500);
        pl->cFP = mx - 1;
        const int before = pl->cFP;
        efMeal(pl,f);
        efReport("cap-near-max",before,pl->cFP,mx);
        f = efFood(pl,"food ration");
        pl->SetStatiDur(HUNGER,-1,NULL,500);
        pl->cFP = mx;
        efMeal(pl,f);
        efReport("cap-at-max",mx,pl->cFP,mx);
    }

    /* (c) started satiated (2880 is SATIATED: above CONTENT, not above SATIATED). */
    {
        Food *f = efFood(pl,"food ration");
        pl->SetStatiDur(HUNGER,-1,NULL,2880);
        pl->cFP = mx - 5;
        const int before = pl->cFP;
        const int state = pl->HungerState();
        efMeal(pl,f);
        efReport("satiated-start",before,pl->cFP,before);
        if (state != SATIATED) {
            Error("EATFAT_PROBE: satiated-start INCONCLUSIVE hunger state %d is not SATIATED",state);
            ++efFails;
        }
    }

    /* (d) a vomit costs one fatigue. A vomit is !random(20) above BLOATED+500,
       so bite single apples at 7200 hunger until one vomits (a vomit drops
       hunger to HUNGRY at most; no vomit leaves it above 7200). */
    {
        int tries = 0, vomits = 0;
        for (; tries < 400 && !vomits; ++tries) {
            Food *f = efFood(pl,"apple");
            pl->SetStatiDur(HUNGER,-1,NULL,7200);
            pl->cFP = mx - 5;
            const int before = pl->cFP;
            EventInfo e; e.Clear();
            e.EActor = pl; e.EItem = f; e.EMap = pl->m;
            efTold = false;
            f->Eat(e);
            const bool vomited = pl->GetStatiDur(HUNGER) < 7200;
            if (vomited) {
                ++vomits;
                efReport("vomit",before,pl->cFP,before - 1);
            } else if (pl->cFP != before) {
                ++efFails;
                Error("EATFAT_PROBE: no-vomit-bite before=%d after=%d FAIL",before,(int)pl->cFP);
            }
            f->Remove(true);
        }
        if (!vomits) {
            Error("EATFAT_PROBE: vomit INCONCLUSIVE no vomit in %d bites",tries);
            ++efFails;
        } else
            Error("EATFAT_PROBE: vomit-tries=%d",tries);
    }

    eatfatArmed = false;
    pl->SetStatiDur(HUNGER,-1,NULL,oldHunger);
    pl->cFP = oldFP;
    pl->Options[OPT_NO_FATIGUE] = oldOpt;
    pl->CalcValues();
    theGame->PlayMode = oldPlay;
    Error("EATFAT_PROBE: done failures=%d",efFails);
}
