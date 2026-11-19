/* inc-jahch: opt-in oracle for fatigue from an interrupted rest, from waiting
   and from AutoRest, enabled by INCURSION_FATIGUE_REST_PROBE=1. It drives the
   real Player::Rest (encounter roll and share forced through
   FatigueRestProbeArm in src/Player.cpp), the real Creature::DoTurn and the
   real AutoRest macro, and prints one FATREST_PROBE line per case. See
   tools/check_fatigue_rest.sh. Expected values are computed here from the
   rules, never by calling the code under test. */
#define protected public
#include "Incursion.h"
#undef protected

extern void FatigueRestProbeArm(bool on, int16 roll, int16 percent);

int FatigueRestProbeMax = 0; /* read by CalcValues; 0 outside the probe */
static int frFails = 0;
static void frReport(const char *name, int before, int after, int expect, const char *extra) {
    const bool pass = after == expect;
    if (!pass) ++frFails;
    Error("FATREST_PROBE: %s before=%d after=%d expect=%d%s%s %s",
          name,before,after,expect,*extra ? " " : "",extra,pass ? "PASS" : "FAIL");
}

/* (1) interrupted rest: cFP += (max(25,Percent) * (max - cFP)) / 100. */
static void frRest(Player *pl, const char *level, int start, int percent, int mx) {
    char name[64];
    snprintf(name,sizeof(name),"rest-%s-%d",level,percent);
    pl->cFP = start;
    FatigueRestProbeArm(true,percent < 100 ? -1 : 1000,percent < 100 ? percent : 0);
    EventInfo e; e.Clear();
    e.EParam = REST_DUNGEON | REST_INSTANT | REST_NOIDENT | REST_NOMSG;
    const EvReturn r = pl->Rest(e);
    FatigueRestProbeArm(false,0,0);
    pl->RemoveStati(SLEEPING);
    pl->Timeout = 0;
    if (r == ABORT) {
        Error("FATREST_PROBE: %s INCONCLUSIVE Rest aborted",name);
        ++frFails;
        return;
    }
    int expect;
    if (percent < 100)
        expect = start + (max(25,percent) * (mx - start)) / 100;
    else
        expect = mx; /* a full rest from Vigorous */
    frReport(name,start,pl->cFP,expect,"");
}

/* Fatigue Regeneration rank r as the existing pace: gain one point at the
   turn FFCount first passes 50 + 50/r, then every 50/r + 1 turns. */
static int frGainedRegen(int turn, int r) {
    const int first = 51 + 50 / r;
    return turn < first ? 0 : 1 + (turn - first) / (50 / r + 1);
}

/* (2) waiting: a fight just ended (FFCount 0), then `turns` real DoTurn calls.
   rank 0 gains 1 point per 250 quiet turns (the first quiet turn is the 51st). */
static void frWait(Player *pl, const char *name, int rank, int start, int turns, int mx) {
    const int ceil = max(1, min(mx, (mx * (50 + 5 * rank)) / 100));
    pl->Abilities[CA_FATIGUE_REGEN] = rank;
    pl->cFP = start;
    pl->FFCount = 0;
    pl->QuietTurns = 0;
    int firstBad = 0, expectNow = start;
    for (int t = 1; t <= turns; ++t) {
        pl->SetStatiDur(HUNGER,-1,NULL,2870);
        pl->DoTurn();
        const int gained = rank ? frGainedRegen(t,rank) : (t > 50 ? (t - 50) / 250 : 0);
        expectNow = start >= ceil ? start : min(ceil,start + gained);
        if (!firstBad && pl->cFP != expectNow)
            firstBad = t;
    }
    char extra[64];
    snprintf(extra,sizeof(extra),"rank=%d ceil=%d turns=%d firstbad=%d",rank,ceil,turns,firstBad);
    if (pl->AbilityLevel(CA_FATIGUE_REGEN) != rank) {
        Error("FATREST_PROBE: %s INCONCLUSIVE ability level %d is not %d",
              name,(int)pl->AbilityLevel(CA_FATIGUE_REGEN),rank);
        ++frFails;
        return;
    }
    if (firstBad) ++frFails;
    frReport(name,start,pl->cFP,expectNow,extra);
}

/* (3) AutoRest: the real macro, one real DoTurn per macro call (the game
   spends 1.5 turns per call, so this is the slower side). */
static void frAutoRest(Player *pl, const char *name, int rank, int start, int expect, int minCalls, int maxCalls) {
    pl->Abilities[CA_FATIGUE_REGEN] = rank;
    pl->cFP = start;
    pl->FFCount = 0;
    pl->QuietTurns = 0;
    pl->Timeout = 0;
    RES(FIND("AutoRest"))->PEvent(EV_INITIALIZE,pl,FIND("AutoRest"),0);
    pl->GainPermStati(ACTING,NULL,SS_MISC,EV_MACRO,0,FIND("AutoRest"));
    int calls = 0;
    for (; calls < 20000 && pl->HasStati(ACTING); ++calls) {
        pl->Timeout = 0;
        pl->SetStatiDur(HUNGER,-1,NULL,2870);
        if (ThrowEff(EV_MACRO,FIND("AutoRest"),pl) == ABORT)
            pl->RemoveStati(ACTING);
        pl->DoTurn();
    }
    pl->RemoveStati(ACTING);
    char extra[64];
    snprintf(extra,sizeof(extra),"calls=%d mincalls=%d maxcalls=%d",calls,minCalls,maxCalls);
    if (calls < minCalls || calls > maxCalls) ++frFails;
    const int after = pl->cFP;
    if (calls < minCalls || calls > maxCalls) {
        Error("FATREST_PROBE: %s before=%d after=%d expect=%d %s FAIL",name,start,after,expect,extra);
        return;
    }
    frReport(name,start,after,expect,extra);
}

void FatigueRestProbe(Player *pl) {
    /* inc-jahch: armed only by INCURSION_FATIGUE_REST_PROBE. */
    if (!getenv("INCURSION_FATIGUE_REST_PROBE")) return;
    if (!pl || !pl->m || !FIND("AutoRest")) {
        Error("FATREST_PROBE: setup INCONCLUSIVE missing player/map/resources");
        return;
    }
    const bool oldPlay = theGame->PlayMode;
    const int oldFP = pl->cFP, oldOpt = pl->Options[OPT_NO_FATIGUE];
    const int oldHunger = pl->GetStatiDur(HUNGER);
    const uint8 oldRegen = pl->Abilities[CA_FATIGUE_REGEN];
    const int oldFF = pl->FFCount, oldQuiet = pl->QuietTurns;
    theGame->PlayMode = true;
    pl->Options[OPT_NO_FATIGUE] = 0;
    pl->Options[OPT_AUTOMORE] = 1;
    /* CONTENT hunger: Hungry would lower the maximum by 1 on the next CalcValues. */
    pl->SetStatiDur(HUNGER,-1,NULL,2870);
    /* Player::Rest takes armour off, which changes the maximum; do it first so
       the maximum read here is the one every case sees. */
    if (pl->InSlot(SL_ARMOUR) && !pl->InSlot(SL_ARMOUR)->isCursed()) {
        Item *ar = pl->InSlot(SL_ARMOUR);
        ar->Remove(false);
        ar->PlaceAt(pl->m,pl->x,pl->y);
    }
    pl->CalcValues();
    const int mx = pl->Attr[A_FAT];
    if (mx < 6) {
        Error("FATREST_PROBE: setup INCONCLUSIVE maximum fatigue %d is below 6",mx);
        theGame->PlayMode = oldPlay;
        return;
    }
    pl->Abilities[CA_FATIGUE_REGEN] = 0;
    pl->uMana = pl->hMana = 0;

    /* (1) every level, a low share (10, the 25% floor) and a high share (90). */
    const int starts[3] = { mx - 4, -2, -mx - 3 };
    const char *levels[3] = { "vigorous", "fatigued", "exhausted" };
    const int shares[4] = { 10, 25, 60, 90 };
    for (int l = 0; l < 3; ++l)
        for (int s = 0; s < 4; ++s)
            frRest(pl,levels[l],starts[l],shares[s],mx);
    frRest(pl,"vigorous",mx - 4,100,mx);

    /* (2) waiting. rank 0: from 2 below the ceiling (mx/2), 1200 turns. */
    frWait(pl,"wait-rank0",0,mx / 2 - 2,1200,mx);
    frWait(pl,"wait-at-ceiling-rank0",0,mx / 2,700,mx);
    frWait(pl,"wait-rank1",1,(mx * 55) / 100 - 2,400,mx);
    frWait(pl,"wait-rank10",10,mx - 3,200,mx);

    /* (3) AutoRest from deep below 0 needs more than 1000 calls. */
    frAutoRest(pl,"autorest-rank0",0,-mx,1,1001,20000);
    frAutoRest(pl,"autorest-rank10",10,mx - 2,mx,1,200);
    /* An ability holder stops at its ceiling (rank 1, 55% of mx), not at the
       maximum: the first gain is the 101st turn, so it ends in about 102 calls. */
    frAutoRest(pl,"autorest-rank1",1,(mx * 55) / 100 - 1,(mx * 55) / 100,50,300);

    /* (4) maximum fatigue 1: the ceiling is never below 1. Forced through
       FatigueRestProbeMax, which CalcValues applies to the player; the probe
       reads it back (INCONCLUSIVE if it is not 1) and clears it afterward. */
    FatigueRestProbeMax = 1;
    pl->CalcValues();
    frWait(pl,"wait-max1",0,0,700,1);
    frAutoRest(pl,"autorest-max1",0,-1,1,500,1000);
    if (pl->Attr[A_FAT] != 1) {
        Error("FATREST_PROBE: max1 INCONCLUSIVE maximum fatigue is %d, not 1",(int)pl->Attr[A_FAT]);
        ++frFails;
    }
    FatigueRestProbeMax = 0;
    pl->CalcValues();

    pl->Abilities[CA_FATIGUE_REGEN] = oldRegen;
    pl->FFCount = oldFF;
    pl->QuietTurns = oldQuiet;
    pl->SetStatiDur(HUNGER,-1,NULL,oldHunger);
    pl->cFP = oldFP;
    pl->Options[OPT_NO_FATIGUE] = oldOpt;
    pl->CalcValues();
    theGame->PlayMode = oldPlay;
    Error("FATREST_PROBE: done failures=%d",frFails);
}
