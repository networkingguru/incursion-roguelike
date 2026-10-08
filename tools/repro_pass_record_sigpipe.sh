#!/usr/bin/env bash
# Repro for inc-g9wz: tools/check_pass_record.sh's says() used
# `printf '%s\n' "$OUT" | grep -q -- "$1"`. grep -q exits at its first match,
# printf then dies of SIGPIPE, pipefail makes the pipeline non-zero, and says
# returns false for text that DOES match. This script extracts the single says()
# line from the check and drives it against a large OUT whose first line matches.
set -uo pipefail

file="${1:-tools/check_pass_record.sh}"

if [ ! -r "$file" ]; then
    printf '%s: cannot read\n' "$file" >&2
    exit 2
fi

says_line="$(grep -n -m1 '^says() {' -- "$file")" || {
    printf '%s: no says() line found\n' "$file" >&2
    exit 2
}
says_line="${says_line#*:}"
eval "$says_line"

NEEDLE="NEEDLE_inc_g9wz_$$"
OUT="$NEEDLE
$(seq 1 20000 | sed 's/^/filler line /')"

misses=0
i=0
while [ "$i" -lt 20 ]; do
    if ! says NEEDLE; then
        misses=$(( misses + 1 ))
    fi
    i=$(( i + 1 ))
done

printf '%s: %d/20 false misses\n' "$file" "$misses"
[ "$misses" -eq 0 ] && exit 0
exit 1
