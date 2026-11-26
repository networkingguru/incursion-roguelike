/* inc-i63lc: live presentation observer, armed only by the opt-in reel driver.
   States count the first frame plus consecutive changes in displayed map RGB,
   including flight, fill and tail; they are not unique effect-clock values.
   End hooks delimit the last effect (including struck flashes) in the cast. */
#include <chrono>
#include "Incursion.h"
#include "Light.h"
#include "EffectLight.h"

namespace {
using Clock = std::chrono::steady_clock;
bool armed = false, started = false, ended = false, inWait = false, noneMode = false;
struct Counts {
    int presents = 0, states = 0;
    uint32 previous = 0;
    void Present(uint32 hash) {
        if (++presents == 1 || hash != previous) ++states;
        previous = hash;
    }
};
Counts total, waitCounts, phases[3], endTotal, endWait, endPhases[3];
int phaseBucket = 0;
double waitMs = 0;
Clock::time_point waitStart;
Clock::time_point first, last;
}

/* None (option 2) shows no light, so no flash ever starts the clock: the cast itself is the span. */
void AnimSpeedArm(int option) {
    armed = true; started = ended = false;
    noneMode = option == 2;
    if (noneMode) { first = Clock::now(); started = true; }
    total = waitCounts = endTotal = endWait = Counts{};
    for (int i = 0; i < 3; ++i) phases[i] = endPhases[i] = Counts{};
    phaseBucket = 0; waitMs = 0;
}

bool AnimSpeedSampling() { return armed; }
void AnimSpeedWait(bool inside) {
    if (armed && inside && !inWait) waitStart = Clock::now();
    if (armed && !inside && inWait) waitMs += std::chrono::duration<double, std::milli>(Clock::now() - waitStart).count();
    inWait = inside;
}

/* Buckets follow the last hook, not inferred light age. EL_HOLD includes tail;
   TF_LIT begins another burst and either end hook leaves the hold/tail bucket. */
void AnimSpeedPhase(int phase, bool target) {
    if (!armed) return;
    phaseBucket = (target ? phase == TF_LIT : phase == EL_LIT) ? 1 : 2;
}

void AnimSpeedPresent(uint32 hash) {
    if (!armed) return;
    if (!started) {
        if (!noneMode && !LightFlashCount()) return;
        first = Clock::now();
        started = true;
    }
    total.Present(hash);
    if (inWait) waitCounts.Present(hash);
    phases[phaseBucket].Present(hash);
}

void AnimSpeedEnd() {
    if (!armed || !started) return;
    last = Clock::now(); ended = true;
    endTotal = total; endWait = waitCounts;
    for (int i = 0; i < 3; ++i) endPhases[i] = phases[i];
}

void AnimSpeedReport(int option) {
    if (!armed) return;
    armed = false;
    if (noneMode) {   /* nothing ends an effect that is not shown: close the span here */
        last = Clock::now(); ended = true;
        endTotal = total; endWait = waitCounts;
        for (int i = 0; i < 3; ++i) endPhases[i] = phases[i];
    }
    if (!started || !ended) {
        Error("ANIM_SPEED_ERROR no live SDL presents or effect end");
        return;
    }
    const double ms = std::chrono::duration<double, std::milli>(last - first).count();
    Error("ANIM_SPEED option=%d presents=%d states=%d wall_ms=%.3f effect=Fireball "
          "wait_presents=%d wait_states=%d flight_presents=%d flight_states=%d "
          "burst_presents=%d burst_states=%d hold_tail_presents=%d hold_tail_states=%d wait_ms=%.3f",
          option, endTotal.presents, endTotal.states, ms,
          endWait.presents, endWait.states, endPhases[0].presents, endPhases[0].states,
          endPhases[1].presents, endPhases[1].states, endPhases[2].presents, endPhases[2].states, waitMs);
}
