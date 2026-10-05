/* inc-tmys: opt-in probe for the Monster::Initialize hit-point invariant
   (cHP == mHP + Attr[A_THP] after the EV_INITIALIZE events). Off unless
   INCURSION_MONINIT_PROBE is set. Called from Game::Play (src/Main.cpp);
   read by tools/check_monster_init_hp.sh. Output goes to errors.log through
   Error(), one MONINIT_PROBE line per fact. */
#include "Incursion.h"

void MonsterInitProbe(Player *pl) {
    if (!getenv("INCURSION_MONINIT_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("MONINIT_PROBE: INCONCLUSIVE -- no live player and map");
        return;
    }
    const rID elfID = FIND("elf"), druidID = FIND("wildshaped druid");
    if (!elfID || !druidID) {
        Error("MONINIT_PROBE: INCONCLUSIVE -- missing elf or wildshaped druid");
        return;
    }
    if (RES(elfID)->Type != T_TMONSTER || RES(druidID)->Type != T_TTEMPLATE) {
        Error("MONINIT_PROBE: INCONCLUSIVE -- FIND gave type %d for elf, %d for template",
            (int)RES(elfID)->Type, (int)RES(druidID)->Type);
        return;
    }
    Map *mp = pl->m;
    int16 tx = -1, ty = -1;
    for (int d = 2; d <= 6 && tx < 0; ++d)
        for (int dx = -d; dx <= d && tx < 0; ++dx)
            for (int dy = -d; dy <= d && tx < 0; ++dy) {
                const int16 nx = pl->x + dx, ny = pl->y + dy;
                if (!mp->InBounds(nx, ny) || mp->SolidAt(nx, ny)) continue;
                if (mp->FCreatureAt(nx, ny)) continue;
                tx = nx; ty = ny;
            }
    if (tx < 0) {
        Error("MONINIT_PROBE: INCONCLUSIVE -- no open floor");
        return;
    }
    /* Same steps as the generator (src/MakeLev.cpp) and Debug summon:
       build, template, gear, birth, place, Initialize. The one forced
       step is ELEVATED: Initialize gives it to a tree-climbing monster
       standing on a tree square (src/Monster.cpp), and the probe stands in
       for that rather than hunting for a tree. */
    Monster *mn = new Monster(elfID);
    mn->CalcValues(); /* isMType(MA_SAPIENT) reads Attr[A_INT] */
    mn->AddTemplate(druidID);
    TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    mn->PlaceAt(mp, tx, ty, true);
    mn->GainPermStati(ELEVATED, NULL, SS_MISC, ELEV_TREE, 0);
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    mn->Initialize(false);
    theGame->PlayMode = wasInPlay;
    if ((mn->Flags & F_DELETE) || mn->isDead() ||
        !mn->HasStati(TEMPLATE) || !mn->HasStati(POLYMORPH)) {
        Error("MONINIT_PROBE: INCONCLUSIVE -- deleted=%d dead=%d template=%d polymorph=%d",
            (int)((mn->Flags & F_DELETE) != 0), (int)mn->isDead(),
            (int)mn->HasStati(TEMPLATE), (int)mn->HasStati(POLYMORPH));
        return;
    }
    /* Initialize ends by resetting cHP (src/Monster.cpp, after PreBuff), so
       the broken state exists only at its ASSERT. The verdict is therefore
       the ASSERT count in errors.log, which the check reads; the line below
       says the path ran: elevated_left=0 means ClimbFall consumed ELEVATED. */
    Error("MONINIT_PROBE: DONE elevated_left=%d cHP=%d mHP=%d THP=%d",
        (int)mn->HasStati(ELEVATED), (int)mn->cHP, (int)mn->mHP,
        (int)mn->Attr[A_THP]);
}
