#!/bin/bash
#
# inc-rwha: refuse a landing on a machine under memory pressure, once, without
# waiting. The 2026-10-05 flakes (inc-g9wz, inc-xn7g, inc-fdkz) are why: a
# landing started while the box was thrashing timed out checks that were
# correct, then reported a red gate nobody had actually failed.
#
# inc-b0ziu.8: it refuses, printing one line to stderr and exiting 2, ONLY when
# kernel memory pressure is 2 (warn) or higher. It exits 0 otherwise. It never
# waits. The 1-minute load average is measured and printed on a line that is
# not a refusal; it does not decide the exit. tools/timing_log.sh records
# load beside each check's elapsed time, so a later load limit has data.
# It does not look for another running gate: finish_bead.sh serializes
# landings with a per-base-branch lock.
set -uo pipefail

# Append one bypass row to the load-guard log. The location defaults to
# <shared checkout>/logs/load-guard.log so every worktree logs in one place
# (a worktree's own logs/ is destroyed at landing). INCURSION_LOAD_GUARD_LOG
# overrides it. A failure to write MUST NOT change the exit status; the
# caller decides whether to warn. inc-p8bw.
load_guard_log_path() {
    if [ -n "${INCURSION_LOAD_GUARD_LOG:-}" ]; then
        printf '%s\n' "$INCURSION_LOAD_GUARD_LOG"
        return 0
    fi
    local common
    common="$(git rev-parse --git-common-dir 2>/dev/null)"
    if [ -n "$common" ]; then
        printf '%s\n' "$(cd "$(dirname "$common")" 2>/dev/null && pwd)/logs/load-guard.log"
        return 0
    fi
    printf '%s\n' "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/logs/load-guard.log"
}

# log_guard_bypass <row> -> 0 wrote, 1 could not. Never exits.
log_guard_bypass() {
    local row="$1" path
    path="$(load_guard_log_path)" || return 1
    mkdir -p "$(dirname "$path")" 2>/dev/null || return 1
    printf '%s\n' "$row" >> "$path" 2>/dev/null || return 1
    return 0
}

if [ "${INCURSION_LOAD_GUARD_OFF:-}" = "1" ]; then
    echo "load_guard: bypassed by INCURSION_LOAD_GUARD_OFF=1"
    _row="$(date -u +%Y-%m-%dT%H:%M:%SZ) bypass INCURSION_LOAD_GUARD_OFF=1 caller=load_guard.sh cwd=$(pwd)"
    log_guard_bypass "$_row" \
        || echo "load_guard: WARNING: could not append to $(load_guard_log_path)" >&2
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

printf 'load_guard: 1-min load %s, %s CPUs (not a refusal)\n' "$load" "$ncpu"

if [ -n "${INCURSION_LOAD_GUARD_FAKE_PRESSURE:-}" ]; then
    pressure="$INCURSION_LOAD_GUARD_FAKE_PRESSURE"
else
    pressure="$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)"
fi
if [ -n "$pressure" ] && [ "$pressure" -ge 2 ] 2>/dev/null; then
    printf 'REFUSED (memory): kernel memory pressure level %s is 2 (warn) or higher\n' \
        "$pressure" >&2
    trip=1
fi

[ "$trip" -eq 0 ] || exit 2
if [ -z "${pressure:-}" ]; then
    printf 'load_guard: ok (pressure unknown)\n'
else
    printf 'load_guard: ok (pressure %s)\n' "$pressure"
fi
exit 0
