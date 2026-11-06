/* inc-t05z9: opt-in probe. INCURSION_BONUS_ORDER_PROBE=<mag>,<mag>,... gives
   the player one permanent ADJUST stati on A_STR per listed Mag, once, when
   Game::Play starts. Off unless set. The log lines come from
   BonusOrderProbeNote (src/Values.cpp); graded by tools/check_bonus_order.sh. */
#include "Incursion.h"

void BonusOrderProbe(Player *pl) {
    const char *list = getenv("INCURSION_BONUS_ORDER_PROBE");
    if (!list || !pl)
        return;
    for (const char *p = list; *p; ) {
        char *end;
        long mag = strtol(p, &end, 10);
        if (end == p) {
            Error("BONUS_ORDER_PROBE: INCONCLUSIVE -- bad list '%s'", list);
            return;
        }
        pl->GainPermStati(ADJUST, NULL, SS_MISC, A_STR, (int16)mag);
        p = (*end == ',') ? end + 1 : end;
    }
    pl->CalcValues();
}
