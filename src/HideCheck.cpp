/* HIDECHECK.CPP -- See the Incursion LICENSE file for copyright information.

   inc-u3dp phase 1: pure helpers for a hide/spot check. NOTHING here is wired
   into play; Perceives, Hide and every game behaviour are unchanged. The only
   writers are HideSetKey and HideClearKey, which maintain the TRIED-stati state
   keys defined in inc/HideCheck.h. */

/* upstream: `Creature::Perceives` (src/Vision.cpp:894) decided whether a watcher
   saw a hidden creature with a single roll per hide -- Hide plus a -5..+5 value
   against the watcher's bare Spot -- so a watcher either never or always saw a
   given hider for the whole hide, and only one such check ran per hide. This
   file replaces that with the SRD opposed check (d20 + Spot against d20 + Hide,
   rolled each check) stored per watcher. Observed by
   tools/check_hide_no_spot_roll.sh and the other hide checks. Tracking:
   inc-u3dp. Not sent upstream. */

#include <map>          /* before Incursion.h: it defines a macro named array */
#include "Incursion.h"
#include "HideCheck.h"

/* Round to the nearest integer, halfway away from zero. The ramps below are
   the only callers and their results are always <= 0. */
static int16 hcRound(double v) {
    return (int16)(v < 0 ? -((int)(-v + 0.5)) : (int)(v + 0.5));
}

/* True when w's best sight for this pair is infravision: w senses heat, so the
   darkness of h's square costs it nothing. InfraRange is 0 without the ability
   (Values.cpp), so the range test is also the ability test. */
static bool hcUsingInfra(Creature *w, Creature *h, int16 d) {
    return w->InfraRange > 0 && d <= (int16)w->InfraRange;
}

uint8 HideLightAt(Map *m, int16 x, int16 y) {
    if (LightMapIsFor(m))
        return LightLevelAt(x, y);
    /* The legacy fallback: a .Bright cell reads as LIGHT_LEGACY_BRIGHT, a
       .Lit-but-not-.Bright cell as LIGHT_LEGACY_LIT, anything else as dark.
       Darkness/shadow fields are not consulted here because the legacy path
       below the light map has no field term for them. */
    if (m->At(x, y).Bright || m->FieldAt(x, y, FI_LIGHT))
        return LIGHT_LEGACY_BRIGHT;
    if (m->At(x, y).Lit)
        return LIGHT_LEGACY_LIT;
    return 0;
}

int16 HideLightBand(uint8 L) {
    if (L < LIGHT_SEE_MIN) return 0;
    if (L < LIGHT_HIDE_MIN) return 1;
    return 2;
}

/* The darkness penalty from L and w's sight mode. The rules:
     infravision (h within w->InfraRange): 0
     CA_LOWLIGHT:  -20 at L=0, rising linearly to 0 at L=90
     normal sight: -20 for L<=48, rising linearly to 0 at L=90
   L>=90 is 0 either way. */
static int16 hcDarkness(Creature *w, Creature *h, int16 d, uint8 L) {
    if (hcUsingInfra(w, h, d)) return 0;
    if (L >= LIGHT_HIDE_MIN) return 0;
    if (w->HasAbility(CA_LOWLIGHT)) {
        if (L == 0) return -20;
        return hcRound(-20.0 * (LIGHT_HIDE_MIN - L) / LIGHT_HIDE_MIN);
    }
    if (L <= LIGHT_SEE_MIN) return -20;
    return hcRound(-20.0 * (LIGHT_HIDE_MIN - L) /
                   (LIGHT_HIDE_MIN - LIGHT_SEE_MIN));
}

/* The whole spot sum, given the light on the hider's square (Lh) and on the
   watcher's square (Lw). Split out from SpotModifiers so the probe can drive
   exact light levels the map cannot produce (see HideSpotModifiersForTest). */
static int16 hcSpotAtLight(Creature *w, Creature *h, int16 d,
                           uint8 Lh, uint8 Lw) {
    int16 sum = 0;

    /* Distance: -1 per square between watcher and hider. */
    sum -= d;

    /* Darkness, from the light on the hider's square. */
    sum += hcDarkness(w, h, d, Lh);

    /* Watcher in light: a lit watcher is easier to see (so a lit watcher is
       worse at spotting). Skipped while it uses infravision. */
    if (!hcUsingInfra(w, h, d) && Lw > Lh) {
        int16 pen = (int16)((Lw - Lh) / 16);
        if (pen > 10) pen = 10;
        sum -= pen;
    }

    /* Distracted: a live HK_DISTRACT key, counted once. */
    if (w->HasStati(TRIED, HK_DISTRACT)) sum -= 5;

    /* Roar: a live HK_ROAR key, counted once. */
    if (HideRoarLive(w)) sum -= 10;

    return sum;
}

int16 SpotModifiers(Creature *w, Creature *h) {
    if (!w || !h || !w->m || !h->m) return 0;
    const int16 d = dist(w->x, w->y, h->x, h->y);
    const uint8 Lh = HideLightAt(h->m, h->x, h->y);
    const uint8 Lw = HideLightAt(w->m, w->x, w->y);
    return hcSpotAtLight(w, h, d, Lh, Lw);
}

int16 HideSpotModifiersForTest(Creature *w, Creature *h, uint8 Lh, uint8 Lw) {
    if (!w || !h || !w->m || !h->m) return 0;
    const int16 d = dist(w->x, w->y, h->x, h->y);
    return hcSpotAtLight(w, h, d, Lh, Lw);
}

int16 ListenModifiers(Creature *w) {
    if (!w || !w->m) return 0;
    int16 sum = 0;

    /* Distracted: counted once. */
    if (w->HasStati(TRIED, HK_DISTRACT)) sum -= 5;

    /* Song: w hears a song another creature sings. The singer's SINGING stati
       carries the range in its Mag (Skills.cpp:2211). A deaf w hears nothing,
       and w is not its own audience. */
    if (!w->HasMFlag(M_DEAF)) {
        int i; Creature *c;
        MapIterate(w->m, c, i)
            if (c != w && c->isCreature() && c->HasStati(SINGING) &&
                dist(w->x, w->y, c->x, c->y) <= c->GetStatiMag(SINGING)) {
                sum -= 5;
                break;
            }
    }

    /* Roar: a live HK_ROAR key, counted once. */
    if (HideRoarLive(w)) sum -= 10;

    return sum;
}

int16 HiderModifiers(Creature *h) {
    if (!h) return 0;
    int16 sum = 0;
    if (h->HasStati(SPRINTING)) sum -= 20;
    return sum;
}

int16 ItemSizePenalty(Item *it) {
    if (!it) return 0;
    const int sz = it->Size();
    switch (sz) {
    case 0:
    case SZ_MINISCULE:
    case SZ_TINY:
        return 0;
    case SZ_SMALL:
        return -2;
    case SZ_MEDIUM:
        return -5;
    case SZ_LARGE:
        return -8;
    default:            /* SZ_HUGE or larger */
        return -10;
    }
}

int16 HideRoundStamp(void) {
    return (int16)((theGame->Turn / HIDE_ROUND_TICKS) & 0x7FFF);
}

bool HideRoarLive(Creature *c) {
    if (!c || !c->HasStati(TRIED, HK_ROAR)) return false;
    const int elapsed = (HideRoundStamp() - c->GetStatiMag(TRIED, HK_ROAR)) & 0x7FFF;
    return elapsed < HIDE_ROAR_ROUNDS;
}

void HideSetKey(Creature *c, int16 key, Thing *src, int16 mag) {
    if (!c) return;
    if (c->HasStati(TRIED, key, src))
        c->SetStatiMag(TRIED, key, src, mag);
    else
        c->GainPermStati(TRIED, src, SS_MISC, key, mag);
}

void HideClearKey(Creature *c, int16 key, Thing *src) {
    if (!c) return;
    c->RemoveStati(TRIED, -1, key, -1, src);
}

bool SpotCheck(Creature *w, Creature *h, int16 hiderPenalty) {
    if (!w || !h) return false;
    const int16 watcherMod = (int16)(w->SkillLevel(SK_SPOT) + SpotModifiers(w, h));
    const int16 hiderMod = (int16)(h->SkillLevel(SK_HIDE) + HiderModifiers(h)
                                   + hiderPenalty);
    bool spotted = false;
    for (int round = 0; round < 20; round++) {
        const int16 wr = (int16)(Dice::Roll(1, 20) + watcherMod);
        const int16 hr = (int16)(Dice::Roll(1, 20) + hiderMod);
        if (wr > hr) { spotted = true; break; }
        if (hr > wr) { spotted = false; break; }
        /* Tie on the dice: the higher modifier wins; equal modifiers roll
           again (SRD 3.5 opposed-check tie rule). */
        if (watcherMod > hiderMod) { spotted = true; break; }
        if (hiderMod > watcherMod) { spotted = false; break; }
    }
    const int16 mag = (int16)(((h->HideVal & 0xFF) << 1) | (spotted ? 1 : 0));
    HideSetKey(w, HK_SPOT_RESULT, h, mag);
    if (getenv("INCURSION_HIDE_TRIGGER_PROBE") ||
        getenv("INCURSION_HIDE_SEARCH_PROBE"))
        Error("HIDE_TRIGGER_ROLL watcher=%d hider=%d hiderPenalty=%d HiderModifiers=%d result=%d",
            (int)w->myHandle, (int)h->myHandle, (int)hiderPenalty,
            (int)HiderModifiers(h), spotted ? 1 : 0);
    /* Throw last: its scripts may delete w or h, so neither is read again. */
    ThrowVal(EV_SPOT_CHECK, (int16)(spotted ? 1 : 0), w, h);
    return spotted;
}

bool IsSpotted(Creature *w, Creature *h) {
    if (!w || !h) return false;
    if (!w->HasStati(TRIED, HK_SPOT_RESULT, h)) return false;
    const int16 mag = w->GetStatiMag(TRIED, HK_SPOT_RESULT, h);
    if (((mag >> 1) & 0xFF) != (h->HideVal & 0xFF)) return false;
    return (mag & 1) != 0;
}

bool HideCanWatch(Creature *w, Creature *h) {
    if (!w || !h) return false;
    if (w == h) return false;
    if (!w->m || w->m != h->m) return false;
    if (w->x == -1 || h->x == -1) return false;
    if (w->isDead()) return false;
    /* inc-yp23: the distance tests run before HasStati(ASLEEP) and isLedBy so
       pairs beyond sight range cost no status walk or leader lookup. Same
       result for every input, only the order changed. */
    if (w->isBlind() || w->SightRange == 0) return false;
    const int16 d = dist(w->x, w->y, h->x, h->y);
    if (d > (int16)w->SightRange) return false;
    if (w->HasStati(ASLEEP)) return false;
    if (w->isLedBy(h) || h->isLedBy(w)) return false;
    return w->m->LineOfVisualSight(w->x, w->y, h->x, h->y, w);
}

void HideTrigger(Creature *h, int16 hiderPenalty) {
    if (!h || !h->HasStati(HIDING)) return;
    Map *mp = h->m;
    if (!mp) return;
    const hObj hHandle = h->myHandle;
    Creature *w; int i;
    hObj watch[HIDE_WATCH_MAX];
    int nWatch = 0;
    MapIterate(mp, w, i)
        if (w && w->isCreature() && HideCanWatch(w, h)) {
            if (nWatch >= HIDE_WATCH_MAX) break;
            watch[nWatch++] = w->myHandle;
        }
    /* Each SpotCheck throws an event whose scripts can delete any creature, so
       re-fetch both the watcher and the hider from their handles every pass and
       never touch a pointer captured before an earlier check. */
    for (int k = 0; k < nWatch; k++) {
        if (!isValidHandle(hHandle) || !isValidHandle(watch[k])) continue;
        Creature *hk = oCreature(hHandle);
        if (!hk || hk->isDead() || (hk->Flags & F_DELETE)) continue;
        if (!hk->HasStati(HIDING)) continue;
        Creature *wk = oCreature(watch[k]);
        if (!wk || wk->isDead() || (wk->Flags & F_DELETE)) continue;
        if (wk->m != hk->m) continue;
        SpotCheck(wk, hk, hiderPenalty);
    }
}

void HideSearch(Creature *w) {
    if (!w || !w->m) return;
    Map *mp = w->m;
    const hObj wHandle = w->myHandle;
    Creature *h; int i;
    hObj hidden[HIDE_WATCH_MAX];
    int nHidden = 0;
    MapIterate(mp, h, i)
        if (h && h->isCreature() && h->HasStati(HIDING) && HideCanWatch(w, h)) {
            if (nHidden >= HIDE_WATCH_MAX) break;
            hidden[nHidden++] = h->myHandle;
        }
    /* SpotCheck throws an event whose scripts can delete w or h, so re-fetch w
       and the hider from their handles every pass and never touch a pointer
       captured before an earlier check. */
    for (int k = 0; k < nHidden; k++) {
        if (!isValidHandle(wHandle)) return;
        Creature *wk = oCreature(wHandle);
        if (!wk || wk->isDead() || (wk->Flags & F_DELETE)) return;
        if (!isValidHandle(hidden[k])) continue;
        Creature *hk = oCreature(hidden[k]);
        if (!hk || hk->isDead() || (hk->Flags & F_DELETE)) continue;
        if (!hk->HasStati(HIDING)) continue;
        if (wk->m != hk->m) continue;
        SpotCheck(wk, hk, 0);
    }
}

/* inc-yp23: what a watcher remembers about one creature between scans, so a
   pair is re-tested only when something changed. In memory only: never a field
   of Creature, so no class layout, FIELD_* list or save code changes. */
struct HcTrack {
    Creature *owner;      /* the pointer this entry was made for */
    int16 lx, ly;         /* last position seen (lazy move detection) */
    uint32 movedAt;       /* hcClock when this creature last changed square */
    uint32 scanAt;        /* hcClock of the owner's last scan */
    int16 fullRound;      /* last round the owner got a full re-test */
    int16 sr;             /* owner's SightRange last seen */
    bool blind;           /* owner's isBlind() last seen */
    bool asleep;          /* owner's HasStati(ASLEEP) last seen */
};
/* Ordered by hObj so the keys are deterministic (a check must not depend on the
   seed, and unordered iteration order could differ between runs). */
/* ponytail: this table is never pruned -- one entry per creature handle ever
   scanned, for the process lifetime. Ceiling is memory and log-n lookup on very
   long sessions. Upgrade path: erase an entry when its creature is destroyed
   (e.g. from the destroy queue in src/Main.cpp) or on map change. */
static std::map<hObj, HcTrack> hcTracks;

/* A module clock, bumped once per HidePairsFor: orders two scans in one tick. */
static uint32 hcClock = 0;

/* The track for the creature behind handle h and pointer c, made or repaired on
   demand. A missing entry, or one whose stored pointer differs (the handle was
   reused for a different creature), comes back changed -- which also covers a
   fresh game load, since the table starts empty. */
static HcTrack &hcTrackFor(hObj h, Creature *c) {
    HcTrack &t = hcTracks[h];
    if (t.owner != c) {
        t.owner = c;
        t.lx = c->x; t.ly = c->y;
        t.movedAt = ++hcClock;
        t.scanAt = 0;
        t.fullRound = (int16)-1;
        t.sr = c->SightRange;
        t.blind = c->isBlind();
        t.asleep = c->HasStati(ASLEEP);
    } else if (c->x != t.lx || c->y != t.ly) {
        t.lx = c->x; t.ly = c->y;
        t.movedAt = ++hcClock;
    }
    return t;
}

void HideStarted(Creature *h, bool rollNow) {
    if (!h) return;
    h->HideVal = (int8)(h->HideVal + 1);
    HideSetKey(h, HK_HIDE_BAND, h, HideLightBand(HideLightAt(h->m, h->x, h->y)));
    /* A new hide must be re-tested by every watcher: mark h moved now. */
    hcTrackFor(h->myHandle, h).movedAt = ++hcClock;
    if (rollNow) HideTrigger(h, 0);
}

bool HasCurrentResult(Creature *w, Creature *h) {
    if (!w || !h) return false;
    if (!w->HasStati(TRIED, HK_SPOT_RESULT, h)) return false;
    const int16 mag = w->GetStatiMag(TRIED, HK_SPOT_RESULT, h);
    return ((mag >> 1) & 0xFF) == (h->HideVal & 0xFF);
}

void HideUpdatePair(Creature *w, Creature *h) {
    if (!w || !h) return;
    if (!h->HasStati(HIDING)) return;
    if (HideCanWatch(w, h)) {
        /* A watcher that keeps sight holds a current result and does not roll
           again here; one that lost sight cleared its key and so rolls on
           regaining it. */
        if (!HasCurrentResult(w, h))
            SpotCheck(w, h, 0);
    } else if (w->HasStati(TRIED, HK_SPOT_RESULT, h)) {
        /* Cannot watch any more: forget any remembered verdict for h, so
           regaining sight next time starts a fresh check. */
        HideClearKey(w, HK_SPOT_RESULT, h);
    }
}

void HidePairsFor(Creature *x) {
    /* inc-yp23 invariants: (1) x is the WATCHER only -- no hider-side roll here;
       (2) a pair is re-tested only when x moved, y moved, y began a new hide, or
       x's own sight state changed; (3) a once-per-round backstop re-tests every
       in-range pair regardless; (4) all state is in hcTracks, memory only. */
    if (!x || !x->m) return;
    Map *mx = x->m;
    const hObj xHandle = x->myHandle;
    const uint32 now = ++hcClock;

    /* x's own track: refresh position, then decide whether this scan is full. */
    HcTrack &xt = hcTrackFor(xHandle, x);
    const bool stateChanged = xt.sr != x->SightRange ||
                              xt.blind != x->isBlind() ||
                              xt.asleep != x->HasStati(ASLEEP);
    xt.sr = x->SightRange;
    xt.blind = x->isBlind();
    xt.asleep = x->HasStati(ASLEEP);
    const int16 round = HideRoundStamp();
    const bool full = xt.fullRound != round ||
                      xt.movedAt > xt.scanAt || stateChanged;
    /* inc-yp23: a hider re-tests when its move or new hide is later than
       this watcher's PREVIOUS scan. Stamp this scan after refreshing x so
       x's own move causes one full scan, not two. */
    const uint32 prevScan = xt.scanAt;
    xt.scanAt = hcClock;
    if (full) xt.fullRound = round;

    /* One map pass, creatures only, same map, not x, this watcher's range. */
    hObj others[HIDE_WATCH_MAX];
    int nOthers = 0;
    bool anyHiding = false;
    { Creature *y; int i;
      MapIterate(mx, y, i) {
          if (!y || !y->isCreature() || y == x) continue;
          if (y->m != mx || y->x == -1) continue;
          if (dist(x->x, x->y, y->x, y->y) > (int16)x->SightRange) continue;
          if (y->HasStati(HIDING)) anyHiding = true;
          if (nOthers >= HIDE_WATCH_MAX) break;
          others[nOthers++] = y->myHandle;
      } }
    /* x's scanAt and track are already updated above, so a bare return here is
       safe: with nothing hiding in range no pair can change this scan. */
    if (!anyHiding) return;

    /* Each HideUpdatePair can run SpotCheck, whose event runs scripts that can
       delete any creature, so re-fetch both creatures from their handles every
       pass and never touch a pointer captured before an earlier check. */
    for (int k = 0; k < nOthers; k++) {
        if (!isValidHandle(xHandle) || !isValidHandle(others[k])) continue;
        Creature *xk = oCreature(xHandle);
        if (!xk || xk->isDead() || (xk->Flags & F_DELETE) || !xk->m) break;
        Creature *yk = oCreature(others[k]);
        if (!yk || yk->isDead() || (yk->Flags & F_DELETE)) continue;
        if (yk->m != xk->m) continue;
        if (!yk->HasStati(HIDING)) continue;
        /* Detect y's move lazily, now, before deciding. */
        const HcTrack &yt = hcTrackFor(others[k], yk);
        if (full || yt.movedAt > prevScan) {
            /* inc-yp23: observe pair re-tests, independent of cached verdicts. */
            if (getenv("INCURSION_HIDE_PAIRS_PROBE"))
                Error("HIDE_PAIRS CALL watcher=%d hider=%d",
                    (int)xk->myHandle, (int)yk->myHandle);
            HideUpdatePair(xk, yk);
        }
    }
}

/* inc-yp23: erase one TRIED note by (key, source handle) without a Thing*.
   HideClearKey(c, key, NULL) would match every source, so the invalid-handle
   case in HideTurnStart needs this handle-exact removal. */
static void hcClearNoteByHandle(Creature *c, int16 key, hObj h) {
    if (!c) return;
    StatiIterNature(c, TRIED)
        if (S->Val == key && S->h == h)
            Stati_RemoveInline(S, c);
    StatiIterEnd(c)
}

void HideTurnStart(Creature *x) {
    if (!x) return;
    const hObj xHandle = x->myHandle;

    /* (a) The light on the hider's square changed band: re-stamp and trigger. */
    if (x->HasStati(HIDING) && x->m) {
        const int16 band = HideLightBand(HideLightAt(x->m, x->x, x->y));
        if (!x->HasStati(TRIED, HK_HIDE_BAND, x) ||
            x->GetStatiMag(TRIED, HK_HIDE_BAND, x) != band) {
            HideSetKey(x, HK_HIDE_BAND, x, band);
            HideTrigger(x, 0);
        }
    }

    /* (b) Line of sight or light changed for x's neighbours. inc-yp23: a
       watcher erases its own out-of-range notes here, at its own action, since
       the range-filtered HidePairsFor no longer walks those pairs. */
    if (!isValidHandle(xHandle)) return;
    x = oCreature(xHandle);
    if (!x || x->isDead() || (x->Flags & F_DELETE)) return;
    if (x->m) {
        hObj stale[HIDE_WATCH_MAX];
        int nStale = 0;
        StatiIterNature(x, TRIED)
            if (S->Val == HK_SPOT_RESULT) {
                Creature *h = isValidHandle(S->h) ? oCreature(S->h) : NULL;
                if (!h || h->isDead() || (h->Flags & F_DELETE) ||
                    h->m != x->m || h->x == -1 ||
                    dist(x->x, x->y, h->x, h->y) > (int16)x->SightRange) {
                    if (nStale < HIDE_WATCH_MAX) stale[nStale++] = S->h;
                }
            }
        StatiIterEnd(x)
        for (int k = 0; k < nStale; k++)
            hcClearNoteByHandle(x, HK_SPOT_RESULT, stale[k]);
    }
    if (!isValidHandle(xHandle)) return;
    x = oCreature(xHandle);
    if (!x || x->isDead() || (x->Flags & F_DELETE)) return;
    HidePairsFor(x);

    /* (c) This action spent x's distraction. */
    if (!isValidHandle(xHandle)) return;
    x = oCreature(xHandle);
    if (!x || x->isDead() || (x->Flags & F_DELETE)) return;
    HideClearKey(x, HK_DISTRACT, NULL);
}
