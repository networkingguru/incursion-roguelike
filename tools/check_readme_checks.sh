#!/usr/bin/env bash
# gate: cheap
#
# Does every regression check have a row in tools/README.md's check table?
#
#   tools/check_readme_checks.sh              compare against the baseline
#   tools/check_readme_checks.sh --record     re-freeze the baseline
#   tools/check_readme_checks.sh --selftest   prove this script still bites
#
# WHY THIS EXISTS. On 2026-08-25, tools/ held 99 check scripts and the README
# table listed 40. The one document an outsider reads understated the work by
# sixty per cent, and nothing noticed, because adding a check and documenting it
# are two separate acts and only one of them is habit.
#
# A RATCHET, NOT A SWEEP. Draining the 59 missing rows needs a sentence per check
# that says what the check defends, which is judgement and not a script's job.
# So this check fails on a check added AFTER the baseline with no row, and stays
# quiet about the backlog. tools/readme_checks.baseline is that backlog. Delete
# lines from it as rows are written; never add lines by hand.
#
# On 2026-09-18 the table moved from README.md to tools/README.md (bead
# inc-3c2l), because a row per fix made the player-facing README grow with
# every change.
#
# A MATCH COUNTS ONLY INSIDE "### The regression checks". Measured the same
# day (inc-3c2l): 32 of the 265 checks are also named elsewhere in
# tools/README.md -- prose, another table's row -- so a whole-file grep saw
# them as documented while deleting their real row still passed. Restricting
# the match to the section is what makes that deletion visible again.
#
# Exit: 0 every new check is documented
#       1 a check outside the baseline has no row
#       2 could not measure

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="$ROOT/tools/readme_checks.baseline"

# Not game checks, so not in the game-check table.
#   check_gate.sh       checks the gate, which the README says in the table's own
#                       preamble.
#   check_lib.sh        the shared library other checks source (bd inc-le1m). It
#                       defends no defect and cannot be run as a check -- it
#                       prints usage and exits 2 -- so a row in a table of
#                       regression checks would misdescribe it. It is documented
#                       in tools/README.md and proves itself with --selftest.
#   *_cron.sh           schedulers, documented in tools/README.md under
#                       Diagnostics rather than as regression checks.
exempt() {
    case "$1" in
        check_gate.sh|check_lib.sh|*_cron.sh) return 0 ;;
        *) return 1 ;;
    esac
}

SECTION_HEADING='### The regression checks'

# True (exit 0) if $1 has the section heading at all.
have_section() {
    grep -qF "$SECTION_HEADING" "$1"
}

# True (exit 0) if a line INSIDE the "### The regression checks" section of
# $2 begins with "| `$1` |". The section runs from the heading to the next
# line that begins with "#". Matched as a fixed string (awk substr, not a
# regex), because a check name contains "." and must not be read as one.
row_in_section() {
    local name="$1" readme="$2"
    awk -v target="| \`${name}\` |" -v heading="$SECTION_HEADING" '
        index($0, heading) == 1 { insec=1; next }
        insec && substr($0, 1, 1) == "#" { insec=0 }
        insec && substr($0, 1, length(target)) == target { found=1 }
        END { exit !found }
    ' "$readme"
}

# Echo every check script that has no row in the section of the given README.
undocumented() {
    local readme="$1" dir="$2" f name
    for f in "$dir"/check_*.sh "$dir"/check_*.py; do
        [ -e "$f" ] || continue
        name="$(basename "$f")"
        exempt "$name" && continue
        row_in_section "$name" "$readme" || echo "$name"
    done
}

if [ "${1:-}" = "--selftest" ]; then
    tmp="$(mktemp -d)" || exit 2
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/tools"
    : > "$tmp/tools/check_documented.sh"
    : > "$tmp/tools/check_missing.sh"
    : > "$tmp/tools/check_gate.sh"
    : > "$tmp/tools/check_outside.sh"
    {
        printf '### The regression checks\n\n'
        printf '| `check_documented.sh` | it is here |\n'
        printf '\ncheck_outside.sh is mentioned here, in prose, not a row.\n\n'
        printf '### Something else\n\n'
        printf '| `check_outside.sh` | named only outside the section |\n'
    } > "$tmp/README.md"

    got="$(undocumented "$tmp/README.md" "$tmp/tools")"
    st=0
    printf '%s\n' "$got" | grep -qx 'check_missing.sh' || {
        echo "SELFTEST FAIL: did not report an undocumented check"; st=1; }
    printf '%s\n' "$got" | grep -qx 'check_documented.sh' && {
        echo "SELFTEST FAIL: reported a check that has a row"; st=1; }
    printf '%s\n' "$got" | grep -qx 'check_gate.sh' && {
        echo "SELFTEST FAIL: reported the exempt check_gate.sh"; st=1; }
    printf '%s\n' "$got" | grep -qx 'check_outside.sh' || {
        echo "SELFTEST FAIL: did not report a check named only outside the section"; st=1; }

    # Case 5 (rule 2): a document with no such heading makes the script exit 2.
    tmp5="$(mktemp -d)" || exit 2
    mkdir -p "$tmp5/tools"
    cp "$0" "$tmp5/tools/check_readme_checks.sh"
    printf 'no such section here\n' > "$tmp5/tools/README.md"
    ( cd "$tmp5" && bash tools/check_readme_checks.sh ) >/dev/null 2>&1
    rc5=$?
    rm -rf "$tmp5"
    [ "$rc5" -eq 2 ] || {
        echo "SELFTEST FAIL: a document with no heading did not exit 2 (got $rc5)"; st=1; }

    [ "$st" -eq 0 ] && echo "SELFTEST PASS: check_readme_checks.sh sees all four cases"
    exit "$st"
fi

[ -f "$ROOT/tools/README.md" ] || { echo "no tools/README.md" >&2; exit 2; }
have_section "$ROOT/tools/README.md" || {
    echo "tools/README.md has no \"$SECTION_HEADING\" section" >&2
    exit 2
}

now="$(undocumented "$ROOT/tools/README.md" "$ROOT/tools" | sort)"

if [ "${1:-}" = "--record" ]; then
    {
        echo "# Checks with no row in tools/README.md, frozen 2026-08-25."
        echo "# Draining this file is bd inc-5ysg follow-up work. Delete a line"
        echo "# when you write its row. Never add a line by hand."
        printf '%s\n' "$now"
    } > "$BASELINE"
    echo "recorded $(printf '%s\n' "$now" | grep -c .) undocumented check(s)"
    exit 0
fi

[ -f "$BASELINE" ] || { echo "missing $BASELINE; run --record" >&2; exit 2; }

base="$(grep -vE '^\s*(#|$)' "$BASELINE" | sort)"
new="$(comm -23 <(printf '%s\n' "$now") <(printf '%s\n' "$base"))"

echo "check_readme_checks: $(printf '%s\n' "$base" | grep -c .) known undocumented, backlog"

if [ -n "$new" ]; then
    echo "FAIL: these checks were added without a README row:"
    printf '  %s\n' $new
    echo "Add a row to the table under \"### The regression checks\" in tools/README.md, in alphabetical order."
    exit 1
fi
echo "PASS: no check was added without a row"
exit 0
