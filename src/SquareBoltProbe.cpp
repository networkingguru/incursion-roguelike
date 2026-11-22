/* inc-s87gl: opt-in probe. Off unless INCURSION_SQUARE_BOLT_PROBE is set.
   Called from Game::Play (src/Main.cpp); graded by
   tools/check_square_bolt_flight.sh. A non-multi, non-ball bolt with no chosen
   creature (aimed at a square, or cast in a direction) MUST fly: a glyph on
   every square it crosses, and the effect run there (Magic::MagicXY).
   It builds one open, lit room and casts the wand effect Fire Bolts
   (lib/m_items.irh, AR_BOLT, AD_FIRE) from a +5 wand along row y=11 from the player at (5,11), reading two existing hooks:
   GlyphDrawHook kind 5 (a bolt glyph drawn, src/Magic.cpp) and
   AreaProbeXYHook (every MagicXY call). Each case logs one SQUARE_BOLT line. */
#include "Incursion.h"

extern void (*GlyphDrawHook)(int kind, int x, int y);
extern void (*AreaProbeXYHook)(int16,int16);
extern void LOFSetForcedRoll(int8 r);

namespace {

// no-family
const int RX0 = 3, RX1 = 36, RY0 = 3, RY1 = 20;   /* the open room */
const int PLX = 5, PLY = 11;
// end no-family

Player *gPl;
int gGlyph[64], gXY[64];          /* per-column counts for the current case */
Monster *gWatch;                  /* the creature whose hit points order is checked */
int gGlyphAfterHit;               /* glyphs drawn after gWatch lost hit points */
int gGlyphN, gXYN;

void NoteGlyph(int kind, int x, int y) {
    if (kind != 5 || y != PLY || x < 0 || x >= 64) return;
    ++gGlyph[x]; ++gGlyphN;
    if (gWatch && gWatch->cHP < 10000) ++gGlyphAfterHit;
}
void NoteXY(int16 x, int16 y) {
    if (y != PLY || x < 0 || x >= 64) return;
    ++gXY[x]; ++gXYN;
}

} /* namespace */

void SquareBoltProbe(Player *pl) {
    if (!getenv("INCURSION_SQUARE_BOLT_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("SQUARE_BOLT: INCONCLUSIVE -- no live player and map");
        return;
    }
    Map *mp = pl->m;
    const rID floor = FIND("floor"), wall = FIND("dungeon wall");
    const rID iceID = FIND("Ice Wall"), kobID = FIND("kobold");
    const rID wandID = FIND("wand"), fireID = FIND("Fire Bolts");
    if (!floor || !wall || !iceID || !kobID || !fireID || !wandID) {
        Error("SQUARE_BOLT: INCONCLUSIVE -- missing floor, wall, Ice Wall, "
            "kobold, wand or Fire Bolts");
        return;
    }
    if (mp->SizeX() < 40 || mp->SizeY() < 24) {
        Error("SQUARE_BOLT: INCONCLUSIVE -- map smaller than 40x24");
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
            const bool open = x >= RX0 && x <= RX1 && y >= RY0 && y <= RY1;
            mp->WriteAt(rect, x, y, open ? floor : wall, region, PRIO_MAX, true);
            mp->At(x, y).Lit = open;
            mp->At(x, y).Dark = false;
            mp->At(x, y).Visibility = 0;
            mp->At(x, y).Memory = 0;
        }
    pl->CalcVision();
    int los = 0, sq = 0;
    for (int x = PLX + 1; x <= RX1; ++x) {
        ++sq;
        if (mp->LineOfSight(pl->x, pl->y, x, PLY, pl)) ++los;
    }
    Error("SQUARE_BOLT: SETUP player=(%d,%d) row_squares=%d row_in_los=%d "
        "map=%dx%d", (int)pl->x, (int)pl->y, sq, los, (int)mp->SizeX(),
        (int)mp->SizeY());
    if (los != sq) {
        Error("SQUARE_BOLT: INCONCLUSIVE -- the row is not all in line of sight");
        theGame->PlayMode = wasInPlay;
        return;
    }
    pl->GainAbility(CA_SPELLCASTING, 10, 0, SS_PERM);
    Item *wand = Item::Create(wandID);
    wand->MakeMagical(fireID, 5);
    pl->GainItem(wand, false);
    gPl = pl;
    GlyphDrawHook = NoteGlyph;
    AreaProbeXYHook = NoteXY;

    Monster *kob[2] = {NULL, NULL};
    auto clearKobolds = [&]() {
        for (int i = 0; i < 2; ++i)
            if (kob[i]) { kob[i]->Remove(true); kob[i] = NULL; }
    };
    auto placeKobold = [&](int slot, int x) {
        Monster *mn = new Monster(kobID);
        mn->PlaceAt(mp, x, PLY, true);
        mn->Initialize(true);
        mn->RemoveStati(SLEEPING); mn->RemoveStati(ASLEEP);
        mn->mHP = mn->cHP = 10000;
        kob[slot] = mn;
    };
    /* one case: cast, then log which required squares got no glyph and no
       effect. need = squares from..to (columns) that MUST show both. */
    auto runCase = [&](const char *name, bool dir, int aimX, int roll,
            int needFrom, int needTo, Monster *watch, bool wantStruck, Monster *aimAt = NULL) {
        memset(gGlyph, 0, sizeof gGlyph); memset(gXY, 0, sizeof gXY);
        gGlyphN = gXYN = gGlyphAfterHit = 0;
        gWatch = watch;
        LOFSetForcedRoll((int8)roll);
        EventInfo xe; xe.Clear();
        xe.EActor = pl;
        xe.eID    = fireID;
        xe.EItem  = wand;
        xe.vRange = 20;
        xe.EMap   = mp;
        xe.MM     = MM_MAXIMIZE;
        if (dir) { xe.isDir = true; xe.EDir = EAST; }
        else if (aimAt) xe.EVictim = aimAt;   /* aimed AT it */
        else     { xe.isLoc = true; xe.EXVal = aimX; xe.EYVal = PLY; }
        const EvReturn r = ReThrow(EV_EFFECT, xe);
        LOFSetForcedRoll(0);
        int glyphMissing = 0, xyMissing = 0;
        char drawn[200] = "";
        for (int x = needFrom; x <= needTo; ++x) {
            if (!gGlyph[x]) ++glyphMissing;
            if (!gXY[x]) ++xyMissing;
        }
        for (int x = 0; x < 64; ++x)
            if (gGlyph[x])
                snprintf(drawn + strlen(drawn), sizeof drawn - strlen(drawn) - 1,
                    "%d,", x);
        int hit = 0;
        for (int i = 0; i < 2; ++i)
            if (kob[i] && kob[i]->cHP < 10000) ++hit;
        const int sA = (kob[0] && kob[0]->cHP < 10000) ? 1 : 0;
        const int sB = (kob[1] && kob[1]->cHP < 10000) ? 1 : 0;
        Error("SQUARE_BOLT: CASE name=%s struckA=%d struckB=%d cast=%d need=%d..%d glyph_missing=%d "
            "glyphs_total=%d xy_missing=%d xy_total=%d kobolds_struck=%d "
            "want_struck=%d glyphs_after_hit=%d drawn=%s", name, sA, sB,
            r != ABORT ? 1 : 0, needFrom, needTo, glyphMissing, gGlyphN,
            xyMissing, gXYN, hit, wantStruck ? 1 : 0, gGlyphAfterHit, drawn);
    };

    /* S5 control: aimed AT a kobold at x=15. */
    placeKobold(0, 15);
    runCase("S5-control-at-creature", false, 15, 20, PLX + 1, 14, kob[0], false, kob[0]);
    clearKobolds();
    /* S1: empty square at x=15. */
    runCase("S1-empty-square", false, 15, 20, PLX + 1, 14, NULL, false);
    /* S2: empty aim x=15, a kobold on x=14; forced hit. */
    placeKobold(0, 14);
    runCase("S2-creature-beside-aim", false, 15, 20, PLX + 1, 13, kob[0], true);
    clearKobolds();
    /* S3: two kobolds on x=10 and x=13, forced miss (roll 1 misses both);
       the flight passes both and ends at the aim square x=15. */
    placeKobold(0, 10); placeKobold(1, 13);
    runCase("S3-miss-both-flies-on", false, 15, 1, PLX + 1, 14, NULL, false);
    clearKobolds();
    /* S4: a direction cast east, nothing in the way. MagicEvent recomputes the
       range from the effect (here 10 squares, counted from the caster's own
       square), so the probe's vRange=20 is overwritten: require 10 squares. */
    runCase("S4-direction-cast", true, 0, 20, PLX + 1, PLX + 9, NULL, false);
    /* S7: miss A (x=10), beat B (x=13), one roll. The pins come from the
       game's own arithmetic: total = vHit + roll against TouchDef + penalty,
       penalty LineOfFireCoverPenalty(1) with two candidates. vHit is read
       from a calibration cast (A unbeatable), so no seed enters. */
    extern int8 LOFGetLastVHit();
    extern int8 LineOfFireCoverPenalty(int16 N);
    auto s7 = [&](const char *name, int xa, int xb, int needTo) {
        placeKobold(0, xa); placeKobold(1, xb);
        kob[0]->TouchDef = 60; kob[1]->TouchDef = 60;
        runCase("S0-calibration", false, 15, 10, PLX + 1, PLX + 1, NULL, false);
        const int vHit = LOFGetLastVHit(), pen = LineOfFireCoverPenalty(1);
        const int DB = vHit + 10 - pen, DA = DB + 5;
        Error("SQUARE_BOLT: PIN case=%s vHit=%d pen=%d TouchDefA=%d TouchDefB=%d "
            "roll=10", name, vHit, pen, DA, DB);
        for (int i = 0; i < 2; ++i) kob[i]->cHP = kob[i]->mHP = 10000;
        /* the chain head is the first candidate; pin it to miss, the next to
           beat the roll by 1 (no tie: Strike and the explicit strike treat a
           tie differently) */
        Creature *head = mp->FCreatureAt(xa, PLY);
        Monster *first = kob[0], *second = kob[1];
        if (xa == xb && head == kob[1]) { first = kob[1]; second = kob[0]; }
        first->TouchDef = (int8)DA; second->TouchDef = (int8)(DB - 1);
        Error("SQUARE_BOLT: HEAD case=%s head_is_slot=%d", name,
            head == kob[0] ? 0 : head == kob[1] ? 1 : -1);
        runCase(name, false, 15, 10, PLX + 1, needTo, second, true);
        Error("SQUARE_BOLT: ROLE case=%s struck_first=%d struck_second=%d", name,
            first->cHP < 10000 ? 1 : 0, second->cHP < 10000 ? 1 : 0);
        clearKobolds();
    };
    s7("S7-miss-then-hit", 10, 13, 12);
    /* S8: two kobolds on ONE square (a rider and its mount share a square
       the same way). The line-of-fire spec tests the head of each square
       only, so a beatable second creature is NOT struck: head missed, none
       struck, the flight runs on to the aim square. */
    s7("S8-same-square-head-only", 12, 12, 14);

    /* S6: an Ice Wall at x=10 on the row. Fire melts it only through
       MagicXY on that square. Control S6c aims at a kobold at x=15 behind
       it; S6 aims at the empty square x=15. */
    mp->WriteTerra(10, PLY, iceID);
    placeKobold(0, 15);
    runCase("S6c-ice-wall-at-creature", false, 15, 20, 10, 10, NULL, false, kob[0]);
    Error("SQUARE_BOLT: ICE name=S6c still_ice=%d",
        mp->TerrainAt(10, PLY) == iceID ? 1 : 0);
    clearKobolds();
    mp->WriteTerra(10, PLY, iceID);
    runCase("S6-ice-wall-empty-square", false, 15, 20, 10, 10, NULL, false);
    Error("SQUARE_BOLT: ICE name=S6 still_ice=%d",
        mp->TerrainAt(10, PLY) == iceID ? 1 : 0);

    GlyphDrawHook = NULL;
    AreaProbeXYHook = NULL;
    gPl = NULL;
    Error("SQUARE_BOLT: DONE");
    theGame->PlayMode = wasInPlay;
}
