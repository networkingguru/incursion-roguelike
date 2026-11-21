/* inc-9r189: opt-in probe. Off unless INCURSION_UNSEEN_GLYPH_PROBE is set.
   Called from Game::Play (src/Main.cpp); graded by
   tools/check_unseen_spell_glyphs.sh. It builds two rooms: the player's own,
   and a closed room (walls all round, no door) the player has never seen.
   A third area, an unlit one in the player's line of sight, is the positive
   control: a spell effect there MUST still draw. Each area gets hostile
   spellcasters; then the probe returns; the key
   script lets turns pass. GlyphDrawHook (src/Magic.cpp) reports every overlay
   glyph queued (kind 1), every overlay glyph drawn by Map::Update (kind 2) and
   every direct effect-highlight PutGlyph (kind 3). A kind 2 or 3 event is a
   real draw. Kind 5 is the bolt/beam path in Magic::ABallBeamBolt deciding to
   draw a square; kind 6 is a thrown or fired missile glyph drawn by
   LOFDrawFlight (src/Fight.cpp); kind 7 is a missile flying over a square,
   drawn or not (a flight count). Both sites are gated by the inc-9r189 fix. Each event inside either area is logged to errors.log as one
   UNSEEN_GLYPH line carrying area=A (closed room) or area=B (dark, in view). */
#include <execinfo.h>
#include <stdarg.h>
#include "Incursion.h"

extern void (*GlyphDrawHook)(int kind, int x, int y);
extern void (*AreaProbeXYHook)(int16,int16);

namespace {

// no-family
const int AX0 = 20, AX1 = 34, AY0 = 5, AY1 = 20;   /* the closed room */
const int PX0 = 3, PX1 = 12, PY0 = 8, PY1 = 14;    /* the player's room */
const int BX0 = 13, BX1 = 18, BY0 = 8, BY1 = 14;   /* dark, open to the player's view */
const int PLX = 6, PLY = 11;
// end no-family

Player *gPl;
int gLogged, gLoggedB, gLoggedDrawA, gLoggedDrawB;
int gAdd, gDraw, gPut, gBolt, gMis, gXY, gXYB, gFlyA, gFlyB;

bool InArea(int x, int y) { return x >= AX0 && x <= AX1 && y >= AY0 && y <= AY1; }
bool InOpen(int x, int y) { return x >= BX0 && x <= BX1 && y >= BY0 && y <= BY1; }

void Note(int kind, int x, int y) {
    if (!gPl || !gPl->m) return;
    Map *mp = gPl->m;
    if (!mp->InBounds(x, y)) return;
    const bool inA = InArea(x, y);
    if (!inA && !InOpen(x, y)) return;
    const char area = inA ? 'A' : 'B';
    const int vis = mp->At(x, y).Visibility;
    if (kind == 7) {   /* a missile flew over this square, drawn or not */
        if (inA) ++gFlyA; else ++gFlyB;
        if ((inA ? gFlyA : gFlyB) <= 200)
            Error("UNSEEN_GLYPH: MISSILE-AT x=%d y=%d turn=%d area=%c", x, y,
                (int)theGame->Turn, area);
        return;
    }
    if (kind == 1) ++gAdd; else if (kind == 2) ++gDraw; else if (kind == 5) ++gBolt;
    else if (kind == 6) ++gMis; else ++gPut;
    /* bolt and missile draws have their own log budget, so a flood of queued
       and overlay events cannot hide them from the check's counts */
    int &budget = (kind == 5 || kind == 6) ? (inA ? gLoggedDrawA : gLoggedDrawB)
                                           : (inA ? gLogged : gLoggedB);
    if (budget >= 400) return;
    ++budget;
    const bool los = mp->LineOfSight(gPl->x, gPl->y, x, y, gPl);
    char site[200] = "";
    if (kind == 1) {
        void *fr[8];
        const int n = backtrace(fr, 8);
        char **sy = backtrace_symbols(fr, n);
        for (int i = 2; sy && i < n && i < 5; ++i) {
            const char *q = strstr(sy[i], "0x");
            snprintf(site + strlen(site), sizeof site - strlen(site) - 1,
                "%.60s;", q ? q : sy[i]);
        }
        free(sy);
    }
    Error("UNSEEN_GLYPH: EVENT kind=%d(%s) x=%d y=%d turn=%d vi_visible=%d "
        "vi_defined=%d los=%d area=%c site=%s", kind,
        kind == 1 ? "AddGlyph" : kind == 2 ? "OverlayDraw" :
        kind == 5 ? "BoltDrawn" : kind == 6 ? "MissileDrawn" : "PutGlyph", x, y,
        (int)theGame->Turn, (vis & VI_VISIBLE) ? 1 : 0,
        (vis & VI_DEFINED) ? 1 : 0, los ? 1 : 0, area, site);
}

void NoteXY(int16 x, int16 y) {
    const bool inA = InArea(x, y);
    if (!inA && !InOpen(x, y)) return;
    if (++(inA ? gXY : gXYB) <= 200)
        Error("UNSEEN_GLYPH: EFFECT-AT x=%d y=%d turn=%d area=%c", (int)x,
            (int)y, (int)theGame->Turn, inA ? 'A' : 'B');
}

} /* namespace */

void UnseenGlyphProbe(Player *pl) {
    /* hook served by inc-9r189 (tools/check_unseen_spell_glyphs.sh) */
    if (!getenv("INCURSION_UNSEEN_GLYPH_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("UNSEEN_GLYPH: INCONCLUSIVE -- no live player and map");
        return;
    }
    Map *mp = pl->m;
    const rID floor = FIND("floor"), wall = FIND("dungeon wall");
    const int NC = 22;   /* 0-5 casters in A, 6-11 casters in B, 12-14 and 18-19 missile users in A, 15-17 and 20-21 in B */
    const char *names[NC] = {"amnizu", "amnizu", "eye of the storm",
        "eye of the storm", "ice mephit", "bloodshot eye",
        "amnizu", "amnizu", "eye of the storm",
        "eye of the storm", "ice mephit", "bloodshot eye",
        "halfling", "halfling", "bugbear", "halfling", "halfling", "bugbear",
        "halfling", "halfling", "halfling", "halfling"};
    const int px[NC] = {21, 33, 21, 33, 27, 27, 17, 17, 14, 14, 15, 18,
        23, 31, 25, 16, 16, 13, 29, 22, 15, 16};
    const int py[NC] = {6, 19, 19, 6, 12, 6, 9, 13, 9, 13, 11, 11,
        8, 17, 15, 10, 12, 11, 10, 13, 9, 13};
    rID mid[NC];
    for (int i = 0; i < NC; ++i) mid[i] = FIND(names[i]);
    if (!floor || !wall || !mid[0] || !mid[2] || !mid[4] || !mid[5] || !mid[12] || !mid[14]) {
        Error("UNSEEN_GLYPH: INCONCLUSIVE -- missing floor, wall or a caster");
        return;
    }
    if (mp->SizeX() < 40 || mp->SizeY() < 24) {
        Error("UNSEEN_GLYPH: INCONCLUSIVE -- map %dx%d is smaller than 40x24",
            (int)mp->SizeX(), (int)mp->SizeY());
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    Thing *obj; int index;
    for (;;) {
        Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != pl) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    pl->PlaceAt(mp, PLX, PLY);
    const rID region = mp->RegionAt(pl->x, pl->y);
    Rect rect(0, 0, mp->SizeX() - 1, mp->SizeY() - 1);
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x) {
            const bool open = (x >= PX0 && x <= PX1 && y >= PY0 && y <= PY1) ||
                              InArea(x, y) || InOpen(x, y);
            mp->WriteAt(rect, x, y, open ? floor : wall, region, PRIO_MAX, true);
            mp->At(x, y).Lit = open && !InOpen(x, y);
            mp->At(x, y).Dark = false;
            mp->At(x, y).Visibility = 0;
            mp->At(x, y).Memory = 0;
        }
    pl->CalcVision();
    /* Control: the room must be unseen and out of line of sight. */
    int seen = 0, los = 0;
    for (int y = AY0; y <= AY1; ++y)
        for (int x = AX0; x <= AX1; ++x) {
            if (mp->At(x, y).Visibility & (VI_VISIBLE | VI_DEFINED)) ++seen;
            if (mp->LineOfSight(pl->x, pl->y, x, y, pl)) ++los;
        }
    /* Control: the dark area must be unseen but in line of sight. */
    int bSeen = 0, bLos = 0, bSq = 0;
    for (int y = BY0; y <= BY1; ++y)
        for (int x = BX0; x <= BX1; ++x) {
            ++bSq;
            if (mp->At(x, y).Visibility & VI_VISIBLE) ++bSeen;
            if (mp->LineOfSight(pl->x, pl->y, x, y, pl)) ++bLos;
        }
    Monster *mn[NC];
    for (int i = 0; i < NC; ++i) {
        mn[i] = new Monster(mid[i]);
        if (i >= 12) {   /* the missile users' own Gear: slings, javelins */
            TMON(mn[i]->tmID)->GrantGear(mn[i], mn[i]->tmID, true);
            TMON(mn[i]->tmID)->PEvent(EV_BIRTH, mn[i], mn[i]->tmID);
        }
        mn[i]->PlaceAt(mp, px[i], py[i], true);
        mn[i]->Initialize(true);
        mn[i]->RemoveStati(SLEEPING); mn[i]->RemoveStati(ASLEEP);
        mn[i]->RemoveStati(AFRAID);
        mn[i]->ts.Clear();
    }
    for (int i = 0; i < NC; ++i)
        for (int j = 0; j < NC; ++j)
            if (i != j) mn[i]->ts.TurnHostileTo(mn[i], mn[j]);
    int hostile = 0;
    for (int i = 0; i < NC; ++i)
        for (int j = 0; j < NC; ++j)
            if (i != j && mn[i]->isHostileTo(mn[j])) ++hostile;
    Error("UNSEEN_GLYPH: SETUP area=(%d,%d)-(%d,%d) player=(%d,%d) casters=%d "
        "hostile_pairs=%d/%d area_squares_seen_or_defined=%d "
        "area_squares_in_los=%d map=%dx%d", AX0, AY0, AX1, AY1, (int)pl->x,
        (int)pl->y, NC, hostile, NC * (NC - 1), seen, los, (int)mp->SizeX(),
        (int)mp->SizeY());
    Error("UNSEEN_GLYPH: SETUP-B area=(%d,%d)-(%d,%d) squares=%d "
        "squares_visible=%d squares_in_los=%d", BX0, BY0, BX1, BY1, bSq, bSeen,
        bLos);
    if (bSeen || bLos != bSq) {
        Error("UNSEEN_GLYPH: INCONCLUSIVE -- the dark area is visible, or "
            "not all of it is in line of sight");
    }
    if (seen || los || hostile != NC * (NC - 1)) {
        Error("UNSEEN_GLYPH: INCONCLUSIVE -- the closed room is seen or in "
            "line of sight, or the casters are not all hostile");
    }
    gPl = pl;
    GlyphDrawHook = Note;
    AreaProbeXYHook = NoteXY;
    theGame->PlayMode = wasInPlay;
}

