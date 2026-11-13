/* Test-only control (inc-pu6v.1.4): INCURSION_FORCE_GOD_PULSE makes the
   interval god-pulse lottery in GodPulsePass always pass its 1-in-10 gate.
   "1" also makes the god pick always choose the patron. A god's name (for
   example "Xel") makes the pick choose THAT god instead, patron or not, when
   the character is involved with it; the non-patron interval * 5 spacing in
   the due test still applies. The draws are still taken. Unset or empty: no
   effect. Any other value logs one Error and is ignored. */
static rID ForcedPulseGod = 0;
static bool ForceGodPulse() {
    static bool done = false, forced = false;
    if (done)
        return forced;
    done = true;
    const char *s = getenv("INCURSION_FORCE_GOD_PULSE");
    if (s && *s) {
        if (!strcmp(s, "1"))
            forced = true;
        else {
            rID g = FIND(s);
            for (int16 i = 0; g && i != nGods; i++)
                if (GodIDList[i] == g) {
                    ForcedPulseGod = g;
                    forced = true;
                    break;
                }
            if (!forced)
                Error("INCURSION_FORCE_GOD_PULSE must be 1 or a god's name; ignoring \"%s\".", s);
        }
    }
    return forced;
}

/* inc-pu6v.345: the god pulse's two delivery passes, moved out of DoTurn
   unchanged. Returns true when DoTurn must return (the follower died or left
   the map during a pulse), as the in-place `return` did. */
extern void FlockStanceProbe(Map *mp, Creature *follower, const char *ev);
@@@ next hunk
            FlockStanceProbe(m, this, anger ? "anger" : "pulse");   /* inc-pu6v.1.4 */
@@@ next hunk
    bool lotteryGate = false;
    if (isCharacter()) {
        lotteryGate = !random(10);
        if (ForceGodPulse())
            lotteryGate = true;
    }
    if (lotteryGate) {
@@@ next hunk
        EvReturn pulseResult;
@@@ next hunk
                bool patronDraw = random(4) != 0;
                if (ForceGodPulse() && ForcedPulseGod)
                    gID = (thisp->getGodFlags(ForcedPulseGod) & GS_INVOLVED) ? ForcedPulseGod : 0;
                else if ((patronDraw || ForceGodPulse()) && thisp->GodID)
@@@ next hunk
        pulseResult = ThrowEffVal(isAnger ? EV_ANGER_PULSE : EV_GODPULSE,gID,reason,param,this);
        FlockStanceProbe(m, this, isAnger ? "anger" : "pulse");   /* inc-pu6v.1.4 */
        if (pulseResult != NOTHING) {
