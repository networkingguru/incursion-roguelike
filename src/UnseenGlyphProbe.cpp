/* inc-9r189: opt-in probe. Off unless INCURSION_UNSEEN_GLYPH_PROBE is set.
   Called from Game::Play (src/Main.cpp); graded by
   tools/check_unseen_spell_glyphs.sh. It builds two rooms: the player's own,
   and a closed room (walls all round, no door) the player has never seen.
   It fills the closed room with hostile spellcasters, then returns; the key
   script lets turns pass. GlyphDrawHook (src/Magic.cpp) reports every overlay
   glyph queued (kind 1), every overlay glyph drawn by Map::Update (kind 2) and
   every direct effect-highlight PutGlyph (kind 3). A kind 2 or 3 event is a
   real draw. Each event inside the closed room is logged to errors.log as one
   UNSEEN_GLYPH line. */
#include <execinfo.h>
#include <stdarg.h>
#include "Incursion.h"

extern void (*GlyphDrawHook)(int kind, int x, int y);
extern void (*AreaProbeXYHook)(int16,int16);

namespace {

// no-family
const int AX0 = 20, AX1 = 34, AY0 = 5, AY1 = 20;   /* the closed room */
const int PX0 = 3, PX1 = 12, PY0 = 8, PY1 = 14;    /* the player's room */
const int PLX = 6, PLY = 11;
// end no-family

Player *gPl;
int gLogged;
int gAdd, gDraw, gPut, gXY;

bool InArea(int x, int y) { return x >= AX0 && x <= AX1 && y >= AY0 && y <= AY1; }

void Note(int kind, int x, int y) {
    if (!gPl || !gPl->m) return;
    Map *mp = gPl->m;
    if (!mp->InBounds(x, y)) return;
    const bool in = InArea(x, y);
    if (!in) return;
    const int vis = mp->At(x, y).Visibility;
    if (kind == 1) ++gAdd; else if (kind == 2) ++gDraw; else ++gPut;
    if (gLogged >= 400) return;
    ++gLogged;
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
        "vi_defined=%d los=%d site=%s", kind,
        kind == 1 ? "AddGlyph" : kind == 2 ? "OverlayDraw" : "PutGlyph", x, y,
        (int)theGame->Turn, (vis & VI_VISIBLE) ? 1 : 0,
        (vis & VI_DEFINED) ? 1 : 0, los ? 1 : 0, site);
}

void NoteXY(int16 x, int16 y) {
    if (!InArea(x, y)) return;
    if (++gXY <= 200)
        Error("UNSEEN_GLYPH: EFFECT-AT x=%d y=%d turn=%d", (int)x, (int)y,
            (int)theGame->Turn);
}

} /* namespace */

void UnseenGlyphProbe(Player *pl) {
    if (!getenv("INCURSION_UNSEEN_GLYPH_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("UNSEEN_GLYPH: INCONCLUSIVE -- no live player and map");
        return;
    }
    Map *mp = pl->m;
    const rID floor = FIND("floor"), wall = FIND("dungeon wall");
    const char *names[6] = {"amnizu", "amnizu", "eye of the storm",
        "eye of the storm", "ice mephit", "bloodshot eye"};
    const int px[6] = {21, 33, 21, 33, 27, 27};
    const int py[6] = {6, 19, 19, 6, 12, 6};
    rID mid[6];
    for (int i = 0; i < 6; ++i) mid[i] = FIND(names[i]);
    if (!floor || !wall || !mid[0] || !mid[2] || !mid[4] || !mid[5]) {
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
                              InArea(x, y);
            mp->WriteAt(rect, x, y, open ? floor : wall, region, PRIO_MAX, true);
            mp->At(x, y).Lit = open;
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
    Monster *mn[6];
    for (int i = 0; i < 6; ++i) {
        mn[i] = new Monster(mid[i]);
        mn[i]->PlaceAt(mp, px[i], py[i], true);
        mn[i]->Initialize(true);
        mn[i]->RemoveStati(SLEEPING); mn[i]->RemoveStati(ASLEEP);
        mn[i]->RemoveStati(AFRAID);
        mn[i]->ts.Clear();
    }
    for (int i = 0; i < 6; ++i)
        for (int j = 0; j < 6; ++j)
            if (i != j) mn[i]->ts.TurnHostileTo(mn[i], mn[j]);
    int hostile = 0;
    for (int i = 0; i < 6; ++i)
        for (int j = 0; j < 6; ++j)
            if (i != j && mn[i]->isHostileTo(mn[j])) ++hostile;
    Error("UNSEEN_GLYPH: SETUP area=(%d,%d)-(%d,%d) player=(%d,%d) casters=6 "
        "hostile_pairs=%d/30 area_squares_seen_or_defined=%d "
        "area_squares_in_los=%d map=%dx%d", AX0, AY0, AX1, AY1, (int)pl->x,
        (int)pl->y, hostile, seen, los, (int)mp->SizeX(), (int)mp->SizeY());
    if (seen || los || hostile != 30) {
        Error("UNSEEN_GLYPH: INCONCLUSIVE -- the closed room is seen or in "
            "line of sight, or the casters are not all hostile");
    }
    gPl = pl;
    GlyphDrawHook = Note;
    AreaProbeXYHook = NoteXY;
    theGame->PlayMode = wasInPlay;
}

