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


struct PQueue
  {
    int16 Weight;
    NArray<uint16,200,200> Elements;
    PQueue *Next;
    PQueue(uint16 FirstNode, int16 _Weight)
      { Next = NULL;
        Weight = Weight;
        Elements.Set(FirstNode,0);  }
  };

PQueue *PHead;

uint16 ThePath[MAX_PATH_LENGTH];

void Map::PQInsert(uint16 Node, int16 Weight)
  {
    PQueue *pq, *pq2;
    if (PHead == NULL || PHead->Weight > Weight)
      {
        PHead = new PQueue(Node, Weight);
        return;
      }

    for(pq = PHead; pq->Next && pq->Next->Weight < Weight; pq = pq->Next) 
      ;
      
    if (pq->Weight == Weight)
      {
        pq->Elements.Add(Node);
        return;
      }
    pq2 = new PQueue(Node, Weight);
    pq2->Next = pq->Next;
    pq->Next = pq2;

    return;
  }
  
int32 Map::PQPeekMin()          
  {
    if (!PHead) 
      return -1;
    if (PHead->Elements.Total() == 0) 
      return -1;
    return PHead->Elements[0];
  }

bool Map::PQPopMin()
  {
    PQueue *pq;
    if (PQPeekMin() == -1)
      return false;
    
    /* Remove the node from the first stack */
    PHead->Elements.Remove(0);

    /* Remove the stack if it's empty */
    if (PHead->Elements.Total() == 0)
      {
        pq = PHead;
        PHead = PHead->Next;
        delete pq;
      }
    return true;
  }


#ifdef PATH_PROBE
/* Sizing inc-2k3. Counts what one pathfinding call actually does, so a fix can
   be argued from numbers rather than from reading. Not compiled by default. */
unsigned long long PP_Calls=0, PP_RunOver=0, PP_TerrEvent=0, PP_FeatEvent=0,
                   PP_Cells=0, PP_DistinctTer=0, PP_MCHit=0, PP_MCMiss=0;
static rID PP_seen[64]; static int PP_nseen;
void PP_Report(void);
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

bool Map::ShortestPath(uint8 sx, uint8 sy, uint8 tx, uint8 ty,
                       Creature *runner, int32 dangerFactor,
                       uint16 *ThePath, int32 *outCost)
  {
    int32 xy, i, c; int16 x, y, nx, ny;
    static int16 Dist[256][256];
    static uint16 Parent[256][256];

    if (!ThePath)
      ThePath = ::ThePath;

#ifdef PATH_PROBE
    { if (!PP_Calls) { extern int atexit(void (*)(void)); atexit(PP_Report); }
      PP_Calls++; PP_Cells += (unsigned long long)sizeX * sizeY; PP_nseen = 0; }
#endif
    ASSERT(InBounds(sx,sy))
    ASSERT(InBounds(tx,ty))
    PHead = NULL;

    MCCacheOn = true;
    MCCacheN  = 0;

    bool Incor = 
      runner->HasMFlag(M_INCOR) ||
      runner->HasStati(PHASED);
    bool Meld = 
      runner->HasAbility(CA_EARTHMELD);

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
          }
    }

    Dist[sx][sy] = 0;

    PQInsert(sx+sy*256,0);

    while ((xy = PQPeekMin()) != -1)
      {
        PQPopMin();
        x = (int16)(xy % 256);
        y = (int16)(xy / 256);

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
          int baseCost = RunOver(nx&0xFF,ny&0xFF,true,runner,dangerFactor,Incor,Meld);
          if (!baseCost)
            continue;
          if (DirX[i] && DirY[i])
            baseCost = (baseCost * 3) / 2;

          if (Dist[x][y] + baseCost < Dist[nx][ny])
            {
              Dist[nx][ny] = min(30000,Dist[x][y] + baseCost);
              Parent[nx][ny] = x+y*256;
              PQInsert(nx+ny*256,Dist[nx][ny]);
            }
          }
      }

    x = tx;
    y = ty;
    c = 0;

    if (Dist[tx][ty] == 30000) {
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

uint16 Map::RunOver(uint8 x, uint8 y, bool memonly, Creature *c,
                  int32 dangerFactor, bool Incor, bool Meld)
{
  if (!Incor && SolidAt(x,y)) {
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
  if (At(x,y).Contents) {
    Creature *ca; Trap *tr; Door *dr;
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
      if (!dr->isPassable())
        return 0;
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
#ifdef PATH_PROBE
    if ((PP_FeatEvent++), TFEAT(f->fID)->PEvent(EV_MON_CONSIDER,c,f,f->fID) == ABORT) {
#else
    if (TFEAT(f->fID)->PEvent(EV_MON_CONSIDER,c,f,f->fID) == ABORT) {
#endif
      if (dangerFactor & DF_IGNORE_TERRAIN) 
        return (sizeX * 3);
      else
        return 0; 
    } 
  if (At(x,y).Terrain) { 
    rID t = PTerrainAt(x,y,c);
    if (TTER(t)->HasFlag(TF_WARN)) {
#ifdef PATH_PROBE
      { int _i; bool _f = false;
        PP_TerrEvent++;
        for (_i = 0; _i < PP_nseen; _i++) if (PP_seen[_i] == t) { _f = true; break; }
        if (!_f && PP_nseen < 64) { PP_seen[PP_nseen++] = t; PP_DistinctTer++; } }
#endif
      EvReturn mc = NOTHING;
      int ci, found = 0;
      if (MCCacheOn)
        for (ci = 0; ci < MCCacheN; ci++)
          if (MCCacheID[ci] == t)
            { mc = MCCacheVal[ci]; found = 1; break; }
#ifdef PATH_PROBE
      if (found) PP_MCHit++; else PP_MCMiss++;
#endif
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

#ifdef PATH_PROBE
#include <stdio.h>
void PP_Report(void) {
  if (!PP_Calls) return;
  fprintf(stderr,
    "PATHPROBE calls=%llu runover=%llu (%.1f/call) terrain-events=%llu (%.1f/call)"
    " distinct-terrains=%llu (%.2f/call) feature-events=%llu (%.1f/call)"
    " live-cells=%llu (%.0f/call, vs 65536 cleared)"
    " consider-cache: reused=%llu ran=%llu\n",
    PP_Calls, PP_RunOver, (double)PP_RunOver/PP_Calls,
    PP_TerrEvent, (double)PP_TerrEvent/PP_Calls,
    PP_DistinctTer, (double)PP_DistinctTer/PP_Calls,
    PP_FeatEvent, (double)PP_FeatEvent/PP_Calls,
    PP_Cells, (double)PP_Cells/PP_Calls, PP_MCHit, PP_MCMiss);
  fflush(stderr);
}
#endif
