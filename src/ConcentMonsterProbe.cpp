/* inc-59lq: put two monsters into the state a monster caster would be in, so
   Monster::ChooseAction's concentration rule can be observed. No monster here
   casts a table spell on cue and Magic::Illusion returns early for non-players
   (src/Effects.cpp), so tools/check_concentration.sh cannot wait for one.
   Off unless INCURSION_CONCENT_MONSTER_PROBE is set. Called once from
   Main.cpp, needs a live player and map. Each rat holds Telekinesis (range 10)
   and the CONCENTRATING row Creature::StartConcentration would have given it:
   one at full hit points, one below half. The rule's own
   "CONCENT monster=..." lines (INCURSION_CONCENT_PROBE) are the oracle. */
#include "Incursion.h"

static Monster *CMPlace(Map *mp, int16 x, int16 y, int16 hp, int16 mhp)
{
    Monster *mn = new Monster(FIND("giant rat"));
    TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
    TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
    mn->PlaceAt(mp, x, y, true);
    mn->Initialize(true);
    mn->mHP = mhp; mn->cHP = hp;
    mn->RemoveStati(ASLEEP);
    rID tk = FIND("Telekinesis");
    mn->GainTempStati(TELEKINETIC, NULL, 500, SS_ENCH, 0, 10, tk, 10);
    mn->GainTempStati(CONCENTRATING, NULL, 500, SS_ENCH, 0, 0, tk, 10);
    return mn;
}

void ConcentMonsterProbe(Player *pl)
{
    if (!getenv("INCURSION_CONCENT_MONSTER_PROBE") || !pl || !pl->m) return;
    Map *mp = pl->m;
    int16 placed = 0;
    Monster *rat[2] = { NULL, NULL };
    for (int16 d = 2; d <= 5 && placed < 2; d++) {
        int16 tx = pl->x + d, ty = pl->y;
        if (!mp->InBounds(tx, ty) || mp->SolidAt(tx, ty) ||
            mp->FCreatureAt(tx, ty)) continue;
        mp->At(tx, ty).Lit = 1;
        rat[placed] = CMPlace(mp, tx, ty, placed ? 40 : 100, 100);
        placed++;
    }
    for (int16 i = 0; i < placed; i++) {
        rat[i]->Timeout = 0;
        rat[i]->ChooseAction();   /* direct: OPT_FREEZE_MON may idle it */
    }
    Error("CONCENT_PROBE placed=%d", (int)placed);
}
