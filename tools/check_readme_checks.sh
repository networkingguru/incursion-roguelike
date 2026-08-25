#!/usr/bin/env bash
#
# Does every regression check have a row in the README's check table?
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
# Exit: 0 every new check is documented
#       1 a check outside the baseline has no row
#       2 could not measure

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="$ROOT/tools/readme_checks.baseline"

# Not game checks, so not in the game-check table.
#   check_gate.sh       checks the gate, which the README says in the table's own
#                       preamble.
#   *_cron.sh           schedulers, documented in tools/README.md under
#                       Diagnostics rather than as regression checks.
exempt() {
    case "$1" in
        check_gate.sh|*_cron.sh) return 0 ;;
        *) return 1 ;;
    esac
}

# Echo every check script that has no row in the given README.
undocumented() {
    local readme="$1" dir="$2" f name
    for f in "$dir"/check_*.sh "$dir"/check_*.py; do
        [ -e "$f" ] || continue
        name="$(basename "$f")"
        exempt "$name" && continue
        grep -qF "\`$name\`" "$readme" || echo "$name"
    done
}

if [ "${1:-}" = "--selftest" ]; then
    tmp="$(mktemp -d)" || exit 2
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/tools"
    : > "$tmp/tools/check_documented.sh"
    : > "$tmp/tools/check_missing.sh"
    : > "$tmp/tools/check_gate.sh"
    printf '| `check_documented.sh` | it is here |\n' > "$tmp/README.md"

    got="$(undocumented "$tmp/README.md" "$tmp/tools")"
    st=0
    printf '%s\n' "$got" | grep -qx 'check_missing.sh' || {
        echo "SELFTEST FAIL: did not report an undocumented check"; st=1; }
    printf '%s\n' "$got" | grep -qx 'check_documented.sh' && {
        echo "SELFTEST FAIL: reported a check that has a row"; st=1; }
    printf '%s\n' "$got" | grep -qx 'check_gate.sh' && {
        echo "SELFTEST FAIL: reported the exempt check_gate.sh"; st=1; }

    [ "$st" -eq 0 ] && echo "SELFTEST PASS: check_readme_checks.sh sees all three cases"
    exit "$st"
fi

[ -f "$ROOT/README.md" ] || { echo "no README.md" >&2; exit 2; }

now="$(undocumented "$ROOT/README.md" "$ROOT/tools" | sort)"

if [ "${1:-}" = "--record" ]; then
    {
        echo "# Checks with no row in the README table, frozen 2026-08-25."
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
    echo "Add a row to the table under \"### The checks\" in README.md."
    exit 1
fi
echo "PASS: no check was added without a row"
exit 0
