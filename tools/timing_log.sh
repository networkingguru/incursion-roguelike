#!/bin/bash
#
# inc-b0ziu.8: append ONE row to logs/check-timing.tsv in the shared checkout,
# so a later decision on a load limit has data: how long a check took, and
# what the machine was doing while it ran.
#
# Usage: tools/timing_log.sh <runner> <check> <exit> <elapsed_s>
#   runner  fast | gate
#
# Columns (tab-separated; a header row is written when the file is new):
#   utc_time runner check exit elapsed_s load1 ncpu mem_pressure gates_running branch
#
# INCURSION_CHECK_TIMING_LOG overrides the path (tests). The same
# INCURSION_LOAD_GUARD_FAKE_LOAD/_NCPU/_PRESSURE fakes as load_guard.sh apply.
# It NEVER fails its caller: on any error it warns once on stderr and exits 0.
set -uo pipefail

warn() { echo "timing_log: WARNING: $1" >&2; exit 0; }

[ $# -eq 4 ] || warn "usage: timing_log.sh <runner> <check> <exit> <elapsed_s>"

timing_log_path() {
    if [ -n "${INCURSION_CHECK_TIMING_LOG:-}" ]; then
        printf '%s\n' "$INCURSION_CHECK_TIMING_LOG"
        return 0
    fi
    local common
    common="$(git rev-parse --git-common-dir 2>/dev/null)"
    if [ -n "$common" ]; then
        printf '%s\n' "$(cd "$(dirname "$common")" 2>/dev/null && pwd)/logs/check-timing.tsv"
        return 0
    fi
    printf '%s\n' "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/logs/check-timing.tsv"
}

load="${INCURSION_LOAD_GUARD_FAKE_LOAD:-$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')}"
ncpu="${INCURSION_LOAD_GUARD_FAKE_NCPU:-$(sysctl -n hw.ncpu 2>/dev/null)}"
pressure="${INCURSION_LOAD_GUARD_FAKE_PRESSURE:-$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)}"
# '[n]ightly_verify.sh' cannot match this script's own command line.
gates="$(pgrep -f '[n]ightly_verify.sh' 2>/dev/null | wc -l | tr -d ' ')"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

path="$(timing_log_path)" || warn "could not resolve the log path"
mkdir -p "$(dirname "$path")" 2>/dev/null || warn "could not create $(dirname "$path")"
if [ ! -s "$path" ]; then
    printf 'utc_time\trunner\tcheck\texit\telapsed_s\tload1\tncpu\tmem_pressure\tgates_running\tbranch\n' \
        >> "$path" 2>/dev/null || warn "could not write $path"
fi
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$now" "$1" "$2" "$3" "$4" "${load:-}" "${ncpu:-}" "${pressure:-}" "${gates:-0}" "${branch:-}" \
    >> "$path" 2>/dev/null || warn "could not write $path"
exit 0
