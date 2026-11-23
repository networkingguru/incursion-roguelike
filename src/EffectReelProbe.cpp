/* inc-jw0hw: opt-in effect reel. Off unless INCURSION_EFFECT_REEL is set.
   Called from Game::Play (src/Main.cpp); driven by tools/render_effect_reel.sh,
   counted by tools/check_effect_reel_list.sh. For every effect that is EA_BLAST,
   AR_GLOBE, an AR_FIELD/AR_MFIELD with FI_MODIFIER or FI_BLOCKER, or flagged
   EF_COLOR_PATTERN, plus
   "Breath Weapon" once per damage type a monster breathes, it rebuilds one lit
   room, names a recorder clip, casts the effect, and lets virtual time pass.
   errors.log gets "REEL <n> <name> <kind>", "REEL_SKIP <name> <reason>" and
   "REEL_DONE <count>" last. INCURSION_EFFECT_REEL_ONLY=<a,b> keeps only the
   named effects (case-insensitive). A clip whose row in INCURSION_LIGHT_TABLE says
   shows_nothing = yes is skipped with a REEL_SKIP line. Its glow column picks the room: UNLIT
   (or no row) a bright room, LIT a dark one; REEL_ROOM <n> <name> bright|dark logs it. */
#include <ctype.h>
#include <strings.h>
#include <string>
#include <vector>
#define protected public   /* Term::QueuedChar (answers a script prompt) and Term::XOff/YOff (the map view), as EffectLightProbe does */
#include "Incursion.h"
#undef protected
#include "Light.h"
#include "EffectLight.h"

extern int16 Silence;
extern bool isExchange;
extern void LOFSetForcedRoll(int8 r);
extern void LOFSetForcedSaveThrowRoll(int8 r);
extern void LOFClearForcedSaveThrowRoll();
extern Trap *SkullTrapPlace(Player *pl, Map *mp, rID trapR, rID skull, rID skullSpell, int x, int y);

extern void (*PutGlyphProbeHook)(int16 x, int16 y, bool remembered, uint16 vis);
extern void (*BallRingHook)(int ring, int ntaken, const int16 *tx, const int16 *ty,
    int ndrawn, const int16 *dx, const int16 *dy, int waitMs);
extern void (*GlobeGlyphHook)(int16 x, int16 y, Glyph was, Glyph now);
extern void (*FormationHook)(int order, int batch, int n, const int16 *xs, const int16 *ys, Glyph first, int drawn,
    int16 cx, int16 cy, int16 radius, rID terrain);

extern void (*SporeHook)(int id, int step, int16 x, int16 y, int16 dx, int16 dy, Glyph g);
extern void (*WallSweepHook)(void);

namespace {
/* inc-jw0hw: the paint decision TextTerm::PutGlyph made for the three kobold squares in the last Refresh: -1 not painted through the light, 0 lit, 1 remembered. */
int gPaintRem[3] = { -1, -1, -1 };
int16 gPaintX[3], gPaintY[3];
signed char gSqPaint[64][40];   /* the same decision for every square of the Pyrotechnics (smoke) log: -1 none, 0 lit, 1 remembered */
void PaintHook(int16 x, int16 y, bool remembered, uint16) {
    if (x >= 0 && x < 64 && y >= 0 && y < 40) gSqPaint[x][y] = remembered ? 1 : 0;
    for (int k = 0; k < 3; ++k)
        if (x == gPaintX[k] && y == gPaintY[k]) gPaintRem[k] = remembered ? 1 : 0;
}

// no-family
const int PX = 5, PY = 17;     /* the player's square in every clip: west end of the room, middle row */
const int RX0 = 4, RX1 = 34, RY0 = 10, RY1 = 24;   /* the floor: 31 x 15 */
const int CX = (RX0 + RX1) / 2;                    /* the map window centers here */
const int AIMX = PX + 9;       /* the middle target; the other two stand 2 squares above and below */
const int STUBX = AIMX + 2;    /* a wall stub for the spill to land on */
// end no-family

struct Entry { rID id; const char *kind; int dtype; char form; bool cone; };   /* dtype -1: not a breath; form: the answer to Pyrotechnics' prompt, 0 for none */

/* inc-jw0hw: how a player's cast aims an effect. The first segment's qval says what the
   cast prompt asks for (Monster.cpp:1622-1640 is the monster form of the same test); with
   none of Q_TAR, Q_LOC and Q_DIR there is no prompt and Magic.cpp:1250 makes the caster
   the target. An aura field and a breath keep the reel's own aim. */
bool IsTouch(TEffect *te) {
    if (te->ef.aval == AR_TOUCH) return true;
    for (int8 v = 1; te->Vals(v); ++v)
        if (te->Vals(v)->aval == AR_TOUCH) return true;
    return false;
}
// no-family
enum AimKind { AIM_SELF, AIM_DIR, AIM_TAR, AIM_LOC, AIM_FIELD, AIM_BREATH };
// end no-family
const char *const kAimName[] = { "self", "dir", "tar", "loc", "field", "breath" };
AimKind AimOf(const Entry &en, TEffect *te) {
    if (en.dtype >= 0) return AIM_BREATH;
    if (en.form) return AIM_LOC;               /* Pyrotechnics is Q_LOC */
    if (en.kind[0] == 'a') return AIM_FIELD;
    const uint32 q = (uint32)te->ef.qval;
    if (q & Q_TAR) return AIM_TAR;
    if (q & Q_LOC) return AIM_LOC;
    if (q & Q_DIR) return AIM_DIR;
    /* Only a player-centered globe or a touch is cast on the caster. An effect with no prompt and no area (a poison
       or venom, a bolt a monster fires) is delivered to a victim, and cast on the player it drains him dead and
       ends the run; a death effect (Unearthly Beauty, a gaze) does the same whatever the hit points. Those two
       and a trapdoor are aimed at the middle kobold. */
    bool globeOrTouch = IsTouch(te) || te->ef.aval == AR_GLOBE;
    for (int8 v = 1; te->Vals(v); ++v) globeOrTouch = globeOrTouch || te->Vals(v)->aval == AR_GLOBE;
    /* A trapdoor drops its victim to the next level, so on the caster it ends the clip run. */
    if (te->HasFlag(EF_DEATH) || !globeOrTouch || strstr(NAME(en.id), "trapdoor")) return AIM_TAR;
    return AIM_SELF;
}

/* Effects whose script asks the player to choose (a menu, a prompt); the reel has no
   keys to answer with. ponytail: a new prompting effect hangs the run until it is
   added here; the render script feeds ESC keys so the run ends instead. */
struct SkipRow { const char *name, *reason; };
const SkipRow kSkip[] = {
    { "Alisdair's Fundamental Breakdown", "it opens a menu to choose a potion" },
    { "Animate Dead", "it asks: skeletons or zombies" },
    { "Ice Storm", "it asks: hail or sleet" },
    { "Bless", "it asks: combat blessing or item blessing" },
};

/* inc-jw0hw (Phase 2): what each clip's cast draws, for tools/check_effect_reel_shapes.sh. The hooks are set around the cast
   and write REEL_STEP (a projectile, pillar, dart, thrown item or burst glyph shows), REEL_RING (a ball or globe ring) and
   REEL_GLOBEGLYPH (a recolored globe square) lines, each with the number of light flashes alive at that moment. */
char gClip[160];
int gElLit, gElLitFlash, gTfLit;
void StepHook(int kind, int16 x, int16 y, Glyph g) {
    static const char *const kn[] = { "travel", "step", "pillar", "dart", "thrown", "burst" };
    Error("REEL_STEP %s %s %d,%d glyph %d fore %d flashes %d lit %d", gClip, kn[kind], (int)x, (int)y,
          (int)GLYPH_ID_VALUE(g), (int)GLYPH_FORE_VALUE(g), (int)LightFlashCount(), LightLitAt(x, y) ? 1 : 0);
}
void ElHook(int phase) {
    if (phase != EL_LIT) return;
    ++gElLit;
    if (LightFlashCount() > 0) ++gElLitFlash;
}
void TfHook(int phase) { if (phase == TF_LIT) ++gTfLit; }
void RingHook(int ring, int ntaken, const int16 *tx, const int16 *ty, int ndrawn, const int16 *, const int16 *, int) {
    Error("REEL_RING %s ring %d taken %d drawn %d flashes %d at %d,%d", gClip, ring, ntaken, ndrawn, (int)LightFlashCount(),
          ring == -2 && tx ? (int)tx[0] : -1, ring == -2 && ty ? (int)ty[0] : -1);
}
/* inc-jw0hw (Phase 4a): the formation of an environment effect, one line per batch with its squares, one per phase end, and after the
   cast the squares the game really changed. tools/check_effect_formation.sh reads them. */
int gFormCx = -1, gFormCy, gFormR;
rID gFormTerrain;
Player *gSweepPl = NULL; rID gSweepTerr = 0; int gSweepStep = 0;
std::vector<int> gWallDrawnX, gWallDrawnY;   /* a barrier's squares the formation has drawn so far (inc-jw0hw Phase 6b) */
int gWallFormStep = 0;
void WallFormRead(bool all);
void FormHook(int order, int batch, int n, const int16 *xs, const int16 *ys, Glyph first, int drawn, int16 cx, int16 cy, int16 radius, rID terrain) {
    if (gSweepTerr && terrain == gSweepTerr) {
        /* The hook runs before the batch's own paint: the paint of the batches before it has run, so read those squares now. */
        if (batch == 0) { gWallDrawnX.clear(); gWallDrawnY.clear(); gWallFormStep = 0; }
        if (batch >= 0 || batch == -1) WallFormRead(batch == -1);
        if (batch >= 0 && drawn == n)
            for (int i = 0; i < n; ++i) { gWallDrawnX.push_back(xs[i]); gWallDrawnY.push_back(ys[i]); }
    }
    gFormCx = cx; gFormCy = cy; gFormR = radius; gFormTerrain = terrain;
    if (batch == -3) {   /* one step of a flying caltrop: n is which caltrop, drawn its step, xs/ys where it shows */
        Error("REEL_FORMATION_FLY %s order %d id %d step %d at %d,%d glyph %d", gClip, order, n, drawn, (int)xs[0], (int)ys[0], (int)GLYPH_ID_VALUE(first));
        return;
    }
    if (batch < 0) {
        Error("REEL_FORMATION_END %s order %d phase %d total %d shown %d at %d,%d radius %d", gClip, order, batch, n, drawn, (int)cx, (int)cy, (int)radius);
        return;
    }
    char sq[1300]; size_t at = 0;
    sq[0] = 0;
    for (int i = 0; i < n && at < sizeof(sq) - 16; ++i)
        at += (size_t)snprintf(sq + at, sizeof(sq) - at, "%s%d,%d", i ? ";" : "", (int)xs[i], (int)ys[i]);
    Error("REEL_FORMATION %s order %d batch %d n %d drawn %d glyph %d fore %d at %d,%d radius %d sq %s", gClip, order, batch, n, drawn,
          (int)GLYPH_ID_VALUE(first), (int)GLYPH_FORE_VALUE(first), (int)cx, (int)cy, (int)radius, sq);
}
void GlobeGlyph(int16 x, int16 y, Glyph, Glyph now) {
    Error("REEL_GLOBEGLYPH %s %d,%d fore %d", gClip, (int)x, (int)y, (int)GLYPH_FORE_VALUE(now));
}
/* inc-jw0hw (Phase 5): the motion the SDL build would draw. A start logs the squares, each with what stands there (C a creature,
   I an item on the floor, N neither: a floor or wall square), then the pick of each square on 12 frames (400 ms), one line per
   frame: i:dx,dy,flipX,flipY. A stop logs the end. tools/check_effect_motion.sh reads these. */
void MotionLog(int start, int n, const int16 *xs, const int16 *ys, const uint8 *modes) {
    Player *pl = theGame->GetPlayer(0);
    Map *mp = pl ? pl->m : NULL;
    if (!start) { Error("REEL_MOTION_END %s n %d", gClip, n); return; }
    std::string sq;
    for (int i = 0; i < n; ++i) {
        char kind = 'N';
        if (mp && mp->FCreatureAt(xs[i], ys[i])) kind = 'C';
        else if (mp) for (Thing *t = mp->FirstAt(xs[i], ys[i]); t; t = mp->NextAt(xs[i], ys[i]))
            if (t->isItem()) { kind = 'I'; break; }
        char b[40];
        snprintf(b, sizeof b, "%s%d,%d,%c,%d", i ? ";" : "", (int)xs[i], (int)ys[i], kind, (int)modes[i]);
        sq += b;
    }
    Error("REEL_MOTION_START %s n %d sq %s", gClip, n, sq.c_str());
    for (int f = 0; f < 12; ++f) {
        std::string line;
        for (int i = 0; i < n; ++i) {
            const MotionXf xf = MotionPick((uint32)f, i);
            char b[48];
            snprintf(b, sizeof b, "%s%d:%d,%d,%d,%d", i ? ";" : "", i, xf.dx, xf.dy, xf.flipX ? 1 : 0, xf.flipY ? 1 : 0);
            line += b;
        }
        Error("REEL_MOTION_FRAME %s f %d %s", gClip, f, line.c_str());
    }
}
/* The cell transform, on a synthetic 8 x 16 cell: every shift of 1 to 3 pixels in the eight directions, and the three mirrors with no shift.
   Each result must hold the cell's own pixels moved (or mirrored) and the background in the strip the move uncovers, and nothing may be
   written outside the cell. bad counts the pixels that are wrong. */
void MotionSelfTest() {
    const int cw = 8, ch = 16, BG = 0x00ABCDEF;
    uint32 buf[3 * cw * ch];   /* dst sits in the middle third; the outer thirds are guards */
    uint32 src[cw * ch];
    for (int i = 0; i < cw * ch; ++i) src[i] = 0x01000000u + (uint32)i;
    int bad = 0, cases = 0, guardBad = 0;
    static const int DX[8] = { 1, 1, 0, -1, -1, -1, 0, 1 }, DY[8] = { 0, 1, 1, 1, 0, -1, -1, -1 };
    for (int mag = 1; mag <= 3; ++mag)
        for (int d = 0; d < 9; ++d) {
            MotionXf xf = { d < 8 ? DX[d] * mag : 0, d < 8 ? DY[d] * mag : 0, d == 8 && mag == 2, d == 8 && mag == 3 };
            for (int g = 0; g < 3 * cw * ch; ++g) buf[g] = 0xDEADBEEFu;
            MotionTransform(src, buf + cw * ch, cw, ch, xf, (uint32)BG);
            ++cases;
            for (int g = 0; g < cw * ch; ++g) if (buf[g] != 0xDEADBEEFu || buf[2 * cw * ch + g] != 0xDEADBEEFu) ++guardBad;
            for (int y = 0; y < ch; ++y)
                for (int x = 0; x < cw; ++x) {
                    int sx = x - xf.dx, sy = y - xf.dy;
                    const bool out = sx < 0 || sx >= cw || sy < 0 || sy >= ch;
                    if (!out) { if (xf.flipX) sx = cw - 1 - sx; if (xf.flipY) sy = ch - 1 - sy; }
                    const uint32 want = out ? (uint32)BG : src[sy * cw + sx];
                    if (buf[cw * ch + y * cw + x] != want) ++bad;
                }
        }
    Error("REEL_MOTION_XFORM cases %d bad %d guard-bad %d", cases, bad, guardBad);
}
/* A spore's glyph, and the direction of its flight. */
void SporeLog(int id, int step, int16 x, int16 y, int16 dx, int16 dy, Glyph g) {
    Error("REEL_SPORE %s flight %d step %d at %d,%d dir %d,%d glyph %d", gClip, id, step, (int)x, (int)y, (int)dx, (int)dy, (int)GLYPH_ID_VALUE(g));
}

/* inc-jw0hw: the Skull Trap clip's probe of the script light, on the trap's square. */
int gSkX, gSkY, gSkTicks, gSkLitTicks, gSkEnds;
float gSkFirst, gSkLast;
void SkTick(float clk) {
    if (!gSkTicks++) gSkFirst = clk;
    gSkLast = clk;
    if (LightLitAt((int16)gSkX, (int16)gSkY)) ++gSkLitTicks;
}
void SkEnd() { ++gSkEnds; }

bool InBlock(int x, int y) { return x >= RX0 && x <= RX1 && y >= RY0 && y <= RY1; }

/* inc-jw0hw (Phase 6b): each step of a barrier's sweep, after the game's own paint of that step, count the wall squares and those the light map lights. */
void WallFormRead(bool all) {
    if (gWallDrawnX.empty()) return;
    int lit = 0;
    for (size_t k = 0; k < gWallDrawnX.size(); ++k)
        if (LightLitAt((int16)gWallDrawnX[k], (int16)gWallDrawnY[k])) ++lit;
    Error("REEL_WALLFORM %s step %d drawn %d lit %d", all ? "end" : "batch", ++gWallFormStep, (int)gWallDrawnX.size(), lit);
}
void SweepHook() {
    Map *mp = gSweepPl ? gSweepPl->m : NULL;
    if (!mp || !gSweepTerr) return;
    int n = 0, lit = 0;   /* no repaint here: it reads the light map the game's own paint of this step left */
    for (int y = RY0; y <= RY1; ++y)
        for (int x = RX0; x <= RX1; ++x)
            if (mp->TerrainAt(x, y) == gSweepTerr) { ++n; if (LightLitAt((int16)x, (int16)y)) ++lit; }
    Error("REEL_WALLSWEEP step %d squares %d lit %d standing %d", ++gSweepStep, n, lit, StandingWallCount());
}

/* inc-jw0hw: the player's statuses at the start of the reel. Every clip begins from exactly these: BuildRoom removes
   any other status (poison, paralysis, prone, a spell's aura) an earlier clip left, and puts the clock and hunger back. */
struct StKey { int nat, src, eid; };
std::vector<StKey> gBaseStati;
uint32 gTurn0 = 0; int32 gHunger0 = -1;
void SnapshotPlayer(Player *pl) {
    gBaseStati.clear();
    StatiIter(pl)
        StKey k = { (int)S->Nature, (int)S->Source, (int)S->eID };
        gBaseStati.push_back(k);
    StatiIterEnd(pl)
    gTurn0 = theGame->Turn;
    gHunger0 = pl->HasStati(HUNGER) ? (int32)pl->GetStatiDur(HUNGER) : -1;
}
int ResetPlayerStati(Player *pl) {
    std::vector<StKey> left = gBaseStati;
    int removed = 0;
    StatiIter(pl)
        bool keep = false;
        for (size_t i = 0; i < left.size() && !keep; ++i)
            if (left[i].nat == (int)S->Nature && left[i].src == (int)S->Source && left[i].eid == (int)S->eID) {
                left.erase(left.begin() + i);
                keep = true;
            }
        if (!keep) { ++removed; StatiIter_RemoveCurrent(pl) }
    StatiIterEnd(pl)
    if (theGame->Turn != gTurn0) Error("REEL_CLOCK restored %d -> %d", (int)theGame->Turn, (int)gTurn0);
    theGame->Turn = gTurn0;   /* Heroes' Feast spends an hour (Player::SpendHours) */
    if (gHunger0 >= 0 && pl->HasStati(HUNGER)) pl->SetStatiDur(HUNGER, -1, NULL, gHunger0);
    return removed;
}

/* The monster whose natural attack delivers this Poison effect (its `Poison:` attribute, lib/mon1.irh:1562). */
rID VenomMonster(rID eff) {
    Module *mod = theGame->Modules[0];
    for (int i = 0; i < mod->szMon; ++i) {
        const rID mid = mod->MonsterID(i);
        for (rID x = TMON(mid)->FirstRes(AN_POISON); x; x = TMON(mid)->NextRes(AN_POISON))
            if (x == eff) return mid;
    }
    return 0;
}

/* A trap effect fires only through a Trap object: its source is AI_TRAP (the marker MakeLev.cpp:2399 picks level traps by).
   The Skull Trap has its own path above and is left out. */
bool IsTrapClip(rID eff) {
    return TEFF(eff)->HasSource(AI_TRAP) && eff != FIND("skull trap;trap");
}

/* Writes terrain at (x, y) and remembers it, as the Pyrotechnics clip does for its torches. */
void PutTerrain(Map *mp, rID terr, int x, int y) {
    Rect rect(0, 0, mp->SizeX() - 1, mp->SizeY() - 1);
    mp->WriteAt(rect, x, y, terr, mp->RegionAt(x, y), PRIO_MAX, true);
    mp->At(x, y).Memory = (uint32)mp->At(x, y).Glyph;
}

void BuildRoom(Map *mp, Player *pl, rID floor, rID wall, bool bright) {
    Thing *obj; int index;
    StandingWallStopAll();   /* a wall light of the last clip ends with its wall */
    for (;;) {
        Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != pl) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    for (int i = 0; mp->Fields[i]; ) mp->RemoveField(mp->Fields[i]);
    /* inc-jw0hw: a clip that casts on the caster leaves its statuses behind (AFRAID stops the next clip's touch
       strike, Magic.cpp:1248 aims at the caster). Clear every status an effect put on the player. */
    StatiIter(pl)
        if (S->eID && RES(S->eID)->Type == T_TEFFECT && S->Nature != HELD_MANA)
            StatiIter_RemoveCurrent(pl)
    StatiIterEnd(pl)
    const int cleaned = ResetPlayerStati(pl);
    if (cleaned) Error("REEL_RESET removed %d leftover statuses", cleaned);
    pl->PlaceAt(mp, PX, PY);
    const rID region = mp->RegionAt(pl->x, pl->y);
    Rect rect(0, 0, mp->SizeX() - 1, mp->SizeY() - 1);
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x) {
            mp->WriteAt(rect, x, y, InBlock(x, y) ? floor : wall, region, PRIO_MAX, true);
            mp->At(x, y).Lit = false;
            mp->At(x, y).Bright = false;
            mp->At(x, y).Dark = false;
        }
    for (int y = PY - 2; y <= PY + 2; ++y)
        mp->WriteAt(rect, STUBX, y, wall, region, PRIO_MAX, true);
    /* inc-jw0hw: a lit room, as Map::calcLight (MakeLev.cpp:167) leaves one: Lit set on every floor and wall square of it.
       bright (an effect with no light of its own, table glow UNLIT) sets Lit and Bright on them: LIGHT_LEGACY_BRIGHT (160)
       ambient, so the floor reads clearly. Otherwise (a LIT effect) the room is DARK, Lit and Bright both false, no ambient:
       the per-channel max in ComposeFrame would hide a LIT effect's own light under 160. A bright room is seen whole, so an
       aura or a spell with no light of its own draws on squares in view. The room and its walls are also remembered. */
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x) {
            const bool near = x >= RX0 - 1 && x <= RX1 + 1 && y >= RY0 - 1 && y <= RY1 + 1;
            mp->At(x, y).Memory = near ? (uint32)mp->At(x, y).Glyph : 0;
            mp->At(x, y).Lit = near && bright;
            mp->At(x, y).Bright = near && bright;
        }
    pl->CalcVision();
    int seen = 0, total = 0;
    for (int y = RY0; y <= RY1; ++y)
        for (int x = RX0; x <= RX1; ++x) {
            ++total;
            if (mp->At(x, y).Visibility & VI_VISIBLE) ++seen;
        }
    Error("REEL_ROOMSEEN %d of %d room squares are visible to the player", seen, total);
}

/* inc-jw0hw: the view every frame of every clip uses. TextTerm::AdjustMap (Term.cpp:1061-1107) reads the
   player's old screen position (rx, ry) BEFORE it recenters, then adds a scroll of 2*lx or 2*ly on that stale
   value when the old position lay near an edge. One AdjustMap(CX, PY, true) can therefore land off by 10 rows
   (seen: origin y -12, then -2 on the next call), which is a room that moves on screen. Repeat it until the
   origin stops changing; the result is a fixpoint, and the player's square lies inside the no-scroll band of
   it, so the non-newmap AdjustMap calls (RefreshMap: Term.h:760, Wlibtcod.cpp:1427, Main.cpp:883) leave it. */
int16 gViewX, gViewY;
void Refresh(Player *pl) {
    for (int i = 0; i < 6; ++i) {
        const int16 ox = pl->MyTerm->XOff, oy = pl->MyTerm->YOff;
        pl->MyTerm->AdjustMap(CX, PY, true);   /* the room fills the frame, not the player */
        if (pl->MyTerm->XOff == ox && pl->MyTerm->YOff == oy && i) break;
    }
    gViewX = pl->MyTerm->XOff; gViewY = pl->MyTerm->YOff;
    pl->UpdateMap = 1;
    pl->MyTerm->ShowMap();
}

/* inc-jw0hw: the map window's origin, to show that a clip keeps the view Refresh() sets. */
void ViewLog(Player *pl, const char *nm, const char *when) {
    /* The map window as a pixel rectangle of every recorded frame; tools/render_effect_reel.sh hashes only this area. */
    int px0, py0, cw, ch, px1, py1, cw1, ch1;
    if (TermCellPixel(pl->MyTerm->XOff, pl->MyTerm->YOff, px0, py0, cw, ch) &&
        TermCellPixel((int16)(pl->MyTerm->XOff + pl->MyTerm->MSizeX() - 1), (int16)(pl->MyTerm->YOff + pl->MyTerm->MSizeY() - 1), px1, py1, cw1, ch1))
        Error("REEL_MAPRECT %d %d %d %d", px0, py0, px1 + cw1 - px0, py1 + ch1 - py0);
    Error("REEL_VIEW %s %s %s origin %d,%d window %dx%d map %dx%d center-option %d", nm, when, pl->MyTerm->XOff == gViewX && pl->MyTerm->YOff == gViewY ? "pinned" : "MOVED", (int)pl->MyTerm->XOff, (int)pl->MyTerm->YOff,
          (int)pl->MyTerm->MSizeX(), (int)pl->MyTerm->MSizeY(), (int)pl->m->SizeX(), (int)pl->m->SizeY(), (int)pl->Opt(OPT_CENTER_MAP));
}

std::string Sanitize(const char *s) {
    std::string r;
    for (; *s; ++s) {
        const char c = (char)tolower((unsigned char)*s);
        if (isalnum((unsigned char)c)) r += c;
        else if (!r.empty() && r[r.size() - 1] != '-') r += '-';
    }
    while (!r.empty() && r[r.size() - 1] == '-') r.erase(r.size() - 1);
    return r.empty() ? std::string("x") : r;
}

bool IsReelKind(TEffect &te, const char **kind) {
    const EffectValues &ef = te.ef;
    if (ef.eval == EA_BLAST) { *kind = "blast"; return true; }
    if (ef.aval == AR_GLOBE) { *kind = "globe"; return true; }
    if ((ef.aval == AR_FIELD || ef.aval == AR_MFIELD) &&
        ((uint32)ef.rval & (FI_MODIFIER | FI_BLOCKER))) { *kind = "aura"; return true; }
    /* inc-jw0hw (Phase 4b): a wall (AR_BARRIER): its line forms in an order. */
    if (ef.aval == AR_BARRIER) { *kind = "barrier"; return true; }
    /* inc-jw0hw: a beam or bolt that draws the color pattern. */
    if (te.HasFlag(EF_COLOR_PATTERN)) { *kind = "pattern"; return true; }
    return false;
}

/* inc-jw0hw: the class name the light-table check compares: a COL_* row by its
   short name, a plain palette color as cval:<NAME>, "random" for none. */
const char *LightClass(int16 colour, char *buf, size_t n) {
    static const char *rows[] = { "fire", "cold", "magic", "necro", "elec", "rainbow", "light",
        "poison", "acid", "disint", "petri", "poly", "sonic", "silvery", "crimson", "darkred",
        "sunyellow", "azure" };
    static const char *pal[] = { "BLACK", "BLUE", "GREEN", "CYAN", "RED", "PURPLE", "BROWN", "GREY",
        "SHADOW", "AZURE", "EMERALD", "SKYBLUE", "PINK", "MAGENTA", "YELLOW", "WHITE" };
    if (colour >= COL_FIRE && colour <= COL_AZURE) return rows[colour - COL_FIRE];
    if (colour > 0 && colour < 16) { snprintf(buf, n, "cval:%s", pal[colour]); return buf; }
    return "random";
}

const char *FormWord(char f) { return f == 's' ? "smoke" : f == 'f' ? "fireworks" : "explosion"; }
rID FormEffect(char f) {
    return FIND(f == 's' ? "Pyrotechnics;smoke" : f == 'f' ? "Pyrotechnics;flash" : "Pyrotechnics;blast");
}

bool WantedByFilter(const char *only, const char *name) {
    if (!only || !*only) return true;
    const char *p = only;
    while (*p) {
        const char *q = strchr(p, ',');
        const size_t n = q ? (size_t)(q - p) : strlen(p);
        if (strlen(name) == n && strncasecmp(p, name, n) == 0) return true;
        if (!q) break;
        p = q + 1;
    }
    return false;
}

/* inc-jw0hw: one table row of tools/fixtures/effect-light-table.tsv, keyed by the effect's declared name: glow (column 2,
   LIT or UNLIT) and shows_nothing (column 4). The path is INCURSION_LIGHT_TABLE, the one the render script reads; the
   scripts pass an absolute path because the game does not run from the root. */
struct TableRow { std::string key, glow; bool nothing; };
std::vector<TableRow> ReadTable() {
    std::vector<TableRow> rows;
    const char *path = getenv("INCURSION_LIGHT_TABLE");
    FILE *fh = fopen(path && *path ? path : "tools/fixtures/effect-light-table.tsv", "r");
    if (!fh) return rows;
    char line[1024];
    while (fgets(line, sizeof line, fh)) {
        std::string ln(line);
        while (!ln.empty() && (ln[ln.size() - 1] == '\n' || ln[ln.size() - 1] == '\r')) ln.erase(ln.size() - 1);
        if (ln.empty() || ln[0] == '#') continue;
        std::vector<std::string> f;
        size_t from = 0, tab;
        while ((tab = ln.find('\t', from)) != std::string::npos) { f.push_back(ln.substr(from, tab - from)); from = tab + 1; }
        f.push_back(ln.substr(from));
        if (f.size() < 4) continue;
        TableRow r; r.key = f[0]; r.glow = f[1]; r.nothing = f[3] == "yes";
        rows.push_back(r);
    }
    fclose(fh);
    return rows;
}


/* inc-jw0hw (Phase 5c): the second run of tools/check_effect_motion.sh stage W3. The first run saved the level with a Wall of Fire
   standing (INCURSION_WALL_SAVE below); this run LOADED that save, so the map's wall terrain came from the file and no wall light
   was ever started. Log the wall squares, the standing lights and the lit squares before and after the first repaint. */
void WallLoadProbe(Player *pl) {
    Map *mp = pl->m;
    const rID fw = FIND("Wall of Fire");
    if (!mp || !fw) { Error("REEL_ERROR WALLLOAD no map or no Wall of Fire"); return; }
    const rID terr = TEFF(fw)->ef.rval;
    std::vector<int> wx, wy;
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x)
            if (mp->TerrainAt(x, y) == terr) { wx.push_back(x); wy.push_back(y); }
    Error("REEL_WALLLOAD before-repaint squares %d standing %d", (int)wx.size(), StandingWallCount());
    pl->UpdateMap = 1;
    pl->MyTerm->ShowMap();
    int lit = 0;
    for (size_t k = 0; k < wx.size(); ++k) if (LightLitAt((int16)wx[k], (int16)wy[k])) ++lit;
    Error("REEL_WALLLOAD after-repaint squares %d lit %d standing %d", (int)wx.size(), lit, StandingWallCount());
}

/* inc-jw0hw (Phase 6b): INCURSION_FIERY_ROOM generates dungeon levels until one holds the region "Fiery Prison" (a room furnished with
   the curtain of flame by FU_CENTER_CIRCLE_LARGE), puts the player beside the curtain with no light of his own, repaints as the game
   does, and logs how many curtain squares the player sees and how many of them are lit. */
void FieryRoomProbe(Player *pl) {
    const rID reg = FIND("Fiery Prison"), curtain = FIND("curtain of flame");
    rID dID = pl->m->dID;
    if (!dID) dID = theGame->DungeonID[1];
    Map *keep = NULL; int tries = 0;
    for (; tries < 800 && !keep; ++tries) {
        Map *m = new Map();
        m->Generate(dID, 3 + tries % 5, pl->m, (int8)pl->GetAttr(A_LUC));
        for (int y = 0; y < m->SizeY() && !keep; ++y)
            for (int x = 0; x < m->SizeX() && !keep; ++x)
                if (m->RegionAt(x, y) == reg) keep = m;
        if (!keep) delete m;
    }
    if (!keep) { Error("FIERY_ROOM none in %d levels", tries); return; }
    int n = 0;
    std::vector<int> cx, cy;
    for (int y = 0; y < keep->SizeY(); ++y)
        for (int x = 0; x < keep->SizeX(); ++x)
            if (keep->TerrainAt(x, y) == curtain) { ++n; cx.push_back(x); cy.push_back(y); }
    pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
    int px = -1, py = -1;
    for (size_t k = 0; k < cx.size() && px < 0; ++k)
        for (int d = 0; d < 8 && px < 0; ++d) {
            static const int DXX[8] = { 1, 1, 0, -1, -1, -1, 0, 1 }, DYY[8] = { 0, 1, 1, 1, 0, -1, -1, -1 };
            const int x = cx[k] + DXX[d] * 1, y = cy[k] + DYY[d];
            if (keep->InBounds(x, y) && !keep->SolidAt(x, y) && keep->TerrainAt(x, y) != curtain && !keep->FCreatureAt(x, y)) { px = x; py = y; }
        }
    if (px < 0) { Error("FIERY_ROOM no square beside the curtain"); return; }
    pl->PlaceAt(keep, px, py);
    Map *mp = pl->m;
    Error("FIERY_ROOM levels %d depth %d region %s curtain-squares %d player %d,%d", tries, (int)mp->Depth, NAME(reg), n, px, py);
    pl->CalcVision();
    pl->UpdateMap = 1;
    pl->MyTerm->ShowMap();
    int seen = 0, lit = 0;
    for (size_t k = 0; k < cx.size(); ++k) {
        if (!(mp->At(cx[k], cy[k]).Visibility & VI_VISIBLE)) continue;
        ++seen;
        if (LightLitAt((int16)cx[k], (int16)cy[k])) ++lit;
    }
    Error("FIERY_ROOM seen %d lit %d standing %d", seen, lit, StandingWallCount());
}

/* inc-as123 (Phase 4): the weapon clips. A held light, a hit flash or a flight light does not come from an effect, so the effect list
   cannot name it; this list is the reel's own, each clip keyed "Weapon <held|hit|flight> <what>" with a row in the light table. The
   weapon's light is whatever the engine decides (LightHeldColour, LightMissileOf, WeaponHitColour); the clip only sets the scene. */
// no-family
enum { WM_HELD, WM_HIT, WM_FLIGHT };
enum { WK_ANY, WK_GOOD, WK_EVIL, WK_LAWFUL, WK_CHAOTIC, WK_NEUTRAL, WK_UNDEAD };
// end no-family
struct WClip {
    const char *key; int mode;
    const char *item; int q, plus; const char *eff;   /* held: the weapon; hit: a long sword with quality q; flight: the missile with quality q */
    bool torch, monster, nls;                         /* held: a torch too; a hobgoblin holds it; the activation status stands */
    bool burst, crit; int ak, vk, saveRoll, dtype;    /* hit: burst quality, crit, actor and victim kind, forced save roll, extra damage type */
    const char *launcher; int lq; bool seeds;         /* flight: the launcher and its quality; fire seeds (no light in flight, a wide flash) */
};
WClip WHeld(const char *key, const char *item, int q, int plus, const char *eff, bool torch = false, bool monster = false, bool nls = false) {
    WClip c = { key, WM_HELD, item, q, plus, eff, torch, monster, nls, false, false, 0, 0, 0, 0, NULL, -1, false };
    return c;
}
WClip WHit(const char *key, int q, bool burst, bool crit, int ak, int vk, int save, int dtype) {
    WClip c = { key, WM_HIT, "long sword", q, -1, NULL, false, false, false, burst, crit, ak, vk, save, dtype, NULL, -1, false };
    return c;
}
WClip WFlight(const char *key, const char *missile, int mq, const char *launcher, bool seeds = false) {
    WClip c = { key, WM_FLIGHT, missile, mq, -1, NULL, false, false, false, false, false, 0, 0, 0, seeds ? AD_FIRE : 0, launcher, -1, seeds };
    return c;
}
std::vector<WClip> WeaponClips() {
    std::vector<WClip> v;
    v.push_back(WHeld("Weapon held flaming long sword", "long sword", WQ_FLAMING, 0, NULL));
    v.push_back(WHeld("Weapon held flame blade", "flame blade;weapon", -1, -1, NULL));
    v.push_back(WHeld("Weapon held produced flame", "produced flame", -1, -1, NULL));
    v.push_back(WHeld("Weapon held glowing long sword", "long sword", WQ_GLOWING, 2, NULL));
    v.push_back(WHeld("Weapon held Sunblade", "short sword", -1, -1, "Sunblade"));
    v.push_back(WHeld("Weapon held Quickblade", "rapier", -1, -1, "Quickblade"));
    v.push_back(WHeld("Weapon held Sword of the Planes", "long sword", -1, -1, "Sword of the Planes"));
    v.push_back(WHeld("Weapon held Nine Lives Stealer", "long sword", -1, -1, "Nine Lives Stealer", false, true, true));   /* an evil weapon: a hobgoblin holds it, as the priest would lose levels */
    v.push_back(WHeld("Weapon held torch and Sunblade", "short sword", -1, -1, "Sunblade", true));
    v.push_back(WHeld("Weapon held monster flaming sword", "long sword", WQ_FLAMING, 0, NULL, false, true));
    v.push_back(WHit("Weapon hit flaming", WQ_FLAMING, false, false, WK_ANY, WK_ANY, 0, AD_FIRE));
    v.push_back(WHit("Weapon hit frost", WQ_FROST, false, false, WK_ANY, WK_ANY, 0, AD_COLD));
    v.push_back(WHit("Weapon hit shocking", WQ_SHOCKING, false, false, WK_ANY, WK_ANY, 0, AD_ELEC));
    v.push_back(WHit("Weapon hit soul-drinking", WQ_SOULDRINK, false, false, WK_ANY, WK_ANY, 0, AD_NECR));
    v.push_back(WHit("Weapon hit flaming burst critical", WQ_FLAMING, true, true, WK_ANY, WK_ANY, 0, AD_FIRE));
    v.push_back(WHit("Weapon hit holy", WQ_HOLY, false, false, WK_GOOD, WK_EVIL, 0, AD_HOLY));
    v.push_back(WHit("Weapon hit lawful", WQ_LAWFUL, false, false, WK_LAWFUL, WK_CHAOTIC, 0, AD_LAWF));
    v.push_back(WHit("Weapon hit chaotic", WQ_CHAOTIC, false, false, WK_CHAOTIC, WK_LAWFUL, 0, AD_CHAO));
    v.push_back(WHit("Weapon hit balance", WQ_BALANCE, false, false, WK_NEUTRAL, WK_NEUTRAL, 0, AD_MAGC));
    v.push_back(WHit("Weapon hit unholy", WQ_UNHOLY, false, false, WK_EVIL, WK_GOOD, 0, AD_EVIL));
    v.push_back(WHit("Weapon hit disruption kill", WQ_DISRUPTION, false, false, WK_ANY, WK_UNDEAD, 1, AD_HOLY));   /* its flash is holy white */
    v.push_back(WFlight("Weapon flight flaming dagger", "dagger", WQ_FLAMING, NULL));
    v.push_back(WFlight("Weapon flight flaming arrow", "sheaf arrow", WQ_FLAMING, "short bow"));
    v.push_back(WFlight("Weapon flight fire seeds", "fire seeds", -1, NULL, true));
    v.push_back(WFlight("Weapon flight produced flame", "produced flame", -1, NULL));
    return v;
}

/* One weapon item the clip names, made as the game makes it: its effect (if any) builds it, then plus and quality are set directly. */
Item *WMake(Creature *src, const char *base, int q, int plus, const char *eff) {
    Item *it = Item::Create(FIND(base));
    if (!it) { Error("REEL_ERROR weapon item %s is missing", base); return NULL; }
    if (eff) {
        it->eID = FIND(eff);
        if (!it->eID) { Error("REEL_ERROR weapon effect %s is missing", eff); return NULL; }
        it->Initialize(false);
    }
    if (plus >= 0) it->Plus = (int8)plus;
    if (q >= 0) it->GainPermStati(EXTRA_QUALITY, src, SS_MISC, (int16)q, 0, 0);
    return it;
}

bool WWield(Creature *c, Item *it, int slot) {
    const bool wasPlay = theGame->PlayMode;
    if (!c->isPlayer()) {   /* a monster's slot is read off its inventory list; out of play, an opposed alignment drains no levels */
        theGame->PlayMode = false;
        it->Remove(false);
        c->GainItem(it, true);
    }
    Silence = 1;
    isExchange = true;
    if (c->InSlot(slot) != it) ThrowVal(EV_WIELD, slot, c, NULL, it);
    isExchange = false;
    Silence = 0;
    theGame->PlayMode = wasPlay;
    c->CalcValues();
    return c->InSlot(slot) == it;
}

void WStrip(Creature *c, int slot) {
    Item *it = c->InSlot(slot);
    if (!it) return;
    EventInfo t; t.Clear(); t.EActor = c; t.EItem = it; t.EParam = slot;
    Silence = 1;
    c->TakeOff(t);
    Silence = 0;
    it->Remove(true);
}

/* The player's own sight: whatever the weapon gives, and no infravision or shadow sight. */
void WRefresh(Player *pl) {
    pl->CalcValues();
    pl->InfraRange = pl->ShadowRange = 0;
    pl->CalcVision();
    Refresh(pl);
}

int WLitCount(Map *mp) {
    int n = 0;
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x)
            if (LightLitAt((int16)x, (int16)y)) ++n;
    return n;
}

bool WKindFits(Creature *c, int kind) {
    switch (kind) {
        case WK_GOOD: return c->isMType(MA_GOOD);
        case WK_EVIL: return c->isMType(MA_EVIL);
        case WK_LAWFUL: return c->isMType(MA_LAWFUL);
        case WK_CHAOTIC: return c->isMType(MA_CHAOTIC);
        case WK_NEUTRAL: return c->isMType(MA_NEUTRAL) && !c->isMType(MA_GOOD) && !c->isMType(MA_EVIL) && !c->isMType(MA_LAWFUL) && !c->isMType(MA_CHAOTIC);
        case WK_UNDEAD: return c->isMType(MA_UNDEAD);
    }
    return true;
}

/* The first generated monster of the kind that gives no light of its own where it stands, placed at (x, y); NULL when none. */
Monster *WSpawn(Map *mp, Player *pl, int kind, int x, int y) {
    Module *mod = theGame->Modules[0];
    int tries = 0;
    for (int idx = 0; idx < mod->szMon && tries < 80; ++idx) {
        TMonster &t = mod->QMon[idx];
        if (t.HasFlag(M_NOGEN)) continue;
        Monster *m = new Monster(mod->MonsterID((uint16)idx));
        m->mHP = m->cHP = 500;
        m->CalcValues();
        if (!WKindFits(m, kind)) { delete m; continue; }
        ++tries;
        m->PlaceAt(mp, x, y, true);
        Refresh(pl);
        if (WLitCount(mp) == 0) return m;
        m->Remove(true);
    }
    return NULL;
}

/* The light class of a color the engine decided: a COL_* row's name, or rgb:<r>,<g>,<b> when no row has it. */
const char *WClassOfRGB(LightRGB c, char *buf, size_t n) {
    for (int col = COL_FIRE; col <= COL_AZURE; ++col) {
        const LightRGB r = LightEffectColour((int16)col);
        if (r.r == c.r && r.g == c.g && r.b == c.b) return LightClass((int16)col, buf, n);
    }
    snprintf(buf, n, "rgb:%d,%d,%d", (int)c.r, (int)c.g, (int)c.b);
    return buf;
}

/* The engine's light decision for a weapon clip: the light class, NULL when the clip lights nothing. The held and flight light come from LightHeldColour and
   LightMissileOf on the clip's own item; a hit flash from WeaponHitColour on the clip's damage type. */
const char *WClass(Player *pl, const WClip &w, char *buf, size_t n) {
    LightRGB c;
    if (w.mode == WM_HIT || w.seeds) {
        const int16 col = WeaponHitColour((int16)w.dtype);
        return col ? LightClass(col, buf, n) : NULL;
    }
    Item *it = WMake(pl, w.item, w.q, w.plus, w.eff);
    if (!it) return NULL;
    bool lit;
    if (w.mode == WM_HELD) {
        if (w.nls) pl->GainPermStati(EFF_FLAG1, it, SS_ENCH, 0, 0, FIND("Nine Lives Stealer"), 7);
        lit = LightHeldColour(pl, it, c);
        if (w.nls) pl->RemoveEffStati(FIND("Nine Lives Stealer"));
    } else {
        Item *bow = w.launcher ? WMake(pl, w.launcher, w.lq, -1, NULL) : NULL;
        int16 col;
        lit = LightMissileOf(it, bow, col, c);
        if (bow) bow->Remove(true);
    }
    it->Remove(true);
    return lit ? WClassOfRGB(c, buf, n) : NULL;
}

int gWFlight;
void WFlightHook(int kind, int16, int16, Glyph) { if (kind == ES_FLIGHT) ++gWFlight; }

void WeaponTableList(Player *pl, int &shown) {
    const std::vector<WClip> clips = WeaponClips();
    for (size_t i = 0; i < clips.size(); ++i) {
        char cls[40];
        const char *name = WClass(pl, clips[i], cls, sizeof cls);
        Error("LIGHT %s\t%s\t%s", clips[i].key, name ? "LIT" : "UNLIT", name ? name : "-");
        ++shown;
    }
}

/* One scene per weapon clip, in a dark room, the player stripped of light and weapons. Held: the holder (the player, or a hobgoblin) walks 8 squares
   east, so the light moves over the floor. Hit: the weapon's quality strikes a victim, as Weapon::QualityDmgSingle does for a hit. Flight: the
   player throws or fires at a victim 10 squares east, the attack roll forced to a hit. */
void WeaponReel(Player *pl, Map *mp, rID floor, rID wall, const char *only, const std::vector<TableRow> &table, int &count) {
    const std::vector<WClip> clips = WeaponClips();
    for (size_t n = 0; n < clips.size(); ++n) {
        const WClip &w = clips[n];
        if (!WantedByFilter(only, w.key) && !WantedByFilter(only, "Weapons")) continue;
        const TableRow *row = NULL;
        for (size_t k = 0; k < table.size(); ++k)
            if (table[k].key == w.key) row = &table[k];
        if (row && row->nothing) { Error("REEL_SKIP %s shows nothing by the table", w.key); continue; }
        const bool bright = !row || row->glow != "LIT";
        if (!row) Error("REEL_ROOM_NOROW %s has no table row; room treated as UNLIT", w.key);
        BuildRoom(mp, pl, floor, wall, bright);
        Error("REEL_ROOM %d %s %s", count + 1, w.key, bright ? "bright" : "dark");
        LightFlashClearAll();
        WStrip(pl, SL_LIGHT); WStrip(pl, SL_WEAPON); WStrip(pl, SL_READY);
        pl->mHP = pl->cHP = 30000;
        Monster *hold = NULL, *a = NULL, *v = NULL;
        Item *it = NULL, *bow = NULL;
        int hx = PX;
        if (w.mode == WM_HELD) {
            if (w.monster) {
                hold = new Monster(FIND("hobgoblin"));
                hold->mHP = hold->cHP = 500;
                hold->CalcValues();
                hx = PX + 3;
                hold->PlaceAt(mp, hx, PY, true);
            }
            Creature *holder = hold ? (Creature *)hold : (Creature *)pl;
            it = WMake(holder, w.item, w.q, w.plus, w.eff);
            if (!it || !WWield(holder, it, SL_WEAPON)) { Error("REEL_ERROR weapon clip %s: the weapon did not go into the hand", w.key); continue; }
            if (w.torch) {
                Item *tr = WMake(pl, "torch", -1, -1, NULL);
                if (tr) WWield(pl, tr, SL_LIGHT);
            }
            if (w.nls) { holder->GainPermStati(EFF_FLAG1, it, SS_ENCH, 0, 0, FIND("Nine Lives Stealer"), 7); holder->CalcValues(); }
        } else {
            pl->GainPermStati(TRUE_SIGHT, pl, SS_MISC, 30, 0, 0);   /* the victim is seen in the dark without lighting a square */
            if (w.mode == WM_HIT) {
                a = WSpawn(mp, pl, w.ak, AIMX - 2, PY);
                v = a ? WSpawn(mp, pl, w.vk, AIMX + 1, PY) : NULL;
                it = WMake(pl, "long sword", w.q, -1, NULL);
                if (it && w.burst) it->GainPermStati(EXTRA_QUALITY, pl, SS_MISC, (int16)WQ_BURST, 0, 0);
            } else {
                v = WSpawn(mp, pl, WK_ANY, PX + 10, PY);
                if (w.launcher) bow = WMake(pl, w.launcher, w.lq, -1, NULL);
                it = WMake(pl, w.item, w.q, -1, NULL);
            }
            if (!it || !v || (w.mode == WM_HIT && !a) || (w.launcher && !bow)) {
                Error("REEL_ERROR weapon clip %s: item %p victim %p actor %p launcher %p", w.key, (void *)it, (void *)v, (void *)a, (void *)bow);
                continue;
            }
            v->mHP = v->cHP = 500;
        }
        WRefresh(pl);
        ++count;
        const std::string clip = Sanitize(w.key);
        char cname[200];
        snprintf(cname, sizeof cname, "%03d-%s", count, clip.c_str());
        Error("REEL %d %s weapon", count, w.key);
        Error("REEL_KEY %d %s", count, w.key);
        ViewLog(pl, w.key, "before");
        FrameClip(cname);
        pl->MyTerm->StopWatch(300);
        if (w.mode == WM_HELD) {
            Creature *holder = hold ? (Creature *)hold : (Creature *)pl;
            for (int i = 1; i <= 8; ++i) {
                holder->PlaceAt(mp, hx + i, PY, true);
                WRefresh(pl);
                pl->MyTerm->StopWatch(250);
            }
            Error("REEL_WEAPON_HELD %s lightrange %d radius %d lit %d", w.key, (int)holder->LightRange, (int)LightHeldRadius(holder, it), WLitCount(mp));
            pl->MyTerm->StopWatch(500);
        } else if (w.mode == WM_HIT) {
            EventInfo e; e.Clear();
            e.EActor = a; e.EVictim = v; e.ETarget = v; e.EItem = it;
            e.isCrit = w.crit; e.vDmg = 10;
            const hObj vh = v->myHandle;
            if (w.saveRoll) LOFSetForcedSaveThrowRoll((int8)w.saveRoll);
            gTfLit = 0;
            TargetFlashHook = TfHook;
            Silence = 1;
            ((Weapon *)it)->QualityDmgSingle(e, w.q);
            Silence = 0;
            TargetFlashHook = NULL;
            LOFClearForcedSaveThrowRoll();
            Creature *vv = oCreature(vh);
            Refresh(pl);
            pl->MyTerm->StopWatch(700);
            Error("REEL_WEAPON_HIT %s flashes %d xdmg %d died %d", w.key, gTfLit, (int)e.xDmg, (!vv || vv->isDead()) ? 1 : 0);
        } else {
            const int hp0 = (int)v->cHP;
            gWFlight = 0; gTfLit = 0;
            LOFSetForcedRoll(20);
            EffectStepHook = WFlightHook;
            TargetFlashHook = TfHook;
            Silence = 1;
            Throw(EV_RATTACK, pl, v, bow, it);
            Silence = 0;
            EffectStepHook = NULL;
            TargetFlashHook = NULL;
            LOFSetForcedRoll(0);
            const int hit = (int)v->cHP < hp0 ? 1 : 0;
            Refresh(pl);
            pl->MyTerm->StopWatch(700);
            Error("REEL_WEAPON_FLIGHT %s steps %d flashes %d hit %d", w.key, gWFlight, gTfLit, hit);
        }
        if (bow) bow->Remove(true);
        pl->RemoveStati(TRUE_SIGHT);
        pl->mHP = pl->cHP = 30000;
        ViewLog(pl, w.key, "after");
    }
}

} /* namespace */

/* inc-jw0hw: hooks INCURSION_EFFECT_REEL, INCURSION_EFFECT_LIGHT_TABLE, INCURSION_WALL_LOAD and INCURSION_FIERY_ROOM. */
void EffectReelProbe(Player *pl) {
    const bool tableMode = getenv("INCURSION_EFFECT_LIGHT_TABLE") != NULL;
    if (getenv("INCURSION_WALL_LOAD") && pl && pl->m) { WallLoadProbe(pl); return; }
    if (getenv("INCURSION_FIERY_ROOM") && pl && pl->m) { FieryRoomProbe(pl); return; }
    if (!getenv("INCURSION_EFFECT_REEL") && !tableMode)
        return;
    if (!pl || !pl->m) {
        Error("REEL_ERROR no live player and map");
        return;
    }
    Map *mp = pl->m;
    const rID floor = FIND("floor"), wall = FIND("dungeon wall"), kobold = FIND("kobold");
    const rID breath = FIND("Breath Weapon");
    if (!floor || !wall || !kobold || !breath) {
        Error("REEL_ERROR missing floor, dungeon wall, kobold or Breath Weapon");
        return;
    }
    if (mp->SizeX() < 44 || mp->SizeY() < 34) {
        Error("REEL_ERROR map %dx%d is smaller than 44x34", (int)mp->SizeX(), (int)mp->SizeY());
        return;
    }
    /* inc-jw0hw: INCURSION_EFFECT_REEL_ONLY keeps the named effects (tools/render_effect_reel.sh --only). */
    const char *only = getenv("INCURSION_EFFECT_REEL_ONLY");
    /* inc-jw0hw: INCURSION_REEL_SCENE_OFF leaves out the creatures, corpses and items a scene places for its effect to act on
       (tools/check_effect_reel_scenes.sh --red uses it to show each assertion goes red). */
    const bool sceneOff = getenv("INCURSION_REEL_SCENE_OFF") != NULL;
    const std::vector<TableRow> table = ReadTable();

    /* The list, from the loaded module. */
    std::vector<Entry> list;
    Module *mod = theGame->Modules[0];
    for (int i = 0; i < mod->szEff; ++i) {
        const rID id = mod->EffectID(i);
        const char *kind;
        if (id == breath) continue;   /* once per damage type, below */
        if (IsReelKind(mod->QEff[i], &kind)) {
            Entry e = { id, kind, -1, 0, false };
            list.push_back(e);
        }
    }
    std::vector<int> dts;
    for (int i = 0; i < mod->szMon; ++i)
        for (int j = 0; j < NUM_TMON_ATTK; ++j) {
            const TAttack &a = mod->QMon[i].Attk[j];
            if (a.AType != A_BREA && a.AType != A_BRE2) continue;
            bool seen = false;
            for (size_t k = 0; k < dts.size(); ++k) seen = seen || dts[k] == a.DType;
            if (!seen) dts.push_back(a.DType);
        }
    for (size_t k = 0; k < dts.size(); ++k) {
        Entry e = { breath, "breath", dts[k], 0, false };
        list.push_back(e);
    }
    /* inc-epzc0: a second clip for each damage type some monster breathes as a cone (Fight.cpp scopes AR_CONE the same way). */
    std::vector<int> cdts;
    for (int i = 0; i < mod->szMon; ++i)
        for (int j = 0; j < NUM_TMON_ATTK; ++j) {
            const TAttack &a = mod->QMon[i].Attk[j];
            if (a.AType != A_BREA && a.AType != A_BRE2) continue;
            if (mod->QMon[i].GetConst(a.AType == A_BREA ? BREATH_SHAPE : BREATH2_SHAPE) != (uint32)AR_CONE) continue;
            bool seen = false;
            for (size_t k = 0; k < cdts.size(); ++k) seen = seen || cdts[k] == a.DType;
            if (!seen) cdts.push_back(a.DType);
        }
    for (size_t k = 0; k < cdts.size(); ++k) {
        Entry e = { breath, "cone", cdts[k], 0, true };
        list.push_back(e);
    }
    /* inc-jw0hw: Pyrotechnics asks "Smoke, fireworks or explosion?" and redirects to one of
       three effects; one clip per answer, with the answer queued in the terminal. */
    const rID pyro = FIND("Pyrotechnics");
    if (pyro && TEFF(pyro)->ef.eval == EA_GENERIC) {
        const char formKey[3] = { 's', 'f', 'e' };
        for (int k = 0; k < 3; ++k) {
            Entry e = { pyro, "form", -1, formKey[k], false };
            list.push_back(e);
        }
    }

    if (tableMode) {
        /* inc-jw0hw: list the glow decision of every reel effect; cast nothing. */
        int shown = 0;
        for (size_t n = 0; n < list.size(); ++n) {
            const Entry &en = list[n];
            char nm[160];
            if (en.dtype >= 0)
                snprintf(nm, sizeof nm, en.cone ? "Breath Weapon (%s) cone" : "Breath Weapon (%s)", Lookup(DTypeNames, en.dtype));
            else if (en.form)
                snprintf(nm, sizeof nm, "Pyrotechnics (%s)", FormWord(en.form));
            else   /* the declared name keeps its ;tag, which keys a repeated name */
                snprintf(nm, sizeof nm, "%s", mod->GetText(TEFF(en.id)->Name));
            /* a form is lit as the effect its answer redirects to */
            TEffect *te = en.form ? TEFF(FormEffect(en.form)) : TEFF(en.id);
            bool skip = (te->ef.qval & (Q_INV | Q_EQU | Q_ITM | Q_LOOK)) != 0;
            for (size_t k = 0; k < sizeof kSkip / sizeof kSkip[0]; ++k)
                if (en.dtype < 0 && strcmp(kSkip[k].name, NAME(en.id)) == 0) skip = true;
            if (skip) continue;
            const int dt = en.dtype >= 0 ? en.dtype : (te->ef.eval == EA_BLAST ? te->ef.xval : 0);
            const EffectLightDecision d = EffectLightDecide(te, (int16)dt);
            char buf[40];
            Error("LIGHT %s\t%s\t%s", nm, d.lit ? "LIT" : "UNLIT",
                  d.lit ? LightClass(d.colour, buf, sizeof buf) : "-");
            ++shown;
        }
        WeaponTableList(pl, shown);
        Error("LIGHT_DONE %d", shown);
        return;
    }

    MotionSelfTest();
    const bool wasPlay = theGame->PlayMode;
    const int8 wasAnim = pl->Options[OPT_ANIMATION], wasMore = pl->Options[OPT_AUTOMORE];
    const int8 wasLight = pl->LightRange, wasInfra = pl->InfraRange, wasShadow = pl->ShadowRange;
    const int16 wasHP = pl->cHP, wasMax = pl->mHP, wasFP = pl->cFP;
    theGame->PlayMode = true;
    pl->Options[OPT_ANIMATION] = 0;   /* Normal: the light map is live */
    pl->Options[OPT_AUTOMORE] = 1;
    int count = 0;
    SnapshotPlayer(pl);

    for (size_t n = 0; n < list.size(); ++n) {
        const Entry &en = list[n];
        char nm[160];
        char key[160];   /* the table's name for the clip: the declared name with its ;tag */
        if (en.dtype >= 0)
            snprintf(nm, sizeof nm, en.cone ? "Breath Weapon (%s) cone" : "Breath Weapon (%s)", Lookup(DTypeNames, en.dtype));
        else if (en.form)
            snprintf(nm, sizeof nm, "Pyrotechnics (%s)", FormWord(en.form));
        else
            snprintf(nm, sizeof nm, "%s", NAME(en.id));
        if (en.dtype < 0 && !en.form) snprintf(key, sizeof key, "%s", mod->GetText(TEFF(en.id)->Name));
        else snprintf(key, sizeof key, "%s", nm);
        if (!WantedByFilter(only, nm) && !(en.dtype >= 0 && WantedByFilter(only, "Breath Weapon"))
            && !(en.form && WantedByFilter(only, "Pyrotechnics")))
            continue;
        TEffect *te = TEFF(en.id);
        const char *skipWhy = NULL;
        for (size_t k = 0; k < sizeof kSkip / sizeof kSkip[0]; ++k)
            if (en.dtype < 0 && strcmp(kSkip[k].name, nm) == 0) skipWhy = kSkip[k].reason;
        if (skipWhy) {
            Error("REEL_SKIP %s %s", nm, skipWhy);
            continue;
        }
        if (te->ef.qval & (Q_INV | Q_EQU | Q_ITM | Q_LOOK)) {
            Error("REEL_SKIP %s it prompts for an item", nm);
            continue;
        }
        const TableRow *row = NULL;
        for (size_t k = 0; k < table.size(); ++k)
            if (table[k].key == key) row = &table[k];
        if (row && row->nothing) {   /* the table says this clip shows nothing: do not render it */
            Error("REEL_SKIP %s shows nothing by the table", nm);
            continue;
        }
        /* an effect with no light of its own needs a bright room to be judged; a LIT one a dark room. No row: bright. */
        const bool bright = !row || row->glow != "LIT";
        if (!row) Error("REEL_ROOM_NOROW %s has no table row; room treated as UNLIT", nm);
        BuildRoom(mp, pl, floor, wall, bright);
        Error("REEL_ROOM %d %s %s", count + 1, nm, bright ? "bright" : "dark");
        /* inc-jw0hw: the Pyrotechnics script removes the middle kobold's torch, so the smoke would land on squares with no light of their own.
           A wall torch in the stub (LK_WALLTORCH, range 3, Light.cpp) is a separate source the cast does not remove.
           BuildRoom rewrites every square, so the next clip starts without it. */
        if (en.form == 's') {
            /* The cast removes the kobold's torch, so the kobold's light is gone and three wall torches (LK_WALLTORCH, range 3) light it:
               (21,17) behind the cloud on the player's row, (14,25) in the south wall beside the cloud (its glow on rows 22-24 is
               outside the cloud and not behind it), and (10,18) on the player's side, which lights the cloud's front face. */
            Rect trect(0, 0, mp->SizeX() - 1, mp->SizeY() - 1);
            const rID reg = mp->RegionAt(pl->x, pl->y);
            const rID wt = FIND("Wall Torch");
            for (int y = PY - 2; y <= PY + 2; ++y) mp->WriteAt(trect, STUBX, y, floor, reg, PRIO_MAX, true);
            mp->WriteAt(trect, 21, PY, wt, reg, PRIO_MAX, true);
            mp->WriteAt(trect, 14, RY1 + 1, wt, reg, PRIO_MAX, true);
            mp->WriteAt(trect, 10, PY + 1, wt, reg, PRIO_MAX, true);
            /* BuildRoom set Memory from the old glyphs; take it again from the new ones, as BuildRoom does. */
            const int mx[8] = { STUBX, STUBX, STUBX, STUBX, STUBX, 21, 14, 10 };
            const int my[8] = { PY - 2, PY - 1, PY, PY + 1, PY + 2, PY, RY1 + 1, PY + 1 };
            for (int i = 0; i < 8; ++i) mp->At(mx[i], my[i]).Memory = (uint32)mp->At(mx[i], my[i]).Glyph;
            pl->CalcVision();
        }
        LightFlashClearAll();
        pl->mHP = pl->cHP = 30000;      /* the player survives every clip */
        pl->cFP = wasFP;                /* an effect that costs fatigue asks nothing */
        const AimKind aim = AimOf(en, te);
        const bool touch = IsTouch(te);
        /* inc-jw0hw: the scene each of these effects needs to work as it does in play (each reads its target square or its party). */
        const bool plain = en.dtype < 0 && !en.form;
        const bool isWater = plain && !strcmp(nm, "Waterspout");              /* lib/pspells.irh:3536: the aim square must be TF_WATER */
        const bool isFeast = plain && !strcmp(nm, "Heroes' Feast");           /* lib/pspells.irh:5937: three friendly creatures within 10 */
        const bool isRock = plain && !strcmp(nm, "Transmute Rock to Mud");    /* src/Effects.cpp:1598: the square must be solid rock */
        const bool isCharm = plain && !strcmp(nm, "Fire Charm");              /* lib/wspells.irh:6325: the square must hold a flame source */
        const bool isAlch = plain && !strcmp(nm, "Alchemist's Fire");         /* src/Magic.cpp:656: its damage comes from the flask's ALCHEMY_LEV */
        const bool isVenom = plain && te->ef.aval == AR_POISON && VenomMonster(en.id);   /* a monster's `Poison:` attribute names it: delivered by its attack, then its pulse */
        const bool isTrapClip = plain && IsTrapClip(en.id);                      /* fired through a Trap object */
        const bool isUndeath = plain && !strcmp(nm, "Undeath to Death");     /* lib/pspells.irh:6017: harms undead only */
        const bool isHoly = plain && !strcmp(nm, "water");                   /* lib/alchemy.irh:146: a blessed flask harms undead only */
        const bool isRaise = plain && !strcmp(nm, "reanimation trap");       /* lib/threats.irh:1258: affects corpses only */
        const bool isAnimate = plain && !strcmp(nm, "Animate Objects");      /* lib/pspells.irh:5573: affects unattended items and held items */
        const bool isChain = plain && !strcmp(nm, "Chain Lightning");        /* lib/wspells.irh:8549: arcs one target to the next */
        const bool isFumes = plain && !strcmp(nm, "thunderbeast fumes");     /* lib/mon1.irh:3032: a thunderbeast's own cloud */
        const bool isShake = plain && (!strcmp(nm, "Tremor") || !strcmp(nm, "Thunder"));   /* lib/wspells.irh:5781, lib/m_items.irh:3934: the globe shakes */
        const bool isDance = plain && !strcmp(nm, "Othello's Irresistable Dance");         /* lib/wspells.irh:9295: the affected creatures dance */
        const bool isSpores = plain && !strcmp(nm, "Vrock Spores");          /* lib/mon4.irh:698: spores blast from a vrock */
        const bool isEarthmaw = plain && !strcmp(nm, "Earthmaw");            /* lib/pspells.irh:3418: the victim shakes */
        int aimX = -1, aimY = -1;   /* -1: the middle kobold's square */
        if (isRock || isCharm) { aimX = STUBX; aimY = PY; }
        /* The kobolds stand where the cast reaches them. Default: 9 squares east, rows PY-2, PY, PY+2.
           A caster-centered globe (no target prompt): inside its radius lval, so Electric Loop
           (lval 1) has all three adjacent to the player. A touch: the middle kobold adjacent. */
        int kx[3], ky[3];
        for (int k = 0; k < 3; ++k) { kx[k] = AIMX; ky[k] = PY + 2 * (k - 1); }
        if (aim == AIM_SELF && te->ef.aval == AR_GLOBE) {
            const int L = te->ef.lval < 1 ? 1 : te->ef.lval > 9 ? 9 : te->ef.lval;
            const int d = L <= 2 ? 1 : L - 1, sp = L <= 2 ? 1 : 2;
            for (int k = 0; k < 3; ++k) { kx[k] = PX + d; ky[k] = PY + sp * (k - 1); }
        }
        /* A directional effect with no area type is a script that strikes the three squares in front of the caster
           (Burning Hands, lib/wspells.irh:1065): all three kobolds stand there, east of the player. */
        if (aim == AIM_DIR && te->ef.aval == AR_NONE)
            for (int k = 0; k < 3; ++k) { kx[k] = PX + 1; ky[k] = PY + (k - 1); }
        if (touch) { kx[1] = PX + 1; ky[1] = PY; }
        if (isCharm) {   /* a wall torch in the stub, where the kobolds see it */
            PutTerrain(mp, FIND("Wall Torch"), STUBX, PY);
            pl->CalcVision();
        }
        if (isWater) {   /* a pool 7 squares across under the aim point; BuildRoom rewrites it for the next clip */
            const rID pool = FIND("shallow water");
            for (int y = PY - 3; y <= PY + 3; ++y)
                for (int x = AIMX - 3; x <= AIMX + 3; ++x)
                    if (InBlock(x, y) && !(x == STUBX && y >= PY - 2 && y <= PY + 2)) PutTerrain(mp, pool, x, y);
            pl->CalcVision();
        }
        Monster *mid = NULL, *ks[3] = { NULL, NULL, NULL };
        for (int k = 0; k < 3; ++k) {
            Monster *mn = new Monster(kobold); ks[k] = mn;
            mn->PlaceAt(mp, kx[k], ky[k], true);
            mn->Initialize(true);
            if (k == 1) mid = mn;
        }
        /* inc-jw0hw: the scene's content: what the effect acts on, placed where the cast reaches it. */
        std::vector<Monster *> exm; std::vector<int> exhp;   /* placed creatures and their hit points at the start */
        int floorItems = 0, heldItems = 0, corpseCount = 0;
        Monster *aimMon = mid;                               /* the creature a targeted cast is aimed at */
        Monster *tb = NULL;                                  /* the thunderbeast that exudes the fumes */
        auto addMon = [&](const char *rn, int x, int y) -> Monster * {
            if (sceneOff) return NULL;
            const rID r = FIND(rn);
            if (!r) { Error("REEL_ERROR scene creature %s is missing", rn); return NULL; }
            Monster *m2 = new Monster(r);
            m2->PlaceAt(mp, x, y, true);
            m2->Initialize(true);
            exm.push_back(m2); exhp.push_back((int)m2->cHP);
            return m2;
        };
        auto addFloorItem = [&](const char *rn, int x, int y) {
            if (sceneOff) return;
            const rID r = FIND(rn);
            Item *it = r ? Item::Create(r) : NULL;
            if (!it) { Error("REEL_ERROR scene item %s is missing", rn); return; }
            it->PlaceAt(mp, x, y);
            ++floorItems;
        };
        auto addCorpse = [&](int x, int y) {   /* a kobold corpse: the creature is made, leaves its corpse, and is removed */
            if (sceneOff) return;
            Monster *tmp = new Monster(kobold);
            tmp->PlaceAt(mp, x, y, true);
            tmp->Initialize(true);
            Corpse *c = new Corpse(tmp);
            c->PlaceAt(mp, x, y);
            tmp->Remove(true);
            ++corpseCount;
        };
        if (isUndeath) {   /* the burst is 4 squares around the middle kobold: five undead of 1 Hit Die each stand inside it */
            addMon("skeletal foot soldier", AIMX - 2, PY);
            addMon("skeletal foot soldier", AIMX - 1, PY - 1);
            addMon("skeletal foot soldier", AIMX - 1, PY + 1);
            addMon("crawling claw", AIMX + 1, PY);
            addMon("crawling claw", AIMX - 2, PY - 2);
        }
        if (isHoly) {      /* the flask reaches 6 squares (EV_CALC_EFFECT, lib/alchemy.irh:175) and the splash is 1 square around its target:
                              the target undead stands 5 squares from the player and three more stand inside the splash, none on the row he throws along */
            aimMon = addMon("skeletal foot soldier", PX + 5, PY);
            addMon("skeletal foot soldier", PX + 5, PY - 1);
            addMon("skeletal foot soldier", PX + 5, PY + 1);
            addMon("skeletal foot soldier", PX + 4, PY - 1);
            if (!aimMon) aimMon = mid;
        }
        if (isRaise) {     /* the globe is 6 squares around the trap: five corpses inside it */
            addCorpse(AIMX - 4, PY - 1);   /* not under a kobold: the raised undead stands on its corpse's square */
            addCorpse(AIMX - 2, PY - 3);
            addCorpse(AIMX - 2, PY + 3);
            addCorpse(AIMX + 3, PY - 3);
            addCorpse(AIMX + 3, PY + 3);
        }
        if (isAnimate) {   /* the globe is 6 squares around the player: six items on the floor, and each kobold holds one */
            const char *floorNames[6] = { "club", "dagger", "quarterstaff", "club", "dagger", "quarterstaff" };
            const int fx[6] = { 7, 7, 8, 8, 9, 9 }, fy[6] = { PY - 3, PY + 3, PY - 1, PY + 1, PY - 3, PY + 3 };
            for (int i = 0; i < 6; ++i) addFloorItem(floorNames[i], fx[i], fy[i]);
            const char *heldNames[3] = { "dagger", "club", "quarterstaff" };
            for (int k = 0; k < 3 && !sceneOff; ++k) {
                Item *gear;   /* the kobold holds only the item placed: whatever it was generated with does not decide which item the spell takes */
                while ((gear = ks[k]->FirstInv()) != NULL) gear->Remove(true);
                Item *it = Item::Create(FIND(heldNames[k]));
                if (!it) continue;
                ks[k]->GainItem(it, true);
                ThrowVal(EV_WIELD, SL_WEAPON, ks[k], NULL, it);
                ++heldItems;
            }
        }
        if (isShake) {     /* the globe is 6 squares around the aimed kobold: two items on the floor inside it, one far outside it */
            addFloorItem("club", AIMX - 2, PY - 3);
            addFloorItem("dagger", AIMX + 2, PY + 3);
            addFloorItem("club", RX1 - 1, PY);
        }
        if (isAnimate)     /* one more item, far outside the globe: it must not shake */
            addFloorItem("club", RX1 - 9, PY);
        if (isChain) {     /* three more kobolds, so the bolt has six to arc through; the first three stand where every clip puts them */
            addMon("kobold", AIMX - 3, PY - 3);
            addMon("kobold", AIMX - 5, PY - 3);
            addMon("kobold", AIMX - 3, PY + 3);
        }
        if (isFumes && !sceneOff) {   /* the thunderbeast stands beside the kobolds, north of the stub, in the player's view and 12 squares from him */
            const rID tbr = FIND("thunderbeast");
            if (tbr) {
                /* its own EV_INITIALIZE makes a fog field by script: Map::NewField billows it (inc-jw0hw Phase 4b); log that formation */
                snprintf(gClip, sizeof gClip, "thunderbeast script fog");
                FormationHook = FormHook;
                tb = new Monster(tbr);
                tb->PlaceAt(mp, AIMX + 3, PY - 4, true);
                tb->Initialize(true);
                FormationHook = NULL;
                tb->mHP = tb->cHP = 5000;
                /* Its own EV_INITIALIZE (lib/mon1.irh:3001) has made the cloud; the clip casts the fumes effect instead. */
                for (int i = 0; mp->Fields[i]; ) mp->RemoveField(mp->Fields[i]);
            } else Error("REEL_ERROR scene creature thunderbeast is missing");
        }
        /* A caster level high enough for the effect to reach what the scene placed (Undeath to Death's pool is (caster level)d4 Hit Dice;
           Chain Lightning arcs once for each 3 caster levels, Magic.cpp via lib/wspells.irh:8571). The status carries the effect's id,
           so BuildRoom removes it before the next clip. */
        if ((isUndeath || isChain) && !sceneOff)
            pl->GainPermStati(BONUS_SCHOOL_CASTING_LEVEL, NULL, SS_MISC, (int16)te->Schools, isUndeath ? 10 : 9, en.id);
        if (isFeast)   /* the party: the three kobolds join the priest, hurt so the feast's healing shows */
            for (int k = 0; k < 3; ++k) {
                const bool joined = ks[k]->MakeCompanion(pl, PHD_FREEBIE);
                ks[k]->mHP = 10; ks[k]->cHP = 2;
                Error("REEL_COMPANION %s kobold %d joined %d friendly %d", nm, k, joined ? 1 : 0, ks[k]->isFriendlyTo(pl) ? 1 : 0);
            }
        if (isVenom) mid->mHP = mid->cHP = 500;   /* the venom is re-delivered until it takes: the victim must outlast the tries */
        Trap *realTrap = NULL;
        if (isTrapClip) {
            realTrap = new Trap(FIND("trap"), en.id);
            realTrap->PlaceAt(mp, mid->x, mid->y);
            realTrap->TrapFlags |= TS_FOUND;
            realTrap->SetImage();
        }
        Item *flask = NULL;
        /* a flask of the effect, as Skills.cpp:3993 makes it for a crafter with Alchemy 20; the holy water is a blessed one
           (its EV_ISTARGET, lib/alchemy.irh:167, harms undead only for a blessed flask) */
        auto makeFlask = [&]() -> Item * {
            Item *f = Item::Create(FIND("placeholder"));
            f->MakeMagical(en.id, 0);
            f->Initialize();
            if (isAlch) f->GainPermStati(ALCHEMY_LEV, NULL, SS_MISC, 0, 20);
            if (isHoly) f->IFlags |= IF_BLESSED;
            return f;
        };
        if (isAlch || isHoly) flask = makeFlask();
        /* inc-jw0hw: Pyrotechnics proceeds only if the target square holds a creature with a lit torch in SL_LIGHT. */
        if (en.form) {
            Item *torch = Item::Create(FIND("torch"));
            if (torch) {
                mid->GainItem(torch, true);
                ThrowVal(EV_WIELD, SL_LIGHT, mid, NULL, torch);
            }
            Error("REEL_TORCH %s in-slot %d range %d", nm, mid->InSlot(SL_LIGHT) ? 1 : 0,
                  mid->InSlot(SL_LIGHT) ? (int)mid->InSlot(SL_LIGHT)->GetLightRange() : 0);
        }
        /* inc-jw0hw: the Skull Trap's script lights its skull only when EItem is the trap. */
        Trap *skullTrap = NULL;
        const bool isSkull = en.dtype < 0 && en.id == FIND("skull trap;trap");
        const bool isNightmare = en.dtype < 0 && en.id == FIND("nightmare smite;actual blast");   /* cast through its gather */
        if (isSkull) {
            skullTrap = SkullTrapPlace(pl, mp, FIND("trap"), en.id, FIND("Skull Trap"), AIMX - 1, PY);
            gSkX = AIMX - 1; gSkY = PY; gSkTicks = 0; gSkFirst = gSkLast = 0; gSkLitTicks = 0; gSkEnds = 0;
            ScriptLightTickHook = SkTick; ScriptLightEndHook = SkEnd;
        }
        pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
        Refresh(pl);
        pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;

        ++count;
        const std::string clip = Sanitize(nm);
        char cname[200];
        snprintf(cname, sizeof cname, "%03d-%s", count, clip.c_str());
        Error("REEL %d %s %s", count, nm, en.kind);
        FrameClip(cname);
        pl->MyTerm->StopWatch(300);

        /* REEL_SMOKE: the row through the cloud's center (AIM y), and one row outside the cloud, east of the player. */
        auto smokeLog = [&](const char *when) {
            if (en.form != 's') return;
            const int rows[4] = { mid->y, 22, 23, 24 };
            for (int r = 0; r < 4; ++r)
                for (int x = PX + 1; x <= RX1; ++x) {
                    LightRGB fc;
                    Error("REEL_SMOKE %s %d,%d vis %d lit %d fog %d paint %d", when, x, rows[r],
                          (mp->At(x, rows[r]).Visibility & VI_VISIBLE) ? 1 : 0, LightLitAt((int16)x, (int16)rows[r]) ? 1 : 0,
                          LightFogAt((int16)x, (int16)rows[r], fc) ? 1 : 0, (int)gSqPaint[x][rows[r]]);
                }
        };
        memset(gSqPaint, -1, sizeof gSqPaint);   /* no paint is recorded before the cast */
        smokeLog("before");
        EventInfo xe; xe.Clear();
        xe.EActor = pl; xe.EMap = mp; xe.eID = en.id; xe.isSpell = true;
        /* Aim as the player's prompt would (see AimOf); a breath lands on the middle target and a
           field is centered on the player, as before. A death effect ignores hit points. */
        switch (aim) {
        case AIM_SELF:   /* no prompt: Magic.cpp:1250 makes the caster the target */
            xe.ETarget = pl; xe.EVictim = pl; xe.EXVal = PX; xe.EYVal = PY;
            break;
        case AIM_DIR:
            xe.isDir = true; xe.EDir = EAST;
            break;
        case AIM_TAR:
            xe.ETarget = aimMon; xe.EVictim = aimMon; xe.EXVal = aimMon->x; xe.EYVal = aimMon->y;
            break;
        case AIM_LOC:
            xe.isLoc = true; xe.EXVal = aimMon->x; xe.EYVal = aimMon->y;
            break;
        case AIM_FIELD:
            xe.isLoc = true; xe.EXVal = PX; xe.EYVal = PY;
            if (tb) { xe.EActor = tb; xe.EXVal = tb->x; xe.EYVal = tb->y; }   /* the fumes are the thunderbeast's: the cloud is centered on it and follows it */
            break;
        case AIM_BREATH:
            xe.isLoc = true; xe.EXVal = AIMX; xe.EYVal = PY; xe.EVictim = mid;
            break;
        }
        if (aimX >= 0) { xe.EXVal = aimX; xe.EYVal = aimY; }
        /* inc-jw0hw (Phase 5): the squares that should move, found here from the scene and the effect's data, not from the engine's own
           pick: the globe's center is where the cast is aimed, and its radius is the effect's lval. */
        if (isShake || isAnimate || isDance || isEarthmaw) {
            const int cxm = xe.EXVal, cym = xe.EYVal, R = te->ef.lval;
            std::string want;
            auto addSq = [&](int x, int y) {
                char b[24]; snprintf(b, sizeof b, "%s%d,%d", want.empty() ? "" : ";", x, y); want += b;
            };
            Thing *t; int ti;
            if (isEarthmaw) addSq(aimMon->x, aimMon->y);
            else MapIterate(mp, t, ti) {
                if (dist(cxm, cym, t->x, t->y) > R) continue;
                if (t->isItem() && !((Item *)t)->Owner()) { if (!isDance) addSq(t->x, t->y); continue; }
                if (!t->isCreature()) continue;
                Creature *c = (Creature *)t;
                if (isShake) addSq(t->x, t->y);
                else if (te->HasFlag(EF_CASTER_IMMUNE) && c == pl) continue;   /* the spell's own flag: the caster is not an Animate Objects holder */
                else if (isDance) { if (c->isMType(MA_HUMANOID) && c->isMType(MA_LIVING) && c->ResistLevel(AD_MIND) != -1) addSq(t->x, t->y); }
                else if (isAnimate) continue;   /* inc-jw0hw (Phase 6b): Animate Objects shakes floor items only, never a creature that holds one */
            }
            Error("REEL_MOTION_EXPECT %s center %d,%d radius %d sq %s", nm, cxm, cym, R, want.c_str());
        }
        /* The skull wakes when a creature steps near it (Trap::TriggerTrap): the middle kobold. Its globe is centered on the skull's
           square (13,17), not on the caster, so the player (the trap's caster) stands outside it. */
        if (isSkull && !sceneOff) {
            xe.EActor = mid; xe.ETarget = mid; xe.EVictim = ks[0];
            xe.isLoc = true; xe.EXVal = AIMX - 1; xe.EYVal = PY;
        }
        if (isAlch || isHoly) { xe.EItem = flask; xe.isItem = true; xe.ETarget = aimMon; xe.EVictim = aimMon; }   /* inc-s87gl: thrown AT the kobold, as a player targeting it; a location throw skips the bolt's flight and light */
        static rID terBefore[64][40];
        for (int y = 0; y < 40 && y < mp->SizeY(); ++y)
            for (int x = 0; x < 64 && x < mp->SizeX(); ++x) terBefore[x][y] = mp->TerrainAt(x, y);
        int16 hp0[3]; for (int k = 0; k < 3; ++k) hp0[k] = ks[k]->cHP;
        ViewLog(pl, nm, "before-cast");
        Error("REEL_AIM %s %s", nm, kAimName[aim]);
        Error("REEL_KEY %d %s", count, key);
        snprintf(gClip, sizeof gClip, "%s", nm);
        Error("REEL_GEOM %s player %d,%d victim %d,%d aim %d,%d top %d", nm, (int)pl->x, (int)pl->y, (int)mid->x, (int)mid->y,
              (int)(aimMon ? aimMon->x : mid->x), (int)(aimMon ? aimMon->y : mid->y), (int)(pl->MyTerm->OffsetY() > 0 ? pl->MyTerm->OffsetY() : 0));
        if (te->HasFlag(EF_DART))   /* the dart's plan for a victim 2 squares and 1 square from the west wall (x 3) */
            for (int vx = 5; vx >= 4; --vx) {
                int16 qx[3], qy[3];
                const int qn = DartFlightPlan(mp, (int16)vx, PY, qx, qy, 3, NULL, NULL);
                Error("REEL_DARTPLAN %s victim %d,%d squares %d first %d,%d", nm, vx, PY, qn, (int)qx[0], (int)qy[0]);
            }
        for (int8 v = 0; v == 0 || te->Vals(v); ++v) {   /* the light decision of each blast part, as the part's own damage type gives it */
            const EffectValues *sg = v == 0 ? &te->ef : te->Vals(v);
            if (sg->eval != EA_BLAST) continue;
            const EffectLightDecision d = EffectLightDecide(te, (int16)sg->xval);
            Error("REEL_DECIDE %s part %d dtype %d lit %d colour %d", nm, (int)v, (int)sg->xval, d.lit ? 1 : 0, (int)d.colour);
        }
        Error("REEL_COLSET %s poison %d,%d,%d,%d necro %d,%d,%d,%d", nm, (int)BlastColourSets[COL_POISON * 4], (int)BlastColourSets[COL_POISON * 4 + 1],
              (int)BlastColourSets[COL_POISON * 4 + 2], (int)BlastColourSets[COL_POISON * 4 + 3], (int)BlastColourSets[COL_NECRO * 4],
              (int)BlastColourSets[COL_NECRO * 4 + 1], (int)BlastColourSets[COL_NECRO * 4 + 2], (int)BlastColourSets[COL_NECRO * 4 + 3]);
        if (en.dtype >= 0) {
            /* Fight.cpp (A_BREA) loads the resource with the attack's values before the throw. */
            te->ef.pval.Number = 3; te->ef.pval.Sides = 6; te->ef.pval.Bonus = 0;
            te->ef.lval = 4;
            te->ef.xval = (uint8)en.dtype;
            te->ef.aval = en.cone ? AR_CONE : AR_BREATH;   /* inc-epzc0: scoped to this clip; restored after the loop */
            xe.DType = (int8)en.dtype;
            xe.Dmg = te->ef.pval;
            xe.AType = A_BREA;
            xe.isNAttack = true;
        }
        /* The effect code sets e.vRange = 5 + caster level / 2 itself; Extend doubles it, so the
           first level-1 cast reaches 10 squares and the targets stand 9 away. */
        xe.MM |= MM_EXTEND;
        /* inc-jw0hw: Magic.cpp:932 runs an EF_ACTIVATE segment only when isActivation is set. */
        xe.isActivation = te->HasFlag(EF_ACTIVATE);
        if (skullTrap) {
            xe.EItem = (Item *)skullTrap; xe.isTrap = true; xe.vCasterLev = 12;   /* as Trap::TriggerTrap */
            skullTrap->TrapFlags |= TS_DISARMED;
            skullTrap->SetImage();
        }
        /* A long message makes the text terminal wait for a key; the reel prints none. */
        Silence = 1;
        gElLit = gElLitFlash = gTfLit = 0;
        gFormCx = -1; gFormTerrain = 0;
        EffectStepHook = StepHook; EffectLightHook = ElHook; TargetFlashHook = TfHook;
        BallRingHook = RingHook; GlobeGlyphHook = GlobeGlyph;
        FormationHook = FormHook;
        MotionHook = MotionLog; SporeHook = SporeLog;
        if (te->ef.aval == AR_BARRIER && te->ef.eval == EA_TERRAFORM && EffectLightDecide(te, 0).lit) {
            gSweepPl = pl; gSweepTerr = te->ef.rval; gSweepStep = 0; WallSweepHook = SweepHook;
        }
        if (isNightmare) {
            /* inc-jw0hw: the Nightmare Smite clip plays what a player sees: the demon casts the gather, its rainbow pattern
               changes for 2 s while the game waits for a key (idle frames), one turn passes with the pattern still changing,
               then the next turn ends the gather and the blast and the struck flash play. The demon stands north of the
               kobolds, 11 squares from the player, who is outside the blast. */
            const rID gather = FIND("Nightmare Smite"), nalf = FIND("nalfeshnee");
            Monster *demon = new Monster(nalf);
            demon->PlaceAt(mp, AIMX - 1, RY0 + 1, true);
            demon->Initialize(true);
            demon->mHP = demon->cHP = 5000;
            while (demon->HasStati(INVIS)) demon->RemoveStati(INVIS);   /* its spell list starts it invisible */
            EventInfo ge; ge.Clear();
            ge.EActor = demon; ge.EVictim = demon; ge.EMap = mp; ge.eID = gather; ge.isSpell = true;
            ReThrow(EV_EFFECT, ge);
            Refresh(pl);
            pl->MyTerm->StopWatch(2000);
            demon->UpdateStati();           /* one turn passes: the gather stands */
            pl->MyTerm->StopWatch(1000);
            demon->UpdateStati();           /* the gather ends: the pattern stops, the blast plays */
            StandingPatternStopAll();
        } else {
            /* inc-jw0hw: the spell asks its question through the terminal's key read; the queued key is the answer. */
            if (en.form) pl->MyTerm->QueuedChar = (uint8)en.form;
            if (isVenom) {
                /* inc-jw0hw: a venom reaches its victim as in play: the monster's attack poisons it (the AD_POIS damage,
                   Fight.cpp:9305, retried until the Fortitude save fails), then each poison pulse (Creature::PoisonPulse)
                   saves, and on a failed save casts the venom on the victim. The pulse is forced until one lands. */
                const rID vm = VenomMonster(en.id);
                Monster *att = vm ? new Monster(vm) : NULL;
                int tries = 0, pulses = 0; bool landed = false;
                /* A kobold is poison-immune (lib/mon2.irh:480, Magic.cpp:1066 skips an immune victim), so no venom could land on
                   one. The kobold resource loses that immunity while the venom is delivered and gets it back at once. */
                TMonster *tk = TMON(kobold);
                const uint32 imm0 = tk->Imm;
                tk->Imm &= ~(uint32)DF_POIS;
                if (att) {
                    att->PlaceAt(mp, mid->x - 1, mid->y, true);
                    att->Initialize(true);
                    att->mHP = att->cHP = 5000;
                    if (isSpores) Error("REEL_SCENE %s vrock 1 at %d,%d victim %d,%d", nm, (int)att->x, (int)att->y, (int)mid->x, (int)mid->y);
                    while (!mid->HasEffStati(POISONED, en.id) && tries < 80 && !mid->isDead()) {
                        ++tries;
                        ThrowDmg(EV_DAMAGE, AD_POIS, 1, "venom", att, mid);
                    }
                    while (!landed && pulses < 80 && !mid->isDead()) {
                        Status *st = mid->GetStati(POISONED);
                        if (!st) break;
                        const int mag0 = st->Mag;
                        ++pulses;
                        mid->PoisonPulse(true, false);
                        st = mid->GetStati(POISONED);
                        if (!st) break;
                        landed = st->Mag <= mag0;
                    }
                }
                tk->Imm = imm0;
                Error("REEL_VENOM %s attacker %s poisoned %d (attacks %d) landed %d (pulses %d)", nm, vm ? NAME(vm) : "none",
                      mid->HasEffStati(POISONED, en.id) ? 1 : 0, tries, landed ? 1 : 0, pulses);
            } else if (realTrap) {
                /* inc-jw0hw: the middle kobold steps on the trap: Trap::TriggerTrap, which gives the kobold its avoid save;
                   a saved trap stays armed and the kobold steps on it again. */
                int tries = 0;
                while (!(realTrap->TrapFlags & TS_DISARMED) && tries < 80 && !mid->isDead()) {
                    ++tries;
                    EventInfo ti; ti.Clear();
                    ti.EActor = mid; ti.EMap = mp;
                    realTrap->TriggerTrap(ti, true);
                }
                Error("REEL_TRAP %s sprung %d (steps %d)", nm, (realTrap->TrapFlags & TS_DISARMED) ? 1 : 0, tries);
            } else {
                ReThrow(EV_EFFECT, xe);
                /* inc-jw0hw: a thrown flask is an attack roll (EF_ATTACK) and can miss; the player throws again, as in play. */
                if (isAlch || isHoly) {
                    /* the holy water harms only the undead: the target is the first placed one, whose hit points the throw must lower */
                    Monster *tg = isHoly ? aimMon : mid;
                    const int tg0 = isHoly && !exhp.empty() && aimMon == exm[0] ? exhp[0] : (int)hp0[1];
                    int throwsMade = 1;
                    while (tg->cHP >= tg0 && !tg->isDead() && throwsMade < 30) {
                        ++throwsMade;
                        EventInfo re; re.Clear();
                        re.EActor = pl; re.EMap = mp; re.eID = en.id; re.isSpell = true;
                        re.isLoc = true; re.EXVal = tg->x; re.EYVal = tg->y; re.ETarget = tg; re.EVictim = tg;
                        re.MM |= MM_EXTEND; re.isActivation = true;
                        re.EItem = isHoly ? makeFlask() : flask; re.isItem = true;   /* the water script removes its flask */
                        ReThrow(EV_EFFECT, re);
                    }
                    Error("REEL_THROW %s throws %d", nm, throwsMade);
                }
                /* inc-jw0hw: an aimed attack-roll spell (Earthmaw, EF_ATTACK) can miss; the caster casts again, as in play. */
                else if (plain && !strcmp(nm, "Earthmaw")) {   /* ponytail: only Earthmaw is known to miss and land blank; the other EF_ATTACK blasts already show */
                    int castsMade = 1;
                    while (mid->cHP >= hp0[1] && !mid->isDead() && castsMade < 30) {
                        ++castsMade;
                        EventInfo re; re.Clear();
                        re.EActor = pl; re.EMap = mp; re.eID = en.id; re.isSpell = true;
                        re.ETarget = mid; re.EVictim = mid; re.EXVal = mid->x; re.EYVal = mid->y;
                        re.MM |= MM_EXTEND; re.isActivation = te->HasFlag(EF_ACTIVATE);
                        ReThrow(EV_EFFECT, re);
                    }
                    Error("REEL_CAST %s casts %d", nm, castsMade);
                }
            }
            if (en.form) {
                Error("REEL_FORM %s answered %d", nm, pl->MyTerm->QueuedChar ? 0 : 1);
                pl->MyTerm->QueuedChar = 0;
            }
        }
        /* inc-jw0hw: the cast of a touch spell only charges the hand (TOUCH_ATTACK); the touch lands in melee
           (Fight.cpp:7461). The player strikes the adjacent middle kobold through EV_NATTACK, as a bump does
           (Move.cpp:417). A miss leaves the charge, so the strike repeats until the charge falls (a natural 20
           always hits); the loop is capped at 60 strikes. */
        if (touch) {
            const bool charged = pl->HasStati(TOUCH_ATTACK);
            const int mag0 = charged ? (int)pl->GetStatiMag(TOUCH_ATTACK) : 0;
            int tries = 0; bool landed = false;
            while (charged && !landed && tries < 60 && !mid->isDead()) {
                ++tries;
                Throw(EV_NATTACK, pl, mid);
                /* Fight.cpp:7500 lowers the charge by one, or removes the stati at the last one */
                landed = !pl->HasStati(TOUCH_ATTACK) || (int)pl->GetStatiMag(TOUCH_ATTACK) < mag0;
            }
            Error("REEL_TOUCH %s landed %d (charged %d, charge %d, strikes %d)", nm, landed ? 1 : 0, charged ? 1 : 0, mag0, tries);
        }
        if (gFormCx >= 0 && gFormTerrain) {
            char sq[1300]; size_t at = 0; int n = 0, fg = 0;
            sq[0] = 0;
            for (int x = gFormCx - gFormR; x <= gFormCx + gFormR; ++x)
                for (int y = gFormCy - gFormR; y <= gFormCy + gFormR; ++y)
                    if (mp->InBounds(x, y) && at < sizeof(sq) - 16) {
                        /* a square the cast changed: its terrain is the effect's and was not before, or a feature of the effect stands on it (trees) */
                        Feature *ft = mp->FFeatureAt((int16)x, (int16)y);
                        const bool terra = mp->TerrainAt(x, y) == gFormTerrain && terBefore[x][y] != gFormTerrain;
                        const bool feat = ft && ft->fID == gFormTerrain;
                        if (!terra && !feat) continue;
                        at += (size_t)snprintf(sq + at, sizeof(sq) - at, "%s%d,%d", n ? ";" : "", x, y);
                        if (!n) fg = feat ? (int)GLYPH_ID_VALUE(ft->Image) : (int)GLYPH_ID_VALUE(mp->At(x, y).Glyph);
                        ++n;
                    }
            Error("REEL_FORMATION_FINAL %s n %d glyph %d sq %s", nm, n, fg, sq);
        }
        Silence = 0;
        EffectStepHook = NULL; EffectLightHook = NULL; TargetFlashHook = NULL; BallRingHook = NULL; GlobeGlyphHook = NULL; FormationHook = NULL;
        MotionHook = NULL; SporeHook = NULL; WallSweepHook = NULL; gSweepPl = NULL;
        Error("REEL_HOOKS %s light-steps %d with-flash %d target-flashes %d", nm, gElLit, gElLitFlash, gTfLit);
        if (isSkull) {
            ScriptLightTickHook = NULL; ScriptLightEndHook = NULL;
            Error("REEL_SKULL trap (%d,%d): steps %d, lit steps %d, first %.0f ms, last %.0f ms, end hook calls %d, flashes left %d",
                  gSkX, gSkY, gSkTicks, gSkLitTicks, gSkFirst, gSkLast, gSkEnds, (int)LightFlashCount());
        }
        pl->mHP = pl->cHP = 30000;
        pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
        Error("REEL_HP %s kobold hp %d/%d %d/%d %d/%d", nm, (int)ks[0]->cHP, (int)hp0[0], (int)ks[1]->cHP, (int)hp0[1], (int)ks[2]->cHP, (int)hp0[2]);
        /* inc-jw0hw: what the scene's content did (tools/check_effect_reel_scenes.sh reads these lines). */
        if (isUndeath || isHoly || isChain) {
            int placed = (int)exm.size(), changed = 0, dead = 0;
            for (size_t i = 0; i < exm.size(); ++i) {
                if (exm[i]->isDead()) { ++dead; ++changed; }
                else if ((int)exm[i]->cHP < exhp[i]) ++changed;
            }
            if (isChain)   /* the three kobolds every clip has are targets too */
                for (int k = 0; k < 3; ++k) {
                    ++placed;
                    if (ks[k]->isDead()) { ++dead; ++changed; }
                    else if (ks[k]->cHP < hp0[k]) ++changed;
                }
            Error("REEL_SCENE %s targets %d struck %d dead %d", nm, placed, changed, dead);
        }
        if (isRaise || isAnimate) {
            Thing *t; int idx, left = 0, made = 0, itemsLeft = 0;
            std::string raisedSq;
            MapIterate(mp, t, idx)
                if (t->isType(T_CORPSE)) ++left;
                else if (t->isItem() && !((Item *)t)->Owner()) {
                    ++itemsLeft;
                    Error("REEL_ITEM %s left %s at %d,%d", nm, (const char *)t->Name(), (int)t->x, (int)t->y);
                }
                else if (t->isCreature() && t != pl && t != ks[0] && t != ks[1] && t != ks[2]) {
                    if (isRaise) {
                        ++made;
                        char b[24]; snprintf(b, sizeof b, "%s%d,%d", raisedSq.empty() ? "" : ";", (int)t->x, (int)t->y); raisedSq += b;
                    }
                    else if (strstr(NAME(((Creature *)t)->mID), "animated")) {
                        ++made;
                        Error("REEL_ITEM %s animated %s at %d,%d", nm, NAME(((Creature *)t)->mID), (int)t->x, (int)t->y);
                    }
                }
            if (isRaise) {
                Error("REEL_SCENE %s corpses %d left %d raised %d", nm, corpseCount, left, made);
                Error("REEL_RAISED %s sq %s", nm, raisedSq.c_str());
            }
            else Error("REEL_SCENE %s floor-items %d held-items %d floor-items-left %d animated %d", nm, floorItems, heldItems, itemsLeft, made);
        }
        if (isFumes) {
            int found = 0;
            for (int i = 0; mp->Fields[i]; ++i) {
                const Field *f = mp->Fields[i];
                Error("REEL_FIELD %s %s center %d,%d radius %d creator %s", nm, NAME(f->eID), (int)f->cx, (int)f->cy, (int)f->rad,
                      isValidHandle(f->Creator) ? NAME(oCreature(f->Creator)->mID) : "none");
                ++found;
            }
            Error("REEL_SCENE %s fields %d thunderbeast %d at %d,%d player %d,%d", nm, found, tb ? 1 : 0, tb ? (int)tb->x : -1, tb ? (int)tb->y : -1, (int)pl->x, (int)pl->y);
        }
        {   /* what the effect left behind: statuses on each kobold and the player, and changed terrain */
            auto stLog = [&](Creature *c, const char *who) {
                std::string l;
                StatiIter(c)
                    if (S->Source == SS_RACE || S->Source == SS_CLAS || S->Source == SS_ITEM || S->Source == SS_BODY || S->Nature == HUNGER) continue;
                    l += std::string(l.empty() ? "" : ",") + Lookup(STATI_CONSTNAMES, S->Nature);
                StatiIterEnd(c)
                if (!l.empty()) Error("REEL_STATI %s %s %s", nm, who, l.c_str());
            };
            stLog(pl, "player"); stLog(ks[0], "kobold0"); stLog(ks[1], "kobold1"); stLog(ks[2], "kobold2");
            int changed = 0, fx = -1, fy = -1;
            for (int y = 0; y < 40 && y < mp->SizeY(); ++y)
                for (int x = 0; x < 64 && x < mp->SizeX(); ++x)
                    if (terBefore[x][y] != mp->TerrainAt(x, y)) { if (!changed) { fx = x; fy = y; } ++changed; }
            if (changed) Error("REEL_TERRAIN %s changed %d squares, first (%d,%d) %s -> %s", nm, changed, fx, fy, NAME(terBefore[fx][fy]), NAME(mp->TerrainAt(fx, fy)));
            if (isFeast) Error("REEL_FEAST turn %d (start %d) kobold hp %d %d %d", (int)theGame->Turn, (int)gTurn0, (int)ks[0]->cHP, (int)ks[1]->cHP, (int)ks[2]->cHP);
        }
        ViewLog(pl, nm, "after-cast");
        for (int k = 0; k < 3; ++k) { gPaintX[k] = ks[k]->x; gPaintY[k] = ks[k]->y; gPaintRem[k] = -1; }
        memset(gSqPaint, -1, sizeof gSqPaint);
        PutGlyphProbeHook = PaintHook;
        Refresh(pl);
        PutGlyphProbeHook = NULL;
        ViewLog(pl, nm, "after-refresh");
        if (en.form == 's') {
            int lit = 0, fog = 0; LightRGB fc;
            for (int y = mid->y - 3; y <= mid->y + 3; ++y)
                for (int x = mid->x - 3; x <= mid->x + 3; ++x)
                    if ((x - mid->x) * (x - mid->x) + (y - mid->y) * (y - mid->y) <= 9) {
                        if (LightLitAt((int16)x, (int16)y)) ++lit;
                        if (LightFogAt((int16)x, (int16)y, fc)) ++fog;
                    }
            Error("REEL_LIGHT %s after-cast lit-squares %d fog-squares %d", nm, lit, fog);
            pl->CalcVision();
            smokeLog("after");
        }
        pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
        /* inc-jw0hw (Phase 4h): a clip whose effect leaves creatures glowing holds 2 s, as an aura does, so the glow flickers on the recording. */
        bool leavesGlow = te->ef.eval == EA_INFLICT && te->ef.xval == ILLUMINATED;   /* the first component is te->ef; Vals(1) on are the later ones */
        for (int8 v = 1; te->Vals(v); ++v)
            if (te->Vals(v)->eval == EA_INFLICT && te->Vals(v)->xval == ILLUMINATED) leavesGlow = true;
        auto glowLog = [&](const char *when) {
            if (!leavesGlow) return;
            for (int k = 0; k < 3; ++k) {
                LightRGB c = { 0, 0, 0 }; const bool got = LightAt(ks[k]->x, ks[k]->y, c);
                Status *st = ks[k]->GetStati(ILLUMINATED);
                Error("REEL_GLOW %s kobold %d stati %d val %d light %d,%d,%d (%d) lit %d seen %d level %d painted-remembered %d", when, k, st ? 1 : 0, st ? (int)st->Val : -1,
                    (int)c.r, (int)c.g, (int)c.b, got ? 1 : 0, LightLitAt(ks[k]->x, ks[k]->y) ? 1 : 0,
                    (mp->At(ks[k]->x, ks[k]->y).Visibility & VI_VISIBLE) ? 1 : 0, (int)LightLevelAt(ks[k]->x, ks[k]->y), gPaintRem[k]);
            }
        };
        glowLog("after-cast");
        if (te->ef.aval == AR_BARRIER && te->ef.eval == EA_TERRAFORM && EffectLightDecide(te, 0).lit) {
            int n = 0, lit = 0;
            for (int y = RY0; y <= RY1; ++y)
                for (int x = RX0; x <= RX1; ++x)
                    if (mp->TerrainAt(x, y) == te->ef.rval) { ++n; if (LightLitAt((int16)x, (int16)y)) ++lit; }
            Error("REEL_WALLLIGHT %s after-cast squares %d lit %d standing %d", nm, n, lit, StandingWallCount());
        }
        const int idleMs = en.kind[0] == 'a' || leavesGlow || en.form == 's' ? 2000 : 700;
        Error("REEL_IDLE %s %d", nm, idleMs);
        pl->MyTerm->StopWatch(idleMs);
        glowLog("after-idle");
        /* inc-jw0hw (Phase 5): a wall of terrain whose effect glows lights its squares while it stands: count the lit wall squares after the
           cast and after the idle, then take the wall down and count again. A square is a wall square when it holds the effect's terrain. */
        if (te->ef.aval == AR_BARRIER && te->ef.eval == EA_TERRAFORM && EffectLightDecide(te, 0).lit) {
            std::vector<int> wx, wy;
            for (int y = RY0; y <= RY1; ++y)
                for (int x = RX0; x <= RX1; ++x)
                    if (mp->TerrainAt(x, y) == te->ef.rval) { wx.push_back(x); wy.push_back(y); }
            int lit = 0;
            for (size_t k = 0; k < wx.size(); ++k) if (LightLitAt((int16)wx[k], (int16)wy[k])) ++lit;
            Error("REEL_WALLLIGHT %s after-idle squares %d lit %d standing %d", nm, (int)wx.size(), lit, StandingWallCount());
            /* inc-jw0hw (Phase 5c): INCURSION_WALL_SAVE leaves the wall standing and ends the probe, so the key script can save the
               level with the wall in it (tools/check_effect_motion.sh stage W3 loads that save in a second run). */
            if (getenv("INCURSION_WALL_SAVE")) {
                Error("REEL_WALLSAVE squares %d lit %d standing %d", (int)wx.size(), lit, StandingWallCount());
                pl->LightRange = wasLight; pl->InfraRange = wasInfra; pl->ShadowRange = wasShadow;
                pl->mHP = wasMax; pl->cHP = wasHP; pl->cFP = wasFP;
                pl->Options[OPT_ANIMATION] = wasAnim;
                pl->Options[OPT_AUTOMORE] = wasMore;
                theGame->PlayMode = wasPlay;
                return;
            }
            /* inc-jw0hw (Phase 5b): a load and a level entry both call Term::SetMap (Registry.cpp, Display.cpp), which forgets every
               standing light. The next repaint must find the wall in the map and light it again. */
            pl->MyTerm->SetMap(mp);
            Error("REEL_WALLLIGHT %s after-reset squares %d lit %d standing %d", nm, (int)wx.size(), 0, StandingWallCount());
            Refresh(pl);
            int litRe = 0;
            for (size_t k = 0; k < wx.size(); ++k) if (LightLitAt((int16)wx[k], (int16)wy[k])) ++litRe;
            Error("REEL_WALLLIGHT %s after-reload squares %d lit %d standing %d", nm, (int)wx.size(), litRe, StandingWallCount());
            for (size_t k = 0; k < wx.size(); ++k) PutTerrain(mp, floor, wx[k], wy[k]);
            Refresh(pl);
            int litAfter = 0;
            for (size_t k = 0; k < wx.size(); ++k) if (LightLitAt((int16)wx[k], (int16)wy[k])) ++litAfter;
            Error("REEL_WALLLIGHT %s wall-down squares %d lit %d standing %d", nm, (int)wx.size(), litAfter, StandingWallCount());
        }
        /* inc-jw0hw (Phase 5b): the dance lasts the whole status. After the idle, one turn passes at a time (every creature's statuses
           count down once), the map repaints as it does when the game waits for a key, and each turn logs the creatures that hold
           the status (found here, with HasEffStati) beside the squares the motion set holds. The clip runs on for 0.6 s a turn, so
           the recording shows the dance between casts and keypresses, until the last dancer stops. */
        if (isDance)   /* inc-jw0hw (Phase 6b): the caster is not affected: no Dancing status, no dance motion on his square */
            Error("REEL_DANCE_CASTER %s at %d,%d status %d", nm, (int)pl->x, (int)pl->y, pl->HasEffStati(ADJUST_CIRC, en.id, A_DEF) ? 1 : 0);
        if (isDance) {
            Silence = 1;   /* "You stop dancing" prints nothing: the text terminal would wait for a key */
            for (int turn = 0; turn < 14; ++turn) {
                std::string want, got; int nWant = 0;
                Thing *t; int ti;
                MapIterate(mp, t, ti) {
                    if (!t->isCreature() || t->x < 0 || ((Creature *)t)->isDead() || !((Creature *)t)->HasEffStati(ADJUST_CIRC, en.id, A_DEF)) continue;
                    if (!(mp->At(t->x, t->y).Visibility & VI_VISIBLE)) continue;
                    char b[24]; snprintf(b, sizeof b, "%s%d,%d", nWant ? ";" : "", (int)t->x, (int)t->y); want += b; ++nWant;
                }
                Refresh(pl);
                for (int i = 0; i < MotionCount(); ++i) {
                    int16 mx, my; uint8 md;
                    if (!MotionSquare(i, mx, my, md)) continue;
                    char b[24]; snprintf(b, sizeof b, "%s%d,%d,%d", i ? ";" : "", (int)mx, (int)my, (int)md); got += b;
                }
                Error("REEL_DANCE_TURN %s turn %d want %d %s got %d %s", nm, turn, nWant, want.c_str(), MotionCount(), got.c_str());
                pl->MyTerm->StopWatch(600);
                if (!nWant) break;
                MapIterate(mp, t, ti) if (t->isCreature()) t->UpdateStati();
            }
            Silence = 0;
        }
        ViewLog(pl, nm, "after-idle");
    }
    TEFF(breath)->ef.aval = AR_BREATH;   /* inc-epzc0 */
    WeaponReel(pl, mp, floor, wall, only, table, count);
    Error("REEL_DONE %d", count);

    LightFlashClearAll();
    BuildRoom(mp, pl, floor, wall, false);
    pl->LightRange = wasLight; pl->InfraRange = wasInfra; pl->ShadowRange = wasShadow;
    pl->mHP = wasMax; pl->cHP = wasHP; pl->cFP = wasFP;
    pl->Options[OPT_ANIMATION] = wasAnim;
    pl->Options[OPT_AUTOMORE] = wasMore;
    theGame->PlayMode = wasPlay;
}
