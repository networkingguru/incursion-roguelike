#!/bin/bash
# gate: cheap
# Does every check in tools/ say whether the gate should run it?
#
# WHY. tools/nightly_verify.sh used to hold a hand-written list of the checks
# it ran. Nothing made an author add a row to it, so on 2026-09-11 the gate ran
# 18 of the 226 checks in this directory, and five of the absentees met its own
# admission rule in full: deterministic, no build, one second for all five
# together. A list nobody is obliged to update is a list that stops being true.
#
# So the gate discovers its checks instead, by reading a marker in each file,
# and this check is what obliges an author to write one:
#
#   # gate: cheap              deterministic, needs no build, costs seconds
#   # gate: cheap --selftest   the same, with arguments; @base becomes the ref
#   # gate: live               the same, but it plays the game and needs a build
#   # gate: none <reason>      not for the gate, and the reason says why
#
# The marker goes in the first 40 lines. Anything that needs a build, a network,
# a worktree, a public tracker or more than a few seconds is `none`, and the
# reason is for the next person, not for this script.
#
# THE BACKLOG. tools/gate_membership.baseline holds the checks that were here
# before the rule, so the rule does not block every commit on a backlog nobody
# asked for. A check IN the baseline may stay unmarked. A check that is NOT in
# the baseline and has no marker fails this check. The baseline only shrinks:
# mark a check, then delete its line.
#
# Usage: tools/check_gate_membership.sh [--selftest]

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${GATE_MEMBERSHIP_DIR:-$ROOT/tools}"
BASELINE="${GATE_MEMBERSHIP_BASELINE:-$ROOT/tools/gate_membership.baseline}"

marker_of() { # marker_of <file> -> the marker text, or nothing
    sed -n '1,40p' "$1" | sed -n 's/^#[[:space:]]*gate:[[:space:]]*//p' | head -1
}

in_baseline() { # in_baseline <basename>
    [ -r "$BASELINE" ] || return 1
    grep -qx -- "$1" "$BASELINE"
}

run() {
    local f base marker tier rest
    local unmarked=0 bad=0 marked=0 graduated=0 stale=0

    for f in "$DIR"/check_*.sh "$DIR"/check_*.py; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        marker="$(marker_of "$f")"

        if [ -z "$marker" ]; then
            if in_baseline "$base"; then
                continue
            fi
            echo "NO MARKER  $base"
            echo "           add one of: '# gate: cheap', '# gate: live',"
            echo "           or '# gate: none <why not>' in its first 40 lines."
            unmarked=$((unmarked + 1))
            continue
        fi

        marked=$((marked + 1))
        tier="${marker%%[[:space:]]*}"
        rest="${marker#"$tier"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        case "$tier" in
            cheap|live) ;;
            none)
                if [ -z "$rest" ]; then
                    echo "NO REASON  $base says 'gate: none' and does not say why."
                    bad=$((bad + 1))
                fi
                ;;
            *)
                echo "BAD TIER   $base says 'gate: $tier' (want cheap, live or none)"
                bad=$((bad + 1))
                ;;
        esac

        if in_baseline "$base"; then
            echo "note: $base now declares a tier; delete its line from"
            echo "      $(basename "$BASELINE")"
            graduated=$((graduated + 1))
        fi
    done

    if [ -r "$BASELINE" ]; then
        while read -r base; do
            case "$base" in ''|'#'*) continue ;; esac
            [ -f "$DIR/$base" ] || { echo "note: $base is in the baseline and gone from tools/"; stale=$((stale + 1)); }
        done < "$BASELINE"
    fi

    echo
    echo "$marked check(s) declare a gate tier; $unmarked do not and are not in the baseline."
    [ "$graduated" = 0 ] || echo "$graduated baseline line(s) can be deleted."
    [ "$stale" = 0 ] || echo "$stale baseline line(s) name a file that is gone."

    if [ "$unmarked" = 0 ] && [ "$bad" = 0 ]; then
        echo "PASS: every check says whether the gate should run it."
        return 0
    fi
    echo "FAIL: $unmarked undeclared, $bad malformed."
    return 1
}

selftest() {
    local dir rc fails=0
    dir="$(mktemp -d -t gatemember)" || return 2
    # Expanded now, not at exit: $dir is local and gone by the time EXIT fires.
    trap "rm -rf '$dir'" EXIT

    printf '#!/bin/sh\n# gate: cheap\n'            > "$dir/check_marked.sh"
    printf '#!/bin/sh\n# gate: none too slow\n'    > "$dir/check_excused.sh"
    printf '#!/bin/sh\n# nothing here\n'           > "$dir/check_old.sh"
    printf '#!/bin/sh\n# nothing here\n'           > "$dir/check_new.sh"
    printf '#!/bin/sh\n# gate: sometimes\n'        > "$dir/check_wrong.sh"
    printf '#!/bin/sh\n# gate: none\n'             > "$dir/check_silent.sh"
    printf 'check_old.sh\n'                        > "$dir/baseline"

    _case() { # _case <expect-rc> <what it proves> <extra files to hide>
        local want="$1" what="$2"
        local out
        out="$(GATE_MEMBERSHIP_DIR="$dir" GATE_MEMBERSHIP_BASELINE="$dir/baseline" "$0" 2>&1)"
        rc=$?
        if [ "$rc" = "$want" ]; then
            printf '  ok    %s\n' "$what"
        else
            printf '  FAIL  %s (exit %s, wanted %s)\n%s\n' "$what" "$rc" "$want" "$out"
            fails=$((fails + 1))
        fi
    }

    _case 1 'an undeclared new check fails'
    rm "$dir/check_new.sh"
    _case 1 'a malformed tier fails'
    rm "$dir/check_wrong.sh"
    _case 1 "'none' with no reason fails"
    rm "$dir/check_silent.sh"
    _case 0 'a marked check, an excused one and a baselined one pass'

    echo
    [ "$fails" = 0 ] && { echo "SELFTEST PASS"; return 0; }
    echo "SELFTEST FAIL: $fails"
    return 1
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    "")         run; exit $? ;;
    -h|--help)  sed -n '3,27p' "$0"; exit 0 ;;
    *)          echo "unknown argument: $1" >&2; exit 2 ;;
esac
