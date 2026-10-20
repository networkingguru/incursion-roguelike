/* inc-u3dp phase 5: searching finds hidden creatures. A no-op unless
   INCURSION_HIDE_SEARCH_PROBE is set. Caller: Game::Play (src/Main.cpp),
   beside HideTriggerProbe. Reader: tools/check_hide_search.sh.

   The probe plays three scenes (run in the order DOOR, MON, SCENE):
     DOOR  a secret door beside the player, found through the real
           Creature::Search (Throw of EV_SEARCH);
     SCENE a hidden monster in the player's sight with a stored "not spotted"
           result; the key script then presses the search key, whose rolls are
           logged by SpotCheck's HIDE_TRIGGER_ROLL probe line;
     MON   one monster that has a hostile target it cannot see (ts vis == 0)
           and one with no target, each driven through 60 real ChooseAction
           calls; only the first may propose ACT_SEARCH, and each search rolls
           against the hidden player.

   The probe never calls HideSearch itself: the player scene is driven by the
   key script, the door by Throw(EV_SEARCH,...), and the monsters by
   ChooseAction. */
#include "Incursion.h"
#include "HideCheck.h"

static bool hsOpen(Map *mp, int x, int y) {
    return mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FCreatureAt(x, y);
}

static bool hsAtDist(Map *mp, int px, int py, int d, int *ox, int *oy) {
    for (int dy = -d; dy <= d; dy++)
        for (int dx = -d; dx <= d; dx++) {
            if (dist(px, py, px + dx, py + dy) != d) continue;
            if (hsOpen(mp, px + dx, py + dy)) {
                *ox = px + dx; *oy = py + dy;
                return true;
            }
        }
    return false;
}

static Monster *hsSpawn(Map *mp, const char *name, int x, int y) {
    const rID id = FIND(name);
    if (!id) return NULL;
    Monster *m = new Monster(id);
    TMON(m->tmID)->GrantGear(m, m->tmID, true);
    TMON(m->tmID)->PEvent(EV_BIRTH, m, m->tmID);
    m->PlaceAt(mp, x, y);
    m->Initialize(true);
    m->RemoveStati(SLEEPING);
    m->RemoveStati(ASLEEP);
    m->SightRange = 20;
    return m;
}

void HideSearchProbe(Player *pl) {
    if (!getenv("INCURSION_HIDE_SEARCH_PROBE")) return;
    if (!pl || !pl->m) { Error("HIDE_SEARCH INCONCLUSIVE no live player and map"); return; }
    Map *mp = pl->m;
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    const int8 autoMore = pl->Options[OPT_AUTOMORE];
    pl->Options[OPT_AUTOMORE] = 1;

    /* Everything already on the map sleeps, so no unrelated creature halts the
       player's search with a "hostile" prompt. */
    Creature *c; int idx;
    MapIterate(mp, c, idx)
        if (c->isCreature() && c != pl)
            c->GainPermStati(ASLEEP, NULL, SS_MISC);

    /* --- DOOR: a secret door beside the player, found by the real Search. --- */
    int dx, dy;
    if (!hsAtDist(mp, pl->x, pl->y, 1, &dx, &dy)) {
        Error("HIDE_SEARCH INCONCLUSIVE no adjacent open square for the door");
        pl->Options[OPT_AUTOMORE] = autoMore; theGame->PlayMode = wasInPlay; return;
    }
    Door *door = new Door(FIND("oak door"));
    door->PlaceAt(mp, dx, dy);
    door->DoorFlags = DF_SECRET;
    door->SetImage();
    mp->At(dx, dy).Lit = true;
    pl->CalcVision();
    pl->GainPermStati(SKILL_BONUS, NULL, SS_MISC, SK_SEARCH, 100);
    Throw(EV_SEARCH, pl, NULL, NULL);
    const bool found = (door->DoorFlags & DF_SECRET) == 0;
    Error("HIDE_SEARCH DOOR found=%d", found ? 1 : 0);
    if (!found) {
        Error("HIDE_SEARCH INCONCLUSIVE secret door was not found");
        pl->Options[OPT_AUTOMORE] = autoMore; theGame->PlayMode = wasInPlay; return;
    }

    /* --- MON: 60 real ChooseAction calls for each monster. Runs before SCENE
       so a loss monster cannot walk to the hidden rat and kill it. --- */
    /* The player hides, so a monster that targets it cannot see it (ts vis ==
       0) -- the "lost sight" case. */
    pl->RemoveStati(HIDING);
    pl->GainPermStati(HIDING, NULL, SS_CLAS, HI_SHADOWS, 1);
    HideStarted(pl, false);
    /* The player hides far better than any rat searches, so the searches the
       monsters make do not spot it and the target stays lost. */
    pl->GainPermStati(SKILL_BONUS, NULL, SS_MISC, SK_HIDE, 100);
    int mx, my, cx, cy;
    hsAtDist(mp, pl->x, pl->y, 4, &mx, &my);
    hsAtDist(mp, pl->x, pl->y, 5, &cx, &cy);
    Monster *loss = hsSpawn(mp, "giant rat", mx, my);
    Monster *ctrl = hsSpawn(mp, "giant rat", cx, cy);
    if (loss && ctrl) {
        loss->ts.giveOrder(loss, NULL, OrderDoNotHide);
        ctrl->ts.giveOrder(ctrl, NULL, OrderDoNotHide);
        loss->ts.addCreatureTarget(pl, TargetEnemy);   /* vis == 0: cannot see player */
        /* A stored "not spotted" verdict, so the first ChooseAction does not
           roll a spot and see the player. */
        HideSetKey(loss, HK_SPOT_RESULT, pl, (int16)(((pl->HideVal & 0xFF) << 1) | 0));
        for (int k = 0; k < 60; k++) {
            loss->Timeout = 0;
            loss->ChooseAction();
        }
        for (int k = 0; k < 60; k++) {
            ctrl->Timeout = 0;
            ctrl->ChooseAction();
        }
    }
    const int lossH = loss ? (int)loss->myHandle : 0;
    const int ctrlH = ctrl ? (int)ctrl->myHandle : 0;
    /* Remove the monsters: a visible hostile near the player would halt the
       key-driven search in ExtendedAction. Their actions are logged. */
    if (loss) loss->Remove(true);
    if (ctrl) ctrl->Remove(true);

    /* --- SCENE: a hidden monster the player will find by searching. --- */
    int hx, hy;
    if (!hsAtDist(mp, pl->x, pl->y, 2, &hx, &hy)) {
        Error("HIDE_SEARCH INCONCLUSIVE no open square at distance 2");
        pl->Options[OPT_AUTOMORE] = autoMore; theGame->PlayMode = wasInPlay; return;
    }
    Monster *hid = hsSpawn(mp, "giant rat", hx, hy);
    if (!hid) {
        Error("HIDE_SEARCH INCONCLUSIVE no giant rat");
        pl->Options[OPT_AUTOMORE] = autoMore; theGame->PlayMode = wasInPlay; return;
    }
    hid->GainPermStati(HIDING, NULL, SS_CLAS, HI_SHADOWS, 1);
    HideStarted(hid, false);
    if (!HideCanWatch(pl, hid)) {
        Error("HIDE_SEARCH INCONCLUSIVE player cannot watch the hidden monster");
        pl->Options[OPT_AUTOMORE] = autoMore; theGame->PlayMode = wasInPlay; return;
    }
    /* A stored "not spotted" verdict for the monster's current epoch. */
    HideSetKey(pl, HK_SPOT_RESULT, hid, (int16)(((hid->HideVal & 0xFF) << 1) | 0));
    /* The player searches far better than the rat hides, so repeated searches
       spot it. */
    pl->GainPermStati(SKILL_BONUS, NULL, SS_MISC, SK_SPOT, 100);
    pl->CalcVision();
    if (pl->Perceives(hid)) {
        Error("HIDE_SEARCH INCONCLUSIVE player still perceives the hidden monster");
        pl->Options[OPT_AUTOMORE] = autoMore; theGame->PlayMode = wasInPlay; return;
    }

    Error("HIDE_SEARCH SCENE player=%d hidden=%d loss=%d ctrl=%d",
        (int)pl->myHandle, (int)hid->myHandle,
        lossH, ctrlH);

    pl->Options[OPT_AUTOMORE] = autoMore;
    theGame->PlayMode = wasInPlay;
    Error("HIDE_SEARCH COMPLETE");
}
