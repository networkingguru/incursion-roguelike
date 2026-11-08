#!/bin/bash
# witness for F05 (both sides add an option numbered 899): the landed tree loads a real fixture save with the
# 900-byte settings file the case started from, through the game's own load path (LoadOptions reads OPT_LAST
# bytes). A short read or a refusal is a failure of the case. $1 = the worktree, $2 = the oracle's output directory.
# fact: fixture -- tools/fixtures/chars/elf-mage-spotted-seed1.sav, frozen bytes; no seed (seed 1 only repeats the run)
# fact: settings -- tools/fixtures/options-2026-08-22.dat, frozen bytes, 900 of them
set -uo pipefail
W="$1"; O="$2"
[ -x "$W/tools/headless.sh" ] || { echo "no headless.sh"; exit 2; }
RD="$O/f05-opt-run"; rm -rf "$RD"
( cd "$W" && INCURSION_OPTIONS="$W/tools/fixtures/options-2026-08-22.dat" \
    INCURSION_LOAD="$W/tools/fixtures/chars/elf-mage-spotted-seed1.sav" INCURSION_RUN_DIR="$RD" \
    tools/headless.sh tools/keys/load-char-sheet.keys 1 ) > "$O/f05-opt.out" 2>&1
rc=$?
olast="$(sed -n 's/^#define OPT_LAST[[:space:]]*\([0-9]*\).*/\1/p' "$W/inc/Defines.h" | head -1)"
echo "OPT_LAST=${olast:-?} settings file=900 bytes headless exit=$rc"
if grep -qiE 'EREADERR|short read|corrupt|Fatal' "$O/f05-opt.out" "$RD"/logs/*.log 2>/dev/null; then
    echo "FAIL: the load of a real save with the 900-byte settings file reported an error:"
    grep -hiE 'EREADERR|short read|corrupt|Fatal' "$O/f05-opt.out" "$RD"/logs/*.log 2>/dev/null | head -3
    exit 1
fi
[ $rc -eq 0 ] || { echo "FAIL: headless exit $rc loading a real save with the 900-byte settings file"; exit 1; }
echo "witness: the real save loads with the 900-byte settings file"
exit 0
