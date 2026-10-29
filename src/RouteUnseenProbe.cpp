/* inc-vhkei reproduction hook: does a creature move toward its target through
   ground the PLAYER has never seen?
   Off unless INCURSION_ROUTE_UNSEEN is set; with it unset nothing here writes
   game state or a file. tools/check_route_unseen.sh is the only caller.

   THE DEFECT. Monster::SmartDirTo (src/Monster.cpp) asks Map::ShortestPath for
   a route and the flood runs over the PLAYER's map memory
   (RunOver(...,memonly=true,...), src/Djikstra.cpp "if (memonly &&
   !At(x,y).Memory) return 0;"). So every square the player has not seen is
   impassable to it: a creature in a room the player never saw finds no route,
   SmartDirTo returns CENTER, and the creature waits every turn. The search runs
   only on OPT_MON_DJIKSTRA YES (1) for any creature, or PETS (2) for a
   companion (is_pet true); otherwise SmartDirTo steps straight (DirTo).

   WHAT THIS STAGES. A fixed L-shaped one-square corridor in a sealed box,
   independent of the generated level: player at (px,py), corridor east then
   south, the watched creature at the far end. Every arena square except the
   player's own is left with Memory 0, cleared again each turn so the player's
   field of view cannot re-see the route. Its own Monster::Movement ->
   Monster::SmartDirTo moves it, so the route search runs under the option.

   INCURSION_ROUTE_UNSEEN picks the creature and its real reason to move:
     hostile    hostile to the player, TRACKING it (perceives through walls)
     companion  MakeCompanion to the player (PHD_PARTY), follows getLeader()
     neutral    TurnNeutralTo and an inc-9622 investigate TargetArea
   INCURSION_ROUTE_OPT sets OPT_MON_DJIKSTRA (0,1,2); INCURSION_ROUTE_TURNS is
   how many turns to watch. RouteUnseenPerTurn() runs once per player turn
   (src/Main.cpp): clears the route squares' memory, logs to
   logs/routeunseen.log ("route at=.. tgt=.. turn=N dist=D opt=V ..."). */
#include "Incursion.h"
#include <cstdarg>
#include <cstdlib>
#include <cstdio>
#include <cstring>

/* Corridor shape: the player at (px,py), floor east to (px+ROUTE_LE,py) then
   south to (px+ROUTE_LE,py+ROUTE_LS), the creature at the far end. Kept short
   so the creature stays inside the radius at which the game gives it a turn. */
#define ROUTE_LE 5
#define ROUTE_LS 4

static hObj   RouteMon  = 0;
static hObj   RoutePlayer = 0;
static int    RouteTx   = 0, RouteTy = 0;
static bool   RouteStaged = false;
static uint32 RouteTurnStart = 0;

static const char *RouteMode() {    const char *e = getenv("INCURSION_ROUTE_UNSEEN");
    return (e && *e) ? e : NULL;
}

static int RouteOpt() {
    const char *e = getenv("INCURSION_ROUTE_OPT");
    int v = e ? atoi(e) : 1;
    return (v >= 0 && v <= 2) ? v : 1;
}

static int RouteTurns() {
    const char *e = getenv("INCURSION_ROUTE_TURNS");
    int v = e ? atoi(e) : 30;
    return (v > 0 && v <= 1000) ? v : 30;
}

static FILE *RouteLogFile() {    static FILE *f = NULL;
    if (!f) {
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/routeunseen.log",
                 (const char*)T1->IncursionDirectory);
        f = fopen(path, "a");
    }
    return f;
}

static void RouteUnseenLog(const char *fmt, ...) {
    FILE *f = RouteLogFile();
    va_list ap;
    if (!f) return;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fflush(f);
}

/* Clear memory on every arena square except the player's own, so no route
   square is ever "seen" no matter what the player's field of view refreshes. */
static void RouteClearMemory(Map *m, int px, int py, int x0, int y0, int x1, int y1) {
    for (int x = x0; x <= x1; x++)
        for (int y = y0; y <= y1; y++)
            if (!(x == px && y == py))
                m->At(x, y).Memory = 0;
}

/* Called once, when the overview map first opens (src/Term.cpp), the same
   hook RunToStage uses. Serves inc-vhkei, tools/check_route_unseen.sh. */
void RouteUnseenStage(Map *m, Player *p) {
    const char *mode = RouteMode();
    int px, py, x, y, i, LE = ROUTE_LE, LS = ROUTE_LS;
    rID wall, floor_, reg, monid;
    if (!mode || RouteStaged || !m || !p)
        return;
    RouteStaged = true;
    px = p->x; py = p->y;
    monid = FIND("giant rat");
    wall = FIND("Dungeon Wall"); floor_ = FIND("Floor"); reg = FIND("Winding Corridor");
    if (!monid || !wall || !floor_ || !reg ||
        !m->InBounds(px - 1, py - 1) || !m->InBounds(px + LE + 1, py + LS + 1)) {
        RouteUnseenLog("stage failed reason=resources-or-bounds mode=%s\n", mode);
        return;
    }
    /* Any other creature spoils the scene; items and features are cleared. */
    for (x = px - 1; x <= px + LE + 1; x++)
        for (y = py - 1; y <= py + LS + 1; y++) {
            Thing *t, *nx;
            if (x == px && y == py) continue;
            for (t = oThing(m->At(x, y).Contents); t; t = nx) {
                nx = oThing(t->Next);
                if (t->isCreature()) {
                    RouteUnseenLog("stage failed reason=creature at=%d,%d mode=%s\n", x, y, mode);
                    return;
                }
                t->Remove(true);
            }
        }
    /* Wall the box, then open the L corridor. */
    for (x = px - 1; x <= px + LE + 1; x++)
        for (y = py - 1; y <= py + LS + 1; y++)
            m->WriteTerra(x, y, wall);
    for (i = 0; i <= LE; i++) {
        m->WriteTerra(px + i, py, floor_);
        m->SetRegion(Rect(px + i, py, px + i, py), reg);
    }
    for (i = 1; i <= LS; i++) {
        m->WriteTerra(px + LE, py + i, floor_);
        m->SetRegion(Rect(px + LE, py + i, px + LE, py + i), reg);
    }
    /* Terrain renders; then every arena square is memory-cleared. */
    for (x = px - 1; x <= px + LE + 1; x++)
        for (y = py - 1; y <= py + LS + 1; y++)
            m->Update(x, y);
    RouteClearMemory(m, px, py, px - 1, py - 1, px + LE + 1, py + LS + 1);

    p->Options[OPT_MON_DJIKSTRA] = (int16)RouteOpt();

    /* The player case. Same sealed L corridor, but no watched creature: the
       PLAYER asks to travel to the far end with Player::RunTo (src/Creature.cpp)
       -- the function the overview map's [R] Run to Point calls -- and the
       probes's control shows the same request reaching the far end when the
       corridor's memory is intact. RunTo routes with Map::ShortestPath's DEFAULT
       memonly=true, so with memory cleared it must refuse. Serves
       tools/check_route_unseen.sh, inc-vhkei. */
    if (!strcmp(mode, "player")) {
        int farx = px + LE, fary = py + LS;
        bool declined = false, ctl, un;
        RoutePlayer = p->myHandle;
        RouteTurnStart = theGame->Turn;
        /* Control: memory intact (what the player sees after walking there). */
        for (x = px - 1; x <= px + LE + 1; x++)
            for (y = py - 1; y <= py + LS + 1; y++)
                m->At(x, y).Memory = m->At(x, y).Glyph;
        p->RemoveStati(ACTING);
        ctl = p->RunTo((int16)farx, (int16)fary, &declined);
        RouteUnseenLog("player runto phase=seen from=%d,%d to=%d,%d accepted=%d\n",
                       (int)p->x, (int)p->y, farx, fary, (int)ctl);
        if (p->HasStati(ACTING))
            p->RemoveStati(ACTING);
        /* Candidate: the same request, corridor's memory cleared (as the nine
           creature cases stage it). */
        RouteClearMemory(m, p->x, p->y, px - 1, py - 1, px + LE + 1, py + LS + 1);
        declined = false;
        un = p->RunTo((int16)farx, (int16)fary, &declined);
        RouteUnseenLog("player runto phase=unseen from=%d,%d to=%d,%d accepted=%d declined=%d\n",
                       (int)p->x, (int)p->y, farx, fary, (int)un, (int)declined);
        if (p->HasStati(ACTING))
            p->RemoveStati(ACTING);
        RouteUnseenLog("stage mode=player player=%d,%d dest=%d,%d opt=%d turns=%d ph=%d\n",
                       px, py, farx, fary, (int)theGame->Opt(OPT_MON_DJIKSTRA),
                       RouteTurns(), (int)p->myHandle);
        return;
    }

    Monster *mn = new Monster(monid);
    TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    mn->PlaceAt(m, px + LE, py + LS);
    mn->Initialize(true);
    mn->RemoveStati(ASLEEP);
    mn->RemoveStati(SLEEPING);
    mn->CalcValues();
    /* Give each creature a real reason for its own AI to move, so
       Monster::Movement -> Monster::SmartDirTo (src/Monster.cpp) drives it. */
    if (!strcmp(mode, "companion")) {
        mn->MakeCompanion(p, PHD_PARTY);
    } else if (!strcmp(mode, "neutral")) {
        mn->ts.TurnNeutralTo(mn, p);
        mn->ts.SetInvestigateTarget(mn, (uint8)px, (uint8)py, TargetHeardNoise);
    } else {
        /* Hostile: put the player on the target list and let the creature
           track it. TRACKING makes Perceives (src/Vision.cpp) return
           PER_TRACK, so vis is nonzero even with no line of fire down the
           sealed corridor, and the TargetEnemy survives the ChooseAction
           refresh (src/Monster.cpp). */
        mn->GainPermStati(TRACKING, p, SS_MISC, 0, 200);
        mn->ts.addCreatureTarget(p, TargetEnemy);
    }
    RouteMon = mn->myHandle;
    RoutePlayer = p->myHandle;
    RouteTx = px; RouteTy = py;
    RouteTurnStart = theGame->Turn;

    RouteUnseenLog("stage mode=%s mon=%d,%d player=%d,%d tgt=%d,%d opt=%d "
                   "hostile=%d leader=%d lof=%d turns=%d ph=%d mh=%d\n",
                   mode, (int)mn->x, (int)mn->y, px, py, px, py,
                   (int)theGame->Opt(OPT_MON_DJIKSTRA),
                   (int)mn->isHostileTo(p), (int)(mn->ts.getLeader() == p),
                   (int)m->LineOfFire(mn->x, mn->y, px, py, mn), RouteTurns(),
                   (int)p->myHandle, (int)mn->myHandle);
}

/* Called once per player turn from the main game loop (src/Main.cpp), right
   before the turn counter advances, so it runs whether or not the creature
   itself acted. Clears the route squares' memory (the player's field of view
   must not re-see them) and logs the watched creature's square and distance
   to its target. */
void RouteUnseenPerTurn(Player *p) {
    Monster *mn;
    Map *m;
    int px, py, dist_;
    if (!RouteMon || !RoutePlayer || !RouteStaged || !p)
        return;
    if (p->myHandle != RoutePlayer)
        return;
    if (!isValidHandle(RouteMon))
        return;
    mn = (Monster*)oCreature(RouteMon);
    if (!mn || !(m = mn->m))
        return;
    px = p->x; py = p->y;
    if (theGame->Turn - RouteTurnStart > RouteTurns())
        return;
    RouteClearMemory(m, px, py, px - 1, py - 1, px + ROUTE_LE + 1, py + ROUTE_LS + 1);
    dist_ = dist(mn->x, mn->y, RouteTx, RouteTy);
    RouteUnseenLog("route at=%d,%d tgt=%d,%d turn=%d dist=%d opt=%d "
                   "hostile=%d leader=%d\n",
                   (int)mn->x, (int)mn->y, RouteTx, RouteTy,
                   (int)theGame->Turn, dist_,
                   (int)theGame->Opt(OPT_MON_DJIKSTRA),
                   (int)mn->isHostileTo(p), (int)(mn->ts.getLeader() == p));
}

/* Called from Monster::SmartDirTo (src/Monster.cpp) at every return, watched
   creature only, so the log says which branch ran and what direction came out.
   Off unless INCURSION_ROUTE_UNSEEN staged the watched creature. */
void RouteUnseenSmartDirTo(Monster *mn, int16 tx, int16 ty, bool is_pet,
                           const char *branch, Dir ret) {
    if (!RouteMon || !RouteStaged || !mn || mn->myHandle != RouteMon)
        return;
    RouteUnseenLog("smartdir turn=%d at=%d,%d tgt=%d,%d opt=%d pet=%d "
                   "branch=%s ret=%d\n",
                   (int)theGame->Turn, (int)mn->x, (int)mn->y,
                   (int)tx, (int)ty, (int)theGame->Opt(OPT_MON_DJIKSTRA),
                   (int)is_pet, branch, (int)ret);
}

/* Called from Monster::Movement (src/Monster.cpp) once the follow branches have
   run, watched creature only, so the log names which Movement branch steered it
   even if SmartDirTo was never reached. */
void RouteUnseenMovement(Monster *mn, const char *branch, int wx, int wy) {
    if (!RouteMon || !RouteStaged || !mn || mn->myHandle != RouteMon)
        return;
    RouteUnseenLog("movement turn=%d at=%d,%d branch=%s wx=%d wy=%d opt=%d\n",
                   (int)theGame->Turn, (int)mn->x, (int)mn->y, branch,
                   wx, wy, (int)theGame->Opt(OPT_MON_DJIKSTRA));
}

/* Called from the target loop in Monster::Movement (src/Monster.cpp, the
   SmartDirTo(ts.t[i].X(),ts.t[i].Y()) call whose is_pet defaults to false),
   watched creature only, so the log names the target type that drives it. */
void RouteUnseenTargetLoop(Monster *mn, int type, int tx, int ty) {
    if (!RouteMon || !RouteStaged || !mn || mn->myHandle != RouteMon)
        return;
    RouteUnseenLog("targetloop turn=%d at=%d,%d type=%d tgt=%d,%d opt=%d pet=0\n",
                   (int)theGame->Turn, (int)mn->x, (int)mn->y, type, tx, ty,
                   (int)theGame->Opt(OPT_MON_DJIKSTRA));
}
