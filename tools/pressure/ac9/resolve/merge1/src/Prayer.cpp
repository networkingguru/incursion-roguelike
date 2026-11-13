void BetrayedProbe(const char *what, Thing *v, int wasFriendly, Thing *actor);
#include "DamageClassProbe.h" /* inc-kx693 */
@@@ next hunk
    int16 i; rID aidChart[64]; int32 price;
    int32 rowMin = 0; int16 vDmgBefore; bool hpGatePassed = false, fired = false;
    bool spoke; /* inc-pu6v.202: did the god speak its own MSG_AID+AID_DEFLECT line? */
    EvReturn ret;
    DamageClassGodEntry(e); /* inc-kx693 */
@@@ next hunk
    applyTransgression(gID,mag,doWrath,reason,false);
  }
