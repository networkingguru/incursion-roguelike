/* inc-e5ke: make the double after-damage step of a converted damage event
   visible. Creature::Damage turns some damage types (AD_CHAO, AD_LAWF, AD_EVIL,
   AD_HOLY, ...) into AD_NORM and re-delivers the event with ReThrow(EV_DAMAGE,e).
   The inner event runs its own POST(EV_DAMAGE) step (RealThrow, src/Event.cpp),
   and then the outer event runs its own POST(EV_DAMAGE) step with the same
   victim and amount -- so every POST(EV_DAMAGE) listener runs twice for one
   converted hit. This probe records both halves so tools/check_dmgpost_once.sh
   can count them. Off unless INCURSION_DMGPOST_PROBE is set; output goes to the
   run's logs/errors.log through Error(), the same channel the other *_PROBE
   hooks use. */

#include "Incursion.h"

static int DmgPostProbeOn(void) {
    return getenv("INCURSION_DMGPOST_PROBE") ? 1 : 0;
}

/* Called at every ReThrow(EV_DAMAGE,e) site in Creature::Damage, just before
   the call, with 'from' the damage type the event carried before the site
   overwrote it. EventSP is the outer event's stack slot; the re-thrown inner
   event will run in EventSP+1. */
void DmgPostConvertProbe(EventInfo &e, int from) {
    if (!DmgPostProbeOn()) return;
    Error("DMGPOST convert victim=%u from=%d sp=%d",
        (unsigned)(e.EVictim ? e.EVictim->myHandle : 0), from, EventSP);
}

/* Called in RealThrow just before the POST step runs, when the main event is
   EV_DAMAGE. */
void DmgPostPostProbe(EventInfo &e) {
    if (!DmgPostProbeOn()) return;
    Error("DMGPOST post victim=%u dmg=%d type=%d sp=%d",
        (unsigned)(e.EVictim ? e.EVictim->myHandle : 0), (int)e.vDmg,
        (int)e.DType, EventSP);
}
