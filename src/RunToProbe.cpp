/* inc-vmpk reproduction hooks for the overview map's Run to Point.
   Off unless INCURSION_RUNTO_PROBE (log) or INCURSION_RUNTO_STAGE (scene)
   is set; with both unset nothing here writes game state or a file.
   tools/check_runto_hazards.sh is the only caller.
   Serves inc-vmpk. */
#include "Incursion.h"
#include <cstdarg>
#include <cstdlib>
#include <cstdio>

hObj RunToWatched = 0;

/* INCURSION_RUNTO_SKILL_ROLL=<1..20> forces the d20 of every skill check;
   0 (unset) leaves the roll alone. Serves inc-vmpk. */
int RunToSkillRoll() {
    const char *e = getenv("INCURSION_RUNTO_SKILL_ROLL");
    int v = e ? atoi(e) : 0;
    return (v >= 1 && v <= 20) ? v : 0;
}

void RunToProbe(const char *fmt, ...) {
    static FILE *f = NULL;
    va_list ap;
    if (!getenv("INCURSION_RUNTO_PROBE"))
        return;
    if (!f) {
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/runtoprobe.log",
                 (const char*)T1->IncursionDirectory);
        f = fopen(path, "a");
    }
    if (!f)
        return;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fflush(f);
}


/* Case M. A sealed box holding two routes between the character (0,0) and an
   ogre, who is the character's companion and so follows him with
   Monster::SmartDirTo (src/Monster.cpp). Offsets from the character:
     short route  (1..5,0) east, then (5,1)..(5,4) south through a Medium
                  region ("Twisty Little Passage"), ogre at (5,5)
     detour       (5,6)(5,7)(5,8), (4..0,8) west, (0,7)..(0,1) north
   All other open squares are the Large "Winding Corridor" region, which an ogre
   (Large) may enter. The ogre has no line of fire to the character. */
static void RunToStageM(Map *m, Player *p) {
    int px = p->x, py = p->y, x, y, i;
    rID wall = FIND("Dungeon Wall"), floor_ = FIND("Floor");
    rID large = FIND("Winding Corridor"), med = FIND("Twisty Little Passage");
    rID ogre = FIND("ogre");
    static const int sh[][2] = {{1,0},{2,0},{3,0},{4,0},{5,0},{5,1},{5,2},{5,3},{5,4},{5,5}};
    static const int de[][2] = {{5,6},{5,7},{5,8},{4,8},{3,8},{2,8},{1,8},{0,8},
                                {0,7},{0,6},{0,5},{0,4},{0,3},{0,2},{0,1}};
    if (!wall || !floor_ || !large || !med || !ogre ||
        !m->InBounds(px - 1, py - 1) || !m->InBounds(px + 6, py + 9)) {
        RunToProbe("stage failed reason=resources-or-bounds\n");
        return;
    }
    for (x = px - 1; x <= px + 6; x++)
        for (y = py - 1; y <= py + 9; y++) {
            Thing *t, *nx;
            if (x == px && y == py)
                continue;
            for (t = oThing(m->At(x, y).Contents); t; t = nx) {
                nx = oThing(t->Next);
                if (t->isCreature()) {
                    RunToProbe("stage failed reason=creature at=%d,%d\n", x, y);
                    return;
                }
                t->Remove(true);
            }
        }
    for (x = px - 1; x <= px + 6; x++)
        for (y = py - 1; y <= py + 9; y++)
            m->WriteTerra(x, y, wall);
    m->WriteTerra(px, py, floor_);
    m->SetRegion(Rect(px, py, px, py), large);
    for (i = 0; i < 10; i++) {
        m->WriteTerra(px + sh[i][0], py + sh[i][1], floor_);
        m->SetRegion(Rect(px + sh[i][0], py + sh[i][1], px + sh[i][0], py + sh[i][1]),
                     (sh[i][0] == 5 && sh[i][1] >= 1 && sh[i][1] <= 4) ? med : large);
    }
    for (i = 0; i < 15; i++) {
        m->WriteTerra(px + de[i][0], py + de[i][1], floor_);
        m->SetRegion(Rect(px + de[i][0], py + de[i][1], px + de[i][0], py + de[i][1]), large);
    }
    for (x = px - 1; x <= px + 6; x++)
        for (y = py - 1; y <= py + 9; y++) {
            m->At(x, y).Memory = m->At(x, y).Glyph;
            m->Update(x, y);
        }
    Monster *mn = new Monster(ogre);
    TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    mn->PlaceAt(m, px + 5, py + 5);
    mn->Initialize(true);
    mn->MakeCompanion(p, PHD_FREEBIE);
    RunToWatched = mn->myHandle;
    RunToProbe("stage mode=M player=%d,%d entrance=%d,%d mon=%d,%d "
               "monsize=%d medsize=%d lof=%d opt=%d leader=%d\n",
               px, py, px + 5, py + 5, (int)mn->x, (int)mn->y,
               (int)mn->GetAttr(A_SIZ), (int)TREG(med)->Size,
               (int)m->LineOfFire(mn->x, mn->y, px, py, mn),
               (int)theGame->Opt(OPT_MON_DJIKSTRA),
               (int)(mn->ts.getLeader() == p));
}

/* inc-rabe: opt-in route-function scene and rest-by-rest observations.
   INCURSION_ROUTE_PROBE=missing deliberately omits the monster.
   A U corridor has one first step (south); west is a wall. */
static void RouteProbe(Map *m, Player *p) {
    const char *mode = getenv("INCURSION_ROUTE_PROBE");
    if (!mode || !*mode || !m || !p) return;
    static bool staged = false;
    static hObj watched = 0;
    static int sample = 0;
    static uint32 start = 0;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/routeprobe.log",
             (const char*)T1->IncursionDirectory);
    FILE *f = fopen(path, "a");
    if (!f) return;
    if (!staged) {
        staged = true;
        rID wall = FIND("Dungeon Wall"), floor_ = FIND("Floor");
        rID region = FIND("Winding Corridor"), rat = FIND("giant rat");
        if (!wall || !floor_ || !region || !rat || !m->InBounds(15, 15)) {
            fprintf(f, "setup missing=1 reason=resources-or-bounds\n");
            fclose(f); return;
        }
        // Clear the scene and all ambient creatures before positioning either actor.
        for (int x = 0; x < m->SizeX(); ++x)
            for (int y = 0; y < m->SizeY(); ++y)
                for (Thing *t = oThing(m->At(x,y).Contents), *next; t; t = next) {
                    next = oThing(t->Next);
                    if (t != p && (t->isCreature() ||
                        (x >= 9 && x <= 15 && y >= 9 && y <= 15)))
                        t->Remove(true);
                }
        for (int x = 9; x <= 15; ++x)
            for (int y = 9; y <= 15; ++y) {
                bool open = ((x == 10 || x == 14) && y >= 10 && y <= 14) ||
                            (y == 14 && x >= 10 && x <= 14);
                m->WriteTerra(x, y, open ? floor_ : wall);
                m->SetRegion(Rect(x,y,x,y), region);
                m->At(x,y).Memory = m->At(x,y).Glyph;
                m->At(x,y).Lit = true;
            }
        p->PlaceAt(m, 10, 10);
        p->RemoveStati(NONDETECTION);
        p->RemoveStati(HIDING);
        p->Options[OPT_MON_DJIKSTRA] = 1;
        p->Options[OPT_AUTOMORE] = 1;
        p->cHP = p->mHP = 10000;
        start = theGame->Turn;
        if (!strcmp(mode, "missing")) {
            fprintf(f, "setup missing=1 reason=requested\n");
            fclose(f); return;
        }
        Monster *mn = new Monster(rat);
        mn->PlaceAt(m, 14, 10);
        mn->Initialize(true);
        mn->RemoveStati(ASLEEP);
        mn->RemoveStati(SLEEPING);
        mn->GainPermStati(EXTRA_ABILITY, NULL, SS_MISC, CA_TELEPATHY, 30);
        mn->CalcValues();
        mn->ts.giveOrder(mn, NULL, OrderDoNotHide);
        mn->ts.addCreatureTarget(p, TargetEnemy);
        p->ts.addCreatureTarget(mn, TargetEnemy);
        watched = mn->myHandle;
        int lof = m->LineOfFire(mn->x, mn->y, p->x, p->y, mn);
        int perceives = mn->Perceives(p);
        int hostile = p->isHostileTo(mn) && mn->isHostileTo(p);
        int straight = mn->DirTo(p->x, p->y);
        int expected = mn->DirTo(14, 11);
        int blocked = m->SolidAt(mn->x + DirX[straight], mn->y + DirY[straight]);
        int dir = mn->SmartDirTo(p->x, p->y);
        fprintf(f, "setup missing=0 mon=%d,%d player=%d,%d lof=%d perceives=%d "
                "hostile=%d opt=%d telepathy=%d straight=%d blocked=%d expected=%d "
                "center=%d dir=%d\n", mn->x, mn->y, p->x, p->y, lof, perceives,
                hostile, theGame->Opt(OPT_MON_DJIKSTRA), mn->TelepRange,
                straight, blocked, expected, CENTER, dir);
    }
    if (watched && isValidHandle(watched)) {
        Creature *mn = oCreature(watched);
        fprintf(f, "observe rest=%d tick=%u mon=%d,%d player=%d,%d adjacent=%d\n",
                sample++, (unsigned)(theGame->Turn - start), mn->x, mn->y,
                p->x, p->y, (int)(mn->m == p->m && dist(mn->x,mn->y,p->x,p->y) == 1));
    }
    fclose(f);
}

/* Build a sealed box around the player, once, when the overview map first
   opens: a one-square-wide corridor running east, ten squares long, with one
   hazard on its fifth square. Mode T a found armed trap, D deep water, S a corridor
   region whose Size is below any character's. The corridor is the only open
   ground, so every route to its far end crosses the hazard.
   Serves tools/check_runto_hazards.sh, inc-vmpk. */
void RunToStage(Map *m, Player *p) {
    RouteProbe(m, p);
    static bool done = false;
    const char *mode = getenv("INCURSION_RUNTO_STAGE");
    int px, py, x, y, hx;
    rID wall, floor_, magma, reg;
    if (!mode || !*mode || done || !m || !p)
        return;
    done = true;
    px = p->x; py = p->y; hx = px + 5;
    if (mode[0] == 'M') {
        RunToStageM(m, p);
        return;
    }
    if (!strchr("TDS", mode[0]) ||
        !m->InBounds(px - 1, py - 2) || !m->InBounds(px + 11, py + 2)) {
        RunToProbe("stage failed reason=bounds\n");
        return;
    }
    wall = FIND("Dungeon Wall"); floor_ = FIND("Floor");
    magma = FIND(getenv("INCURSION_RUNTO_TERRAIN") && *getenv("INCURSION_RUNTO_TERRAIN") ? getenv("INCURSION_RUNTO_TERRAIN") : "deep water"); reg = FIND("Winding Corridor");
    if (!wall || !floor_ || !magma || !reg) {
        RunToProbe("stage failed reason=resources\n");
        return;
    }
    /* Any other creature spoils the scene; items and features are cleared. */
    for (x = px - 1; x <= px + 11; x++)
        for (y = py - 2; y <= py + 2; y++) {
            Thing *t, *nx;
            if (x == px && y == py)
                continue;
            for (t = oThing(m->At(x, y).Contents); t; t = nx) {
                nx = oThing(t->Next);
                if (t->isCreature()) {
                    RunToProbe("stage failed reason=creature at=%d,%d\n", x, y);
                    return;
                }
                RunToProbe("stage cleared %d at=%d,%d\n", (int)t->Type, x, y);
                t->Remove(true);
            }
        }
    for (x = px - 1; x <= px + 11; x++)
        for (y = py - 2; y <= py + 2; y++)
            m->WriteTerra(x, y, wall);
    for (x = px; x <= px + 10; x++) {
        m->WriteTerra(x, py, (mode[0] == 'D' && x == hx) ? magma : floor_);
        if (mode[0] == 'S' && x > px) {
            m->SetRegion(Rect(x, py, x, py), reg);
            TREG(reg)->Size = SZ_MINISCULE;
        }
    }
    /* INCURSION_RUNTO_TRAP names the trap placed in mode T; Serves
       tools/check_runto_hazards.sh, inc-vmpk. */
    if (mode[0] == 'T') {
        Trap *t = new Trap(FIND("trap"), FIND(getenv("INCURSION_RUNTO_TRAP") && *getenv("INCURSION_RUNTO_TRAP") ? getenv("INCURSION_RUNTO_TRAP") : "howling trap"));
        t->PlaceAt(m, hx, py);
        t->TrapFlags |= TS_FOUND;
    }
    for (x = px - 1; x <= px + 11; x++)
        for (y = py - 2; y <= py + 2; y++) {
            m->At(x, y).Memory = m->At(x, y).Glyph;
            m->Update(x, y);
        }
    RunToProbe("stage mode=%c player=%d,%d hazard=%d,%d dest=%d,%d\n",
               mode[0], px, py, hx, py, px + 10, py);
}
