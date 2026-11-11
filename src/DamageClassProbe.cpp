/* inc-kx693: before/after observation of every place the engine decides
   "does this damage type take hit points?" (the sixteen places that ask
   DTypeTakesHP(); before inc-kx693, the `<= 13` number line). Off unless INCURSION_DAMAGE_CLASS_PROBE=1;
   called once from Main.cpp at the start of Game::Play. Writes
   logs/damage-class.log: SETUP_ERROR lines, or 332 lines
   `DC case=<id> type=<n> <field>=<value> ...`.

   Each case stages its inputs in process, calls the REAL production method or
   script handler, and reads the result at the production site through the
   hooks in inc/DamageClassProbe.h. This file holds NO copy of the damage-class
   test, and no hook decides anything. The log must be byte-identical before
   and after the table replaces the tests (tools/check_damage_class.sh). A
   setup that cannot be staged logs SETUP_ERROR and the check fails. */
#include <vector>
#include <algorithm>
#define protected public /* the probe stages Character religion and spell state */
#include "Incursion.h"
#include "DamageClassProbe.h"

/* ---- hook state: the probe sets it, the hooks only read it ---- */
static bool      dcRun = false;
static Creature *dcActor = NULL, *dcVictim = NULL, *dcWatch = NULL;
static Item     *dcItem = NULL;
static rID       dcHRes = 0;
static int       dcHEv = 0, dcType = 0, dcGodNum = -1;
static int       dcSiteHits[DC_SITE_COUNT], dcSiteB[DC_SITE_COUNT], dcSiteV[DC_SITE_COUNT];
static int       dcWatchCalls = 0, dcWatchReq = 0, dcItemCalls = 0,
                 dcHandlerHits = 0, dcGodCalls = 0, dcPenAtSite = 0;

static void DCArm(Creature *actor, Creature *victim, int type)
{
    memset(dcSiteHits, 0, sizeof(dcSiteHits));
    memset(dcSiteB, 0, sizeof(dcSiteB));
    memset(dcSiteV, 0, sizeof(dcSiteV));
    dcWatchCalls = dcWatchReq = dcItemCalls = dcHandlerHits = dcGodCalls = 0;
    dcPenAtSite = 0;
    dcActor = actor; dcVictim = victim; dcType = type;
}

void DamageClassCheckpoint(int site, EventInfo &e)
{
    if (!dcRun || site < 0 || site >= DC_SITE_COUNT) return;
    if (e.EVictim != dcVictim || e.EActor != dcActor || e.DType != dcType) return;
    dcSiteHits[site]++;
    dcSiteB[site] = e.bDmg;
    dcSiteV[site] = e.vDmg;
    if (site == DC_SITE_GOD_AFTER && dcGodNum >= 0 && e.EVictim->isCharacter())
        dcPenAtSite = e.EPVictim->FavPenalty[dcGodNum];
}

void DamageClassDamageEntry(EventInfo &e)
{
    if (!dcRun || !dcWatch) return;
    if (e.EVictim == dcWatch) { dcWatchCalls++; dcWatchReq += e.vDmg; }
}

void DamageClassItemDamage(Item *it)
{
    if (dcRun && it && it == dcItem) dcItemCalls++;
}

void DamageClassHandler(rID xID, EventInfo &e)
{
    if (dcRun && xID == dcHRes && e.Event == dcHEv) dcHandlerHits++;
}

void DamageClassGodEntry(EventInfo &e)
{
    if (dcRun && e.EVictim == dcVictim && e.EActor == dcActor) dcGodCalls++;
}

/* ---- the probe ---- */
static FILE *dcLog = NULL;
static int   dcLines = 0, dcErrors = 0;
static EventInfo dcEv;           /* one event buffer; SetEvent clears it */

struct DCCell { int16 x, y; };

struct DCCtx {
    Player *pl;
    Map *mp;
    std::vector<Creature*> made;
};

static const char *DCRet(EvReturn r)
{
    switch (r) {
        case NOTHING: return "NOTHING";
        case DONE:    return "DONE";
        case ABORT:   return "ABORT";
        case NOMSG:   return "NOMSG";
        case ERROR:   return "ERROR";
        default:      return "OTHER";
    }
}

static bool DCErr(const char *id, int type, const char *why)
{
    fprintf(dcLog, "SETUP_ERROR case=%s type=%d why=%s\n", id, type, why);
    fflush(dcLog);
    dcErrors++;
    return false;
}

static void DCLine(const char *id, int type, const char *fmt, ...)
{
    va_list ap;
    fprintf(dcLog, "DC case=%s type=%d ", id, type);
    va_start(ap, fmt);
    vfprintf(dcLog, fmt, ap);
    va_end(ap);
    fputc('\n', dcLog);
    fflush(dcLog);
    dcLines++;
}

static bool DCCellOK(Map *mp, Player *pl, int16 x, int16 y)
{
    if (!mp->InBounds(x, y) || mp->SolidAt(x, y) || mp->FCreatureAt(x, y)) return false;
    if (mp->FieldAt(x, y)) return false;
    if (x == pl->x && y == pl->y) return false;
    return true;
}

static int DCFreeNeighbors(Map *mp, Player *pl, int16 x, int16 y)
{
    int n = 0;
    for (int dx = -1; dx <= 1; dx++)
        for (int dy = -1; dy <= 1; dy++)
            if ((dx || dy) && DCCellOK(mp, pl, x + dx, y + dy)) n++;
    return n;
}

static bool DCCellLess(const std::pair<int, DCCell> &a, const std::pair<int, DCCell> &b)
{
    if (a.first != b.first) return a.first < b.first;
    if (a.second.y != b.second.y) return a.second.y < b.second.y;
    return a.second.x < b.second.x;
}

/* Open floor near the player with room around it, nearest first. */
static std::vector<DCCell> DCCells(Map *mp, Player *pl)
{
    std::vector<std::pair<int, DCCell> > v;
    for (int dx = -14; dx <= 14; dx++)
        for (int dy = -14; dy <= 14; dy++) {
            int16 x = pl->x + dx, y = pl->y + dy;
            if (!DCCellOK(mp, pl, x, y)) continue;
            if (DCFreeNeighbors(mp, pl, x, y) < 5) continue;
            DCCell c; c.x = x; c.y = y;
            v.push_back(std::make_pair((int)dist(pl->x, pl->y, x, y), c));
        }
    std::sort(v.begin(), v.end(), DCCellLess);
    std::vector<DCCell> out;
    for (size_t i = 0; i < v.size(); i++) out.push_back(v[i].second);
    return out;
}

static Monster *DCMake(DCCtx &c, const char *name, DCCell cell, int hp)
{
    rID id = FIND(name);
    if (!id) return NULL;
    c.mp->At(cell.x, cell.y).Lit = 1;
    Monster *mn = new Monster(id);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    mn->PlaceAt(c.mp, cell.x, cell.y, true);
    mn->Initialize(true);
    while (mn->HasStati(SLEEPING)) mn->RemoveStati(SLEEPING);
    mn->mHP = mn->cHP = hp;
    c.made.push_back(mn);
    return mn;
}

static void DCClean(DCCtx &c)
{
    dcRun = false;
    dcWatch = NULL; dcItem = NULL; dcActor = dcVictim = NULL;
    for (size_t i = 0; i < c.made.size(); i++)
        if (!(c.made[i]->Flags & F_DELETE)) c.made[i]->Remove(true);
    c.made.clear();
}

/* Set an attribute so its modifier is `mod`, by an inherent bonus carried
   under a cause (SS_ENCH) the fixture's character does not use. */
static bool DCSetMod(Creature *c, int attr, int mod, int16 &delta)
{
    c->CalcValues();
    delta = (int16)((10 + 2 * mod) - c->GetAttr(attr));
    if (delta) c->GainPermStati(ADJUST_INH, NULL, SS_ENCH, attr, delta);
    c->CalcValues();
    return c->Mod(attr) == mod;
}

static void DCUnsetMod(Creature *c, int attr, int16 delta)
{
    if (delta) c->RemoveStati(ADJUST_INH, SS_ENCH, attr, delta);
    c->CalcValues();
}

static void DCBase(EventInfo &e, int ev, Creature *a, Creature *v, Map *mp, int type)
{
    SetEvent(e, ev, a, v);
    e.EMap = mp;
    e.DType = (int8)type;
}

static int DCCountKind(Map *mp, rID tmID)
{
    int n = 0, i;
    Creature *t;
    MapIterate(mp, t, i)
        if (t->isCreature() && t->tmID == tmID && !(t->Flags & F_DELETE)) n++;
    return n;
}

/* ---- the cases ---- */

static bool DCNegate(DCCtx &c, int type)
{
    const char *id = "negate";
    std::vector<DCCell> cells = DCCells(c.mp, c.pl);
    if (cells.size() < 3) return DCErr(id, type, "no arena");
    Monster *g = DCMake(c, "goblin", cells[0], 1000);
    Monster *k = DCMake(c, "kobold", cells[1], 1000);
    if (!g || !k) return DCErr(id, type, "missing monster resource");
    g->GainPermStati(NEGATED, NULL, SS_MISC, 1);
    if (g->GetStatiVal(NEGATED) != 1) return DCErr(id, type, "NEGATED readback");
    DCBase(dcEv, EV_DAMAGE, g, k, c.mp, type);
    dcEv.vDmg = 20; dcEv.isNAttack = true;
    DCArm(g, k, type);
    EvReturn r = g->HandleNegate(dcEv);
    DCLine(id, type, "ret=%s", DCRet(r));
    return true;
}

static bool DCMien(DCCtx &c, int type)
{
    const char *id = "mien";
    std::vector<DCCell> cells = DCCells(c.mp, c.pl);
    if (cells.size() < 3) return DCErr(id, type, "no arena");
    Monster *g = DCMake(c, "goblin", cells[0], 1000);
    Monster *k = DCMake(c, "kobold", cells[1], 1000);
    if (!g || !k) return DCErr(id, type, "missing monster resource");
    k->GainPermStati(EXTRA_FEAT, NULL, SS_MISC, FT_TERRIBLE_MEIN);
    int16 d = 0;
    if (!DCSetMod(k, A_CHA, 4, d)) return DCErr(id, type, "CHA readback");
    if (!k->HasFeat(FT_TERRIBLE_MEIN)) return DCErr(id, type, "feat readback");
    if (!g->isMType(MA_SAPIENT)) return DCErr(id, type, "actor not sapient");
    if (g->ResistLevel(AD_FEAR) == -1) return DCErr(id, type, "actor fear-immune");
    if (g->SumStatiMag(SAVE_BONUS, SN_FEAR) != 0) return DCErr(id, type, "fear bonus");
    if (!g->Perceives(k) || !k->Perceives(g)) return DCErr(id, type, "no mutual perception");
    DCBase(dcEv, PRE(EV_STRIKE), g, k, c.mp, type);
    dcEv.AType = A_TUCH;
    DCArm(g, k, type);
    dcRun = true;
    g->PreStrike(dcEv);
    dcRun = false;
    if (dcSiteHits[DC_SITE_MIEN_BEFORE] != 1 || dcSiteHits[DC_SITE_MIEN_AFTER] != 1)
        return DCErr(id, type, "checkpoints not both reached once");
    DCLine(id, type, "delta_bDmg=%d",
        dcSiteB[DC_SITE_MIEN_AFTER] - dcSiteB[DC_SITE_MIEN_BEFORE]);
    return true;
}

static bool DCTough(DCCtx &c, int type)
{
    const char *id = "tough";
    std::vector<DCCell> cells = DCCells(c.mp, c.pl);
    if (cells.size() < 3) return DCErr(id, type, "no arena");
    Monster *g = DCMake(c, "goblin", cells[0], 1000);
    Monster *k = DCMake(c, "kobold", cells[1], 1000);
    if (!g || !k) return DCErr(id, type, "missing monster resource");
    int16 d = 0;
    if (!DCSetMod(k, A_CON, 4, d)) return DCErr(id, type, "CON readback");
    if (k->AbilityLevel(CA_TOUGH_AS_HELL) != 0) return DCErr(id, type, "preexisting TaH");
    int lev = max(1, (int)k->ChallengeRating());
    k->GainPermStati(EXTRA_ABILITY, NULL, SS_MISC, CA_TOUGH_AS_HELL, lev);
    k->CalcValues();
    if (k->AbilityLevel(CA_TOUGH_AS_HELL) != lev) return DCErr(id, type, "TaH level readback");
    if (max(1, (int)k->ChallengeRating()) != lev) return DCErr(id, type, "CR moved");
    if (k->InSlot(SL_ARMOUR)) return DCErr(id, type, "victim wears armour");
    DCBase(dcEv, EV_DAMAGE, g, k, c.mp, type);
    dcEv.vDmg = 20; dcEv.bDmg = 0; dcEv.AType = A_TUCH; dcEv.isActOfGod = true;
    DCArm(g, k, type);
    dcRun = true;
    k->Damage(dcEv);
    dcRun = false;
    if (dcSiteHits[DC_SITE_TAH_BEFORE] != 1 || dcSiteHits[DC_SITE_TAH_AFTER] != 1)
        return DCErr(id, type, "checkpoints not both reached once");
    DCLine(id, type, "in=%d out=%d delta_bDmg=%d", dcSiteV[DC_SITE_TAH_BEFORE],
        dcSiteV[DC_SITE_TAH_AFTER],
        dcSiteB[DC_SITE_TAH_AFTER] - dcSiteB[DC_SITE_TAH_BEFORE]);
    return true;
}

static bool DCGod(DCCtx &c, int type)
{
    const char *id = "god";
    Player *pl = c.pl;
    rID hes = FIND("Hesani");
    if (!hes) return DCErr(id, type, "no Hesani");
    std::vector<DCCell> cells = DCCells(c.mp, pl);
    if (cells.size() < 2) return DCErr(id, type, "no arena");
    Monster *g = DCMake(c, "goblin", cells[0], 1000);
    if (!g) return DCErr(id, type, "missing monster resource");
    if (pl->HasFeat(FT_REED_IN_THE_WIND)) return DCErr(id, type, "player has Reed in the Wind");
    int gn = theGame->GodNum(hes);
    /* save */
    rID oGod = pl->GodID;
    int16 oHP = pl->cHP, oMHP = pl->mHP, oFF = pl->FFCount;
    uint16 oFlags = pl->godFlags[gn];
    int16 oAnger = pl->Anger[gn], oPen = pl->FavPenalty[gn];
    int32 oSac[MAX_SAC_CATS + 2];
    memcpy(oSac, pl->SacVals[gn], sizeof(oSac));
    /* stage */
    pl->GodID = hes;
    pl->godFlags[gn] = GS_INVOLVED;
    pl->Anger[gn] = 0; pl->FavPenalty[gn] = 0;
    memset(pl->SacVals[gn], 0, sizeof(oSac));
    pl->cHP = pl->mHP = 100;
    bool ok = true;
    if (pl->calcFavour(hes) != 0) ok = DCErr(id, type, "favour readback");
    if (ok) {
        DCBase(dcEv, EV_DAMAGE, g, pl, c.mp, type);
        dcEv.vDmg = 100; dcEv.bDmg = 0; dcEv.AType = A_TUCH; dcEv.isActOfGod = true;
        dcEv.isCrit = true; dcEv.vCrit = 2; dcEv.eID = hes;
        DCArm(g, pl, type);
        dcGodNum = gn;
        dcRun = true;
        pl->Damage(dcEv);
        dcRun = false;
        dcGodNum = -1;
        /* The fixture's barbarian has Tough as Hell from his class
           (lib/classes.irh:178). It must not move vDmg before the god gate. */
        if (dcSiteHits[DC_SITE_GOD_AFTER] != 1 || dcSiteHits[DC_SITE_TAH_BEFORE] != 1 ||
            dcSiteHits[DC_SITE_TAH_AFTER] != 1)
            ok = DCErr(id, type, "gate checkpoint not reached once");
        else if (dcSiteV[DC_SITE_TAH_BEFORE] != dcSiteV[DC_SITE_TAH_AFTER])
            ok = DCErr(id, type, "Tough as Hell moved vDmg before the god gate");
        else
            DCLine(id, type, "calls=%d out=%d penalty=%d", dcGodCalls,
                dcSiteV[DC_SITE_GOD_AFTER], dcPenAtSite);
    }
    /* restore */
    pl->RemoveStati(STUCK);
    pl->GodID = oGod; pl->godFlags[gn] = oFlags;
    pl->Anger[gn] = oAnger; pl->FavPenalty[gn] = oPen;
    memcpy(pl->SacVals[gn], oSac, sizeof(oSac));
    pl->cHP = oHP; pl->mHP = oMHP; pl->FFCount = (int8)oFF;
    return ok;
}

static bool DCIllusion(DCCtx &c, int type, bool actor)
{
    const char *id = actor ? "illusion-actor" : "illusion-effect";
    rID ipf = FIND("Improved Phantasmal Force");
    if (!ipf) return DCErr(id, type, "no Improved Phantasmal Force");
    std::vector<DCCell> cells = DCCells(c.mp, c.pl);
    if (cells.size() < 3) return DCErr(id, type, "no arena");
    Monster *g = DCMake(c, "goblin", cells[0], 1000);
    Monster *k = DCMake(c, "kobold", cells[1], 1000);
    if (!g || !k) return DCErr(id, type, "missing monster resource");
    DCBase(dcEv, EV_DAMAGE, g, k, c.mp, type);
    dcEv.vDmg = 20; dcEv.bDmg = 0; dcEv.AType = A_TUCH; dcEv.isActOfGod = true;
    dcEv.eID = ipf;
    if (actor) {
        g->GainPermStati(ILLUSION, c.pl, SS_ENCH, 15, 0, ipf, 5);
        if (!g->HasStati(ILLUSION)) return DCErr(id, type, "ILLUSION readback");
        if (!g->isRealTo(k)) return DCErr(id, type, "actor not real to victim");
        dcEv.actIllusion = true;
    } else
        dcEv.effIllusion = true;
    k->FFCount = 7;
    DCArm(g, k, type);
    dcRun = true;
    k->Damage(dcEv);
    dcRun = false;
    DCLine(id, type, "early=%d ff=%d", dcSiteHits[DC_SITE_ILL_PASSED] ? 0 : 1, (int)k->FFCount);
    return true;
}

/* The 77 distinct existing damage-type values: 0-14, 16-30, 32-39, 41-74,
   90-94 (AD_MIND aliases AD_CHRM). */
static void DCManifest(std::vector<int> &out)
{
    for (int v = 0; v <= 14; v++) out.push_back(v);
    for (int v = 16; v <= 30; v++) out.push_back(v);
    for (int v = 32; v <= 39; v++) out.push_back(v);
    for (int v = 41; v <= 74; v++) out.push_back(v);
    for (int v = 90; v <= 94; v++) out.push_back(v);
}

static bool DCFury(DCCtx &c, std::vector<int> &types)
{
    Player *pl = c.pl;
    rID am = FIND("Arrow Mind");
    if (!am) return DCErr("fury", -1, "no Arrow Mind");
    TEffect *te = TEFF(am);
    EffectValues saved[4];
    for (int j = 0; j < 4; j++) {
        if (!te->Vals(j)) return DCErr("fury", -1, "Arrow Mind has fewer than four slots");
        saved[j] = *te->Vals(j);
    }
    if (te->HasFlag(EF_NO_BONUS_DMG)) return DCErr("fury", -1, "EF_NO_BONUS_DMG");
    /* The fixture's orc has Spell Fury from his race (lib/races.irh:1873): grant
       it only when absent, and remove only what was granted. */
    if (pl->AbilityLevel(CA_ARCANE_WILL) != 0)
        return DCErr("fury", -1, "player already has Arcane Will");
    const bool grantFury = !pl->HasAbility(CA_SPELL_FURY);
    int sn = theGame->SpellNum(am);
    uint32 oSpell = pl->Spells[sn];
    int16 d = 0;
    bool ok = true;
    if (!DCSetMod(pl, A_WIS, 4, d)) ok = DCErr("fury", -1, "WIS readback");
    if (ok) {
        if (grantFury) pl->GainPermStati(EXTRA_ABILITY, NULL, SS_MISC, CA_SPELL_FURY, 1);
        pl->CalcValues();
        pl->Spells[sn] = SP_ARCANE;
        if (!pl->HasAbility(CA_SPELL_FURY)) ok = DCErr("fury", -1, "Spell Fury readback");
    }
    for (int j = 0; ok && j < 4; j++) {
        char id[16];
        snprintf(id, sizeof(id), "fury%d", j);
        for (size_t t = 0; t < types.size(); t++) {
            for (int s = 0; s < 4; s++) {
                te->Vals(s)->eval = (int8)(s == j ? EA_BLAST : EA_INFLICT);
                if (s == j) te->Vals(s)->xval = (uint8)types[t];
            }
            int16 bonus = pl->SpellDmgBonus(am);
            DCLine(id, types[t], "bonus=%d", (int)bonus);
        }
        for (int s = 0; s < 4; s++) *te->Vals(s) = saved[s];
    }
    for (int s = 0; s < 4; s++) *te->Vals(s) = saved[s];
    pl->Spells[sn] = oSpell;
    if (grantFury) pl->RemoveStati(EXTRA_ABILITY, SS_MISC, CA_SPELL_FURY, 1);
    DCUnsetMod(pl, A_WIS, d);
    return ok;
}

static bool DCBreeder(DCCtx &c, int type, bool jelly)
{
    const char *id = jelly ? "jelly" : "worms";
    const char *name = jelly ? "blue jelly" : "white worm mass";
    std::vector<DCCell> cells = DCCells(c.mp, c.pl);
    if (cells.size() < 3) return DCErr(id, type, "no arena");
    Monster *g = DCMake(c, "goblin", cells[0], 1000);
    Monster *b = DCMake(c, name, cells[cells.size() / 2], 100);
    if (!g || !b) return DCErr(id, type, "missing monster resource");
    rID bid = b->tmID;
    if (b->HasStati(SUMMONED) || b->HasStati(POLYMORPH) || b->HasStati(NEGATED) ||
        b->HasStati(GENERATION))
        return DCErr(id, type, "breeder carries a blocking stati");
    if (dist(g->x, g->y, b->x, b->y) < 3) return DCErr(id, type, "actor beside breeder");
    int16 oBreed = c.mp->BreedCount;
    c.mp->BreedCount = 0;
    DCBase(dcEv, jelly ? EV_DAMAGE : EV_HIT, g, b, c.mp, type);
    dcEv.aDmg = 8;
    int sel = jelly ? EVICTIM(POST(EV_DAMAGE)) : POST(EVICTIM(EV_HIT));
    DCArm(g, b, type);
    dcHRes = bid; dcHEv = sel;
    int before = DCCountKind(c.mp, bid);
    dcRun = true;
    RES(bid)->Event(dcEv, bid, sel);
    dcRun = false;
    int after = DCCountKind(c.mp, bid);
    int breed = c.mp->BreedCount;
    bool ok = true;
    if (dcHandlerHits != 1) ok = DCErr(id, type, "handler did not run once");
    else DCLine(id, type, "count_before=%d count_after=%d breed_delta=%d", before, after, breed);
    /* remove every jelly or worm, children included */
    {
        std::vector<Creature*> kids;
        Creature *t; int i;
        MapIterate(c.mp, t, i)
            if (t->isCreature() && t->tmID == bid) kids.push_back(t);
        for (size_t k = 0; k < kids.size(); k++)
            if (!(kids[k]->Flags & F_DELETE)) kids[k]->Remove(true);
    }
    c.mp->BreedCount = oBreed;
    return ok;
}

static bool DCJovoc(DCCtx &c, int type)
{
    const char *id = "jovoc";
    /* inc-kx693: reads the catalog control only to refuse a run without it */
    const char *fs = getenv("INCURSION_FORCE_SAVE_ROLL");
    if (!fs || strcmp(fs, "1")) return DCErr(id, type, "INCURSION_FORCE_SAVE_ROLL is not 1");
    std::vector<DCCell> cells = DCCells(c.mp, c.pl);
    /* jovoc: at least 5 from the player, no creature within 4, a free cell within 4 */
    int ji = -1, ki = -1, gi = -1;
    for (size_t i = 0; ji < 0 && i < cells.size(); i++) {
        if (dist(c.pl->x, c.pl->y, cells[i].x, cells[i].y) < 5) continue;
        bool lonely = true;
        Creature *t; int n;
        MapIterate(c.mp, t, n)
            if (t->isCreature() && dist(t->x, t->y, cells[i].x, cells[i].y) <= 4) lonely = false;
        if (!lonely) continue;
        for (size_t k = 0; ki < 0 && k < cells.size(); k++)
            if (k != i && dist(cells[i].x, cells[i].y, cells[k].x, cells[k].y) <= 4) ki = (int)k;
        if (ki < 0) continue;
        for (size_t g = 0; gi < 0 && g < cells.size(); g++)
            if (dist(cells[i].x, cells[i].y, cells[g].x, cells[g].y) >= 5) gi = (int)g;
        if (gi < 0) { ki = -1; continue; }
        ji = (int)i;
    }
    if (ji < 0) return DCErr(id, type, "no jovoc arena");
    Monster *j = DCMake(c, "jovoc", cells[ji], 100);
    Monster *k = DCMake(c, "kobold", cells[ki], 1000);
    Monster *g = DCMake(c, "goblin", cells[gi], 1000);
    if (!j || !k || !g) return DCErr(id, type, "missing monster resource");
    {   /* exactly one eligible neighbor */
        int eligible = 0; Creature *t; int n;
        MapIterate(c.mp, t, n)
            if (t->isCreature() && t != j && dist(j->x, j->y, t->x, t->y) <= 4 &&
                !t->isMType(MA_DEMON)) eligible++;
        if (eligible != 1) return DCErr(id, type, "not exactly one eligible neighbor");
    }
    DCBase(dcEv, EV_DAMAGE, g, j, c.mp, type);
    dcEv.aDmg = 8;
    int sel = EVICTIM(POST(EV_DAMAGE));
    DCArm(g, j, type);
    dcHRes = j->tmID; dcHEv = sel; dcWatch = k;
    dcRun = true;
    RES(j->tmID)->Event(dcEv, j->tmID, sel);
    dcRun = false;
    if (dcHandlerHits != 1) return DCErr(id, type, "handler did not run once");
    DCLine(id, type, "deliveries=%d requested=%d", dcWatchCalls, dcWatchReq);
    return true;
}

static bool DCShield(DCCtx &c, int type)
{
    const char *id = "shield";
    rID so = FIND("Shield Other");
    if (!so) return DCErr(id, type, "no Shield Other");
    std::vector<DCCell> cells = DCCells(c.mp, c.pl);
    if (cells.size() < 4) return DCErr(id, type, "no arena");
    Monster *g = DCMake(c, "goblin", cells[0], 1000);
    Monster *p = DCMake(c, "kobold", cells[1], 1000);
    Monster *l = DCMake(c, "kobold", cells[2], 1000);
    if (!g || !p || !l) return DCErr(id, type, "missing monster resource");
    if (p->HasStati(TRAP_EVENT) || l->HasStati(TRAP_EVENT)) return DCErr(id, type, "preexisting TRAP_EVENT");
    p->GainPermStati(TRAP_EVENT, l, SS_ENCH, EVICTIM(EV_DAMAGE), 0, so, 5);
    if (p->GetEffStatiObj(TRAP_EVENT, so) != l) return DCErr(id, type, "link readback");
    DCBase(dcEv, EV_DAMAGE, g, p, c.mp, type);
    dcEv.vDmg = 20;
    int sel = META(EVICTIM(EV_DAMAGE));
    DCArm(g, p, type);
    dcHRes = so; dcHEv = sel; dcWatch = l;
    dcRun = true;
    EvReturn r = RES(so)->Event(dcEv, so, sel);
    dcRun = false;
    if (dcHandlerHits != 1) return DCErr(id, type, "handler did not run once");
    DCLine(id, type, "ret=%s out=%d deliveries=%d requested=%d", DCRet(r), (int)dcEv.vDmg,
        dcWatchCalls, dcWatchReq);
    return true;
}

static bool DCAnimated(DCCtx &c, int type, bool rope)
{
    const char *id = rope ? "rope" : "object";
    rID animID = FIND(rope ? "animated hemp rope" : "small animated object");
    rID itemID = FIND(rope ? "hemp rope" : "dagger");
    rID spell = rope ? FIND("Animate Rope") : 0;
    if (!animID || !itemID || (rope && !spell)) return DCErr(id, type, "missing resource");
    std::vector<DCCell> cells = DCCells(c.mp, c.pl);
    if (cells.size() < 3) return DCErr(id, type, "no arena");
    Monster *g = DCMake(c, "goblin", cells[0], 1000);
    Monster *a = DCMake(c, rope ? "animated hemp rope" : "small animated object", cells[1], 100);
    if (!g || !a) return DCErr(id, type, "missing monster resource");
    Item *it = Item::Create(itemID);
    if (!it) return DCErr(id, type, "item creation failed");
    it->Quantity = 1;
    it->cHP = it->MaxHP();
    if (rope) {
        a->GainPermStati(TRAP_EVENT, NULL, SS_MISC, PRE(EVICTIM(EV_DAMAGE)), 0, spell, 5);
        a->GainPermStati(TRANSFORMED, it, SS_ENCH, 0, 0, spell, 5);
    } else
        a->GainPermStati(TRANSFORMED, it, SS_ENCH, 0, 0, 0, 0);
    if (a->GetStatiObj(TRANSFORMED) != it) return DCErr(id, type, "TRANSFORMED readback");
    a->cHP = 80;
    DCBase(dcEv, EV_DAMAGE, g, a, c.mp, type);
    dcEv.vDmg = 0; dcEv.aDmg = 0;
    rID res = rope ? spell : animID;
    int sel = rope ? META(PRE(EVICTIM(EV_DAMAGE))) : PRE(EVICTIM(EV_DAMAGE));
    DCArm(g, a, type);
    dcHRes = res; dcHEv = sel; dcItem = it;
    dcRun = true;
    EvReturn r = RES(res)->Event(dcEv, res, sel);
    dcRun = false;
    if (dcHandlerHits != 1) return DCErr(id, type, "handler did not run once");
    DCLine(id, type, "ret=%s item_calls=%d anim_hp=%d target_restored=%d", DCRet(r),
        dcItemCalls, (int)a->cHP, dcEv.EVictim == (Creature*)a ? 1 : 0);
    return true;
}

static void DCPair(DCCtx &c, bool (*fn)(DCCtx &, int))
{
    for (int type = 13; type <= 14; type++) {
        fn(c, type);
        DCClean(c);
    }
}

static bool DCIllA(DCCtx &c, int t) { return DCIllusion(c, t, true); }
static bool DCIllE(DCCtx &c, int t) { return DCIllusion(c, t, false); }
static bool DCJelly(DCCtx &c, int t) { return DCBreeder(c, t, true); }
static bool DCWorms(DCCtx &c, int t) { return DCBreeder(c, t, false); }
static bool DCObject(DCCtx &c, int t) { return DCAnimated(c, t, false); }
static bool DCRope(DCCtx &c, int t) { return DCAnimated(c, t, true); }

void DamageClassProbe(Player *pl)
{
    /* inc-kx693 */
    const char *mode = getenv("INCURSION_DAMAGE_CLASS_PROBE");
    if (!mode || strcmp(mode, "1")) return;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/damage-class.log",
        (const char*)T1->IncursionDirectory);
    dcLog = fopen(path, "w");
    if (!dcLog) return;
    if (!pl || !pl->m) {
        fprintf(dcLog, "SETUP_ERROR case=all type=-1 why=no player or map\n");
        fclose(dcLog); dcLog = NULL;
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    /* Messages from the cases would stop at "-- more --" and eat the key
       script's keys; clear them as the other staging probes do. */
    const int8 autoMore = pl->Options[OPT_AUTOMORE];
    pl->Options[OPT_AUTOMORE] = 1;
    DCCtx c;
    c.pl = pl; c.mp = pl->m;
    std::vector<int> types;
    DCManifest(types);
    if (types.size() != 77) DCErr("manifest", -1, "manifest is not 77 values");

    DCPair(c, DCNegate);
    DCPair(c, DCMien);
    DCPair(c, DCTough);
    DCPair(c, DCGod);
    DCPair(c, DCIllA);
    DCPair(c, DCIllE);
    DCFury(c, types);
    DCClean(c);
    DCPair(c, DCJelly);
    DCPair(c, DCWorms);
    DCPair(c, DCJovoc);
    DCPair(c, DCShield);
    DCPair(c, DCObject);
    DCPair(c, DCRope);

    pl->Options[OPT_AUTOMORE] = autoMore;
    fprintf(dcLog, "END lines=%d errors=%d\n", dcLines, dcErrors);
    fclose(dcLog); dcLog = NULL;
    theGame->PlayMode = wasInPlay;
}
