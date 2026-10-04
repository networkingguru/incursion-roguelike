#!/usr/bin/env bash
# Repro for inc-eq7m: SIGPIPE race in tools/check_upstream_label.sh.
# Runs 10 rounds under load, target in foreground, eight cheap checks in
# background. Eight are needed because three background checks did not load
# the machine enough to trigger the race (the original failed 0/10 under three,
# 3/6 under eight). Prints the count of non-zero target exits. Pass the script
# to run as $1 (default: tools/check_upstream_label.sh), and a label as $2.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
target=${1:-tools/check_upstream_label.sh}
label=${2:-${target##*/}}
fails=0
for i in $(seq 1 10); do
    tools/check_bead_dupe_wiring.sh >/dev/null 2>&1 &
    tools/check_bead_dupes.sh >/dev/null 2>&1 &
    tools/check_commit_lane.sh >/dev/null 2>&1 &
    tools/check_epic_merge.sh >/dev/null 2>&1 &
    tools/check_orphan_branches.sh >/dev/null 2>&1 &
    tools/check_resume_gc.sh >/dev/null 2>&1 &
    tools/check_rules_channel.sh >/dev/null 2>&1 &
    tools/check_upstream_marks.sh >/dev/null 2>&1 &
    bash "$target" >/dev/null 2>&1
    rc=$?
    wait
    [ "$rc" -eq 0 ] || fails=$((fails + 1))
done
echo "$label: $fails/10 non-zero exits"
[ "$fails" -eq 0 ]
