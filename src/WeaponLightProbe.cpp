/* inc-as123: opt-in probe for the light a held weapon gives. Off unless
   INCURSION_WEAPON_LIGHT_PROBE is set. Called from Game::Play (src/Main.cpp);
   graded by tools/check_weapon_light.sh. It builds a dark room, clears every
   thing but the player, strips the player's light and weapons, then holds one
   weapon at a time and logs the light map's color on the squares east of the
   holder, one WEAPON_LIGHT line per case. The check grades the lines.
   Phase 2 (inc-as123): then, one WEAPON_FLASH line per weapon-hit case. Each case calls Weapon::QualityDmgSingle on a
   victim with a forced crit flag and a forced save roll, and samples the light map from TargetFlashHook, while the flash shows.
   Phase 3 (inc-as123): then, one WEAPON_FLIGHT line per thrown or fired case. The player throws or fires through Throw(EV_RATTACK) with a
   forced attack roll, and the light map is sampled at each flight step (EffectStepHook ES_FLIGHT, which the flight issues after its light
   moves: the effect's own clock, no wall clock) and at the impact flash (TargetFlashHook). */
#include <stdarg.h>
#define protected public   /* Item::Plus, as EffectLightProbe does for TextTerm */
#include "Incursion.h"
#undef protected
#include "Light.h"
#include "EffectLight.h"

extern bool isExchange;
extern void LOFSetForcedRoll(int8 r);
extern void LOFSetForcedSaveThrowRoll(int8 r);
extern void LOFClearForcedSaveThrowRoll();
extern void (*TargetFlashHook)(int phase);   /* src/Inv.cpp: set, it answers the two-handed prompt without a key */

namespace {

// no-family
const int PX = 6, PY = 17;   /* the player's square in every case */
const int ROW = 9;           /* squares logged from the source east */
// end no-family

bool InBlock(int x, int y) { return x >= 4 && x <= 38 && y >= 5 && y <= 29; }

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
            mp->WriteAt(rect, x, y, InBlock(x, y) ? floor : wall, region, PRIO_MAX, true);
            mp->At(x, y).Lit = false;
            mp->At(x, y).Bright = false;
            mp->At(x, y).Dark = false;
        }
    pl->CalcVision();
}

void Refresh(Player *pl) {
    pl->CalcValues();
    pl->InfraRange = pl->ShadowRange = 0;   /* the player's infravision and shadow sight light nothing here */
    pl->MyTerm->AdjustMap(pl->x, pl->y, true);
    pl->UpdateMap = 1;
    pl->MyTerm->ShowMap();
}

/* Take the item out of its slot and delete it. */
void Strip(Creature *c, int slot) {
    Item *it = c->InSlot(slot);
    if (!it) return;
    EventInfo t; t.Clear(); t.EActor = c; t.EItem = it; t.EParam = slot;
    SetSilence();
    c->TakeOff(t);
    UnsetSilence();
    it->Remove(true);
}

/* eff: a weapon effect the game builds the item from (Item::Initialize applies its base item and qualities). */
Item *Hold(Creature *c, const char *base, int slot, int quality, int plus, const char *eff = NULL) {
    Item *it = Item::Create(FIND(base));
    if (!it) { Error("WEAPON_LIGHT: INCONCLUSIVE -- no item %s", base); return NULL; }
    if (eff) {
        it->eID = FIND(eff);
        if (!it->eID) { Error("WEAPON_LIGHT: INCONCLUSIVE -- no effect %s", eff); return NULL; }
        it->Initialize(false);
    }
    if (plus >= 0) it->Plus = (int8)plus;
    if (quality >= 0)
        it->GainPermStati(EXTRA_QUALITY, c, SS_MISC, (int16)quality, 0, 0);
    const bool wasPlay = theGame->PlayMode;
    if (!c->isPlayer()) {   /* a monster's slot is read off its inventory list; out of play, an opposed alignment drains no levels */
        theGame->PlayMode = false;
        it->Remove(false);
        c->GainItem(it, true);
    }
    SetSilence();
    isExchange = true;
    if (c->InSlot(slot) != it)
        ThrowVal(EV_WIELD, slot, c, NULL, it);
    isExchange = false;
    UnsetSilence();
    theGame->PlayMode = wasPlay;
    c->CalcValues();
    if (c->InSlot(slot) != it)
        Error("WEAPON_LIGHT: INCONCLUSIVE -- %s did not go into slot %d", base, slot);
    return c->InSlot(slot) == it ? it : NULL;
}

void Dump(const char *tag, int cx, int cy, Creature *holder, const char *extra) {
    char buf[600]; int n = 0;
    for (int d = 0; d < ROW; ++d) {
        LightRGB c = { 0, 0, 0 };
        LightAt((int16)(cx + d), (int16)cy, c);
        n += snprintf(buf + n, sizeof buf - n, " %d,%d,%d", c.r, c.g, c.b);
    }
    Item *hw = holder->InSlot(SL_WEAPON);
    Error("WEAPON_LIGHT: CASE %s lightrange=%d heldradius=%d row=%s %s weapon=[%s]", tag, (int)holder->LightRange, hw ? (int)LightHeldRadius(holder, hw) : -1, buf, extra, hw ? NAME(hw->iID) : "-");
}

void StripAll(Player *pl) {
    Strip(pl, SL_LIGHT); Strip(pl, SL_WEAPON); Strip(pl, SL_READY);
}


/* inc-as123 phase 2: the weapon-hit flash cases. */
// no-family
enum { K_ANY, K_GOOD, K_EVIL, K_LAWFUL, K_CHAOTIC, K_NEUTRAL, K_UNDEAD };   /* not a code: a probe-local case index, never read outside this file */
const int FROW = 6;           /* squares logged east of the victim */
// end no-family
int gVX, gVY, gHookCalls, gHookRow[FROW], gHookStray, gHookVar, gHookLit;
LightRGB gHookC[FROW];
LightRGB gRefC[FROW];
int gRefVar;

int Peak(int x, int y) {
    LightRGB c = { 0, 0, 0 };
    LightAt((int16)x, (int16)y, c);
    return c.r > c.g ? (c.r > c.b ? c.r : c.b) : (c.g > c.b ? c.g : c.b);
}

int LitCount(Map *mp) {
    int n = 0;
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x)
            if (LightLitAt((int16)x, (int16)y)) ++n;
    return n;
}

/* inc-as123: the floor and wall the probe builds with, and a full-height wall column that hides everything east of it from the player. */
rID gFloor, gWall;
int gSeenLit;   /* the most lit squares the player has line of sight to, at any hook call of the case */

void SetWall(Map *mp, Player *pl, int x, bool on) {
    const rID region = mp->RegionAt(pl->x, pl->y);
    Rect rect(0, 0, mp->SizeX() - 1, mp->SizeY() - 1);
    for (int y = 5; y <= 29; ++y) {
        mp->WriteAt(rect, x, y, on ? gWall : gFloor, region, PRIO_MAX, true);
        mp->At(x, y).Lit = false;
        mp->At(x, y).Bright = false;
        mp->At(x, y).Dark = false;
    }
    pl->CalcVision();
}

/* lit squares the player has line of sight to, now; noted into gSeenLit. */
void NoteSeenLit(Player *pl) {
    int n = 0;
    for (int y = 0; y < pl->m->SizeY(); ++y)
        for (int x = 0; x < pl->m->SizeX(); ++x)
            if (LightLitAt((int16)x, (int16)y) && pl->m->LineOfSight(pl->x, pl->y, x, y, pl)) ++n;
    if (n > gSeenLit) gSeenLit = n;
}

/* squares of the band x0..x1, PY-1..PY+1 that the player has line of sight to */
int SeenBand(Player *pl, int x0, int x1) {
    int n = 0;
    for (int y = PY - 1; y <= PY + 1; ++y)
        for (int x = x0; x <= x1; ++x)
            if (pl->m->LineOfSight(pl->x, pl->y, x, y, pl)) ++n;
    return n;
}

/* At TF_LIT: the flash shows at age 0. Log its squares, the lit squares more than 3 from the victim, and how much the victim's
   square changes over 31 ticks (a steady flash does not change). */
void FlashHook(int phase) {
    if (phase != TF_LIT) return;
    ++gHookCalls;
    Player *pl = theGame->GetPlayer(0);
    NoteSeenLit(pl);
    for (int d = 0; d < FROW; ++d) {
        LightRGB c = { 0, 0, 0 };
        LightAt((int16)(gVX + d), (int16)gVY, c);
        gHookC[d] = c;
    }
    gHookStray = 0; gHookLit = 0;
    for (int y = 0; y < pl->m->SizeY(); ++y)
        for (int x = 0; x < pl->m->SizeX(); ++x)
            if (LightLitAt((int16)x, (int16)y)) {
                ++gHookLit;
                const int dx = x > gVX ? x - gVX : gVX - x, dy = y > gVY ? y - gVY : gVY - y;
                if ((dx > dy ? dx : dy) > 3) ++gHookStray;
            }
    int lo = 999, hi = 0;
    for (int t = 0; t <= 3000; t += 100) {
        LightTick((uint32)t);
        const int v = Peak(gVX, gVY);
        if (v < lo) lo = v;
        if (v > hi) hi = v;
    }
    LightTick(0);
    gHookVar = hi - lo;
}

bool TFits(TMonster &t, rID rid, int kind) {
    switch (kind) {
        case K_GOOD: return t.isMType(rid, MA_GOOD);
        case K_EVIL: return t.isMType(rid, MA_EVIL);
        case K_LAWFUL: return t.isMType(rid, MA_LAWFUL);
        case K_CHAOTIC: return t.isMType(rid, MA_CHAOTIC);
        case K_NEUTRAL: return t.isMType(rid, MA_NEUTRAL);
        case K_UNDEAD: return t.isMType(rid, MA_UNDEAD);
    }
    return true;
}

bool CFits(Creature *c, int kind) {
    switch (kind) {
        case K_GOOD: return c->isMType(MA_GOOD);
        case K_EVIL: return c->isMType(MA_EVIL);
        case K_LAWFUL: return c->isMType(MA_LAWFUL);
        case K_CHAOTIC: return c->isMType(MA_CHAOTIC);
        case K_NEUTRAL: return c->isMType(MA_NEUTRAL) && !c->isMType(MA_GOOD) && !c->isMType(MA_EVIL) && !c->isMType(MA_LAWFUL) && !c->isMType(MA_CHAOTIC);
        case K_UNDEAD: return c->isMType(MA_UNDEAD);
    }
    return true;
}

/* The first generated monster of the kind that gives no light of its own where it stands, placed at (x, y); NULL when none. */
Monster *Spawn(Map *mp, Player *pl, int kind, int x, int y) {
    Module *mod = theGame->Modules[0];
    int tries = 0;
    for (int idx = 0; idx < mod->szMon && tries < 80; ++idx) {
        TMonster &t = mod->QMon[idx];
        if (t.HasFlag(M_NOGEN) || !TFits(t, mod->MonsterID((uint16)idx), kind)) continue;
        Monster *m = new Monster(mod->MonsterID((uint16)idx));
        m->mHP = m->cHP = 500;
        m->CalcValues();
        if (!CFits(m, kind)) { delete m; continue; }
        ++tries;
        m->PlaceAt(mp, x, y, true);
        Refresh(pl);
        if (LitCount(mp) == 0) return m;
        m->Remove(true);
    }
    return NULL;
}

/* One hit: a weapon with quality q (and WQ_BURST when `burst`) strikes a victim of kind vk for an actor of kind ak. roll: the forced
   save roll, 0 for none. */
void FlashCase(Map *mp, Player *pl, const char *tag, int q, bool burst, bool crit, int ak, int vk, int roll,
               int refCol, int refReach, int refStyle, bool hide = false) {
    const int VX = PX + 14, VY = PY, AX = PX + 20, AY = PY + 6;
    gSeenLit = 0;
    if (hide) SetWall(mp, pl, PX + 7, true);
    gVX = VX; gVY = VY; gHookCalls = 0; gHookStray = 0; gHookVar = 0; gHookLit = 0;
    for (int d = 0; d < FROW; ++d) { LightRGB z = { 0, 0, 0 }; gHookC[d] = z; }
    Monster *a = Spawn(mp, pl, ak, AX, AY);
    Monster *v = a ? Spawn(mp, pl, vk, VX, VY) : NULL;
    Item *it = Item::Create(FIND("long sword"));
    if (!a || !v || !it) {
        Error("WEAPON_FLASH: INCONCLUSIVE -- case %s: actor %p victim %p item %p", tag, (void *)a, (void *)v, (void *)it);
        if (hide) SetWall(mp, pl, PX + 7, false);
        return;
    }
    it->GainPermStati(EXTRA_QUALITY, pl, SS_MISC, (int16)q, 0, 0);
    if (burst) it->GainPermStati(EXTRA_QUALITY, pl, SS_MISC, (int16)WQ_BURST, 0, 0);
    Refresh(pl);
    const int base = LitCount(mp);
    const hObj vh = v->myHandle;
    /* The reference: the same victim struck by the flash the case should make, named here in color, reach and style. */
    for (int d = 0; d < FROW; ++d) { LightRGB z = { 0, 0, 0 }; gRefC[d] = z; }
    gRefVar = 0;
    if (refCol) {
        Thing *rt = v;
        TargetFlashHook = FlashHook;
        EffectLight::FlashStruck(mp, (int16)refCol, EL_AREA, 0, NULL, &rt, 1, (int16)refReach, refStyle);
        TargetFlashHook = NULL;
        for (int d = 0; d < FROW; ++d) gRefC[d] = gHookC[d];
        gRefVar = gHookVar;
        gHookCalls = 0; gHookStray = 0; gHookVar = 0; gHookLit = 0;
        for (int d = 0; d < FROW; ++d) { LightRGB z = { 0, 0, 0 }; gHookC[d] = z; }
    }
    EventInfo e; e.Clear();
    e.EActor = a; e.EVictim = v; e.ETarget = v; e.EItem = it;
    e.isCrit = crit; e.vDmg = 10;
    if (roll) LOFSetForcedSaveThrowRoll((int8)roll);
    TargetFlashHook = FlashHook;
    SetSilence();
    ((Weapon *)it)->QualityDmgSingle(e, q);
    UnsetSilence();
    TargetFlashHook = NULL;
    LOFClearForcedSaveThrowRoll();
    Creature *vv = oCreature(vh);
    const int died = (!vv || vv->isDead()) ? 1 : 0;
    const int vis = SeenBand(pl, VX - 1, VX + 1);
    Refresh(pl);
    const int after = LitCount(mp);
    char buf[400]; int n = 0;
    for (int d = 0; d < FROW; ++d)
        n += snprintf(buf + n, sizeof buf - n, " %d,%d,%d", gHookC[d].r, gHookC[d].g, gHookC[d].b);
    char rbuf[400]; int rn = 0;
    for (int d = 0; d < FROW; ++d)
        rn += snprintf(rbuf + rn, sizeof rbuf - rn, " %d,%d,%d", gRefC[d].r, gRefC[d].g, gRefC[d].b);
    Error("WEAPON_FLASH: CASE %s calls=%d row=%s stray=%d var=%d lit=%d base=%d after=%d xdmg=%d died=%d refvar=%d ref=%s seen=%d vis=%d", tag, gHookCalls, buf, gHookStray, gHookVar, gHookLit, base, after, (int)e.xDmg, died, gRefVar, rbuf, gSeenLit, vis);
    it->Remove(true);
    if (oCreature(vh)) oCreature(vh)->Remove(true);
    a->Remove(true);
    if (hide) SetWall(mp, pl, PX + 7, false);
}

/* inc-as123 phase 3: a thrown or fired weapon's flight. One record per flight step. */
// no-family
const int MAXSTEP = 40;
// end no-family
struct FStep { int x, y, lit, stray; LightRGB c, nc; };   /* c: the missile's square; nc: the square below it */
FStep gSteps[MAXSTEP];
int gNSteps, gStepVar;

/* At each ES_FLIGHT the light has just moved: the lit squares, the ones more than 1 from the missile, and (at step 3) how much the
   missile's own square changes over 31 ticks of the light clock (a steady light does not change). */
void FlightHook(int kind, int16 x, int16 y, Glyph) {
    if (kind != ES_FLIGHT || gNSteps >= MAXSTEP) return;
    Player *pl = theGame->GetPlayer(0);
    NoteSeenLit(pl);
    FStep &s = gSteps[gNSteps++];
    s.x = x; s.y = y; s.lit = 0; s.stray = 0;
    s.c.r = s.c.g = s.c.b = 0;
    s.nc = s.c;
    LightAt(x, y, s.c);
    LightAt(x, (int16)(y + 1), s.nc);
    for (int yy = 0; yy < pl->m->SizeY(); ++yy)
        for (int xx = 0; xx < pl->m->SizeX(); ++xx)
            if (LightLitAt((int16)xx, (int16)yy)) {
                ++s.lit;
                const int dx = xx > x ? xx - x : x - xx, dy = yy > y ? yy - y : y - yy;
                if ((dx > dy ? dx : dy) > 1) ++s.stray;
            }
    if (gNSteps == 3) {
        int lo = 999, hi = 0;
        for (int t = 0; t <= 3000; t += 100) {
            LightTick((uint32)t);
            const int v = Peak(x, y);
            if (v < lo) lo = v;
            if (v > hi) hi = v;
        }
        LightTick(0);
        gStepVar = hi - lo;
    }
}

/* One shot. missile/mq: the item thrown or fired and the extra quality it carries (-1 none); launcher/lq likewise (launcher NULL: a
   throw). roll: the forced attack roll, 20 hits and 1 misses. aimEmpty: aim at an empty square, no creature there. */
void FlightCase(Map *mp, Player *pl, rID kob, const char *tag, const char *missile, int mq, const char *launcher, int lq, int roll,
                bool aimEmpty) {
    const int TX = PX + 10, TY = PY;
    gVX = TX; gVY = TY; gHookCalls = 0; gHookStray = 0; gHookVar = 0; gHookLit = 0; gNSteps = 0; gStepVar = 0;
    for (int d = 0; d < FROW; ++d) { LightRGB z = { 0, 0, 0 }; gHookC[d] = z; }
    Monster *v = NULL;
    if (!aimEmpty) {
        v = Spawn(mp, pl, K_ANY, TX, TY);   /* the first generated monster that lights no square, as the flash cases take */
        if (v) { v->mHP = v->cHP = 500; }
    }
    /* the launcher is not wielded: a held bow in the weapon slots would light the shooter, and RAttack reads only the item it is given */
    Item *bow = launcher ? Item::Create(FIND(launcher)) : NULL;
    if (bow && lq >= 0) bow->GainPermStati(EXTRA_QUALITY, pl, SS_MISC, (int16)lq, 0, 0);
    Item *it = Item::Create(FIND(missile));
    if (!it || (launcher && !bow) || (!aimEmpty && !v)) {
        Error("WEAPON_FLIGHT: INCONCLUSIVE -- case %s: missile %p launcher %p victim %p", tag, (void *)it, (void *)bow, (void *)v);
        return;
    }
    if (mq >= 0) it->GainPermStati(EXTRA_QUALITY, pl, SS_MISC, (int16)mq, 0, 0);
    /* True sight sees the victim in the dark without lighting a square, so no 50% miss chance against an unseen victim decides the hit. */
    pl->GainPermStati(TRUE_SIGHT, pl, SS_MISC, 30, 0, 0);
    pl->CalcVision();
    Refresh(pl);
    const int base = LitCount(mp);
    const int hp0 = v ? (int)v->cHP : 0;
    LOFSetForcedRoll((int8)roll);
    EffectStepHook = FlightHook;
    TargetFlashHook = FlashHook;
    SetSilence();
    if (aimEmpty) ThrowXY(EV_RATTACK, TX, TY, pl, NULL, NULL, it);
    else Throw(EV_RATTACK, pl, v, bow, it);
    UnsetSilence();
    EffectStepHook = NULL;
    TargetFlashHook = NULL;
    LOFSetForcedRoll(0);
    const int hit = v && (int)v->cHP < hp0 ? 1 : 0;
    Refresh(pl);
    const int after = LitCount(mp);
    char buf[MAXSTEP * 40]; int n = 0;
    for (int i = 0; i < gNSteps; ++i)
        n += snprintf(buf + n, sizeof buf - n, " %d:%d:%d:%d:%d,%d,%d:%d,%d,%d", gSteps[i].x, gSteps[i].y, gSteps[i].lit, gSteps[i].stray,
                      gSteps[i].c.r, gSteps[i].c.g, gSteps[i].c.b, gSteps[i].nc.r, gSteps[i].nc.g, gSteps[i].nc.b);
    if (!gNSteps) snprintf(buf, sizeof buf, " none");
    Error("WEAPON_FLIGHT: CASE %s hp=%d>%d victim=[%s] steps=%d hit=%d var=%d calls=%d flashlit=%d fc=%d,%d,%d base=%d after=%d path=%s", tag, hp0, v ? (int)v->cHP : -1, v ? NAME(v->mID) : "-", gNSteps, hit, gStepVar,
          gHookCalls, gHookLit, gHookC[0].r, gHookC[0].g, gHookC[0].b, base, after, buf);
    pl->RemoveStati(TRUE_SIGHT);
    pl->CalcVision();
    if (bow) bow->Remove(true);
    if (v) v->Remove(true);
    for (Thing *obj; ; ) {   /* what landed on the floor goes */
        int index; Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != pl) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
}

/* inc-as123: a shot a monster makes beyond a wall column (wall true) or in the open (wall false). The player stands at PX; the
   thrower at PX+8 throws at the victim at PX+16 (or at that square when aimEmpty). hide: the wall stands at PX+3. */
void HiddenShot(Map *mp, Player *pl, const char *tag, const char *missile, int mq, int roll, bool aimEmpty, bool hide) {
    const int HX = PX + 8, TX = PX + 16;
    gSeenLit = 0; gVX = TX; gVY = PY; gHookCalls = 0; gHookStray = 0; gHookVar = 0; gHookLit = 0; gNSteps = 0; gStepVar = 0;
    for (int d = 0; d < FROW; ++d) { LightRGB z = { 0, 0, 0 }; gHookC[d] = z; }
    if (hide) SetWall(mp, pl, PX + 3, true);
    Monster *a = Spawn(mp, pl, K_ANY, HX, PY);
    Monster *v = (a && !aimEmpty) ? Spawn(mp, pl, K_ANY, TX, PY) : NULL;
    Item *it = Item::Create(FIND(missile));
    if (!a || !it || (!aimEmpty && !v)) {
        Error("WEAPON_HIDDEN: INCONCLUSIVE -- case %s: thrower %p victim %p item %p", tag, (void *)a, (void *)v, (void *)it);
        if (hide) SetWall(mp, pl, PX + 3, false);
        return;
    }
    if (v) v->mHP = v->cHP = 500;
    a->GainPermStati(TRUE_SIGHT, a, SS_MISC, 30, 0, 0);   /* no concealment roll decides the hit */
    a->CalcValues();
    if (mq >= 0) it->GainPermStati(EXTRA_QUALITY, pl, SS_MISC, (int16)mq, 0, 0);
    Refresh(pl);
    const int base = LitCount(mp);
    const int vis = SeenBand(pl, HX - 1, TX + 1);
    const int hp0 = v ? (int)v->cHP : 0;
    LOFSetForcedRoll((int8)roll);
    EffectStepHook = FlightHook;
    TargetFlashHook = FlashHook;
    SetSilence();
    if (aimEmpty) ThrowXY(EV_RATTACK, TX, PY, a, NULL, NULL, it);
    else Throw(EV_RATTACK, a, v, NULL, it);
    UnsetSilence();
    EffectStepHook = NULL;
    TargetFlashHook = NULL;
    LOFSetForcedRoll(0);
    const int hit = v && (int)v->cHP < hp0 ? 1 : 0;
    Refresh(pl);
    const int after = LitCount(mp);
    Error("WEAPON_HIDDEN: CASE %s hit=%d steps=%d calls=%d flashlit=%d seen=%d vis=%d base=%d after=%d", tag, hit, gNSteps, gHookCalls, gHookLit, gSeenLit, vis, base, after);
    for (Thing *obj; ; ) {
        int index; Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != pl) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    if (hide) SetWall(mp, pl, PX + 3, false);
}

}  // namespace

/* inc-as123: the weapon-light probe, run by tools/check_weapon_light.sh. */
void WeaponLightProbe(Player *pl) {
    if (!getenv("INCURSION_WEAPON_LIGHT_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("WEAPON_LIGHT: INCONCLUSIVE -- no live player and map");
        return;
    }
    Map *mp = pl->m;
    const rID floor = FIND("floor"), wall = FIND("dungeon wall"), kob = FIND("hobgoblin");
    gFloor = floor; gWall = wall;
    if (!floor || !wall || !kob || mp->SizeX() < 44 || mp->SizeY() < 34) {
        Error("WEAPON_LIGHT: INCONCLUSIVE -- missing floor, dungeon wall, hobgoblin, or the map is under 44x34");
        return;
    }
    const bool wasPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    pl->Options[OPT_ANIMATION] = 0;
    BuildDark(mp, pl, floor, wall);
    StripAll(pl);
    LightFlashClearAll();
    Item *w;
    char ex[200];

    Refresh(pl);
    Dump("none", PX, PY, pl, "");

    /* a plain long sword, held: the control for every quality case. */
    w = Hold(pl, "long sword", SL_WEAPON, -1, 0);
    Refresh(pl);
    Dump("plain", PX, PY, pl, "");
    Strip(pl, SL_WEAPON);

    /* flaming: lit while held; then dropped on the floor, and then in the pack. */
    w = Hold(pl, "long sword", SL_WEAPON, WQ_FLAMING, 0);
    Refresh(pl);
    Dump("flaming", PX, PY, pl, "");
    if (w) {
        EventInfo t; t.Clear(); t.EActor = pl; t.EItem = w; t.EParam = SL_WEAPON;
        SetSilence(); pl->TakeOff(t); UnsetSilence();
        w->Remove(false);
        w->PlaceAt(mp, PX + 8, PY);
        pl->CalcValues();
        Refresh(pl);
        Dump("flaming-dropped", PX, PY, pl, "");
        w->Remove(true);
    }
    Refresh(pl);

    /* a flame blade and a produced flame carry no quality. */
    w = Hold(pl, "flame blade;weapon", SL_WEAPON, -1, -1);
    Refresh(pl);
    Dump("flame-blade", PX, PY, pl, "");
    Strip(pl, SL_WEAPON);
    w = Hold(pl, "produced flame", SL_WEAPON, -1, -1);
    Refresh(pl);
    Dump("produced-flame", PX, PY, pl, "");
    Strip(pl, SL_WEAPON);

    /* glowing: white, radius plus x 3; then the Sunblade, golden. */
    w = Hold(pl, "long sword", SL_WEAPON, WQ_GLOWING, 2);
    snprintf(ex, sizeof ex, "plus=%d", w ? (int)w->GetPlus() : -99);
    Refresh(pl);
    Dump("glowing", PX, PY, pl, ex);
    Strip(pl, SL_WEAPON);
    w = Hold(pl, "short sword", SL_WEAPON, -1, -1, "Sunblade");
    snprintf(ex, sizeof ex, "plus=%d glowing=%d", w ? (int)w->GetPlus() : -99, w ? (int)w->HasQuality(WQ_GLOWING) : -1);
    Refresh(pl);
    Dump("sunblade", PX, PY, pl, ex);

    /* a torch in the light slot as well: two sources, two colors. */
    Hold(pl, "torch", SL_LIGHT, -1, -1);
    Item *tr = pl->InSlot(SL_LIGHT);
    snprintf(ex, sizeof ex, "torchrange=%d lowlight=%d", tr ? (int)tr->GetLightRange() : -1, (int)pl->AbilityLevel(CA_LOWLIGHT));
    Refresh(pl);
    Dump("torch+sunblade", PX, PY, pl, ex);
    Strip(pl, SL_WEAPON);
    Refresh(pl);
    Dump("torch", PX, PY, pl, ex);
    Strip(pl, SL_LIGHT);

    /* brilliant energy: blue, radius 4. */
    Hold(pl, "long sword", SL_WEAPON, WQ_ENERGY, 0);
    Refresh(pl);
    Dump("energy", PX, PY, pl, "");
    Strip(pl, SL_WEAPON);

    /* a monster (a hobgoblin) holds the rest: the alignment weapons would drain the priest. */
    {
        const int KX = PX + 14;
        Monster *k = new Monster(kob);
        k->mHP = k->cHP = 500;
        k->CalcValues();   /* its size, so the wield size test reads a real value */
        k->PlaceAt(mp, KX, PY, true);
        char tag[60];
        static const int dark[] = { WQ_FROST, WQ_SHOCKING, WQ_THUNDERING, WQ_CORROSIVE, WQ_HOLY, WQ_UNHOLY, WQ_LAWFUL, WQ_CHAOTIC, WQ_SOULDRINK };
        static const char *const darkName[] = { "frost", "shocking", "thundering", "corrosive", "holy", "unholy", "lawful", "chaotic", "soul-drinking" };
        for (size_t i = 0; i < sizeof dark / sizeof dark[0]; ++i) {
            Hold(k, "long sword", SL_WEAPON, dark[i], 0);
            Refresh(pl);
            snprintf(tag, sizeof tag, "dark-%s", darkName[i]);
            Dump(tag, KX, PY, k, "holder=hobgoblin");
            Strip(k, SL_WEAPON);
        }
        /* a monster holding a flaming weapon lights its own square. */
        Hold(k, "long sword", SL_WEAPON, WQ_FLAMING, 0);
        Refresh(pl);
        Dump("monster-flaming", KX, PY, k, "holder=hobgoblin");
        Strip(k, SL_WEAPON);
        /* the Nine Lives Stealer: dark until activated, crimson while the activation's status stands, dark once it is off. */
        Item *nl = Hold(k, "long sword", SL_WEAPON, -1, -1, "Nine Lives Stealer");
        Refresh(pl);
        Dump("nls-inactive", KX, PY, k, "holder=hobgoblin");
        if (nl) {
            k->GainPermStati(EFF_FLAG1, nl, SS_ENCH, 0, 0, FIND("Nine Lives Stealer"), 7);   /* what the activation does */
            k->CalcValues();
            Refresh(pl);
            Dump("nls-active", KX, PY, k, "holder=hobgoblin");
            k->RemoveEffStati(FIND("Nine Lives Stealer"));
            k->CalcValues();
            Refresh(pl);
            Dump("nls-ended", KX, PY, k, "holder=hobgoblin");
        }
    }

    /* inc-as123 phase 2: the light a weapon hit makes on the struck creature. */
    {
        Thing *obj; int index;
        for (;;) {
            Thing *remove = NULL;
            MapIterate(mp, obj, index)
                if (obj != pl) { remove = obj; break; }
            if (!remove) break;
            remove->Remove(true);
        }
        Refresh(pl);
        FlashCase(mp, pl, "flaming", WQ_FLAMING, false, false, K_ANY, K_ANY, 0, COL_FIRE, 1, -1);
        FlashCase(mp, pl, "frost", WQ_FROST, false, false, K_ANY, K_ANY, 0, COL_COLD, 1, -1);
        FlashCase(mp, pl, "shocking", WQ_SHOCKING, false, false, K_ANY, K_ANY, 0, COL_ELEC, 1, -1);
        FlashCase(mp, pl, "soul-drinking", WQ_SOULDRINK, false, false, K_ANY, K_ANY, 0, COL_NECRO, 1, -1);
        FlashCase(mp, pl, "corrosive", WQ_CORROSIVE, false, false, K_ANY, K_ANY, 0, 0, 0, -1);
        FlashCase(mp, pl, "thundering", WQ_THUNDERING, false, false, K_ANY, K_ANY, 0, 0, 0, -1);
        FlashCase(mp, pl, "flaming-burst-nocrit", WQ_FLAMING, true, false, K_ANY, K_ANY, 0, COL_FIRE, 1, -1);
        FlashCase(mp, pl, "flaming-burst-crit", WQ_FLAMING, true, true, K_ANY, K_ANY, 0, COL_FIRE, 2, -1);
        FlashCase(mp, pl, "frost-burst-crit", WQ_FROST, true, true, K_ANY, K_ANY, 0, COL_COLD, 2, -1);
        FlashCase(mp, pl, "corrosive-burst-crit", WQ_CORROSIVE, true, true, K_ANY, K_ANY, 0, 0, 0, -1);
        FlashCase(mp, pl, "thundering-burst-crit", WQ_THUNDERING, true, true, K_ANY, K_ANY, 0, 0, 0, -1);
        FlashCase(mp, pl, "holy", WQ_HOLY, false, false, K_GOOD, K_EVIL, 0, COL_LIGHT, 1, -1);
        FlashCase(mp, pl, "holy-mismatch", WQ_HOLY, false, false, K_GOOD, K_GOOD, 0, 0, 0, -1);
        FlashCase(mp, pl, "lawful", WQ_LAWFUL, false, false, K_LAWFUL, K_CHAOTIC, 0, COL_AZURE, 1, -1);
        FlashCase(mp, pl, "chaotic", WQ_CHAOTIC, false, false, K_CHAOTIC, K_LAWFUL, 0, COL_CRIMSON, 1, LF_FIRE);
        FlashCase(mp, pl, "balance", WQ_BALANCE, false, false, K_NEUTRAL, K_NEUTRAL, 0, COL_SILVERY, 1, -1);
        FlashCase(mp, pl, "unholy", WQ_UNHOLY, false, false, K_EVIL, K_GOOD, 0, COL_NECRO, 1, -1);
        FlashCase(mp, pl, "disruption-failed-save", WQ_DISRUPTION, false, false, K_ANY, K_UNDEAD, 1, COL_LIGHT, 2, -1);
        FlashCase(mp, pl, "disruption-saved", WQ_DISRUPTION, false, false, K_ANY, K_UNDEAD, 20, 0, 0, -1);
        /* inc-as123: the same flaming hit with a wall between the player and the victim, and without it (the control). */
        FlashCase(mp, pl, "flaming-open", WQ_FLAMING, false, false, K_ANY, K_ANY, 0, COL_FIRE, 1, -1, false);
        FlashCase(mp, pl, "flaming-hidden", WQ_FLAMING, false, false, K_ANY, K_ANY, 0, 0, 0, -1, true);
        static const struct { const char *name; int col; } cols[] = {
            { "holy", COL_LIGHT }, { "lawful", COL_AZURE }, { "chaotic", COL_CRIMSON }, { "balance", COL_SILVERY } };
        for (size_t i = 0; i < sizeof cols / sizeof cols[0]; ++i) {
            const LightRGB c = LightEffectColour((int16)cols[i].col);
            Error("WEAPON_FLASH: COLOR %s %d,%d,%d", cols[i].name, c.r, c.g, c.b);
        }
    }
    /* inc-as123 phase 3: thrown and fired weapons light their flight. */
    {
        Thing *obj; int index;
        for (;;) {
            Thing *remove = NULL;
            MapIterate(mp, obj, index)
                if (obj != pl) { remove = obj; break; }
            if (!remove) break;
            remove->Remove(true);
        }
        StripAll(pl);
        Refresh(pl);
        FlightCase(mp, pl, kob, "dagger-flaming-hit", "dagger", WQ_FLAMING, NULL, -1, 20, false);
        FlightCase(mp, pl, kob, "dagger-flaming-miss", "dagger", WQ_FLAMING, NULL, -1, 1, false);
        FlightCase(mp, pl, kob, "dagger-frost-hit", "dagger", WQ_FROST, NULL, -1, 20, false);
        FlightCase(mp, pl, kob, "dagger-plain-hit", "dagger", -1, NULL, -1, 20, false);
        FlightCase(mp, pl, kob, "arrow-flaming-hit", "sheaf arrow", WQ_FLAMING, "short bow", -1, 20, false);
        FlightCase(mp, pl, kob, "arrow-flaming-miss", "sheaf arrow", WQ_FLAMING, "short bow", -1, 1, false);
        FlightCase(mp, pl, kob, "arrow-plain-hit", "sheaf arrow", -1, "short bow", -1, 20, false);
        FlightCase(mp, pl, kob, "arrow-plain-flaming-bow", "sheaf arrow", -1, "short bow", WQ_FLAMING, 20, false);
        FlightCase(mp, pl, kob, "flame-hit", "produced flame", -1, NULL, -1, 20, false);
        FlightCase(mp, pl, kob, "flame-miss", "produced flame", -1, NULL, -1, 1, false);
        FlightCase(mp, pl, kob, "seeds-hit", "fire seeds", -1, NULL, -1, 20, false);
        FlightCase(mp, pl, kob, "seeds-miss", "fire seeds", -1, NULL, -1, 1, false);
        FlightCase(mp, pl, kob, "seeds-empty", "fire seeds", -1, NULL, -1, 1, true);
    }
    /* inc-as123: shots out of the player's sight. */
    {
        Thing *obj; int index;
        for (;;) {
            Thing *remove = NULL;
            MapIterate(mp, obj, index)
                if (obj != pl) { remove = obj; break; }
            if (!remove) break;
            remove->Remove(true);
        }
        StripAll(pl);
        Refresh(pl);
        HiddenShot(mp, pl, "dagger-open", "dagger", WQ_FLAMING, 20, false, false);
        HiddenShot(mp, pl, "dagger-hidden", "dagger", WQ_FLAMING, 20, false, true);
        HiddenShot(mp, pl, "seeds-open", "fire seeds", -1, 20, false, false);
        HiddenShot(mp, pl, "seeds-hidden-hit", "fire seeds", -1, 20, false, true);
        HiddenShot(mp, pl, "seeds-hidden-miss", "fire seeds", -1, 1, false, true);
        HiddenShot(mp, pl, "seeds-hidden-empty", "fire seeds", -1, 1, true, true);
    }
    theGame->PlayMode = wasPlay;
    Error("WEAPON_LIGHT: DONE");
}
