/* inc-epzc0: opt-in check of the cone effects. Off unless INCURSION_CONE_PROBE
   is set. Called from Game::Play (src/Main.cpp). It rebuilds the player's map
   (open room, one-wide hallway, walled room), casts and breathes through the real
   paths, and grades each case: one `CONE_PROBE: <CASE> PASS|FAIL <detail>` line
   per assertion, then `CONE_PROBE: CASE <name> PASS|FAIL checks=<n>` per case.
   tools/check_cone_shape.sh reads those lines. */
#include <vector>
#include <stdarg.h>
#include <string.h>
#include "Incursion.h"

extern void (*AreaProbeXYHook)(int16,int16);
extern void (*MeanderHook)(int16 lx, int16 ly, int16 dx, int16 dy, Glyph g);
extern void (*EffectLightHook)(int phase);
extern void (*EffectWaitHook)(int ms);
extern void (*BallRingHook)(int ring, int ntaken, const int16 *tx,
    const int16 *ty, int ndrawn, const int16 *dx, const int16 *dy, int waitMs);

namespace {

/* ---- the verdicts ---------------------------------------------------- */
const char *CASES[] = { "OPEN", "OFFAXIS", "WALL", "HALL", "WAVE", "PREDICT",
    "BREATH", "ITEMS" };
// no-family
const int NCASES = 8;
// end no-family
int gChecks[NCASES], gBad[NCASES];
void Chk(const char *cs, bool ok, const char *fmt, ...) {
    char buf[300];
    va_list ap; va_start(ap, fmt); vsnprintf(buf, sizeof buf, fmt, ap); va_end(ap);
    for (int i = 0; i < NCASES; ++i)
        if (!strcmp(CASES[i], cs)) { ++gChecks[i]; if (!ok) ++gBad[i]; }
    Error("CONE_PROBE: %s %s %s", cs, ok ? "PASS" : "FAIL", buf);
}

/* ---- a cast, read through the hooks ----------------------------------- */
struct Ring { int ring, nt, nd, wait; };
bool gOpen; int gOpens, gFinalWait, gNRings, gNXY;
Ring gRings[80];
int16 gXx[6000], gXy[6000];
std::vector<char> gDrawn;
int gDrawnW;
std::vector<int> gEv;   /* 1000 lit, 1001 hold, 1002 end, else a wait in ms */
void NoteXY(int16 x, int16 y) {
    if (gOpen && gNXY < 6000) { gXx[gNXY] = x; gXy[gNXY] = y; ++gNXY; }
}
void NoteRing(int ring, int nt, const int16 *, const int16 *, int nd,
    const int16 *dx, const int16 *dy, int wait) {
    if (ring == -2) { gOpen = true; ++gOpens; return; }
    if (ring == -1) { gOpen = false; gFinalWait = wait; return; }
    if (gNRings < 80) { Ring r = { ring, nt, nd, wait }; gRings[gNRings++] = r; }
    for (int i = 0; i < nd; ++i)
        if (gDrawnW && dy[i]*gDrawnW + dx[i] < (int)gDrawn.size())
            gDrawn[dy[i]*gDrawnW + dx[i]] = 1;
}
void NoteLight(int phase) { gEv.push_back(1000 + phase); }
void NoteWait(int ms) { gEv.push_back(ms); }

// no-family
const int CX = 26, CY = 17;
// end no-family

void Build(Map *mp, Player *pl, bool hall, rID floor, rID wall) {
    Thing *obj; int index;
    for (;;) {
        Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != pl) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    pl->PlaceAt(mp, hall ? 20 : CX, CY);
    const rID region = mp->RegionAt(pl->x, pl->y);
    Rect rect(0, 0, mp->SizeX() - 1, mp->SizeY() - 1);
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x) {
            const bool open = hall ? (y == CY && x >= 4 && x <= 36)
                                   : (x >= 4 && x <= 38 && y >= 5 && y <= 29);
            mp->WriteAt(rect, x, y, open ? floor : wall, region, PRIO_MAX, true);
            mp->At(x, y).Lit = open;
        }
    pl->CalcVision();
}

/* S source taken, s source not taken, o taken, # solid terrain, + solid
   feature, . open and not taken. */
void Show(Map *mp, int sx, int sy, int tx, int ty, int L, const char *name) {
    EventInfo e; e.Clear();
    std::vector<BallSquare> fill;
    const int ax = tx - sx, ay = ty - sy;
    const int16 count = Magic::ConeVolume(e, L, ax, ay);
    Magic::ConeFill(*mp, sx, sy, tx, ty, count, fill);
    int taken = 0;
    for (size_t i = 0; i < fill.size(); ++i) taken += fill[i].kind == 0;
    Error("CONE_PROBE: %s L=%d aim=(%d,%d) volume=%d taken=%d", name, L, ax, ay,
        (int)count, taken);
    const int R = 10;
    for (int y = sy - R; y <= sy + R; ++y) {
        char row[2*R + 2];
        for (int x = sx - R; x <= sx + R; ++x) {
            char ch = !mp->InBounds(x, y) ? '#' :
                mp->At(x, y).Solid ? ' ' : '.';
            for (size_t i = 0; i < fill.size(); ++i)
                if (fill[i].x == x && fill[i].y == y)
                    ch = fill[i].kind == 1 ? '#' : fill[i].kind == 2 ? '+' :
                        (x == sx && y == sy) ? 'S' : 'o';
            if (x == sx && y == sy && ch == '.') ch = 's';
            row[x - (sx - R)] = ch;
        }
        row[2*R + 1] = 0;
        Error("CONE_PROBE:   %s", row);
    }
}

/* The probe's own cone, independent of Magic::ConeFill: in the ball's disc
   for whole length L and within 45 degrees of the aim (ax,ay). */
bool InCone(int dx, int dy, int L, int ax, int ay) {
    if (!dx && !dy) return false;
    const int dot = dx*ax + dy*ay;
    return 4*(dx*dx + dy*dy) <= (2*L + 1)*(2*L + 1) && dot > 0 &&
        2*dot*dot >= (dx*dx + dy*dy)*(ax*ax + ay*ay);
}

/* ally: the probe makes this kobold the player's companion. want: 1 the
   foe must be struck, 0 it must not, set by the case before the cast. */
struct Foe { Monster *m; int dx, dy; int ally; int want; };

struct Res {
    int L, vol, nStruck, fired, nv, frames, drawnFrames;
    std::vector<char> hit;
    int W;
    bool sq[16], dmg[16], pred[16], allyOK[16];
    bool casterSq, casterDmg, casterPred;
    int nf;
    /* the wave */
    bool consecutive, allDrew, eventsOK, holdOK, drawnIsStruck;
    int firstRing, finalHold, pairs, lits, holds;
};

/* Casts `cone` from (px,CY): aim east as a direction when (ax,ay) is (1,0),
   else at the square (px+ax, CY+ay). mode 0 casts as a spell; 1 zaps an item
   (no activation flag); 2 activates an item or ability (EF_ACTIVATE). it may be
   NULL (the tattoo). Reads, never grades. */
void Cast(Map *mp, Player *pl, rID cone, rID kobold, const char *name,
    int px, Foe *foes, int nf, Res &R, int ax = 1, int ay = 0, int mode = 0,
    Item *it = NULL) {
    R.L = TEFF(cone)->ef.lval ? TEFF(cone)->ef.lval : 5; /* the engine floor for an lval-less cone */
    R.nf = nf;
    const bool dir = ax == 1 && ay == 0;
    Monster *mk[16]; int hp0[16];
    for (int i = 0; i < nf; ++i) {
        mk[i] = new Monster(kobold);
        mk[i]->PlaceAt(mp, px + foes[i].dx, CY + foes[i].dy, true);
        mk[i]->Initialize(true);
        if (foes[i].ally) mk[i]->MakeCompanion(pl, PHD_FREEBIE);
        mk[i]->cHP = mk[i]->mHP = 500; hp0[i] = 500;
    }
    pl->cHP = pl->mHP = 500;
    Creature *victims[1024]; int16 nv = 0;
    {
        EventInfo pe; pe.Clear();
        pe.EActor = pl; pe.EMap = mp; pe.eID = cone; pe.isSpell = mode == 0;
        pe.EItem = it; pe.isItem = it != NULL; pe.isActivation = mode == 2;
        pe.EMagic = &TEFF(cone)->ef; pe.Event = EV_CAST; pe.MM = 0;
        if (dir) { pe.isDir = true; pe.EDir = EAST; }
        else { pe.isLoc = true; pe.EXVal = px + ax; pe.EYVal = CY + ay; }
        pe.vCasterLev = (int8)pl->CasterLev();
        pe.vRange = pe.EMagic->lval;
        pl->CalcEffect(pe);
        pl->PredictVictimsOfBallBeamBolt(pe, false, false, false, victims, nv);
    }
    R.nv = nv;
    gOpen = false; gOpens = 0; gFinalWait = -1; gNRings = 0; gNXY = 0;
    gDrawnW = mp->SizeX(); gDrawn.assign(mp->SizeX() * mp->SizeY(), 0);
    gEv.clear();
    AreaProbeXYHook = NoteXY; BallRingHook = NoteRing;
    EffectLightHook = NoteLight; EffectWaitHook = NoteWait;
    EventInfo xe; xe.Clear();
    xe.EActor = pl; xe.EMap = mp; xe.eID = cone; xe.isSpell = mode == 0;
    xe.EItem = it; xe.isItem = it != NULL; xe.isActivation = mode == 2;
    if (dir) { xe.isDir = true; xe.EDir = EAST; }
    else { xe.isLoc = true; xe.EXVal = px + ax; xe.EYVal = CY + ay; }
    ReThrow(EV_EFFECT, xe);
    AreaProbeXYHook = NULL; BallRingHook = NULL;
    EffectLightHook = NULL; EffectWaitHook = NULL;

    EventInfo ve; ve.Clear();
    R.vol = Magic::ConeVolume(ve, R.L, ax, ay);
    R.W = mp->SizeX();
    R.hit.assign(mp->SizeX() * mp->SizeY(), 0);
    R.nStruck = 0;
    for (int i = 0; i < gNXY; ++i) {
        const int x = gXx[i], y = gXy[i];
        if (!mp->InBounds(x, y) || mp->At(x, y).Solid) continue;
        if (!R.hit[y*R.W + x]) { R.hit[y*R.W + x] = 1; ++R.nStruck; }
    }
    R.fired = gOpens;
    Error("CONE_PROBE: CAST %s L=%d volume=%d struck=%d fired=%d", name, R.L,
        R.vol, R.nStruck, gOpens);
    const int RR = 9;
    for (int y = CY - 6; y <= CY + 6; ++y) {
        char row[2*RR + 2];
        for (int x = px - 2; x <= px - 2 + 2*RR; ++x) {
            char ch = !mp->InBounds(x, y) || mp->At(x, y).Solid ? ' ' : '.';
            if (mp->InBounds(x, y) && R.hit[y*R.W + x]) ch = 'o';
            if (x == px && y == CY) ch = R.hit[y*R.W + x] ? 'S' : 's';
            for (int i = 0; i < nf; ++i)
                if (x == px + foes[i].dx && y == CY + foes[i].dy) ch = 'k';
            row[x - (px - 2)] = ch;
        }
        row[2*RR + 1] = 0;
        Error("CONE_PROBE:   %s", row);
    }
    for (int i = 0; i < nf; ++i) {
        const bool dead = mk[i]->isDead() || (mk[i]->Flags & F_DELETE);
        R.dmg[i] = dead || mk[i]->cHP < hp0[i];
        R.sq[i] = R.hit[(CY + foes[i].dy)*R.W + px + foes[i].dx] != 0;
        R.pred[i] = false;
        for (int j = 0; j < nv; ++j) if (victims[j] == mk[i]) R.pred[i] = true;
        R.allyOK[i] = !foes[i].ally || mk[i]->isFriendlyTo(pl);
        Error("CONE_PROBE: foe at (%+d,%+d) ally=%d struck_square=%d damaged=%d "
            "predicted=%d", foes[i].dx, foes[i].dy, foes[i].ally, (int)R.sq[i],
            (int)R.dmg[i], (int)R.pred[i]);
    }
    R.casterSq = R.hit[CY*R.W + px] != 0;
    R.casterDmg = pl->cHP < 500;
    R.casterPred = false;
    for (int j = 0; j < nv; ++j) if (victims[j] == pl) R.casterPred = true;
    Error("CONE_PROBE: caster struck_square=%d damaged=%d predicted=%d hp=%d",
        (int)R.casterSq, (int)R.casterDmg, (int)R.casterPred, (int)pl->cHP);
    Error("CONE_PROBE: predicted victims=%d", (int)nv);
    /* the wave */
    R.frames = gNRings; R.drawnFrames = 0;
    R.consecutive = gNRings > 0; R.allDrew = gNRings > 0;
    R.firstRing = gNRings ? gRings[0].ring : -9;
    for (int i = 0; i < gNRings; ++i) {
        const Ring &r = gRings[i];
        Error("CONE_PROBE: frame %d band=%d taken=%d drawn=%d wait=%dms", i,
            r.ring, r.nt, r.nd, r.wait);
        if (i && r.ring != gRings[i-1].ring + 1) R.consecutive = false;
        if (r.nd > 0) ++R.drawnFrames;
        else if (r.nt > 0) R.allDrew = false;   /* a band of walls only takes none */
    }
    R.finalHold = gFinalWait;
    R.pairs = R.lits = R.holds = 0; R.holdOK = false;
    for (size_t i = 0; i < gEv.size(); ++i) {
        if (gEv[i] == 1000) {
            ++R.lits;
            if (i + 1 < gEv.size() && gEv[i+1] == 70) ++R.pairs;
        }
        if (gEv[i] == 1001) {
            ++R.holds;
            if (i + 1 < gEv.size() && gEv[i+1] == 300) R.holdOK = true;
        }
    }
    Error("CONE_PROBE: wave events lit=%d lit_then_70ms=%d holds=%d hold_then_300ms=%d "
        "total=%d", R.lits, R.pairs, R.holds, (int)R.holdOK, (int)gEv.size());
    R.eventsOK = R.lits == R.drawnFrames && R.pairs == R.lits;
    R.drawnIsStruck = true;
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x)
            if ((gDrawn[y*R.W + x] != 0) != (R.hit[y*R.W + x] != 0))
                R.drawnIsStruck = false;
    for (int i = 0; i < nf; ++i) mk[i]->Remove(true);
}

/* The struck set against an independent cone (aim ax,ay, length L) over every
   open square. Returns the mismatch count; expected is the cone's size. */
int Compare(Map *mp, const Res &R, int px, int ax, int ay, int &expected) {
    int mismatch = 0; expected = 0;
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x)
            if (!mp->At(x, y).Solid) {
                const bool want = InCone(x - px, y - CY, R.L, ax, ay);
                expected += want;
                if (want != (R.hit[y*R.W + x] != 0)) ++mismatch;
            }
    return mismatch;
}

/* The prediction equals the strike, creature by creature, caster included. */
void CheckPredict(const char *tag, const Res &R, const Foe *foes) {
    int inSq = R.casterSq ? 1 : 0; bool same = R.casterSq == R.casterPred;
    for (int i = 0; i < R.nf; ++i) {
        inSq += R.sq[i];
        if (R.sq[i] != R.pred[i]) same = false;
    }
    (void)foes;
    Chk("PREDICT", same && R.nv == inSq,
        "%s: predicted %d creatures, %d stand on struck squares, each agrees=%d",
        tag, R.nv, inSq, (int)same);
}

/* The wave of one cast. */
void CheckWave(const char *tag, const Res &R) {
    Chk("WAVE", R.frames >= 2 && R.consecutive && R.firstRing <= 1,
        "%s: %d frames, band numbers rise by one each frame, first band %d", tag,
        R.frames, R.firstRing);
    Chk("WAVE", R.allDrew, "%s: every band that takes a square draws it", tag);
    Chk("WAVE", R.eventsOK && R.drawnFrames > 0,
        "%s: %d lit frames, each followed by a %d ms step (%d of %d)", tag,
        R.lits, 70, R.pairs, R.lits);
    Chk("WAVE", R.holds == 1 && R.holdOK && R.finalHold == 300,
        "%s: one final hold of 300 ms (holds=%d then300=%d reported=%d)", tag,
        R.holds, (int)R.holdOK, R.finalHold);
    Chk("WAVE", R.drawnIsStruck,
        "%s: the squares drawn over all frames are exactly the squares struck", tag);
}

/* Phase 3: a monster breathes (or spits) at the player through
   Creature::SAttack, the real natural-attack path. Reports the squares the
   effect struck and whether it ran as a cone or a line. */
int gMeanderPts;
void NoteMeander(int16 lx, int16, int16, int16, Glyph) { if (lx != -1) ++gMeanderPts; }
void NoteAll(int16 x, int16 y) {
    if (gNXY < 6000) { gXx[gNXY] = x; gXy[gNXY] = y; ++gNXY; }
}
struct Br { bool ok, cone; int ret, struck, offAxis, fired; };
Br Breathe(Map *mp, Player *pl, const char *mon, int atype) {
    Br b = { false, false, 0, 0, 0, 0 };
    const bool tmpl = !strcmp(mon, "half-red dragon");
    const rID mid = FIND(tmpl ? "kobold" : mon);
    if (!mid) { Error("CONE_PROBE: BREATH %s INCONCLUSIVE no such monster", mon); return b; }
    Monster *mn = new Monster(mid);
    mn->PlaceAt(mp, CX - 3, CY, true);
    mn->Initialize(true);
    if (tmpl) mn->AddTemplate(FIND(mon));
    mn->Timeout = 0;
    pl->cHP = pl->mHP = 5000;
    gOpen = false; gOpens = 0; gFinalWait = -1; gNRings = 0; gNXY = 0; gMeanderPts = 0;
    gDrawnW = 0;
    AreaProbeXYHook = NoteAll; BallRingHook = NoteRing; MeanderHook = NoteMeander;
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    const int mhp0 = pl->mHP, con0 = pl->Attr[A_CON];
    EvReturn r = ThrowVal(EV_SATTACK, atype, mn, pl);
    theGame->PlayMode = wasInPlay;
    Error("CONE_PROBE: BREATH %s hp before=%d/%d after=%d/%d Con %d->%d", mon,
        5000, mhp0, (int)pl->cHP, (int)pl->mHP, con0, (int)pl->Attr[A_CON]);
    AreaProbeXYHook = NULL; BallRingHook = NULL; MeanderHook = NULL;
    std::vector<char> hit(mp->SizeX() * mp->SizeY(), 0);
    int nStruck = 0, offAxis = 0;
    for (int i = 0; i < gNXY; ++i) {
        const int x = gXx[i], y = gXy[i];
        if (!mp->InBounds(x, y) || hit[y*mp->SizeX() + x]) continue;
        hit[y*mp->SizeX() + x] = 1; ++nStruck;
        if (y != CY) ++offAxis;
    }
    Error("CONE_PROBE: BREATH %s atype=%d ret=%d shape=%s struck=%d offaxis=%d "
        "cone_fills=%d meander_points=%d hp_lost=%d", mon, atype, (int)r,
        gOpens ? "CONE" : "LINE", nStruck, offAxis, gOpens, gMeanderPts,
        (int)(5000 - pl->cHP));
    b.ok = true; b.cone = gOpens != 0; b.ret = (int)r; b.struck = nStruck;
    b.offAxis = offAxis; b.fired = gOpens;
    mn->Remove(true);
    return b;
}

/* A cast graded as an open-floor cone: the struck set, the volume, the foes. */
void GradeOpen(const char *cs, Map *mp, const Res &R, int px, int ax, int ay,
    const Foe *foes, bool needCaster0) {
    int expected, mism = Compare(mp, R, px, ax, ay, expected);
    Chk(cs, mism == 0 && R.nStruck > 0,
        "struck squares equal the independent cone: struck=%d cone=%d mismatches=%d",
        R.nStruck, expected, mism);
    Chk(cs, R.nStruck == R.vol && R.fired == 1,
        "struck count %d equals ConeVolume %d (one strike, fired=%d)", R.nStruck,
        R.vol, R.fired);
    for (int i = 0; i < R.nf; ++i) {
        const bool want = foes[i].want != 0;
        Chk(cs, R.sq[i] == want && R.dmg[i] == want && R.allyOK[i],
            "%s at (%+d,%+d): wanted %s, square struck=%d damaged=%d",
            foes[i].ally ? "ally" : "foe", foes[i].dx, foes[i].dy,
            want ? "struck" : "untouched", (int)R.sq[i], (int)R.dmg[i]);
    }
    if (needCaster0)
        Chk(cs, !R.casterSq && !R.casterDmg, "caster not struck: square=%d damaged=%d",
            (int)R.casterSq, (int)R.casterDmg);
}

} /* namespace */

void ConeShapeProbe(Player *pl) {
    if (!getenv("INCURSION_CONE_PROBE"))
        return;
    if (!pl || !pl->m || pl->m->SizeX() < 44 || pl->m->SizeY() < 34) {
        Error("CONE_PROBE: INCONCLUSIVE -- no live map of 44x34 or more");
        return;
    }
    Map *mp = pl->m;
    const rID floor = FIND("floor"), wall = FIND("dungeon wall");
    if (!floor || !wall) {
        Error("CONE_PROBE: INCONCLUSIVE -- missing floor or dungeon wall");
        return;
    }
    EventInfo e; e.Clear();
    Error("CONE_PROBE: counts L axis diagonal");
    for (int L = 1; L <= 10; ++L)
        Error("CONE_PROBE: count %d %d %d", L, (int)Magic::ConeDiscCount(L, 1, 0),
            (int)Magic::ConeDiscCount(L, 1, 1));
    static const int DX[8] = {1, 1, 0, -1, -1, -1, 0, 1};
    static const int DY[8] = {0, 1, 1, 1, 0, -1, -1, -1};
    Build(mp, pl, false, floor, wall);
    for (int L = 1; L <= 8; ++L) {
        for (int d = 0; d < 8; ++d)
            Show(mp, CX, CY, CX + 8*DX[d], CY + 8*DY[d], L, "open");
        Show(mp, CX, CY, CX + 8, CY + 3, L, "offaxis");
    }
    Build(mp, pl, true, floor, wall);
    Show(mp, 20, CY, 28, CY, 6, "hall");
    Show(mp, 20, CY, 28, CY, 3, "hall");
    const rID coneID = FIND("Cone of Cold"), kob = FIND("kobold");
    if (!coneID || !kob) {
        Error("CONE_PROBE: INCONCLUSIVE -- no Cone of Cold or kobold");
        return;
    }
    const int L0 = TEFF(coneID)->ef.lval ? TEFF(coneID)->ef.lval : 5;

    /* OPEN: a known group, one of it an ally, cast east on open floor. */
    {
        Foe f[] = { {0,3,0,0,0}, {0,7,0,0,0}, {0,4,3,0,0}, {0,3,-3,0,0},
            {0,5,2,0,0}, {0,8,0,0,0}, {0,2,3,0,0}, {0,-3,0,0,0}, {0,5,-2,1,0} };
        const int n = sizeof f / sizeof f[0];
        for (int i = 0; i < n; ++i) f[i].want = InCone(f[i].dx, f[i].dy, L0, 1, 0);
        Build(mp, pl, false, floor, wall);
        Res R; Cast(mp, pl, coneID, kob, "open", CX, f, n, R);
        Chk("OPEN", R.L == L0, "cast length %d equals the data's lval %d", R.L, L0);
        GradeOpen("OPEN", mp, R, CX, 1, 0, f, true);
        int allies = 0, struckAllies = 0;
        for (int i = 0; i < n; ++i) if (f[i].ally) { ++allies; struckAllies += R.sq[i] && R.dmg[i]; }
        Chk("OPEN", allies == 1 && struckAllies == 1,
            "the ally inside the cone is struck (%d of %d)", struckAllies, allies);
        CheckPredict("open", R, f);
        CheckWave("open", R);
    }
    /* OFFAXIS: aim at the square (8,3). */
    {
        Foe f[] = { {0,6,2,0,0}, {0,3,1,0,0}, {0,7,3,0,0}, {0,6,4,0,0},
            {0,2,-2,0,0}, {0,8,-1,0,0}, {0,-2,0,0,0}, {0,1,4,0,0} };
        const int n = sizeof f / sizeof f[0];
        for (int i = 0; i < n; ++i) f[i].want = InCone(f[i].dx, f[i].dy, L0, 8, 3);
        Build(mp, pl, false, floor, wall);
        Res R; Cast(mp, pl, coneID, kob, "offaxis", CX, f, n, R, 8, 3);
        GradeOpen("OFFAXIS", mp, R, CX, 8, 3, f, true);
        CheckPredict("offaxis", R, f);
    }
    /* WALL: a wall two squares east cuts the cone. */
    {
        Foe f[] = { {0,1,0,0,1}, {0,1,2,0,1}, {0,4,0,0,0}, {0,4,3,0,0}, {0,6,-2,0,0} };
        const int n = sizeof f / sizeof f[0];
        Build(mp, pl, false, floor, wall);
        Rect wr(0, 0, mp->SizeX() - 1, mp->SizeY() - 1);
        for (int y = CY - 10; y <= CY + 10; ++y)
            mp->WriteAt(wr, CX + 2, y, wall, mp->RegionAt(CX, CY), PRIO_MAX, true);
        Res R; Cast(mp, pl, coneID, kob, "walled", CX, f, n, R);
        int behind = 0, inFront = 0;
        for (int y = 0; y < mp->SizeY(); ++y)
            for (int x = 0; x < mp->SizeX(); ++x)
                if (R.hit[y*R.W + x]) { if (x > CX + 2) ++behind; else ++inFront; }
        Chk("WALL", behind == 0 && inFront > 0,
            "squares struck behind the wall: %d (in front: %d)", behind, inFront);
        for (int i = 0; i < n; ++i)
            Chk("WALL", R.sq[i] == (f[i].want != 0) && R.dmg[i] == (f[i].want != 0),
                "foe at (%+d,%+d): wanted %s, square struck=%d damaged=%d",
                f[i].dx, f[i].dy, f[i].want ? "struck" : "untouched",
                (int)R.sq[i], (int)R.dmg[i]);
        CheckPredict("walled", R, f);
    }
    /* HALL: a length-3 cone east from mid-hallway. */
    {
        const int16 saved = TEFF(coneID)->ef.lval;
        TEFF(coneID)->ef.lval = 3;
        Foe f[] = { {0,-2,0,0,1}, {0,6,0,0,1}, {0,8,0,0,0}, {0,-4,0,0,0} };
        const int n = sizeof f / sizeof f[0];
        Build(mp, pl, true, floor, wall);
        Res R; Cast(mp, pl, coneID, kob, "hall", 20, f, n, R);
        TEFF(coneID)->ef.lval = saved;
        int open = 0, behind = 0, ahead = 0;
        {   /* the open-floor volume of a length-3 cone, from the probe's own cone */
            for (int dy = -5; dy <= 5; ++dy)
                for (int dx = -5; dx <= 5; ++dx) open += InCone(dx, dy, 3, 1, 0);
        }
        for (int x = 0; x < mp->SizeX(); ++x)
            if (R.hit[CY*R.W + x]) { if (x < 20) ++behind; else if (x > 20) ++ahead; }
        Chk("HALL", R.L == 3 && R.vol == open && open == 11,
            "open-floor volume of a length-3 cone: %d (engine %d, length %d)", open,
            R.vol, R.L);
        Chk("HALL", R.nStruck == open,
            "squares struck in the hallway %d equal the open-floor volume %d",
            R.nStruck, open);
        Chk("HALL", R.casterSq && R.casterDmg,
            "caster struck: square=%d damaged=%d", (int)R.casterSq, (int)R.casterDmg);
        Chk("HALL", behind == 3 && ahead == 7,
            "split is %d behind / caster / %d ahead (wanted 3 / 7)", behind, ahead);
        for (int i = 0; i < n; ++i)
            Chk("HALL", R.sq[i] == (f[i].want != 0) && R.dmg[i] == (f[i].want != 0),
                "foe at (%+d,%+d): wanted %s, square struck=%d damaged=%d",
                f[i].dx, f[i].dy, f[i].want ? "struck" : "untouched",
                (int)R.sq[i], (int)R.dmg[i]);
        CheckPredict("hall", R, f);
        CheckWave("hall", R);
    }
    Build(mp, pl, false, floor, wall);
    /* BREATH: monster breath shapes (inc-epzc0 phase 3). */
    {
        static const struct { const char *mon; int at; int want; } B[] = {
            {"gold dragon", A_BREA, 1},
            {"black dragon", A_BREA, 0}, {"blue dragon", A_BREA, 0},
            {"bronze dragon", A_BREA, 0},
            {"water mephit", A_BREA, -1}, {"spitting frog", A_SPIT, 0},
            {"half-red dragon", A_BREA, -1}, {"black dragon", A_BREA, 0} };
        for (size_t i = 0; i < sizeof(B)/sizeof(B[0]); ++i) {
            Build(mp, pl, false, floor, wall);
            Br b = Breathe(mp, pl, B[i].mon, B[i].at);
            if (B[i].want < 0) continue;   /* printed above, not graded */
            const bool fail = !b.ok || b.ret != 1 || b.struck < 2 ||
                (B[i].want == 1 ? !(b.cone && b.fired == 1 && b.offAxis > 0)
                                : !(!b.cone && b.offAxis == 0));
            Chk("BREATH", !fail,
                "%s type %d must be a %s: shape=%s struck=%d offaxis=%d fills=%d%s",
                B[i].mon, B[i].at, B[i].want ? "cone" : "beam",
                b.cone ? "cone" : "beam", b.struck, b.offAxis, b.fired,
                i == 7 ? " (after the gold dragon)" : "");
        }
    }
    Build(mp, pl, false, floor, wall);
    /* ITEMS and the other cone effects, each through its real path. */
    {
        struct P4 { const char *name; int mode; const char *base; int wantL; };
        static const P4 list[] = {
            {"Fear", 0, NULL, 0}, {"Shout", 0, NULL, 0}, {"Ice;wand", 1, "wand", 5},
            {"Blasting", 2, "horn", 0}, {"Dragon", 2, NULL, 6} };
        for (size_t i = 0; i < sizeof(list)/sizeof(list[0]); ++i) {
            /* FIND takes a monster or item of the same name first ("Dragon"). */
            rID eid = 0;
            for (int q = 0; q < MAX_MODULES && !eid; ++q)
                if (theGame->Modules[q])
                    for (int k = 0; k < theGame->Modules[q]->szEff; ++k)
                        if (!stricmp(list[i].name, theGame->Modules[q]->GetText(
                                theGame->Modules[q]->QEff[k].Name)))
                            { eid = theGame->Modules[q]->EffectID(k); break; }
            if (!eid) { Error("CONE_PROBE: P4 %s INCONCLUSIVE no such effect", list[i].name); continue; }
            Item *it = NULL;
            if (list[i].base) {
                it = Item::Create(FIND(list[i].base));
                it->MakeMagical(eid);
                it->MakeKnown(0xFF);
                it->SetCharges(list[i].mode == 1 ? 50 : 0); /* a horn counts uses up from 0 */
                pl->GainItem(it, true);
            }
            Build(mp, pl, false, floor, wall);
            Error("CONE_PROBE: P4 effect %s aval=%d lval=%d", list[i].name,
                (int)TEFF(eid)->ef.aval, (int)TEFF(eid)->ef.lval);
            Foe f[] = { {0,3,0,0,0}, {0,7,0,0,0}, {0,4,3,0,0}, {0,3,-3,0,0},
                {0,5,2,0,0}, {0,8,0,0,0}, {0,2,3,0,0}, {0,-3,0,0,0} };
            const int n = sizeof f / sizeof f[0];
            Res R; Cast(mp, pl, eid, kob, "open", CX, f, n, R, 1, 0, list[i].mode, it);
            int expected, mism = Compare(mp, R, CX, 1, 0, expected);
            Chk("ITEMS", mism == 0 && R.nStruck == R.vol && R.fired == 1 &&
                    (!list[i].wantL || R.L == list[i].wantL),
                "%s: length %d struck %d, volume %d, independent cone %d, mismatches %d%s",
                list[i].name, R.L, R.nStruck, R.vol, expected, mism,
                list[i].wantL ? " (named length checked)" : "");
            Chk("ITEMS", !R.casterSq, "%s: caster not struck", list[i].name);
        }
    }
    Build(mp, pl, false, floor, wall);
    for (int i = 0; i < NCASES; ++i)
        Error("CONE_PROBE: CASE %s %s checks=%d", CASES[i],
            gChecks[i] > 0 && !gBad[i] ? "PASS" : "FAIL", gChecks[i]);
    Error("CONE_PROBE: DONE");
}
