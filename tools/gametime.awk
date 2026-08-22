# Grade a session by whether it spent game time, not by whether it exited 0.
#
# Input: one "<key> <turn>" line per screen dump, in dump order, read from the
# dump headers that posixTerm::DumpScreen writes (src/Wposix.cpp).
# Output: the "game time:" block of tools/headless.sh's report.
#
# WHY THIS IS SHARED RATHER THAN INLINE. tools/headless.sh reports it and
# tools/check_clock_advance.sh tests it. A copy in each would let the tested
# text and the shipped text drift apart, which is the failure mode where a
# regression check passes while the thing it guards is broken.
#
# WHAT IT MEASURES. A run that reads keys without advancing the turn counter
# is not playing. That covers the death prompt (inc-loa.3), the
# threat-disengage prompt (inc-loa.5), Inventory Mode, and refused commands
# (inc-loa.2) with one test instead of four string matches. See inc-2k3.
#
# A frozen interval in the MIDDLE is reported but is not a failure: a walk may
# legitimately spend keys inside a menu it then leaves. A frozen interval at
# the END is a stall, because nothing after it can be gameplay.

NR == 1 { k0 = $1; t0 = $2; pk = $1; pt = $2; next }

{
    dk = $1 - pk
    dt = $2 - pt
    n++
    if (dt == 0) {
        frozen++
        lastfrozen = 1
        if (fk0 == "") fk0 = pk
        fkeys += dk
    } else {
        lastfrozen = 0
        fk0 = ""
        fkeys = 0
    }
    pk = $1
    pt = $2
}

END {
    if (NR == 0) { print "game time:  no screen dump carried a turn stamp"; exit }
    tk = pk - k0
    tt = pt - t0
    if (tk <= 0) { print "game time:  no keys between dumps"; exit }
    printf "game time:  %d turns over %d keys (%.2f turns/key)\n", tt, tk, tt / tk
    if (frozen > 0)
        printf "            %d of %d intervals advanced ZERO turns\n", frozen, n
    if (lastfrozen)
        printf "            STALLED -- the last %d keys (from key %d) spent no\n            game time. Nothing after that point is gameplay.\n", fkeys, fk0
    else if (frozen == 0)
        printf "            every interval advanced. No stall.\n"
}
