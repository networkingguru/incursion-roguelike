/* inc-u3dp phase 1, part 3: exercise the pure hide-check modifier functions
   (inc/HideCheck.h, src/HideCheck.cpp) and compare each result to the literal
   expected value from the rules. A no-op unless INCURSION_HIDE_MOD_PROBE is
   set. Caller: Game::Play (src/Main.cpp), beside HideProbe. Reader:
   tools/check_hide_modifiers.sh.
   One line per case:  HIDE_MOD case=<name> expect=<n> got=<n>

   Sight notes (reported in the probe report, not fixed here):
   - The chargen fixture builds an ORC rogue, and the orc player race grants
     CA_INFRAVISION 6 (lib/races.irh:1855, applied to Abilities[]). To drive the
     exact sight modes the rules name, the probe sets the watcher's public
     InfraRange field directly (Creature.h:264-267) after any CalcValues, and
     grants/removes CA_LOWLIGHT through the engine's own EXTRA_ABILITY stati.
   - Items for ItemSizePenalty are made with the engine factory
     Item::Create(FIND(name)); no item of Size 0 ships in this module, so the
     literal 0 case is not emitted (1 and 2 already cover the 0,1,2 -> 0 arm). */
#include "Incursion.h"
#include "HideCheck.h"

static int hmFails = 0;

static void hmEmit(const char *name, int expect, int got) {
    Error("HIDE_MOD case=%s expect=%d got=%d", name, expect, got);
    if (expect != got) hmFails++;
}

static bool hmOpen(Map *mp, int x, int y) {
    return mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FCreatureAt(x, y);
}

/* First open square at exactly distance d from (px,py). */
static bool hmAtDist(Map *mp, int px, int py, int d, int *ox, int *oy) {
    for (int dy = -d; dy <= d; dy++)
        for (int dx = -d; dx <= d; dx++) {
            if (dist(px, py, px + dx, py + dy) != d) continue;
            if (hmOpen(mp, px + dx, py + dy)) {
                *ox = px + dx; *oy = py + dy;
                return true;
            }
        }
    return false;
}

static Monster *hmSpawn(Map *mp, const char *name, int x, int y) {
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

void HideModProbe(Player *pl) {
    /* inc-u3dp: hook for tools/check_hide_modifiers.sh. */
    if (!getenv("INCURSION_HIDE_MOD_PROBE")) return;
    if (!pl || !pl->m) {
        Error("HIDE_MOD INCONCLUSIVE no live player and map");
        return;
    }
    Map *mp = pl->m;
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;

    const int turn = (int)theGame->Turn;
    Error("HIDE_MOD setup turn=%d x=%d y=%d", turn, (int)pl->x, (int)pl->y);

    /* The hider is one awake giant rat, moved for each distance. */
    int hx, hy;
    if (!hmAtDist(mp, pl->x, pl->y, 1, &hx, &hy)) {
        Error("HIDE_MOD INCONCLUSIVE no open square at distance 1");
        theGame->PlayMode = wasInPlay;
        return;
    }
    Monster *hid = hmSpawn(mp, "giant rat", hx, hy);
    if (!hid) {
        Error("HIDE_MOD INCONCLUSIVE no giant rat");
        theGame->PlayMode = wasInPlay;
        return;
    }

    /* Clear any sight modes the race gave the watcher; drive them by hand. */
    pl->RemoveStati(EXTRA_ABILITY, -1, CA_LOWLIGHT);
    pl->RemoveStati(EXTRA_ABILITY, -1, CA_INFRAVISION);
    pl->InfraRange = 0;
    const bool wasLit = mp->At(pl->x, pl->y).Lit;

    /* Place the hider at distance d and return the spot sum at Lh,Lw. */
#define SPOT_AT(d, Lh, Lw)                                                   \
    (hmAtDist(mp, pl->x, pl->y, (d), &hx, &hy)                               \
        ? (hid->PlaceAt(mp, hx, hy),                                          \
           HideSpotModifiersForTest(pl, hid, (uint8)(Lh), (uint8)(Lw)))       \
        : (Error("HIDE_MOD INCONCLUSIVE cannot place hider at d=%d", (d)),   \
           hmFails++, 9999))

    /* Distance: -1 per square. Bright both squares: no darkness, no watcher
       term. */
    hmEmit("spot_dist1", -1, SPOT_AT(1, 90, 90));
    hmEmit("spot_dist3", -3, SPOT_AT(3, 90, 90));
    hmEmit("spot_dist8", -8, SPOT_AT(8, 90, 90));

    /* Darkness, normal sight, watcher not lit (Lw==Lh). d=1. */
    hmEmit("spot_dark_norm_47", -21, SPOT_AT(1, 47, 47));
    hmEmit("spot_dark_norm_48", -21, SPOT_AT(1, 48, 48));
    hmEmit("spot_dark_norm_69", -11, SPOT_AT(1, 69, 69));
    hmEmit("spot_dark_norm_90",  -1, SPOT_AT(1, 90, 90));

    /* Darkness, low-light sight, watcher not lit. d=1. */
    pl->GainPermStati(EXTRA_ABILITY, NULL, SS_MISC, CA_LOWLIGHT, 1);
    pl->InfraRange = 0;
    hmEmit("spot_dark_low_0",  -21, SPOT_AT(1,  0,  0));
    hmEmit("spot_dark_low_24", -16, SPOT_AT(1, 24, 24));
    hmEmit("spot_dark_low_45", -11, SPOT_AT(1, 45, 45));
    hmEmit("spot_dark_low_89",  -1, SPOT_AT(1, 89, 89));
    hmEmit("spot_dark_low_90",  -1, SPOT_AT(1, 90, 90));
    pl->RemoveStati(EXTRA_ABILITY, -1, CA_LOWLIGHT);
    pl->InfraRange = 0;

    /* Infravision: in range -> darkness 0 at any L, watcher-in-light skipped;
       out of range -> falls back to normal sight. */
    pl->InfraRange = 3;
    hmEmit("spot_infra_in_range", -1, SPOT_AT(1, 0, 200));
    pl->InfraRange = 1;
    hmEmit("spot_infra_out_range", -23, SPOT_AT(3, 0, 0));
    pl->InfraRange = 0;

    /* Watcher in light (normal sight), Lh=90 so darkness is 0; d=1. */
    hmEmit("spot_wl_diff0",   -1, SPOT_AT(1, 90,  90));
    hmEmit("spot_wl_diff16",  -2, SPOT_AT(1, 90, 106));
    hmEmit("spot_wl_diff160", -11, SPOT_AT(1, 90, 250));
    hmEmit("spot_wl_diff255", -11, SPOT_AT(1, 90, 255));

    /* Distraction and roar on the watcher. Bright squares, d=1. */
    pl->RemoveStati(TRIED);
    HideSetKey(pl, HK_DISTRACT, NULL, 0);
    hmEmit("spot_distract_once", -6, SPOT_AT(1, 90, 90));
    HideSetKey(pl, HK_DISTRACT, NULL, 0);
    hmEmit("spot_distract_twice", -6, SPOT_AT(1, 90, 90));
    pl->RemoveStati(TRIED);

    /* HK_ROAR's Mag is a signed 16-bit Status field (inc/Res.h:325), but
       theGame->Turn is 32-bit and already ~198000 in a fresh game, so the key
       stores a 15-bit round stamp (HideRoundStamp) rather than a raw Turn.
       No Turn override is needed: the stamp fits however large Turn is. */
    HideSetKey(pl, HK_ROAR, NULL, HideRoundStamp());
    hmEmit("spot_roar_live", -11, SPOT_AT(1, 90, 90));
    HideSetKey(pl, HK_ROAR, NULL, (int16)((HideRoundStamp() - 2) & 0x7FFF));
    hmEmit("spot_roar_live2", -11, SPOT_AT(1, 90, 90));
    HideSetKey(pl, HK_ROAR, NULL, (int16)((HideRoundStamp() - 3) & 0x7FFF));
    hmEmit("spot_roar_expired", -1, SPOT_AT(1, 90, 90));
    pl->RemoveStati(TRIED);

    /* Listen: no light or sight term. Watcher is a plain giant rat. */
    int wx, wy;
    if (!hmAtDist(mp, pl->x, pl->y, 1, &wx, &wy)) {
        Error("HIDE_MOD INCONCLUSIVE no open square for the listener");
        hid->Remove(true);
        theGame->PlayMode = wasInPlay;
        return;
    }
    Monster *wat = hmSpawn(mp, "giant rat", wx, wy);
    if (!wat) {
        Error("HIDE_MOD INCONCLUSIVE no listener");
        hid->Remove(true);
        theGame->PlayMode = wasInPlay;
        return;
    }

    hmEmit("listen_base", 0, ListenModifiers(wat));

    /* Light must not enter ListenModifiers: same value at L=0 and L=89. */
    mp->At(wat->x, wat->y).Lit = 0;
    hmEmit("listen_light0", 0, ListenModifiers(wat));
    mp->At(wat->x, wat->y).Lit = 1;
    hmEmit("listen_light89", 0, ListenModifiers(wat));
    mp->At(wat->x, wat->y).Lit = 0;

    HideSetKey(wat, HK_DISTRACT, NULL, 0);
    hmEmit("listen_distract", -5, ListenModifiers(wat));
    wat->RemoveStati(TRIED);

    HideSetKey(wat, HK_ROAR, NULL, HideRoundStamp());
    hmEmit("listen_roar_live", -10, ListenModifiers(wat));
    HideSetKey(wat, HK_ROAR, NULL, (int16)((HideRoundStamp() - 3) & 0x7FFF));
    hmEmit("listen_roar_expired", 0, ListenModifiers(wat));
    wat->RemoveStati(TRIED);

    /* Song: a second creature with SINGING (Mag = its range). */
    int sx, sy;
    if (!hmAtDist(mp, wat->x, wat->y, 1, &sx, &sy)) {
        Error("HIDE_MOD INCONCLUSIVE no open square for the singer");
        wat->Remove(true);
        hid->Remove(true);
        theGame->PlayMode = wasInPlay;
        return;
    }
    Monster *singer = hmSpawn(mp, "giant rat", sx, sy);
    if (!singer) {
        Error("HIDE_MOD INCONCLUSIVE no singer");
        wat->Remove(true);
        hid->Remove(true);
        theGame->PlayMode = wasInPlay;
        return;
    }
    singer->GainPermStati(SINGING, NULL, SS_MISC, 0, 2);
    hmEmit("listen_song_in_range", -5, ListenModifiers(wat));

    /* Out of range: stretch the listener away from the singer. */
    const int rangeWanted = 1;
    singer->SetStatiMag(SINGING, -1, NULL, rangeWanted);
    if (hmAtDist(mp, singer->x, singer->y, 3, &wx, &wy))
        wat->PlaceAt(mp, wx, wy);
    hmEmit("listen_song_out_range", 0, ListenModifiers(wat));

    /* A deaf listener hears nothing even in range. */
    singer->SetStatiMag(SINGING, -1, NULL, 4);
    if (hmAtDist(mp, singer->x, singer->y, 1, &wx, &wy)) {
        Monster *deaf = hmSpawn(mp, "devilfish", wx, wy);
        if (deaf) {
            hmEmit("listen_song_deaf", 0, ListenModifiers(deaf));
            deaf->Remove(true);
        } else {
            Error("HIDE_MOD INCONCLUSIVE no devilfish");
            hmFails++;
        }
    } else {
        Error("HIDE_MOD INCONCLUSIVE no open square for the deaf listener");
        hmFails++;
    }

    /* The singer is not its own audience. */
    hmEmit("listen_song_self", 0, ListenModifiers(singer));

    singer->Remove(true);
    wat->Remove(true);

    /* Hider-side modifiers. */
    hmEmit("hider_normal", 0, HiderModifiers(hid));
    hid->GainPermStati(SPRINTING, NULL, SS_MISC, 0, 0);
    hmEmit("hider_sprinting", -20, HiderModifiers(hid));
    hid->RemoveStati(SPRINTING);

    /* Item size penalties. */
    {
        static const struct { const char *name; const char *item; int expect; }
        its[] = {
            { "itemsize_1", "ring",            0 },
            { "itemsize_2", "viewing lens",    0 },
            { "itemsize_3", "climbing rig",   -2 },
            { "itemsize_4", "medium backpack", -5 },
            { "itemsize_5", "large oak chest",  -8 },
            { "itemsize_6", "huge club",      -10 },
        };
        for (unsigned k = 0; k < sizeof(its) / sizeof(its[0]); k++) {
            Item *it = Item::Create(FIND(its[k].item));
            if (!it) { Error("HIDE_MOD INCONCLUSIVE no item %s", its[k].item); hmFails++; continue; }
            hmEmit(its[k].name, its[k].expect, ItemSizePenalty(it));
            it->Remove(true);
        }
    }

    mp->At(pl->x, pl->y).Lit = wasLit;
    hid->Remove(true);
    theGame->PlayMode = wasInPlay;
    Error("HIDE_MOD COMPLETE fails=%d", hmFails);
}
