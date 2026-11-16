/* DJIKSTRA.CPP -- See the Incursion LICENSE file for copyright information.

     An implementation of Djikstra's algorithm used for the
   running code, but available for any other (AI?) purposes
   that it might be needed as well.

     void Map::PQInsert(uint16 Node, int16 Weight)
     int32 Map::PQPeekMin()          
     bool Map::PQPopMin()
     bool Map::ShortestPath(uint8 sx, uint8 sy, uint8 tx, uint8 ty)
     uint16 Map::PathPoint(int16 n)
     bool Map::RunOver(uint8 x, uint8 y)

*/

#include "Incursion.h"


/* upstream: base-code defect. Traced. inc-gst2. Not sent.
     The invariant is that the priority queue is ordered by weight and the
   route search stops as soon as the target is popped. Upstream's queue was a
   linked list of buckets whose constructor did `Weight = Weight;` -- a
   self-assignment that left every bucket's Weight as uninitialised heap memory
   -- so the order was arbitrary and only a full flood to an empty queue found
   the route. Both defects are in the original v0.6.5B source and would
   misbehave identically on Win32, so this is upstream's, not the port's.
     The search also cannot succeed when the target itself fails RunOver, so
   ShortestPath rejects that before clearing Dist or flooding the region. */

struct PQEntry
  {
    int16 Weight;
    uint16 Node;
    unsigned long Seq;
    int16 Breaks;   /* inc-zm6li: doors to break; ordered before Weight */
  };

static PQEntry *PQHeap = NULL;
static int PQHeapN = 0, PQHeapCap = 0;
static unsigned long PQSeq = 0;

static inline bool PQLess(const PQEntry &a, const PQEntry &b)
  {
    return a.Breaks < b.Breaks ||
           (a.Breaks == b.Breaks &&
            (a.Weight < b.Weight ||
             (a.Weight == b.Weight && a.Seq < b.Seq)));
  }

static void PQHeapPush(int16 Weight, uint16 Node, int16 Breaks)
  {
    if (PQHeapN == PQHeapCap)
      {
        PQHeapCap = PQHeapCap ? PQHeapCap * 2 : 256;
        PQHeap = (PQEntry*)realloc(PQHeap, PQHeapCap * sizeof(PQEntry));
      }
    int i = PQHeapN++;
    PQHeap[i].Weight = Weight;
    PQHeap[i].Node   = Node;
    PQHeap[i].Seq    = PQSeq++;
    PQHeap[i].Breaks = Breaks;
    while (i > 0)
      {
        int p = (i - 1) / 2;
        if (!PQLess(PQHeap[i], PQHeap[p]))
          break;
        PQEntry t = PQHeap[p]; PQHeap[p] = PQHeap[i]; PQHeap[i] = t;
        i = p;
      }
  }

static void PQHeapPop()
  {
    PQHeapN--;
    if (PQHeapN == 0)
      return;
    PQHeap[0] = PQHeap[PQHeapN];
    int i = 0;
    for (;;)
      {
        int l = i * 2 + 1, r = l + 1, s = i;
        if (l < PQHeapN && PQLess(PQHeap[l], PQHeap[s]))
          s = l;
        if (r < PQHeapN && PQLess(PQHeap[r], PQHeap[s]))
          s = r;
        if (s == i)
          break;
        PQEntry t = PQHeap[s]; PQHeap[s] = PQHeap[i]; PQHeap[i] = t;
        i = s;
      }
  }

uint16 ThePath[MAX_PATH_LENGTH];

void Map::PQInsert(uint16 Node, int16 Weight, int16 Breaks)
  { PQHeapPush(Weight, Node, Breaks); }
  
int32 Map::PQPeekMin()          
  {
    if (PQHeapN == 0)
      return -1;
    return PQHeap[0].Node;
  }

bool Map::PQPopMin()
  {
    if (PQHeapN == 0)
      return false;
    PQHeapPop();
    return true;
  }


#ifdef PATH_PROBE
int PP_Purpose = 63;
unsigned long long PP_RecDrops, PP_RecOK, PP_RecentHits;
unsigned long long PP_ReuseHit, PP_ReuseMiss[6], PP_ReuseDrop;
#include "PathCostProbe.h"
#endif

/* THE MONSTER-CONSIDER CACHE. See inc-2k3.

   While a monster works out a route it asks, for every square it considers,
   "is this ground dangerous?". The game answers by running a script attached to
   that kind of ground. Measured on Brian's live game on 2026-08-15, that script
   was the single largest cost in the engine: of the work the game was actually
   doing, pathfinding was 82%, and running this script was the biggest piece
   inside it -- three times the cost of the route search itself.

   The answer cannot change from square to square within one route calculation.
   The script is never told which square is being asked about: Resource::PEvent
   fills the event in from the CREATURE -- actor, victim, map, and the creature's
   own position -- and nothing from the square. So for a fixed creature the
   answer depends only on the kind of ground. Ask once per kind, and reuse it.

   Scoped deliberately. RunOver has other callers in src/Creature.cpp that ask
   about one or two squares; the cache is off for those. It is emptied when a
   route calculation starts and switched off again on every exit from it, so an
   answer can never outlive the calculation that produced it. */
#define MC_CACHE_MAX 32
static bool     MCCacheOn = false;
static int      MCCacheN  = 0;
static rID      MCCacheID[MC_CACHE_MAX];
static EvReturn MCCacheVal[MC_CACHE_MAX];

#if defined(ASTAR_SELFCHECK) || defined(LABEL_SELFCHECK)
#include "SelfCheckTerm.h"
#endif
#ifdef ASTAR_SELFCHECK
#include "AStarSelfCheck.h"
#endif

/* A* heuristic: octile distance at the cheapest step costs (orthogonal 2,
   diagonal 3). Never overestimates and is consistent. ASTAR_OVERESTIMATE is a
   deliberately inadmissible variant, used only to prove the self-check can
   fail. */
static inline int AStarH(int x, int y, int tx, int ty)
  {
    int dx = x > tx ? x - tx : tx - x, dy = y > ty ? y - ty : ty - y;
    int h = 2 * (dx > dy ? dx : dy) + (dx > dy ? dy : dx);
#ifdef ASTAR_OVERESTIMATE
    h *= 4;
#endif
    return h;
  }


/* inc-vhkei: wall-connected areas. WallLabel[set][x][y] numbers each
   8-connected component of squares a !Incor, !Meld runner can enter (InBounds,
   not (0,0), not a wall); wall squares get 0. inc-zm6li: there are three sets,
   one per door rule. Set 0 treats every SolidAt square as a wall, closed doors
   included: it is exact for a runner that does not open doors. Set 1 treats a
   closed door that is neither locked nor secret as open (LabelSolid): it is
   exact for a runner that opens doors (DF_OPEN_DOORS). Set 2 treats every
   closed door that is not secret as open: it joins at least what a runner with
   DF_BASH_DOORS reaches (per-monster five-try walls are not in the labels, so
   it may join more, never less). ShortestPath picks the set from its
   dangerFactor. Each set has its own validity state. */
static uint16 WallLabel[3][256][256];
static uint32 WallLabelMap[3] = {0, 0, 0};
static uint32 WallLabelTurn[3] = {0, 0, 0};
static bool   WallLabelValid[3] = {false, false, false};
#ifdef LABEL_SELFCHECK
static unsigned long LS_Refusals, LS_Mismatch;
static void LS_Report()
  {
    fprintf(stderr, "LABEL_SELFCHECK refusals=%lu mismatches=%lu\n",
            LS_Refusals, LS_Mismatch);
    fflush(stderr);
  }
static void (*LS_Prev)(int);
static void LS_Term(int sig)
  {
    SC_Buf s;
    s.Str("LABEL_SELFCHECK refusals="); s.Num(LS_Refusals);
    s.Str(" mismatches="); s.Num(LS_Mismatch); s.Str("\n"); s.Flush();
    SC_Done(LS_Prev, sig);
  }
/* at startup, so a run cut before its first refusal still writes a tally */
static struct LS_Init { LS_Init() { atexit(LS_Report); SC_Install(LS_Term, &LS_Prev); } } LS_InitOnce;
#endif

static bool LabelSolid(Map *m, int x, int y, int set)
  {
    if (!m->SolidAt(x,y))
      return false;
    for (Door *d = m->FDoorAt(x,y); d; d = m->NDoorAt(x,y))
      if (!d->isPassable() &&
          !(d->DoorFlags & (set == 2 ? DF_SECRET : (DF_LOCKED | DF_SECRET))))
        return false;
    return true;
  }

static void BuildWallLabels(Map *m, int16 sizeX, int16 sizeY, int set)
  {
#ifdef PATH_PROBE
    double ppT0 = PP_Now();
#endif
    static uint32 Queue[65536];
    int lx = min((int16)256, sizeX), ly = min((int16)256, sizeY);
    int x, y, k;
    uint16 next = 0;
    uint16 (*L)[256] = WallLabel[set];
    for (x = 0; x != 256; x++)
      for (y = 0; y != 256; y++)
        L[x][y] = 0;
    for (x = 0; x != lx; x++)
      for (y = 0; y != ly; y++)
        {
          if (L[x][y] || (x == 0 && y == 0) || (set ? LabelSolid(m,x,y,set) : m->SolidAt(x,y)))
            continue;
          next++;
          int qh = 0, qt = 0;
          L[x][y] = next;
          Queue[qt++] = x + y*256;
          while (qh != qt)
            {
              int cx = Queue[qh] % 256, cy = Queue[qh] / 256;
              qh++;
              for (k = 0; k != 8; k++)
                {
#ifdef LABEL_BREAK
                  if (DirX[k] && DirY[k]) continue;
#endif
                  int nx = cx + DirX[k], ny = cy + DirY[k];
                  if (nx < 0 || ny < 0 || nx >= lx || ny >= ly) continue;
                  if (nx == 0 && ny == 0) continue;
                  if (L[nx][ny] || !m->InBounds(nx,ny)) continue;
                  if (set ? LabelSolid(m,nx,ny,set) : m->SolidAt(nx,ny)) continue;
                  L[nx][ny] = next;
                  Queue[qt++] = nx + ny*256;
                }
            }
        }
    WallLabelMap[set] = m->myHandle;
    WallLabelTurn[set] = theGame->Turn;
    WallLabelValid[set] = true;
#ifdef PATH_PROBE
    PP_LabelRebuilds++;
    PP_LabelSecs += PP_Now() - ppT0;
#endif
  }

bool Map::ShortestPath(uint8 sx, uint8 sy, uint8 tx, uint8 ty,
                       Creature *runner, int32 dangerFactor,
                       uint16 *ThePath, int32 *outCost, bool memonly)
  {
    int32 xy, i, c; int16 x, y, nx, ny;
    static int16 Dist[256][256];
    static uint16 Parent[256][256];
    /* inc-zm6li: doors to break on the best path to each square. Used only
       when dangerFactor has DF_BASH_DOORS; every other search leaves it alone. */
    static int16 Brk[256][256];
    const bool bash = (dangerFactor & DF_BASH_DOORS) != 0;

    if (!ThePath)
      ThePath = ::ThePath;

#ifdef PATH_PROBE
    PP_Call ppCall(dangerFactor,sx,sy,tx,ty);
#endif
    ASSERT(InBounds(sx,sy))
    ASSERT(InBounds(tx,ty))
    PQHeapN = 0;
    PQSeq   = 0;

    MCCacheOn = true;
    MCCacheN  = 0;

    bool Incor = 
      runner->HasMFlag(M_INCOR) ||
      runner->HasStati(PHASED);
    bool Meld = 
      runner->HasAbility(CA_EARTHMELD);

    /* Pre-check: a search enters a square only when RunOver(nx,ny,memonly,...)
       returns non-zero with exactly these arguments, so if the target itself
       fails RunOver it can never be entered. Unless start==target, the search
       then cannot succeed and would flood the region before returning false.
       Same answer as the full search, reached without the flood. */
    if ((sx != tx || sy != ty) &&
        RunOver(tx,ty,memonly,runner,dangerFactor,Incor,Meld,true) == 0)
      {
#ifdef PATH_PROBE
        PP_Prechk++;
        { Creature *pc = FCreatureAt(tx,ty);
          PP_Classify(2, runner, PP_Purpose, 0, !pc ? 0 : pc->isPlayer() ? 2 : 1,
                      0, 0, 0.0, tx, ty, myHandle); }
#endif
        MCCacheOn = false;
        return false;
      }

    /* inc-vhkei: refuse only when walls alone separate start and target, on
       labels built just now (solid squares change as doors open and close,
       even within one Turn, so a refusal never rests on older labels). A
       same-area answer is only a hint, so the search runs. Invariant: a label
       refusal never refuses a route the full search finds. The runner's door
       rule picks the set (DF_BASH_DOORS: set 2, DF_OPEN_DOORS: set 1, else
       set 0); sets 0 and 1 are exact, set 2 may join more (inc-zm6li). */
#ifdef LABEL_SELFCHECK
    bool labelCut = false;
    int  labelSet = 0;
#endif
    if (!Incor && !Meld)
      {
        const int set = (dangerFactor & DF_BASH_DOORS) ? 2 :
                        (dangerFactor & DF_OPEN_DOORS) ? 1 : 0;
        uint16 (*L)[256] = WallLabel[set];
        if (!WallLabelValid[set] || WallLabelMap[set] != (uint32)myHandle)
          BuildWallLabels(this,sizeX,sizeY,set);
        if (L[sx][sy] && L[sx][sy] != L[tx][ty])
          {
            BuildWallLabels(this,sizeX,sizeY,set);
            if (L[sx][sy] && L[sx][sy] != L[tx][ty])
              {
#ifdef PATH_PROBE
                PP_LabelCut++;
                PP_LabelCutSet[ppCall.door]++;
#endif
#ifdef LABEL_SELFCHECK
                labelCut = true;
                labelSet = set;
#else
                MCCacheOn = false;
                return false;
#endif
              }
          }
      }

#ifdef PATH_PROBE
    ppCall.ResetStart();
#endif
    /* Only the squares this map has. The arrays are dimensioned for the
       largest map the engine allows and this loop used to clear all of both,
       65,536 cells and 131,072 writes, whatever the level's real size. A
       128x128 level uses a quarter of that, and the search that follows looks
       at eight squares on average. Measured over one long session: 1,045,755
       calls, 8.0 squares examined per call. See inc-2k3. */
    {
      int16 lx = min((int16)256, sizeX), ly = min((int16)256, sizeY);
      for (x = 0; x != lx; x++)
        for (y = 0; y != ly; y++)
          {
            Dist[x][y]   = 30000;
            Parent[x][y] = 0;
            if (bash) Brk[x][y] = 30000;
          }
    }

#ifdef PATH_PROBE
    ppCall.FloodStart();
#endif
    Dist[sx][sy] = 0;
    if (bash) Brk[sx][sy] = 0;

    PQInsert(sx+sy*256,AStarH(sx,sy,tx,ty),0);

    while ((xy = PQPeekMin()) != -1)
      {
        int16 PW = PQHeap[0].Weight;
        int16 PB = PQHeap[0].Breaks;
        PQPopMin();
        x = (int16)(xy % 256);
        y = (int16)(xy / 256);

        /* Lazily discard a stale entry: the node was relaxed to a smaller
           distance after this copy was inserted, so this pop is a ghost. */
        { int16 bk = bash ? Brk[x][y] : 0;
          if (PB > bk || (PB == bk && PW > Dist[x][y] + AStarH(x,y,tx,ty)))
            continue; }

#ifdef PATH_PROBE
        PP_Pops++;
#endif

        /* Early stop: the queue is ordered by Dist + h, and h is consistent,
           so the first time the target is popped (h = 0) its Dist is final. */
        if (x == (int16)tx && y == (int16)ty)
          {
#ifdef PATH_PROBE
            PP_TgtHit++;
#endif
            break;
          }

        for (i=0;i!=8;i++) {
          nx = x + DirX[i];
          ny = y + DirY[i];
          /* KLUDGE: We consider (0,0) to be offmap so that we can use
             node 0 as a special empty/unmarked value. */
          if (nx == 0 && ny == 0)
            continue;
          if (!InBounds(nx,ny))
            continue;
#ifdef PATH_PROBE
          PP_RunOver++;
#endif
          bool isBrk = false;
          int baseCost = RunOver(nx&0xFF,ny&0xFF,memonly,runner,dangerFactor,Incor,Meld,
                                (nx == (int16)tx && ny == (int16)ty),&isBrk);
          if (!baseCost)
            {
#ifdef PATH_PROBE
              if (!SolidAt(nx&0xFF,ny&0xFF))
                {
                  Door *pd = FDoorAt(nx&0xFF,ny&0xFF); int k = 3;
                  if (pd && !pd->isPassable())
                    k = (pd->DoorFlags & DF_SECRET) ? 1 : 0;
                  else
                    for (Creature *pa=FCreatureAt(nx&0xFF,ny&0xFF);pa;pa=NCreatureAt(nx&0xFF,ny&0xFF))
                      if (runner->Perceives(pa) && pa->isHostileTo(runner)) { k = 2; break; }
                  ppCall.rej[k]++;
                  { int rr = PP_RefuseReason(this,nx,ny,memonly,runner,dangerFactor,Incor,Meld,
                                (nx == (int16)tx && ny == (int16)ty));
                    ppCall.rr[rr]++;
                    if (rr == PPR_WARN) { int ws = PP_WarnSlot(PP_LastWarn); if (ws >= 0) ppCall.wn[ws]++; } }
                }
#endif
              continue;
            }
          if (DirX[i] && DirY[i])
            baseCost = (baseCost * 3) / 2;

          int16 nb = bash ? (int16)(Brk[x][y] + (isBrk ? 1 : 0)) : 0;
          if (bash ? (nb < Brk[nx][ny] ||
                      (nb == Brk[nx][ny] && Dist[x][y] + baseCost < Dist[nx][ny]))
                   : (Dist[x][y] + baseCost < Dist[nx][ny]))
            {
              Dist[nx][ny] = min(30000,Dist[x][y] + baseCost);
              if (bash) Brk[nx][ny] = nb;
              Parent[nx][ny] = x+y*256;
              PQInsert(nx+ny*256,Dist[nx][ny] + AStarH(nx,ny,tx,ty),nb);
            }
          }
      }

#ifdef PATH_PROBE
    ppCall.FloodEnd(xy != -1);
    if (bash && Dist[tx][ty] != 30000)
      { int bk = Brk[tx][ty] > 0; PP_BrkN[bk]++; PP_BrkPops[bk] += ppCall.lastPops; }
    { int nbr = 0, reached = (Dist[tx][ty] != 30000);
      for (i=0;i<8;i++)
        { int16 ax = tx + DirX[i], ay = ty + DirY[i];
          if (InBounds(ax,ay) && !(ax == 0 && ay == 0) && Dist[ax][ay] != 30000) nbr = 1; }
      Creature *pc = FCreatureAt(tx,ty);
      int strict = RunOver(tx,ty,false,runner,dangerFactor,Incor,Meld,false) != 0;
      int cls = reached ? 0 : 1;
      for (i=0;i<4;i++) PP_Rej[cls][i] += ppCall.rej[i];
      for (i=0;i<PPR_N;i++) PP_RR[cls][i] += ppCall.rr[i];
      if (cls) { for (i=0;i<64;i++) PP_WN[i].n[cls] += ppCall.wn[i];
        int best = -1; unsigned long long bn = 0;
        for (i=0;i<PPR_N;i++) if (ppCall.rr[i] > bn) { bn = ppCall.rr[i]; best = i; }
        if (best >= 0) PP_Dom[cls][best]++;
        int wp = (PP_Purpose < 0 || PP_Purpose > 63) ? 63 : PP_Purpose;
        int open = PP_WallReach(this,sx,sy,tx,ty,Incor,Meld,runner) ? 1 : 0;
        PP_WallN[wp][open]++; PP_WallT[wp][open] += ppCall.lastT; }
      PP_Classify(cls, runner, PP_Purpose, strict, !pc ? 0 : pc->isPlayer() ? 2 : 1,
                  nbr, ppCall.lastPops, ppCall.lastT, tx, ty, myHandle); }
#endif
#ifdef ASTAR_SELFCHECK
    { /* rerun as plain Dijkstra (weight = Dist) and compare to the A* result */
      int16 lx = min((int16)256, sizeX), ly = min((int16)256, sizeY);
      for (int16 ax = 0; ax != lx; ax++)
        for (int16 ay = 0; ay != ly; ay++) AS_D[ax][ay] = 30000;
      PQHeapN = 0; PQSeq = 0;
      AS_D[sx][sy] = 0; PQInsert(sx+sy*256,0);
      while ((xy = PQPeekMin()) != -1)
        {
          int16 pw = PQHeap[0].Weight; PQPopMin();
          int16 ax = xy % 256, ay = xy / 256;
          if (pw > AS_D[ax][ay]) continue;
          if (ax == (int16)tx && ay == (int16)ty) break;
          for (int k=0;k!=8;k++)
            {
              int16 bx = ax + DirX[k], by = ay + DirY[k];
              if ((bx == 0 && by == 0) || !InBounds(bx,by)) continue;
              int bc = RunOver(bx&0xFF,by&0xFF,memonly,runner,dangerFactor,Incor,Meld,
                               (bx == (int16)tx && by == (int16)ty));
              if (!bc) continue;
              if (DirX[k] && DirY[k]) bc = (bc * 3) / 2;
              if (AS_D[ax][ay] + bc < AS_D[bx][by])
                { AS_D[bx][by] = min(30000,AS_D[ax][ay] + bc);
                  PQInsert(bx+by*256,AS_D[bx][by]); }
            }
        }
      if (++AS_Calls % 1000 == 0) AS_Report(); /* a timed-out run never reaches atexit */
      if (!bash && AS_D[tx][ty] != Dist[tx][ty])
        { AS_Mismatch++;
          fprintf(stderr, "ASTAR_MISMATCH %d,%d %d,%d astar=%d dijkstra=%d\n",
                  (int)sx,(int)sy,(int)tx,(int)ty,(int)Dist[tx][ty],(int)AS_D[tx][ty]); }
      PQHeapN = 0;
    }
#endif
#ifdef LABEL_SELFCHECK
    if (labelCut)
      {
        LS_Refusals++;
        if (Dist[tx][ty] != 30000)
          { LS_Mismatch++;
            { uint16 l1 = WallLabel[labelSet][sx][sy], l2 = WallLabel[labelSet][tx][ty]; uint32 t0 = WallLabelTurn[labelSet];
              BuildWallLabels(this,sizeX,sizeY,labelSet);
              fprintf(stderr, "LABEL_MISMATCH %d,%d %d,%d old=%d/%d@%u now=%d/%d@%u\n",
                    (int)sx,(int)sy,(int)tx,(int)ty,(int)l1,(int)l2,(unsigned)t0,
                    (int)WallLabel[labelSet][sx][sy],(int)WallLabel[labelSet][tx][ty],(unsigned)theGame->Turn); } }
        if (LS_Refusals % 1000 == 0) LS_Report();
        MCCacheOn = false;
        return false;
      }
#endif
    x = tx;
    y = ty;
    c = 0;

    if (Dist[tx][ty] == 30000) {
#ifdef PATH_PROBE
      PP_TgtUnreach++;
#endif
      #ifdef DEBUG_DJIKSTRA
      for (x = min(0,sx-30);x!=max(127,sx+30);x++)
        for (y = min(0,sx-30);y!=max(127,sy+30);y++)
          if (Dist[x][y] != 30000)
            {
              At(x,y).Glyph =
                GLYPH_VALUE(GLYPH_FLOOR2, EMERALD);
              At(x,y).Memory =
				  GLYPH_VALUE(GLYPH_FLOOR2, EMERALD);
              At(x,y).Shade = false;
            }              
      #endif
      MCCacheOn = false;
      return false;
      }

    if (outCost)
      *outCost = Dist[tx][ty];

    do {
      c++;
      xy = Parent[x][y];
      x = (int16)(xy % 256);
      y = (int16)(xy / 256);
      }
    while (xy);

    x = tx;
    y = ty;
    i = 0; c--;
    do {
      ThePath[c - i] = x + y*256;
      xy = Parent[x][y];
      x = (int16)(xy % 256);
      y = (int16)(xy / 256);
      i++;
      }
    while (xy);

    ThePath[c+1] = 0;

    #ifdef DEBUG_DJIKSTRA
    for (i=0;i==0 || ThePath[i];i++) {
      At(ThePath[i]%256,ThePath[i]/256).Glyph =
		  GLYPH_VALUE(GLYPH_FLOOR2, MAGENTA);
      At(ThePath[i]%256,ThePath[i]/256).Memory =
		  GLYPH_VALUE(GLYPH_FLOOR2, MAGENTA);
      At(ThePath[i]%256,ThePath[i]/256).Shade = false;
      }
    #endif

    MCCacheOn = false;
    return true;



  }

uint16 Map::PathPoint(int16 n)
  { return ThePath[n]; }

/* The route gate movement refuses: a material-plane mover without
   CA_EARTHMELD may not leave its region for a region smaller than its A_SIZ.
   src/Move.cpp tests exactly this, and only when the two squares are in
   different regions, so a creature already inside may move within it.
   Shared by Map::RunOver and Map::RunToFailReason so the two cannot drift. */
static bool RegionTooSmallFor(Map *m, int16 x, int16 y, Creature *c)
{
  if (!c)
    return false;
  if (c->onPlane() != PHASE_MATERIAL || c->HasAbility(CA_EARTHMELD))
    return false;
  rID r = m->RegionAt(x, y);
  if (!r)
    return false;
  if (r == m->RegionAt(c->x, c->y))
    return false;
  return TREG(r)->Size < c->GetAttr(A_SIZ);
}

/* inc-zm6li: what a runner with these flags may do with a closed door:
   0 refuse it, 1 open it (a hand opens it, no break), 2 break it down.
   A secret door is never entered. A walker with hands (DF_OPEN_DOORS) opens
   every door that is not locked and breaks a locked one only with
   DF_BASH_DOORS; a walker without hands breaks every closed door, again only
   with DF_BASH_DOORS. A door the runner has failed to break five times
   (TRIED,2 on the door, per runner) is a wall. */
static int DoorRule(Door *d, Creature *c, int32 df)
{
  if (d->DoorFlags & DF_SECRET)
    return 0;
  if ((df & DF_OPEN_DOORS) && !(d->DoorFlags & DF_LOCKED))
    return 1;
  if (!(df & DF_BASH_DOORS))
    return 0;
  if (c && d->GetStatiMag(TRIED,2,c) >= 5)
    return 0;
  return 2;
}

uint16 Map::RunOver(uint8 x, uint8 y, bool memonly, Creature *c,
                  int32 dangerFactor, bool Incor, bool Meld, bool isTarget,
                  bool *breaks)
{
  /* inc-pu6v.117: a closed door is solid (F_SOLID), so the solid test below
     refused it before the door test further down could run. A walker that opens
     doors (DF_OPEN_DOORS) treats a closed, unlocked, non-secret door as open. */
  bool openDoor = false;
  if ((dangerFactor & (DF_OPEN_DOORS | DF_BASH_DOORS)) && SolidAt(x,y)) {
    Door *od;
    for (od = FDoorAt(x,y); od; od = NDoorAt(x,y))
      if (!od->isPassable() && DoorRule(od,c,dangerFactor))
        openDoor = true;
  }
  if (!Incor && !openDoor && SolidAt(x,y)) {
    if (Meld) {
      int i = TTER(PTerrainAt(x,y,c))->Material;
      if (i == MAT_GRANITE || i == MAT_MAGMA || i == MAT_QUARTZ ||
          i == MAT_GEMSTONE || i == MAT_MINERAL)
        ; // we can walk here
      else
        return 0; 
    } else return 0;
  } 
  if (memonly && !At(x,y).Memory)
    return 0;
  /* upstream: base-code defect. Observed. inc-vmpk. Not sent.
       A region smaller than the mover is a wall: movement refuses the
     step (src/Move.cpp, "too large to enter"), so a route through it
     strands the mover at its edge. Mirrors Move.cpp's test, including
     the same-region exemption. */
  if (RegionTooSmallFor(this, x, y, c))
    return 0;
  if (At(x,y).Contents) {
    Creature *ca; Trap *tr; Door *dr;
    /* upstream: base-code defect. Observed. inc-rabe. Not sent.
         Invariant: a search's target square is enterable even when a
       perceived hostile stands on it; every other square still blocks. A
       chased target stands on that square, so without the exemption no route
       to a hostile target exists. The test is in the original v0.6.5B source
       (7b8504a3) and fails identically on Win32. */
    if (!isTarget)
      for (ca=FCreatureAt(x,y);ca;ca=NCreatureAt(x,y))
        if (ca && c->Perceives(ca) && ca->isHostileTo(c))
          return 0;
    for (tr=FTrapAt(x,y);tr;tr=NTrapAt(x,y)) {
      if (tr->TrapFlags & TS_FOUND)
        if (!(tr->TrapFlags & TS_DISARMED)) {
          if (dangerFactor & DF_IGNORE_TRAPS)
            return (sizeX * 3) + (tr->TrapLevel() * 10);
          else
            return 0;
        } 
    } 
    for (dr=FDoorAt(x,y);dr;dr=NDoorAt(x,y))
      /* upstream: base-code defect. Observed. inc-8zu. Not sent.
           A broken door is a hole you walk through, and this test used to ask
         only for DF_OPEN -- so a door carrying DF_BROKEN without DF_OPEN was a
         wall to every route search while the player and the monsters walked
         straight through it. Door::isPassable (inc/Feature.h) holds the
         engine's own answer; see the mark there for why it is upstream's, for
         the measurements, and for the other reader this fixed. */
      if (!dr->isPassable()) {
        /* inc-pu6v.117: a walker that opens doors (DF_OPEN_DOORS) may route
           through a closed door that is neither locked nor secret; it costs
           one extra normal step (an ordinary floor returns 2 below).
           inc-zm6li: DF_BASH_DOORS adds the doors it can only break down,
           reported through *breaks so the search can count them. */
        int rule = DoorRule(dr,c,dangerFactor);
        if (rule) {
          if (rule == 2 && breaks)
            *breaks = true;
          return 4;
        }
        return 0;
      }
  }
  rID stickyID = StickyAt(x,y); 
  if (stickyID && 
      !c->HasStati(STUCK) && 
      !c->HasMFlag(M_AMORPH) && 
      !c->isAerial() && 
      c->onPlane() == PHASE_MATERIAL && 
      c->ResistLevel(AD_STUK) != -1 && 
      !c->HasAbility(CA_WOODLAND_STRIDE)) {
    if (dangerFactor & DF_IGNORE_TERRAIN) 
      return (sizeX * 3);
    else
      return 0; 
  } 

  Feature * f; 
  for (f=FFeatureAt(x,y);f;f=NFeatureAt(x,y)) 
    if (TFEAT(f->fID)->PEvent(EV_MON_CONSIDER,c,f,f->fID) == ABORT) {
      if (dangerFactor & DF_IGNORE_TERRAIN) 
        return (sizeX * 3);
      else
        return 0; 
    } 
  if (At(x,y).Terrain) { 
    rID t = PTerrainAt(x,y,c);
    if (TTER(t)->HasFlag(TF_WARN)) {
      EvReturn mc = NOTHING;
      int ci, found = 0;
      if (MCCacheOn)
        for (ci = 0; ci < MCCacheN; ci++)
          if (MCCacheID[ci] == t)
            { mc = MCCacheVal[ci]; found = 1; break; }
      if (!found) {
        mc = TTER(t)->PEvent(EV_MON_CONSIDER,c,t);
        if (MCCacheOn && MCCacheN < MC_CACHE_MAX) {
          MCCacheID[MCCacheN]  = t;
          MCCacheVal[MCCacheN] = mc;
          MCCacheN++;
        }
      }
      if (mc == ABORT) {
        if (dangerFactor & DF_IGNORE_TERRAIN) 
            return (sizeX * 3);
        else
            return 0; 
      } 
    } 
    if (TTER(t)->MoveMod)
      return 4;
    else
      return 2; 
  }
  return 2;
}

/* Why did Player::RunTo (src/Creature.cpp) refuse a destination? RunTo returns
   only a bool, but the overview-map 'R' command wants to tell the player WHICH
   gate stopped it. This finds a physical corridor to the target -- SolidAt-open
   squares only, the same graph src/Dump.cpp's reachability walk uses, so it
   passes through closed doors the player would open -- and then names the first
   square on it that RunTo's memory-enforced gate rejects. RunTo has already
   failed when this runs, so on the shortest such corridor at least one square
   must fail the gate; the one nearest the player is the obstacle the player
   meets first, and that is a true, actionable cause.

   This runs once per refused 'R' press, never in the pathfinding hot loop, so
   the per-call heap arrays cost nothing that matters. ponytail: the classify
   block below mirrors the never-relaxed branches of Map::RunOver (above) and
   of GateBlockReason (src/Dump.cpp) in the same order; keep the three in step.
   inc-otz. */
int Map::RunToFailReason(Creature *runner, int16 tx, int16 ty)
  {
    if (!runner || !InBounds(runner->x, runner->y) || !InBounds(tx, ty))
      return RTF_NOROUTE;

    int32 sx = sizeX, sy = sizeY, cells = sx * sy;
    int16 *dist  = new int16[cells];
    int32 *par   = new int32[cells];
    int32 *queue = new int32[cells];
    int32 qh = 0, qt = 0, k;
    for (k = 0; k < cells; k++) { dist[k] = -1; par[k] = -1; }

    int32 si = (int32)runner->y * sx + runner->x;
    int32 ti = (int32)ty * sx + tx;
    dist[si] = 0;
    queue[qt++] = si;
    while (qh < qt)
      {
        int32 cur = queue[qh++];
        int16 cx = (int16)(cur % sx), cy = (int16)(cur / sx);
        for (int16 d = 0; d != 8; d++)
          {
            int16 ax = cx + DirX[d], ay = cy + DirY[d];
            if (!InBounds(ax, ay))
              continue;
            int32 ai = (int32)ay * sx + ax;
            if (dist[ai] != -1)
              continue;
            if (SolidAt(ax, ay))
              continue;
            dist[ai] = (int16)(dist[cur] + 1);
            par[ai] = cur;
            queue[qt++] = ai;
          }
      }

    int reason = RTF_NONE;
    if (dist[ti] < 0)
      reason = RTF_NOROUTE;
    else
      {
        bool Incor = runner->HasMFlag(M_INCOR) || runner->HasStati(PHASED);
        bool Meld  = runner->HasAbility(CA_EARTHMELD);
        /* Follow the corridor from the target back to the player. Every square
           the gate rejects overwrites the answer, so the value left standing is
           the rejecting square nearest the player -- the first one blocking the
           way out. The player's own square is always remembered, so it is never
           the blocker. */
        for (int32 node = ti; node >= 0; node = par[node])
          {
            int16 x = (int16)(node % sx), y = (int16)(node / sx);
            if (RunOver((uint8)x, (uint8)y, true, runner,
                        DF_IGNORE_TRAPS | DF_IGNORE_TERRAIN, Incor, Meld,
                        node == ti))
              continue;                 /* this square passes the gate */
            if (!At(x, y).Memory)
              { reason = RTF_UNEXPLORED; continue; }
            reason = RTF_UNEXPLORED;     /* default if the scans below find nothing */
            bool named = false;
            if (node != ti)   /* the target's own hostile occupant is not a blocker */
             for (Creature *ca = FCreatureAt(x, y); ca; ca = NCreatureAt(x, y))
              if (ca && runner->Perceives(ca) && ca->isHostileTo(runner))
                { reason = RTF_HOSTILE; named = true; break; }
            if (!named)
              for (Door *dr = FDoorAt(x, y); dr; dr = NDoorAt(x, y))
                if (!dr->isPassable())
                  { reason = RTF_DOOR; named = true; break; }
            if (!named && RegionTooSmallFor(this, x, y, runner))
              reason = RTF_TOOSMALL;
          }
      }

    delete [] dist;
    delete [] par;
    delete [] queue;
    return reason;
  }
