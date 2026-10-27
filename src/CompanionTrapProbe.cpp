/* inc-47ws: does a companion walk over a trap that has already sprung?
   Opt-in only: INCURSION_COMPANION_TRAP_PROBE=<sprung|avoided|armed|none>.
   tools/check_companion_trap.sh is the only caller. The scene is a wall with
   one gap; the trap square is the gap, so every route crosses it. */
#include "Incursion.h"
#include <cstdlib>
#include <cstring>

static const char *ctMode;
static hObj ctComp;
static Trap *ctTrap;
static int ctTx, ctTy, ctTicks, ctCrossed, ctStood;
static const int CT_TURNS = 25;

void CompanionTrapProbeTick(Player *p) {
    if (!ctMode || !ctComp || !isValidHandle(ctComp) || ctTicks > CT_TURNS) return;
    Creature *c = oCreature(ctComp);
    if (ctTicks == CT_TURNS) {
        ++ctTicks;
        Error("COMPANION_TRAP mode=%s crossed=%d flags=%x turns=%d stood=%d",
            ctMode, ctCrossed, ctTrap ? (unsigned)ctTrap->TrapFlags : 0u,
            CT_TURNS, ctStood);
        return;
    }
    bool on = c->x == ctTx && c->y == ctTy;
    if (on) ctStood = 1;
    if (c->x >= ctTx) ctCrossed = 1;   /* the gap column and beyond: the far side */
    Error("COMPANION_TRAP tick mode=%s n=%d comp=%d,%d on_trap=%d flags=%x player=%d,%d",
        ctMode, ctTicks, (int)c->x, (int)c->y, on,
        ctTrap ? (unsigned)ctTrap->TrapFlags : 0u, (int)p->x, (int)p->y);
    ++ctTicks;
}

void CompanionTrapProbe(Player *p) {
    ctMode = getenv("INCURSION_COMPANION_TRAP_PROBE");
    if (!ctMode || !*ctMode || !p || !p->m) { ctMode = NULL; return; }
    Map *m = p->m;
    for (Thing *t = m->FirstThing(); t; ) {
        Thing *next = m->NextThing();
        if (t != p) t->Remove(true);
        t = next;
    }
    int px = m->SizeX()/2, py = m->SizeY()/2;
    rID wall = FIND("Dungeon Wall"), floor_ = FIND("Floor"), reg = FIND("Winding Corridor");
    for (int x=px-11; x<=px+11; ++x)
        for (int y=py-8; y<=py+8; ++y) {
            if (!m->InBounds(x,y)) continue;
            bool west = x >= px-9 && x <= px-4 && y >= py+1 && y <= py+4;
            bool east = x >= px-2 && x <= px+4 && y >= py-3 && y <= py+4;
            bool gap  = x == px-3 && y == py+2;
            m->WriteTerra(x,y,(west||east||gap) ? floor_ : wall);
            m->SetRegion(Rect(x,y,x,y),reg);
            m->At(x,y).Lit = 1;
            m->At(x,y).Memory = m->At(x,y).Glyph;
        }
    if (TREG(m->RegionAt(px,py))->Desc) REGMEM(m->RegionAt(px,py),p)->Seen = true;
    p->PlaceAt(m,px,py);
    p->CalcValues();
    ctTx = px-3; ctTy = py+2;

    Monster *mn = new Monster(FIND("wolf"));
    mn->CalcValues();
    mn->PlaceAt(m,px-7,py+2,true);
    const bool wasPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    mn->Initialize(true);
    theGame->PlayMode = wasPlay;
    int joined = mn->MakeCompanion(p,PHD_ANIMAL);
    ctComp = mn->myHandle;

    int trapped = strcmp(ctMode,"none") != 0;
    if (trapped) {
        ctTrap = new Trap(FIND("trap"),FIND("light trap"));
        ctTrap->PlaceAt(m,ctTx,ctTy);
        ctTrap->TrapFlags |= TS_FOUND;
        ctTrap->SetImage();
        m->At(ctTx,ctTy).Memory = ctTrap->Image;
    }
    int triggered = 0;
    if (!strcmp(ctMode,"sprung") || !strcmp(ctMode,"avoided")) {
        /* a bystander (not the companion) triggers the real code path */
        Monster *v = new Monster(FIND("giant rat"));
        v->PlaceAt(m,ctTx,ctTy,true);
        v->Initialize(true);
        EventInfo e; e.Clear();
        e.EActor = v; e.EMap = m;
        ctTrap->TriggerTrap(e,true);
        triggered = 1;
        v->Remove(true);
    }
    Error("COMPANION_TRAP stage mode=%s joined=%d leader_is_player=%d lof=%d djikstra_opt=%d comp=%d,%d trap=%d,%d flags=%x triggered=%d",
        ctMode, joined, mn->ts.getLeader() == p,
        (int)m->LineOfFire(mn->x,mn->y,p->x,p->y,mn),
        (int)theGame->Opt(OPT_MON_DJIKSTRA),(int)mn->x,(int)mn->y,ctTx,ctTy,
        ctTrap ? (unsigned)ctTrap->TrapFlags : 0u, triggered);
}
