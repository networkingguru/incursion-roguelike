/* inc-93mxz: opt-in oracle for "LoseFatigue recalculates on every fatigue band
   change", enabled by INCURSION_FATIGUE_FLOOR_PROBE=1. Pays fatigue through the
   real Creature::LoseFatigue, then compares Strength and the fatigue floor
   (Attr[A_FAT], the value the pass-out warning reads) with a fresh CalcValues.
   Prints one FATFLOOR_PROBE line per case. See tools/check_fatigue_floor.sh. */
#define protected public
#include "Incursion.h"
#undef protected

static int ffFails = 0;

static void ffSettle(Player *pl, int fp) {
    for (int i = 0; i < 4; ++i) { pl->cFP = fp; pl->CalcValues(); }
}

/* Add apples until the load is EN_LIGHT at fatigue 0 and EN_MODERATE once
   Fatigued (Str -2), so the band change moves the floor (Moderate -1 A_FAT). */
static bool ffFindLoad(Player *pl, int mx) {
    (void)mx;
    for (int n = 0; n < 400; ++n) {
        ffSettle(pl,0);
        const int e1 = pl->Encumbrance(), s1 = pl->Attr[A_STR], f1 = pl->Attr[A_FAT];
        ffSettle(pl,-1);
        const int e2 = pl->Encumbrance(), s2 = pl->Attr[A_STR], f2 = pl->Attr[A_FAT];
        if (e1 == EN_LIGHT && e2 == EN_MODERATE) {
            Error("FATFLOOR_PROBE: load-found apples=%d str0=%d str-1=%d floor0=%d floor-1=%d",n,s1,s2,f1,f2);
            return true;
        }
        Food *f = (Food *)Item::Create(FIND("apple"));
        if (!f) return false;
        pl->GainItem(f,false);
    }
    return false;
}

/* The load found above: pay one at a time from exactly 0. After each payment
   the stored floor and fatigue must already equal what a settling CalcValues
   gives (so `cFP < -Attr[A_FAT]`, the pass-out warning, reads a current floor
   and fires at the same payment as with a fresh floor). Settling a current
   floor changes nothing; a stale one moves it. */
static void ffLoadCase(Player *pl) {
    ffSettle(pl,0);
    int stale = 0, firstStale = 0, warnIdx = 0, floor1 = 0, fresh1 = 0;
    for (int k = 1; k <= 20; ++k) {
        pl->LoseFatigue(1,false);
        const int fp = pl->cFP, fl = pl->Attr[A_FAT];
        const bool warn = fp < -fl;
        if (k == 1) floor1 = fl;
        if (warn && !warnIdx) warnIdx = k;
        for (int i = 0; i < 4; ++i) pl->CalcValues();
        const int fp2 = pl->cFP, fl2 = pl->Attr[A_FAT];
        if (k == 1) fresh1 = fl2;
        const bool warn2 = fp2 < -fl2;
        if (fl != fl2 || fp != fp2 || warn != warn2) {
            ++stale;
            if (!firstStale) firstStale = k;
            Error("FATFLOOR_PROBE: load-detail payment=%d stored fp=%d floor=%d warn=%d settled fp=%d floor=%d warn=%d",
                  k,fp,fl,(int)warn,fp2,fl2,(int)warn2);
        }
    }
    const bool passA = floor1 == fresh1;
    const bool passB = stale == 0 && warnIdx != 0;
    if (!passA) ++ffFails;
    if (!passB) ++ffFails;
    Error("FATFLOOR_PROBE: load-floor first_payment_floor=%d settled=%d %s",floor1,fresh1,passA ? "PASS" : "FAIL");
    Error("FATFLOOR_PROBE: load-warning first_warning_payment=%d stale_payments=%d first_stale=%d %s",
          warnIdx,stale,firstStale,passB ? "PASS" : "FAIL");
}

/* Back-to-back CalcValues at one fatigue must not move the floor. */
static void ffStable(Player *pl, const char *name, int fp) {
    int f[3];
    for (int i = 0; i < 3; ++i) { pl->cFP = fp; pl->CalcValues(); f[i] = pl->Attr[A_FAT]; }
    const bool pass = f[0] == f[1] && f[1] == f[2];
    if (!pass) ++ffFails;
    Error("FATFLOOR_PROBE: stable-%s fp=%d floors=%d,%d,%d %s",name,fp,f[0],f[1],f[2],pass ? "PASS" : "FAIL");
}

/* Start at `start`, pay `amt`, and compare the stored values with a fresh
   recalculation. `bandChange` says the payment moves between fatigue bands. */
static void ffCase(Player *pl, const char *name, int start, int amt, bool bandChange) {
    pl->cFP = start;
    pl->CalcValues();           /* settle the starting band */
    const int sFloor = pl->Attr[A_FAT];
    const bool ok = pl->LoseFatigue(amt,false);
    const int paidStr = pl->Attr[A_STR], paidFloor = pl->Attr[A_FAT];
    pl->CalcValues();           /* the fresh answer */
    const int freshStr = pl->Attr[A_STR], freshFloor = pl->Attr[A_FAT];
    const bool pass = ok && paidStr == freshStr && paidFloor == freshFloor;
    if (!pass) ++ffFails;
    Error("FATFLOOR_PROBE: %s start=%d pay=%d startfloor=%d band=%d paid_str=%d fresh_str=%d paid_floor=%d fresh_floor=%d %s",
          name,start,amt,sFloor,(int)bandChange,paidStr,freshStr,paidFloor,freshFloor,pass ? "PASS" : "FAIL");
}

void FatigueFloorProbe(Player *pl) {
    if (!getenv("INCURSION_FATIGUE_FLOOR_PROBE")) return;
    if (!pl || !pl->m) {
        Error("FATFLOOR_PROBE: setup INCONCLUSIVE missing player/map");
        return;
    }
    const bool oldPlay = theGame->PlayMode;
    const int oldFP = pl->cFP, oldOpt = pl->Options[OPT_NO_FATIGUE];
    theGame->PlayMode = true;
    pl->Options[OPT_NO_FATIGUE] = 0;
    pl->CalcValues();
    const int mx = pl->Attr[A_FAT];
    if (mx < 4) {
        Error("FATFLOOR_PROBE: setup INCONCLUSIVE floor %d is below 4",mx);
        theGame->PlayMode = oldPlay;
        return;
    }
    /* Fresh to Fatigued is the defect: exactly 0, then below 0. */
    ffCase(pl,"zero-to-below",0,1,true);
    ffCase(pl,"zero-to-below-big",0,3,true);
    /* Control: a payment inside the Fatigued band changes no band. The floor
       itself is not compared across the exhausted band or from above 0, where
       back-to-back CalcValues calls alternate it (see inc-93mxz notes). */
    ffCase(pl,"within-fatigued",-1,1,false);
    ffStable(pl,"cross-floor",-mx);
    ffStable(pl,"above-zero",mx);
    ffSettle(pl,0);
    if (ffFindLoad(pl,mx)) ffLoadCase(pl);
    else Error("FATFLOOR_PROBE: load INCONCLUSIVE no apple load found");
    Error("FATFLOOR_PROBE: done failures=%d",ffFails);
    pl->cFP = oldFP;
    pl->Options[OPT_NO_FATIGUE] = oldOpt;
    pl->CalcValues();
    theGame->PlayMode = oldPlay;
}
