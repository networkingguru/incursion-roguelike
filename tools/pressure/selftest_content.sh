#!/bin/bash
# Self-test of the containment rule of tools/pressure/content_check.sh (inc-cjos0 phase 9, A5): a content save is
# loaded only in a tree that holds the commit that planted it. Runs the real content_check.sh with a stub observer
# and comparer, in a throwaway git repository; it builds nothing and loads no save.
#   tools/pressure/selftest_content.sh        exit 0 pass, 1 fail
# fact: the repository and the saves -- made up in this script; no game, no seed, no machine load
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/incursion-selftest-content.XXXXXX")"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tools" "$T/repo" "$T/content"
cp "$HERE/content_check.sh" "$T/tools/"
printf '#!/bin/bash\necho "s f uint f=1" > "$3"\n' > "$T/tools/field_values.sh"
printf '#!/bin/bash\nexit 0\n' > "$T/tools/compare_values.py"
chmod +x "$T/tools/"*
g() { git -C "$T/repo" -c user.name=t -c user.email=t@t "$@"; }
g init -q -b m || exit 1
echo 1 > "$T/repo/f"; g add f; g commit -q -m base || exit 1
g checkout -q -b side; echo 2 > "$T/repo/f"; g commit -qam side || exit 1
SIDE="$(g rev-parse HEAD)"
g checkout -q m
for tag in P B; do : > "$T/content/$tag.sav"; echo x > "$T/content/$tag.txt"; : > "$T/content/$tag.scored"; done
echo "$SIDE" > "$T/content/B.commit"
fail=0
out="$("$T/tools/content_check.sh" "$T/repo" "$T/content" "$T/out1" 2>&1)"; rc=$?
echo "$out" | grep -q "content save B skipped" && echo "$out" | grep -q "^content: PASS -- 1 content saves load.*1 not in this tree" && [ $rc -eq 0 ] \
    && echo "ok   a tree without the planting commit skips the save (rc $rc)" || { echo "FAIL a tree without the planting commit: rc $rc: $out"; fail=1; }
g merge -q --no-edit side > /dev/null 2>&1
out="$("$T/tools/content_check.sh" "$T/repo" "$T/content" "$T/out2" 2>&1)"; rc=$?
echo "$out" | grep -q "^content: PASS -- 2 content saves load" && [ $rc -eq 0 ] \
    && echo "ok   a tree that holds the commit loads the save (rc $rc)" || { echo "FAIL a tree that holds the commit: rc $rc: $out"; fail=1; }
echo "0000000000000000000000000000000000000000" > "$T/content/B.commit"
out="$("$T/tools/content_check.sh" "$T/repo" "$T/content" "$T/out3" 2>&1)"; rc=$?
[ $rc -eq 2 ] && echo "ok   a commit git cannot place is UNMEASURED, not a skip (rc $rc)" || { echo "FAIL an unknown commit: rc $rc: $out"; fail=1; }
[ $fail -eq 0 ] && echo "content_check selftest: PASS" || echo "content_check selftest: FAIL"
exit $fail
