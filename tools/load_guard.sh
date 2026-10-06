#!/bin/bash
#
# inc-rwha: refuse a landing on an overloaded machine, once, without waiting.
# The 2026-10-05 load flakes (inc-g9wz, inc-xn7g, inc-fdkz) are why: a
# landing started while the box was thrashing timed out checks that were
# correct, then reported a red gate nobody had actually failed.
#
# It refuses, printing one line per tripped condition to stderr and exiting
# 2, when the 1-minute load average is above hw.ncpu / 2, when kernel memory
# pressure is 2 (warn) or higher, or when another tools/nightly_verify.sh is
# already running. It exits 0 when the machine is fit. It never waits.
set -uo pipefail

if [ "${INCURSION_LOAD_GUARD_OFF:-}" = "1" ]; then
    echo "load_guard: bypassed by INCURSION_LOAD_GUARD_OFF=1"
    exit 0
fi

trip=0

if [ -n "${INCURSION_LOAD_GUARD_FAKE_LOAD:-}" ] && [ -n "${INCURSION_LOAD_GUARD_FAKE_NCPU:-}" ]; then
    load="$INCURSION_LOAD_GUARD_FAKE_LOAD"
    ncpu="$INCURSION_LOAD_GUARD_FAKE_NCPU"
elif [ -n "${INCURSION_LOAD_GUARD_FAKE_LOAD:-}" ]; then
    load="$INCURSION_LOAD_GUARD_FAKE_LOAD"
    ncpu="$(sysctl -n hw.ncpu 2>/dev/null)"
elif [ -n "${INCURSION_LOAD_GUARD_FAKE_NCPU:-}" ]; then
    ncpu="$INCURSION_LOAD_GUARD_FAKE_NCPU"
    load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
else
    load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
    ncpu="$(sysctl -n hw.ncpu 2>/dev/null)"
fi

limit="$(awk -v n="$ncpu" 'BEGIN { printf "%.1f", n / 2 }' 2>/dev/null)"
above="$(awk -v l="$load" -v lim="$limit" 'BEGIN { print (l > lim) ? 1 : 0 }' 2>/dev/null)"
if [ "${above:-0}" = "1" ]; then
    printf 'REFUSED (overload): 1-min load average %s is above the limit %s (half of %s CPUs)\n' \
        "$load" "$limit" "$ncpu" >&2
    trip=1
fi

if [ -n "${INCURSION_LOAD_GUARD_FAKE_PRESSURE:-}" ]; then
    pressure="$INCURSION_LOAD_GUARD_FAKE_PRESSURE"
else
    pressure="$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)"
fi
if [ -n "$pressure" ] && [ "$pressure" -ge 2 ] 2>/dev/null; then
    printf 'REFUSED (overload): kernel memory pressure level %s is 2 (warn) or higher\n' \
        "$pressure" >&2
    trip=1
fi

gate_pid=""
if [ -n "${INCURSION_LOAD_GUARD_FAKE_GATES:-}" ]; then
    if [ "${INCURSION_LOAD_GUARD_FAKE_GATES}" -ge 1 ] 2>/dev/null; then
        gate_pid="fake"
    fi
else
    while read -r pid; do
        [ -n "$pid" ] || continue
        cmd="$(ps -o command= -p "$pid" 2>/dev/null)"
        [ -n "$cmd" ] || continue
        # Match only a shell whose second word is the gate script, so a shell
        # whose command line merely mentions the pattern text does not count.
        set -- $cmd
        first="$1"
        second="${2:-}"
        case "$first" in
            *bash|*sh|*zsh) ;;
            *) continue ;;
        esac
        case "$second" in
            *nightly_verify.sh)
                if [ -z "$gate_pid" ] || { [ "$gate_pid" != "fake" ] && [ "$pid" -lt "$gate_pid" ] 2>/dev/null; }; then
                    gate_pid="$pid"
                fi
                ;;
        esac
    done < <(pgrep -f 'tools/nightly_verify.sh' 2>/dev/null)
fi
if [ -n "$gate_pid" ]; then
    printf 'REFUSED (overload): another tools/nightly_verify.sh gate is running (pid %s)\n' \
        "$gate_pid" >&2
    trip=1
fi

[ "$trip" -eq 0 ] || exit 2
exit 0
