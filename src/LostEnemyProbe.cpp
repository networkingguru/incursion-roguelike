/* inc-9622: staged observation only; no AI decisions are overridden.
   Each process stages one scene. Forty ChooseAction calls allow the arrival
   plus the whole 5-turn investigate search window (the subject arrives around
   own turn 17-18). The control replaces
   the first action with PlaceAt, proving the identical arrival oracle can pass. */
#include "Incursion.h"

static Monster *leWatched;
static FILE *leLog;
static int leTurn, leAction;

void LostEnemyProbeAction(Monster *mn, int action, int result) {
    if (!leLog || mn != leWatched) return;
    leAction = action;
    fprintf(leLog, "ACTION turn=%d action=%d result=%d\n", leTurn, action, result);
}

static void leRow(Monster *mn, Player *pl, int gx, int gy, bool noise) {
    Target *t = noise ? mn->ts.getTargetOfType(TargetArea) : mn->ts.GetTarget(pl);
    /* inc-9622: an investigate target is a TargetArea whose why.type is
       TargetHeardNoise or TargetLostTrack. Log it and its own-turn search
       count every pass so the check can observe the 5-turn window live. */
    Target *inv = mn->ts.getTargetOfType(TargetArea);
    const bool held = inv && (inv->why.type == TargetHeardNoise ||
                              inv->why.type == TargetLostTrack);
    fprintf(leLog, "TURN turn=%d x=%d y=%d distance=%d vis=%d perceived=%d current_distance=%d action=%d asleep=%d afraid=%d held=%d searchTurns=%d\n",
        leTurn, mn->x, mn->y, dist(mn->x,mn->y,gx,gy), t ? t->vis : 0,
        mn->Perceives(pl), mn->DistFrom(pl), leAction,
        mn->HasStati(ASLEEP) || mn->HasStati(SLEEPING), mn->HasStati(AFRAID),
        held ? 1 : 0, held ? inv->data.Area.searchTurns : -1);
    fflush(leLog);
}

void LostEnemyProbe(Player *pl) {
    const char *mode = getenv("INCURSION_LOST_ENEMY_PROBE");
    if (!mode) return;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/lost-enemy.log", (const char*)T1->IncursionDirectory);
    leLog = fopen(path, "w");
    if (!leLog) return;
    const bool noise = !strcmp(mode, "noise") || !strcmp(mode, "noise-control");
    const bool control = strstr(mode, "control") != NULL;
    auto stop = [&](const char *why) {
        fprintf(leLog, "INCONCLUSIVE %s\n", why);
        fclose(leLog); leLog = NULL; leWatched = NULL;
    };
    if (!pl || !pl->m) { stop("no player/map"); return; }
    Map *mp = pl->m;
    if (mp->SizeX() < 38 || mp->SizeY() < 38) { stop("map too small"); return; }
    const rID floor = FIND("floor"), wall = FIND("dungeon wall"), goblin = FIND("goblin");
    if (!floor || !wall || !goblin) { stop("missing resource"); return; }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    pl->Options[OPT_AUTOMORE] = 1;
    pl->RemoveStati(HIDING);
    /* Remove unrelated map objects before carving the arena; inventory stays
       with the loaded player. Restart iteration because Remove compacts Things. */
    Thing *obj; int index;
    for (;;) {
        Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != pl) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    pl->PlaceAt(mp, 34, 10);
    const rID region = mp->RegionAt(pl->x,pl->y);
    Rect rect(0,0,mp->SizeX()-1,mp->SizeY()-1);
    /* A wide room opens into a narrow southbound corridor around its SE corner.
       The hidden player at (34,34) is beyond all the goblin's senses. */
    for (int y=0; y<mp->SizeY(); ++y)
        for (int x=0; x<mp->SizeX(); ++x) {
            const bool open = (x>=3 && x<=35 && y>=3 && y<=15) ||
                              (x>=34 && x<=35 && y>=16 && y<=35);
            mp->WriteAt(rect,x,y,open ? floor : wall,region,PRIO_MAX,true);
            mp->At(x,y).Lit = open;
        }
    pl->CalcVision();
    Monster *mn = new Monster(goblin);
    mn->PlaceAt(mp,26,10);
    mn->Initialize(true);
    mn->RemoveStati(SLEEPING); mn->RemoveStati(ASLEEP);
    mn->RemoveStati(AFRAID);
    mn->ts.Clear();
    mn->ts.giveOrder(mn,NULL,OrderDoNotHide);
    mn->ts.giveOrder(mn,NULL,OrderNoPickup);
    leWatched = mn;
    int gx = 34, gy = noise ? 18 : 10;
    fprintf(leLog,"SETUP case=%s control=%d goal_x=%d goal_y=%d turns=40 monster=goblin move_action=%d search_action=%d\n",
        noise ? "noise" : "lost",control,gx,gy,ACT_MOVE,ACT_SEARCH);
    if (!noise) {
        mn->ts.TurnHostileTo(mn,pl);
        mn->ts.Consider(mn,pl);
        leTurn = -1; leAction = -1; mn->Timeout = 0;
        mn->ChooseAction();
        Target *t = mn->ts.GetTarget(pl);
        fprintf(leLog,"SEEN x=%d y=%d player_x=%d player_y=%d vis=%d perceived=%d hostile=%d\n",
            mn->x,mn->y,pl->x,pl->y,t ? t->vis : 0,mn->Perceives(pl),mn->isHostileTo(pl));
        if (!t || !t->vis || !mn->Perceives(pl) || !mn->isHostileTo(pl)) {
            stop("enemy was not perceived and hostile"); return;
        }
    }
    pl->PlaceAt(mp,34,34);
    pl->CalcVision();
    if (noise) {
        mn->ts.HearNoise(mn,gx,gy);
        Target *t = mn->ts.getTargetOfType(TargetArea);
        fprintf(leLog,"HEARD target=%d why=%d empty=%d los=%d\n",
            t != NULL,t ? t->why.type : -1,!mp->FCreatureAt(gx,gy),mp->LineOfSight(mn->x,mn->y,gx,gy,mn));
        if (!t || t->why.type != TargetHeardNoise || mp->FCreatureAt(gx,gy) ||
            mp->LineOfSight(mn->x,mn->y,gx,gy,mn)) {
            stop("noise not an unseen empty-square TargetArea"); return;
        }
    }
    fprintf(leLog,"HIDDEN player_x=%d player_y=%d perceived=%d los=%d\n",
        pl->x,pl->y,mn->Perceives(pl),mp->LineOfSight(mn->x,mn->y,pl->x,pl->y,mn));
    if (mn->Perceives(pl)) { stop("player still perceived"); return; }
    leTurn = 0; leAction = -1;
    leRow(mn,pl,gx,gy,noise);
    const uint32 savedTurn = theGame->Turn;
    for (leTurn=1; leTurn<=40; ++leTurn) {
        leAction = -1;
        mn->Timeout = 0;
        if (control) {
            if (leTurn == 1) mn->PlaceAt(mp,gx,gy);
            leAction = -2; // explicitly manual, never presented as an AI action
        } else mn->ChooseAction();
        leRow(mn,pl,gx,gy,noise);
        theGame->Turn += max(1,mn->Timeout);
    }
    theGame->Turn = savedTurn;
    fprintf(leLog,"COMPLETE\n");
    fclose(leLog); leLog = NULL; leWatched = NULL;
    mn->Remove(true);
    theGame->PlayMode = wasInPlay;
}
