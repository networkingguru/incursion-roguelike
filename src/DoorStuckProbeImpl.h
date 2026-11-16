#include <map>
#include <vector>
#include <string>
#include "Incursion.h"

/* inc-zm6li: observational only; no extra searches, no change to a result.
   A pair (monster, door) counts as stuck for one OWN TURN (one run of
   Monster::ChooseAction) only when: the monster is alive, it is on the
   player's map, its last SmartDirTo result of that turn pointed into the
   closed door, and during that turn it neither changed position, opened the
   door, nor bashed it. The streak counts consecutive such own turns. Ticks
   (Game::Turn) are kept only to name where a streak began and ended. */
struct DSMon {
    bool pending;           /* a turn began and is not yet judged */
    hObj map;               /* monster's map when the turn began */
    int x, y;
    bool sameMap;           /* on the player's map when the turn began */
    uint32 tick;            /* Game::Turn when the turn began */
    uint32 lastTick;        /* tick of the last turn begun */
    hObj door;              /* closed door the last SmartDirTo pointed into */
    bool acted;             /* opened or bashed during this turn */
    std::vector<std::pair<int,int> > acts;  /* (Act, result) attempted */
};
struct DSPair {
    hObj mon, map, door;
    rID kind; int nohands;
    int x,y, flags, mag2;
    uint32 streak, worst, firstTick, endTick, curFirst;
    unsigned opens, bashes;
    std::map<std::string,unsigned> curActs, worstActs;
    int worstMag2, worstFlags;
};
static std::map<hObj, DSMon> DSMons;
static std::map<std::pair<hObj,hObj>, DSPair> DSPairs;
static FILE *DSLog;
static hObj DSPlayerMap;
static uint32 DSLastTick;

static const char *DSClass(const DSPair &p) {
    bool allMove=true;
    for (auto &a : p.worstActs) if (a.first.compare(0,5,"act1:") != 0) allMove=false;
    if (!allMove) return "c";
    if (p.worstMag2 < 5 && (p.nohands || (p.worstFlags & DF_LOCKED))) return "a";
    if (p.worstMag2 >= 5) return "b";
    return "d";
}
static std::string DSActs(const DSPair &p) {
    std::string s;
    for (auto &a : p.worstActs) {
        char b[64]; snprintf(b,sizeof b,"%s%s=%u",s.empty()?"":",",a.first.c_str(),a.second);
        s+=b;
    }
    return s.empty() ? "none" : s;
}
static void DSReport() {
    unsigned count=0, cls[4]={0,0,0,0};
    /* inc-zm6li: INCURSION_DOORSTUCK_MIN lowers the stuck-streak floor (10) for tools/measure_door_stuck.py */
    const char *minEnv=getenv("INCURSION_DOORSTUCK_MIN");   /* diagnostic: lower the 10 */
    uint32 minTurns = minEnv ? (uint32)atoi(minEnv) : 10;
    for (auto &entry : DSPairs) {
        DSPair &p=entry.second;
        if (p.worst < minTurns) continue;
        const char *c=DSClass(p);
        count++; cls[c[0]-'a']++;
        DSMon &m=DSMons[p.mon];
        fprintf(stderr,"DOORSTUCK mon=%u map=%u door=%u at=%d,%d own_turns=%u first_tick=%u end_tick=%u mon_last_tick=%u class=%s opens=%u bashes=%u flags=%d mag2=%d nohands=%d kind=%s actions=%s\n",
            (unsigned)p.mon,(unsigned)p.map,(unsigned)p.door,p.x,p.y,p.worst,
            p.firstTick,p.endTick,m.lastTick,c,p.opens,p.bashes,p.worstFlags,
            p.worstMag2,p.nohands,NAME(p.kind),DSActs(p).c_str());
    }
    fprintf(stderr,"DOORSTUCK total=%u a=%u b=%u c=%u d=%u unit=own_turn final_tick=%u\n",
        count,cls[0],cls[1],cls[2],cls[3],DSLastTick);
    if (DSLog) fflush(DSLog);
}
static void DSInit() {
    static bool registered=false;
    if (registered) return;
    registered=true; atexit(DSReport);
    const char *dir=getenv("INCURSION_RUN_DIR");
    if (dir) {
        char path[1024]; snprintf(path,sizeof path,"%s/door-stuck.log",dir);
        DSLog=fopen(path,"w");
    }
}
static DSPair &DSPairFor(hObj mon, Monster *mn, Door *d) {
    DSPair &p=DSPairs[std::make_pair(mon,d->myHandle)];
    if (!p.mon) { p.mon=mon; p.door=d->myHandle; p.x=d->x; p.y=d->y; }
    p.map=mn->m ? mn->m->myHandle : 0;
    p.kind=mn->mID; p.nohands=mn->HasMFlag(M_NOHANDS);
    return p;
}
/* Judge the turn that just ended for monster mn (now at x,y, still alive). */
static void DSJudge(hObj h, DSMon &s, Monster *mn) {
    s.pending=false;
    bool moved = !mn || mn->x != s.x || mn->y != s.y || !mn->m ||
                 mn->m->myHandle != s.map;
    Door *d = (s.door && isValidHandle(s.door)) ? (Door*)oThing(s.door) : NULL;
    bool stuck = d && !moved && !s.acted && s.sameMap && mn &&
                 !(mn->Flags & F_DELETE) && !mn->isDead() && !d->isPassable();
    /* any pair of this monster that is not this turn's stuck pair ends */
    for (auto it=DSPairs.lower_bound(std::make_pair(h,(hObj)0));
         it != DSPairs.end() && it->first.first == h; ++it) {
        DSPair &p=it->second;
        if (stuck && p.door == s.door) continue;
        p.streak=0; p.curActs.clear();
    }
    if (!stuck) return;
    DSPair &p=DSPairFor(h,mn,d);
    if (!p.streak) { p.curFirst=s.tick; p.curActs.clear(); }
    p.streak++;
    for (auto &a : s.acts) {
        char b[32]; snprintf(b,sizeof b,"act%d:res%d",a.first,a.second);
        p.curActs[b]++;
    }
    if (p.streak > p.worst) {
        p.worst=p.streak; p.firstTick=p.curFirst; p.endTick=s.tick;
        p.worstActs=p.curActs;
        p.worstFlags=d->DoorFlags; p.worstMag2=d->GetStatiMag(TRIED,2,mn);
    }
    if (DSLog && p.streak == 10)
        fprintf(DSLog,"stuck10 mon=%u door=%u at=%d,%d first_tick=%u tick=%u\n",
            (unsigned)h,(unsigned)p.door,p.x,p.y,p.curFirst,s.tick);
}
/* Hook: top of Monster::ChooseAction. Judges the monster's previous turn,
   then opens a new one. */
void DoorStuckBegin(Monster *mn) {
    DSInit();
    Player *pl=theGame->GetPlayer(0);
    hObj pm = (pl && pl->m) ? pl->m->myHandle : 0;
    if (pm != DSPlayerMap) {
        if (DSLog) fprintf(DSLog,"playermap old=%u new=%u tick=%u\n",
            (unsigned)DSPlayerMap,(unsigned)pm,(unsigned)theGame->Turn);
        DSPlayerMap=pm;
    }
    DSLastTick=theGame->Turn;
    DSMon &s=DSMons[mn->myHandle];
    if (s.pending) DSJudge(mn->myHandle,s,mn);
    s.pending=true; s.map = mn->m ? mn->m->myHandle : 0;
    s.x=mn->x; s.y=mn->y; s.sameMap = pm && s.map == pm;
    s.tick=s.lastTick=theGame->Turn; s.door=0; s.acted=false; s.acts.clear();
}
/* Hook: every return of Monster::SmartDirTo. The last one in a turn counts. */
void DoorStuckNext(Monster *mn, int tx, int ty, const char *branch, Dir dir) {
    (void)tx; (void)ty; (void)branch;
    auto it=DSMons.find(mn->myHandle);
    if (it == DSMons.end() || !it->second.pending || it->second.tick != theGame->Turn) return;
    DSMon &s=it->second;
    s.door=0;
    int nx=mn->x+DirX[dir], ny=mn->y+DirY[dir];
    if (dir != CENTER && mn->m && mn->m->InBounds(nx,ny)) {
        Door *d=mn->m->FDoorAt(nx,ny);
        if (d && !d->isPassable()) {
            s.door=d->myHandle;
            DSPairFor(mn->myHandle,mn,d);
        }
    }
}
/* Hook: Monster::OpenDoor, on each open or bash attempt. */
void DoorStuckAction(Monster *mn, Door *d, bool opening) {
    DSInit();
    DSPair &p=DSPairFor(mn->myHandle,mn,d);
    if (opening) p.opens++; else p.bashes++;
    auto it=DSMons.find(mn->myHandle);
    if (it != DSMons.end()) it->second.acted=true;
    if (DSLog) fprintf(DSLog,"action mon=%u door=%u tick=%u kind=%s flags=%d mag2=%d\n",
        (unsigned)p.mon,(unsigned)p.door,(unsigned)theGame->Turn,
        opening ? "open" : "bash",(int)d->DoorFlags,
        (int)d->GetStatiMag(TRIED,2,mn));
}
/* Hook: each attempted action in Monster::ChooseAction. */
void DoorStuckChosen(Monster *mn, int action, int result) {
    auto it=DSMons.find(mn->myHandle);
    if (it == DSMons.end() || !it->second.pending) return;
    it->second.acts.push_back(std::make_pair(action,result));
}
