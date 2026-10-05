/* inc-3lsp probe: Monster::nAct accumulating across Monster::Initialize.
   A no-op unless INCURSION_ACT_OVERFLOW_PROBE is set. Caller: Game::Play
   (src/Main.cpp). Reader: tools/check_act_overflow.sh. */
#define protected public
#include "Incursion.h"
#undef protected

/* Builds 64 goblins carrying the "archer" template (its EV_INITIALIZE calls
   AddAct(ACT_EQUIP), lib/mon2.irh) and Initializes each, as Map::Generate
   does, with no ChooseAction between them. Logs one line through Error():
     ACT_OVERFLOW_PROBE n=64 nAct=<n> PASS|FAIL
   PASS means nAct stayed below 63. */
void ActOverflowProbe(Player *pl) {
    if (!getenv("INCURSION_ACT_OVERFLOW_PROBE")) return;
    if (!pl || !pl->m) {
        Error("ACT_OVERFLOW_PROBE INCONCLUSIVE no live player and map");
        return;
    }
    const rID arch = FIND("archer"), gob = FIND("goblin");
    if (!gob || !arch) {
        Error("ACT_OVERFLOW_PROBE INCONCLUSIVE missing goblin or archer");
        return;
    }
    const int N = 64;
    Map *mp = pl->m;
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    Monster::nAct = 0;
    int made = 0, tmpl = 0;
    for (int i = 0; i < N; i++) {
        Monster *mn = new Monster(gob);
        mn->PlaceAt(mp, pl->x, pl->y, true);
        /* MA_SAPIENT is only true after a first Initialize, and archer needs
           it, so the template goes on afterwards. */
        mn->Initialize(true);
        mn->AddTemplate(arch);
        tmpl += mn->HasEffStati(TEMPLATE, arch) ? 1 : 0;
        mn->Initialize(true);
        made++;
        mn->Remove(true);
    }
    int n = Monster::nAct;
    Monster::nAct = 0;
    theGame->PlayMode = wasInPlay;
    if (tmpl != made) {
        Error("ACT_OVERFLOW_PROBE INCONCLUSIVE archer template on %d of %d",
            tmpl, made);
        return;
    }
    Error("ACT_OVERFLOW_PROBE n=%d nAct=%d %s", made, n,
        n < 63 ? "PASS" : "FAIL");
}
