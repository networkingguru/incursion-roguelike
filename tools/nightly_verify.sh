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
#   tools/nightly_verify.sh --landing   # the short gate a landing runs
#   tools/nightly_verify.sh --landing --reuse-pass # the landing, reusing a pass
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
# WHERE A CHECK'S OUTPUT GOES. nightly-verify/ beside that base, one file per
# check, written whether the check passed or failed, and named in the terminal
# whenever a check comes back non-zero. Until 2026-09-16 every check's stdout
# and stderr went to /dev/null, so a BROKEN verdict named the check and nothing
# else. run_check carries the whole reason and inc-9diw is the flake that paid
# for it.
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
# One directory of check output, beside the base and the pass record for the
# same reason they sit together: all three are records of a run and none is
# source. Left alone that is $ROOT/logs/nightly-verify, and .gitignore already
# covers logs/ whole, so no run of this gate can dirty `git status`. The
# selftest points $NIGHTLY_VERIFY_STATE at a directory it deletes on the way
# out, and the logs of its made-up checks go with it.
LOG_DIR="$(dirname "$STATE")/nightly-verify"
PASS_MAX_AGE=86400
BASE_REF="${NIGHTLY_BASE_REF:-master}"
# The selftest points this at a directory of made-up checks. Nothing else does.
CHECK_DIR="${NIGHTLY_CHECK_DIR:-$ROOT/tools}"
MODE="compare"

SKIP_BUILDS=0
SKIP_LIVE=0
REUSE=0
LANDING=0
PRINT_MODE=0
PRINT_GATE_NAME=0
NFLAGS=0
for arg in "$@"; do
    case "$arg" in
        --print-mode|--print-gate-name) ;;
        *) NFLAGS=$((NFLAGS + 1)) ;;
    esac
    case "$arg" in
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
        # --landing is the short gate a landing runs; in this phase it only
        # parses and is otherwise --compare (spec
        # docs/specs/2026-10-06-landing-gate-split-spec.md section 4).
        --landing)     MODE="compare"; LANDING=1 ;;
        --selftest)    MODE="selftest" ;;
        "")            MODE="compare" ;;
        -h|--help)     sed -n '2,16p' "$0"; exit 0 ;;
        --print-mode)  PRINT_MODE=1 ;;
        --print-gate-name) PRINT_GATE_NAME=1 ;;
        *)             echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# Flag combinations. One argument is handled by the loop above; here a lone
# --landing or --reuse-pass stands as it always did. Two arguments are accepted
# only as --landing and --reuse-pass in either order. Any other pair, any
# repeated flag, or three or more flags cannot be trusted to mean one thing.
# NFLAGS counts every argument but --print-mode.
if [ "$NFLAGS" -ge 2 ]; then
    if [ "$NFLAGS" -eq 2 ] && [ "$LANDING" = 1 ] && [ "$REUSE" = 1 ] \
        && [ "$SKIP_BUILDS" = 0 ] && [ "$SKIP_LIVE" = 0 ]; then
        :
    else
        echo "nightly_verify: these flags do not combine: $*" >&2
        exit 2
    fi
fi

# A hidden self-test hook: print the parser's verdict and leave before any
# discovery or build (tools/nightly_verify.sh --print-mode).
if [ "$PRINT_MODE" = 1 ]; then
    printf 'MODE=%s LANDING=%s REUSE=%s\n' "$MODE" "$LANDING" "$REUSE"
    exit 0
fi

# The name of the gate a run that cannot reuse a pass falls through to. With
# --landing that is the short landing gate; every other mode runs the full
# gate. Kept as one small function so the fallback line and the selftest read
# the same choice (inc-nf9h).
gate_name() {
    if [ "$LANDING" = 1 ]; then
        printf 'landing gate\n'
    else
        printf 'full gate\n'
    fi
}

# A hidden self-test hook, in the style of --print-mode: print the fallback
# gate's name and leave before any discovery or build, so the selftest can
# prove the choice without starting a real run (inc-nf9h).
if [ "$PRINT_GATE_NAME" = 1 ]; then
    gate_name
    exit 0
fi

# --------------------------------------------------------------- discovery ---
# Each entry is "<id><TAB><command><TAB><tier>". The id is what the state file
# keys on, so it holds the marker verbatim; the command is the id with @base
# expanded; the tier is what the marker said.
# Keeping them apart means NIGHTLY_BASE_REF can change without every recorded
# base silently turning into a set of checks nobody has ever measured.
#
# A check is SERIAL when the first 40 lines of its file carry a non-empty
# '# gate-serial: <reason>'. A serial check runs alone, while nothing else runs,
# because its measurement cannot tolerate a peer: it races a wall-clock
# deadline, or it writes an artefact a peer reads (the shared mod/Incursion.Mod,
# a binary, a fixed scratch path). Serial is not the same as "last": since
# inc-yg8e the serial CHEAP checks run in the cheap phase, before the builds,
# and only the serial LIVE checks run at the end. The marker lives in the check,
# not in a list here, for the same reason the tier does: a new check declares
# its own rules.
#
# CHECK_ENTRIES is every check in discovery order, serial or not, cheap before
# live. The parallel runner is given a phase's non-serial entries; the serial
# runner is given that phase's serial entries, in this same order.
CHECKS=()
SERIAL_ENTRIES=()

is_serial_file() { # <check file> -> 0 when it declares a non-empty gate-serial
    grep -Eq '^#[[:space:]]*gate-serial:[[:space:]]*[^[:space:]]' \
        <<<"$(sed -n '1,40p' "$1")"
}

discover_checks() {
    local f marker tier args id cmd serial
    local cheap=() smoke=() live=()
    SERIAL_ENTRIES=()
    LANDING_LIVE_KEPT=0
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
        serial=0
        is_serial_file "$f" && serial=1
        case "$tier" in
            cheap) cheap+=( "$id	$cmd	cheap	$serial" ) ;;
            smoke) smoke+=( "$id	$cmd	smoke	$serial" ) ;;
            live)
                # Under the landing gate only a changed live check is kept. The
                # match is the file's basename against a whole line of
                # LANDING_CHANGED, so a check can never be kept by a substring
                # of another's name. The tier is still the marker on disk.
                if [ "$LANDING" = 1 ]; then
                    local _lc _kept=0
                    while IFS= read -r _lc; do
                        [ -n "$_lc" ] || continue
                        [ "$(basename "$f")" = "$_lc" ] && _kept=1 && break
                    done <<EOF
$LANDING_CHANGED
EOF
                    if [ "$_kept" = 0 ]; then
                        continue
                    fi
                    LANDING_LIVE_KEPT=$((LANDING_LIVE_KEPT + 1))
                fi
                live+=( "$id	$cmd	live	$serial" ) ;;
            none)  ;;
            *) echo "$f: unknown gate tier '$tier' (want cheap, smoke, live or none)" >&2 ;;
        esac
        # A serial smoke or live check is still one for --docs-only's purpose:
        # it is dropped with the rest of the live tier and never reaches the
        # serial runner. Only this record decides that, so the two rules stay
        # in one place.
        if [ "$SKIP_LIVE" = 1 ] && { [ "$tier" = live ] || [ "$tier" = smoke ]; }; then
            continue
        fi
        if [ "$serial" = 1 ]; then
            SERIAL_ENTRIES+=( "$id	$cmd	$tier	$serial" )
        fi
    done
    # Cheap first, so a reader watching the output sees the seconds before the
    # minutes. Within a tier the glob's order is alphabetical and stable.
    if [ "$SKIP_LIVE" = 1 ]; then
        CHECKS=( ${cheap[@]+"${cheap[@]}"} )
    else
        CHECKS=( ${cheap[@]+"${cheap[@]}"} ${smoke[@]+"${smoke[@]}"} ${live[@]+"${live[@]}"} )
    fi
}

# phase_entries <tier> -> the non-serial entries of a tier, in discovery order.
# Used to hand the parallel runner one phase at a time.
PHASE_ENTRIES=()
phase_entries() { # <tier>
    local tier="$1" e et
    PHASE_ENTRIES=()
    for e in "${CHECKS[@]}"; do
        et="${e#*	}"; et="${et#*	}"; et="${et%%	*}"
        [ "$et" = "$tier" ] || continue
        [ "${e##*	}" = 0 ] || continue
        PHASE_ENTRIES+=( "$e" )
    done
}

# serial_phase_entries <tier> -> the SERIAL entries of a tier, in discovery
# order. The mirror of phase_entries for the alone-runner. The serial set is
# split by tier too (inc-yg8e): the serial CHEAP checks run before the builds,
# beside the parallel cheap tier, and only the serial LIVE checks wait for the
# binary at the end.
SERIAL_PHASE_ENTRIES=()
serial_phase_entries() { # <tier>
    local tier="$1" e et
    SERIAL_PHASE_ENTRIES=()
    for e in ${SERIAL_ENTRIES[@]+"${SERIAL_ENTRIES[@]}"}; do
        et="${e#*	}"; et="${et#*	}"; et="${et%%	*}"
        [ "$et" = "$tier" ] || continue
        SERIAL_PHASE_ENTRIES+=( "$e" )
    done
}

# check_log_path "<check id>" -> the one file that check's output goes to.
#
# A check id is a command line, not a name: it holds '/', spaces and '--flags',
# as in "tools/check_doc_citations.sh --base master". Every character outside
# [A-Za-z0-9._-] becomes '_', so no '/' survives to make a directory of its own
# and nothing in an id can steer the write anywhere but $LOG_DIR. A name that
# would start with a dot is prefixed instead of trimmed, which stops '..' from
# meaning the parent directory and stops a log from hiding from `ls`.
check_log_path() {
    local name="${1//[^A-Za-z0-9._-]/_}"
    case "$name" in ''|.*) name="check_$name" ;; esac
    printf '%s/%s.log' "$LOG_DIR" "$name"
}

# run_check "<check id>" "<command line>" -> echoes the exit code, and leaves
# everything the check said in check_log_path "<check id>".
#
# WHY THE OUTPUT IS KEPT. It used to go to /dev/null. On 2026-09-16
# tools/check_doc_citations.sh failed inside the gate, passed on three re-runs
# by hand, and left not one word behind to read: the verdict line named the
# check, the exit code and nothing else, and the only recourse anybody had was
# to run the check again and watch it pass (inc-9diw). A check that takes 77
# seconds and fails once in some unknown number of runs cannot be studied that
# way. The run that failed has to keep its own words, because it is the only
# run that has anything to say.
#
# A PASSING CHECK KEEPS ITS LOG TOO. It is one code path instead of a
# delete-when-green branch that could only ever delete the wrong file, the
# files are small, and $LOG_DIR is ignored by git. It is also the half of
# inc-9diw that is easy to forget: a flake is diagnosed by reading the run that
# failed NEXT TO the run that passed, and the gate records both.
#
# THE LOG IS A DIAGNOSTIC AND NEVER A VERDICT. A redirection that cannot open
# its file takes the command's exit status with it, so an unwritable logs/
# would report a green check as a failure. This proves the file first and falls
# back to /dev/null -- the behaviour of every run before this one -- rather than
# let the gate's answer depend on a directory.
run_check() {
    local log rc timefile
    log="$(check_log_path "$1")"
    mkdir -p "$LOG_DIR" 2> /dev/null
    ( : > "$log" ) 2> /dev/null || log="/dev/null"
    # $LOG_DIR holds the last run of every check, and a mode that drops a tier
    # leaves the previous run's file sitting there untouched. The header is how
    # a reader tells this morning's log from last week's.
    printf '=== check:   %s\n=== command: %s\n=== started: %s\n\n' \
        "$1" "$2" "$(date '+%Y-%m-%d %H:%M:%S %Z')" >> "$log" 2> /dev/null
    # The CPU time (user + sys, this check and its children) is what the slow
    # cheap note judges for a PARALLEL check: its wall-clock is shared with
    # fifty peers, so wall-clock blames the machine and CPU time blames the
    # check. /usr/bin/time writes the time file and returns the command's exit
    # status. No time file when the log fell back to /dev/null or /usr/bin/time
    # is not there: the note falls back to wall-clock.
    timefile="${log}.time"
    if [ "$log" != "/dev/null" ] && [ -x /usr/bin/time ]; then
        rm -f "$timefile" 2> /dev/null
        /usr/bin/time -p -o "$timefile" bash -c "$2" >> "$log" 2>&1
    else
        ( eval "$2" ) >> "$log" 2>&1
    fi
    rc=$?
    printf '\n=== exit %s\n' "$rc" >> "$log" 2> /dev/null
    echo "$rc"
}

# cpu_seconds "<time file>": the integer sum of the file's user and sys lines,
# rounded up, or nothing when the file is missing or unparseable. The parallel
# runner asks this of each cheap check; an empty answer makes print_verdict
# fall back to the wall-clock rule.
cpu_seconds() {
    awk '
        /^user / { u = $2 + 0; got = 1 }
        /^sys /  { s = $2 + 0; got = 1 }
        END {
            if (!got) exit 0
            t = u + s
            n = int(t)
            if (t > n) n = n + 1
            print n
        }
    ' "$1" 2> /dev/null
}

# show_log "<check id>" <lines>: say where that check's output went, and show
# the end of it when <lines> is more than zero.
#
# Only the verdicts that STOP THE MERGE get the tail. This gate carries a
# backlog of checks that were already red before the run -- that is the whole
# reason it ratchets -- and thirty tails would bury the one verdict a reader
# has to act on. A pre-existing red still gets its path, because the file is
# there and somebody draining the backlog wants it.
show_log() {
    local log
    log="$(check_log_path "$1")"
    [ -s "$log" ] || return 0
    printf '            output: %s\n' "$log"
    [ "${2:-0}" -gt 0 ] || return 0
    tail -n "$2" "$log" | sed 's/^/            | /'
}

# ------------------------------------------------------------ the verdicts ---
# print_verdict "<check id>" <now-exit> <elapsed-seconds> <tier> <serial 0|1>
# <cpu-seconds-or-empty>: turn one check's exit code into the line this gate has
# always printed, and set FAILED when that line stops the merge. The last two
# arguments decide the slow-cheap note (spec §6): a serial check is judged by
# its wall-clock, a parallel one by its CPU time when known and its wall-clock
# otherwise. Extracted from the old serial loop so the parallel runner, the
# serial runner and --record all reach one definition of the table and cannot
# drift.
#
# FAILED is the caller's global, as it always was.
print_verdict() {
    local id="$1" now="$2" elapsed="$3" tier="$4" serial="$5" cpu="$6" was=""
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
            show_log "$id" 15
            FAILED=1
        else
            printf 'unmeasured  %s (exit 2 before and after -- not this run)\n' "$id"
            show_log "$id" 0
        fi
    elif [ "$was" != "0" ] && [ "$was" != "2" ]; then
        printf 'pre-existing %s (exit %s now, exit %s before -- not this run)\n' "$id" "$now" "$was"
        show_log "$id" 0
    else
        printf 'BROKEN      %s (exit %s; it %s before this run)\n' "$id" "$now" \
            "$([ "$was" = 2 ] && echo "could not be measured" || echo "passed")"
        show_log "$id" 15
        FAILED=1
    fi
    # The cheap tier's whole promise is that it costs seconds, and a check that
    # quietly stops keeping it is how a gate becomes something people skip.
    # A SERIAL check runs alone, so its wall-clock is its own cost and judges
    # it. A PARALLEL check shares the machine with its peers, so only its CPU
    # time blames the check; with no CPU time to read, wall-clock is the
    # fallback (spec §6). The serial/wall-clock limit is ${NIGHTLY_CHEAP_LIMIT:-30};
    # the parallel CPU rule has its own limit ${NIGHTLY_CHEAP_CPU_LIMIT:-45}.
    local limit="${NIGHTLY_CHEAP_LIMIT:-30}"
    local cpu_limit="${NIGHTLY_CHEAP_CPU_LIMIT:-45}"
    if [ "$tier" = "cheap" ]; then
        if [ "$serial" = "1" ]; then
            if [ "$elapsed" -gt "$limit" ]; then
                printf '            note: %ss. A cheap check should cost seconds --\n' "$elapsed"
                printf '            mark it "# gate: live" or "# gate: none <why>".\n'
            fi
        elif [ -n "$cpu" ]; then
            if [ "$cpu" -gt "$cpu_limit" ]; then
                printf '            note: %ss of CPU. A cheap check should cost seconds --\n' "$cpu"
                printf '            mark it "# gate: live" or "# gate: none <why>".\n'
            fi
        elif [ "$elapsed" -gt "$limit" ]; then
            printf '            note: %ss. A cheap check should cost seconds --\n' "$elapsed"
            printf '            mark it "# gate: live" or "# gate: none <why>".\n'
        fi
    fi
}

# ------------------------------------------------------- the parallel runner ---
# HOW MANY AT ONCE. INCURSION_GATE_JOBS if set, otherwise the machine's core
# count minus two (two left for the background steps and whatever else the
# machine is doing), never below one. On Linux nproc, on macOS sysctl.
gate_jobs() {
    local n
    if [ -n "${INCURSION_GATE_JOBS:-}" ]; then
        n="${INCURSION_GATE_JOBS}"
    else
        if command -v nproc > /dev/null 2>&1; then
            n="$(nproc)"
        else
            n="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"
        fi
        n=$((n - 2))
    fi
    case "$n" in ''|*[!0-9]*) n=1 ;; esac
    [ "$n" -lt 1 ] && n=1
    printf '%s' "$n"
}

# announce_jobs: say the worker count once per run, the first time a parallel
# phase is reached. Nothing else prints it, so a reader sees one number.
JOBS_PRINTED=0
announce_jobs() {
    [ "$JOBS_PRINTED" = 1 ] && return 0
    JOBS_PRINTED=1
    echo "--- checks run $(gate_jobs) at a time (INCURSION_GATE_JOBS; default is cores minus 2) ---"
}

# The background jobs a phased run may have started: the parallel runner's
# workers and the three background steps. The trap kills them all on an
# interrupt so Ctrl-C leaves nothing running.
GATE_WORKERS=""
GATE_STEPS=""
#
# KILLING A WORKER IS NOT ENOUGH. A worker is a subshell running run_check,
# which evals the check; the check is the worker's CHILD, and a check that runs
# a headless session has grandchildren below that. TERM to the worker (or even
# KILL) does not reach them, so an interrupted run would leave a `sleep 60` or
# a game session behind. There is no job control in a non-interactive script
# (each background job shares the gate's process group, so signalling the group
# would signal the gate itself), and macOS has no setsid. So descend: collect
# the whole tree under each tracked worker/step pid, then signal every level.
descendants() { # <pid> -> its descendants, one per line, deepest last
    local pid="$1" c
    for c in $(pgrep -P "$pid" 2>/dev/null); do
        descendants "$c"
        printf '%s\n' "$c"
    done
}
kill_gate_jobs() {
    local p tree=""
    for p in $GATE_WORKERS $GATE_STEPS; do
        tree="$tree $(descendants "$p")"
    done
    for p in $tree $GATE_WORKERS $GATE_STEPS; do
        kill "$p" 2>/dev/null
    done
    sleep 0.3
    for p in $tree $GATE_WORKERS $GATE_STEPS; do
        kill -KILL "$p" 2>/dev/null
    done
}
STEP_TRAP=0
arm_gate_trap() {
    [ "$STEP_TRAP" = 1 ] && return 0
    STEP_TRAP=1
    trap 'kill_gate_jobs' INT TERM
}

# live_count <pid...>: how many of these pids are still running. The throttle
# must count only THIS phase's workers, never all shell jobs: the three big
# steps are background jobs too, and counting them would starve the live tier
# (with INCURSION_GATE_JOBS=1 and three steps, jobs -rp alone would deadlock).
live_count() {
    local p n=0
    for p in "$@"; do
        kill -0 "$p" 2>/dev/null && n=$((n + 1))
    done
    printf '%s' "$n"
}

# run_phase_parallel <tier>: run that tier's non-serial checks through the
# parallel runner, then print their verdicts in discovery order. Jobs are
# subshells that each call run_check (so each check keeps its own log) and
# write their exit code and elapsed seconds to a private file. Throttling polls
# the live worker count with a short sleep; bash 3.2 has no wait -n.
run_phase_parallel() {
    local tier="$1"
    phase_entries "$tier"
    [ "${#PHASE_ENTRIES[@]}" -gt 0 ] || return 0
    arm_gate_trap
    announce_jobs

    local jobs resdir idx entry id cmd rc elapsed cpu pids
    jobs="$(gate_jobs)"
    resdir="$(mktemp -d "${TMPDIR:-/tmp}/nvjobs.XXXXXX")" || { echo "could not make a job dir" >&2; return 2; }
    # A private mktemp dir per phase, so two phases cannot collide and nothing
    # outside $TMPDIR is written.

    idx=0
    pids=""
    for entry in "${PHASE_ENTRIES[@]}"; do
        idx=$((idx + 1))
        id="${entry%%	*}"; entry="${entry#*	}"
        cmd="${entry%%	*}"
        # Throttle: at most $jobs workers of THIS phase running. Only the
        # pids this phase launched are counted, so the background steps beside
        # the live phase cannot inflate the count.
        while [ "$(live_count $pids)" -ge "$jobs" ]; do
            sleep 0.2
        done
        (
            started=$SECONDS
            r="$(run_check "$id" "$cmd")"
            printf '%s\n' "$r" > "$resdir/$idx.rc"
            printf '%s\n' "$((SECONDS - started))" > "$resdir/$idx.elapsed"
        ) &
        pids="$pids $!"
        GATE_WORKERS="$GATE_WORKERS $!"
    done
    # Wait on THIS phase's workers by pid, never bare `wait`: a bare wait would
    # also reap the background steps running beside the live phase, and a second
    # wait on an already-reaped pid is an error the step verdicts would read as
    # FAILED.
    for worker in $pids; do
        wait "$worker"
    done

    # Results in discovery order, after the phase's jobs finish: deterministic
    # output however the workers interleaved. entry is "<id>\t<cmd>\t<tier>\t<serial>",
    # so the tier is what remains after stripping id and cmd.
    idx=0
    for entry in "${PHASE_ENTRIES[@]}"; do
        idx=$((idx + 1))
        id="${entry%%	*}"; entry="${entry#*	}"; entry="${entry#*	}"; tier="${entry%%	*}"
        rc="$(cat "$resdir/$idx.rc" 2>/dev/null)"
        [ -n "$rc" ] || rc=2
        elapsed="$(cat "$resdir/$idx.elapsed" 2>/dev/null)"
        [ -n "$elapsed" ] || elapsed=0
        # This parallel check's own CPU time, from the time file run_check left
        # beside its log. Empty when there is none: the note then falls back to
        # wall-clock.
        cpu="$(cpu_seconds "$(check_log_path "$id").time")"
        print_verdict "$id" "$rc" "$elapsed" "$tier" 0 "$cpu"
    done
    rm -rf "$resdir"
    GATE_WORKERS=""
    return 0
}

# run_phase_serial <tier>: run that tier's serial checks one at a time, nothing
# else running, in discovery order, and print their verdicts. Uses run_check
# directly, as the old loop did. The tier split (inc-yg8e) lets the serial
# cheap checks run beside the parallel cheap tier, before the builds, and keeps
# only the serial live checks at the end where the binary is ready.
run_phase_serial() {
    local tier="$1"
    serial_phase_entries "$tier"
    [ "${#SERIAL_PHASE_ENTRIES[@]}" -gt 0 ] || return 0
    local entry id cmd et started elapsed now
    for entry in "${SERIAL_PHASE_ENTRIES[@]}"; do
        id="${entry%%	*}"; entry="${entry#*	}"
        cmd="${entry%%	*}"; entry="${entry#*	}"
        et="${entry%%	*}"
        started=$SECONDS
        now="$(run_check "$id" "$cmd")"
        elapsed=$((SECONDS - started))
        # A serial check runs alone, so its wall-clock is its own cost and the
        # note judges that. No CPU time is passed.
        print_verdict "$id" "$now" "$elapsed" "$et" 1 ""
    done
    return 0
}

# ---------------------------------------------------- the three big steps ---
# The Linux cross-build, the layout sweep and the soak. Their own steps, not
# ratcheted checks, because each has three exit codes and each needs a build.
# They run in the BACKGROUND, beside the live tier, because they are minutes
# long and the live tier is independent of them; each writes its output to its
# own file under $LOG_DIR so a red one can be read after the fact. Their ok /
# SKIPPED / FAILED wording and exit-code meaning (0 ok, 2 skipped, else FAILED)
# are exactly what the old serial loop printed.
#
# STEPS entries are "<command><TAB><what to run by hand when it goes red>".
STEPS=(
    "tools/check_linux_build.sh	tools/check_linux_build.sh"
    "tools/check_layout_sweep.sh	tools/check_layout_sweep.sh --no-build"
    "tools/gate_compare.sh	tools/gate_compare.sh --from <the run it kept>"
)

# The soak only; spec §4.2. A landing runs this and nothing else.
LANDING_STEPS=(
    "tools/gate_compare.sh	tools/gate_compare.sh --from <the run it kept>"
)

# The selftest points this at a file of made-up steps, one "<command><TAB><hint>"
# per line. Only the selftest sets it, like $NIGHTLY_CHECK_DIR. Unset, nothing
# changes.
if [ -n "${NIGHTLY_STEPS_FILE:-}" ] && [ -r "$NIGHTLY_STEPS_FILE" ]; then
    STEPS=()
    while IFS= read -r _step_line; do
        [ -n "$_step_line" ] && STEPS+=( "$_step_line" )
    done < "$NIGHTLY_STEPS_FILE"
    unset _step_line
fi

# The selftest sets only $NIGHTLY_CHECK_DIR; it must never run a real step.
if [ -n "${NIGHTLY_CHECK_DIR:-}" ] && [ -z "${NIGHTLY_STEPS_FILE:-}" ]; then
    STEPS=()
    LANDING_STEPS=()
fi

# An array of "<pid><TAB><name><TAB><rerun>" for the steps now running.
STEP_PIDS=()

step_log_path() { # <command> -> a per-step log beside the check logs
    local name
    name="$(basename "${1%% *}")"
    name="${name%.sh}"
    printf '%s/step_%s.log' "$LOG_DIR" "$name"
}

start_background_steps() { # <array name>
    arm_gate_trap
    local name="$1" step cmd rerun log
    local list=()
    eval 'list=( ${'"$name"'[@]+"${'"$name"'[@]}"} )'
    mkdir -p "$LOG_DIR" 2> /dev/null
    STEP_PIDS=()
    for step in ${list[@]+"${list[@]}"}; do
        cmd="${step%%	*}"
        rerun="${step#*	}"
        log="$(step_log_path "$cmd")"
        ( eval "$cmd" ) > "$log" 2>&1 &
        STEP_PIDS+=( "$!	${cmd%% *}	$rerun" )
        GATE_STEPS="$GATE_STEPS $!"
    done
}

wait_background_steps() {
    local entry pid name rerun rc
    for entry in ${STEP_PIDS[@]+"${STEP_PIDS[@]}"}; do
        pid="${entry%%	*}"; entry="${entry#*	}"
        name="${entry%%	*}"; rerun="${entry#*	}"
        wait "$pid"
        rc=$?
        printf '%s ... ' "$name"
        case "$rc" in
            0) echo "ok" ;;
            2) echo "SKIPPED (could not measure)" ;;
            *) echo "FAILED"
               echo "    re-run it to see why: $rerun"
               FAILED=1 ;;
        esac
    done
    STEP_PIDS=()
    GATE_STEPS=""
}

# A check id is a command line, not a name (see check_log_path). For the record
# driver's per-check rc files the same sanitising rule gives a unique flat name.
id_file_stem() { # <id> -> one path component
    local name="${1//[^A-Za-z0-9._-]/_}"
    case "$name" in ''|.*) name="check_$name" ;; esac
    printf '%s' "$name"
}

# collect_phase_parallel <tier> <resdir>: run that tier's non-serial checks
# through the parallel runner, writing each check's exit code and elapsed
# seconds into <resdir>. No verdicts are printed; the record driver reads the
# files back in discovery order.
collect_phase_parallel() {
    local tier="$1" resdir="$2"
    phase_entries "$tier"
    [ "${#PHASE_ENTRIES[@]}" -gt 0 ] || return 0
    arm_gate_trap
    local jobs idx entry id cmd stem pids
    announce_jobs
    jobs="$(gate_jobs)"
    idx=0
    pids=""
    for entry in "${PHASE_ENTRIES[@]}"; do
        idx=$((idx + 1))
        id="${entry%%	*}"; entry="${entry#*	}"
        cmd="${entry%%	*}"
        stem="$(id_file_stem "$id")"
        while [ "$(live_count $pids)" -ge "$jobs" ]; do
            sleep 0.2
        done
        (
            started=$SECONDS
            r="$(run_check "$id" "$cmd")"
            printf '%s\n' "$r" > "$resdir/$stem.rc"
            printf '%s\n' "$((SECONDS - started))" > "$resdir/$stem.elapsed"
        ) &
        pids="$pids $!"
        GATE_WORKERS="$GATE_WORKERS $!"
    done
    for worker in $pids; do
        wait "$worker"
    done
    GATE_WORKERS=""
}

# collect_serial <tier> <resdir>: run that tier's serial checks alone, writing
# its rc and elapsed into <resdir>, in discovery order. Split by tier so the
# record driver can mirror the compare order: serial cheap after parallel cheap,
# serial live at the very end (inc-yg8e). The state file still comes out in
# discovery order, because the driver reads every rc back from <resdir>.
collect_serial() {
    local tier="$1" resdir="$2" entry id cmd stem started now
    serial_phase_entries "$tier"
    for entry in ${SERIAL_PHASE_ENTRIES[@]+"${SERIAL_PHASE_ENTRIES[@]}"}; do
        id="${entry%%	*}"; entry="${entry#*	}"
        cmd="${entry%%	*}"
        stem="$(id_file_stem "$id")"
        started=$SECONDS
        now="$(run_check "$id" "$cmd")"
        printf '%s\n' "$now" > "$resdir/$stem.rc"
        printf '%s\n' "$((SECONDS - started))" > "$resdir/$stem.elapsed"
    done
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
    local tree base envh rtree rbase renv rtime age rmode want
    [ -e "$PASS_RECORD" ] || { echo "no full pass on record"; return 1; }
    [ -r "$PASS_RECORD" ] || { echo "the pass record cannot be read"; return 1; }
    rtree="$(record_field tree)"; rbase="$(record_field base)"
    renv="$(record_field env)";   rtime="$(record_field time)"
    rmode="$(record_field mode)"
    if [ "$LANDING" = 1 ]; then want="landing"; else want="full"; fi
    # At most 12 digits, so the age below cannot overflow into a match.
    case "$rtime" in ''|*[!0-9]*|?????????????*)
        echo "the pass record is malformed"; return 1 ;;
    esac
    if [ -z "$rtree" ] || [ -z "$rbase" ] || [ -z "$renv" ] || [ -z "$rmode" ]; then
        echo "the pass record is malformed"; return 1
    fi
    if [ "$rmode" != "$want" ]; then
        echo "the pass record is from the $rmode gate, not the $want gate"; return 1
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
    echo "a $rmode pass at $(record_field when): tree $tree, base $base, env $envh"
    return 0
}

# write_pass_record <tree> <base> <env>. A record that cannot be written costs
# one full run at the landing and nothing else, so it warns and does not fail.
write_pass_record() {
    local tmp="$PASS_RECORD.tmp.$$"
    mkdir -p "$(dirname "$PASS_RECORD")" 2> /dev/null
    if {
        echo "# A tools/nightly_verify.sh gate passed on these files (inc-689z)."
        echo "# A record of a run, not source: never commit it."
        if [ "$LANDING" = 1 ]; then
            printf 'mode landing\n'
        else
            printf 'mode full\n'
        fi
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

    # Each made-up check says one recognisable sentence before it exits, so the
    # selftest can prove the gate KEPT the words of a check that failed and not
    # merely that it wrote a file. That is the half inc-9diw was missing.
    _mk() { # _mk <name> <exit-code-when-BEFORE-is-set> <exit-code-otherwise>
        printf '#!/bin/sh\n# gate: cheap\necho "check_%s said this and the gate must keep it"\n[ -n "${BEFORE:-}" ] && exit %s\nexit %s\n' \
            "$1" "$2" "$3" > "$dir/check_$1.sh"
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
        if grep -Eq "$2" <<<"$out"; then
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

    # ---- the output a BROKEN verdict leaves behind (inc-9diw) --------------
    # The verdict must name the file, and the file must hold what the check
    # said. Before 2026-09-16 it held nothing, because run_check sent every
    # check's stdout and stderr to /dev/null.
    _want 'a BROKEN verdict names the file holding the output' \
          '^ +output: .*tools_check_broke\.sh\.log$'
    _want 'a pre-existing red names its file too' \
          '^ +output: .*tools_check_red\.sh\.log$'

    local broke_log="$dir/nightly-verify/tools_check_broke.sh.log"
    if grep -q 'check_broke said this and the gate must keep it' "$broke_log" 2> /dev/null; then
        printf '  ok    the log of a failing check holds what the check said\n'
    else
        printf '  FAIL  %s does not hold the failing check.s own words\n' "$broke_log"
        fails=$((fails + 1))
    fi
    if grep -q 'check_green said this and the gate must keep it' \
        "$dir/nightly-verify/tools_check_green.sh.log" 2> /dev/null; then
        printf '  ok    a passing check keeps its log, to compare against a failing one\n'
    else
        printf '  FAIL  a passing check left no log to compare a flake against\n'
        fails=$((fails + 1))
    fi

    # ---- the log path cannot leave its directory --------------------------
    # A check id is a command line: "tools/check_doc_citations.sh --base
    # master" carries a '/', two spaces and a '--flag'. A name built from one
    # must not make a directory, climb out of $LOG_DIR, or hide from `ls`.
    _path() { # _path <check id> <the one file name it may produce>
        local got
        got="$(check_log_path "$1")"
        if [ "$got" = "$LOG_DIR/$2" ]; then
            printf '  ok    a check id stays one file in one directory: %s\n' "$2"
        else
            printf '  FAIL  check_log_path "%s"\n      wanted %s\n      got    %s\n' \
                "$1" "$LOG_DIR/$2" "$got"
            fails=$((fails + 1))
        fi
    }
    _path 'tools/check_doc_citations.sh --base master' \
          'tools_check_doc_citations.sh_--base_master.log'
    _path '../../etc/passwd' 'check_.._.._etc_passwd.log'
    _path '..'               'check_...log'

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

    # ---- the cheap tier stops the run before the builds (inc-yg8e) ---------
    # A cheap check that breaks must stop at once: the STOPPED line, exit 1, and
    # the live check must NOT have run (its marker file stays absent). This is
    # the whole reason the cheap tier moved first.
    _run_case_cheap_stop() {
        local d="$dir/cheapstop" out rc marker
        mkdir -p "$d"
        marker="$d/live-touched"
        printf '#!/bin/sh\n# gate: cheap\nexit 1\n' > "$d/check_aa_break.sh"
        printf '#!/bin/sh\n# gate: live\ntouch "%s"\nexit 0\n' "$marker" > "$d/check_bb_live.sh"
        chmod +x "$d/check_aa_break.sh" "$d/check_bb_live.sh"
        out="$(NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --checks-only 2>&1)"
        rc=$?
        if grep -q '^=== STOPPED: the cheap tier broke a check; the builds and the live tier were not run ===' <<<"$out" \
            && [ "$rc" = 1 ] && [ ! -e "$marker" ]; then
            printf '  ok    a broken cheap check stops before the builds and the live tier\n'
        else
            printf '  FAIL  cheap-tier stop: rc=%s marker=%s\n' "$rc" \
                "$([ -e "$marker" ] && echo present || echo absent)"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
    }
    _run_case_cheap_stop

    # ---- a SERIAL cheap check stops the run too (inc-yg8e) -----------------
    # The serial cheap checks run in the cheap phase, beside the parallel cheap
    # ones and before the builds. A serial cheap check that breaks must produce
    # the same STOPPED line, exit 1, and must stop the run before the live tier
    # (the live check's marker file stays absent). Before the split it ran at the
    # very end, so a break it found could only report after the builds.
    _run_case_serial_cheap_stop() {
        local d="$dir/serialcheapstop" out rc marker
        mkdir -p "$d"
        marker="$d/live-touched"
        printf '#!/bin/sh\n# gate: cheap\n# gate-serial: runs alone\nexit 1\n' \
            > "$d/check_aa_break.sh"
        printf '#!/bin/sh\n# gate: live\ntouch "%s"\nexit 0\n' "$marker" \
            > "$d/check_bb_live.sh"
        chmod +x "$d/check_aa_break.sh" "$d/check_bb_live.sh"
        out="$(NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --checks-only 2>&1)"
        rc=$?
        if grep -q '^=== STOPPED: the cheap tier broke a check; the builds and the live tier were not run ===' <<<"$out" \
            && [ "$rc" = 1 ] && [ ! -e "$marker" ]; then
            printf '  ok    a broken SERIAL cheap check stops before the live tier too\n'
        else
            printf '  FAIL  serial cheap-tier stop: rc=%s marker=%s\n' "$rc" \
                "$([ -e "$marker" ] && echo present || echo absent)"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
    }
    _run_case_serial_cheap_stop

    # ---- a smoke check runs like a live one, and --docs-only drops it --------
    # smoke "plays the game briefly": in a full run it behaves exactly like a
    # live check, and --docs-only drops it as it drops live. A made-up smoke
    # check touches a marker: --checks-only must run it and leave the marker;
    # --docs-only must not.
    _run_case_smoke_tier() {
        local d="$dir/smoke" out rc marker
        mkdir -p "$d"
        marker="$d/smoke-touched"
        printf '#!/bin/sh\n# gate: smoke\ntouch "%s"\nexit 0\n' "$marker" \
            > "$d/check_aa_smoke.sh"
        # A cheap check keeps the set non-empty so --docs-only is a valid run
        # (an empty set exits 2); the smoke marker is what proves smoke ran.
        printf '#!/bin/sh\n# gate: cheap\nexit 0\n' > "$d/check_bb_cheap.sh"
        chmod +x "$d/check_aa_smoke.sh" "$d/check_bb_cheap.sh"
        out="$(NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --checks-only 2>&1)"
        rc=$?
        if [ "$rc" = 0 ] && [ -e "$marker" ]; then
            printf '  ok    a smoke check runs under --checks-only\n'
        else
            printf '  FAIL  smoke under --checks-only: rc=%s marker=%s\n' "$rc" \
                "$([ -e "$marker" ] && echo present || echo absent)"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
        rm -f "$marker"
        out="$(NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --docs-only 2>&1)"
        rc=$?
        if [ "$rc" = 0 ] && [ ! -e "$marker" ]; then
            printf '  ok    --docs-only drops the smoke tier\n'
        else
            printf '  FAIL  --docs-only ran the smoke tier: rc=%s marker=%s\n' "$rc" \
                "$([ -e "$marker" ] && echo present || echo absent)"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
    }
    _run_case_smoke_tier

    # ---- --record runs every step and records each one's code -------------
    # The real steps need the binary, so the selftest fakes the step list with
    # $NIGHTLY_STEPS_FILE: --record must run each entry in order and append one
    # "<rc><TAB><id>" line per step beside the check lines. One step exits 0 and
    # one exits 1; the record must hold both, and must exit 0 regardless.
    _run_case_record_steps() {
        local d="$dir/recordsteps" out rc state
        mkdir -p "$d"
        state="$d/base.txt"
        printf '#!/bin/sh\n# gate: cheap\nexit 0\n' > "$d/check_aa_cheap.sh"
        chmod +x "$d/check_aa_cheap.sh"
        printf '#!/bin/sh\nexit 0\n' > "$d/step_ok.sh"
        printf '#!/bin/sh\nexit 1\n' > "$d/step_bad.sh"
        chmod +x "$d/step_ok.sh" "$d/step_bad.sh"
        printf '%s\t%s\n' "$d/step_ok.sh" "$d/step_ok.sh" > "$d/steps.txt"
        printf '%s\t%s\n' "$d/step_bad.sh" "$d/step_bad.sh" >> "$d/steps.txt"
        out="$(NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$state" \
            NIGHTLY_STEPS_FILE="$d/steps.txt" "$0" --record 2>&1)"
        rc=$?
        if [ "$rc" = 0 ] \
            && grep -q "$(printf '0\ttools/check_aa_cheap.sh')" "$state" \
            && grep -q "$(printf '0\t%s/step_ok.sh' "$d")" "$state" \
            && grep -q "$(printf '1\t%s/step_bad.sh' "$d")" "$state"; then
            printf '  ok    --record runs every step and records each code\n'
        else
            printf '  FAIL  --record steps: rc=%s state=%s\n' "$rc" \
                "$(tr '\n' '|' < "$state" 2>/dev/null)"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
    }
    _run_case_record_steps

    # ---- a step command with a space argument survives the array copy -----
    # The step list is copied by name inside start_background_steps; a command
    # with spaces must stay one word in the command and its argument must reach
    # the script intact. The script writes "$1" so an argument destroyed by the
    # copy is visible as the wrong file contents.
    _run_case_landing_steps_copy() {
        local d="$dir/stepcopy" out rc state
        mkdir -p "$d"
        state="$d/base.txt"
        printf '#!/bin/sh\n# gate: cheap\nexit 0\n' > "$d/check_aa_cheap.sh"
        chmod +x "$d/check_aa_cheap.sh"
        printf '#!/bin/sh\nprintf %%s "$1" > "$2"\n' > "$d/step_ok.sh"
        chmod +x "$d/step_ok.sh"
        printf '%s\t%s\n' "$d/step_ok.sh one-arg $d/got.txt" \
            "$d/step_ok.sh --from <the run it kept>" > "$d/steps.txt"
        out="$(NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$state" \
            NIGHTLY_STEPS_FILE="$d/steps.txt" "$0" --record 2>&1)"
        rc=$?
        if [ "$rc" = 0 ] && [ "$(cat "$d/got.txt" 2>/dev/null)" = one-arg ]; then
            printf '  ok    a step command with a space argument survives the copy\n'
        else
            printf '  FAIL  step copy: rc=%s got=%s\n' "$rc" \
                "$(cat "$d/got.txt" 2>/dev/null)"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
    }
    _run_case_landing_steps_copy

    # ---- the reuse fallback names the gate it actually runs (inc-nf9h) ----
    # Since the landing split the fallback line said "Running the full gate."
    # even under --landing, which runs the landing gate. The gate-name choice
    # lives in gate_name(), reachable through the hidden --print-gate-name hook
    # in the style of --print-mode: this proves the choice without starting a
    # build or a game session.
    _run_case_reuse_fallback_name() {
        local d out
        d="$dir/fallbackname"; mkdir -p "$d"
        out="$(NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --print-gate-name --landing 2>&1)"
        if [ "$out" = "landing gate" ]; then
            printf '  ok    the reuse fallback names the landing gate under --landing\n'
        else
            printf '  FAIL  --landing fallback gate name: %s\n' "$out"
            fails=$((fails + 1))
        fi
        out="$(NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --print-gate-name 2>&1)"
        if [ "$out" = "full gate" ]; then
            printf '  ok    the reuse fallback names the full gate otherwise\n'
        else
            printf '  FAIL  default fallback gate name: %s\n' "$out"
            fails=$((fails + 1))
        fi
    }
    _run_case_reuse_fallback_name

    # ---- the flags combine only as the landing says they may --------------
    # --landing combines with --reuse-pass and nothing else. The two accepted
    # orders must leave the parser at MODE=compare LANDING=1 REUSE=1; every
    # other pair, and any unknown flag, must exit 2. The accepted pair is
    # checked through the hidden --print-mode hook, which leaves before any
    # discovery or build: a made-up dir has no live or smoke check, but proving
    # that no build starts without a stub is more than this test needs, so it
    # reads the parser's own verdict instead.
    _run_case_flag_combos() {
        local d out rc
        d="$dir/flagcombos"; mkdir -p "$d"
        printf '#!/bin/sh\n# gate: cheap\nexit 0\n' > "$d/check_only.sh"
        chmod +x "$d/check_only.sh"

        out="$(NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --print-mode --landing --reuse-pass 2>&1)"
        if [ "$out" = "MODE=compare LANDING=1 REUSE=1" ]; then
            printf '  ok    --landing --reuse-pass parses to MODE=compare LANDING=1 REUSE=1\n'
        else
            printf '  FAIL  --landing --reuse-pass parsed to: %s\n' "$out"
            fails=$((fails + 1))
        fi

        out="$(NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --print-mode --reuse-pass --landing 2>&1)"
        if [ "$out" = "MODE=compare LANDING=1 REUSE=1" ]; then
            printf '  ok    --reuse-pass --landing parses to the same\n'
        else
            printf '  FAIL  --reuse-pass --landing parsed to: %s\n' "$out"
            fails=$((fails + 1))
        fi

        NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --landing --docs-only > /dev/null 2>&1
        rc=$?
        if [ "$rc" = 2 ]; then
            printf '  ok    --landing --docs-only exits 2\n'
        else
            printf '  FAIL  --landing --docs-only exited %s\n' "$rc"
            fails=$((fails + 1))
        fi

        out="$(NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --print-mode --landing --docs-only 2>/dev/null)"
        rc=$?
        if [ "$rc" = 2 ] && [ -z "$out" ]; then
            printf '  ok    --print-mode --landing --docs-only exits 2 and prints nothing\n'
        else
            printf '  FAIL  --print-mode --landing --docs-only exited %s and printed: %s\n' "$rc" "$out"
            fails=$((fails + 1))
        fi

        NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --compare --compare > /dev/null 2>&1
        rc=$?
        if [ "$rc" = 2 ]; then
            printf '  ok    --compare --compare exits 2\n'
        else
            printf '  FAIL  --compare --compare exited %s\n' "$rc"
            fails=$((fails + 1))
        fi

        NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --bogus > /dev/null 2>&1
        rc=$?
        if [ "$rc" = 2 ]; then
            printf '  ok    an unknown flag exits 2\n'
        else
            printf '  FAIL  --bogus exited %s\n' "$rc"
            fails=$((fails + 1))
        fi
    }
    _run_case_flag_combos

    # ---- the parallel runner is faster than the serial one (inc-yg8e) ------
    # Eight cheap checks that each sleep 2 s: 16 s one at a time, under 8 s with
    # four at once. The runner is a poll loop, not wait -n, so this is the case
    # that proves the throttle actually overlaps them.
    _run_case_speedup() {
        local d="$dir/speedup" i t0 t1 dt
        mkdir -p "$d"
        for i in 1 2 3 4 5 6 7 8; do
            printf '#!/bin/sh\n# gate: cheap\nsleep 2\nexit 0\n' > "$d/check_slow$i.sh"
            chmod +x "$d/check_slow$i.sh"
        done
        t0=$(date +%s)
        INCURSION_GATE_JOBS=4 NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --checks-only > /dev/null 2>&1
        t1=$(date +%s)
        dt=$((t1 - t0))
        if [ "$dt" -lt 8 ]; then
            printf '  ok    eight 2 s checks run in %ss with four jobs (serial would be 16)\n' "$dt"
        else
            printf '  FAIL  the parallel runner took %ss for eight 2 s checks\n' "$dt"
            fails=$((fails + 1))
        fi
    }
    _run_case_speedup

    # ---- the slow-cheap note judges a parallel check by CPU time (spec §6) --
    # A parallel check that sleeps for 3 s while its peers share the machine
    # costs almost no CPU, so the note must stay silent even though its
    # wall-clock passes the limit. A parallel check that burns 3 s of CPU must
    # get the note, and it must say "of CPU". The low limit makes the sleeping
    # check's wall-clock the only thing that could trip a wall-clock rule.
    _run_case_cheap_note() {
        local d="$dir/cheapnote" out
        mkdir -p "$d"
        printf '#!/bin/sh\n# gate: cheap\nsleep 3\nexit 0\n' > "$d/check_sleep.sh"
        printf '#!/bin/sh\n# gate: cheap\nend=$(( $(date +%%s) + 3 )); while [ $(date +%%s) -lt $end ]; do :; done\nexit 0\n' \
            > "$d/check_burn.sh"
        chmod +x "$d/check_sleep.sh" "$d/check_burn.sh"
        out="$(NIGHTLY_CHEAP_LIMIT=1 NIGHTLY_CHEAP_CPU_LIMIT=1 INCURSION_GATE_JOBS=4 \
            NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --checks-only 2>&1)"
        local sleep_note burn_note
        sleep_note="$(grep -A1 '^ok          tools/check_sleep.sh$' <<<"$out" | grep 'note:')"
        burn_note="$(grep -A1 '^ok          tools/check_burn.sh$' <<<"$out" | grep 'note:')"
        if [ -z "$sleep_note" ] && grep -q 'of CPU' <<<"$burn_note"; then
            printf '  ok    the parallel note judges CPU time, not wall-clock\n'
        else
            printf '  FAIL  cheap note: sleep=[%s] burn=[%s]\n' "$sleep_note" "$burn_note"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
    }
    _run_case_cheap_note

    # ---- the verdicts do not depend on the job count (inc-yg8e) ------------
    # The existing eight-check table, run at one job and at four, must produce
    # the same verdict lines. A worker that raced the state lookup or lost a
    # verdict would show here.
    _run_case_verdict_equality() {
        local d="$dir/eq" out1 out4 v1 v4
        mkdir -p "$d"
        printf '#!/bin/sh\n# gate: cheap\necho eq\n[ -n "${BEFORE:-}" ] && exit 0\nexit 0\n' > "$d/check_eq_green.sh"
        printf '#!/bin/sh\n# gate: cheap\necho eq\n[ -n "${BEFORE:-}" ] && exit 0\nexit 1\n' > "$d/check_eq_broke.sh"
        printf '#!/bin/sh\n# gate: cheap\necho eq\n[ -n "${BEFORE:-}" ] && exit 1\nexit 0\n' > "$d/check_eq_fixed.sh"
        printf '#!/bin/sh\n# gate: cheap\necho eq\n[ -n "${BEFORE:-}" ] && exit 2\nexit 1\n' > "$d/check_eq_was_un.sh"
        chmod +x "$d"/check_eq_*.sh
        BEFORE=1 NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --record > /dev/null 2>&1
        out1="$(INCURSION_GATE_JOBS=1 NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --checks-only 2>&1)"
        out4="$(INCURSION_GATE_JOBS=4 NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --checks-only 2>&1)"
        v1="$(grep -E '^(ok|FIXED|BROKEN|UNMEASURED|unmeasured|pre-existing) ' <<<"$out1")"
        v4="$(grep -E '^(ok|FIXED|BROKEN|UNMEASURED|unmeasured|pre-existing) ' <<<"$out4")"
        if [ -n "$v1" ] && [ "$v1" = "$v4" ]; then
            printf '  ok    one job and four jobs give identical verdict lines\n'
        else
            printf '  FAIL  the verdict lines differ with the job count\n'
            printf '      jobs=1: %s\n' "$v1"
            printf '      jobs=4: %s\n' "$v4"
            fails=$((fails + 1))
        fi
    }
    _run_case_verdict_equality

    # ---- a serial check runs alone (inc-yg8e) -------------------------------
    # Every non-serial made-up check holds a "running" file in a shared dir
    # while it sleeps; the serial check fails if any such file exists. Because
    # the serial runner starts only after every parallel job has finished, the
    # serial check must find none and pass.
    _run_case_serial_rule() {
        local d="$dir/serial" shared out
        mkdir -p "$d"
        shared="$d/shared"; mkdir -p "$shared"
        local i
        for i in 1 2 3 4; do
            printf '#!/bin/sh\n# gate: cheap\n: > "%s/running-%s"\nsleep 1\nrm -f "%s/running-%s"\nexit 0\n' \
                "$shared" "$i" "$shared" "$i" > "$d/check_par$i.sh"
            chmod +x "$d/check_par$i.sh"
        done
        printf '#!/bin/sh\n# gate: cheap\n# gate-serial: fails if a peer is running\nls "%s"/running-* >/dev/null 2>&1 && exit 1\nexit 0\n' \
            "$shared" > "$d/check_zserial.sh"
        chmod +x "$d/check_zserial.sh"
        out="$(INCURSION_GATE_JOBS=4 NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$d/base.txt" \
            "$0" --checks-only 2>&1)"
        if grep -q '^ok          tools/check_zserial.sh$' <<<"$out"; then
            printf '  ok    the serial check ran alone and passed\n'
        else
            printf '  FAIL  the serial check did not run alone\n'
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
    }
    _run_case_serial_rule

    # ---- the landing gate keeps only the changed live checks (spec §4) ------
    # A throwaway git repository with three made-up checks: a smoke, a live
    # check the bead did not touch, and a live check the bead changed. --landing
    # must run the smoke and the changed live check, and must NOT run the
    # unchanged live one. It must also fail closed (exit 2) when the diff ref is
    # unset or unknown. The builds are stubbed because $NIGHTLY_CHECK_DIR is set
    # (see BUILDS above).
    _run_case_landing_set() {
        local repo d self out rc
        local smoke_marker live_same_marker live_changed_marker
        repo="$dir/landrepo"
        d="$repo/tools"
        mkdir -p "$d"
        self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
        smoke_marker="$d/smoke-touched"
        live_same_marker="$d/live-same-touched"
        live_changed_marker="$d/live-changed-touched"
        printf '#!/bin/sh\n# gate: smoke\ntouch "%s"\nexit 0\n' "$smoke_marker" \
            > "$d/check_aa_smoke.sh"
        printf '#!/bin/sh\n# gate: live\ntouch "%s"\nexit 0\n' "$live_same_marker" \
            > "$d/check_bb_live_same.sh"
        printf '#!/bin/sh\n# gate: live\ntouch "%s"\nexit 0\n' "$live_changed_marker" \
            > "$d/check_cc_live_changed.sh"
        chmod +x "$d/check_aa_smoke.sh" "$d/check_bb_live_same.sh" "$d/check_cc_live_changed.sh"
        git -C "$repo" init -q
        git -C "$repo" config user.email selftest@example.invalid
        git -C "$repo" config user.name selftest
        git -C "$repo" checkout -q -b base
        git -C "$repo" add -A
        git -C "$repo" commit -q -m base
        git -C "$repo" checkout -q -b bead
        printf '\n# changed by the bead\n' >> "$d/check_cc_live_changed.sh"
        git -C "$repo" add -A
        git -C "$repo" commit -q -m bead
        rm -f "$smoke_marker" "$live_same_marker" "$live_changed_marker"
        out="$(cd "$repo" && NIGHTLY_CHECK_DIR="$d" \
            NIGHTLY_VERIFY_STATE="$repo/base.txt" \
            INCURSION_LANDING_DIFF_REF=base "$self" --landing 2>&1)"
        rc=$?
        if [ "$rc" = 0 ] && [ -e "$smoke_marker" ] \
            && [ -e "$live_changed_marker" ] && [ ! -e "$live_same_marker" ]; then
            printf '  ok    --landing runs smoke and the changed live check only\n'
        else
            printf '  FAIL  landing set: rc=%s smoke=%s same=%s changed=%s\n' "$rc" \
                "$([ -e "$smoke_marker" ] && echo present || echo absent)" \
                "$([ -e "$live_same_marker" ] && echo present || echo absent)" \
                "$([ -e "$live_changed_marker" ] && echo present || echo absent)"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
        out="$(cd "$repo" && env -u INCURSION_LANDING_DIFF_REF \
            NIGHTLY_CHECK_DIR="$d" NIGHTLY_VERIFY_STATE="$repo/base.txt" \
            "$self" --landing 2>&1)"
        rc=$?
        if [ "$rc" = 2 ]; then
            printf '  ok    --landing with no diff ref exits 2\n'
        else
            printf '  FAIL  --landing with no diff ref exited %s\n' "$rc"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
        out="$(cd "$repo" && NIGHTLY_CHECK_DIR="$d" \
            NIGHTLY_VERIFY_STATE="$repo/base.txt" \
            INCURSION_LANDING_DIFF_REF=no-such-ref "$self" --landing 2>&1)"
        rc=$?
        if [ "$rc" = 2 ]; then
            printf '  ok    --landing with an unknown diff ref exits 2\n'
        else
            printf '  FAIL  --landing with an unknown diff ref exited %s\n' "$rc"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
    }
    _run_case_landing_set

    # ---- a pass record says which gate passed (inc-t3iu) -------------------
    # A pass of the short landing gate must never be reused by a full run and
    # the reverse must be refused. A throwaway repository with an always-green
    # cheap and live check gives a real full pass to record; the mode line is
    # then hand-edited to drive each refusal. The builds and steps are stubbed
    # because $NIGHTLY_CHECK_DIR is set.
    _run_case_reuse_mode() {
        # The script copy lives in the scratch repo: nightly_verify.sh does
        # "cd $ROOT" and takes the key of its cwd, so a run from the real ROOT
        # would key the real files, not the scratch ones. Copying the script in
        # (as tools/check_pass_record.sh does) makes $ROOT the scratch repo.
        local repo d self out rc rec
        repo="$dir/reusemode"
        d="$repo/tools"
        mkdir -p "$d"
        self="$d/nightly_verify.sh"
        cp "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")" "$self"
        printf '#!/bin/sh\n# gate: cheap\nexit 0\n' > "$d/check_aa_cheap.sh"
        printf '#!/bin/sh\n# gate: live\nexit 0\n' > "$d/check_bb_live.sh"
        printf '#!/bin/sh\nexit 0\n' > "$repo/build_macos.sh"
        printf 'logs/\n' > "$repo/.gitignore"
        chmod +x "$self" "$d/check_aa_cheap.sh" "$d/check_bb_live.sh" "$repo/build_macos.sh"
        git -C "$repo" init -q
        git -C "$repo" config user.email selftest@example.invalid
        git -C "$repo" config user.name selftest
        git -C "$repo" checkout -q -b base
        git -C "$repo" add -A
        git -C "$repo" commit -q -m base
        rec="$repo/logs/nightly-verify-pass.txt"
        # A real full pass writes a "mode full" record.
        out="$(cd "$repo" && NIGHTLY_CHECK_DIR="$d" \
            NIGHTLY_VERIFY_STATE="$repo/logs/nightly-verify-base.txt" "$self" --compare 2>&1)"
        rc=$?
        if [ "$rc" = 0 ] && [ "$(sed -n 's/^mode //p' "$rec" 2>/dev/null)" = full ]; then
            printf '  ok    a full gate writes a "mode full" pass record\n'
        else
            printf '  FAIL  full record: rc=%s mode=%s\n' "$rc" \
                "$(sed -n 's/^mode //p' "$rec" 2>/dev/null)"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
        # The full record is reused by a plain --reuse-pass.
        out="$(cd "$repo" && NIGHTLY_CHECK_DIR="$d" \
            NIGHTLY_VERIFY_STATE="$repo/logs/nightly-verify-base.txt" "$self" --reuse-pass 2>&1)"
        rc=$?
        if [ "$rc" = 0 ] && grep -q 'REUSED from a full pass at' <<<"$out"; then
            printf '  ok    a "mode full" record is reused by --reuse-pass\n'
        else
            printf '  FAIL  full reuse: rc=%s\n' "$rc"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
        # A full record is NOT reused by the landing gate.
        out="$(cd "$repo" && NIGHTLY_CHECK_DIR="$d" \
            NIGHTLY_VERIFY_STATE="$repo/logs/nightly-verify-base.txt" \
            INCURSION_LANDING_DIFF_REF=base "$self" --landing --reuse-pass 2>&1)"
        rc=$?
        if grep -q 'the pass record is from the full gate' <<<"$out"; then
            printf '  ok    a full record is refused by --landing --reuse-pass\n'
        else
            printf '  FAIL  landing refused a full record: rc=%s\n' "$rc"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
        # A landing record is NOT reused by a full --reuse-pass.
        sed 's/^mode .*/mode landing/' "$rec" > "$rec.new"; mv -f "$rec.new" "$rec"
        out="$(cd "$repo" && NIGHTLY_CHECK_DIR="$d" \
            NIGHTLY_VERIFY_STATE="$repo/logs/nightly-verify-base.txt" "$self" --reuse-pass 2>&1)"
        rc=$?
        if grep -q 'the pass record is from the landing gate' <<<"$out"; then
            printf '  ok    a landing record is refused by --reuse-pass\n'
        else
            printf '  FAIL  reuse refused a landing record: rc=%s\n' "$rc"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
        # A record with no mode line at all is stale, and fails closed.
        sed '/^mode /d' "$rec" > "$rec.new"; mv -f "$rec.new" "$rec"
        out="$(cd "$repo" && NIGHTLY_CHECK_DIR="$d" \
            NIGHTLY_VERIFY_STATE="$repo/logs/nightly-verify-base.txt" "$self" --reuse-pass 2>&1)"
        rc=$?
        if grep -q 'malformed' <<<"$out"; then
            printf '  ok    a record with no mode line is malformed\n'
        else
            printf '  FAIL  a record with no mode line: rc=%s\n' "$rc"
            printf '%s\n' "$out" | sed 's/^/      | /'
            fails=$((fails + 1))
        fi
    }
    _run_case_reuse_mode

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
        echo "--- no pass to reuse: $REUSE_VERDICT. Running the $(gate_name). ---"
    fi
fi
FULL_RUN=0
if [ "$MODE" = "compare" ] && [ "$SKIP_BUILDS" = 0 ] && [ "$SKIP_LIVE" = 0 ]; then
    FULL_RUN=1
    rm -f "$PASS_RECORD"
    KEY_TREE="$(content_tree)"; KEY_BASE="$(base_hash)"; KEY_ENV="$(env_hash)"
fi

# The landing gate measures ONLY the live checks whose file the branch changed.
# The changed set comes from the landing script's diff ref; it fails CLOSED,
# because "could not list the changes" must never read as "no changes" (spec
# docs/specs/2026-10-06-landing-gate-split-spec.md section 4). Nothing here
# runs unless LANDING=1, so --compare and --record are untouched.
LANDING_CHANGED=""
if [ "$LANDING" = 1 ]; then
    if [ -z "${INCURSION_LANDING_DIFF_REF:-}" ]; then
        echo "landing gate: INCURSION_LANDING_DIFF_REF is unset or empty, so the changed live checks cannot be listed" >&2
        exit 2
    fi
    if ! git -C "$CHECK_DIR" rev-parse --verify "${INCURSION_LANDING_DIFF_REF}^{commit}" > /dev/null 2>&1; then
        echo "landing gate: cannot resolve INCURSION_LANDING_DIFF_REF=$INCURSION_LANDING_DIFF_REF to a commit" >&2
        exit 2
    fi
    LANDING_CHANGED="$(git -C "$CHECK_DIR" diff --name-only --relative "${INCURSION_LANDING_DIFF_REF}...HEAD" -- .)"
    LANDING_DIFF_RC=$?
    if [ "$LANDING_DIFF_RC" != 0 ]; then
        echo "landing gate: git diff against $INCURSION_LANDING_DIFF_REF failed (exit $LANDING_DIFF_RC)" >&2
        exit 2
    fi
fi

discover_checks
if [ "${#CHECKS[@]}" = 0 ]; then
    echo "no check in $CHECK_DIR declares a '# gate:' tier" >&2
    exit 2
fi

# The build set, named once and read by --record and --compare alike, so the two
# can never drift into building different things (inc-o5bi). Both backends,
# because they are separate main()s; posix first, because the libtcod build then
# leaves mod/Incursion.Mod as the module every live check reads.
BUILDS=( "BACKEND=posix ./build_macos.sh" "./build_macos.sh" )
# The selftest points $NIGHTLY_CHECK_DIR at made-up checks and must never run a
# real build. Nothing else sets it. $NIGHTLY_BUILDS_REAL=1 opts a selftest run
# back into the real builds.
if [ -n "${NIGHTLY_CHECK_DIR:-}" ] && [ "${NIGHTLY_BUILDS_REAL:-0}" != 1 ]; then
    BUILDS=()
fi

# ------------------------------------------------------------------ record ---
# THE BASE IS BUILT BEFORE IT IS MEASURED (inc-o5bi). Until 2026-09-17 this
# branch measured the live tier against whatever ./incursion-headless happened
# to be lying in the tree, while --compare built first. The ratchet then
# compared two measurements taken against DIFFERENT binaries, so a live check
# could report BROKEN or FIXED with no source change behind it at all.
#
# Observed, 2026-09-12, landing inc-8wsm -- two integers in an options table and
# no code whatever. --record in the shared checkout, whose ./incursion-headless
# predated the source, wrote "base 1 tools/check_pray_aid_int32.sh". --compare
# in a freshly built worktree of that same source answered "FIXED
# tools/check_pray_aid_int32.sh (was exit 1)". A third run held the source still
# and changed only the binary, and it reproduced both answers. The source was
# never the variable.
#
# FIXED is the harmless direction, and it is the one that showed. The harmful
# direction is its mirror and it is silent: a stale binary fails a check that
# the current source passes, the base writes that check down as failing, the run
# then breaks that area for real, and the table above reads base-fail plus
# now-fail as "pre-existing, passes". The merge proceeds. This header already
# says a tree that does not compile is never safe to merge; the same reasoning
# applies to the base, because a base measured on a tree that is not the tree
# under test is not a base.
#
# THE SAME BUILDS AS --compare, AND NOTHING ELSE. The Linux cross-build, the
# layout sweep and the soak stay out of this branch: the state file records none
# of them, so running them here would cost minutes and tell the ratchet nothing.
# They are verdicts on the tree, and --record passes no verdict.
#
# ONLY WHEN A LIVE CHECK IS THERE TO MEASURE. The builds exist to give the live
# tier a binary from this source, and a check set holding no live tier needs no
# binary. That is what keeps --selftest, whose made-up checks are every one of
# them cheap, at a second rather than a rebuild. --checks-only and --docs-only
# never reach this branch at all: both set MODE=compare, so the SKIP_BUILDS they
# set is read further down, and neither one builds anything here or there.
#
# A BUILD THAT FAILS WRITES NO BASE AND DELETES THE OLD ONE. A base measured on
# a tree that does not compile is worse than no base, and the previous run's
# base left sitting in place is the stale record this whole fix is about. Exit 2
# is "could not measure". A --compare that finds no base demands that every
# check pass outright, which is the strict direction to fail in.
if [ "$MODE" = "record" ]; then
    record_live=0
    for entry in "${CHECKS[@]}"; do
        # entry is "<id>\t<cmd>\t<tier>\t<serial>": strip id and cmd, then the
        # tier is the next field.
        tier="${entry#*	}"; tier="${tier#*	}"; tier="${tier%%	*}"
        { [ "$tier" = live ] || [ "$tier" = smoke ]; } && record_live=1
    done
    # The real steps need the binary, so build when any step is present; an
    # empty step list never forces a build.
    [ "${#STEPS[@]}" -gt 0 ] && record_live=1
    if [ "$record_live" = 1 ]; then
        echo "--- builds (a base is only a base when this source built the binary) ---"
        for build in ${BUILDS[@]+"${BUILDS[@]}"}; do
            printf '%s ... ' "$build"
            if ( eval "$build" ) > /dev/null 2>&1; then
                echo "ok"
            else
                echo "FAILED"
                echo "    re-run it to see why: $build"
                rm -f "$STATE"
                echo "NO base recorded, and $STATE is gone:"
                echo "a base from a tree that does not compile is worse than none."
                exit 2
            fi
        done
        echo
    fi
    mkdir -p "$(dirname "$STATE")" || exit 2
    : > "$STATE"
    # The same runner and the same serial rule as --compare: the non-serial
    # checks in parallel, then the serial ones alone, cheap before live. The
    # serial cheap phase runs before the serial live one for the same reason
    # --compare does (inc-yg8e): a live check needs the binary, a cheap one does
    # not, and the base records both. The state file, though, is a record keyed
    # by check, and a reader diffs it against a later one line by line, so its
    # lines come out in discovery order however the phases ran.
    RESDIR="$(mktemp -d "${TMPDIR:-/tmp}/nvrec.XXXXXX")" || exit 2
    collect_phase_parallel cheap "$RESDIR"
    collect_serial cheap "$RESDIR"
    collect_phase_parallel smoke "$RESDIR"
    collect_serial smoke "$RESDIR"
    collect_phase_parallel live "$RESDIR"
    collect_serial live "$RESDIR"
    # Every step runs here, one after another, each writing its own log. A step
    # that fails or exits 2 only records its code: it never stops --record and
    # never deletes the base. Only a failed build does that, above.
    STEP_RCS=()
    for step in ${STEPS[@]+"${STEPS[@]}"}; do
        cmd="${step%%	*}"
        log="$(step_log_path "$cmd")"
        ( eval "$cmd" ) > "$log" 2>&1
        rc=$?
        STEP_RCS+=( "$rc	${cmd%% *}" )
    done
    for entry in "${CHECKS[@]}"; do
        id="${entry%%	*}"
        stem="$(id_file_stem "$id")"
        rc="$(cat "$RESDIR/$stem.rc" 2>/dev/null)"
        [ -n "$rc" ] || rc=2
        printf '%s\t%s\n' "$rc" "$id" >> "$STATE"
        printf 'base %-3s %s\n' "$rc" "$id"
    done
    for entry in ${STEP_RCS[@]+"${STEP_RCS[@]}"}; do
        rc="${entry%%	*}"; id="${entry#*	}"
        printf '%s\t%s\n' "$rc" "$id" >> "$STATE"
        printf 'base %-3s %s\n' "$rc" "$id"
    done
    rm -rf "$RESDIR"
    echo "recorded the pre-run state in $STATE"
    exit 0
fi

# ----------------------------------------------------------------- compare ---
# THE NEW ORDER (inc-yg8e). The old loop ran every check strictly one at a
# time, after the builds: a clean landing on a ten-core Mac cost about 33
# minutes and the cheapest checks -- which cost seconds -- could only report
# after the minutes-long ones. This runs the cheap tier FIRST and stops on a
# cheap failure (no reason to spend the builds on a tree whose seconds already
# broke), then the builds, then the three big steps in the background beside the
# live tier, then the serial live checks alone. The SERIAL cheap checks are part
# of that cheap phase too, after the parallel cheap ones and before the builds:
# a serial cheap check that breaks must stop at once like any other cheap check,
# not wait for the end. Every verdict line and every exit code is unchanged;
# only when each one is printed has moved.
FAILED=0

echo
if [ "$LANDING" = 1 ]; then
    echo "--- landing gate: cheap, builds, soak, smoke, and $LANDING_LIVE_KEPT changed live check(s) ---"
fi
echo "--- checks (ratcheted against the state before the run) ---"
if [ -r "$STATE" ]; then
    echo "base recorded in $STATE"
else
    echo "NO recorded base. Every check must pass outright."
fi

# 1. The cheap tier, through the parallel runner.
run_phase_parallel cheap

# 1b. The SERIAL cheap checks, one at a time. They run here, before the builds,
#     and not at the end with the serial live checks (inc-yg8e): a serial cheap
#     check that breaks must stop the run while nothing else has started, or the
#     fail-fast the first phase promised is defeated by a check that only reports
#     at the end. Nothing else is running yet, so the alone-run rule holds. Both
#     sets' verdicts print before the STOPPED line, so a reader sees the whole
#     cheap tier whether it passed or broke.
run_phase_serial cheap
if [ "$FAILED" = 1 ]; then
    echo "=== STOPPED: the cheap tier broke a check; the builds and the live tier were not run ==="
    echo "=== FAIL: do NOT merge. The branch stays for a person to read. ==="
    exit 1
fi

# 2. The builds, the two of them one after the other, as today. A tree that does
#    not compile is never safe to merge, so a failed build stops at once rather
#    than carrying on to measure a binary that is not this source.
if [ "$SKIP_BUILDS" = 1 ]; then
    if [ "$REUSED" = 1 ]; then
        echo "--- builds and the live tier REUSED from $REUSE_VERDICT ---"
    elif [ "$SKIP_LIVE" = 1 ]; then
        echo "--- builds and the live tier SKIPPED (--docs-only: no *.md reaches them) ---"
    else
        echo "--- builds SKIPPED (--checks-only) ---"
    fi
else
    echo "--- builds, macOS only (absolute: a tree that does not compile never merges) ---"
    if [ "$LANDING" = 0 ]; then
        echo "    (the Linux cross-build follows as a background step)"
    fi
    build_failed=0
    for build in ${BUILDS[@]+"${BUILDS[@]}"}; do
        printf '%s ... ' "$build"
        if ( eval "$build" ) > /dev/null 2>&1; then
            echo "ok"
        else
            echo "FAILED"
            echo "    re-run it to see why: $build"
            build_failed=1
        fi
    done
    if [ "$build_failed" = 1 ]; then
        echo "=== FAIL: do NOT merge. The branch stays for a person to read. ==="
        exit 1
    fi

    # 3. The three big steps in the BACKGROUND, each to its own log, while the
    #    live tier runs. They read the tree but do not write it: the Linux build
    #    exports the working tree into a container and never bind-mounts it; the
    #    layout sweep builds the probe with a private OUT= and a non-empty
    #    EXTRA_CXXFLAGS=, so it skips the shared module rewrite; the soak runs
    #    sessions under logs/runs and writes no module or binary.
    if [ "$LANDING" = 1 ]; then
        start_background_steps LANDING_STEPS
    else
        start_background_steps STEPS
    fi
fi

# 4. The smoke tier, through the parallel runner, then the live tier, while the
#    steps run. Smoke "plays the game briefly" and needs the builds like live.
run_phase_parallel smoke
run_phase_parallel live

# 5. Wait for the steps and print their ok / SKIPPED / FAILED lines.
if [ "$SKIP_BUILDS" = 0 ]; then
    wait_background_steps
fi

# 6. The SERIAL smoke then live checks, one at a time, nothing else running. The
#    serial cheap checks already ran in step 1b; this is only the smoke and live
#    half.
run_phase_serial smoke
run_phase_serial live

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
