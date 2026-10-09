/* inc-u3dp phase 4: prove the distraction / roar / step-check writers through
   the real events the game dispatches. A no-op unless INCURSION_HIDE_DIST_PROBE
   is set. Caller: Game::Play (src/Main.cpp), beside the other hide probes.
   Reader: tools/check_hide_distraction.sh.

   The probe NEVER calls HideSetKey itself: it dispatches ThrowVal(EV_SATTACK,
   ...) / Throw(EV_STRIKE,...) / Map::MakeNoiseXY / Character::UseAbility and
   then reads the stored TRIED keys and the modifier functions. Literal
   expectations live in the shell oracle. */
#include "Incursion.h"
#include "HideCheck.h"

static int hdFails = 0;

static void hdEmit(const char *name, int expect, int got) {
    Error("HIDE_DIST case=%s expect=%d got=%d", name, expect, got);
    if (expect != got) hdFails++;
}

static bool hdOpen(Map *mp, int x, int y) {
    return mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FCreatureAt(x, y);
}

static bool hdNear(Map *mp, int px, int py, int want, int *ox, int *oy) {
    for (int dy = -want; dy <= want; dy++)
        for (int dx = -want; dx <= want; dx++) {
            if (dist(px, py, px + dx, py + dy) != want) continue;
            if (hdOpen(mp, px + dx, py + dy)) {
                *ox = px + dx; *oy = py + dy;
                return true;
            }
        }
    return false;
}

static Monster *hdSpawn(Map *mp, const char *name, int x, int y) {
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
    m->mHP = m->cHP = 10000;
    return m;
}

/* One HK_SPOT_RESULT entry, anywhere, means a spot check rolled. */
static int hdSpotResults(Map *mp) {
    int c = 0; Creature *cr; int i;
    MapIterate(mp, cr, i)
        if (cr && cr->isCreature())
            StatiIterNature(cr, TRIED)
                if (S->Val == HK_SPOT_RESULT) c++;
            StatiIterEnd(cr)
    return c;
}

void HideDistProbe(Player *pl) {
    /* inc-u3dp: hook for tools/check_hide_distraction.sh. */
    if (!getenv("INCURSION_HIDE_DIST_PROBE")) return;
    if (!pl || !pl->m) { Error("HIDE_DIST INCONCLUSIVE no player"); return; }
    Map *mp = pl->m;
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    const int8 autoMore = pl->Options[OPT_AUTOMORE];
    pl->Options[OPT_AUTOMORE] = 1;

    /* A hiding or invisible player is asked "Take opportunity on the rat?"
       (src/Fight.cpp OAttack) whenever a rat acts beside it, and that prompt
       eats the key script. Clear both before any rat acts. */
    pl->RemoveStati(HIDING);
    pl->RemoveStati(INVIS);

    /* Clear any pre-existing keys so each case reads only what it caused. */
    pl->RemoveStati(TRIED);

    /* --- 1. Attack marks BOTH attacker and target. --- */
    {
        int ax, ay, bx, by;
        /* Far from the player: a fight beside the player prompts it for an
           attack of opportunity and eats the key script. */
        if (!hdNear(mp, pl->x, pl->y, 4, &ax, &ay) ||
            !hdNear(mp, ax, ay, 1, &bx, &by)) {
            Error("HIDE_DIST INCONCLUSIVE no room for the attack pair");
            hdFails++;
        } else {
            Monster *atk = hdSpawn(mp, "giant rat", ax, ay);
            Monster *tgt = hdSpawn(mp, "giant rat", bx, by);
            atk->ts.Retarget(tgt);
            atk->RemoveStati(TRIED);
            tgt->RemoveStati(TRIED);
            /* A real ranged attack with a dagger (EV_RATTACK reaches Strike();
               a weaponless rat aborts EV_WATTACK). */
            Item *dag = Item::Create(FIND("dagger"));
            dag->MakeKnown(0xFF);
            atk->GainItem(dag, true);
            Throw(EV_RATTACK, atk, tgt, NULL, dag);
            const int aMark = atk->HasStati(TRIED, HK_DISTRACT) ? 1 : 0;
            const int tMark = tgt->HasStati(TRIED, HK_DISTRACT) ? 1 : 0;
            hdEmit("attack_marks_attacker", 1, aMark);
            hdEmit("attack_marks_target", 1, tMark);
            /* SpotModifiers counts the mark as -5 once. The light terms are
               not under test, so read the sum with the mark cleared and with
               it set; the difference is the literal -5. */
            const int withMark = SpotModifiers(atk, tgt);
            atk->RemoveStati(TRIED, -1, HK_DISTRACT, -1, NULL);
            const int noMark = SpotModifiers(atk, tgt);
            atk->GainPermStati(TRIED, NULL, SS_MISC, HK_DISTRACT, 1);
            hdEmit("attack_attacker_spot_mod", -5, withMark - noMark);

            /* A second strike must still leave exactly one entry (still -5). */
            Throw(EV_RATTACK, atk, tgt, NULL, dag);
            int n = 0;
            StatiIterNature(atk, TRIED)
                if (S->Val == HK_DISTRACT) n++;
            StatiIterEnd(atk)
            hdEmit("attack_two_one_entry", 1, n == 1 ? 1 : 0);
            hdEmit("attack_two_same_mod", -5, SpotModifiers(atk, tgt) - noMark);

            /* --- 3. The mark is gone after B's next action start. --- */
            tgt->RemoveStati(TRIED, -1, HK_DISTRACT, -1, NULL);
            tgt->GainPermStati(TRIED, NULL, SS_MISC, HK_DISTRACT, 1);
            hdEmit("distract_before_action", 1,
                tgt->HasStati(TRIED, HK_DISTRACT) ? 1 : 0);
            /* Take the attacker away first: a hostile neighbour would be
               attacked by tgt's own action, and that attack re-marks tgt. */
            atk->Remove(true);
            atk = NULL;
            tgt->ts.giveOrder(tgt, NULL, OrderStandStill);
            tgt->Timeout = 0;
            { const int t0 = tgt->x, t1 = tgt->y;
              tgt->ChooseAction();
              tgt->PlaceAt(mp, t0, t1); }
            hdEmit("distract_gone_after_action", 0,
                tgt->HasStati(TRIED, HK_DISTRACT) ? 1 : 0);

            tgt->Remove(true);
        }
    }

    /* --- 6. Step check: a distracted listener rolls with -5. The probe line
       HIDE_STEP (src/Move.cpp) prints the modifier the comparison uses. --- */
    {
        int dir = -1;
        for (int d = 0; d < 8 && dir < 0; d++) {
            if (hdOpen(mp, pl->x + DirX[d], pl->y + DirY[d]) &&
                hdOpen(mp, pl->x + 2 * DirX[d], pl->y + 2 * DirY[d]))
                dir = d;
        }
        if (dir < 0) {
            Error("HIDE_DIST INCONCLUSIVE no room for the step listener");
            hdFails++;
        } else {
            Monster *l = hdSpawn(mp, "giant rat", pl->x + 2 * DirX[dir],
                                 pl->y + 2 * DirY[dir]);
            l->RemoveStati(TRIED);
            l->GainPermStati(TRIED, NULL, SS_MISC, HK_DISTRACT, 1);
            pl->Timeout = 0;
            Error("HIDE_DIST step_begin");
            ThrowDir(EV_MOVE, dir, pl);
            Error("HIDE_DIST step_end");
            l->Remove(true);
        }
    }

    /* --- 2. Heard noise marks the listener, not the maker; no spot roll. --- */
    {
        int ax, ay, bx, by;
        if (!hdNear(mp, pl->x, pl->y, 4, &ax, &ay) ||
            !hdNear(mp, pl->x, pl->y, 5, &bx, &by)) {
            Error("HIDE_DIST INCONCLUSIVE no room for the noise pair");
            hdFails++;
        } else {
            Monster *a = hdSpawn(mp, "giant rat", ax, ay);
            Monster *b = hdSpawn(mp, "giant rat", bx, by);
            a->RemoveStati(TRIED);
            b->RemoveStati(TRIED);
            const int spotsBefore = hdSpotResults(mp);
            /* The maker A makes a loud noise that reaches B. */
            mp->MakeNoiseXY(a->x, a->y, 6);
            const int aMark = a->HasStati(TRIED, HK_DISTRACT) ? 1 : 0;
            const int bMark = b->HasStati(TRIED, HK_DISTRACT) ? 1 : 0;
            hdEmit("noise_maker_not_marked", 0, aMark);
            hdEmit("noise_listener_marked", 1, bMark);
            hdEmit("noise_listener_listen_mod", -5, ListenModifiers(b));
            hdEmit("noise_no_spot_roll", 0, hdSpotResults(mp) - spotsBefore);

            /* The listener's next action clears the mark. */
            a->Remove(true);
            a = NULL;
            b->ts.giveOrder(b, NULL, OrderStandStill);
            b->Timeout = 0;
            { const int t0 = b->x, t1 = b->y;
              b->ChooseAction();
              b->PlaceAt(mp, t0, t1); }
            hdEmit("noise_mark_gone_after_action", 0,
                b->HasStati(TRIED, HK_DISTRACT) ? 1 : 0);
            b->Remove(true);
        }
    }

    /* --- 4. Roar marks every reached creature, live three rounds. --- */
    {
        int rx, ry;
        if (!hdNear(mp, pl->x, pl->y, 2, &rx, &ry)) {
            Error("HIDE_DIST INCONCLUSIVE no room for the roarer");
            hdFails++;
        } else {
            Monster *roarer = hdSpawn(mp, "krenshar", rx, ry);
            if (!roarer) {
                Error("HIDE_DIST INCONCLUSIVE no krenshar (A_ROAR)");
                hdFails++;
            } else {
                /* Three listeners: two normal, one deaf. */
                Monster *near1 = NULL, *near2 = NULL, *deaf = NULL;
                int gx, gy;
                int placed = 0;
                for (int d = 1; d <= 12 && placed < 2; d++) {
                    if (hdNear(mp, roarer->x, roarer->y, d, &gx, &gy)) {
                        Monster *m = hdSpawn(mp, "giant rat", gx, gy);
                        if (m) { m->RemoveStati(TRIED);
                                 if (placed == 0) near1 = m; else near2 = m;
                                 placed++; }
                    }
                }
                /* The belabra carries M_DEAF in its template flags. */
                for (int d = 1; d <= 3 && !deaf; d++)
                    if (hdNear(mp, roarer->x, roarer->y, d, &gx, &gy))
                        deaf = hdSpawn(mp, "belabra", gx, gy);
                if (deaf) { deaf->RemoveStati(TRIED);
                            hdEmit("roar_deaf_is_deaf", 1,
                                   deaf->HasMFlag(M_DEAF) ? 1 : 0); }
                roarer->RemoveStati(TRIED);
                if (!near1 || !deaf) {
                    Error("HIDE_DIST INCONCLUSIVE could not place roar listeners");
                    hdFails++;
                } else {
                    const uint32 tBase = theGame->Turn;
                    ThrowVal(EV_SATTACK, A_ROAR, roarer, NULL);
                    hdEmit("roar_roarer_not_marked", 0,
                        roarer->HasStati(TRIED, HK_ROAR) ? 1 : 0);
                    hdEmit("roar_listener_marked", 1,
                        near1->HasStati(TRIED, HK_ROAR) ? 1 : 0);
                    hdEmit("roar_listener_live", 1, HideRoarLive(near1) ? 1 : 0);
                    hdEmit("roar_listener_spot_mod", -11,
                        SpotModifiers(near1, roarer));
                    hdEmit("roar_listener_listen_mod", -10,
                        ListenModifiers(near1));
                    if (deaf)
                        hdEmit("roar_deaf_not_marked", 0,
                            deaf->HasStati(TRIED, HK_ROAR) ? 1 : 0);
                    /* Live for 3 rounds. */
                    theGame->Turn = tBase + 2 * HIDE_ROUND_TICKS;
                    hdEmit("roar_live_at_2_rounds", 1,
                        HideRoarLive(near1) ? 1 : 0);
                    theGame->Turn = tBase + 3 * HIDE_ROUND_TICKS;
                    hdEmit("roar_gone_at_3_rounds", 0,
                        HideRoarLive(near1) ? 1 : 0);

                    /* --- 5. A countersong clears a live roar. --- */
                    /* Re-stamp the roar live, then sing a countersong. */
                    theGame->Turn = tBase;
                    near1->RemoveStati(TRIED, -1, HK_ROAR, -1, NULL);

                    /* The player needs the ability; the song menu then offers
                       Countersong (3rd). The keys file selects it. */
                    pl->GainPermStati(EXTRA_ABILITY, NULL, SS_MISC,
                                      CA_BARDIC_MUSIC, 5);
                    pl->PlaceAt(mp, roarer->x + 2 <= mp->SizeX() - 1 ?
                        roarer->x + 2 : roarer->x - 2, roarer->y);
                    ThrowVal(EV_SATTACK, A_ROAR, roarer, NULL);
                    hdEmit("roar_re_marked", 1,
                        near1->HasStati(TRIED, HK_ROAR) ? 1 : 0);
                    Error("HIDE_DIST countersong_begin");
                    pl->UseAbility(CA_BARDIC_MUSIC, 0);
                    hdEmit("countersong_clears_roar", 0,
                        near1->HasStati(TRIED, HK_ROAR) ? 1 : 0);

                    theGame->Turn = tBase;
                    if (near1) near1->Remove(true);
                    if (near2) near2->Remove(true);
                    if (deaf) deaf->Remove(true);
                }
                roarer->Remove(true);
            }
        }
    }

    pl->Options[OPT_AUTOMORE] = autoMore;
    theGame->PlayMode = wasInPlay;
    Error("HIDE_DIST COMPLETE fails=%d", hdFails);
}
