#!/usr/bin/env bash
#
# The gate an unattended run's branch must clear before it reaches master.
#
#   tools/nightly_verify.sh --record    # before the run: what already failed
#   tools/nightly_verify.sh --compare   # after the run: did this run break any
#   tools/nightly_verify.sh             # same as --compare, no recorded base
#   tools/nightly_verify.sh --selftest  # does the ratchet itself still bite?
#   tools/nightly_verify.sh --docs-only # *.md changed and nothing else did
#   tools/nightly_verify.sh --reuse-pass # the landing: reuse a full pass on these files
#
# Exit: 0 safe to merge
#       1 this run broke something, or a build failed
#       2 could not measure
#
# WHY A RATCHET AND NOT "EVERYTHING MUST PASS". Checks arrive faster than their
# backlogs drain, so at any moment some check is red for a reason that predates
# the work in hand. A gate demanding a clean sweep would block every merge on
# somebody else's backlog, which is the opposite of the point. So the rule is:
# a check that ALREADY failed before the run is not this run's fault; a check
# that passed before and fails after is, and it stops the merge.
#
# THREE EXIT CODES, NOT TWO. A check exits 0 for pass, 2 for "could not
# measure", and anything else for fail. The difference matters in both
# directions, and until 2026-09-11 this script collapsed 2 into "fail" and got
# both directions wrong: a check that could not measure BEFORE the run forgave
# a real failure after it, and a check that could not measure AFTER a clean
# base cried wolf. The table this script now applies, base down, now across:
#
#             now 0          now 2                     now other
#   base 0    ok             UNMEASURED, stops merge   BROKEN, stops merge
#   base 2    FIXED          unmeasured, passes        BROKEN, stops merge
#   base fail FIXED          unmeasured, passes        pre-existing, passes
#
# Read the two that are not obvious. Base 2 with a failure now STOPS the merge,
# because nothing measured this check before the run and an unknown that is red
# now is what a person must look at. Base 0 with a 2 now also stops it: the
# check ran before this work and cannot run after it, which is a change for the
# worse even when the check itself is blameless.
#
# WHICH CHECKS RUN, AND WHY YOU DO NOT EDIT A LIST HERE. Every check declares
# its own tier, on one line near the top of its own file:
#
#   # gate: cheap              deterministic, needs no build, costs seconds
#   # gate: cheap --selftest   the same, with arguments; @base becomes the ref
#   # gate: live               the same, but it plays the game and needs a build
#   # gate: none <reason>      not for the gate, and the reason says why
#
# This script globs tools/check_* and reads those markers, so a new check joins
# the gate when it is written rather than when somebody remembers this file.
# Before 2026-09-11 the lists lived here, and five checks that met the rule in
# full -- deterministic, no build, one second for all five together -- had sat
# outside the gate for weeks. tools/check_gate_membership.sh is the check that
# a new check declares a tier at all.
#
# The BUILDS are absolute, not ratcheted. A tree that does not compile is never
# safe to merge, whatever it did yesterday. Both backends build, because they
# are separate main()s and a change can break one while the other compiles.
#
# THE LINUX CROSS-BUILD, THE LAYOUT SWEEP AND THE SOAK run here with the builds
# and not in the ratchet, because they share the same three properties: each
# needs a build of its own, each has three exit codes, and a machine that
# cannot run one reports a skip and stays green. A check that could not run has
# measured nothing, and nothing is not a failure.
#
#   the Linux cross-build   commit 04431f2 broke it on 2026-09-02 and nothing
#                           saw it until a release build failed two days later.
#   the layout sweep        does this build still play the same game when its
#                           objects move? The inc-dhc class, about an hour a
#                           site to hunt by hand.
#   the soak                40 seeded sessions against tools/gates/*.baseline,
#                           about a minute. It is the canary the ratchet is
#                           not: it names no rule, and reports a new complaint
#                           in several sessions at once, fewer sessions
#                           reaching a map, or more deaths and freezes.
#
# WHERE THE BASE IS RECORDED. $NIGHTLY_VERIFY_STATE if set (the harness points it
# outside the repository), otherwise logs/nightly-verify-base.txt. It is a
# record of a run, not source: never commit it.
#
# A FULL PASS IS REMEMBERED, FOR THE FILES IT MEASURED (inc-689z). Each full
# --compare that passes writes nightly-verify-pass.txt beside the base. Its key
# is the hash of the files on disk (tracked, and untracked but not ignored), the
# hash of the base, and a fingerprint of the toolchain and of the variables the
# builds read. --reuse-pass, which tools/finish_bead.sh runs, finds a record that
# matches all three and is under 24 hours old, then skips the builds, the Linux
# build, the layout sweep, the soak and the live tier. None of those reads git:
# they read the files, the toolchain and the base, which is exactly the key.
#
# THE CHEAP TIER ALWAYS RUNS AGAIN. Some of its checks read git and bead state
# -- commit messages, HEAD, the branches -- which no hash of the files covers.
# On 2026-09-13 a landing went red on one of them after an earlier run on the
# same files was green, because the commit in between moved HEAD.
#
# IT FAILS CLOSED. A missing, unreadable, malformed, stale or mismatched record
# runs the full gate. A full run deletes the old record first, so a failure
# after a pass is never forgotten, and it writes no record when the files
# changed while it ran. --checks-only, --docs-only and a reused pass write none.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

STATE="${NIGHTLY_VERIFY_STATE:-$ROOT/logs/nightly-verify-base.txt}"
PASS_RECORD="$(dirname "$STATE")/nightly-verify-pass.txt"
PASS_MAX_AGE=86400
BASE_REF="${NIGHTLY_BASE_REF:-master}"
# The selftest points this at a directory of made-up checks. Nothing else does.
CHECK_DIR="${NIGHTLY_CHECK_DIR:-$ROOT/tools}"
MODE="compare"

SKIP_BUILDS=0
SKIP_LIVE=0
REUSE=0
case "${1:-}" in
    --record)      MODE="record" ;;
    --compare)     MODE="compare" ;;
    # --checks-only exists so the ratchet can be exercised without rebuilding.
    # A build here overwrites ./incursion and mod/Incursion.Mod, which is not
    # safe to do while somebody is playing the game out of this directory.
    --checks-only) MODE="compare"; SKIP_BUILDS=1 ;;
    # --docs-only is the carve-out for a change that cannot reach the
    # game: it drops the builds and the live tier and keeps the whole
    # cheap tier, which is where every documentation check lives. The
    # CALLER decides a change qualifies, and tools/docs_only_change.sh is
    # the only thing allowed to make that decision -- this flag trusts it
    # and asks no questions, so nothing may pass it on a guess.
    --docs-only)   MODE="compare"; SKIP_BUILDS=1; SKIP_LIVE=1 ;;
    # --reuse-pass asks no trust of its caller: it checks the pass record
    # itself, and with no match it is --compare.
    --reuse-pass)  MODE="compare"; REUSE=1 ;;
    --selftest)    MODE="selftest" ;;
    "")            MODE="compare" ;;
    -h|--help)     sed -n '2,14p' "$0"; exit 0 ;;
    *)             echo "unknown argument: $1" >&2; exit 2 ;;
esac

# --------------------------------------------------------------- discovery ---
# Each entry is "<id><TAB><command><TAB><tier>". The id is what the state file
# keys on, so it holds the marker verbatim; the command is the id with @base
# expanded; the tier is what the marker said.
# Keeping them apart means NIGHTLY_BASE_REF can change without every recorded
# base silently turning into a set of checks nobody has ever measured.
CHECKS=()

discover_checks() {
    local f marker tier args id cmd
    local cheap=() live=()
    for f in "$CHECK_DIR"/check_*.sh "$CHECK_DIR"/check_*.py; do
        [ -f "$f" ] || continue
        marker="$(sed -n '1,40p' "$f" | sed -n 's/^#[[:space:]]*gate:[[:space:]]*//p' | head -1)"
        [ -n "$marker" ] || continue
        tier="${marker%%[[:space:]]*}"
        args="${marker#"$tier"}"
        args="${args#"${args%%[![:space:]]*}"}"
        # The id names the check the way a reader and the state file want it,
        # always tools/<name>. The command names the file that is actually
        # there, which is a different path only when the selftest is driving.
        id="tools/$(basename "$f")"
        cmd="$f"
        if [ -n "$args" ]; then
            id="$id $args"
            cmd="$cmd ${args//@base/$BASE_REF}"
        fi
        case "$tier" in
            cheap) cheap+=( "$id	$cmd	cheap" ) ;;
            live)  live+=( "$id	$cmd	live" ) ;;
            none)  ;;
            *) echo "$f: unknown gate tier '$tier' (want cheap, live or none)" >&2 ;;
        esac
    done
    # Cheap first, so a reader watching the output sees the seconds before the
    # minutes. Within a tier the glob's order is alphabetical and stable.
    if [ "$SKIP_LIVE" = 1 ]; then
        CHECKS=( ${cheap[@]+"${cheap[@]}"} )
    else
        CHECKS=( ${cheap[@]+"${cheap[@]}"} ${live[@]+"${live[@]}"} )
    fi
}

run_check() { # run_check "<command line>" -> echoes the exit code
    local cmd="$1"
    ( eval "$cmd" ) > /dev/null 2>&1
    echo $?
}

# ------------------------------------------------------------- pass record ---
# The key of a full pass is three hashes. Each function prints nothing when it
# cannot compute its hash, and an empty hash never writes or matches a record.

content_tree() { # the files on disk: tracked, and untracked but not ignored
    # A throwaway copy of the index, so git reads again only the files whose
    # stat changed. git add writes their blobs to the object store; gc prunes.
    local idx tree
    idx="$(mktemp "${TMPDIR:-/tmp}/nvindex.XXXXXX")" || return 0
    cp -f "$(git rev-parse --git-path index 2>/dev/null)" "$idx" 2>/dev/null || rm -f "$idx"
    tree="$(GIT_INDEX_FILE="$idx" git add -A 2>/dev/null \
        && GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null)"
    rm -f "$idx" "$idx.lock"
    printf '%s' "$tree"
}

base_hash() { # the recorded base, or "none" when the run has none
    [ -r "$STATE" ] || { printf none; return 0; }
    git hash-object -- "$STATE" 2>/dev/null
}

env_fingerprint() { # what the builds and the live tier read from outside the files
    uname -srm
    ${CC:-cc} --version 2>/dev/null | head -1
    ${CXX:-c++} --version 2>/dev/null | head -1
    pkg-config --modversion sdl2 2>/dev/null
    # Without these two, the layout sweep and the Linux build report a skip.
    command -v lldb
    if command -v docker > /dev/null && docker info > /dev/null 2>&1; then
        echo "docker daemon up"
    fi
    # The build's variables, the harness's, and every variable src/ reads.
    # Only the cheap tier reads NIGHTLY_BASE_REF, and only tools/finish_bead.sh
    # reads its own two variables, so none of the three can make a landing miss.
    env | grep -E '^(CC|CXX|AR|NM|OUT|TARGET|BACKEND|COMPILER|WARN_FLAGS|EXTRA_[A-Z_]*|CXXFLAGS_[A-Z_]*|INCURSION[A-Z_]*|INC6D5_[A-Z_]*|SteamGameId|NIGHTLY_[A-Z_]*|LAYOUT_[A-Z_]*|SOAK_[A-Z_]*)=' \
        | grep -vE '^(NIGHTLY_BASE_REF|INCURSION_BASE_BRANCH|INCURSION_FINISH_GATE)=' \
        | LC_ALL=C sort
}

env_hash() { env_fingerprint | git hash-object --stdin 2>/dev/null; }

record_field() { sed -n "s/^$1 //p" "$PASS_RECORD" 2>/dev/null; }

# pass_matches -> 0 when a full pass on these exact files is on record, 1 when
# not, and one line either way saying why. Anything it does not expect is a
# miss, so the worst a fault here can cost is one full run.
pass_matches() {
    local tree base envh rtree rbase renv rtime age
    [ -e "$PASS_RECORD" ] || { echo "no full pass on record"; return 1; }
    [ -r "$PASS_RECORD" ] || { echo "the pass record cannot be read"; return 1; }
    rtree="$(record_field tree)"; rbase="$(record_field base)"
    renv="$(record_field env)";   rtime="$(record_field time)"
    # At most 12 digits, so the age below cannot overflow into a match.
    case "$rtime" in ''|*[!0-9]*|?????????????*)
        echo "the pass record is malformed"; return 1 ;;
    esac
    if [ -z "$rtree" ] || [ -z "$rbase" ] || [ -z "$renv" ]; then
        echo "the pass record is malformed"; return 1
    fi
    tree="$(content_tree)"; base="$(base_hash)"; envh="$(env_hash)"
    if [ -z "$tree" ] || [ -z "$base" ] || [ -z "$envh" ]; then
        echo "could not compute the key of these files"; return 1
    fi
    [ "$tree" = "$rtree" ] || { echo "the files differ from the ones that passed"; return 1; }
    [ "$base" = "$rbase" ] || { echo "the recorded base changed after the pass"; return 1; }
    [ "$envh" = "$renv" ] || { echo "the toolchain or the build variables changed after the pass"; return 1; }
    age=$(( $(date +%s) - 10#$rtime ))
    if [ "$age" -lt 0 ] || [ "$age" -gt "$PASS_MAX_AGE" ]; then
        echo "the pass is more than 24 hours old"; return 1
    fi
    echo "a full pass at $(record_field when): tree $tree, base $base, env $envh"
    return 0
}

# write_pass_record <tree> <base> <env>. A record that cannot be written costs
# one full run at the landing and nothing else, so it warns and does not fail.
write_pass_record() {
    local tmp="$PASS_RECORD.tmp.$$"
    mkdir -p "$(dirname "$PASS_RECORD")" 2> /dev/null
    if {
        echo "# A full tools/nightly_verify.sh --compare passed on these files (inc-689z)."
        echo "# A record of a run, not source: never commit it."
        printf 'tree %s\nbase %s\nenv %s\ntime %s\nwhen %s\n' "$1" "$2" "$3" \
            "$(date +%s)" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    } > "$tmp" 2> /dev/null && mv -f "$tmp" "$PASS_RECORD"; then
        echo "pass recorded in $PASS_RECORD:"
        echo "for 24 hours, a landing on these exact files runs only the cheap tier"
    else
        rm -f "$tmp"
        echo "note: could not write $PASS_RECORD, so the landing runs the full gate"
    fi
}

# ---------------------------------------------------------------- selftest ---
# Drives the table in the header over made-up checks, because every cell of it
# was wrong once and the run that would have caught it costs fifteen minutes.
selftest() {
    local dir state fails=0
    dir="$(mktemp -d -t nvselftest)" || return 2
    state="$dir/base.txt"
    # Expanded now, not at exit: $dir is local and gone by the time EXIT fires.
    trap "rm -rf '$dir'" EXIT

    _mk() { # _mk <name> <exit-code-when-BEFORE-is-set> <exit-code-otherwise>
        printf '#!/bin/sh\n# gate: cheap\n[ -n "${BEFORE:-}" ] && exit %s\nexit %s\n' \
            "$2" "$3" > "$dir/check_$1.sh"
        chmod +x "$dir/check_$1.sh"
    }
    #    name          base  now
    _mk green           0     0
    _mk broke           0     1
    _mk red             1     1
    _mk fixed           1     0
    _mk was_unmeasured  2     1
    _mk stays_unmeasured 2    2
    _mk went_unmeasured 0     2
    _mk unmeasured_fixed 2    0

    BEFORE=1 NIGHTLY_CHECK_DIR="$dir" NIGHTLY_VERIFY_STATE="$state" \
        "$0" --record > /dev/null 2>&1
    local out rc
    out="$(NIGHTLY_CHECK_DIR="$dir" NIGHTLY_VERIFY_STATE="$state" \
        "$0" --checks-only 2>&1)"
    rc=$?

    _want() { # _want <regex> <what it proves>
        if printf '%s\n' "$out" | grep -Eq "$2"; then
            printf '  ok    %s\n' "$1"
        else
            printf '  FAIL  %s\n      wanted /%s/\n' "$1" "$2"
            fails=$((fails + 1))
        fi
    }
    _want 'a check that passed before and passes now is quiet' \
          '^ok +tools/check_green\.sh'
    _want 'a check that passed before and fails now stops the merge' \
          '^BROKEN +tools/check_broke\.sh'
    _want 'a check that already failed is not this run.s fault' \
          '^pre-existing tools/check_red\.sh'
    _want 'a check this run repaired says so' \
          '^FIXED +tools/check_fixed\.sh'
    _want 'a failure under an unmeasured base stops the merge' \
          '^BROKEN +tools/check_was_unmeasured\.sh'
    _want 'a check that could not measure before or after passes' \
          '^unmeasured +tools/check_stays_unmeasured\.sh'
    _want 'a check that could measure before and cannot now stops the merge' \
          '^UNMEASURED +tools/check_went_unmeasured\.sh'
    _want 'a check that can measure again says so' \
          '^FIXED +tools/check_unmeasured_fixed\.sh'
    _want 'the run as a whole refuses the merge' \
          '=== FAIL'

    if [ "$rc" != 1 ]; then
        printf '  FAIL  the run exits 1 when it refuses a merge (got %s)\n' "$rc"
        fails=$((fails + 1))
    else
        printf '  ok    the run exits 1 when it refuses a merge\n'
    fi

    # The discovery half: the real tools/ directory must yield checks, and must
    # not yield one that never declared a tier.
    CHECK_DIR="$ROOT/tools" discover_checks
    if [ "${#CHECKS[@]}" -lt 15 ]; then
        printf '  FAIL  discovery found only %s checks in tools/\n' "${#CHECKS[@]}"
        fails=$((fails + 1))
    else
        printf '  ok    discovery found %s checks in tools/\n' "${#CHECKS[@]}"
    fi

    echo
    if [ "$fails" = 0 ]; then
        echo "SELFTEST PASS"
        return 0
    fi
    echo "SELFTEST FAIL: $fails"
    return 1
}

if [ "$MODE" = "selftest" ]; then
    selftest
    exit $?
fi

# Decided before discovery, because a reused pass drops the live tier.
REUSED=0
if [ "$REUSE" = 1 ]; then
    if REUSE_VERDICT="$(pass_matches)"; then
        REUSED=1; SKIP_BUILDS=1; SKIP_LIVE=1
    else
        echo "--- no pass to reuse: $REUSE_VERDICT. Running the full gate. ---"
    fi
fi
FULL_RUN=0
if [ "$MODE" = "compare" ] && [ "$SKIP_BUILDS" = 0 ] && [ "$SKIP_LIVE" = 0 ]; then
    FULL_RUN=1
    rm -f "$PASS_RECORD"
    KEY_TREE="$(content_tree)"; KEY_BASE="$(base_hash)"; KEY_ENV="$(env_hash)"
fi

discover_checks
if [ "${#CHECKS[@]}" = 0 ]; then
    echo "no check in $CHECK_DIR declares a '# gate:' tier" >&2
    exit 2
fi

# ------------------------------------------------------------------ record ---
if [ "$MODE" = "record" ]; then
    mkdir -p "$(dirname "$STATE")" || exit 2
    : > "$STATE"
    for entry in "${CHECKS[@]}"; do
        id="${entry%%	*}"
        rest="${entry#*	}"
        rc="$(run_check "${rest%%	*}")"
        printf '%s\t%s\n' "$rc" "$id" >> "$STATE"
        printf 'base %-3s %s\n' "$rc" "$id"
    done
    echo "recorded the pre-run state in $STATE"
    exit 0
fi

# ----------------------------------------------------------------- compare ---
FAILED=0

if [ "$SKIP_BUILDS" = 1 ]; then
    if [ "$REUSED" = 1 ]; then
        echo "--- builds and the live tier REUSED from $REUSE_VERDICT ---"
    elif [ "$SKIP_LIVE" = 1 ]; then
        echo "--- builds and the live tier SKIPPED (--docs-only: no *.md reaches them) ---"
    else
        echo "--- builds SKIPPED (--checks-only) ---"
    fi
else
    echo "--- builds, macOS then Linux (absolute: a tree that does not compile never merges) ---"
    for build in "BACKEND=posix ./build_macos.sh" "./build_macos.sh"; do
        printf '%s ... ' "$build"
        if ( eval "$build" ) > /dev/null 2>&1; then
            echo "ok"
        else
            echo "FAILED"
            echo "    re-run it to see why: $build"
            FAILED=1
        fi
    done

    # Their own steps, not entries in the loop above, because each has three
    # exit codes and the loop reads every non-zero as a failure. Exit 2 is
    # "could not measure" -- no docker, no lldb, no baseline, a failed image
    # build. None of those says the tree is broken, so none stops a merge.
    # Each entry is "<command><TAB><what to run by hand when it goes red>".
    for step in \
        "tools/check_linux_build.sh	tools/check_linux_build.sh" \
        "tools/check_layout_sweep.sh	tools/check_layout_sweep.sh --no-build" \
        "tools/gate_compare.sh	tools/gate_compare.sh --from <the run it kept>"
    do
        printf '%s ... ' "${step%%	*}"
        ( eval "${step%%	*}" ) > /dev/null 2>&1
        case $? in
            0) echo "ok" ;;
            2) echo "SKIPPED (could not measure)" ;;
            *) echo "FAILED"
               echo "    re-run it to see why: ${step#*	}"
               FAILED=1 ;;
        esac
    done
fi

echo
echo "--- checks (ratcheted against the state before the run) ---"
if [ -r "$STATE" ]; then
    echo "base recorded in $STATE"
else
    echo "NO recorded base. Every check must pass outright."
fi

for entry in "${CHECKS[@]}"; do
    id="${entry%%	*}"
    rest="${entry#*	}"
    tier="${rest#*	}"
    started=$SECONDS
    now="$(run_check "${rest%%	*}")"
    elapsed=$((SECONDS - started))
    was=""
    if [ -r "$STATE" ]; then
        was="$(awk -F'\t' -v c="$id" '$2 == c { print $1 }' "$STATE" | head -1)"
    fi
    # A check the base never saw is a check nobody has measured. Treat it as
    # having passed, so a new check joins the gate green or not at all.
    [ -n "$was" ] || was=0

    if [ "$now" = "0" ]; then
        if [ "$was" != "0" ]; then
            printf 'FIXED       %s (was exit %s)\n' "$id" "$was"
        else
            printf 'ok          %s\n' "$id"
        fi
    elif [ "$now" = "2" ]; then
        if [ "$was" = "0" ]; then
            printf 'UNMEASURED  %s (exit 2; it could be measured before this run)\n' "$id"
            FAILED=1
        else
            printf 'unmeasured  %s (exit 2 before and after -- not this run)\n' "$id"
        fi
    elif [ "$was" != "0" ] && [ "$was" != "2" ]; then
        printf 'pre-existing %s (exit %s now, exit %s before -- not this run)\n' "$id" "$now" "$was"
    else
        printf 'BROKEN      %s (exit %s; it %s before this run)\n' "$id" "$now" \
            "$([ "$was" = 2 ] && echo "could not be measured" || echo "passed")"
        FAILED=1
    fi
    # The cheap tier's whole promise is that it costs seconds, and a check that
    # quietly stops keeping it is how a gate becomes something people skip.
    if [ "$tier" = "cheap" ] && [ "$elapsed" -gt 30 ]; then
        printf '            note: %ss. A cheap check should cost seconds --\n' "$elapsed"
        printf '            mark it "# gate: live" or "# gate: none <why>".\n'
    fi
done

echo
if [ "$FAILED" = 0 ]; then
    if [ "$FULL_RUN" = 1 ]; then
        if [ -z "$KEY_TREE" ] || [ -z "$KEY_BASE" ] || [ -z "$KEY_ENV" ]; then
            echo "no pass recorded: could not compute the key of these files"
        elif [ "$(content_tree)" != "$KEY_TREE" ] || [ "$(base_hash)" != "$KEY_BASE" ]; then
            echo "no pass recorded: the files or the base changed while the gate ran"
        else
            write_pass_record "$KEY_TREE" "$KEY_BASE" "$KEY_ENV"
        fi
    fi
    echo "=== PASS: safe to merge ==="
    exit 0
fi
echo "=== FAIL: do NOT merge. The branch stays for a person to read. ==="
exit 1
