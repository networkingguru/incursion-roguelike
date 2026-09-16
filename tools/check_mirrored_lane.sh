#!/bin/bash
# gate: cheap --selftest
#
# Does tools/sync_issues.sh keep a `mirrored` bead out of everything that
# WRITES to GitHub, while still reconciling its state?
#
# WHY THIS EXISTS. A `mirrored` bead points at an issue somebody outside this
# project filed. The full sync refreshes titles and descriptions, so a mirrored
# bead reaching `bd github sync` would replace a stranger's bug report and
# their screenshots with this project's text. On 2026-09-16 that was one label
# away from happening to GitHub 507 and 508; a --dry-run caught it. See bead
# inc-rza6 and "Every bead carries `public`, `internal` or `mirrored`" in
# AGENTS.md.
#
# The danger is silent. Nothing in a successful sync run says which ids were
# written, so a regression here looks exactly like a healthy push until
# somebody opens the reporter's issue and finds it gone. So this check drives
# the REAL script with `bd` and `gh` stubbed on PATH, and reads the id list the
# script actually handed to `bd github sync`.
#
# It asserts what a person cannot see:
#   1. a mirrored bead never reaches `bd github sync`
#   2. a public bead still does
#   3. a mirrored bead IS in the reconciliation set, so closing the bead still
#      closes the reporter's issue
#   4. a mirrored bead pointing at a rehearsal repository is refused, the same
#      as a public one
#
#   tools/check_mirrored_lane.sh            run the check
#   tools/check_mirrored_lane.sh --selftest prove the check still bites
#
# Exit: 0 the lane holds
#       1 a mirrored bead reached the write path, or fell out of the state path
#       2 could not measure

set -uo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
selftest=""
[ "${1:-}" = "--selftest" ] && selftest=1

work=$(mktemp -d -t check_mirrored_lane) || {
    echo "check_mirrored_lane: no temp dir" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT

# The fixture: two public beads, two mirrored, one of each already linked.
cat > "$work/beads.json" <<'JSON'
[
 {"id":"inc-pub1","status":"open","labels":["public","upstream"],
  "external_ref":"https://github.com/networkingguru/incursion-roguelike/issues/101",
  "title":"a public bead with an issue","description":"x"},
 {"id":"inc-pub2","status":"open","labels":["public"],
  "external_ref":"","title":"a public bead with no issue yet","description":"x"},
 {"id":"inc-mir1","status":"open","labels":["mirrored"],
  "external_ref":"https://github.com/networkingguru/incursion-roguelike/issues/508",
  "title":"an outside report","description":"x"},
 {"id":"inc-mir2","status":"closed","labels":["mirrored"],
  "external_ref":"https://github.com/networkingguru/incursion-roguelike/issues/507",
  "title":"an outside report we fixed","description":"x"}
]
JSON

# check_upstream_label.sh runs before the push and compares the REAL ledger in
# docs/REPORTING-GATE.md against the bead label set. Stubbing that query would
# make every ledger row look unlabelled and stop the run at exit 2, so the stub
# hands this one query to the real bd. Everything this check measures is
# downstream of it.
real_bd=$(command -v bd) || {
    echo "check_mirrored_lane: bd is not on PATH" >&2; exit 2; }

make_stubs() {
    mkdir -p "$work/bin"
    cat > "$work/bin/bd" <<STUB
#!/bin/bash
# Records the --issues list, and answers the three reads the script makes.
if [ "\${1:-}" = "github" ]; then
    while [ \$# -gt 0 ]; do
        [ "\$1" = "--issues" ] && { echo "\$2" > "$work/pushed"; }
        shift
    done
    exit 0
fi
if [ "\${1:-}" = "list" ]; then
    case "\$*" in
        *"--label upstream"*) exec "$real_bd" -C "$repo_root" "\$@" ;;
        *) cat "$work/beads.json" ;;
    esac
    exit 0
fi
exit 0
STUB
    cat > "$work/bin/gh" <<STUB
#!/bin/bash
# The reconciliation lists issues, then closes or reopens. Record the verbs.
if [ "\${1:-}" = "issue" ] && [ "\${2:-}" = "list" ]; then
    echo '[{"number":101,"state":"OPEN"},{"number":508,"state":"OPEN"},{"number":507,"state":"OPEN"}]'
    exit 0
fi
if [ "\${1:-}" = "issue" ]; then
    echo "\$2 \$3" >> "$work/gh-verbs"
    exit 0
fi
exit 0
STUB
    chmod +x "$work/bin/bd" "$work/bin/gh"
}

make_stubs
rm -f "$work/pushed" "$work/gh-verbs"

# GITHUB_TOKEN is set so the script never asks the real `gh` for one.
out=$(cd "$repo_root" && PATH="$work/bin:$PATH" GITHUB_TOKEN=stub \
      SYNC_REPO=networkingguru/incursion-roguelike \
      ./tools/sync_issues.sh 2>&1)
rc=$?

pushed=$(cat "$work/pushed" 2>/dev/null || echo "")
verbs=$(cat "$work/gh-verbs" 2>/dev/null || echo "")

fail=0
say() { echo "check_mirrored_lane: $*" >&2; fail=1; }

if [ "$rc" -ne 0 ]; then
    echo "check_mirrored_lane: the script exited $rc; cannot measure" >&2
    echo "$out" >&2
    exit 2
fi
if [ -z "$pushed" ]; then
    echo "check_mirrored_lane: the script never called 'bd github sync'" >&2
    echo "$out" >&2
    exit 2
fi

# 1. No mirrored bead in the list that reaches bd github sync.
case ",$pushed," in
    *",inc-mir1,"*) say "inc-mir1 (mirrored) reached 'bd github sync'. It would" \
                        "overwrite the reporter's issue." ;;
esac
case ",$pushed," in
    *",inc-mir2,"*) say "inc-mir2 (mirrored) reached 'bd github sync'. It would" \
                        "overwrite the reporter's issue." ;;
esac

# 2. Public beads still reach it, or the lane has suppressed the wrong thing.
for want in inc-pub1 inc-pub2; do
    case ",$pushed," in
        *",$want,"*) ;;
        *) say "$want (public) did NOT reach 'bd github sync'" ;;
    esac
done

# 3. The closed mirrored bead still closes its issue: state is reconciled even
#    though the body is not written. This is the half a naive fix drops.
case "$verbs" in
    *"close 507"*) ;;
    *) say "the closed mirrored bead inc-mir2 did not close issue 507;" \
           "a fixed defect stays advertised as open on the reporter's issue" ;;
esac
case "$verbs" in
    *"close 508"*) say "issue 508 was closed, but bead inc-mir1 is open" ;;
esac

# 4. A mirrored bead linked to a rehearsal repository must be refused, exactly
#    as a public one is. Its state write would otherwise land on the wrong repo.
python3 - "$work/beads.json" "$work/rehearsal.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
for r in rows:
    if r["id"] == "inc-mir1":
        r["external_ref"] = "https://github.com/someone/throwaway/issues/3"
json.dump(rows, open(sys.argv[2], "w"))
PY
cp "$work/rehearsal.json" "$work/beads.json"
rm -f "$work/pushed"
out2=$(cd "$repo_root" && PATH="$work/bin:$PATH" GITHUB_TOKEN=stub \
       SYNC_REPO=networkingguru/incursion-roguelike \
       ./tools/sync_issues.sh 2>&1)
rc2=$?
if [ "$rc2" -eq 0 ]; then
    say "a mirrored bead pointing at a throwaway repository was accepted;" \
        "its state write would land on the wrong tracker"
fi
case "$out2" in
    *"inc-mir1"*) ;;
    *) say "the stale-tracker refusal did not name the mirrored bead" ;;
esac

if [ -n "$selftest" ]; then
    # The check must fail when the lane is removed. Run a copy of the script
    # with the mirrored filter deleted and prove this check catches it.
    # The broken copy MUST live in the real tools/ directory. sync_issues.sh
    # resolves its own repository root from `dirname $0`/.., so a copy run from
    # the temp directory would look for check_upstream_label.sh in /tmp, exit
    # early, and push nothing -- which would look exactly like the filter
    # working and make this selftest a lie. The trap removes it either way.
    broken="$repo_root/tools/.check_mirrored_lane_broken.sh"
    trap 'rm -rf "$work"; rm -f "$broken"' EXIT
    sed 's/^issues = \[x for x in issues if "mirrored" not in.*$//' \
        "$repo_root/tools/sync_issues.sh" > "$broken"
    chmod +x "$broken"
    cp "$work/rehearsal.json" "$work/beads.json"
    python3 - "$work/beads.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
for r in rows:
    if r["id"] == "inc-mir1":
        r["external_ref"] = "https://github.com/networkingguru/incursion-roguelike/issues/508"
json.dump(rows, open(sys.argv[1], "w"))
PY
    rm -f "$work/pushed"
    (cd "$repo_root" && PATH="$work/bin:$PATH" GITHUB_TOKEN=stub \
     SYNC_REPO=networkingguru/incursion-roguelike "$broken" >/dev/null 2>&1)
    broke=$(cat "$work/pushed" 2>/dev/null || echo "")
    case ",$broke," in
        *",inc-mir1,"*)
            echo "SELFTEST PASS: with the mirrored filter removed, a mirrored"
            echo "bead reaches 'bd github sync' -- which is what this check"
            echo "catches. The live run above found the filter in place." ;;
        *)
            echo "SELFTEST FAIL: removing the mirrored filter did not put a" >&2
            echo "mirrored bead on the write path, so this check proves nothing." >&2
            fail=1 ;;
    esac
fi

if [ "$fail" -ne 0 ]; then
    echo "check_mirrored_lane: FAIL" >&2
    exit 1
fi
echo "check_mirrored_lane: a mirrored bead is written to nowhere and still reconciled"
exit 0
