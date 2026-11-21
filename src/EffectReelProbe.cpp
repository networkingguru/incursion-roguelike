/* inc-jw0hw: opt-in effect reel. Off unless INCURSION_EFFECT_REEL is set.
   Called from Game::Play (src/Main.cpp); driven by tools/render_effect_reel.sh,
   counted by tools/check_effect_reel_list.sh. For every effect that is EA_BLAST,
   AR_GLOBE, an AR_FIELD/AR_MFIELD with FI_MODIFIER or FI_BLOCKER, or flagged
   EF_COLOR_PATTERN, plus
   "Breath Weapon" once per damage type a monster breathes, it rebuilds one dark
   room, names a recorder clip, casts the effect, and lets virtual time pass.
   errors.log gets "REEL <n> <name> <kind>", "REEL_SKIP <name> <reason>" and
   "REEL_DONE <count>" last. INCURSION_EFFECT_REEL_ONLY=<a,b> keeps only the
   named effects (case-insensitive). */
#include <ctype.h>
#include <strings.h>
#include <string>
#include <vector>
#define protected public   /* Term::QueuedChar (answers a script prompt) and Term::XOff/YOff (the map view), as EffectLightProbe does */
#include "Incursion.h"
#undef protected

extern int16 Silence;
extern Trap *SkullTrapPlace(Player *pl, Map *mp, rID trapR, rID skull, rID skullSpell, int x, int y);

extern void (*PutGlyphProbeHook)(int16 x, int16 y, bool remembered, uint16 vis);

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

struct Entry { rID id; const char *kind; int dtype; char form; };   /* dtype -1: not a breath; form: the answer to Pyrotechnics' prompt, 0 for none */

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
    /* inc-jw0hw: a clip that casts on the caster leaves its statuses behind (AFRAID stops the next clip's touch
       strike, Magic.cpp:1248 aims at the caster). Clear every status an effect put on the player. */
    StatiIter(pl)
        if (S->eID && RES(S->eID)->Type == T_TEFFECT && S->Nature != HELD_MANA)
            StatiIter_RemoveCurrent(pl)
    StatiIterEnd(pl)
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
    /* inc-jw0hw: a beam or bolt that draws the color pattern. */
    if (te.HasFlag(EF_COLOR_PATTERN)) { *kind = "pattern"; return true; }
    return false;
}

/* inc-jw0hw: the class name the light-table check compares: a COL_* row by its
   short name, a plain palette color as cval:<NAME>, "random" for none. */
const char *LightClass(int16 colour, char *buf, size_t n) {
    static const char *rows[] = { "fire", "cold", "magic", "necro", "elec", "rainbow", "light",
        "poison", "acid", "disint", "petri", "poly", "sonic", "silvery", "crimson", "darkred",
        "sunyellow" };
    static const char *pal[] = { "BLACK", "BLUE", "GREEN", "CYAN", "RED", "PURPLE", "BROWN", "GREY",
        "SHADOW", "AZURE", "EMERALD", "SKYBLUE", "PINK", "MAGENTA", "YELLOW", "WHITE" };
    if (colour >= COL_FIRE && colour <= COL_SUNYELLOW) return rows[colour - COL_FIRE];
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

} /* namespace */

void EffectReelProbe(Player *pl) {
    const bool tableMode = getenv("INCURSION_EFFECT_LIGHT_TABLE") != NULL;
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

    /* The list, from the loaded module. */
    std::vector<Entry> list;
    Module *mod = theGame->Modules[0];
    for (int i = 0; i < mod->szEff; ++i) {
        const rID id = mod->EffectID(i);
        const char *kind;
        if (id == breath) continue;   /* once per damage type, below */
        if (IsReelKind(mod->QEff[i], &kind)) {
            Entry e = { id, kind, -1, 0 };
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
        Entry e = { breath, "breath", dts[k], 0 };
        list.push_back(e);
    }
    /* inc-jw0hw: Pyrotechnics asks "Smoke, fireworks or explosion?" and redirects to one of
       three effects; one clip per answer, with the answer queued in the terminal. */
    const rID pyro = FIND("Pyrotechnics");
    if (pyro && TEFF(pyro)->ef.eval == EA_GENERIC) {
        const char formKey[3] = { 's', 'f', 'e' };
        for (int k = 0; k < 3; ++k) {
            Entry e = { pyro, "form", -1, formKey[k] };
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
                snprintf(nm, sizeof nm, "Breath Weapon (%s)", Lookup(DTypeNames, en.dtype));
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
        Error("LIGHT_DONE %d", shown);
        return;
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
        char key[160];   /* the table's name for the clip: the declared name with its ;tag */
        if (en.dtype >= 0)
            snprintf(nm, sizeof nm, "Breath Weapon (%s)", Lookup(DTypeNames, en.dtype));
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
        BuildRoom(mp, pl, floor, wall);
        /* inc-jw0hw: the Pyrotechnics script removes the middle kobold's torch, so the smoke would land on dark squares.
           A wall torch in the stub (LK_WALLTORCH, range 3, Light.cpp) is a separate source the cast does not remove.
           BuildRoom rewrites every square, so the next clip starts without it. */
        if (en.form == 's') {
            /* The cast removes the kobold's torch, so the room is dark and three wall torches (LK_WALLTORCH, range 3) light it:
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
        Monster *mid = NULL, *ks[3] = { NULL, NULL, NULL };
        for (int k = 0; k < 3; ++k) {
            Monster *mn = new Monster(kobold); ks[k] = mn;
            mn->PlaceAt(mp, kx[k], ky[k], true);
            mn->Initialize(true);
            if (k == 1) mid = mn;
        }
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
            xe.ETarget = mid; xe.EVictim = mid; xe.EXVal = mid->x; xe.EYVal = mid->y;
            break;
        case AIM_LOC:
            xe.isLoc = true; xe.EXVal = mid->x; xe.EYVal = mid->y;
            break;
        case AIM_FIELD:
            xe.isLoc = true; xe.EXVal = PX; xe.EYVal = PY;
            break;
        case AIM_BREATH:
            xe.isLoc = true; xe.EXVal = AIMX; xe.EYVal = PY; xe.EVictim = mid;
            break;
        }
        int16 hp0[3]; for (int k = 0; k < 3; ++k) hp0[k] = ks[k]->cHP;
        ViewLog(pl, nm, "before-cast");
        Error("REEL_AIM %s %s", nm, kAimName[aim]);
        Error("REEL_KEY %d %s", count, key);
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
        /* inc-jw0hw: Magic.cpp:932 runs an EF_ACTIVATE segment only when isActivation is set. */
        xe.isActivation = te->HasFlag(EF_ACTIVATE);
        if (skullTrap) {
            xe.EItem = (Item *)skullTrap; xe.isTrap = true; xe.vCasterLev = 12;   /* as Trap::TriggerTrap */
            skullTrap->TrapFlags |= TS_DISARMED;
            skullTrap->SetImage();
        }
        /* A long message makes the text terminal wait for a key; the reel prints none. */
        Silence = 1;
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
            ReThrow(EV_EFFECT, xe);
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
        Silence = 0;
        if (isSkull) {
            ScriptLightTickHook = NULL; ScriptLightEndHook = NULL;
            Error("REEL_SKULL trap (%d,%d): steps %d, lit steps %d, first %.0f ms, last %.0f ms, end hook calls %d, flashes left %d",
                  gSkX, gSkY, gSkTicks, gSkLitTicks, gSkFirst, gSkLast, gSkEnds, (int)LightFlashCount());
        }
        pl->mHP = pl->cHP = 30000;
        pl->LightRange = pl->InfraRange = pl->ShadowRange = 0;
        Error("REEL_HP %s kobold hp %d/%d %d/%d %d/%d", nm, (int)ks[0]->cHP, (int)hp0[0], (int)ks[1]->cHP, (int)hp0[1], (int)ks[2]->cHP, (int)hp0[2]);
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
        const int idleMs = en.kind[0] == 'a' || leavesGlow || en.form == 's' ? 2000 : 700;
        Error("REEL_IDLE %s %d", nm, idleMs);
        pl->MyTerm->StopWatch(idleMs);
        glowLog("after-idle");
        ViewLog(pl, nm, "after-idle");
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
