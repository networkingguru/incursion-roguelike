/* inc-u3dp phase 2a-1: exercise the opposed hide/spot check, the stored result
   and the trigger loop (inc/HideCheck.h, src/HideCheck.cpp). A no-op unless
   INCURSION_HIDE_ROLL_PROBE is set. Caller: Game::Play (src/Main.cpp), beside
   HideModProbe. Reader: tools/check_hide_roll.sh.
   One line per case:  HIDE_ROLL case=<name> expect=<n> got=<n>

   The scene is the player (a rogue) hiding in a bright room with a hostile
   monster in line of sight, exactly as HideProbe sets up its hider. The
   modifier gap is driven through SpotCheck's hiderPenalty argument: the probe
   computes the base gap once with the same SkillLevel/SpotModifiers/HiderModifiers
   functions the check uses, then asks for penalty = base +/- 30. That setup
   arithmetic is not the oracle; the oracle is the literal expected value on
   each HIDE_ROLL line.

   The RNG no-consume proof uses a counter, not a state snapshot: MT19937's
   state (mt[N], mti) is static in src/Base.cpp with no accessor, so it cannot
   be saved and restored from here. The probe arms HideRollArmRngCount and
   watches HideRollRngCount across 100 IsSpotted calls. */
#include "Incursion.h"
#include "HideCheck.h"

static int hrFails = 0;

static void hrEmit(const char *name, int expect, int got) {
    Error("HIDE_ROLL case=%s expect=%d got=%d", name, expect, got);
    if (expect != got) hrFails++;
}

static bool hrOpen(Map *mp, int x, int y) {
    return mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FCreatureAt(x, y);
}

static bool hrAtDist(Map *mp, int px, int py, int d, int *ox, int *oy) {
    for (int dy = -d; dy <= d; dy++)
        for (int dx = -d; dx <= d; dx++) {
            if (dist(px, py, px + dx, py + dy) != d) continue;
            if (hrOpen(mp, px + dx, py + dy)) {
                *ox = px + dx; *oy = py + dy;
                return true;
            }
        }
    return false;
}

static Monster *hrSpawn(Map *mp, const char *name, int x, int y) {
    const rID id = FIND(name);
    if (!id) return NULL;
    Monster *m = new Monster(id);
    TMON(m->tmID)->GrantGear(m, m->tmID, true);
    TMON(m->tmID)->PEvent(EV_BIRTH, m, m->tmID);
    m->PlaceAt(mp, x, y);
    m->Initialize(true);
    m->RemoveStati(SLEEPING);
    m->RemoveStati(ASLEEP);
    return m;
}

/* The base gap the opposed check will use, computed with the check's own terms
   so the probe can null it out or push it to +/- 30. Setup, not oracle. */
static int hrBaseGap(Creature *w, Creature *h) {
    return (w->SkillLevel(SK_SPOT) + SpotModifiers(w, h))
         - (h->SkillLevel(SK_HIDE) + HiderModifiers(h));
}

static int hrCountWatchKeys(Creature *w, Creature *h) {
    int16 c = 0;
    StatiIterNature(w, TRIED)
        if (S->Val == HK_SPOT_RESULT && S->h == h->myHandle)
            c++;
    StatiIterEnd(w)
    return c;
}

/* Does any creature on the map other than the hider hold an HK_SPOT_RESULT
   entry? (used to count how many watchers the trigger loop rolled for) */
static int hrCountWatchersWithKey(Map *mp, Creature *h) {
    int16 c = 0; Creature *cr; int i;
    MapIterate(mp, cr, i)
        if (cr && cr->isCreature() && cr != h)
            StatiIterNature(cr, TRIED)
                if (S->Val == HK_SPOT_RESULT)
                    c++;
            StatiIterEnd(cr)
    return c;
}

void HideRollProbe(Player *pl) {
    /* inc-u3dp: hook for tools/check_hide_roll.sh. */
    if (!getenv("INCURSION_HIDE_ROLL_PROBE")) return;
    if (!pl || !pl->m) {
        Error("HIDE_ROLL INCONCLUSIVE no live player and map");
        return;
    }
    Map *mp = pl->m;
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;

    int hx, hy;
    if (!hrAtDist(mp, pl->x, pl->y, 2, &hx, &hy)) {
        Error("HIDE_ROLL INCONCLUSIVE no open square at distance 2");
        theGame->PlayMode = wasInPlay;
        return;
    }
    Monster *hid = hrSpawn(mp, "giant rat", hx, hy);
    if (!hid) {
        Error("HIDE_ROLL INCONCLUSIVE no giant rat");
        theGame->PlayMode = wasInPlay;
        return;
    }

    /* Bright room, plain normal sight on the watcher: kills the light term so
       the gap arithmetic is exact and reproducible. */
    const bool wasLit = mp->At(pl->x, pl->y).Lit;
    mp->At(pl->x, pl->y).Lit = 1;
    pl->RemoveStati(EXTRA_ABILITY, -1, CA_LOWLIGHT);
    pl->RemoveStati(EXTRA_ABILITY, -1, CA_INFRAVISION);
    pl->InfraRange = 0;
    pl->CalcVision();

    /* The player hides, epoch 1, no immediate roll. */
    pl->RemoveStati(HIDING);
    pl->GainPermStati(HIDING, NULL, SS_CLAS, HI_SHADOWS, 1);
    hid->RemoveStati(HIDING);
    hid->GainPermStati(HIDING, NULL, SS_CLAS, HI_SHADOWS, 1);
    HideStarted(pl, false);

    pl->RemoveStati(TRIED);

    const int base = hrBaseGap(pl, hid);
    Error("HIDE_ROLL setup gap=%d hideval=%d hide=%d spot=%d",
        base, (int)pl->HideVal, (int)hid->HideVal, (int)pl->SkillLevel(SK_SPOT));

    /* --- gap +30: every roll spotted. Pollutes TRIED; cleared after. --- */
    {
        int n = 0;
        for (int k = 0; k < 200; k++)
            if (SpotCheck(pl, hid, (int16)(base - 30))) n++;
        hrEmit("gap_pos30_all_spotted", 1, n == 200 ? 1 : 0);
    }

    /* --- gap -30: no roll spotted. --- */
    {
        int n = 0;
        for (int k = 0; k < 200; k++)
            if (SpotCheck(pl, hid, (int16)(base + 30))) n++;
        hrEmit("gap_neg30_none_spotted", 1, n == 0 ? 1 : 0);
    }

    /* --- equal modifiers: both outcomes, spotted share 35..65%. --- */
    {
        int n = 0;
        for (int k = 0; k < 400; k++)
            if (SpotCheck(pl, hid, (int16)base)) n++;
        hrEmit("equal_both_outcomes", 1, (n > 0 && n < 400) ? 1 : 0);
        const int pct = (n * 100) / 400;
        hrEmit("equal_share_in_range", 1, (pct >= 35 && pct <= 65) ? 1 : 0);
    }

    /* --- hider 10 ahead: hiderPenalty = base + 10. The watcher's d20 must beat
       the hider's by 11+, so spotted is about 11% and both outcomes occur. If
       the watcher's die is a constant 10, 10 + wm > d20 + wm + 10 is
       impossible, so spotted never occurs. --- */
    {
        int n = 0;
        for (int k = 0; k < 400; k++)
            if (SpotCheck(pl, hid, (int16)(base + 10))) n++;
        Error("HIDE_ROLL share=hider_ahead_10 spotted=%d of 400", n);
        hrEmit("hider_ahead_10_spotted_occurs", 1,
            (n > 0 && n < 400) ? 1 : 0);
    }

    /* --- watcher 10 ahead: hiderPenalty = base - 10. The hider's d20 must beat
       the watcher's by 11+ for a miss, so not-spotted is about 11%. If the
       hider's die is a constant 10, not-spotted (d20 + wm < 10 + hm, and wm =
       hm + 10) is impossible, so at most a handful (on ties) occur. --- */
    {
        int n = 0;
        for (int k = 0; k < 400; k++)
            if (SpotCheck(pl, hid, (int16)(base - 10))) n++;
        const int miss = 400 - n;
        Error("HIDE_ROLL share=watcher_ahead_10 not_spotted=%d of 400", miss);
        hrEmit("watcher_ahead_10_notspotted_occurs", 1,
            (miss >= 5) ? 1 : 0);
    }

    /* --- IsSpotted follows the stored verdict. --- */
    {
        pl->RemoveStati(TRIED);
        bool hit = SpotCheck(pl, hid, (int16)(base - 30));
        hrEmit("is_spotted_after_hit", 1,
            (hit && IsSpotted(pl, hid)) ? 1 : 0);

        pl->RemoveStati(TRIED);
        bool miss = SpotCheck(pl, hid, (int16)(base + 30));
        hrEmit("is_spotted_after_miss", 0,
            (miss ? 1 : (IsSpotted(pl, hid) ? 1 : 0)));

        /* A new epoch makes the stored result stale. */
        HideStarted(pl, false);
        hrEmit("is_spotted_stale_after_bump", 0,
            IsSpotted(pl, hid) ? 1 : 0);
        pl->RemoveStati(TRIED);
    }

    /* --- HideSetKey keeps exactly one entry per (key, source). --- */
    {
        pl->RemoveStati(TRIED);
        for (int k = 0; k < 50; k++)
            SpotCheck(pl, hid, (int16)base);
        hrEmit("one_entry_after_50", 1, hrCountWatchKeys(pl, hid) == 1 ? 1 : 0);
        pl->RemoveStati(TRIED);
    }

    /* --- IsSpotted draws nothing from the RNG. --- */
    {
        HideRollArmRngCount(true);
        const unsigned long long before = HideRollRngCount();
        (void)Dice::Roll(1, 20); (void)Dice::Roll(1, 20);
        (void)Dice::Roll(1, 20); (void)Dice::Roll(1, 20);
        (void)Dice::Roll(1, 20);
        const unsigned long long mid = HideRollRngCount();
        for (int k = 0; k < 100; k++) (void)IsSpotted(pl, hid);
        const unsigned long long after = HideRollRngCount();
        HideRollArmRngCount(false);
        hrEmit("is_spotted_rng_unchanged", 1,
            (mid - before == 5 && after == mid) ? 1 : 0);
    }

    /* --- HideCanWatch refusals. --- */
    {
        pl->RemoveStati(TRIED);
        int wx, wy;
        if (!hrAtDist(mp, hid->x, hid->y, 1, &wx, &wy)) {
            Error("HIDE_ROLL INCONCLUSIVE no open square for a watcher");
            hrFails++;
        } else {
            Monster *wat = hrSpawn(mp, "giant rat", wx, wy);
            if (!wat) { Error("HIDE_ROLL INCONCLUSIVE no watcher"); hrFails++; }
            else {
                const int control = HideCanWatch(wat, hid) ? 1 : 0;
                if (!control) {
                    Error("HIDE_ROLL INCONCLUSIVE watcher has no LOS to hider");
                    hrFails++;
                }
                wat->GainPermStati(ASLEEP, NULL, SS_MISC, 0, 10);
                hrEmit("canwatch_asleep", 0, HideCanWatch(wat, hid) ? 1 : 0);
                wat->RemoveStati(ASLEEP);
                wat->Remove(true);
            }
        }
        hrEmit("canwatch_self", 0, HideCanWatch(hid, hid) ? 1 : 0);

        /* Behind a wall: watch along the line the control watcher used, with
           the cell between made Opaque. */
        int bx, by;
        if (hrAtDist(mp, pl->x, pl->y, 2, &bx, &by)) {
            Monster *far = hrSpawn(mp, "giant rat", bx, by);
            if (!far) { Error("HIDE_ROLL INCONCLUSIVE no far watcher"); hrFails++; }
            else {
                const int mx = (pl->x + bx) / 2, my = (pl->y + by) / 2;
                const unsigned wasOpaque = mp->At(mx, my).Opaque;
                mp->At(mx, my).Opaque = 1;
                hrEmit("canwatch_behind_wall", 0,
                    HideCanWatch(far, pl) ? 1 : 0);
                mp->At(mx, my).Opaque = wasOpaque;
                far->Remove(true);
            }
        } else {
            Error("HIDE_ROLL INCONCLUSIVE no square for the far watcher");
            hrFails++;
        }
    }

    /* --- HideTrigger rolls once per eligible watcher. Two monsters in sight,
       one asleep; the player is put to sleep so only the awake monster rolls.
       Count the stored results: exactly one watcher holds HK_SPOT_RESULT. --- */
    {
        int wx, wy;
        pl->RemoveStati(TRIED);
        hid->RemoveStati(TRIED);
        pl->RemoveStati(HIDING);
        hid->RemoveStati(HIDING);
        /* The hider for this case is a fresh monster. */
        hid->GainPermStati(HIDING, NULL, SS_CLAS, HI_SHADOWS, 1);
        HideStarted(hid, false);

        int a[2][2]; int na = 0;
        for (int k = 0; k < 2 && na < 2; k++) {
            int d = 1 + k;
            if (hrAtDist(mp, hid->x, hid->y, d, &wx, &wy)) {
                a[na][0] = wx; a[na][1] = wy; na++;
            }
        }
        if (na < 2) {
            Error("HIDE_ROLL INCONCLUSIVE room for only %d watchers", na);
            hrFails++;
        } else {
            Monster *m1 = hrSpawn(mp, "giant rat", a[0][0], a[0][1]);
            Monster *m2 = hrSpawn(mp, "giant rat", a[1][0], a[1][1]);
            if (!m1 || !m2) {
                Error("HIDE_ROLL INCONCLUSIVE watcher spawn failed");
                hrFails++;
            } else {
                if (m1->m != hid->m || !HideCanWatch(m1, hid) ||
                    !HideCanWatch(m2, hid)) {
                    Error("HIDE_ROLL INCONCLUSIVE a watcher cannot see the hider");
                    hrFails++;
                }
                m2->GainPermStati(ASLEEP, NULL, SS_MISC, 0, 10);
                /* Silence the player as a watcher. */
                pl->GainPermStati(ASLEEP, NULL, SS_MISC, 0, 10);

                HideTrigger(hid, 0);

                const int nKeys = hrCountWatchersWithKey(mp, hid);
                hrEmit("trigger_one_event", 1, nKeys == 1 ? 1 : 0);

                pl->RemoveStati(ASLEEP);
                if (m1) m1->Remove(true);
                if (m2) m2->Remove(true);
            }
        }
    }

    mp->At(pl->x, pl->y).Lit = wasLit;
    pl->RemoveStati(HIDING);
    pl->CalcVision();
    if (hid) hid->Remove(true);
    theGame->PlayMode = wasInPlay;
    Error("HIDE_ROLL COMPLETE fails=%d", hrFails);
}
