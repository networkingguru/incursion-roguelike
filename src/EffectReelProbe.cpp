/* inc-jw0hw: opt-in effect reel. Off unless INCURSION_EFFECT_REEL is set.
   Called from Game::Play (src/Main.cpp); driven by tools/render_effect_reel.sh,
   counted by tools/check_effect_reel_list.sh. For every effect that is EA_BLAST,
   AR_GLOBE, or an AR_FIELD/AR_MFIELD with FI_MODIFIER or FI_BLOCKER, plus
   "Breath Weapon" once per damage type a monster breathes, it rebuilds one dark
   room, names a recorder clip, casts the effect, and lets virtual time pass.
   errors.log gets "REEL <n> <name> <kind>", "REEL_SKIP <name> <reason>" and
   "REEL_DONE <count>" last. INCURSION_EFFECT_REEL_ONLY=<a,b> keeps only the
   named effects (case-insensitive). */
#include <ctype.h>
#include <strings.h>
#include <string>
#include <vector>
#include "Incursion.h"

extern int16 Silence;

namespace {

// no-family
const int PX = 5, PY = 17;     /* the player's square in every clip: west end of the room, middle row */
const int RX0 = 4, RX1 = 34, RY0 = 10, RY1 = 24;   /* the floor: 31 x 15 */
const int CX = (RX0 + RX1) / 2;                    /* the map window centers here */
const int AIMX = PX + 9;       /* the middle target; the other two stand 2 squares above and below */
const int STUBX = AIMX + 2;    /* a wall stub for the spill to land on */
// end no-family

struct Entry { rID id; const char *kind; int dtype; };   /* dtype -1: not a breath */

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

bool InBlock(int x, int y) { return x >= RX0 && x <= RX1 && y >= RY0 && y <= RY1; }

void BuildRoom(Map *mp, Player *pl, rID floor, rID wall) {
    Thing *obj; int index;
    for (;;) {
        Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != pl) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    for (int i = 0; mp->Fields[i]; ) mp->RemoveField(mp->Fields[i]);
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
    /* The room and its walls are remembered, so the dark room is drawn unlit. */
    for (int y = 0; y < mp->SizeY(); ++y)
        for (int x = 0; x < mp->SizeX(); ++x) {
            const bool near = x >= RX0 - 1 && x <= RX1 + 1 && y >= RY0 - 1 && y <= RY1 + 1;
            mp->At(x, y).Memory = near ? (uint32)mp->At(x, y).Glyph : 0;
        }
    pl->CalcVision();
}

void Refresh(Player *pl) {
    pl->MyTerm->AdjustMap(CX, PY, true);   /* the room fills the frame, not the player */
    pl->UpdateMap = 1;
    pl->MyTerm->ShowMap();
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

bool IsReelKind(const EffectValues &ef, const char **kind) {
    if (ef.eval == EA_BLAST) { *kind = "blast"; return true; }
    if (ef.aval == AR_GLOBE) { *kind = "globe"; return true; }
    if ((ef.aval == AR_FIELD || ef.aval == AR_MFIELD) &&
        ((uint32)ef.rval & (FI_MODIFIER | FI_BLOCKER))) { *kind = "aura"; return true; }
    return false;
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

} /* namespace */

void EffectReelProbe(Player *pl) {
    if (!getenv("INCURSION_EFFECT_REEL"))
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
    const char *only = getenv("INCURSION_EFFECT_REEL_ONLY");

    /* The list, from the loaded module. */
    std::vector<Entry> list;
    Module *mod = theGame->Modules[0];
    for (int i = 0; i < mod->szEff; ++i) {
        const rID id = mod->EffectID(i);
        const char *kind;
        if (id == breath) continue;   /* once per damage type, below */
        if (IsReelKind(mod->QEff[i].ef, &kind)) {
            Entry e = { id, kind, -1 };
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
        Entry e = { breath, "breath", dts[k] };
        list.push_back(e);
    }

    const bool wasPlay = theGame->PlayMode;
    const int8 wasAnim = pl->Options[OPT_ANIMATION], wasMore = pl->Options[OPT_AUTOMORE];
    const int8 wasLight = pl->LightRange, wasInfra = pl->InfraRange, wasShadow = pl->ShadowRange;
    const int16 wasHP = pl->cHP, wasMax = pl->mHP, wasFP = pl->cFP;
    theGame->PlayMode = true;
    pl->Options[OPT_ANIMATION] = 0;   /* Normal: the light map is live */
    pl->Options[OPT_AUTOMORE] = 1;
    int count = 0;

    for (size_t n = 0; n < list.size(); ++n) {
        const Entry &en = list[n];
        char nm[160];
        if (en.dtype >= 0)
            snprintf(nm, sizeof nm, "Breath Weapon (%s)", Lookup(DTypeNames, en.dtype));
        else
            snprintf(nm, sizeof nm, "%s", NAME(en.id));
        if (!WantedByFilter(only, nm) && !(en.dtype >= 0 && WantedByFilter(only, "Breath Weapon")))
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
        BuildRoom(mp, pl, floor, wall);
        LightFlashClearAll();
        pl->mHP = pl->cHP = 30000;      /* the player survives every clip */
        pl->cFP = wasFP;                /* an effect that costs fatigue asks nothing */
        Monster *mid = NULL;
        for (int k = -1; k <= 1; ++k) {
            Monster *mn = new Monster(kobold);
            mn->PlaceAt(mp, AIMX, PY + 2 * k, true);
            mn->Initialize(true);
            if (k == 0) mid = mn;
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

        EventInfo xe; xe.Clear();
        xe.EActor = pl; xe.EMap = mp; xe.eID = en.id; xe.isSpell = true; xe.isLoc = true;
        /* Everything but an aura field lands on the middle target, away from the player
           (a death effect ignores hit points). A field is centered on the player. */
        const bool aimAtTarget = en.kind[0] != 'a';
        if (aimAtTarget) {
            xe.EXVal = AIMX; xe.EYVal = PY; xe.EVictim = mid;
        } else {
            xe.EXVal = PX; xe.EYVal = PY;       /* a globe or field on the player */
        }
        if (en.dtype >= 0) {
            /* Fight.cpp (A_BREA) loads the resource with the attack's values before the throw. */
            te->ef.pval.Number = 3; te->ef.pval.Sides = 6; te->ef.pval.Bonus = 0;
            te->ef.lval = 4;
            te->ef.xval = (uint8)en.dtype;
            xe.DType = (int8)en.dtype;
            xe.Dmg = te->ef.pval;
            xe.AType = A_BREA;
            xe.isNAttack = true;
        }
        /* The effect code sets e.vRange = 5 + caster level / 2 itself; Extend doubles it, so the
           first level-1 cast reaches 10 squares and the targets stand 9 away. */
        xe.MM |= MM_EXTEND;
        /* A long message makes the text terminal wait for a key; the reel prints none. */
        Silence = 1;
        ReThrow(EV_EFFECT, xe);
        Silence = 0;
        pl->mHP = pl->cHP = 30000;
        pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
        Refresh(pl);
        pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
        pl->MyTerm->StopWatch(en.kind[0] == 'a' ? 2000 : 700);
    }
    Error("REEL_DONE %d", count);

    LightFlashClearAll();
    BuildRoom(mp, pl, floor, wall);
    pl->LightRange = wasLight; pl->InfraRange = wasInfra; pl->ShadowRange = wasShadow;
    pl->mHP = wasMax; pl->cHP = wasHP; pl->cFP = wasFP;
    pl->Options[OPT_ANIMATION] = wasAnim;
    pl->Options[OPT_AUTOMORE] = wasMore;
    theGame->PlayMode = wasPlay;
}
