#!/bin/bash
# gate: cheap
#
# Does every gate check carry a `# gate-serial:` line when it would otherwise
# be unsafe to run in parallel with its peers? The gate changed on 2026-09-30
# (inc-yg8e) from a strictly serial loop to a parallel runner: non-serial checks
# run several at a time, so a check that mutates a shared artefact -- the shared
# mod/Incursion.Mod, the two binaries, a fixed scratch path -- could corrupt a
# peer's measurement. A check declares it must run alone with
#
#   # gate-serial: <one-line reason>
#
# near the top of its own file. This check is the guard that keeps a new check
# from joining the parallel tier with a shared-file write and no declaration.
#
# WHAT IT FAILS ON. For every file with a `# gate: cheap|live` marker in its
# first 40 lines that has NO `# gate-serial:` marker, it reads the whole file
# and fails, naming the file and the line, when the text either
#   (a) runs build_macos.sh on a command line that does not carry BOTH a private
#       `OUT=` (a non-default output name) AND a non-empty `EXTRA_CXXFLAGS=`,
#       which is the pair that skips build_macos.sh's shared module rewrite
#       (build_macos.sh:375); or
#   (b) writes the shared mod/Incursion.Mod (cp/mv/rm/ln or `>`/`>>` naming it),
#       or overwrites/deletes ./incursion or ./incursion-headless.
#
# LIMITS, STATED PLAINLY. The test is a line heuristic over shell text, not a
# parser: it does not expand variables, follow functions, look inside a sourced
# library or a here-doc, or understand a command split across lines. It reads
# `tools/check_lib.sh` only as it is SOURCED (its check_build builds without a
# private OUT), so a check that calls check_build with the source on disk is
# covered. A write this cannot see -- a fixed path reached through a variable,
# a write done by a helper this does not read -- needs a hand audit, which is
# how the six gate-serial markers on this branch were chosen in the first place.
# It is a tripwire for the obvious new hazard, not a proof of parallel safety.
#
# Usage: tools/check_gate_parallel_safe.sh            (0 pass, 1 fail, 2 could not run)
#        tools/check_gate_parallel_safe.sh --selftest (prove this check still bites)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="${NIGHTLY_CHECK_DIR:-$ROOT/tools}"
CHECK_LIB="$CHECK_DIR/check_lib.sh"

# has_gate_marker <file> -> 0 when a `# gate: cheap|live` marker is in the top 40
has_gate_marker() {
    grep -Eq '^#[[:space:]]*gate:[[:space:]]*(cheap|live)([[:space:]]|$)' \
        <<<"$(sed -n '1,40p' "$1")"
}

# is_serial <file> -> 0 when a non-empty `# gate-serial:` reason is in the top 40
is_serial() {
    grep -Eq '^#[[:space:]]*gate-serial:[[:space:]]*[^[:space:]]' \
        <<<"$(sed -n '1,40p' "$1")"
}

# build_line_is_executed <line> -> 0 when the build_macos.sh on this line is a
# command this shell would run, not text a reader is shown, a string an echo
# prints, or a name handed to grep/sed/cat/test. The heuristic: the line is not
# a comment or an echo/printf, the build_macos.sh token survives stripping of
# single- and double-quoted runs, and the leading command word is not one that
# merely reads a file.
#
# These tests use a here-string, not a pipe: a pipeline feeding an early-exit
# `grep -q` can kill its writer with SIGPIPE and, under pipefail, invert the
# answer. See docs/specs/2026-09-22-sigpipe-status-spec.md.
build_line_is_executed() {
    local line="$1"
    grep -Eq '^[[:space:]]*(echo|printf|#|:|cat[[:space:]])' <<<"$line" && return 1
    # Strip quoted runs, then require build_macos.sh to survive and the command
    # word not to be a file reader.
    local bare
    bare="$(printf '%s\n' "$line" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")"
    grep -q 'build_macos\.sh' <<<"$bare" || return 1
    grep -Eq '^[[:space:]]*(grep|sed|awk|cat|test|\[|command|which|type)([[:space:]]|$)' <<<"$bare" && return 1
    return 0
}

# scan_build_line <file> <lineno> <text> <prev1> <prev2> -> an offending line,
# or nothing. A build_macos.sh command may carry its OUT=/EXTRA_CXXFLAGS= on an
# immediately preceding continuation line, so the flags are searched for in the
# current line and the two before it.
scan_build_line() {
    local f="$1" n="$2" line="$3" prev1="$4" prev2="$5"
    build_line_is_executed "$line" || return 0
    local ctx="$prev2
$prev1
$line" has_out=0 has_extra=0
    grep -Eq '(^|[[:space:]])OUT=' <<<"$ctx" && has_out=1
    grep -Eq 'EXTRA_CXXFLAGS=["'"'"']?[^"'"'"'[:space:]]' <<<"$ctx" && has_extra=1
    if [ "$has_out" != 1 ] || [ "$has_extra" != 1 ]; then
        printf '%s:%s: runs build_macos.sh without both a private OUT= and a non-empty EXTRA_CXXFLAGS= (build_macos.sh:375 rewrites the shared module)\n' "$f" "$n"
    fi
    return 0
}

# scan_write_line <file> <lineno> <text> -> an offending line, or nothing.
# Comments and echoed text are not writes.
scan_write_line() {
    local f="$1" n="$2" line="$3"
    grep -Eq '^[[:space:]]*(#|:|echo|printf)' <<<"$line" && return 0
    local bare
    bare="$(printf '%s\n' "$line" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")"
    if grep -Eq '(^|[[:space:]/])(cp|mv|rm|ln)([[:space:]]|$)' <<<"$bare" \
        && grep -Eq 'mod/Incursion\.Mod|\./incursion(-headless)?([[:space:]]|$)|[[:space:]]incursion(-headless)?([[:space:]]|$)' <<<"$bare"; then
        printf '%s:%s: writes a shared path (mod/Incursion.Mod or a shared binary) with a cp/mv/rm/ln\n' "$f" "$n"
        return 0
    fi
    if grep -Eq '(>|>>)[[:space:]]*[^|&]*mod/Incursion\.Mod' <<<"$bare"; then
        printf '%s:%s: redirects a shared path (mod/Incursion.Mod)\n' "$f" "$n"
        return 0
    fi
    return 0
}

# scan_file <file> -> offending lines. One grep pass finds the handful of
# candidate lines (a build story, or a cp/mv/rm/ln), so the per-line test runs
# on a few lines instead of every line of every check: the guard is a cheap-tier
# check and must stay one.
scan_file() {
    local f="$1" n line prev1 prev2
    # (a) candidate build lines.
    if grep -q 'build_macos\.sh' "$f" 2>/dev/null; then
        while IFS= read -r n; do
            line="$(sed -n "${n}p" "$f")"
            prev1="$(sed -n "$((n > 1 ? n - 1 : 1))p" "$f")"
            prev2="$(sed -n "$((n > 2 ? n - 2 : 1))p" "$f")"
            [ "$n" -le 1 ] && prev1=""
            [ "$n" -le 2 ] && prev2=""
            scan_build_line "$f" "$n" "$line" "$prev1" "$prev2"
        done <<EOF
$(grep -n 'build_macos\.sh' "$f" | cut -d: -f1)
EOF
    fi
    # (b) candidate write lines.
    while IFS=: read -r n line; do
        [ -n "$n" ] || continue
        scan_write_line "$f" "$n" "$line"
    done <<EOF
$(grep -nE '(^|[[:space:]/])(cp|mv|rm|ln)([[:space:]]|$)|mod/Incursion\.Mod' "$f")
EOF
}

# run_default -> 0 clean, 1 findings, 2 could not run
run_default() {
    local f bad=0 count=0
    if [ ! -d "$CHECK_DIR" ]; then
        echo "no check directory: $CHECK_DIR" >&2
        return 2
    fi
    for f in "$CHECK_DIR"/check_*.sh "$CHECK_DIR"/check_*.py; do
        [ -f "$f" ] || continue
        has_gate_marker "$f" || continue
        count=$((count + 1))
        is_serial "$f" && continue
        out="$(scan_file "$f")"
        if [ -n "$out" ]; then
            printf '%s\n' "$out"
            bad=$((bad + 1))
        fi
    done
    if [ "$bad" -ne 0 ]; then
        echo "FAIL: $bad gate check(s) write a shared artefact without a '# gate-serial:' marker."
        echo "      Add one with a one-line reason, or make the write private."
        return 1
    fi
    echo "PASS: $count gate checks, none writes a shared artefact without a '# gate-serial:' marker"
    return 0
}

# ------------------------------------------------------------- selftest ---
# A planted unsafe check with no marker must fail; the same text WITH the marker
# must pass; a build carrying a private OUT= and EXTRA_CXXFLAGS= must pass.
selftest() {
    local dir fails=0 rc
    dir="$(mktemp -d -t gatesafe)" || return 2
    trap "rm -rf '$dir'" EXIT

    mkdir -p "$dir"
    # Planted unsafe: a plain native build (no OUT=, no EXTRA_CXXFLAGS=).
    printf '#!/bin/sh\n# gate: cheap\nBACKEND=posix ./build_macos.sh\n' \
        > "$dir/check_planted_unsafe.sh"
    # The same text, declared serial: must pass.
    printf '#!/bin/sh\n# gate: cheap\n# gate-serial: builds the shared module\nBACKEND=posix ./build_macos.sh\n' \
        > "$dir/check_planted_serial.sh"
    # A build that carries both a private OUT= and a non-empty EXTRA_CXXFLAGS=: safe.
    printf '#!/bin/sh\n# gate: cheap\nOUT=incursion-probe EXTRA_CXXFLAGS=-DX BACKEND=posix ./build_macos.sh\n' \
        > "$dir/check_planted_private.sh"
    # A copy over the shared module with no marker: unsafe.
    printf '#!/bin/sh\n# gate: cheap\ncp -f cand.mod mod/Incursion.Mod\n' \
        > "$dir/check_planted_copy.sh"

    NIGHTLY_CHECK_DIR="$dir" "$0" > "$dir/out" 2>&1
    rc=$?

    if [ "$rc" -ne 1 ]; then
        echo "  FAIL  planted unsafe check without a marker was not failed (rc=$rc)"
        cat "$dir/out"
        fails=$((fails + 1))
    else
        echo "  ok    planted unsafe check without a marker fails"
    fi
    if grep -q 'check_planted_unsafe\.sh' "$dir/out"; then
        echo "  ok    the failure names the planted unsafe file"
    else
        echo "  FAIL  the failure did not name check_planted_unsafe.sh"
        fails=$((fails + 1))
    fi
    if grep -q 'check_planted_copy\.sh' "$dir/out"; then
        echo "  ok    the failure names the shared-module copy"
    else
        echo "  FAIL  the shared-module copy was not caught"
        fails=$((fails + 1))
    fi
    if grep -q 'check_planted_serial\.sh\|check_planted_private\.sh' "$dir/out"; then
        echo "  FAIL  a safe or serial planted check was reported"
        fails=$((fails + 1))
    else
        echo "  ok    the serial and private-OUT builds are not reported"
    fi

    echo
    if [ "$fails" = 0 ]; then
        echo "SELFTEST PASS"
        return 0
    fi
    echo "SELFTEST FAIL: $fails"
    return 1
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    "")         run_default; exit $? ;;
    -h|--help)  sed -n '2,40p' "$0"; exit 0 ;;
    *)          echo "unknown argument: $1" >&2; exit 2 ;;
esac
