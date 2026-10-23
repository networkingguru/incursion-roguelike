/* inc-nt3z: opt-in probe for spell duration classes. Off unless
   INCURSION_DURATION_PROBE=<spell name> is set. Called from Game::Play
   (src/Main.cpp); graded by tools/check_spell_durations.sh. It calls
   EffectDuration (src/Magic.cpp), the function Magic::CalcEffect uses, at
   caster levels 1, 6 and 20. INCURSION_DURATION_PROBE_FLAG=<EF_x> replaces the
   spell's duration flag for the run, so a check can exercise a class no spell
   carries yet. Output goes to errors.log through Error(), one DURATION_PROBE
   line per fact.
   INCURSION_DURATION_PROBE_HANDLER=1 also runs the spell's compiled
   EV_CALC_EFFECT handler after EffectDuration, as Magic::CalcEffect does, and
   prints DURATION_PROBE_HANDLER lines with the min and max duration over
   INCURSION_DURATION_PROBE_SAMPLES runs (default 1), because a handler may
   roll dice. The shipped flags are used (no forced flag). */
#include "Incursion.h"

extern int16 EffectDuration(TEffect *te, int casterLev, uint32 MM, bool mystic);

struct DurFlag { const char *name; int16 flag; };
static const DurFlag DurFlags[] = {
    { "EF_DSHORT", EF_DSHORT }, { "EF_D1ROUND", EF_D1ROUND },
    { "EF_DLONG", EF_DLONG }, { "EF_DXLONG", EF_DXLONG },
    { "EF_DROUND", EF_DROUND }, { "EF_DMIN", EF_DMIN },
    { "EF_D10MIN", EF_D10MIN }, { "EF_DHOUR", EF_DHOUR },
    { "EF_PERSISTANT", EF_PERSISTANT }, { "EF_PERMANANT", EF_PERMANANT },
    { "NONE", -1 },
};

void DurationProbe(Player *pl) {
    const char *spell = getenv("INCURSION_DURATION_PROBE");
    if (!spell || !*spell)
        return;
    (void)pl;
    const rID eID = FIND(spell);
    if (!eID) {
        Error("DURATION_PROBE: INCONCLUSIVE -- no resource named %s", spell);
        return;
    }
    TEffect *te = TEFF(eID);
    uint8 saved[sizeof(te->EFlags)];
    memcpy(saved, te->EFlags, sizeof(saved));

    const char *force = getenv("INCURSION_DURATION_PROBE_FLAG");
    const char *label = "own";
    if (force && *force) {
        const DurFlag *df = NULL;
        for (size_t i = 0; i < sizeof(DurFlags)/sizeof(DurFlags[0]); ++i)
            if (!strcmp(DurFlags[i].name, force)) df = &DurFlags[i];
        if (!df) {
            Error("DURATION_PROBE: INCONCLUSIVE -- unknown flag %s", force);
            return;
        }
        /* Clear every duration flag so the forced one is the only class. */
        for (size_t i = 0; i < sizeof(DurFlags)/sizeof(DurFlags[0]); ++i)
            if (DurFlags[i].flag >= 0) te->UnsetFlag(DurFlags[i].flag);
        if (df->flag >= 0) te->SetFlag(df->flag);
        label = df->name;
    }

    static const int levels[3] = { 1, 6, 20 };
    struct Mod { const char *name; uint32 mm; bool mystic; };
    static const Mod mods[] = {
        { "plain", 0, false },
        { "extend", MM_EXTEND, false },
        { "anchor+extend", MM_ANCHOR | MM_EXTEND, false },
        { "anchor+mystic+extend", MM_ANCHOR | MM_EXTEND, true },
        { "persistent", MM_PERSISTANT, false },
    };
    for (int li = 0; li < 3; ++li)
        for (size_t mi = 0; mi < sizeof(mods)/sizeof(mods[0]); ++mi)
            Error("DURATION_PROBE: spell=%s flag=%s cl=%d mod=%s dur=%d",
                spell, label, levels[li], mods[mi].name,
                (int)EffectDuration(te, levels[li], mods[mi].mm, mods[mi].mystic));

    memcpy(te->EFlags, saved, sizeof(saved));

    if (!getenv("INCURSION_DURATION_PROBE_HANDLER"))
        return;
    const char *sn = getenv("INCURSION_DURATION_PROBE_SAMPLES");
    const int samples = (sn && atoi(sn) > 0) ? atoi(sn) : 1;
    /* INCURSION_DURATION_PROBE_EFNUM=<n> runs the handler for effect part n
       (a spell with several parts, such as Music of the Spheres). */
    const char *en = getenv("INCURSION_DURATION_PROBE_EFNUM");
    const int efNum = en ? atoi(en) : 0;
    for (int li = 0; li < 3; ++li)
        for (size_t mi = 0; mi < sizeof(mods)/sizeof(mods[0]); ++mi) {
            int lo = 100000, hi = -100000;
            for (int k = 0; k < samples; ++k) {
                EventInfo e; e.Clear();
                e.EActor = pl; e.eID = eID; e.isSpell = true;
                e.EMagic = te->Vals(efNum);
                e.efNum = efNum;
                e.vCasterLev = levels[li]; e.MM = mods[mi].mm;
                e.vDuration = EffectDuration(te, levels[li], mods[mi].mm, mods[mi].mystic);
                e.Event = EV_CALC_EFFECT;
                te->Event(e, eID, EV_CALC_EFFECT);
                if (e.vDuration < lo) lo = e.vDuration;
                if (e.vDuration > hi) hi = e.vDuration;
            }
            Error("DURATION_PROBE_HANDLER: spell=%s cl=%d mod=%s samples=%d min=%d max=%d",
                spell, levels[li], mods[mi].name, samples, lo, hi);
        }
}

/* inc-nt3z phase 6: INCURSION_DURATION_PROBE_BLASPHEMY=<samples> casts the
   shipped Blasphemy at caster level 12 through ReThrow(EV_EFFECT) on real
   monsters whose Challenge Rating (the HD measure the spell reads) is CL+1,
   CL, CL-1 and CL-5, <samples> times, plain and with Extend, and prints one
   BLASPHEMY_PROBE line per (tier, mod) with the min and max of each condition.
   Kill tiers are one cast each (a dead monster cannot be recast). The Will
   save roll is forced (LOFSetForcedSaveThrowRoll). Output goes to errors.log. */
extern void LOFSetForcedSaveThrowRoll(int8 r);
extern void LOFClearForcedSaveThrowRoll();

/* Place a monster of the wanted Challenge Rating that is not evil, not an
   outsider (unless wantOut), undead only if wantUndead, and not immune to
   paralysis or necrotic death. NULL if the module has none. */
static Monster *BlasMake(Map *mp, int16 x, int16 y, int cr, bool wantOut, bool wantUndead) {
    Module *mod = theGame->Modules[0];
    for (int idx = 0; idx < mod->szMon; idx++) {
        const rID id = mod->MonsterID(idx);
        if (TMON(id)->CR != cr && cr >= 0) continue;
        mp->At(x, y).Lit = 1;
        Monster *mn = new Monster(id);
        TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
        TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
        mn->PlaceAt(mp, x, y, true);
        mn->Initialize(true);
        const bool ok = !mn->isMType(MA_EVIL) &&
            mn->isMType(MA_OUTSIDER) == wantOut &&
            mn->isMType(MA_UNDEAD) == wantUndead &&
            (cr < 0 || mn->ChallengeRating() == cr) &&
            mn->ResistLevel(AD_PLYS) != -1 && mn->ResistLevel(AD_NECR) != -1 &&
            !mn->HasStati(PARALYSIS) && mn->GetAttr(A_MR) == 0;
        if (ok) {
            mn->mHP = mn->cHP = 10000;
            return mn;
        }
        mn->Remove(true);
    }
    return NULL;
}

struct BRange {
    int n, lo, hi;
    BRange() : n(0), lo(100000), hi(-100000) {}
    void Add(int v) { n++; if (v < lo) lo = v; if (v > hi) hi = v; }
};

static void BlasCast(Player *pl, Map *mp, rID eID, uint32 mm) {
    pl->cFP = 10000;
    /* The globe also reaches the caster; clear what the last cast left. */
    pl->RemoveStati(PARALYSIS);
    pl->RemoveStati(ADJUST);
    EventInfo xe; xe.Clear();
    xe.EActor = pl; xe.ETarget = pl; xe.EVictim = pl;
    xe.EMap = mp; xe.eID = eID; xe.isSpell = true; xe.MM = mm;
    ReThrow(EV_EFFECT, xe);
}

static void BlasLine(const char *tag, const char *tier, Monster *m, const char *mod,
                     BRange &daze, BRange &held, BRange &wdur, BRange &wmag) {
    Error("BLASPHEMY_TIER: %s tier=%s cr=%d mod=%s daze=%d:%d..%d held=%d:%d..%d weak=%d:%d..%d str=%d..%d",
        tag, tier, (int)m->ChallengeRating(), mod,
        daze.n, daze.n ? daze.lo : 0, daze.n ? daze.hi : 0,
        held.n, held.n ? held.lo : 0, held.n ? held.hi : 0,
        wdur.n, wdur.n ? wdur.lo : 0, wdur.n ? wdur.hi : 0,
        wmag.n ? wmag.lo : 0, wmag.n ? wmag.hi : 0);
}

void BlasTierProbe(Player *pl) {
    const char *sn = getenv("INCURSION_DURATION_PROBE_BLASPHEMY");
    if (!sn || atoi(sn) <= 0)
        return;
    const int samples = atoi(sn);
    const rID eID = FIND("Blasphemy");
    if (!eID || !pl || !pl->m) {
        Error("BLASPHEMY_TIER: INCONCLUSIVE -- no Blasphemy or no live map");
        return;
    }
    const char *cn = getenv("INCURSION_DURATION_PROBE_BLASPHEMY_CL");
    const int CL = (cn && atoi(cn) > 0) ? atoi(cn) : 12;
    if (pl->CasterLev() > CL) {
        Error("BLASPHEMY_TIER: INCONCLUSIVE -- caster level %d above %d", (int)pl->CasterLev(), CL);
        return;
    }
    static const int16 DX[4] = {1,-1,0,0}, DY[4] = {0,0,1,-1};
    Map *mp = pl->m;
    int dir = -1;
    for (int k = 0; k < 4 && dir < 0; ++k) {
        bool ok = true;
        for (int d = 1; d <= 9 && ok; ++d) {
            const int16 x = pl->x + DX[k]*d, y = pl->y + DY[k]*d;
            ok = mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FCreatureAt(x, y);
        }
        if (ok) dir = k;
    }
    if (dir < 0) {
        Error("BLASPHEMY_TIER: INCONCLUSIVE -- no open 9-square orthogonal line");
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    pl->GainAbility(CA_SPELLCASTING, CL - pl->CasterLev(), 0, SS_PERM);
    Error("BLASPHEMY_TIER: caster_lev=%d samples=%d", (int)pl->CasterLev(), samples);
    extern void LOFSetForcedSaveThrowRoll(int8 r);
    extern void LOFClearForcedSaveThrowRoll();
    LOFSetForcedSaveThrowRoll(1);

    /* Surviving tiers: CR = CL+1, CL, CL-1, CL-5, one monster each. */
    static const int crs[4] = { CL + 1, CL, CL - 1, CL - 5 };
    static const char *names[4] = { "above", "equal", "minus1", "minus5" };
    Monster *t[4];
    bool ready = true;
    for (int i = 0; i < 4; ++i) {
        t[i] = BlasMake(mp, pl->x + DX[dir]*(i + 1), pl->y + DY[dir]*(i + 1), crs[i], false, false);
        if (!t[i]) { Error("BLASPHEMY_TIER: INCONCLUSIVE -- no monster of CR %d", crs[i]); ready = false; }
    }
    if (ready) {
        static const struct { const char *name; uint32 mm; } mods[3] = {
            { "plain", 0 }, { "extend", MM_EXTEND }, { "persistent", MM_PERSISTANT } };
        for (int mi = 0; mi < 3; ++mi) {
            BRange daze[4], held[4], wdur[4], wmag[4];
            for (int s = 0; s < samples; ++s) {
                for (int i = 0; i < 4; ++i) { t[i]->RemoveStati(PARALYSIS); t[i]->RemoveStati(ADJUST); }
                BlasCast(pl, mp, eID, mods[mi].mm);
                for (int i = 0; i < 4; ++i) {
                    if (t[i]->HasStati(PARALYSIS, PARA_DAZED)) daze[i].Add(t[i]->GetStatiDur(PARALYSIS, PARA_DAZED));
                    if (t[i]->HasStati(PARALYSIS, PARA_HELD)) held[i].Add(t[i]->GetStatiDur(PARALYSIS, PARA_HELD));
                    if (t[i]->HasStati(ADJUST, A_STR)) {
                        wdur[i].Add(t[i]->GetStatiDur(ADJUST, A_STR));
                        wmag[i].Add(-t[i]->GetStatiMag(ADJUST, A_STR));
                    }
                }
            }
            for (int i = 0; i < 4; ++i)
                BlasLine("hit", names[i], t[i], mods[mi].name, daze[i], held[i], wdur[i], wmag[i]);
        }
    }
    for (int i = 0; i < 4; ++i) if (t[i]) t[i]->Remove(true);

    /* Kill tier: a living monster of CR CL-10, one cast. */
    Monster *k = BlasMake(mp, pl->x + DX[dir], pl->y + DY[dir], CL - 10, false, false);
    if (!k) Error("BLASPHEMY_TIER: INCONCLUSIVE -- no monster of CR %d", CL - 10);
    else {
        BlasCast(pl, mp, eID, 0);
        Error("BLASPHEMY_TIER: kill tier=minus10 cr=%d dead=%d", (int)(CL - 10), k->isDead() ? 1 : 0);
        if (!k->isDead()) k->Remove(true);
    }
    /* Undead tier: a nonevil undead of any CR up to CL-10, if one exists. */
    Monster *u = BlasMake(mp, pl->x + DX[dir], pl->y + DY[dir], -1, false, true);
    if (!u) Error("BLASPHEMY_TIER: undead none -- the module has no nonevil undead the probe can place");
    else {
        const int ucr = u->ChallengeRating();
        BlasCast(pl, mp, eID, 0);
        Error("BLASPHEMY_TIER: undead cr=%d dead=%d", ucr, u->isDead() ? 1 : 0);
        if (!u->isDead()) u->Remove(true);
    }
    /* Banishment: a nonevil outsider, Will save forced to 1 (fails) and 20 (passes). */
    for (int pass = 0; pass < 2; ++pass) {
        LOFSetForcedSaveThrowRoll(pass ? 20 : 1);
        Monster *o = BlasMake(mp, pl->x + DX[dir], pl->y + DY[dir], -1, true, false);
        if (!o) { Error("BLASPHEMY_TIER: banish none -- no nonevil outsider the probe can place"); break; }
        const int ocr = o->ChallengeRating();
        BlasCast(pl, mp, eID, 0);
        Error("BLASPHEMY_TIER: banish roll=%d cr=%d dead=%d", pass ? 20 : 1, ocr, o->isDead() ? 1 : 0);
        if (!o->isDead()) o->Remove(true);
    }
    LOFClearForcedSaveThrowRoll();
    theGame->PlayMode = wasInPlay;
}
