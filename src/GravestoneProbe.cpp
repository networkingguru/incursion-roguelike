/* inc-nx0z: opt-in probe. Off unless INCURSION_GRAVESTONE_PROBE is set.
   Called from Game::Play (src/Main.cpp) at the end of every turn, fires once; used by tools/check_gravestone.sh.
   Deals lethal AD_NORM damage to the player through ThrowDmg(EV_DAMAGE), the
   path a monster blow takes, with the player as actor and victim and the fixed text "gravestone
   probe". Player::Death sets GraveText from that text. No roll is involved. */
#include "Incursion.h"

void GravestoneProbe(Player *pl) {
    static bool fired = false;
    if (fired || !getenv("INCURSION_GRAVESTONE_PROBE"))
        return;
    fired = true;
    if (!pl || !pl->m) {
        Error("GRAVESTONE_PROBE: INCONCLUSIVE -- no live player and map");
        return;
    }
    const int hp = pl->cHP;
    ThrowDmg(EV_DAMAGE, AD_NORM, 30000, "gravestone probe", pl, pl);
    Error("GRAVESTONE_PROBE: dealt lethal damage, hp_before=%d hp_after=%d", hp, (int)pl->cHP);
}
