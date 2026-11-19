/* inc-jw0hw: opt-in probe for effect light. Off unless INCURSION_EFFECT_LIGHT_PROBE
   is set. Called from Game::Play (src/Main.cpp); graded by
   tools/check_effect_light.sh. Output goes to errors.log through Error(), one
   EFFECT_LIGHT line per case and one verdict line last. It builds its own dark
   map, clears every thing but the player, and forces OPT_ANIMATION to Normal
   for its run. Case A: a one-square fire flash lights its square and shows in
   the player's view, a lower level dims it without hiding it, and removal
   leaves the square dark. */
#include <math.h>
#include <stdarg.h>
#include <time.h>
#include <vector>
#define protected public   /* TextTerm::MsgHistory, as AutoLootPacksProbe does */
#include "Incursion.h"
#undef protected
#include "Light.h"
#include "EffectLight.h"

extern void (*AreaProbeXYHook)(int16,int16);
extern void LOFSetForcedRoll(int8 r);
extern void (*GlobeGlyphHook)(int16,int16,Glyph,Glyph);
extern void (*FireworksHook)(int16 x, int16 y, int stage, float clockMs, Glyph g);
extern void (*BallRingHook)(int ring, int ntaken, const int16 *tx,
    const int16 *ty, int ndrawn, const int16 *dx, const int16 *dy, int waitMs);

namespace {

// no-family
const int PX = 6, PY = 17;   /* the player's square in every case */
// end no-family

bool InBlock(int x, int y) { return x >= 4 && x <= 38 && y >= 5 && y <= 29; }

/* Case B state: written by the hooks, read by the case. */
struct Samp {
    bool taken;
    uint32 snap;
    int flashes, nStruck, nStruckLit, nStruckSeen, nSpill, nSpillLit, nSpillSeen;
    LightRGB cc;
    int centerPeak, edgePeak, centerLevel;
};
Map *gMap;
Player *gPl;
bool gOpen, gGlobe, gTimeShow;
int gCx, gCy, gLit, gHolds, gEnds, gPreDirty;
std::vector<char> gStruckGrid;
std::vector<int> gSx, gSy;
Samp gS[2];
double gShowMs;
/* Cases D-F, I: a beam or a missile. gLine makes the hook keep the last EL_LIT
   frame (D) and the lit-cell extent of every EL_LIT frame (E). */
bool gLine;
int gLitMaxCount, gLitMaxSpan, gLitMinCount;
Monster *gKob;
int gFireLevel;     /* case B's center level, the yardstick for case J */
bool gFill;            /* case K: the ball's fill has started */
int gFlightLit, gFlashAtFill;
LightRGB gHue;     /* light color on an early struck square, at the last frame */

/* The ruled fire ramp (logs/ramp-mock/mock.py), as light on a full-weight square:
   color times level at `age` ms. An oracle written apart from src/Light.cpp. */
void FireRampAt(float age, int &r, int &g, int &b) {
    static const float T[6][5] = {
        {   0, 255, 250, 220, 1.0f }, { 120, 255, 220,  80, 1.0f },
        { 300, 255, 140,  30, 0.8f }, { 550, 200,  40,  10, 0.5f },
        { 800,   0,   0,   0, 0.0f }, { 900,   0,   0,   0, 0.0f } };
    int i = 0;
    while (i < 4 && age >= T[i + 1][0]) ++i;
    const float f = age >= T[5][0] ? 1.0f : (age - T[i][0]) / (T[i + 1][0] - T[i][0]);
    float c[4];
    for (int k = 0; k < 4; ++k) c[k] = T[i][k + 1] + (T[i + 1][k + 1] - T[i][k + 1]) * f;
    r = (int)(c[0] * c[3]); g = (int)(c[1] * c[3]); b = (int)(c[2] * c[3]);
}
bool Near(int a, int b) { return abs(a - b) <= 3; }
int gWaitMs;   /* the ring waits so far in the current ball: the effect clock at the hold */

void NoteXY(int16 x, int16 y) {
    if (!gOpen || !gMap->InBounds(x, y) || gMap->At(x, y).Solid) return;
    char &c = gStruckGrid[y * gMap->SizeX() + x];
    if (!c) { c = 1; gSx.push_back(x); gSy.push_back(y); }
}
void NoteRing(int ring, int, const int16 *tx, const int16 *ty, int,
    const int16 *, const int16 *, int waitMs) {
    if (ring >= 0 && gOpen) gWaitMs += waitMs;
    if (ring == -2) {
        gWaitMs = 0;
        gOpen = true; gCx = tx[0]; gCy = ty[0];
        gFill = true; gFlashAtFill = 0;
        for (int y = 0; y < gMap->SizeY(); ++y)
            for (int x = 0; x < gMap->SizeX(); ++x)
                if (LightLitAt((int16)x, (int16)y)) ++gFlashAtFill;
    }
    else if (ring == -1) gOpen = false;
}

std::vector<uint32> gCells[3];
uint32 Snap(Map *mp, int slot = -1, bool vis = true) {
    uint32 h = 2166136261u;
    if (slot >= 0) gCells[slot].assign((size_t)mp->SizeX() * mp->SizeY(), 0);
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x) {
            LightRGB c = { 0, 0, 0 };
            LightAt((int16)x, (int16)y, c);
            const uint32 v = (uint32)c.r | ((uint32)c.g << 8) | ((uint32)c.b << 16) |
                ((uint32)(LightLitAt((int16)x, (int16)y) ? 1 : 0) << 24) |
                ((uint32)((vis && (mp->At(x, y).Visibility & VI_VISIBLE)) ? 1 : 0) << 25);
            h = (h ^ v) * 16777619u;
            if (slot >= 0) gCells[slot][(size_t)y * mp->SizeX() + x] = v;
        }
    return h;
}

int PeakAt(int x, int y);

void Sample(Samp &s) {
    Map *mp = gMap;
    s.taken = true;
    s.snap = Snap(mp);
    s.flashes = (int)LightFlashCount();
    s.nStruck = (int)gSx.size();
    s.nStruckLit = s.nStruckSeen = s.nSpill = s.nSpillLit = s.nSpillSeen = 0;
    int ex = gCx;
    for (size_t i = 0; i < gSx.size(); ++i) {
        const int x = gSx[i], y = gSy[i];
        if (LightLitAt((int16)x, (int16)y)) ++s.nStruckLit;
        if (mp->At(x, y).Visibility & VI_VISIBLE) ++s.nStruckSeen;
        if (y == gCy && x > ex) ex = x;
    }
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x) {
            if (!InBlock(x, y) || gStruckGrid[y * mp->SizeX() + x]) continue;
            bool near2 = false;
            for (size_t i = 0; i < gSx.size() && !near2; ++i)
                near2 = dist(x, y, gSx[i], gSy[i]) <= 2;
            if (!near2) continue;
            ++s.nSpill;
            if (LightLitAt((int16)x, (int16)y)) ++s.nSpillLit;
            if (mp->At(x, y).Visibility & VI_VISIBLE) ++s.nSpillSeen;
        }
    s.cc.r = s.cc.g = s.cc.b = 0;
    LightAt((int16)gCx, (int16)gCy, s.cc);
    s.centerPeak = PeakAt(gCx, gCy);
    s.centerLevel = (int)LightLevelAt((int16)gCx, (int16)gCy);
    s.edgePeak = PeakAt(ex + 2, gCy);
}

void NoteLitExtent() {
    int n = 0, x0 = 999, x1 = -1, y0 = 999, y1 = -1;
    for (int y = 0; y < gMap->SizeY(); ++y)
        for (int x = 0; x < gMap->SizeX(); ++x)
            if (LightLitAt((int16)x, (int16)y)) {
                ++n;
                if (x < x0) x0 = x;
                if (x > x1) x1 = x;
                if (y < y0) y0 = y;
                if (y > y1) y1 = y;
            }
    const int span = n ? ((x1 - x0 > y1 - y0 ? x1 - x0 : y1 - y0) + 1) : 0;
    if (n > gLitMaxCount) gLitMaxCount = n;
    if (span > gLitMaxSpan) gLitMaxSpan = span;
    if (n < gLitMinCount) gLitMinCount = n;
}

/* Case C: what the player sees of the light, and flashes seen at each hook. */
int gCHooks, gCFlashMax;
uint32 gCViewHash;
Map *gCMap;
uint32 ViewHash(Map *mp) {
    uint32 h = 2166136261u;
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x) {
            if (!(mp->At(x, y).Visibility & VI_VISIBLE)) continue;
            LightRGB c = { 0, 0, 0 };
            LightAt((int16)x, (int16)y, c);
            h = (h ^ (uint32)(x * 977 + y)) * 16777619u;
            h = (h ^ ((uint32)c.r | ((uint32)c.g << 8) | ((uint32)c.b << 16))) * 16777619u;
        }
    return h;
}
bool gCDiffer, gCFill;
void CRing(int ring, int, const int16 *, const int16 *, int,
    const int16 *, const int16 *, int) {
    if (ring == -2) gCFill = true;
}
void CHook(int) {
    if (!gCFill) return;   /* the flight starts on the caster's own, seen, square */
    ++gCHooks;
    const int n = (int)LightFlashCount();
    if (n > gCFlashMax) gCFlashMax = n;
    if (ViewHash(gCMap) != gCViewHash) gCDiffer = true;
}

/* Case N: an effect the decision rules UNLIT must add no flash and light no square. */
int gNegCalls, gNegMaxFlashes, gNegMaxLit;
Map *gNegMap;
void NegHook(int) {
    ++gNegCalls;
    const int f = (int)LightFlashCount();
    if (f > gNegMaxFlashes) gNegMaxFlashes = f;
    int lit = 0;
    for (int y = 0; y < gNegMap->SizeY(); ++y)
        for (int x = 0; x < gNegMap->SizeX(); ++x)
            if (LightLitAt((int16)x, (int16)y)) ++lit;
    if (lit > gNegMaxLit) gNegMaxLit = lit;
}

/* Cases T1-T3: the target flash. The hook samples the struck squares at age 0 and
   again when the flash ends. */
int gTfN, gTfLineTo, gTfLitCalls, gTfEndCalls, gTfFlashesLit, gTfFlashesEnd, gTfEnds, gTfLineLit;
int gTfX[2], gTfY[2];
bool gTfLitSq[2];
LightRGB gTfC[2], gTfG[2];
bool gTfGlyph[2];
void TFHook(int phase) {
    if (phase == TF_LIT) {
        ++gTfLitCalls;
        gTfFlashesLit = (int)LightFlashCount();
        gTfEnds = gEnds;
        for (int i = 0; i < gTfN; ++i) {
            gTfLitSq[i] = LightLitAt((int16)gTfX[i], (int16)gTfY[i]);
            LightRGB c = { 0, 0, 0 };
            LightAt((int16)gTfX[i], (int16)gTfY[i], c);
            gTfC[i] = c;
            LightRGB gc = { 0, 0, 0 };
            gTfGlyph[i] = LightEffectGlyphAt((int16)gTfX[i], (int16)gTfY[i], gc);
            gTfG[i] = gc;
        }
        gTfLineLit = 0;
        for (int x = PX + 1; x <= gTfLineTo; ++x)
            if (LightLitAt((int16)x, PY)) ++gTfLineLit;
    } else {
        ++gTfEndCalls;
        gTfFlashesEnd = (int)LightFlashCount();
    }
}

void FlashHook(int phase) {
    if (gLine) {
        if (phase == EL_LIT) {
            ++gLit;
            if (gFill) return;     /* case K: only the flight is graded */
            ++gFlightLit;
            Snap(gMap, 0, true);   /* the last frame wins */
            NoteLitExtent();
            /* the brightest lit square: the effect's own center */
            int best = 0;
            gHue.r = gHue.g = gHue.b = 0;
            for (int y = 0; y < gMap->SizeY(); ++y)
                for (int x = 0; x < gMap->SizeX(); ++x) {
                    LightRGB c = { 0, 0, 0 };
                    if (LightLitAt((int16)x, (int16)y) && LightAt((int16)x, (int16)y, c) &&
                        c.r + c.g + c.b > best) {
                        best = c.r + c.g + c.b;
                        gHue = c;
                    }
                }
            if (LightFlashCount() != 1) gLitMinCount = -1000;
        } else if (phase == EL_END) {
            ++gEnds;
            if (!gS[1].taken) Sample(gS[1]);
        }
        return;
    }
    if (!gFill) return;   /* a ball's flight flash (its own LIT and END) comes before the fill */
    if (phase == EL_LIT) {
        ++gLit;
        if (gGlobe && !gS[0].taken) Sample(gS[0]);
    } else if (phase == EL_HOLD) {
        ++gHolds;
        if (!gGlobe && !gS[0].taken) {
            Sample(gS[0]);
            if (gTimeShow) {
                const clock_t t0 = clock();
                for (int i = 0; i < 5; ++i) {
                    gPl->UpdateMap = 1;
                    gPl->MyTerm->ShowMap();
                }
                gShowMs = 1000.0 * (double)(clock() - t0) / CLOCKS_PER_SEC / 5.0;
            }
        }
    } else if (phase == EL_END) {
        ++gEnds;
        if (!gS[1].taken) Sample(gS[1]);
    }
}


/* Case FW1 (inc-jw0hw): the fireworks globe. One record per shape change. */
struct FwEv { int x, y, stage; float clk; Glyph g; int lvl, litBeyond; };
std::vector<FwEv> gFw;
int gFwCx = -1, gFwCy = -1, gFwR = 0;
void FwHook(int16 x, int16 y, int stage, float clk, Glyph g) {
    FwEv ev;
    ev.x = x; ev.y = y; ev.stage = stage; ev.clk = clk; ev.g = g;
    ev.lvl = (int)LightLevelAt(x, y);
    if (gFw.empty()) { gFwCx = x; gFwCy = y; }   /* the first event is the center's dot */
    /* a cell's light spills 2 squares (Chebyshev), up to 3 rings out in dist() units, so at a ring's start a square 4 rings out must be dark */
    const int r = dist(gFwCx, gFwCy, x, y);
    ev.litBeyond = 0;
    if (stage == 0)   /* only a ring's start says what the later rings have not begun */
    for (int yy = gFwCy - 8; yy <= gFwCy + 8; ++yy)
        for (int xx = gFwCx - 8; xx <= gFwCx + 8; ++xx)
            if (dist(gFwCx, gFwCy, xx, yy) >= r + 4 && dist(gFwCx, gFwCy, xx, yy) <= gFwR && LightLitAt((int16)xx, (int16)yy)) ++ev.litBeyond;
    gFw.push_back(ev);
}

/* Case G3 (inc-6dd41): the glyph a globe's highlight leaves on a square. */
int gGlyphN, gGlyphBad, gGlyphCval;
void GlyphHook(int16, int16, Glyph was, Glyph now) {
    ++gGlyphN;
    bool ok = GLYPH_BACK_VALUE(now) == GLYPH_BACK_VALUE(was);
    if (gGlyphCval >= 16) {
        bool inSet = false;
        for (int i = 0; i < 4; ++i)
            if ((int)GLYPH_FORE_VALUE(now) == BlastColourSets[gGlyphCval * 4 + i]) inSet = true;
        ok = ok && inSet;
    } else
        ok = ok && (int)GLYPH_FORE_VALUE(now) == gGlyphCval;
    if (!ok) ++gGlyphBad;
}

/* An open room that is dark: legacy Lit and Bright are cleared on every cell. */
void BuildDark(Map *mp, Player *pl, rID floor, rID wall) {
    Thing *obj; int index;
    for (;;) {
        Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != pl) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    pl->PlaceAt(mp, PX, PY);
    const rID region = mp->RegionAt(pl->x, pl->y);
    Rect rect(0, 0, mp->SizeX() - 1, mp->SizeY() - 1);
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x) {
            mp->WriteAt(rect, x, y, InBlock(x, y) ? floor : wall, region,
                PRIO_MAX, true);
            mp->At(x, y).Lit = false;
            mp->At(x, y).Bright = false;
            mp->At(x, y).Dark = false;
        }
    pl->CalcVision();
}

void Refresh(Player *pl) {
    /* The vision pass covers only the squares the map window shows. */
    pl->MyTerm->AdjustMap(pl->x, pl->y, true);
    pl->UpdateMap = 1;
    pl->MyTerm->ShowMap();
}

int Peak(int x, int y) {
    LightRGB c;
    if (!LightAt((int16)x, (int16)y, c)) return 0;
    int m = c.r > c.g ? c.r : c.g;
    return c.b > m ? c.b : m;
}
int PeakAt(int x, int y) { return Peak(x, y); }


/* The aura-circle scene (tools/check_aura_circle.sh, INCURSION_AURA_SCENE=1).
   A dark room; the player sees only what the aura lights. Frames are recorded
   first without the field ("before", 300 ms), then with it ("after", 1000 ms).
   A wall hides the south-east of the circle. Writes AURA_SCENE lines with the
   pixel coordinates the check compares between the two clips: a seen point
   inside the circle, the circle's topmost and rightmost points, a hidden
   point inside it, and an outside point. */
void AuraScene(Player *pl, Map *mp, rID floor, rID wall) {
    const int AX = PX + 10, AY = PY, RAD = 4;
    BuildDark(mp, pl, floor, wall);
    LightFlashClearAll();
    pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
    const rID region = mp->RegionAt(pl->x, pl->y);
    Rect rect(0, 0, mp->SizeX() - 1, mp->SizeY() - 1);
    const int wx[3] = { AX + 2, AX + 3, AX + 2 }, wy[3] = { AY + 2, AY + 2, AY + 3 };
    for (int i = 0; i < 3; ++i)
        mp->WriteAt(rect, wx[i], wy[i], wall, region, PRIO_MAX, true);
    Refresh(pl);
    pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
    int px, py, cw, ch;
    if (!TermCellPixel((int16)AX, (int16)AY, px, py, cw, ch)) {
        Error("AURA_SCENE: INCONCLUSIVE -- no pixel geometry (not the SDL build)");
        return;
    }
    pl->MyTerm->StopWatch(300);
    FrameClip("before");
    pl->MyTerm->StopWatch(300);
    mp->NewField(FI_MODIFIER, AX, AY, RAD, GLYPH_VALUE(GLYPH_FLOOR2, PURPLE), -1, 0, NULL);
    Refresh(pl);
    pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
    FrameClip("after");
    /* The circle: center pixel of the field's cell, radius (RAD + 0.5) x mean cell size. */
    const int ccx = px + cw / 2, ccy = py + ch / 2;
    const int R = (int)((RAD + 0.5f) * (cw + ch) / 2.0f + 0.5f);
    /* Offsets from the circle's center pixel, not absolute pixels: the map window
       may scroll after this point, and the script reads the center DrawAuras logs
       (AURA_DRAWN). */
    const int hx = AX + 3, hy = AY + 3, ox = AX + 3 * RAD / 2 + 2;
    int hpx, hpy, opx, opy, c2, h2;
    TermCellPixel((int16)hx, (int16)hy, hpx, hpy, c2, h2);
    TermCellPixel((int16)ox, (int16)AY, opx, opy, c2, h2);
    auto vis = [&](int x, int y) { return (mp->At(x, y).Visibility & VI_VISIBLE) ? 1 : 0; };
    auto cellX = [&](int dx) { return AX + (int)floorf((float)(cw / 2 + dx) / cw); };
    auto cellY = [&](int dy) { return AY + (int)floorf((float)(ch / 2 + dy) / ch); };
    Error("AURA_SCENE: seen %d %d vis=%d", -2 * cw, 0, vis(cellX(-2 * cw), cellY(0)));
    Error("AURA_SCENE: top %d %d vis=%d", 0, -R, vis(cellX(0), cellY(-R)));
    Error("AURA_SCENE: right %d %d vis=%d", R, 0, vis(cellX(R), cellY(0)));
    /* the hidden point is ON the ring (south-east, behind the wall), so a missing
       visibility clip would paint it ring-colored */
    const int hdx = (int)(0.6f * R + 0.5f), hdy = (int)(0.8f * R + 0.5f);
    Error("AURA_SCENE: hidden %d %d vis=%d", hdx, hdy, vis(cellX(hdx), cellY(hdy)));
    Error("AURA_SCENE: cell %d %d vis=1", cw, ch);
    Error("AURA_SCENE: outside %d %d vis=%d", opx + cw / 2 - ccx, opy + ch / 2 - ccy, vis(ox, AY));
    pl->MyTerm->StopWatch(1000);
    Error("AURA_SCENE: DONE");
}

} /* namespace */

void EffectLightProbe(Player *pl) {
    if (!getenv("INCURSION_EFFECT_LIGHT_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("EFFECT_LIGHT: INCONCLUSIVE -- no live player and map");
        return;
    }
    Map *mp = pl->m;
    const rID floor = FIND("floor"), wall = FIND("dungeon wall");
    if (!floor || !wall) {
        Error("EFFECT_LIGHT: INCONCLUSIVE -- missing floor or dungeon wall");
        return;
    }
    if (mp->SizeX() < 44 || mp->SizeY() < 34) {
        Error("EFFECT_LIGHT: INCONCLUSIVE -- map %dx%d is smaller than 44x34",
            (int)mp->SizeX(), (int)mp->SizeY());
        return;
    }
    if (getenv("INCURSION_AURA_SCENE")) {
        const bool wasPlay = theGame->PlayMode;
        theGame->PlayMode = true;
        pl->Options[OPT_ANIMATION] = 0;   /* Normal: shimmer; left set, because the run quits and the last frame must keep the circle */
        AuraScene(pl, mp, floor, wall);
        theGame->PlayMode = wasPlay;
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    const int8 wasAnim = pl->Options[OPT_ANIMATION];
    theGame->PlayMode = true;
    pl->Options[OPT_ANIMATION] = 0;   /* Normal: the light map is live */
    bool anyFail = false, anyInc = false;
    auto verdict = [&](const char *name, int ok, const char *fmt, ...) {
        char buf[300];
        va_list ap; va_start(ap, fmt); vsnprintf(buf, sizeof buf, fmt, ap);
        va_end(ap);
        Error("EFFECT_LIGHT: %s %s %s", name, ok ? "PASS" : "FAIL", buf);
        if (!ok) anyFail = true;
    };
    auto inconclusive = [&](const char *name, const char *why) {
        Error("EFFECT_LIGHT: %s INCONCLUSIVE -- %s", name, why);
        anyInc = true;
    };

    /* ---- Case A: one fire flash, one square, far from the player's light. ---- */
    BuildDark(mp, pl, floor, wall);
    LightFlashClearAll();
    /* Past every unlit sense the player has (light, infravision, shadow). */
    int near = pl->LightRange;
    if (pl->InfraRange > near) near = pl->InfraRange;
    if (pl->ShadowRange > near) near = pl->ShadowRange;
    const int fx = PX + near + 4, fy = PY;
    Refresh(pl);
    if (LightLitAt((int16)fx, (int16)fy) || LightMode(pl) == LIGHT_LEGACY ||
        (mp->At(fx, fy).Visibility & VI_VISIBLE)) {
        inconclusive("A", "the square is lit or in view before the flash, or the light map is legacy");
    } else if (LightFlashDisabled()) {
        inconclusive("A", "INCURSION_EFFECT_LIGHT_OFF is set");
    } else {
        const int32 id = LightFlashAdd(LightEffectColour(COL_FIRE), LF_FIRE, 1.0f, 2, LR_FIRE);
        LightFlashCell(id, (int16)fx, (int16)fy);
        LightFlashSetClock(id, 300.0f);   /* A3 reads the fire ramp's 300 ms stage, (255,140,30) */
        Refresh(pl);
        LightRGB c = { 0, 0, 0 };
        LightAt((int16)fx, (int16)fy, c);
        const bool lit = LightLitAt((int16)fx, (int16)fy);
        const bool seen = (mp->At(fx, fy).Visibility & VI_VISIBLE) != 0;
        const float ratio = c.r ? (float)c.g / c.r : 0.0f;
        verdict("A1", id >= 0 && LightFlashCount() == 1 && lit,
            "id=%d count=%d lit=%d", (int)id, (int)LightFlashCount(), (int)lit);
        verdict("A2", seen, "square (%d,%d) in the player's view=%d", fx, fy, (int)seen);
        verdict("A3", c.r >= c.g && c.g >= c.b && fabsf(ratio - 140.0f / 255.0f) <= 0.15f,
            "color=%d,%d,%d green/red=%.3f need 0.549+-0.15", c.r, c.g, c.b, ratio);
        const int full = Peak(fx, fy);
        LightFlashLevel(id, 0.3f);
        const int dim = Peak(fx, fy);
        verdict("A4", dim < full && dim > 0 && LightLitAt((int16)fx, (int16)fy),
            "peak full=%d at level 0.3=%d lit=%d", full, dim,
            (int)LightLitAt((int16)fx, (int16)fy));
        LightFlashRemove(id);
        Refresh(pl);
        verdict("A5", LightFlashCount() == 0 && !LightLitAt((int16)fx, (int16)fy),
            "count=%d lit=%d", (int)LightFlashCount(),
            (int)LightLitAt((int16)fx, (int16)fy));
    }

    /* ---- Case R: the cooling ramp. A square's light follows its own age on the
       flash clock. R1: a fire square cools, its light level falling and its color
       moving to the next ramp stage (blue falls 0 to 200 ms, green 200 to 600 ms).
       R2: dark energy has no white stage, so age 0 is not whiter than age 200. ---- */
    if (!LightFlashDisabled() && LightMode(pl) != LIGHT_LEGACY) {
        BuildDark(mp, pl, floor, wall);
        LightFlashClearAll();
        int nr = pl->LightRange;
        if (pl->InfraRange > nr) nr = pl->InfraRange;
        if (pl->ShadowRange > nr) nr = pl->ShadowRange;
        const int rx = PX + nr + 4, ry = PY;
        Refresh(pl);
        auto at = [&](int32 rid, float ms, LightRGB &c) {
            LightFlashSetClock(rid, ms);
            c.r = c.g = c.b = 0;
            LightAt((int16)rx, (int16)ry, c);
            return (int)(c.r > c.g ? (c.r > c.b ? c.r : c.b) : (c.g > c.b ? c.g : c.b));
        };
        const int32 fid = LightFlashAdd(LightEffectColour(COL_FIRE), LF_STEADY, 1.0f, 2, LR_FIRE);
        LightFlashCell(fid, (int16)rx, (int16)ry);
        Refresh(pl);
        LightRGB f0, f200, f600;
        const int p0 = at(fid, 0.0f, f0), p200 = at(fid, 200.0f, f200), p600 = at(fid, 600.0f, f600);
        verdict("R1", p0 > p200 && p200 > p600 && p600 > 0 && f200.b < f0.b && f600.g < f200.g,
            "fire square: peak %d,%d,%d at 0,200,600 ms; blue %d->%d; green %d->%d",
            p0, p200, p600, f0.b, f200.b, f200.g, f600.g);
        LightFlashRemove(fid);
        const int32 did = LightFlashAdd(LightEffectColour(COL_NECRO), LF_STEADY, 1.0f, 2, LR_DARK);
        LightFlashCell(did, (int16)rx, (int16)ry);
        Refresh(pl);
        LightRGB d0, d200;
        const int dp0 = at(did, 0.0f, d0), dp200 = at(did, 200.0f, d200);
        auto white = [](const LightRGB &c) {
            const int hi = c.r > c.g ? (c.r > c.b ? c.r : c.b) : (c.g > c.b ? c.g : c.b);
            const int lo = c.r < c.g ? (c.r < c.b ? c.r : c.b) : (c.g < c.b ? c.g : c.b);
            return hi ? (float)lo / hi : 0.0f;
        };
        verdict("R2", dp0 > 0 && dp200 > 0 && white(d0) <= white(d200) + 0.03f,
            "dark energy: color %d,%d,%d at 0 ms, %d,%d,%d at 200 ms; whiteness %.3f then %.3f (age 0 must not be whiter)",
            d0.r, d0.g, d0.b, d200.r, d200.g, d200.b, white(d0), white(d200));
        LightFlashRemove(did);
        Refresh(pl);
    }

    /* ---- Cases B (Fireball), B2 (a globe), H (Hellstorm timing). ---- */
    {
        const rID fire = FIND("Fireball"), hell = FIND("the Hellstorm"),
            sleepE = FIND("Pyrotechnics;blast"), kobold = FIND("kobold");
        if (!fire || !hell || !sleepE || !kobold ||
            TEFF(sleepE)->ef.aval != AR_GLOBE || !TEFF(sleepE)->ef.cval) {
            inconclusive("B", "Fireball, the Hellstorm, Sleep (a globe with a color) or kobold is missing");
        } else {
            gMap = mp; gPl = pl;
            const int aimX = PX + 8;    /* inside the map window; a ball stops at its own range */
            const int8 wasLight = pl->LightRange, wasInfra = pl->InfraRange,
                wasShadow = pl->ShadowRange;
            const bool off = LightFlashDisabled();
            const int8 wasMore = pl->Options[OPT_AUTOMORE];
            pl->Options[OPT_AUTOMORE] = 1;
            TextTerm *term = (TextTerm*)pl->MyTerm;
            auto cast = [&](rID eid, bool globe, bool withKobold, bool timeShow, bool keep,
                    uint32 &pre, uint32 &post, uint32 &postRefresh, int &endFlashes) {
                BuildDark(mp, pl, floor, wall);
                LightFlashClearAll();
                /* Nothing of the player's own may light or show the area. */
                pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                if (globe) { gCx = aimX; gCy = PY; }
                if (withKobold) {
                    Monster *mn = new Monster(kobold);
                    mn->PlaceAt(mp, globe ? aimX + 1 : PX + 4, globe ? PY + 1 : PY, true);
                    mn->Initialize(true);
                }
                if (!keep) {
                    gStruckGrid.assign((size_t)mp->SizeX() * mp->SizeY(), 0);
                    gSx.clear(); gSy.clear();
                }
                gS[0].taken = gS[1].taken = false;
                gLit = gHolds = gEnds = 0;
                gFill = globe;
                gGlobe = globe; gOpen = globe && !keep; gTimeShow = timeShow;
                Refresh(pl);
                pre = Snap(mp);
                const uint32 preLight = Snap(mp, -1, false);
                gPreDirty = 0;
                for (int y = 0; y < mp->SizeY(); ++y)
                    for (int x = 0; x < mp->SizeX(); ++x) {
                        if (LightLitAt((int16)x, (int16)y)) ++gPreDirty;
                        if ((mp->At(x, y).Visibility & VI_VISIBLE) && dist(x, y, PX, PY) > 1)
                            ++gPreDirty;
                    }
                term->MsgHistory[0] = 0;
                AreaProbeXYHook = NoteXY; BallRingHook = NoteRing;
                EffectLightHook = FlashHook;
                EventInfo xe; xe.Clear();
                xe.EActor = pl; xe.EMap = mp; xe.eID = eid; xe.isSpell = true;
                xe.isLoc = true; xe.EXVal = aimX; xe.EYVal = PY;
                ReThrow(EV_EFFECT, xe);
                AreaProbeXYHook = NULL; BallRingHook = NULL; EffectLightHook = NULL;
                /* The cast's vision update recomputes the player's ranges, and a
                   stale view of the old range is not the flash. Compare light only. */
                post = Snap(mp, -1, false) == preLight ? pre : ~pre;
                endFlashes = (int)LightFlashCount();
                pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                Refresh(pl);
                postRefresh = Snap(mp);
            };
            uint32 pre, post, postR; int endF;
            /* B: Fireball. In the OFF run only the message lines are wanted. */
            cast(fire, false, true, false, false, pre, post, postR, endF);
            for (const char *ln = term->MsgHistory; *ln; ) {
                const char *nl = strchr(ln, '\n');
                const int len = nl ? (int)(nl - ln) : (int)strlen(ln);
                if (len > 0) Error("EFFECT_LIGHT: MSG %.*s", len, ln);
                if (!nl) break;
                ln = nl + 1;
            }
            if (off) {
                inconclusive("B", "INCURSION_EFFECT_LIGHT_OFF is set; only the message lines were recorded");
            } else if (gPreDirty || LightMode(pl) == LIGHT_LEGACY) {
                inconclusive("B", "a square is lit or in view before the cast, or the light map is legacy");
            } else {
                const Samp &h = gS[0], &e = gS[1];
                verdict("B0", gHolds == 1 && gEnds == 1 && gLit > 0 && h.taken && e.taken,
                    "hooks: lit=%d hold=%d end=%d struck=%d", gLit, gHolds, gEnds, h.nStruck);
                verdict("B1", h.nStruck > 0 && h.nStruckLit == h.nStruck &&
                    h.nStruckSeen == h.nStruck && h.nSpill > 0 &&
                    h.nSpillLit == h.nSpill && h.nSpillSeen == h.nSpill,
                    "at hold: struck lit %d/%d seen %d/%d; spill lit %d/%d seen %d/%d",
                    h.nStruckLit, h.nStruck, h.nStruckSeen, h.nStruck,
                    h.nSpillLit, h.nSpill, h.nSpillSeen, h.nSpill);
                int er, eg, eb;
                FireRampAt((float)gWaitMs, er, eg, eb);
                verdict("B2", gWaitMs > 0 && Near(h.cc.r, er) && Near(h.cc.g, eg) && Near(h.cc.b, eb),
                    "center color=%d,%d,%d need the fire ramp at the center's age %d ms: %d,%d,%d (+-3)",
                    h.cc.r, h.cc.g, h.cc.b, gWaitMs, er, eg, eb);
                gFireLevel = h.centerLevel;
                verdict("B3", h.edgePeak > 0 && h.edgePeak < h.centerPeak,
                    "reach edge peak %d, center peak %d", h.edgePeak, h.centerPeak);
                verdict("B4", e.taken && e.snap == pre && e.flashes == 0,
                    "at end hook: dump equals the before-cast dump=%d flashes=%d",
                    (int)(e.snap == pre), e.flashes);
                verdict("B5", post == pre && postR == pre && endF == 0,
                    "after the cast returns: same=%d after a refresh same=%d flashes=%d",
                    (int)(post == pre), (int)(postR == pre), endF);
            }
            /* R3: OPT_ANIMATION None. A Fireball draws no tail, leaves no flash, and the cast returns. */
            if (!off) {
                pl->Options[OPT_ANIMATION] = 2;
                cast(fire, false, false, false, false, pre, post, postR, endF);
                pl->Options[OPT_ANIMATION] = 0;
                verdict("R3", gEnds == 1 && endF == 0 && LightFlashCount() == 0,
                    "animation None: end hooks=%d flashes after the cast=%d", gEnds, endF);
            }
            /* C: Fireball with the player boxed in by eight opaque neighbors, as
               check_ball_shape.sh case C: the area is out of sight, so no flash
               is added and no square the player sees changes light. */
            if (!off) {
                BuildDark(mp, pl, floor, wall);
                LightFlashClearAll();
                for (int dx = -1; dx <= 1; ++dx)
                    for (int dy = -1; dy <= 1; ++dy)
                        if (dx || dy) mp->At(PX + dx, PY + dy).Opaque = true;
                pl->CalcVision();
                pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                Refresh(pl);
                gCMap = mp; gCHooks = gCFlashMax = 0; gCDiffer = false; gCFill = false;
                gCViewHash = ViewHash(mp);
                int seenFar = 0;
                for (int y = 0; y < mp->SizeY(); ++y)
                    for (int x = 0; x < mp->SizeX(); ++x)
                        if (dist(x, y, PX, PY) > 1 && (mp->At(x, y).Visibility & VI_VISIBLE)) ++seenFar;
                term->MsgHistory[0] = 0;
                EffectLightHook = CHook; BallRingHook = CRing;
                EventInfo xe; xe.Clear();
                xe.EActor = pl; xe.EMap = mp; xe.eID = fire; xe.isSpell = true;
                xe.isLoc = true; xe.EXVal = aimX; xe.EYVal = PY;
                ReThrow(EV_EFFECT, xe);
                EffectLightHook = NULL; BallRingHook = NULL;
                const int endF = (int)LightFlashCount();
                if (gCHooks == 0 || seenFar || LightMode(pl) == LIGHT_LEGACY)
                    inconclusive("C", "no effect-light hook fired, or the player sees past the box");
                else
                    verdict("C", gCFlashMax == 0 && endF == 0 && !gCDiffer,
                        "boxed in: hooks=%d most flashes=%d flashes at end=%d view changed=%d",
                        gCHooks, gCFlashMax, endF, (int)gCDiffer);
            }
            /* B2: a globe flash (Pyrotechnics;blast, a lit globe; Sleep no longer glows, inc-jw0hw). */
            cast(sleepE, true, true, false, false, pre, post, postR, endF);  /* learns the struck squares */
            if (!off) cast(sleepE, true, true, false, true, pre, post, postR, endF);
            if (off) {
                inconclusive("B2", "INCURSION_EFFECT_LIGHT_OFF is set");
            } else if (gPreDirty || LightMode(pl) == LIGHT_LEGACY) {
                inconclusive("B2", "a square is lit or in view before the cast, or the light map is legacy");
            } else {
                const Samp &h = gS[0], &e = gS[1];
                verdict("G1", gLit == 1 && gEnds == 1 && h.taken && e.taken &&
                    h.nStruck > 0 && h.nStruckLit == h.nStruck &&
                    h.nStruckSeen == h.nStruck && h.nSpill > 0 &&
                    h.nSpillLit == h.nSpill && h.nSpillSeen == h.nSpill,
                    "globe lit: hooks lit=%d end=%d; struck lit %d/%d seen %d/%d; spill lit %d/%d seen %d/%d",
                    gLit, gEnds, h.nStruckLit, h.nStruck, h.nStruckSeen, h.nStruck,
                    h.nSpillLit, h.nSpill, h.nSpillSeen, h.nSpill);
                verdict("G2", e.taken && e.snap == pre && e.flashes == 0 &&
                    post == pre && postR == pre && endF == 0,
                    "globe gone: end hook same=%d flashes=%d; after return same=%d; after refresh same=%d",
                    (int)(e.snap == pre), e.flashes, (int)(post == pre), (int)(postR == pre));
            }
            /* G3: a globe's highlight keeps the background and takes a valid foreground. */
            if (!off) {
                const rID lotus = FIND("Fire Lotus");
                const rID gl[2] = { lotus, sleepE };
                int n[2] = { -1, -1 }, bad[2] = { 0, 0 };
                for (int i = 0; i < 2 && gl[i]; ++i) {
                    gGlyphN = gGlyphBad = 0;
                    gGlyphCval = TEFF(gl[i])->ef.cval;
                    GlobeGlyphHook = GlyphHook;
                    cast(gl[i], true, false, false, false, pre, post, postR, endF);
                    GlobeGlyphHook = NULL;
                    n[i] = gGlyphN; bad[i] = gGlyphBad;
                }
                if (!lotus || TEFF(lotus)->ef.cval < 16 || TEFF(sleepE)->ef.cval >= 16)
                    inconclusive("G3", "Fire Lotus is missing or has no color set, or the plain globe has one");
                else if (n[0] <= 0 || n[1] <= 0)
                    inconclusive("G3", "a globe's highlight never ran");
                else
                    verdict("G3", bad[0] == 0 && bad[1] == 0,
                        "globe glyph: Fire Lotus (color set) %d squares, %d bad; plain globe %d squares, %d bad",
                        n[0], bad[0], n[1], bad[1]);
            }
            /* FW1 (F1 in the brief; F1 is taken by the bolt case): the fireworks globe (Pyrotechnics;flash) plays dot, star, flower, gone,
               ring by ring, each ring pointing away from the center, light born with its ring. */
            if (!off) {
                const rID fw = FIND("Pyrotechnics;flash");
                if (!fw || !TEFF(fw)->HasFlag(EF_FIREWORKS) || TEFF(fw)->ef.aval != AR_GLOBE)
                    inconclusive("FW1", "Pyrotechnics;flash is missing, not a globe, or lacks EF_FIREWORKS");
                else {
                    gFw.clear(); gFwCx = gFwCy = -1; gFwR = TEFF(fw)->ef.lval;
                    FireworksHook = FwHook;
                    cast(fw, true, false, false, false, pre, post, postR, endF);
                    FireworksHook = NULL;
                    int R = 0;
                    for (size_t i = 0; i < gFw.size(); ++i) {
                        const int r = dist(gFwCx, gFwCy, gFw[i].x, gFw[i].y);
                        if (r > R) R = r;
                    }
                    std::vector<int> seq((size_t)mp->SizeX() * mp->SizeY(), 0);   /* next stage each square expects */
                    bool order = !gFw.empty(), light0 = true, dark = true;
                    int nSq = 0;
                    for (size_t i = 0; i < gFw.size(); ++i) {
                        int &nx = seq[(size_t)gFw[i].y * mp->SizeX() + gFw[i].x];
                        if (gFw[i].stage != nx) order = false;
                        ++nx;
                        if (gFw[i].stage == 0) { ++nSq; if (gFw[i].lvl <= 0) light0 = false; }
                        if (gFw[i].litBeyond) dark = false;
                    }
                    int wantSq = 0, allFour = 0;
                    for (int y = 0; y < mp->SizeY(); ++y)
                        for (int x = 0; x < mp->SizeX(); ++x) {
                            const bool want = gFw.empty() ? false : dist(gFwCx, gFwCy, x, y) <= R &&
                                !mp->At(x, y).Solid && mp->LineOfSight(PX, PY, x, y, pl);
                            wantSq += want;
                            if (want && seq[(size_t)y * mp->SizeX() + x] == 4) ++allFour;
                        }
                    float first[2][16];
                    for (int a = 0; a < 2; ++a) for (int r = 0; r < 16; ++r) first[a][r] = -1.0f;
                    for (size_t i = 0; i < gFw.size(); ++i) {
                        const int r = dist(gFwCx, gFwCy, gFw[i].x, gFw[i].y);
                        if (gFw[i].stage < 2 && r < 16 && first[gFw[i].stage][r] < 0.0f)
                            first[gFw[i].stage][r] = gFw[i].clk;
                    }
                    bool rings = R >= 2;
                    for (int r = 1; r <= R && r < 16; ++r)
                        if (first[0][r] < 0.0f || first[0][r] != first[1][r - 1]) rings = false;
                    auto glyphAt = [&](int x, int y, int stage) {
                        for (size_t i = 0; i < gFw.size(); ++i)
                            if (gFw[i].x == x && gFw[i].y == y && gFw[i].stage == stage) return (int)gFw[i].g;
                        return -1;
                    };
                    const int c0 = glyphAt(gFwCx, gFwCy, 0), c1 = glyphAt(gFwCx, gFwCy, 1), c2 = glyphAt(gFwCx, gFwCy, 2);
                    const int ge = glyphAt(gFwCx + 2, gFwCy, 1), gn = glyphAt(gFwCx, gFwCy - 2, 1),
                        gne = glyphAt(gFwCx + 2, gFwCy - 2, 1);
                    verdict("FW1a", nSq > 0 && nSq == wantSq && allFour == wantSq && order,
                        "radius %d: %d squares shown, %d expected in view; %d passed stages 0,1,2,3 once each in order=%d",
                        R, nSq, wantSq, allFour, (int)order);
                    verdict("FW1b", rings, "each ring starts at the clock ring-1 reaches its star (radius %d)", R);
                    verdict("FW1c", c0 > 0 && c1 > 0 && c2 > 0 && c0 != c1 && c1 != c2 && c0 != c2,
                        "center glyphs: dot %d, star %d, flower %d (all different)", c0, c1, c2);
                    verdict("FW1d", ge > 0 && gn > 0 && gne > 0 && ge != gn && ge != gne && gn != gne,
                        "full shapes: east %d, north %d, northeast %d (all different)", ge, gn, gne);
                    verdict("FW1e", light0 && dark,
                        "each square lit right after its ring starts=%d; no square of a later ring lit early=%d",
                        (int)light0, (int)dark);
                }
            }
            /* H: Hellstorm cost, informational (the check does not grade it). */
            if (!off) {
                const clock_t t0 = clock();
                cast(hell, false, false, true, false, pre, post, postR, endF);
                const double total = 1000.0 * (double)(clock() - t0) / CLOCKS_PER_SEC;
                Error("EFFECT_LIGHT: H hellstorm struck=%d ms_per_ShowMap=%.2f cast_total_ms=%.1f",
                    gS[0].nStruck, gShowMs, total);
            }
            /* Cases D, E, F, I: beams and missiles (Task 5). */
            const rID lightning = FIND("Lightning Bolt"), acid = FIND("Magic Missile"),
                flame = FIND("tongue of flame"), missile = FIND("Magic Missile");
            auto shoot = [&](rID eid, bool withKob, bool self, bool engulf,
                    uint32 &pre, uint32 &postLight, int &endFlashes) {
                BuildDark(mp, pl, floor, wall);
                LightFlashClearAll();
                pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                gKob = NULL;
                if (withKob || engulf) {
                    gKob = new Monster(kobold);
                    gKob->PlaceAt(mp, PX + 4, PY, true);
                    gKob->Initialize(true);
                }
                gStruckGrid.assign((size_t)mp->SizeX() * mp->SizeY(), 0);
                gSx.clear(); gSy.clear();
                gS[0].taken = gS[1].taken = false;
                gLit = gHolds = gEnds = 0;
                gGlobe = false; gOpen = true; gTimeShow = false; gLine = true;
                gLitMaxCount = gLitMaxSpan = 0; gLitMinCount = 1000000;
                gFill = false; gFlightLit = 0; gFlashAtFill = -1;
                gCells[0].clear();
                Refresh(pl);
                pre = Snap(mp);
                const uint32 preLight = Snap(mp, -1, false);
                gPreDirty = 0;
                for (int y = 0; y < mp->SizeY(); ++y)
                    for (int x = 0; x < mp->SizeX(); ++x) {
                        if (LightLitAt((int16)x, (int16)y)) ++gPreDirty;
                        if ((mp->At(x, y).Visibility & VI_VISIBLE) && dist(x, y, PX, PY) > 1)
                            ++gPreDirty;
                    }
                term->MsgHistory[0] = 0;
                AreaProbeXYHook = NoteXY; BallRingHook = NoteRing;
                EffectLightHook = FlashHook;
                if (engulf) pl->DoEngulf(gKob);
                EventInfo xe; xe.Clear();
                xe.EActor = pl; xe.EMap = mp; xe.eID = eid; xe.isSpell = true;
                xe.isLoc = true;
                xe.EXVal = self ? PX : (gKob ? PX + 4 : PX + 3); xe.EYVal = PY;
                if (withKob && !self) xe.EVictim = gKob;
                ReThrow(EV_EFFECT, xe);
                AreaProbeXYHook = NULL; BallRingHook = NULL; EffectLightHook = NULL; gLine = false;
                if (engulf && gKob) gKob->DropEngulfed();
                postLight = Snap(mp, -1, false) == preLight ? pre : ~pre;
                endFlashes = (int)LightFlashCount();
                pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
            };
            if (off) {
                inconclusive("D", "INCURSION_EFFECT_LIGHT_OFF is set");
            } else if (!lightning || !acid || !missile || !flame ||
                TEFF(flame)->ef.aval != AR_RAY || TEFF(lightning)->ef.aval != AR_BEAM || TEFF(acid)->ef.aval != AR_BOLT ||
                TEFF(missile)->ef.aval != AR_BOLT) {
                inconclusive("D", "Lightning Bolt (beam), Acid Arrow (bolt) or Magic Missile (bolt) is missing");
            } else {
                /* D: Lightning Bolt. The last frame lights the line and 1 square around it. */
                shoot(lightning, false, false, false, pre, post, endF);
                if (gPreDirty || LightMode(pl) == LIGHT_LEGACY) {
                    inconclusive("D", "a square is lit or in view before the cast, or the light map is legacy");
                } else if (gCells[0].empty()) {
                    verdict("D1", 0, "the beam lit no frame");
                } else {
                    int nS = 0, nSLit = 0, nSSeen = 0, nP = 0, nPLit = 0, nPSeen = 0;
                    for (size_t i = 0; i < gSx.size(); ++i) {
                        if (!InBlock(gSx[i], gSy[i])) continue;
                        const uint32 v = gCells[0][(size_t)gSy[i] * mp->SizeX() + gSx[i]];
                        ++nS; nSLit += (v >> 24) & 1; nSSeen += (v >> 25) & 1;
                    }
                    for (int y = 0; y < mp->SizeY(); ++y)
                        for (int x = 0; x < mp->SizeX(); ++x) {
                            if (!InBlock(x, y) || gStruckGrid[y * mp->SizeX() + x]) continue;
                            bool near1 = false;
                            for (size_t i = 0; i < gSx.size() && !near1; ++i)
                                near1 = dist(x, y, gSx[i], gSy[i]) <= 1;
                            if (!near1) continue;
                            const uint32 v = gCells[0][(size_t)y * mp->SizeX() + x];
                            ++nP; nPLit += (v >> 24) & 1; nPSeen += (v >> 25) & 1;
                        }
                    verdict("D1", gLit > 1 && nS > 1 && nSLit == nS && nSSeen == nS && nP > 0 &&
                        nPLit == nP && nPSeen == nP,
                        "last frame: hooks lit=%d; line lit %d/%d seen %d/%d; spill lit %d/%d seen %d/%d",
                        gLit, nSLit, nS, nSSeen, nS, nPLit, nP, nPSeen, nP);
                    verdict("D2", gEnds == 1 && gS[1].taken && gS[1].snap == pre &&
                        gS[1].flashes == 0 && post == pre && endF == 0,
                        "gone: end hook same=%d flashes=%d; after return same=%d flashes=%d",
                        (int)(gS[1].snap == pre), gS[1].flashes, (int)(post == pre), endF);
                }
                /* I: a fire ray whose glyph color is plain (palette 12) lights with the Fire hue. */
                shoot(flame, true, false, false, pre, post, endF);
                if (gPreDirty) {
                    inconclusive("I", "a square is lit before the cast");
                } else if (gCells[0].empty()) {
                    verdict("I1", 0, "the ray lit no frame");
                } else {
                    int er, eg, eb;
                    FireRampAt(0.0f, er, eg, eb);   /* the brightest square of the last frame was just lit */
                    verdict("I1", Near(gHue.r, er) && Near(gHue.g, eg) && Near(gHue.b, eb),
                        "plain glyph color, fire damage: light %d,%d,%d need the fire ramp at age 0: %d,%d,%d (+-3)",
                        gHue.r, gHue.g, gHue.b, er, eg, eb);
                    verdict("I2", gEnds == 1 && endF == 0 && post == pre,
                        "fire ray ends clean: end=%d flashes=%d same=%d", gEnds, endF,
                        (int)(post == pre));
                }
                /* E: a bolt (Magic Missile; Acid Arrow no longer glows) flies at a kobold: one point of light, no trail. */
                shoot(acid, true, false, false, pre, post, endF);
                if (gPreDirty) {
                    inconclusive("E", "a square is lit before the cast");
                } else if (gCells[0].empty()) {
                    verdict("E1", 0, "the bolt lit no frame");
                } else {
                    verdict("E1", gLit >= 2 && gLitMaxCount >= 1 && gLitMaxCount <= 9 &&
                        gLitMaxSpan <= 3 && gLitMinCount >= 1,
                        "in flight: frames=%d lit cells per frame min=%d max=%d, widest extent=%d (at most 9 cells, 3 wide)",
                        gLit, gLitMinCount, gLitMaxCount, gLitMaxSpan);
                    verdict("E2", gEnds == 1 && gS[1].taken && gS[1].snap == pre &&
                        gS[1].flashes == 0 && post == pre && endF == 0,
                        "gone: end hook same=%d flashes=%d; after return same=%d flashes=%d",
                        (int)(gS[1].snap == pre), gS[1].flashes, (int)(post == pre), endF);
                }
                /* K: a Fireball's flight is one steady point, and it ends when the fill starts. */
                shoot(fire, false, false, false, pre, post, endF);
                if (gPreDirty) {
                    inconclusive("K", "a square is lit before the cast");
                } else {
                    verdict("K1", gFlightLit >= 2 && gLitMaxCount >= 1 && gLitMaxCount <= 9 &&
                        gLitMaxSpan <= 3 && gLitMinCount >= 1,
                        "flight: frames=%d lit cells per frame min=%d max=%d, widest extent=%d (at most 9 cells, 3 wide)",
                        gFlightLit, gLitMinCount, gLitMaxCount, gLitMaxSpan);
                    verdict("K2", gFill && gFlashAtFill == 0 && gFlightLit >= 2,
                        "flight light gone when the fill starts: fill=%d lit cells then=%d", (int)gFill, gFlashAtFill);
                }
                /* N: the decision rules Acid Arrow (a bolt) and Sleep (a globe) UNLIT, so a cast adds no
                   flash and lights no square, though the effect does reach its light code. A
                   lit effect in the same scene (cases B and E) does the opposite. */
                if (!off) {
                    const rID negAcid = FIND("Acid Arrow"), negSleep = FIND("Sleep");
                    if (!negAcid || !negSleep) {
                        inconclusive("N", "Acid Arrow or Sleep is missing");
                    } else {
                        for (int which = 0; which < 2; ++which) {
                            const rID eid = which ? negSleep : negAcid;
                            BuildDark(mp, pl, floor, wall);
                            LightFlashClearAll();
                            pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                            Monster *mn = new Monster(kobold);
                            mn->PlaceAt(mp, which ? aimX + 1 : PX + 4, which ? PY + 1 : PY, true);
                            mn->Initialize(true);
                            Refresh(pl);
                            pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                            gNegMap = mp; gNegCalls = gNegMaxFlashes = gNegMaxLit = 0;
                            term->MsgHistory[0] = 0;
                            EffectLightHook = NegHook;
                            EventInfo xe; xe.Clear();
                            xe.EActor = pl; xe.EMap = mp; xe.eID = eid; xe.isSpell = true;
                            xe.isLoc = true; xe.EXVal = which ? aimX : PX + 4; xe.EYVal = PY;
                            if (!which) xe.EVictim = mn;
                            ReThrow(EV_EFFECT, xe);
                            EffectLightHook = NULL;
                            verdict(which ? "N2" : "N1", gNegCalls > 0 && gNegMaxFlashes == 0 && gNegMaxLit == 0,
                                "%s: light code reached %d times, most flashes %d, most lit squares %d (need >0, 0, 0)",
                                which ? "Sleep globe" : "Acid Arrow bolt", gNegCalls, gNegMaxFlashes, gNegMaxLit);
                        }
                    }
                }

                /* F: no flash survives an early exit. */
                shoot(acid, false, false, false, pre, post, endF);   /* no victim */
                verdict("F1", gLit == 0 && endF == 0 && post == pre,
                    "bolt with no victim: frames=%d flashes after=%d light same=%d", gLit, endF, (int)(post == pre));
                shoot(missile, false, true, false, pre, post, endF); /* self target */
                verdict("F2", gLit == 0 && endF == 0 && post == pre,
                    "self-target cast: frames=%d flashes after=%d light same=%d", gLit, endF, (int)(post == pre));
                shoot(acid, false, false, true, pre, post, endF);    /* engulfed */
                verdict("F3", gLit == 0 && endF == 0 && post == pre,
                    "engulfed cast: frames=%d flashes after=%d light same=%d", gLit, endF, (int)(post == pre));

                /* T: the target flash. Each case builds a dark room, places kobolds at fixed offsets and
                   samples the light map from TargetFlashHook. */
                {
                    const rID chill = FIND("Chill Touch"), callL = FIND("Call Lightning");
                    auto tprep = [&](int nk, const int *kx, const int *ky, Monster **kobs) {
                        BuildDark(mp, pl, floor, wall);
                        LightFlashClearAll();
                        pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                        for (int i = 0; i < nk; ++i) {
                            kobs[i] = new Monster(kobold);
                            kobs[i]->PlaceAt(mp, kx[i], ky[i], true);
                            kobs[i]->Initialize(true);
                            gTfX[i] = kx[i]; gTfY[i] = ky[i];
                        }
                        gTfN = nk; gTfLineTo = PX;
                        gTfLitCalls = gTfEndCalls = gTfFlashesLit = gTfFlashesEnd = gTfEnds = gTfLineLit = 0;
                        gTfLitSq[0] = gTfLitSq[1] = false; gTfGlyph[0] = gTfGlyph[1] = false;
        for (int i = 0; i < 2; ++i) { gTfC[i].r = gTfC[i].g = gTfC[i].b = 0; gTfG[i] = gTfC[i]; }
                        gStruckGrid.assign((size_t)mp->SizeX() * mp->SizeY(), 0);
                        gSx.clear(); gSy.clear();
                        gS[0].taken = gS[1].taken = false;
                        gLit = gHolds = gEnds = 0;
                        gGlobe = false; gOpen = false; gTimeShow = false; gLine = false; gFill = false;
                        Refresh(pl);
                        pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                        term->MsgHistory[0] = 0;
                    };
                    auto hue = [](const LightRGB &c, float &g_over_r, float &b_over_r) {
                        g_over_r = c.r ? (float)c.g / c.r : 0.0f;
                        b_over_r = c.r ? (float)c.b / c.r : 0.0f;
                    };
                    auto glyphOff = [&](int n) {   /* after the flash ends, no struck square carries a glyph color */
                        for (int i = 0; i < n; ++i) {
                            LightRGB gc = { 0, 0, 0 };
                            if (LightEffectGlyphAt((int16)gTfX[i], (int16)gTfY[i], gc)) return false;
                        }
                        return true;
                    };
                    /* T1: a Fireball with two kobolds inside the area. */
                    {
                        const int tAim = PX + 5;   /* inside the fireball's own range, so it bursts on the aim square */
                        const int kx[2] = { tAim, tAim }, ky[2] = { PY - 2, PY + 2 };
                        Monster *kobs[2];
                        tprep(2, kx, ky, kobs);
                        AreaProbeXYHook = NoteXY; BallRingHook = NoteRing;
                        EffectLightHook = FlashHook; TargetFlashHook = TFHook;
                        EventInfo xe; xe.Clear();
                        xe.EActor = pl; xe.EMap = mp; xe.eID = fire; xe.isSpell = true;
                        xe.isLoc = true; xe.EXVal = tAim; xe.EYVal = PY;
                        ReThrow(EV_EFFECT, xe);
                        AreaProbeXYHook = NULL; BallRingHook = NULL; EffectLightHook = NULL; TargetFlashHook = NULL;
                        const int endT = (int)LightFlashCount();
                        const bool struck = gStruckGrid[ky[0] * mp->SizeX() + kx[0]] &&
                            gStruckGrid[ky[1] * mp->SizeX() + kx[1]];
                                                float g0, b0, g1, b1;
                        hue(gTfC[0], g0, b0); hue(gTfC[1], g1, b1);
                        float gg0, gb0, gg1, gb1;
                        hue(gTfG[0], gg0, gb0); hue(gTfG[1], gg1, gb1);
                        const bool glyphsOk = gTfGlyph[0] && gTfGlyph[1] && gg0 >= 0.9f && gb0 >= 0.7f &&
                            gg1 >= 0.9f && gb1 >= 0.7f && glyphOff(2);
                        if (!struck || LightMode(pl) == LIGHT_LEGACY)
                            inconclusive("T1", "a kobold square is outside the fireball's area, or the light map is legacy");
                        else
                            verdict("T1", gTfLitCalls == 1 && gTfEndCalls == 1 && gTfEnds == 1 &&
                                gTfFlashesLit == 1 && gTfFlashesEnd == 0 && endT == 0 &&
                                gTfLitSq[0] && gTfLitSq[1] &&
                                g0 >= 0.9f && b0 >= 0.7f && g1 >= 0.9f && b1 >= 0.7f && glyphsOk,
                                "fireball: target flashes=%d (need 1), ball light ended first=%d, kobold squares lit %d,%d, "
                                "fire age-0 color %d,%d,%d and %d,%d,%d (near white: green/red>=0.9, blue/red>=0.7), glyph colors %d,%d,%d and %d,%d,%d on=%d, flashes at end=%d after=%d",
                                gTfLitCalls, gTfEnds, (int)gTfLitSq[0], (int)gTfLitSq[1],
                                gTfC[0].r, gTfC[0].g, gTfC[0].b, gTfC[1].r, gTfC[1].g, gTfC[1].b,
                                gTfG[0].r, gTfG[0].g, gTfG[0].b, gTfG[1].r, gTfG[1].g, gTfG[1].b, (int)glyphsOk,
                                gTfFlashesEnd, endT);
                    }
                    /* T2: a landed Chill Touch flashes in the necromantic color with no white stage; a miss flashes nothing. */
                    if (!chill) {
                        inconclusive("T2", "Chill Touch is missing");
                    } else {
                        for (int miss = 0; miss < 2; ++miss) {
                            const int kx[1] = { PX + 1 }, ky[1] = { PY };
                            Monster *kobs[1];
                            tprep(1, kx, ky, kobs);
                            pl->GainTempStati(TOUCH_ATTACK, pl, 50, SS_ENCH, 0, 3, chill);
                            TargetFlashHook = TFHook;
                            LOFSetForcedRoll(miss ? 1 : 20);
                            Throw(EV_NATTACK, pl, kobs[0]);
                            LOFSetForcedRoll(0);
                            TargetFlashHook = NULL;
                                                        const bool charged = pl->GetStatiMag(TOUCH_ATTACK) == 3;   /* a landed touch uses one of the three */
                            pl->RemoveStati(TOUCH_ATTACK);
                            float g0, b0;
                            hue(gTfC[0], g0, b0);
                            const int hi = gTfC[0].r > gTfC[0].g ? (gTfC[0].r > gTfC[0].b ? gTfC[0].r : gTfC[0].b)
                                : (gTfC[0].g > gTfC[0].b ? gTfC[0].g : gTfC[0].b);
                            const int lo = gTfC[0].r < gTfC[0].g ? (gTfC[0].r < gTfC[0].b ? gTfC[0].r : gTfC[0].b)
                                : (gTfC[0].g < gTfC[0].b ? gTfC[0].g : gTfC[0].b);
                            const float whiteness = hi ? (float)lo / hi : 1.0f;
                            const int ghi = gTfG[0].r > gTfG[0].g ? (gTfG[0].r > gTfG[0].b ? gTfG[0].r : gTfG[0].b)
                                : (gTfG[0].g > gTfG[0].b ? gTfG[0].g : gTfG[0].b);
                            const int glo = gTfG[0].r < gTfG[0].g ? (gTfG[0].r < gTfG[0].b ? gTfG[0].r : gTfG[0].b)
                                : (gTfG[0].g < gTfG[0].b ? gTfG[0].g : gTfG[0].b);
                            const float gwhite = ghi ? (float)glo / ghi : 1.0f;
                            const bool glyphOk = gTfGlyph[0] && ghi > 0 && gwhite < 0.75f && glyphOff(1);
                            if (LightMode(pl) == LIGHT_LEGACY)
                                inconclusive(miss ? "T2b" : "T2", "the light map is legacy");
                            else if (miss)
                                verdict("T2b", charged && gTfLitCalls == 0 && LightFlashCount() == 0,
                                    "missed touch: hand still charged=%d, target flashes=%d (need 1, 0)",
                                    (int)charged, gTfLitCalls);
                            else
                                verdict("T2", !charged && gTfLitCalls == 1 && gTfEndCalls == 1 &&
                                    gTfFlashesLit == 1 && gTfFlashesEnd == 0 && gTfLitSq[0] &&
                                    hi > 0 && whiteness < 0.75f && glyphOk && LightFlashCount() == 0,
                                    "landed touch: one charge used=%d, target flashes=%d, square lit=%d, necromantic color %d,%d,%d at age 0 whiteness %.2f (need < 0.75, fire is 0.86), glyph color %d,%d,%d whiteness %.2f on=%d, flashes after=%d",
                                    (int)!charged, gTfLitCalls, (int)gTfLitSq[0],
                                    gTfC[0].r, gTfC[0].g, gTfC[0].b, whiteness,
                                    gTfG[0].r, gTfG[0].g, gTfG[0].b, gwhite, (int)glyphOk, (int)LightFlashCount());
                        }
                    }
                    /* T3: Call Lightning shows no stroke: only the target flash, in the electric color. */
                    if (!callL) {
                        inconclusive("T3", "Call Lightning is missing");
                    } else {
                        const int kx[1] = { PX + 6 }, ky[1] = { PY };
                        Monster *kobs[1];
                        tprep(1, kx, ky, kobs);
                        gTfLineTo = PX + 3;   /* every square from the caster to two short of the target */
                        gNegMap = mp; gNegCalls = gNegMaxFlashes = gNegMaxLit = 0;
                        EffectLightHook = NegHook; TargetFlashHook = TFHook;
                        EventInfo xe; xe.Clear();
                        xe.EActor = pl; xe.EMap = mp; xe.eID = callL; xe.isSpell = true;
                        xe.isLoc = true; xe.EXVal = kx[0]; xe.EYVal = ky[0];
                        xe.EVictim = kobs[0];
                        ReThrow(EV_EFFECT, xe);
                        EffectLightHook = NULL; TargetFlashHook = NULL;
                        if (LightMode(pl) == LIGHT_LEGACY)
                            inconclusive("T3", "the light map is legacy");
                        else
                            verdict("T3", gTfLitCalls == 1 && gTfEndCalls == 1 && gNegCalls == 0 &&
                                gTfLitSq[0] && gTfLineLit == 0 && gTfC[0].b >= gTfC[0].r &&
                                gTfGlyph[0] && gTfG[0].b >= gTfG[0].r && glyphOff(1) &&
                                gTfFlashesEnd == 0 && LightFlashCount() == 0,
                                "call lightning: target flashes=%d, stroke light calls=%d (need 1, 0), target lit=%d, "
                                "lit squares on the line=%d (need 0), electric color %d,%d,%d (blue >= red), glyph on=%d color %d,%d,%d, flashes after=%d",
                                gTfLitCalls, gNegCalls, (int)gTfLitSq[0], gTfLineLit,
                                gTfC[0].r, gTfC[0].g, gTfC[0].b, (int)gTfGlyph[0], gTfG[0].r, gTfG[0].g, gTfG[0].b,
                                (int)LightFlashCount());
                    }
                }
            }

            /* J: aura fields (Task 6). A modifier or blocker field that gives no light
               lights its area, at a level between LIGHT_SEE_MIN and 0.6 x the Fireball's
               center level; a fog, darkness or silence field adds none. The square one
               past the area carries a trace of light but is below LIGHT_SEE_MIN. */
            if (!off && gFireLevel > 0) {
                const int AX = PX + 10, AY = PY;
                auto aura = [&](const char *name, int32 ftype, int colour, int RAD) {
                    BuildDark(mp, pl, floor, wall);
                    LightFlashClearAll();
                    pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                    Refresh(pl);
                    pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                    const uint32 pre0 = Snap(mp, -1, false);
                    mp->NewField(ftype, AX, AY, RAD, GLYPH_VALUE(GLYPH_FLOOR2, colour), -1, 0, NULL);
                    Field *fld = mp->Fields[0];
                    Refresh(pl);
                    pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                    int nArea = 0, nLit = 0, nSeen = 0, lo = 999, hi = 0, nRing = 0, nRingLit = 0, ringHi = 0;
                    for (int y = AY - RAD - 2; y <= AY + RAD + 2; ++y)
                        for (int x = AX - RAD - 2; x <= AX + RAD + 2; ++x) {
                            const int lv = (int)LightLevelAt((int16)x, (int16)y);
                            const bool inA = fld && fld->inArea((int16)x, (int16)y);
                            bool nearA = false;
                            for (int oy = -1; oy <= 1 && !nearA; ++oy)
                                for (int ox = -1; ox <= 1 && !nearA; ++ox)
                                    nearA = fld && fld->inArea((int16)(x + ox), (int16)(y + oy));
                            if (inA) {
                                ++nArea;
                                if (LightLitAt((int16)x, (int16)y)) ++nLit;
                                if (mp->At(x, y).Visibility & VI_VISIBLE) ++nSeen;
                                if (lv < lo) lo = lv;
                                if (lv > hi) hi = lv;
                            } else if (nearA) {
                                ++nRing;
                                if (lv > 0) ++nRingLit;
                                if (lv > ringHi) ringHi = lv;
                            }
                        }
                    const int anyLit = (nLit > 0) || (nRingLit > 0);
                    for (int i = 0; mp->Fields[i]; ) mp->RemoveField(mp->Fields[i]);
                    Refresh(pl);
                    pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
                    const bool gone = Snap(mp, -1, false) == pre0;
                    int litAfter = 0;
                    for (int y = AY - RAD - 2; y <= AY + RAD + 2; ++y)
                        for (int x = AX - RAD - 2; x <= AX + RAD + 2; ++x)
                            if (LightLitAt((int16)x, (int16)y)) ++litAfter;
                    if (ftype & (FI_MODIFIER | FI_BLOCKER)) {
                        verdict(name, nArea > 0 && nLit == nArea && nSeen == nArea &&
                            lo >= LIGHT_SEE_MIN && hi <= (int)(0.6f * gFireLevel) &&
                            nRingLit == nRing && ringHi < lo && gone && litAfter == 0,
                            "area lit %d/%d seen %d/%d level %d..%d (need %d..%d); ring has light %d/%d, peak %d; unlit after removal=%d",
                            nLit, nArea, nSeen, nArea, lo, hi, (int)LIGHT_SEE_MIN,
                            (int)(0.6f * gFireLevel), nRingLit, nRing, ringHi, (int)(gone && litAfter == 0));
                    } else {
                        verdict(name, !anyLit && nSeen == 0 && gone,
                            "no light: area lit %d/%d, ring with light %d, seen %d", nLit, nArea, nRingLit, nSeen);
                    }
                };
                aura("J1", FI_MODIFIER, PURPLE, 1);       /* a Minor Globe of Invulnerability field */
                aura("J2", FI_BLOCKER, WHITE, 1);         /* a Magic Circle vs. Evil field */
                aura("J3", FI_FOG, GREY, 1);              /* a fog */
                aura("J4", FI_DARKNESS, GREY, 1);         /* darkness */
                aura("J5", FI_SILENCE, GREY, 1);         /* silence */
                aura("J6", FI_MODIFIER, PURPLE, 4);      /* a radius-4 globe */
            }
            pl->LightRange = wasLight; pl->InfraRange = wasInfra; pl->ShadowRange = wasShadow;
            pl->Options[OPT_AUTOMORE] = wasMore;
        }
    }

    LightFlashClearAll();
    BuildDark(mp, pl, floor, wall);
    pl->Options[OPT_ANIMATION] = wasAnim;
    theGame->PlayMode = wasInPlay;
    if (anyFail)
        Error("EFFECT_LIGHT: FAIL");
    else if (anyInc)
        Error("EFFECT_LIGHT: INCONCLUSIVE -- a case could not be established");
    else
        Error("EFFECT_LIGHT: PASS");
}
