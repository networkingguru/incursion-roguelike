#!/bin/bash
# The scaffolding every behavioural check repeats, in one place. (bd inc-le1m)
#
# WHY THIS EXISTS, measured on 2026-09-10 over the 214 check_*.sh scripts that
# were here before this file: 24,672 lines between them. 127 set
# INCURSION_OPTIONS and called headless.sh by hand, 106 handled a seed by hand,
# 50 wrote their own trap and 46 made their own temp directory. Only 4 touched a
# shared helper, and that one -- tools/gate_lib.sh -- serves the gate, not the
# checks. The bulk was scaffolding, not rigour: counting lines that are neither
# blank nor comment, check_broken_door.sh is 207, check_armour_model.sh 174 and
# check_springblade.sh 185, while check_dequ_save_message.sh does the full
# before/after comparison docs/VERIFICATION.md demands in 58. This file is that
# 58-line shape, extracted, so a new check is about a dozen lines.
#
# NOT A MIGRATION. The 214 existing scripts stay as they are. Rewriting checks
# that currently work risks quietly breaking one that guards a real defect, and
# buys no behaviour. Use this for new work only.
#
# A CHECK WRITTEN WITH IT, whole:
#
#     #!/bin/bash
#     # Does <the thing> still <do the thing>? (bd inc-xxxx)
#     . "$(dirname "$0")/check_lib.sh"
#
#     CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
#     check_mutation src/Fight.cpp 'if (Save(...))' 'if (0)'
#
#     check_run tools/keys/thing.keys 42
#     check_screens '*-thing-*'
#     check_expect "You feel the thing"   "the character is told"
#     check_reject "the thing protects its thing"
#     check_done "the thing still tells the character, in his own words"
#
# WHAT EACH PIECE IS FOR
#
#   check_build      build a target once per invocation, cached.
#   check_run        one seeded, sandboxed session with named settings.
#   check_screens    choose the screen dumps the assertions read.
#   check_expect     a chosen screen contains a string.
#   check_reject     no chosen screen contains a string.
#   check_mutation   declare how to break the fix, so `$0 --prove-red` can
#                    break it, rebuild, re-run this check and prove it fails.
#   check_done       print the verdict and exit 0, 1 or 2.
#
# check_mutation is the point of the whole file. docs/VERIFICATION.md step 2 --
# prove the check goes red -- "is the step that gets skipped, and it is the step
# that matters". It got skipped because it was a manual dance: edit the source,
# rebuild, run, remember to put the source back. Here it is one declaration and
# one flag, and the restore is a trap rather than a memory.
#
# FOUR RULES THIS FILE ENFORCES, because each one has already cost a day:
#
#   Settings are an input. e4a6499 measured one flipped option byte taking
#   dive.keys on seed 4242 from 254 turns to 2190, so CHECK_OPTIONS has no
#   default and check_run refuses to run without it.
#
#   A run that measured nothing is not a pass. tools/headless.sh exits 5 for
#   NO GAMEPLAY and 7 for an unlisted ASSERT; check_run stops on both instead
#   of reading them as a quiet session. That is inc-loa.3.
#
#   A run the game killed is a FAIL, not a shrug. Exits 1 (Fatal), 4 (the
#   watchdog: the game stopped asking for keys, the signature of a hang) and
#   128 and up (a signal killed the process) say the GAME broke, not that the
#   measurement drifted, so check_run exits 1 and quotes the session's
#   errors.log. Calling those "could not measure" made any check whose defect
#   IS a crash unprovable, because --prove-red reads exit 2 as "nothing is
#   proved": inc-upw.30 dies inside the very sentence it asserts. The two rules
#   sit side by side and do not overlap -- 2, 5, 6 and 7 stay INCONCLUSIVE,
#   because each of those says the key script or the harness drifted.
#
#   check_reject alone is unfailable. A run that never reached the interesting
#   state prints neither the good string nor the bad one, and a check made only
#   of check_reject passes on nothing at all. check_done reports that as
#   INCONCLUSIVE, so every check must assert something positive as well.
#
# Exit codes, the convention across tools/: 0 pass, 1 fail, 2 could not measure.
#
# The library cd's to the repository root and sets `set -uo pipefail` for the
# caller, because all 214 existing checks open with those same three lines.
#
# Prove this file still works:  tools/check_lib.sh --selftest

# Bash, not sh or zsh: this file uses arrays and BASH_SOURCE, and under `set -u`
# a shell without them fails with "parameter not set" three lines further down,
# which names neither the cause nor the cure.
if [ -z "${BASH_VERSION:-}" ]; then
    echo "tools/check_lib.sh needs bash. Give the check a #!/bin/bash line." >&2
    return 2 2>/dev/null || exit 2
fi

set -uo pipefail

CHECK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_ROOT="$(cd "$CHECK_LIB_DIR/.." && pwd)"

# The check's own path, resolved BEFORE the cd below and never after it.
# --prove-red re-runs the check, and `$0` is whatever the caller typed: run a
# check as `cd tools && ./check_x.sh --prove-red` and after the cd that name
# resolves to nothing. The re-run then fails to start, which used to look like
# a check that had gone red.
CHECK_SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

cd "$CHECK_ROOT" || exit 2

# The settings file. No default on purpose -- see the header.
CHECK_OPTIONS="${CHECK_OPTIONS:-}"

# Which build the run needs, and therefore which one --prove-red rebuilds.
# "posix" is the headless binary every scripted session plays; "sdl" is the
# one a human plays. A check that needs both sets CHECK_TARGETS="posix sdl".
CHECK_TARGETS="${CHECK_TARGETS:-posix}"

CHECK_RUN=""            # the finished session's directory
CHECK_SCREENS=()        # the screen dumps the assertions read
CHECK_FAIL=0            # any assertion failed
CHECK_EXPECTS=0         # how many check_expect calls passed
CHECK_REJECTS=0         # how many check_reject calls ran
CHECK_BUILT=""          # targets whose build was attempted this invocation

# --prove-red is the library's flag, not the check's. A sourced file sees the
# caller's positional parameters, so this reads the check's own command line.
# CHECK_ARGS is that line with the flag taken out, for the inner re-run.
CHECK_PROVE_RED="${CHECK_PROVE_RED:-0}"
CHECK_ARGS=()
for _check_arg in "$@"; do
    if [ "$_check_arg" = "--prove-red" ]; then
        CHECK_PROVE_RED=1
    else
        CHECK_ARGS+=("$_check_arg")
    fi
done
unset _check_arg

# ---------------------------------------------------------------------------
# Stop, and say which of the three verdicts this is. Anything that means "the
# check could not measure" exits 2, never 0: a green result from a session that
# did nothing is the failure this whole directory is written against.
_check_die() { # <exit code> <line>...
    local code="$1"; shift
    local label="FAIL:"
    [ "$code" = 2 ] && label="INCONCLUSIVE:"
    echo "$label $1"
    shift
    local line
    for line in "$@"; do echo "      $line"; done
    exit "$code"
}

# Count and replace literal text, including text that spans lines. sed is wrong
# for this: a mutation's `from` is a fragment of C++, and `[`, `.`, `*` and `/`
# in it are all live characters to sed and all common in the code being cut.
_check_count() { # <file> <literal> -> prints the number of occurrences
    CHECK_L_FILE="$1" CHECK_L_TEXT="$2" python3 -c '
import os
p = os.environ["CHECK_L_FILE"]
t = os.environ["CHECK_L_TEXT"]
print(open(p, encoding="utf-8", errors="surrogateescape").read().count(t))
' 2>/dev/null || echo 0
}

_check_replace() { # <file> <literal from> <literal to>
    CHECK_L_FILE="$1" CHECK_L_TEXT="$2" CHECK_L_TO="$3" python3 -c '
import os
p = os.environ["CHECK_L_FILE"]
a = os.environ["CHECK_L_TEXT"]
b = os.environ["CHECK_L_TO"]
s = open(p, encoding="utf-8", errors="surrogateescape").read()
open(p, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(a, b))
'
}

# ---------------------------------------------------------------------------
# check_build <posix|sdl> -- build one target, at most once per invocation.
#
# ./build_macos.sh and BACKEND=posix ./build_macos.sh are separate main()s
# (docs/VERIFICATION.md step 3), so a change can break one while the other
# compiles. A no-op build still costs about 22 seconds because it relinks and
# recompiles the module, which is why check_run does NOT call this: an ordinary
# check run wants the binary that is already there. --prove-red calls it,
# because it has just changed the source.
check_build() { # <posix|sdl>
    local target="$1" env_backend="" out log
    case "$target" in
        posix) env_backend="posix"; out="incursion-headless" ;;
        sdl)   env_backend="libtcod"; out="incursion" ;;
        *) _check_die 2 "check_build: unknown target '$target' (want posix or sdl)" ;;
    esac
    case " $CHECK_BUILT " in *" $target "*) return 0 ;; esac

    log="$(mktemp -t check_build)" || _check_die 2 "check_build: no temp file"
    printf '  building %s ... ' "$out"
    CHECK_BUILT="$CHECK_BUILT $target"
    if BACKEND="$env_backend" ./build_macos.sh > "$log" 2>&1; then
        echo "ok"
        rm -f "$log"
        return 0
    fi
    rm -f "$CHECK_ROOT/$out"
    echo "FAILED ($out removed; the failed build may have linked it)"
    tail -20 "$log" | sed 's/^/      /'
    _check_die 2 "BACKEND=$env_backend ./build_macos.sh did not finish; full log in $log"
}

# ---------------------------------------------------------------------------
# _check_session_verdict <exit code> [the harness report] -- judge one session
# by how it ended, and stop unless it ended in a way a check may read.
#
# The three verdicts, and tools/headless.sh's codes behind them (its own header
# lists all of them, around line 31):
#
#   go on   0 the script finished or asked to quit, 3 the key budget ran out.
#           Those are how nearly every key script ends.
#
#   FAIL    1 Fatal(), 4 the watchdog fired -- the game stopped asking for
#           keys, which is the signature of a hang -- and 128 and up, which is
#           a signal killing the process. In each the GAME died, and we can say
#           so; see the fourth rule in this file's header for why that must not
#           be reported as a failure to measure.
#
#   stop 2  everything else: 2 an unreadable key script, 5 the run never
#           entered a map, 6 an @choose/@cursorto/@expect looked for something
#           the screen never showed, 7 an ASSERT tools/known_asserts.txt does
#           not list. Each says the check or the harness drifted, so the
#           session is evidence about nothing.
#
# It is a function of its own, and not four lines inside check_run, so that
# tools/check_lib.sh --selftest can put every code through it in a second
# without building or playing the game.
_check_session_verdict() { # <exit code> [harness output]
    local status="$1" out="${2:-}" why=""

    { [ "$status" -eq 0 ] || [ "$status" -eq 3 ]; } && return 0

    case "$status" in
        1) why="Fatal()" ;;
        4) why="the watchdog fired; the game stopped asking for keys" ;;
        *) [ "$status" -ge 128 ] && why="a signal killed it" ;;
    esac

    if [ -n "$why" ]; then
        # The last messages the engine logged, and not the file: an errors.log
        # entry carries its call stack indented under it, and a whole stack
        # buries the one line that names what the game was doing. `^[0-9]` is
        # the timestamp every message begins with, which headless.sh:244 uses
        # to the same end.
        if [ -n "${CHECK_RUN:-}" ] && [ -f "$CHECK_RUN/logs/errors.log" ]; then
            grep '^[0-9]' "$CHECK_RUN/logs/errors.log" | tail -2 | sed 's/^/      /'
        fi
        _check_die 1 \
            "the game died: tools/headless.sh exit $status, $why." \
            "The session, with its screens and its logs, is in" \
            "${CHECK_RUN:-logs/runs (the harness named no directory)}."
    fi

    [ -n "$out" ] &&
        printf '%s\n' "$out" | sed -n '/^--- after the session ---/,$p' | sed 's/^/      /'
    _check_die 2 \
        "the session ended badly (tools/headless.sh exit $status), so it" \
        "measured nothing. See ${CHECK_RUN:-the output above}."
}

# ---------------------------------------------------------------------------
# check_run <keyscript> <seed> -- one seeded, sandboxed session.
#
# Always through tools/headless.sh, never the bare binary: a bare run reads and
# can write the owner's real save/, and a scripted character has landed beside
# real ones before. The seed is required, not optional -- an unseeded run is a
# smoke test, because the attribute rolls and therefore the offered feats and
# therefore which letter chooses what change on every run.
#
# Export any probe variable the session needs (INCURSION_DOOR_PROBE=1,
# INCURSION_BIN=./incursion-probe) before calling this. They reach the game
# through the environment and need no plumbing here.
#
# Sets CHECK_RUN to the session directory. Leaves the directory in place: it is
# the evidence, and a check that deleted it would have to be re-run to be read.
check_run() { # <keyscript> <seed>
    local keys="${1:-}" seed="${2:-}" out status bin

    [ -n "$CHECK_OPTIONS" ] || _check_die 2 \
        "CHECK_OPTIONS is unset, so this run would not name its settings." \
        "Settings change what a seeded session does. Choose a frozen file:" \
        "  CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat" \
        "tools/fixtures/README.md says what each one holds."
    [ -f "$CHECK_OPTIONS" ] || _check_die 2 \
        "CHECK_OPTIONS names a file that is not there: $CHECK_OPTIONS"
    [ -n "$keys" ] && [ -f "$keys" ] || _check_die 2 \
        "check_run: no such key script: ${keys:-<none given>}" \
        "Key scripts live in tools/keys/."
    [ -n "$seed" ] || _check_die 2 \
        "check_run: a check must pin its seed. Without one the run is not" \
        "reproducible, so a later red result cannot be told from a reroll."

    bin="${INCURSION_BIN:-./incursion-headless}"
    [ -x "$bin" ] || _check_die 2 \
        "$bin is not built." \
        "Run: BACKEND=posix ./build_macos.sh"

    out="$(INCURSION_OPTIONS="$CHECK_OPTIONS" tools/headless.sh "$keys" "$seed" 2>&1 </dev/null)"
    status=$?
    CHECK_RUN="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
    [ -n "$CHECK_RUN" ] && printf '%s\n' "$out" > "$CHECK_RUN/harness.txt"

    _check_session_verdict "$status" "$out"

    # Reported, not failed. headless.sh deliberately leaves the "is a death a
    # failure?" question to the caller (inc-loa.3, inc-loa.5), and this library
    # is not the place to settle a product question. But a session parked at an
    # unanswered prompt stopped playing at that point, so the line has to be
    # visible in the check's own output rather than only in the run directory.
    printf '%s\n' "$out" | grep -E '^(death:|stuck-prompt:) *(STUCK|threat)' | sed 's/^/  note: /'

    echo "  session: $CHECK_RUN (seed $seed, $(basename "$CHECK_OPTIONS"))"
    return 0
}

# ---------------------------------------------------------------------------
# check_screens [glob] -- choose which screen dumps the assertions read.
#
# The glob is matched against the dump file names, which a key script's @dump
# directive labels, so '*-strike-*' selects the screens dumped after each blow.
# With no argument it takes every screen. No screens at all is INCONCLUSIVE and
# never a pass: it is the shape of a run whose key script drifted.
check_screens() { # [glob]
    local pat="${1:-*}"
    [ -n "$CHECK_RUN" ] || _check_die 2 "check_screens: call check_run first"
    CHECK_SCREENS=()
    local f
    for f in "$CHECK_RUN"/logs/screens/$pat.txt; do
        [ -f "$f" ] && CHECK_SCREENS+=("$f")
    done
    [ "${#CHECK_SCREENS[@]}" -gt 0 ] || _check_die 2 \
        "no screen dump under $CHECK_RUN/logs/screens matches '$pat.txt'," \
        "so there is nothing to read. Either the key script dumped no screen" \
        "with that label, or the session never got that far."
    echo "  screens: ${#CHECK_SCREENS[@]} matching '$pat'"
    return 0
}

# ---------------------------------------------------------------------------
# check_expect <text> [what it proves] -- some chosen screen contains the text.
#
# Fixed strings, never regular expressions. Game text is full of `+1`, `[yn]`
# and `...`, and a check whose oracle silently became a pattern is worse than
# no check. Reach for grep yourself on the rare occasion you want a pattern.
check_expect() { # <text> [description]
    local text="$1" why="${2:-}" n
    [ -n "$text" ] || _check_die 2 "check_expect: empty assertion text is a caller error."
    _check_have_screens check_expect
    n="$(grep -lF -- "$text" "${CHECK_SCREENS[@]}" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$n" -gt 0 ]; then
        CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
        printf '  ok    %d/%d screens: %s\n' "$n" "${#CHECK_SCREENS[@]}" "${why:-$text}"
        return 0
    fi
    printf '  FAIL  0/%d screens carry: %s\n' "${#CHECK_SCREENS[@]}" "$text"
    [ -n "$why" ] && printf '        it should prove: %s\n' "$why"
    CHECK_FAIL=1
    return 1
}

# ---------------------------------------------------------------------------
# check_expect_all <text> [description] -- EVERY chosen screen contains it.
#
# The stricter form, for a check that dumps one screen per event and wants the
# right line on all of them rather than on one lucky one.
check_expect_all() { # <text> [description]
    local text="$1" why="${2:-}" n
    [ -n "$text" ] || _check_die 2 "check_expect_all: empty assertion text is a caller error."
    _check_have_screens check_expect_all
    n="$(grep -lF -- "$text" "${CHECK_SCREENS[@]}" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$n" -eq "${#CHECK_SCREENS[@]}" ]; then
        CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
        printf '  ok    %d/%d screens: %s\n' "$n" "${#CHECK_SCREENS[@]}" "${why:-$text}"
        return 0
    fi
    printf '  FAIL  only %d of %d screens carry: %s\n' "$n" "${#CHECK_SCREENS[@]}" "$text"
    [ -n "$why" ] && printf '        it should prove: %s\n' "$why"
    CHECK_FAIL=1
    return 1
}

# ---------------------------------------------------------------------------
# check_reject <text> [description] -- no chosen screen contains the text.
#
# On its own this assertion cannot fail for the right reason. See check_done.
check_reject() { # <text> [description]
    local text="$1" why="${2:-}" hits
    _check_have_screens check_reject
    CHECK_REJECTS=$((CHECK_REJECTS + 1))
    hits="$(grep -lF -- "$text" "${CHECK_SCREENS[@]}" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$hits" -eq 0 ]; then
        printf '  ok    0/%d screens: %s\n' "${#CHECK_SCREENS[@]}" "${why:-no \"$text\"}"
        return 0
    fi
    printf '  FAIL  %d/%d screens still carry: %s\n' "$hits" "${#CHECK_SCREENS[@]}" "$text"
    [ -n "$why" ] && printf '        it should prove: %s\n' "$why"
    grep -hoF -- "$text" "${CHECK_SCREENS[@]}" 2>/dev/null | head -1 | sed 's/^/        first: /'
    CHECK_FAIL=1
    return 1
}

_check_have_screens() { # <caller name>
    [ "${#CHECK_SCREENS[@]}" -gt 0 ] || _check_die 2 \
        "$1: no screens are chosen. Call check_screens after check_run."
}

# ---------------------------------------------------------------------------
# check_mutation <file> <literal from> <literal to> -- declare how to break it.
#
# Two jobs, one line.
#
# On an ordinary run it asserts that `from` still appears in `file` EXACTLY
# once. That alone is worth the line: it catches a check whose declared
# mutation has rotted away under it, which is a check nobody can prove any more.
# Exactly once, not at least once, because an ambiguous mutation proves nothing
# specific about which site the check is watching.
#
# With --prove-red it performs docs/VERIFICATION.md step 2 whole: require a
# green run first, copy the file aside, put `to` in place of `from`, rebuild
# every target in CHECK_TARGETS,
# re-run this same check, restore the file, rebuild again, and report. It exits
# 0 when the inner run FAILED, because a check that goes red on a broken fix is
# a check that measures something. It exits 1 when the inner run passed.
#
# The restore is a trap on EXIT, INT, TERM and HUP, and the file is compared
# against its copy afterwards. This function edits tracked source, so losing
# the original to an interrupt is the one outcome it must make impossible.
#
# The file need not be source. Naming the check's own path mutates its oracle
# instead, which is the other half of what step 2 allows.
#
# ONE MUTATION PER --prove-red RUN. A check may declare several, and an ordinary
# run guards every one of them, but --prove-red performs the FIRST and exits.
# That is deliberate: two mutations at once would prove neither site
# individually. To prove a second site, move it up, or give the check a flag
# that chooses which one it declares.
check_mutation() { # <file> <literal from> <literal to>
    local file="$1" from="$2" to="$3" n
    [ -f "$file" ] || _check_die 2 "check_mutation: no such file: $file"

    # The inner run of --prove-red reaches this line with the mutation already
    # applied, so `from` is gone and the count guard below would stop it with
    # INCONCLUSIVE before it asserted anything. CHECK_MUTATED is how the outer
    # run says "you are the broken build; get on with it".
    [ "${CHECK_MUTATED:-0}" = 1 ] && return 0
    n="$(_check_count "$file" "$from")"
    [ "$n" = 1 ] || _check_die 2 \
        "check_mutation: the text it would replace appears $n times in $file," \
        "and it must appear exactly once. The fix has moved, or the excerpt is" \
        "ambiguous. Until this is right, '$0 --prove-red' cannot prove anything."

    [ "$CHECK_PROVE_RED" = 1 ] || return 0
    _check_prove_red "$file" "$from" "$to"
}

# Undo everything _check_prove_red did, from wherever it stopped. Safe to run
# twice, and safe to run before the mutation was applied.
#
# It removes the binary as well as restoring the file. A run that mutates the
# source, builds, and then dies -- Ctrl-C, or a second target in CHECK_TARGETS
# failing to compile -- leaves correct source beside a binary linked from the
# broken one, and every later check silently measures that. Rebuilding here
# would cost 22 seconds at the moment somebody is holding Ctrl-C down, so the
# binary goes instead: without it the next check stops with "not built" and the
# exact command, which is a loud failure rather than a quiet wrong answer.
_check_pr_restore() {
    [ -n "${_CHECK_PR_FILE:-}" ] || return 0
    local restore_status=0
    if ! cp -p "$_CHECK_PR_KEEP/original" "$_CHECK_PR_FILE" ||
       ! cmp -s "$_CHECK_PR_KEEP/original" "$_CHECK_PR_FILE"; then
        echo "INCONCLUSIVE: restore failed for $_CHECK_PR_FILE; original kept at $_CHECK_PR_KEEP/original. Restore it by hand." >&2
        restore_status=2
    fi
    _check_pr_remove_binaries
    [ "$restore_status" -eq 0 ] && _CHECK_PR_FILE=""
    return "$restore_status"
}

_check_pr_remove_binaries() {
    local target out
    for target in $CHECK_BUILT; do
        case "$target" in
            posix) out=incursion-headless ;;
            sdl)   out=incursion ;;
            *)     continue ;;
        esac
        [ -f "$CHECK_ROOT/$out" ] || continue
        rm -f "$CHECK_ROOT/$out"
        echo "  removed $out -- it may have been linked from the mutated $_CHECK_PR_FILE." >&2
        case "$target" in
            posix) echo "  Rebuild with: BACKEND=posix ./build_macos.sh" >&2 ;;
            sdl)   echo "  Rebuild with: ./build_macos.sh" >&2 ;;
        esac
    done
}

_check_prove_red() { # <file> <literal from> <literal to>
    local file="$1" from="$2" to="$3" keep inner target

    echo "  re-running $CHECK_SELF before mutation"
    ( unset CHECK_MUTATED; CHECK_PROVE_RED=0 "$CHECK_SELF" ${CHECK_ARGS[@]+"${CHECK_ARGS[@]}"} ) 2>&1 | sed 's/^/  | /'
    inner="${PIPESTATUS[0]}"
    [ "$inner" -eq 0 ] || _check_die 2 \
        "the check is not green to begin with (exit $inner); nothing is proved."

    keep="$(mktemp -d -t check_prove_red)" || _check_die 2 "no temp directory"
    cp -p "$file" "$keep/original" || _check_die 2 "could not copy $file aside"
    _CHECK_PR_FILE="$file"
    _CHECK_PR_KEEP="$keep"
    trap '_check_pr_restore || exit 2' EXIT
    trap '_check_pr_restore; exit 130' INT TERM HUP

    echo "--- prove red: $file ---"
    echo "  mutating   $file  (original copied to $keep/original)"
    echo "             this is the first mutation the check declares; a later"
    echo "             one is not reached by this run."
    _check_replace "$file" "$from" "$to" || _check_die 2 "the replacement failed"

    case "$file" in
        src/*|inc/*|lib/*)
            for target in $CHECK_TARGETS; do check_build "$target"; done ;;
        *)
            echo "  no rebuild: $file is not source, so the binary is unchanged" ;;
    esac

    echo "  re-running $CHECK_SELF with the fix broken"
    echo
    CHECK_MUTATED=1 "$CHECK_SELF" ${CHECK_ARGS[@]+"${CHECK_ARGS[@]}"} 2>&1 | sed 's/^/  | /'
    inner="${PIPESTATUS[0]}"
    echo

    echo "  restoring  $file"
    if ! cp -p "$keep/original" "$file" || ! cmp -s "$keep/original" "$file"; then
        _check_die 2 \
            "THE RESTORE DID NOT TAKE. $file does not match the copy it was" \
            "made from. Put it back by hand: cp '$keep/original' '$file'"
    fi
    _check_pr_remove_binaries
    trap - EXIT INT TERM HUP
    _CHECK_PR_FILE=""
    rm -rf "$keep"
    case "$file" in
        src/*|inc/*|lib/*)
            CHECK_BUILT=""
            for target in $CHECK_TARGETS; do check_build "$target"; done ;;
    esac

    echo
    # ONLY exit 1 is evidence. Every other code says something about the run
    # rather than about the defect, and reading them as red is how this
    # function would certify a check that never executed: a re-run that cannot
    # start exits 127, one without an execute bit 126, an interrupted one 130.
    # All three are "not 0", and all three used to print PROVED RED.
    case "$inner" in
        1) ;;
        0) _check_die 1 \
            "the check PASSED with the fix broken, so it is measuring nothing." \
            "Whatever it asserts is true whether the defect is there or not." \
            "Fix the check, not the code. (docs/VERIFICATION.md step 2)" ;;
        2) _check_die 2 \
            "the broken build could not be measured (exit 2), so this proves" \
            "nothing either way. Read the inner run above." ;;
        *) _check_die 2 \
            "the re-run exited $inner, which is neither pass (0), fail (1) nor" \
            "could-not-measure (2). It probably never ran. Nothing is proved." ;;
    esac
    echo "PROVED RED: with $file mutated, this check exits 1."
    echo "            Record the mutation and this line where the work is."
    exit 0
}

# ---------------------------------------------------------------------------
# check_done <one-line summary> -- print the verdict and exit.
check_done() { # <summary>
    local summary="${1:-}"
    echo
    if [ "$CHECK_FAIL" -ne 0 ]; then
        echo "FAIL: $summary"
        [ -n "$CHECK_RUN" ] && echo "      the screens are in $CHECK_RUN/logs/screens"
        exit 1
    fi
    # A check made only of check_reject passes on a session that never reached
    # the state it is watching, because the absent string is absent either way.
    if [ "$CHECK_EXPECTS" -eq 0 ] && [ "$CHECK_REJECTS" -gt 0 ]; then
        _check_die 2 \
            "every assertion in this check says a string is ABSENT, and nothing" \
            "says the run reached the state where it could have appeared. It" \
            "would pass on an empty cave. Add one check_expect that proves the" \
            "session got there."
    fi
    if [ "$CHECK_EXPECTS" -eq 0 ] && [ "$CHECK_REJECTS" -eq 0 ]; then
        _check_die 2 "this check asserted nothing at all."
    fi
    echo "PASS: $summary"
    [ -n "$CHECK_RUN" ] && echo "      ($CHECK_RUN/logs/screens)"
    exit 0
}

# ---------------------------------------------------------------------------
# The library proves itself: tools/check_lib.sh --selftest
#
# docs/VERIFICATION.md asks every checker to have one, because "a check that has
# quietly stopped checking anything looks exactly like a check that passes", and
# a shared library fails 214 checks at once rather than one. Nothing here builds
# or plays the game: the assertions read hand-written screen files, and the
# prove-red case mutates a file in a temp directory. It runs in about a second.

_st_pass=0
_st_fail=0

# Run one case in a subshell -- so its exit, its CHECK_FAIL and its temp state
# stay inside -- and compare the exit code and the output against what the case
# claims. Command substitution is the subshell.
_st() { # <want exit> <want text in output> <description> <function>
    local want="$1" grepfor="$2" desc="$3" fn="$4" out got
    out="$("$fn" 2>&1)"; got=$?
    if [ "$got" = "$want" ] && printf '%s' "$out" | grep -qF -- "$grepfor"; then
        printf 'selftest ok    %-52s -> exit %s\n' "$desc" "$got"
        _st_pass=$((_st_pass + 1))
    else
        printf 'selftest FAIL  %-52s -> exit %s (wanted %s, and %s)\n' \
            "$desc" "$got" "$want" "\"$grepfor\""
        printf '%s\n' "$out" | sed 's/^/               | /'
        _st_fail=$((_st_fail + 1))
    fi
}

_st_screens() { # write two screens into $ST_DIR and choose them
    printf 'You avoid harm to your orcish knife +1.\n' > "$ST_DIR/a.txt"
    printf 'The brown pudding hits you.\n'             > "$ST_DIR/b.txt"
    CHECK_SCREENS=("$ST_DIR/a.txt" "$ST_DIR/b.txt")
}

_st_c_expect_hit()     { _st_screens; check_expect "avoid harm to your"; check_done ok; }
_st_c_expect_empty() { _st_screens; check_expect ""; check_done ok; }
_st_c_expect_all_empty() { _st_screens; check_expect_all ""; check_done ok; }
_st_c_expect_miss()    { _st_screens; check_expect "nothing says this"; check_done ok; }
_st_c_expect_all_bad() { _st_screens; check_expect_all "avoid harm"; check_done ok; }
_st_c_expect_all_ok()  { _st_screens
                         printf 'shared\n' > "$ST_DIR/a.txt"
                         printf 'shared\n' > "$ST_DIR/b.txt"
                         check_expect_all "shared"; check_done ok; }
_st_c_reject_hit()     { _st_screens; check_expect "avoid harm"
                         check_reject "brown pudding"; check_done ok; }
_st_c_reject_clean()   { _st_screens; check_expect "avoid harm"
                         check_reject "protects its"; check_done ok; }
_st_c_reject_only()    { _st_screens; check_reject "protects its"; check_done ok; }
_st_c_asserts_nothing(){ _st_screens; check_done ok; }
_st_c_no_screens()     { CHECK_SCREENS=(); check_expect "anything"; }
_st_c_screens_empty()  { CHECK_RUN="$ST_DIR/empty"; mkdir -p "$CHECK_RUN/logs/screens"
                         check_screens '*-strike-*'; }
_st_c_no_options()     { CHECK_OPTIONS=""; check_run tools/keys/dive.keys 1; }
_st_c_no_seed()        { CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
                         check_run tools/keys/dive.keys; }
_st_c_no_keys()        { CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
                         check_run "$ST_DIR/not-a-key-script" 1; }

# Every ending tools/headless.sh can report, through the one function that
# judges them. No build and no session: _check_session_verdict takes the code
# as an argument, which is why it is a function at all.
_st_c_session_clean()    { CHECK_RUN=""; _check_session_verdict 0 && echo "read as a session"; }
_st_c_session_budget()   { CHECK_RUN=""; _check_session_verdict 3 && echo "read as a session"; }
_st_c_session_fatal()    { CHECK_RUN=""; _check_session_verdict 1; }
_st_c_session_watchdog() { CHECK_RUN=""; _check_session_verdict 4; }
_st_c_session_signal()   { CHECK_RUN=""; _check_session_verdict 139; }
_st_c_session_badkeys()  { CHECK_RUN=""; _check_session_verdict 2; }
_st_c_session_nomap()    { CHECK_RUN=""; _check_session_verdict 5; }
_st_c_session_notshown() { CHECK_RUN=""; _check_session_verdict 6; }
_st_c_session_assert()   { CHECK_RUN=""; _check_session_verdict 7; }

# A dead session says what the engine logged last, and says it without the call
# stack indented under it.
_st_c_session_errorlog() {
    mkdir -p "$ST_DIR/deadrun/logs"
    { printf '=== session 2026-09-11 09:21:36 ===\n'
      printf '2026-09-11 09:21:36  Probable parameter mismatch in __XPrint\n'
      printf '    0   incursion-headless  0x0000 _Z8__XPrint + 5656\n'
    } > "$ST_DIR/deadrun/logs/errors.log"
    CHECK_RUN="$ST_DIR/deadrun"
    _check_session_verdict 1
}

_st_c_mutation_absent() { printf 'alpha\n' > "$ST_DIR/m.txt"
                          check_mutation "$ST_DIR/m.txt" gone stillgone; }
_st_c_mutation_twice()  { printf 'alpha\nalpha\n' > "$ST_DIR/m.txt"
                          check_mutation "$ST_DIR/m.txt" alpha beta; }
_st_c_mutation_once()   { printf 'alpha\nbeta\n' > "$ST_DIR/m.txt"
                          check_mutation "$ST_DIR/m.txt" alpha gamma
                          echo "declared, and the file is untouched"
                          grep -q alpha "$ST_DIR/m.txt" || echo "MUTATED WHEN IT SHOULD NOT HAVE"; }

# The prove-red dance, end to end, on a check that reads a text file instead of
# playing the game. Two inner checks: one that reads the mutated line (so it
# goes red, which is what step 2 wants) and one that ignores it (so it stays
# green, which means it is measuring nothing and must be reported).
_st_fake_check() { # <path> <the assertion body>
    cat > "$1" <<FAKE
#!/bin/bash
. "$CHECK_LIB_DIR/check_lib.sh"
check_mutation "$ST_DIR/oracle.txt" 'THE FIX IS IN' 'THE FIX IS OUT'
$2
FAKE
    chmod +x "$1"
}

_st_c_prove_red_good() {
    printf 'THE FIX IS IN\n' > "$ST_DIR/oracle.txt"
    _st_fake_check "$ST_DIR/good.sh" \
        "grep -qF 'THE FIX IS IN' '$ST_DIR/oracle.txt' && exit 0 || exit 1"
    "$ST_DIR/good.sh" --prove-red
    local rc=$?
    grep -qF 'THE FIX IS IN' "$ST_DIR/oracle.txt" || echo "RESTORE FAILED"
    return $rc
}

_st_c_prove_red_always_bad() {
    printf 'THE FIX IS IN\n' > "$ST_DIR/oracle.txt"
    _st_fake_check "$ST_DIR/always-bad.sh" "exit 1"
    "$ST_DIR/always-bad.sh" --prove-red
}

_st_c_prove_red_blind() {
    printf 'THE FIX IS IN\n' > "$ST_DIR/oracle.txt"
    _st_fake_check "$ST_DIR/blind.sh" "exit 0"
    "$ST_DIR/blind.sh" --prove-red
    local rc=$?
    grep -qF 'THE FIX IS IN' "$ST_DIR/oracle.txt" || echo "RESTORE FAILED"
    return $rc
}

# A check whose re-run cannot start. 127 is what the shell reports when the
# path does not resolve, which is what `cd tools && ./check_x.sh --prove-red`
# produced before CHECK_SELF existed. It must not read as evidence.
_st_c_prove_red_unstartable() {
    printf 'THE FIX IS IN\n' > "$ST_DIR/oracle.txt"
    _st_fake_check "$ST_DIR/gone.sh" '[ "${CHECK_MUTATED:-0}" = 1 ] && exit 127; exit 0'
    "$ST_DIR/gone.sh" --prove-red
    local rc=$?
    grep -qF 'THE FIX IS IN' "$ST_DIR/oracle.txt" || echo "RESTORE FAILED"
    return $rc
}

# The same check, run from a directory that is neither the repository root nor
# the script's own. The library cd's to the root, so a check re-run by the name
# the caller typed would not be found.
_st_c_prove_red_elsewhere() {
    printf 'THE FIX IS IN\n' > "$ST_DIR/oracle.txt"
    _st_fake_check "$ST_DIR/away.sh" \
        "grep -qF 'THE FIX IS IN' '$ST_DIR/oracle.txt' && exit 0 || exit 1"
    cd / || return 2
    "$ST_DIR/away.sh" --prove-red
}

# The restore path on its own, including the half nothing else reaches: a run
# that mutated the source AND built from it must not leave that binary behind.
_st_c_restore_scraps_binary() {
    local fake="$ST_DIR/fakeroot"
    mkdir -p "$fake/keep"
    printf 'original\n' > "$fake/source.cpp"
    printf 'original\n' > "$fake/keep/original"
    printf 'mutated\n'  > "$fake/source.cpp"
    : > "$fake/incursion-headless"
    CHECK_ROOT="$fake" CHECK_BUILT=" posix" \
        _CHECK_PR_FILE="$fake/source.cpp" _CHECK_PR_KEEP="$fake/keep" \
        _check_pr_restore 2>/dev/null
    grep -qF original "$fake/source.cpp" || { echo "the source was not restored"; return 1; }
    [ -f "$fake/incursion-headless" ] && { echo "the mutated binary is still there"; return 1; }
    echo "source restored and the mutated binary removed"
    return 0
}

_check_selftest() {
    ST_DIR="$(mktemp -d -t check_lib_selftest)" || return 2
    trap 'rm -rf "$ST_DIR"' EXIT

    _st 2 'check_expect: empty assertion' 'empty check_expect is a caller error' _st_c_expect_empty
    _st 2 'check_expect_all: empty assertion' 'empty check_expect_all is a caller error' _st_c_expect_all_empty
    _st 2 'not green to begin with (exit 1)' 'prove-red rejects an already failing check' _st_c_prove_red_always_bad
    _st 0 'ok    1/2' 'a string on one screen satisfies check_expect' _st_c_expect_hit
    _st 1 'FAIL  0/2'  'a string on no screen fails check_expect'      _st_c_expect_miss
    _st 1 'only 1 of 2' 'check_expect_all needs every screen'          _st_c_expect_all_bad
    _st 0 'ok    2/2'  'check_expect_all passes when every screen has it' _st_c_expect_all_ok
    _st 1 'still carry' 'check_reject fails on a screen that has it'   _st_c_reject_hit
    _st 0 'PASS'       'check_reject passes when no screen has it'     _st_c_reject_clean
    _st 2 'ABSENT'     'rejects with no expect is INCONCLUSIVE'        _st_c_reject_only
    _st 2 'asserted nothing' 'a check with no assertion is INCONCLUSIVE' _st_c_asserts_nothing
    _st 2 'no screens are chosen' 'asserting before check_screens stops' _st_c_no_screens
    _st 2 'matches'    'check_screens with no matching dump stops'     _st_c_screens_empty
    _st 2 'CHECK_OPTIONS is unset' 'a run with unnamed settings stops' _st_c_no_options
    _st 2 'pin its seed' 'a run with no seed stops'                    _st_c_no_seed
    _st 2 'no such key script' 'a run with no key script stops'        _st_c_no_keys

    _st 0 'read as a session' 'a clean ending is a session'            _st_c_session_clean
    _st 0 'read as a session' 'the key budget running out is a session' _st_c_session_budget
    _st 1 'the game died'  'a Fatal() session FAILS, it is not a shrug' _st_c_session_fatal
    _st 1 'the game died'  'a watchdog stop FAILS'                     _st_c_session_watchdog
    _st 1 'the game died'  'a killing signal FAILS'                    _st_c_session_signal
    _st 1 'Probable parameter mismatch' 'a dead session quotes its error log' _st_c_session_errorlog
    _st 2 'measured nothing' 'an unreadable key script stays INCONCLUSIVE' _st_c_session_badkeys
    _st 2 'measured nothing' 'NO GAMEPLAY stays INCONCLUSIVE'          _st_c_session_nomap
    _st 2 'measured nothing' 'an @expect that found nothing stays INCONCLUSIVE' _st_c_session_notshown
    _st 2 'measured nothing' 'an unlisted ASSERT stays INCONCLUSIVE'   _st_c_session_assert

    _st 2 'appears 0 times' 'a mutation whose text is gone stops'      _st_c_mutation_absent
    _st 2 'appears 2 times' 'an ambiguous mutation stops'              _st_c_mutation_twice
    _st 0 'file is untouched' 'declaring a mutation changes nothing'   _st_c_mutation_once

    _st 0 'PROVED RED'  'prove-red passes when the check goes red'     _st_c_prove_red_good
    _st 1 'measuring nothing' 'prove-red fails a check that cannot go red' _st_c_prove_red_blind
    _st 2 'never ran'   'a re-run that cannot start is not evidence'    _st_c_prove_red_unstartable
    _st 0 'PROVED RED'  'prove-red finds the check from any directory'  _st_c_prove_red_elsewhere
    _st 0 'binary removed' 'the restore undoes the build, not just the file' _st_c_restore_scraps_binary

    echo
    echo "selftest: $_st_pass passed, $_st_fail failed"
    [ "$_st_fail" -eq 0 ]
}

# Sourced by a check, or run on its own? Only the second does anything.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        --selftest) _check_selftest; exit $? ;;
        *) echo "tools/check_lib.sh is sourced by a check, not run."
           echo "Read the header for what a check looks like."
           echo "  tools/check_lib.sh --selftest    prove the library still works"
           exit 2 ;;
    esac
fi
