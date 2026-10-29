/* inc-vhkei: diagnostic counters only; included solely under PATH_PROBE.
   Snapshots contain completed calls, emitted at most every 0.5 seconds plus
   one call's duration. Pre-check refusals are separate from exhausted floods.
   Pops retain PATH_PROBE's definition: non-stale queue entries. RunOver counts
   flood neighbours (the target pre-check is excluded, as in the old probe). */
#include <time.h>
#include <stdio.h>
static unsigned long long PP_Calls=0, PP_RunOver=0, PP_Pops=0,
    PP_TgtHit=0, PP_TgtUnreach=0, PP_Prechk=0,
    PP_HitPops=0, PP_UnreachPops=0;
static unsigned long long PP_LabelCut=0, PP_LabelRebuilds=0;
static double PP_LabelSecs=0;
static double PP_Reset=0, PP_Flood=0, PP_HitFlood=0, PP_UnreachFlood=0;
static double PP_Now() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

/* inc-vhkei step 1: WHAT the unreachable targets are. Classes: 0 reached,
   1 unreachable after a full flood, 2 refused by the pre-check. Cell index:
   purpose (Target type, or 40+ for the non-loop SmartDirTo sites) x target
   strictly passable (RunOver memonly=false, isTarget=false) x creature on the
   target (0 none, 1 other, 2 player) x any of the target's 8 neighbours reached
   by the flood. Unreachable after a full flood means "not connected for this
   runner". */
extern int PP_Purpose;
extern unsigned long long PP_RecDrops, PP_RecOK, PP_RecentHits;
extern unsigned long long PP_ReuseHit, PP_ReuseMiss[6], PP_ReuseDrop;
static unsigned long long PP_Gap0[3], PP_Gap60[3];
struct PP_Cell { unsigned long long n, pops; double t; };
static PP_Cell PP_T[3][64][2][3][2];
struct PP_Kind { rID mid; unsigned long long n[3]; double t[3]; int flags; };
#define PP_KINDS 1024
static PP_Kind PP_K[PP_KINDS];
/* boundary reasons at squares the flood refused, non-solid squares only */
static unsigned long long PP_Rej[3][6]; /* [class][closed door, secret door, hostile creature, other] */
/* repeat table for unreachable calls: runner+target -> last turn */
#define PP_RSLOTS 65536
struct PP_Rep { hObj mon, map; int16 tx, ty; uint32 last; };
static PP_Rep PP_R[PP_RSLOTS];
static unsigned long long PP_RepN[3][6]; /* gap<=300,<=600,<=3000,<=6000,>6000,new */
static double PP_RepT[3][6];
static const char *PP_PurposeName(int p) {
    static const char *n[] = {"Invalid","Enemy","Ally","Leader","Summoner","Master",
        "Mount","Area","Wander","Item","StandStill","DoNotAttack","AttackNeutrals",
        "Hide","DoNotHide","WalkInFront","WalkInBack","WalkNearMe","WalkToPoint",
        "BeFriendly","AttackTarget"};
    if (p >= 0 && p < (int)(sizeof n/sizeof n[0])) return n[p];
    switch (p) { case 40: return "site:WalkToPoint"; case 41: return "site:InFront";
        case 42: return "site:InBack"; case 43: return "site:NearMe";
        case 44: return "site:Leader"; case 63: return "unset"; }
    return "other";
}

/* inc-vhkei probe 2: FACT A (wall-only BFS after a failed search) and FACT B
   (which RunOver test refused a non-solid square). */
static bool RegionTooSmallFor(Map *m, int16 x, int16 y, Creature *c);
enum { PPR_MEM, PPR_REGION, PPR_HOSTILE, PPR_TRAP, PPR_DOOR, PPR_STICKY,
       PPR_FEATURE, PPR_WARN, PPR_UNKNOWN, PPR_N };
static const char *PP_RName[PPR_N] = {"memory","region_too_small","hostile_creature",
    "found_trap","door","sticky","feature","warn_terrain","unknown"};
static unsigned long long PP_RR[3][PPR_N], PP_Dom[3][PPR_N];
static unsigned long long PP_WallN[64][2]; static double PP_WallT[64][2];
struct PP_WName { rID t; unsigned long long n[3]; };
static PP_WName PP_WN[64]; static int PP_WNn = 0;
static rID PP_LastWarn;
static int PP_WarnSlot(rID t) { /* -1 when 64 names are taken */
    for (int i=0;i<PP_WNn;i++) if (PP_WN[i].t == t) return i;
    if (PP_WNn < 64) { PP_WN[PP_WNn].t = t; return PP_WNn++; }
    return -1;
}
/* Mirrors Map::RunOver's tests in order; first refusing test wins. */
static int PP_RefuseReason(Map *m, int16 x, int16 y, bool memonly, Creature *c,
                           int32 dangerFactor, bool Incor, bool Meld, bool isTarget) {
    if (memonly && !m->At(x,y).Memory) return PPR_MEM;
    if (RegionTooSmallFor(m, x, y, c)) return PPR_REGION;
    if (m->At(x,y).Contents) {
        if (!isTarget)
            for (Creature *ca=m->FCreatureAt(x,y);ca;ca=m->NCreatureAt(x,y))
                if (ca && c->Perceives(ca) && ca->isHostileTo(c)) return PPR_HOSTILE;
        for (Trap *tr=m->FTrapAt(x,y);tr;tr=m->NTrapAt(x,y))
            if ((tr->TrapFlags & TS_FOUND) && !(tr->TrapFlags & TS_DISARMED)
                && !(dangerFactor & DF_IGNORE_TRAPS)) return PPR_TRAP;
        for (Door *dr=m->FDoorAt(x,y);dr;dr=m->NDoorAt(x,y))
            if (!dr->isPassable()) return PPR_DOOR;
    }
    if (m->StickyAt(x,y) && !c->HasStati(STUCK) && !c->HasMFlag(M_AMORPH) &&
        !c->isAerial() && c->onPlane() == PHASE_MATERIAL &&
        c->ResistLevel(AD_STUK) != -1 && !c->HasAbility(CA_WOODLAND_STRIDE) &&
        !(dangerFactor & DF_IGNORE_TERRAIN)) return PPR_STICKY;
    for (Feature *f=m->FFeatureAt(x,y);f;f=m->NFeatureAt(x,y))
        if (TFEAT(f->fID)->PEvent(EV_MON_CONSIDER,c,f,f->fID) == ABORT &&
            !(dangerFactor & DF_IGNORE_TERRAIN)) return PPR_FEATURE;
    if (m->At(x,y).Terrain) {
        rID t = m->PTerrainAt(x,y,c);
        if (TTER(t)->HasFlag(TF_WARN) &&
            TTER(t)->PEvent(EV_MON_CONSIDER,c,t) == ABORT &&
            !(dangerFactor & DF_IGNORE_TERRAIN)) { PP_LastWarn = t; return PPR_WARN; }
    }
    return PPR_UNKNOWN;
}
/* Wall-only BFS from the start; true if the target is reached. */
static bool PP_WallReach(Map *m, int sx, int sy, int tx, int ty, bool Incor, bool Meld, Creature *c) {
    static unsigned char seen[256][256]; static uint32 q[65536];
    memset(seen, 0, sizeof seen);
    int h=0, n=0; q[n++] = sx + sy*256; seen[sx][sy] = 1;
    while (h < n) {
        int x = q[h]%256, y = q[h]/256; h++;
        if (x == tx && y == ty) return true;
        for (int i=0;i<8;i++) {
            int16 nx = x + DirX[i], ny = y + DirY[i];
            if ((nx == 0 && ny == 0) || !m->InBounds(nx,ny) || seen[nx][ny]) continue;
            bool open = Incor || !m->SolidAt(nx,ny);
            if (!open && Meld) {
                int k = TTER(m->PTerrainAt(nx,ny,c))->Material;
                open = (k == MAT_GRANITE || k == MAT_MAGMA || k == MAT_QUARTZ ||
                        k == MAT_GEMSTONE || k == MAT_MINERAL);
            }
            if (!open) continue;
            seen[nx][ny] = 1; q[n++] = nx + ny*256;
        }
    }
    return false;
}
/* inc-vhkei: writes the step-1 classification to $INCURSION_RUN_DIR/pathprobe-detail.txt. */
static void PP_Detail() {
    const char *rd = getenv("INCURSION_RUN_DIR");
    if (!rd) return;
    char path[1024]; snprintf(path, sizeof path, "%s/pathprobe-detail.txt", rd);
    FILE *f = fopen(path, "w"); if (!f) return;
    static const char *cn[3] = {"reached","unreach","prechk"};
    for (int c=0;c<3;c++) for (int p=0;p<64;p++) for (int a=0;a<2;a++)
      for (int b=0;b<3;b++) for (int d=0;d<2;d++) {
        PP_Cell &e = PP_T[c][p][a][b][d]; if (!e.n) continue;
        fprintf(f,"CELL class=%s purpose=%s passable=%d creature=%d nbr=%d n=%llu pops=%llu flood_s=%.6f\n",
                cn[c],PP_PurposeName(p),a,b,d,e.n,e.pops,e.t); }
    for (int i=0;i<PP_KINDS;i++) if (PP_K[i].mid)
        fprintf(f,"KIND name=\"%s\" flags=%d reached=%llu unreach=%llu prechk=%llu reached_s=%.6f unreach_s=%.6f\n",
                NAME(PP_K[i].mid),PP_K[i].flags,PP_K[i].n[0],PP_K[i].n[1],PP_K[i].n[2],
                PP_K[i].t[0],PP_K[i].t[1]);
    for (int c=1;c<3;c++) {
        fprintf(f,"REJ class=%s closed_door=%llu secret_door=%llu hostile_creature=%llu other=%llu\n",
                cn[c],PP_Rej[c][0],PP_Rej[c][1],PP_Rej[c][2],PP_Rej[c][3]);
        fprintf(f,"REP class=%s le300=%llu le600=%llu le3000=%llu le6000=%llu gt6000=%llu new=%llu"
                " le300_s=%.6f le600_s=%.6f le3000_s=%.6f le6000_s=%.6f gt6000_s=%.6f new_s=%.6f\n",
                cn[c],PP_RepN[c][0],PP_RepN[c][1],PP_RepN[c][2],PP_RepN[c][3],PP_RepN[c][4],PP_RepN[c][5],
                PP_RepT[c][0],PP_RepT[c][1],PP_RepT[c][2],PP_RepT[c][3],PP_RepT[c][4],PP_RepT[c][5]); }
    for (int p=0;p<64;p++) if (PP_WallN[p][0] || PP_WallN[p][1])
        fprintf(f,"WALL purpose=%s wall_cut=%llu wall_open=%llu cut_s=%.6f open_s=%.6f\n",
                PP_PurposeName(p),PP_WallN[p][0],PP_WallN[p][1],PP_WallT[p][0],PP_WallT[p][1]);
    for (int c=1;c<3;c++) {
        fprintf(f,"REJ2 class=%s",cn[c]);
        for (int r=0;r<PPR_N;r++) fprintf(f," %s=%llu",PP_RName[r],PP_RR[c][r]);
        fprintf(f,"\n");
        for (int i=0;i<PP_WNn;i++) if (PP_WN[i].n[c])
            fprintf(f,"WARNTER class=%s name=\"%s\" n=%llu\n",cn[c],NAME(PP_WN[i].t),PP_WN[i].n[c]);
    }
    fprintf(f,"DOM class=unreach");
    for (int r=0;r<PPR_N;r++) fprintf(f," %s=%llu",PP_RName[r],PP_Dom[1][r]);
    fprintf(f,"\n");
    fprintf(f,"GAP gap0_unreach=%llu gap1to60_unreach=%llu rec_ok=%llu rec_dropped=%llu recent_hits=%llu\n",PP_Gap0[1],PP_Gap60[1],PP_RecOK,PP_RecDrops,PP_RecentHits);
    fclose(f);
}
static void PP_Classify(int cls, Creature *r, int purpose, int passable, int cr,
                        int nbr, unsigned long long pops, double t,
                        int16 tx, int16 ty, hObj map) {
    if (purpose < 0 || purpose > 63) purpose = 63;
    PP_Cell &e = PP_T[cls][purpose][passable][cr][nbr];
    e.n++; e.pops += pops; e.t += t;
    unsigned h = ((unsigned)r->mID * 2654435761u) % PP_KINDS, i;
    for (i = 0; i < PP_KINDS; i++, h = (h+1) % PP_KINDS)
        if (!PP_K[h].mid || PP_K[h].mid == r->mID) break;
    if (i < PP_KINDS) {
        PP_Kind &k = PP_K[h];
        if (!k.mid) { k.mid = r->mID;
            k.flags = (r->HasMFlag(M_INCOR)?1:0) | (r->HasAbility(CA_EARTHMELD)?2:0)
                    | (r->isAerial()?4:0) | (r->HasMFlag(M_AQUATIC)?8:0)
                    | (r->HasMFlag(M_NOHANDS)?16:0); }
        k.n[cls]++; k.t[cls] += t;
    }
    if (cls) {
        uint32 now = theGame ? theGame->Turn : 0;
        unsigned s = ((unsigned)r->myHandle*2654435761u ^ (unsigned)(uint16)tx*3266489917u
                      ^ (unsigned)(uint16)ty*668265263u ^ (unsigned)map*2246822519u) % PP_RSLOTS;
        PP_Rep &q = PP_R[s]; int b;
        if (q.mon == r->myHandle && q.map == map && q.tx == tx && q.ty == ty) {
            uint32 g = now - q.last;
            if (g == 0) PP_Gap0[cls]++; else if (g <= 60) PP_Gap60[cls]++;
            b = g <= 300 ? 0 : g <= 600 ? 1 : g <= 3000 ? 2 : g <= 6000 ? 3 : 4;
        } else b = 5;
        PP_RepN[cls][b]++; PP_RepT[cls][b] += t;
        q.mon = r->myHandle; q.map = map; q.tx = tx; q.ty = ty; q.last = now;
    }
}
static void PP_Report() {
    fprintf(stderr, "PATHPROBE stamp=%.6f turn=%u calls=%llu prechk=%llu"
        " runover=%llu pops=%llu hit=%llu unreach=%llu hit_pops=%llu"
        " unreach_pops=%llu reset_s=%.6f flood_s=%.6f"
        " hit_flood_s=%.6f unreach_flood_s=%.6f"
        " label_cut=%llu label_rebuilds=%llu label_s=%.6f"
        " reuse_hit=%llu reuse_miss_none=%llu reuse_miss_exp=%llu"
        " reuse_miss_off=%llu reuse_miss_end=%llu reuse_miss_block=%llu"
        " reuse_drop=%llu\n",
        PP_Now(), theGame ? (unsigned)theGame->Turn : 0u,
        PP_Calls, PP_Prechk, PP_RunOver, PP_Pops, PP_TgtHit, PP_TgtUnreach,
        PP_HitPops, PP_UnreachPops, PP_Reset, PP_Flood,
        PP_HitFlood, PP_UnreachFlood,
        PP_LabelCut, PP_LabelRebuilds, PP_LabelSecs,
        PP_ReuseHit, PP_ReuseMiss[1], PP_ReuseMiss[2], PP_ReuseMiss[3],
        PP_ReuseMiss[4], PP_ReuseMiss[5], PP_ReuseDrop);
    fflush(stderr);
    PP_Detail();
}
struct PP_Call {
    double start, lastT;
    unsigned long long pops, lastPops;
    unsigned long long rej[6], rr[PPR_N], wn[64];
    PP_Call() : start(0), lastT(0), pops(PP_Pops), lastPops(0) {
        for (int i=0;i<6;i++) rej[i]=0;
        for (int i=0;i<PPR_N;i++) rr[i]=0;
        for (int i=0;i<64;i++) wn[i]=0;
        if (!PP_Calls) atexit(PP_Report);
    }
    void ResetStart() { start = PP_Now(); }
    void FloodStart() { double now=PP_Now(); PP_Reset+=now-start; start=now; }
    void FloodEnd(bool reached) {
        double elapsed=PP_Now()-start;
        lastT=elapsed; lastPops=PP_Pops-pops;
        PP_Flood+=elapsed;
        if (reached) { PP_HitFlood+=elapsed; PP_HitPops+=PP_Pops-pops; }
        else { PP_UnreachFlood+=elapsed; PP_UnreachPops+=PP_Pops-pops; }
    }
    ~PP_Call() {
        ++PP_Calls;
        static double last=0;
        double now=PP_Now();
        if (now-last >= 0.5) { PP_Report(); last=now; }
    }
};
