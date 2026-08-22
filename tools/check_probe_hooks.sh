#!/bin/bash
# Every debugging hook in the shipped game names a bead, and none is deleted
# until the reproduction it carries is preserved somewhere upstream can read it.
#
# Usage: tools/check_probe_hooks.sh              # check
#        tools/check_probe_hooks.sh --baseline   # re-record the known backlog
# Exit:  0 no undeclared hook outside the baseline
#        1 a hook names no bead, or the baseline is stale
#        2 nothing was measured, and the reason is printed
#
# WHY THIS EXISTS. The game reads two dozen INCURSION_* environment variables at
# run time. They are not compiled out for release: they are plain getenv calls,
# live in the binary a stranger downloads, and six of them change how the game
# plays rather than merely logging what it did. Each was added with a comment
# promising it would go when its bead closed. Almost none has gone. Beads close,
# the scaffolding stays, and nothing notices.
#
# THE RULE IT ENFORCES, and it is one rule: a hook must say which bead it serves.
# That is all. It is cheap to obey when you add a hook and impossible to
# reconstruct a year later, which is why the check is worth having at all.
#
# THE RULE IT REFUSES TO ENFORCE. It will not tell you to delete anything. A
# probe is often the only reproduction a defect has -- the state can be
# unreachable from a key script, so the probe IS the evidence -- and several of
# these back claims already made to the original maintainer. Deleting one of
# those destroys our answer to "how do you know?". So a hook whose bead is
# finished is reported as HELD until its reproduction exists as a patch under
# docs/evidence/<bead>/, and only then as RETIRED. docs/evidence/inc-ijs/
# destroy-probe.patch is the pattern: the probe leaves the source and stays
# readable, and the bead and the REPORTING-GATE row point at it.
#
# See docs/REPORTING-GATE.md, "Reconstructing a removed probe".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BASELINE="tools/probe_hooks.baseline"

# Documented facilities, not scaffolding. These are how the tools drive the
# game and are meant to stay: the seed, the key budget, the map audit, the
# error prompt, and the heap-layout switch, which is compiled out anyway.
KNOBS="INCURSION_SEED INCURSION_MAX_KEYS INCURSION_MAP_AUDIT INCURSION_ERROR_PROMPT INCURSION_LAYOUT"

command -v bd > /dev/null || {
    echo "COULD NOT MEASURE: bd is not on PATH, so no bead status can be read."
    exit 2
}

hooks="$(grep -rhoE 'getenv\("INCURSION_[A-Z_]+"' src/ inc/ 2>/dev/null |
         sed 's/getenv("//; s/"//' | sort -u)"

[ -n "$hooks" ] || {
    echo "COULD NOT MEASURE: no getenv(\"INCURSION_...\") found in src/ or inc/."
    echo "  Either the tree moved or this script's pattern is stale."
    exit 2
}

# The bead a hook serves is the nearest tracking id above one of its call
# sites. Forty lines is the window: these hooks sit under a block comment that
# explains them, and the id lives in that comment.
bead_for() {
    local hook="$1" file line id
    grep -rlE "getenv\(\"$hook\"" src/ inc/ 2>/dev/null | while read -r file; do
        line="$(grep -nE "getenv\(\"$hook\"" "$file" | head -1 | cut -d: -f1)"
        [ -n "$line" ] || continue
        id="$(sed -n "$((line > 40 ? line - 40 : 1)),${line}p" "$file" |
              grep -oE 'inc-[a-z0-9]+(\.[0-9]+)*' | tail -1)"
        [ -n "$id" ] && { echo "$id"; return; }
    done | head -1
}

status_of() {
    bd show "$1" 2>/dev/null | head -1 |
        grep -oE '(OPEN|IN_PROGRESS|CLOSED|DEFERRED|BLOCKED)' | head -1
}

if [ "${1:-}" = "--baseline" ]; then
    : > "$BASELINE"
    for h in $hooks; do
        case " $KNOBS " in *" $h "*) continue ;; esac
        [ -z "$(bead_for "$h")" ] && echo "$h" >> "$BASELINE"
    done
    echo "recorded $(wc -l < "$BASELINE" | tr -d ' ') undeclared hook(s) in $BASELINE"
    exit 0
fi

[ -f "$BASELINE" ] || {
    echo "COULD NOT MEASURE: no $BASELINE."
    echo "  Record the hooks that predate this rule, once:"
    echo "    tools/check_probe_hooks.sh --baseline"
    exit 2
}

orphans=0; stale=0; live=0; held=0; retired=0; knobs=0
declare -a HELD_LIST RETIRED_LIST NEW_LIST

for h in $hooks; do
    case " $KNOBS " in *" $h "*) knobs=$((knobs+1)); continue ;; esac
    id="$(bead_for "$h")"

    if [ -z "$id" ]; then
        if grep -qxF "$h" "$BASELINE"; then
            orphans=$((orphans+1))
        else
            NEW_LIST+=("$h")
        fi
        continue
    fi

    # A hook that has since been given a bead must leave the baseline, or the
    # baseline slowly becomes a list of things that are already fixed.
    grep -qxF "$h" "$BASELINE" && { stale=$((stale+1)); NEW_LIST+=("$h names $id but is still in the baseline"); }

    case "$(status_of "$id")" in
        OPEN|IN_PROGRESS|BLOCKED|"")
            live=$((live+1)) ;;
        *)
            if ls docs/evidence/"$id"/*.patch > /dev/null 2>&1; then
                retired=$((retired+1)); RETIRED_LIST+=("$h ($id)")
            else
                held=$((held+1)); HELD_LIST+=("$h ($id)")
            fi ;;
    esac
done

echo "hooks:    $((knobs + live + held + retired + orphans)) reading the environment in src/ and inc/"
echo "  knob:      $knobs documented facility, not scaffolding"
echo "  live:      $live serving a bead that is still open"
echo "  held:      $held bead finished, reproduction NOT yet preserved"
echo "  retired:   $retired bead finished, reproduction preserved -- safe to delete"
echo "  undeclared: $orphans naming no bead, known and baselined"

if [ "$held" -gt 0 ]; then
    echo
    echo "HELD -- these are UNFINISHED CLOSES, not permanent residents. The bead"
    echo "        is done and the probe should have gone with it. Save each one as"
    echo "        a patch under docs/evidence/<bead>/, then delete it from src/:"
    printf '  %s\n' "${HELD_LIST[@]}"
fi

if [ "$retired" -gt 0 ]; then
    echo
    echo "RETIRED -- reproduction is preserved, so the source copy can go:"
    printf '  %s\n' "${RETIRED_LIST[@]}"
fi

if [ ${#NEW_LIST[@]} -gt 0 ]; then
    echo
    echo "FAIL -- a hook must name the bead it serves, in a comment within 40"
    echo "        lines above its getenv:"
    printf '  %s\n' "${NEW_LIST[@]}"
    echo
    echo "  Add the tracking id to the comment. If this hook predates the rule"
    echo "  and you are not fixing it now, re-record the backlog with"
    echo "  tools/check_probe_hooks.sh --baseline and say so in the commit."
    exit 1
fi

echo
echo "PASS -- every hook outside the recorded backlog names its bead."
exit 0
