/* inc-az4d2: opt-in probe for the shape of a ball (AR_BALL). Off unless
   INCURSION_BALL_PROBE is set. Called from Game::Play (src/Main.cpp); graded
   by tools/check_ball_shape.sh. Output goes to errors.log through Error(), one
   BALL_PROBE line per case and one verdict line last. It builds its own map,
   fires Fireball (lval 2, a radius) and the Hellstorm at a chosen square, and reads what the ball struck
   through two hooks in src/Magic.cpp: AreaProbeXYHook (every MagicXY call) and
   BallRingHook (the fill's start, each distance band, the final hold). Only MagicXY
   calls after the fill starts count as struck: the travel to the center also
   calls MagicXY, and that is not the ball's area. */
#include <vector>
#include <math.h>
#include <stdarg.h>
#include "Incursion.h"

extern void (*AreaProbeXYHook)(int16,int16);
extern void (*BallRingHook)(int ring, int ntaken, const int16 *tx,
    const int16 *ty, int ndrawn, const int16 *dx, const int16 *dy, int waitMs);

namespace {

// no-family
const int MAXRING = 80;
const int BANDMAX = 160;
// end no-family
struct RingRec {
    int ring, nt, nd, wait;
    int16 tx[BANDMAX], ty[BANDMAX], dx[BANDMAX], dy[BANDMAX];
};

/* Written by the hooks, read once per shot. */
bool gOpen;
int gOpens, gCx, gCy, gFinalWait, gNRings, gNXY;
RingRec gRings[MAXRING];
int16 gXx[6000], gXy[6000];

void NoteXY(int16 x, int16 y) {
    if (gOpen && gNXY < 6000) { gXx[gNXY] = x; gXy[gNXY] = y; ++gNXY; }
}
void NoteRing(int ring, int nt, const int16 *tx, const int16 *ty, int nd,
    const int16 *dx, const int16 *dy, int wait) {
    if (ring == -2) {
        gOpen = true; ++gOpens; gCx = tx[0]; gCy = ty[0];
        return;
    }
    if (ring == -1) { gOpen = false; gFinalWait = wait; return; }
    if (gNRings >= MAXRING) return;
    RingRec &r = gRings[gNRings++];
    r.ring = ring; r.nt = nt; r.nd = nd; r.wait = wait;
    for (int i = 0; i < nt && i < BANDMAX; ++i) { r.tx[i] = tx[i]; r.ty[i] = ty[i]; }
    for (int i = 0; i < nd && i < BANDMAX; ++i) { r.dx[i] = dx[i]; r.dy[i] = dy[i]; }
}

struct Shot {
    bool fired;
    int cx, cy, nStruck, wallsXY, nRings, finalWait, centerHits;
    std::vector<char> hit;     /* non-solid squares struck, by y*sx+x */
    std::vector<RingRec> rings;
    int sx;
    bool Struck(int x, int y) const { return hit[y * sx + x] != 0; }
};

// no-family
const int CX = 26, CY = 17;   /* the center every case aims at */
// end no-family

struct Setup { Map *mp; Player *pl; rID floor, wall, door, kobold, fire, hell; };

bool InCorridor(int x, int y) { return y == CY && x >= 4 && x <= 36; }
bool InBlock(int x, int y) { return x >= 4 && x <= 38 && y >= 5 && y <= 29; }

/* kind 0: open room, 1: one-wide corridor with a door, 2: open room, the
   player boxed in by opaque (but not solid) squares so it sees nothing. */
void Build(const Setup &s, int kind, int plx, int ply) {
    Map *mp = s.mp; Player *pl = s.pl;
    Thing *obj; int index;
    for (;;) {
        Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != pl) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    pl->PlaceAt(mp, plx, ply);
    const rID region = mp->RegionAt(pl->x, pl->y);
    Rect rect(0, 0, mp->SizeX() - 1, mp->SizeY() - 1);
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x) {
            const bool open = kind == 1 ? InCorridor(x, y) : InBlock(x, y);
            mp->WriteAt(rect, x, y, open ? s.floor : s.wall, region, PRIO_MAX,
                true);
            mp->At(x, y).Lit = open;
            mp->At(x, y).Dark = false;
        }
    if (kind == 2)
        for (int dx = -1; dx <= 1; ++dx)
            for (int dy = -1; dy <= 1; ++dy)
                if (dx || dy) mp->At(plx + dx, ply + dy).Opaque = true;
    if (kind == 1) {
        Door *door = new Door(s.door);
        door->PlaceAt(mp, CX + 5, CY);
        door->DoorFlags = 0;
        door->Flags |= F_SOLID;
        door->SetImage();
    }
    pl->CalcVision();
}

Monster *Place(const Setup &s, int x, int y) {
    Monster *mn = new Monster(s.kobold);
    mn->PlaceAt(s.mp, x, y, true);
    mn->Initialize(true);
    return mn;
}

void Fire(const Setup &s, Shot &out, int mm = 0, rID eid = 0) {
    gOpen = false; gOpens = 0; gCx = gCy = -1; gFinalWait = -1;
    gNRings = 0; gNXY = 0;
    AreaProbeXYHook = NoteXY;
    BallRingHook = NoteRing;
    EventInfo xe; xe.Clear();
    xe.EActor = s.pl; xe.EMap = s.mp; xe.eID = eid ? eid : s.fire; xe.isSpell = true;
    xe.isLoc = true; xe.EXVal = CX; xe.EYVal = CY; xe.MM = mm;
    ReThrow(EV_EFFECT, xe);
    AreaProbeXYHook = NULL;
    BallRingHook = NULL;
    out.sx = s.mp->SizeX();
    out.fired = gOpens == 1;
    out.cx = gCx; out.cy = gCy;
    out.finalWait = gFinalWait; out.nRings = gNRings;
    out.hit.assign(s.mp->SizeX() * s.mp->SizeY(), 0);
    out.nStruck = out.wallsXY = out.centerHits = 0;
    for (int i = 0; i < gNXY; ++i) {
        const int x = gXx[i], y = gXy[i];
        if (x == CX && y == CY) ++out.centerHits;
        if (!s.mp->InBounds(x, y)) continue;
        if (s.mp->At(x, y).Solid) { ++out.wallsXY; continue; }
        if (!out.hit[y * out.sx + x]) { out.hit[y * out.sx + x] = 1; ++out.nStruck; }
    }
    out.rings.assign(gRings, gRings + gNRings);
}



/* The probe's own disc, independent of Magic::BallDiscCount. */
bool InDisc(int dx, int dy, int r) {
    return 4 * (dx * dx + dy * dy) <= (2 * r + 1) * (2 * r + 1);
}
int DiscN(int r) {
    int n = 0;
    for (int x = -r - 1; x <= r + 1; ++x)
        for (int y = -r - 1; y <= r + 1; ++y)
            if (InDisc(x, y, r)) ++n;
    return n;
}
/* Struck non-solid squares in the block that disagree with Disc(r) at the
   shot's center. Returns the count; first holds the first one found. */
int DiscMiss(const Setup &s, const Shot &sh, int r, int &fx, int &fy) {
    int bad = 0;
    fx = fy = -1;
    for (int y = 0; y < s.mp->SizeY(); ++y)
        for (int x = 0; x < s.mp->SizeX(); ++x) {
            if (s.mp->At(x, y).Solid) continue;
            if (sh.Struck(x, y) != InDisc(x - CX, y - CY, r))
                if (!bad++) { fx = x; fy = y; }
        }
    return bad;
}
/* The volume the design gives: 3*want is compared so Focus stays exact. */
int Snap(int base, int mm) {
    const int want3 = (mm & MM_ENLARGE) ? 6 * base : (mm & MM_FOCUS) ? base : 3 * base;
    int best = base, bd = abs(3 * base - want3);
    for (int r = 0; r < 100; ++r) {
        const int c = DiscN(r), d = abs(3 * c - want3);
        if (d <= bd) { best = c; bd = d; }
        if (3 * c > want3 && d > bd) break;
    }
    return best;
}
int SnapR(int vol) { int r = 0; while (DiscN(r) < vol) ++r; return r; }

} /* namespace */

/* inc-az4d2: opt-in ball shape probe (INCURSION_BALL_PROBE), graded by tools/check_ball_shape.sh. */
void BallShapeProbe(Player *pl) {
    if (!getenv("INCURSION_BALL_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("BALL_PROBE: INCONCLUSIVE -- no live player and map");
        return;
    }
    Setup s;
    s.mp = pl->m; s.pl = pl;
    s.floor = FIND("floor"); s.wall = FIND("dungeon wall");
    s.door = FIND("oak door"); s.kobold = FIND("kobold");
    s.fire = FIND("Fireball"); s.hell = FIND("the Hellstorm");
    if (!s.floor || !s.wall || !s.door || !s.kobold || !s.fire || !s.hell) {
        Error("BALL_PROBE: INCONCLUSIVE -- missing floor, dungeon wall, oak "
            "door, kobold, Fireball or the Hellstorm");
        return;
    }
    if (s.mp->SizeX() < 44 || s.mp->SizeY() < 34) {
        Error("BALL_PROBE: INCONCLUSIVE -- map %dx%d is smaller than 44x34",
            (int)s.mp->SizeX(), (int)s.mp->SizeY());
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    bool anyFail = false, anyInc = false;
    auto verdict = [&](const char *name, int ok, const char *fmt, ...) {
        char buf[300];
        va_list ap; va_start(ap, fmt); vsnprintf(buf, sizeof buf, fmt, ap);
        va_end(ap);
        Error("BALL_PROBE: %s %s %s", name, ok ? "PASS" : "FAIL", buf);
        if (!ok) anyFail = true;
    };
    auto inconclusive = [&](const char *name, const char *why) {
        Error("BALL_PROBE: %s INCONCLUSIVE -- %s", name, why);
        anyInc = true;
    };
    Shot a, b, c;
    const int R = TEFF(s.fire)->ef.lval;   /* Fireball's radius, from the data */

    /* ---- Case A0: the disc counts the design names. ---- */
    {
        const int want[5] = {1, 9, 21, 37, 69};
        int bad = 0;
        for (int r = 0; r < 5; ++r)
            if (Magic::BallDiscCount(r) != want[r] || DiscN(r) != want[r]) ++bad;
        verdict("A0", bad == 0, "DiscCount(0..4) = %d %d %d %d %d, need 1 9 21 "
            "37 69; bad=%d", (int)Magic::BallDiscCount(0),
            (int)Magic::BallDiscCount(1), (int)Magic::BallDiscCount(2),
            (int)Magic::BallDiscCount(3), (int)Magic::BallDiscCount(4), bad);
    }

    /* ---- Case A (and E): open floor, four kobolds, player 5 west. ---- */
    Build(s, 0, CX - 5, CY);
    /* K1 (+2,+1): inside Disc(2), outside a 3-square-radius diamond rule
       of the old kind. K2 (+2,+2): outside Disc(2). K3 (-2,-1): inside.
       K4 (0,-3): outside. */
    Monster *k[4];
    const int kdx[4] = {2, 2, -2, 0}, kdy[4] = {1, 2, -1, -3};
    int kx[4], ky[4];
    for (int i = 0; i < 4; ++i) {
        kx[i] = CX + kdx[i]; ky[i] = CY + kdy[i];
        k[i] = Place(s, kx[i], ky[i]);
    }
    Creature *victims[1024]; int16 nv = 0;
    bool predOK = false;
    {
        EventInfo pe; pe.Clear();
        pe.EActor = pl; pe.EMap = s.mp; pe.eID = s.fire; pe.isSpell = true;
        pe.EMagic = &TEFF(s.fire)->ef; pe.Event = EV_CAST; pe.MM = 0;
        pe.isLoc = true; pe.EXVal = CX; pe.EYVal = CY;
        pe.vCasterLev = (int8)pl->CasterLev();
        pe.vRange = pe.EMagic->lval;
        pl->CalcEffect(pe);
        pl->PredictVictimsOfBallBeamBolt(pe, false, true, false, victims, nv);
        predOK = true;
    }
    Fire(s, a);
    if (!a.fired || a.cx != CX || a.cy != CY) {
        inconclusive("A", "the ball did not open its fill at the aimed square");
    } else {
        int fx, fy;
        const int miss = DiscMiss(s, a, R, fx, fy);
        Error("BALL_PROBE: A-info center=(%d,%d) center_struck=%d wallsXY=%d "
            "rings=%d radius=%d", (int)a.cx, (int)a.cy, (int)a.Struck(CX, CY),
            a.wallsXY, a.nRings, R);
        verdict("A2", miss == 0, "squares where struck and Disc(%d) differ=%d "
            "first=(%d,%d)", R, miss, fx, fy);
        verdict("A4", a.nStruck == DiscN(R), "struck=%d Disc(%d)=%d",
            a.nStruck, R, DiscN(R));

        /* Case D: from case A's band records. */
        int d1bad = 0, d1ring = -1, d1x = -1, d1y = -1, d2bad = 0, d3bad = 0,
            d4bad = 0, expect = 0;
        for (size_t r = 0; r < a.rings.size(); ++r) {
            const RingRec &rr = a.rings[r];
            if (rr.ring != expect) ++d2bad;
            expect = rr.ring + 1;
            for (int i = 0; i < rr.nt; ++i) {
                const int dx = rr.tx[i] - CX, dy = rr.ty[i] - CY;
                if ((int)floor(sqrt((double)(dx * dx + dy * dy)) + 0.5) != rr.ring)
                    if (!d1bad++) { d1ring = rr.ring; d1x = rr.tx[i]; d1y = rr.ty[i]; }
            }
            for (int i = 0; i < rr.nd; ++i) {
                bool in = false;
                for (int j = 0; j < rr.nt; ++j)
                    if (rr.tx[j] == rr.dx[i] && rr.ty[j] == rr.dy[i]) in = true;
                if (!in) ++d3bad;
            }
            if (rr.nd > 0 && rr.wait != 70) ++d4bad;
        }
        if (a.rings.empty()) {
            inconclusive("D", "the ball reported no bands");
        } else {
            verdict("D1", d1bad == 0, "taken squares off round(distance)==band: "
                "%d first=band %d (%d,%d)", d1bad, d1ring, d1x, d1y);
            verdict("D1b", a.rings[0].ring == 0 && a.rings[0].nt == 1 &&
                a.rings[0].tx[0] == CX && a.rings[0].ty[0] == CY,
                "band 0 holds the center alone: band=%d taken=%d",
                a.rings[0].ring, a.rings[0].nt);
            verdict("D2", d2bad == 0, "band numbers out of step=%d bands=%d",
                d2bad, (int)a.rings.size());
            verdict("D3", d3bad == 0, "drawn squares not taken=%d", d3bad);
            verdict("D4", d4bad == 0, "drawing bands not asking 70ms=%d",
                d4bad);
            verdict("D6", a.centerHits == 1, "center struck %d times (need "
                "1)", a.centerHits);
            verdict("D5", a.finalWait == 300, "final hold asks %d ms",
                a.finalWait);
        }

        /* Case E: prediction against the kobolds on struck squares. */
        if (!predOK) {
            inconclusive("E", "the prediction could not be called with the "
                "cast's inputs");
        } else {
            int bad = 0;
            for (int i = 0; i < 4; ++i) {
                bool pred = false;
                for (int j = 0; j < nv; ++j) if (victims[j] == k[i]) pred = true;
                const bool stood = a.Struck(kx[i], ky[i]);
                const bool inside = InDisc(kdx[i], kdy[i], R);
                Error("BALL_PROBE: E-info kobold%d at (%+d,%+d) struck=%d "
                    "predicted=%d in_disc=%d", i + 1, kdx[i], kdy[i],
                    (int)stood, (int)pred, (int)inside);
                if (pred != stood || stood != inside) ++bad;
            }
            verdict("E1", bad == 0, "kobolds where prediction, strike and "
                "Disc(%d) do not agree=%d victims_listed=%d", R, bad, (int)nv);
        }
    }

    /* ---- Case A5: the fill function itself, r=1 and r=3. ---- */
    {
        Build(s, 0, CX - 5, CY);
        int bad1 = 0, bad3 = 0, n1 = 0, n3 = 0;
        for (int pass = 0; pass < 2; ++pass) {
            const int r = pass ? 3 : 1;
            std::vector<BallSquare> out;
            Magic::BallFill(*s.mp, CX, CY, DiscN(r), out);
            int n = 0, bad = 0;
            for (size_t i = 0; i < out.size(); ++i)
                if (out[i].kind == 0) {
                    ++n;
                    if (!InDisc(out[i].x - CX, out[i].y - CY, r)) ++bad;
                }
            if (n != DiscN(r)) ++bad;
            if (pass) { bad3 = bad; n3 = n; } else { bad1 = bad; n1 = n; }
        }
        verdict("A5", bad1 == 0 && bad3 == 0, "BallFill graded directly (not "
            "cast): r=1 taken=%d bad=%d, r=3 taken=%d bad=%d", n1, bad1, n3,
            bad3);
    }

    /* ---- Case E2: Enlarge. Strike is Disc(3); prediction agrees. ---- */
    {
        Build(s, 0, CX - 5, CY);
        const int savedHP = pl->cHP;
        pl->cHP = 30000;
        const int edx[4] = {3, 3, -2, 0}, edy[4] = {1, 2, -2, -4};
        Monster *ek[4]; int ex[4], ey[4];
        for (int i = 0; i < 4; ++i) {
            ex[i] = CX + edx[i]; ey[i] = CY + edy[i];
            ek[i] = Place(s, ex[i], ey[i]);
        }
        Creature *ev[1024]; int16 env = 0;
        EventInfo pe; pe.Clear();
        pe.EActor = pl; pe.EMap = s.mp; pe.eID = s.fire; pe.isSpell = true;
        pe.EMagic = &TEFF(s.fire)->ef; pe.Event = EV_CAST; pe.MM = MM_ENLARGE;
        pe.isLoc = true; pe.EXVal = CX; pe.EYVal = CY;
        pe.vCasterLev = (int8)pl->CasterLev();
        pe.vRange = pe.EMagic->lval;
        pl->CalcEffect(pe);
        pl->PredictVictimsOfBallBeamBolt(pe, false, true, false, ev, env);
        Shot en;
        Fire(s, en, MM_ENLARGE);
        pl->cHP = savedHP;
        const int r3 = SnapR(Snap(DiscN(R), MM_ENLARGE));
        if (!en.fired || en.cx != CX || en.cy != CY) {
            inconclusive("E2", "the enlarged ball did not open its fill at "
                "the aimed square");
        } else {
            int fx, fy;
            const int miss = DiscMiss(s, en, r3, fx, fy);
            int bad = 0;
            for (int i = 0; i < 4; ++i) {
                bool pred = false;
                for (int j = 0; j < env; ++j) if (ev[j] == ek[i]) pred = true;
                const bool stood = en.Struck(ex[i], ey[i]);
                const bool inside = InDisc(edx[i], edy[i], r3);
                Error("BALL_PROBE: E2-info kobold%d at (%+d,%+d) struck=%d "
                    "predicted=%d in_disc=%d", i + 1, edx[i], edy[i],
                    (int)stood, (int)pred, (int)inside);
                if (pred != stood || stood != inside) ++bad;
            }
            verdict("E2", miss == 0 && en.nStruck == DiscN(r3) && bad == 0,
                "enlarged: Disc(%d) misses=%d struck=%d need=%d kobolds not "
                "agreeing=%d victims_listed=%d", r3, miss, en.nStruck,
                DiscN(r3), bad, (int)env);
        }
    }

    /* ---- Case F: Focus. A focused Fireball strikes Disc(1). ---- */
    {
        Build(s, 0, CX - 5, CY);
        Shot fo;
        Fire(s, fo, MM_FOCUS);
        const int rf = SnapR(Snap(DiscN(R), MM_FOCUS));
        if (!fo.fired || fo.cx != CX || fo.cy != CY) {
            inconclusive("F", "the focused ball did not open its fill at the "
                "aimed square");
        } else {
            int fx, fy;
            const int miss = DiscMiss(s, fo, rf, fx, fy);
            verdict("F1", rf == 1 && miss == 0 && fo.nStruck == 9,
                "focused: snapped radius=%d Disc misses=%d struck=%d need 9",
                rf, miss, fo.nStruck);
        }
    }

    /* ---- Case G: capacity. The Hellstorm, Enlarged, in open floor. ---- */
    {
        Build(s, 0, CX - 5, CY);
        const int savedHP = pl->cHP;
        pl->cHP = 30000;
        const int hr = TEFF(s.hell)->ef.lval;
        const int vol = Snap(DiscN(hr), MM_ENLARGE);
        Shot hs;
        Fire(s, hs, MM_ENLARGE, s.hell);
        pl->cHP = savedHP;
        Error("BALL_PROBE: G-info Hellstorm lval=%d Disc=%d doubled=%d "
            "snapped=%d (radius %d)", hr, DiscN(hr), 2 * DiscN(hr), vol,
            SnapR(vol));
        if (!hs.fired || hs.cx != CX || hs.cy != CY) {
            inconclusive("G", "the Hellstorm did not open its fill at the "
                "aimed square");
        } else {
            int fx, fy;
            const int miss = DiscMiss(s, hs, SnapR(vol), fx, fy);
            verdict("G1", hs.nStruck == vol && miss == 0, "struck=%d need=%d "
                "Disc misses=%d first=(%d,%d)", hs.nStruck, vol, miss, fx, fy);
        }
    }

    /* ---- Case B: corridor, door 5 east of center, player 4 west. ---- */
    Build(s, 1, CX - 4, CY);
    Fire(s, b);
    if (!b.fired || b.cx != CX || b.cy != CY) {
        inconclusive("B", "the ball did not open its fill at the aimed square");
    } else {
        int b1bad = 0, b1x = -1, b1y = -1, east = 0;
        for (int y = 0; y < s.mp->SizeY(); ++y)
            for (int x = 0; x < s.mp->SizeX(); ++x) {
                if (!b.Struck(x, y)) continue;
                if (!InCorridor(x, y)) { if (!b1bad++) { b1x = x; b1y = y; } }
                if (x > CX + 5 && InCorridor(x, y)) ++east;
            }
        const bool doorXY = [&] {
            for (int i = 0; i < gNXY; ++i)
                if (gXx[i] == CX + 5 && gXy[i] == CY) return true;
            return false;
        }();
        Error("BALL_PROBE: B-info door square terrain Solid=%d struck=%d "
            "(the disc's count is %d)", (int)s.mp->At(CX + 5, CY).Solid,
            b.nStruck, DiscN(R));
        verdict("B1", b1bad == 0, "struck non-solid squares outside the "
            "corridor=%d first=(%d,%d) wallsXY=%d (wall squares do get "
            "MagicXY and are not counted)", b1bad, b1x, b1y, b.wallsXY);
        verdict("B2", doorXY && east == 0, "door_struck=%d squares_east_of_"
            "door_struck=%d", (int)doorXY, east);
        verdict("B3", b.nStruck <= DiscN(R) && b.nStruck >= 17, "corridor "
            "struck=%d need 17..%d", b.nStruck, DiscN(R));
    }

    /* ---- Case C: case A's terrain and center, player sees nothing. ---- */
    Build(s, 2, CX - 5, CY);
    Fire(s, c);
    {
        /* the player's view of the area: no square of it in line of sight */
        int seen = 0;
        for (int y = CY - 6; y <= CY + 6; ++y)
            for (int x = CX - 6; x <= CX + 6; ++x)
                if (abs(x - pl->x) > 1 || abs(y - pl->y) > 1)
                  if (s.mp->LineOfSight(pl->x, pl->y, x, y, pl)) ++seen;
        if (!c.fired || c.cx != CX || c.cy != CY || !a.fired) {
            inconclusive("C", "the ball did not open its fill at the aimed "
                "square");
        } else if (seen) {
            inconclusive("C", "the player still sees part of the area");
        } else {
            int diff = 0, dx0 = -1, dy0 = -1;
            for (int y = 0; y < s.mp->SizeY(); ++y)
                for (int x = 0; x < s.mp->SizeX(); ++x)
                    if (a.Struck(x, y) != c.Struck(x, y))
                        if (!diff++) { dx0 = x; dy0 = y; }
            int drawn = 0;
            for (size_t r = 0; r < c.rings.size(); ++r) drawn += c.rings[r].nd;
            Error("BALL_PROBE: C-info player boxed in by opaque non-solid "
                "squares; area squares in sight=0 bands=%d", c.nRings);
            verdict("C1", diff == 0, "struck squares differing from case A=%d "
                "first=(%d,%d) struck_A=%d struck_C=%d", diff, dx0, dy0,
                a.nStruck, c.nStruck);
            verdict("C2", drawn == 0, "drawn squares=%d", drawn);
        }
    }

    Build(s, 0, CX - 5, CY); /* leave no door or blind box behind */
    theGame->PlayMode = wasInPlay;
    if (anyFail)
        Error("BALL_PROBE: FAIL");
    else if (anyInc)
        Error("BALL_PROBE: INCONCLUSIVE -- a case could not be established");
    else
        Error("BALL_PROBE: PASS");
}
