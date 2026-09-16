#!/bin/bash
# Publish every bead labelled `public` to the GitHub Issues tab, and keep the
# published issues in step with the beads.
#
# WHY THIS EXISTS. The bead database holds several hundred real defects in this
# port. None of them was visible to anybody but Brian, so a stranger about to
# report a bug had no way to see it was already found, already diagnosed, and
# in most cases already traced to a file and a line. This script makes the
# code-relevant part of the database public, and keeps it public without
# anybody remembering to do it.
#
# WHY A LABEL AND NOT A RULE. `bd github sync` has exactly two selectors,
# `--issues <ids>` and `--parent <bead>`. Half the beads have no parent, so
# `--parent` cannot express the filter, and the filter has to be computed out
# here and handed over as an id list. The filter itself is a mandatory label:
# every bead carries exactly one of `public`, `internal` or `mirrored`, and
# tools/check_bead_publish.py fails the commit when a new bead has an empty
# description, or carries none of the three or more than one. It is wired into
# .beads/hooks/pre-commit and blocks (inc-m7xb, 2026-09-06). A required field that blocks a commit is the only kind of rule an
# agent cannot walk past; a paragraph in AGENTS.md has been walked past twice
# on record.
#
#   public    a defect or a wanted feature IN THE GAME -- rules, engine,
#             rendering, saves, the shipped builds. Title, body and state are
#             all written to its issue.
#   internal  the test harness, the key scripts, the documentation checks, the
#             bead and gate machinery, agent process. Never published.
#   mirrored  a game defect that is ALREADY public, because somebody outside
#             filed it. Its `external_ref` points at THEIR issue. Only the
#             open/closed state is written. Never the title, never the body.
#
# WHY `mirrored` EXISTS. The full sync refreshes titles and descriptions, which
# is right for an issue this project wrote and destructive for one it did not.
# On 2026-09-16 two outside reports arrived, GitHub 507 and 508. Filing them as
# `public` with an `external_ref` pointing at those issues would have replaced
# the reporters' text and their screenshots on the next push; a --dry-run said
# "Would update in GitHub" for both. The refs were cleared before any push and
# nothing was lost. See bead inc-rza6.
#
# The diagnosis for a mirrored defect lives in the bead's `notes`, which this
# script never sends: it publishes the DESCRIPTION and nothing else. Telling
# the reporter what was found is a COMMENT on their issue. That is a separate
# act, and it goes through the publishing gate in AGENTS.md.
#
# WHY IT RUNS HERE AND NOT IN CI. A GitHub Actions job cannot read this
# database directly; it would have to bootstrap from the `refs/dolt/data` ref
# on the remote, and that ref is only as fresh as the last push. Measured on
# 2026-09-01, it held 122 beads against 432 here. A CI job would therefore
# publish a stale snapshot and look perfectly healthy while doing it, which is
# the worst failure a public tracker can have. Run from this machine the script
# reads the live database, so it cannot be stale. It is driven by the nightly
# harness; the cost is that it does not run while the Mac is off, which is
# already true of every other check in this project.
#
# WHY THERE IS NO LINT GATE ON PUBLICATION. `bd lint` wants a literal
# `## Steps to Reproduce` heading on anything typed `bug`, and 423 of 432 beads
# do not have one -- including beads that cite the exact file, line, formula
# and observed effect. The check measures a heading, not the presence of
# content, so gating publication on it would suppress essentially the whole
# database. The lint gate belongs on NEWLY created beads, where it is cheap and
# shapes the template; check_bead_publish.py does that.
#
# USAGE
#   tools/sync_issues.sh              push every `public` bead
#   tools/sync_issues.sh --dry-run    say what would be pushed, touch nothing
#   tools/sync_issues.sh --new-only   push only the `public` beads that have no
#                                     issue yet, and say nothing when there are
#                                     none. This is what the pre-push hook
#                                     runs: a full run costs four minutes, a
#                                     quiet --new-only run costs under a second.
#                                     The flags combine.
#
# ENVIRONMENT
#   SYNC_REPO      owner/repo to push into. Default is the real fork. Point it
#                  at a throwaway repo to rehearse.
#   GITHUB_TOKEN   the token. Falls back to `gh auth token`.

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

SYNC_REPO=${SYNC_REPO:-networkingguru/incursion-roguelike}

dry_run=""
new_only=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)  dry_run="--dry-run" ;;
        --new-only) new_only=1 ;;
        *)          echo "usage: $0 [--dry-run] [--new-only]" >&2; exit 2 ;;
    esac
    shift
done

command -v bd >/dev/null 2>&1 || { echo "sync_issues: bd is not on PATH" >&2; exit 1; }

if [ -z "${GITHUB_TOKEN:-}" ]; then
    command -v gh >/dev/null 2>&1 || {
        echo "sync_issues: no GITHUB_TOKEN and no gh to ask for one" >&2; exit 1; }
    GITHUB_TOKEN=$(gh auth token) || {
        echo "sync_issues: gh has no token; run 'gh auth login'" >&2; exit 1; }
fi
[ -n "$GITHUB_TOKEN" ] || { echo "sync_issues: empty GITHUB_TOKEN" >&2; exit 1; }
export GITHUB_TOKEN
export GITHUB_REPOSITORY="$SYNC_REPO"

# The database must be fully labelled before anything is published. A bead with
# neither label is one nobody has classified, and publishing around it silently
# hides it; a bead with both is a contradiction. Either way, stop.
unlabelled=$(bd list --all --limit 0 --flat --json 2>/dev/null | python3 -c '
import sys, json
LANES = {"public", "internal", "mirrored"}
d = json.load(sys.stdin)
issues = d if isinstance(d, list) else d.get("issues", [])
bad = []
for x in issues:
    if len(set(x.get("labels") or []) & LANES) != 1:
        bad.append(x["id"])
print(" ".join(bad))
')
if [ -n "$unlabelled" ]; then
    echo "sync_issues: these beads carry none, or more than one, of" >&2
    echo "sync_issues: public / internal / mirrored:" >&2
    echo "  $unlabelled" >&2
    echo "sync_issues: label them, then re-run. Nothing was pushed." >&2
    exit 1
fi

# Every bead the reporting ledger lists as a base-code (upstream) defect must
# carry the `upstream` label before we publish, or its GitHub issue goes up with
# no tag and the tracker under-counts the port's upstream work -- the gap that
# left 90-odd fixed defects showing as four on 2026-09-04. This is the same
# shape as the guard above: a required label, checked before the push, not left
# to anyone's memory. tools/check_upstream_label.sh is the detector and carries
# its own self-test.
if ! "$repo_root/tools/check_upstream_label.sh"; then
    echo "sync_issues: ledger beads are missing the 'upstream' label (above)." >&2
    echo "sync_issues: label them, then re-run. Nothing was pushed." >&2
    exit 1
fi

# ONE READ OF THE DATABASE, REUSED THREE TIMES.
#
# `bd show --json <ids>` costs 116 SECONDS for 368 beads -- measured 2026-09-03
# with a traced run -- because it pays a round trip per id. The script used to
# call it twice, in the stale-tracker guard and in the state reconciliation,
# which was 232 of the 240 seconds a full run took. `bd list --json` returns
# `external_ref` and `status` for the whole database in 0.6 seconds, and those
# are the only two fields either step wanted. So read once, into a file, and
# let all three steps parse it. A full run is now about ten seconds, nearly all
# of it GitHub's own issue listing.
beads_json=$(mktemp -t sync_issues) || { echo "sync_issues: no temp file" >&2; exit 1; }
trap 'rm -f "$beads_json"' EXIT
# BOTH OUTWARD LANES ARE READ, AND THEY ARE NOT TREATED ALIKE.
#
# `public` beads are written to GitHub: title, body and state. `mirrored` beads
# are NOT written; only their state is reconciled, because the issue they point
# at belongs to the person who reported it. Reading both here and splitting
# below keeps the single-read property above: the reconciliation needs the
# mirrored rows, and a second `bd list` would cost another round trip.
bd list --label-any public,mirrored --all --limit 0 --flat --json \
    > "$beads_json" 2>/dev/null || {
    echo "sync_issues: cannot read the bead database" >&2; exit 1; }

# --new-only keeps just the public beads that have no issue yet. The pre-push
# hook does NOT use it: a push must move statuses too, or a defect closed in
# beads stays advertised as open on the tracker.
#
# `mirrored` is excluded here and nowhere else. This list is what reaches
# `bd github sync`, which writes titles and descriptions; a mirrored bead in it
# would overwrite a stranger's bug report. The reconciliation below reads the
# file again and DOES include them, so their state still tracks the bead.
export NEW_ONLY="$new_only"
ids=$(python3 -c '
import sys, json, os
d = json.load(sys.stdin)
issues = d if isinstance(d, list) else d.get("issues", [])
issues = [x for x in issues if "mirrored" not in set(x.get("labels") or [])]
if os.environ.get("NEW_ONLY"):
    issues = [x for x in issues if not (x.get("external_ref") or "")]
print(",".join(x["id"] for x in issues))
' < "$beads_json")

# THE RECONCILIATION SET IS WIDER THAN THE PUSH SET.
#
# `ids` is what gets WRITTEN to GitHub, and it never holds a mirrored bead.
# `recon_ids` is what gets its open/closed state checked, and it holds both
# lanes: a mirrored bead the port has fixed must stop being advertised as open
# on the reporter's issue, and closing a state is not writing a body.
recon_ids=$(python3 -c '
import sys, json
d = json.load(sys.stdin)
issues = d if isinstance(d, list) else d.get("issues", [])
print(",".join(x["id"] for x in issues))
' < "$beads_json")

# --new-only asks one question, "is there anything NEW to create", and it must
# stay cheap and silent: it runs on every push, and the reconciliation below
# costs a full GitHub issue listing. An empty push set ends the run there, and
# the state reconciliation waits for the next full sync.
if [ -n "$new_only" ] && [ -z "$ids" ]; then
    exit 0
fi

if [ -z "$recon_ids" ]; then
    echo "sync_issues: no bead is labelled public or mirrored; nothing to do."
    exit 0
fi

count=$(printf '%s\n' "$ids" | tr ',' '\n' | grep -c . || true)

# `bd github sync --issues` takes the whole list as one argument. Assert it
# fits rather than assuming: ARG_MAX on macOS is about 1 MB, and the list is a
# few KB, but a database ten times this size should fail loudly here and not
# half-way through a push.
limit=$(getconf ARG_MAX 2>/dev/null || echo 262144)
length=${#ids}
if [ "$length" -gt $((limit / 4)) ]; then
    echo "sync_issues: the id list is ${length} bytes, too close to ARG_MAX (${limit})." >&2
    echo "sync_issues: sync_issues.sh needs to batch. Nothing was pushed." >&2
    exit 1
fi

# A BEAD MAY ONLY BE LINKED TO ONE TRACKER AT A TIME.
#
# `external_ref` on a bead holds the URL of the issue bd created for it. After
# a rehearsal against a throwaway repository, every bead points at the
# throwaway. Pointing this script at the real repository then updates the
# rehearsal issues and creates nothing real, silently. So refuse, and say which
# beads to clear.
#
# Asked of the RECONCILIATION set, not the push set. A mirrored bead is never
# written to, but its state IS reconciled, so a mirrored bead pointing at a
# rehearsal repository would close the wrong issue.
export SYNC_IDS="$recon_ids"
stale=$(python3 -c '
import sys, json, os
repo = os.environ["GITHUB_REPOSITORY"]
mine = "https://github.com/%s/issues/" % repo
wanted = set(os.environ["SYNC_IDS"].split(","))
d = json.load(sys.stdin)
issues = d if isinstance(d, list) else d.get("issues", [])
bad = []
for b in issues:
    if b["id"] not in wanted:
        continue
    ref = b.get("external_ref") or ""
    if ref and "/issues/" in ref and not ref.startswith(mine):
        bad.append(b["id"])
print(" ".join(bad))
' < "$beads_json")
if [ -n "$stale" ]; then
    n=$(printf '%s\n' "$stale" | wc -w | tr -d ' ')
    echo "sync_issues: ${n} bead(s) are already linked to a DIFFERENT tracker." >&2
    echo "sync_issues: pushing now would update those issues, not ${SYNC_REPO}." >&2
    echo "sync_issues: clear them first, e.g." >&2
    echo "  for b in \$(...); do bd update \$b --external-ref '' -q; done" >&2
    echo "sync_issues: first few: $(printf '%s' "$stale" | cut -d' ' -f1-6)" >&2
    exit 1
fi

mirrored_count=$(python3 -c '
import sys, json
d = json.load(sys.stdin)
issues = d if isinstance(d, list) else d.get("issues", [])
print(sum(1 for x in issues if "mirrored" in set(x.get("labels") or [])))
' < "$beads_json")

if [ "$count" -gt 0 ]; then
    echo "sync_issues: ${count} public beads -> ${SYNC_REPO} (${length} bytes of ids)"
    bd github sync --push-only --issues "$ids" ${dry_run:+$dry_run}
else
    echo "sync_issues: no public bead to write."
fi
if [ "$mirrored_count" -gt 0 ]; then
    echo "sync_issues: ${mirrored_count} mirrored beads: state only, no title and no body."
fi

# Re-read, because the sync above has just written `external_ref` onto every
# bead it created an issue for, and the reconciliation below needs those.
bd list --label-any public,mirrored --all --limit 0 --flat --json \
    > "$beads_json" 2>/dev/null || {
    echo "sync_issues: cannot re-read the beads; state NOT reconciled" >&2; exit 1; }

# RECONCILE THE OPEN/CLOSED STATE OURSELVES.
#
# `bd github sync` creates every issue open, whatever the bead says, and only
# closes it on a LATER run. Measured on the rehearsal repo, 2026-09-01: run 1
# created 364 issues, all open, against 104 closed beads; run 2 closed 77 of
# them; run 3 closed none and changed nothing. So 27 fixed defects were left
# advertised as open, permanently, and no further run repaired them.
#
# A public tracker that shows fixed bugs as open is worse than no tracker: it
# invites a stranger to spend an evening on something already done. So the
# state is not left to bd. `external_ref` on each bead holds the issue URL bd
# assigned, which is the durable link, and `gh` sets the state directly.
#
# Both lanes are reconciled. A mirrored bead's issue belongs to the person who
# reported it, and closing it is the one write this project may make there:
# state, never title and never body.
python3 - "$SYNC_REPO" "$recon_ids" "${dry_run:-}" "$beads_json" <<'PY'
import json, subprocess, sys

repo, ids, dry, beads_json = (
    sys.argv[1], sys.argv[2].split(","), bool(sys.argv[3]), sys.argv[4])


def sh(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else None


# From the file, not `bd show <ids>`: that call costs 116 seconds for 368 ids
# and returns nothing this step cannot read here.
d = json.load(open(beads_json))
rows = d if isinstance(d, list) else d.get("issues", [])
wanted = set(ids)
beads = [b for b in rows if b["id"] in wanted]

out = sh(["gh", "issue", "list", "-R", repo, "--state", "all",
          "--limit", "2000", "--json", "number,state"])
if out is None:
    sys.exit("sync_issues: cannot list the issues; state NOT reconciled")
actual = {i["number"]: i["state"] for i in json.loads(out)}

want_closed, want_open = [], []
for b in beads:
    ref = b.get("external_ref") or ""
    prefix = "https://github.com/%s/issues/" % repo
    if not ref.startswith(prefix):
        continue
    try:
        n = int(ref[len(prefix):])
    except ValueError:
        continue
    if n not in actual:
        continue
    closed = b.get("status") == "closed"
    if closed and actual[n] == "OPEN":
        want_closed.append((n, b["id"]))
    elif not closed and actual[n] == "CLOSED":
        want_open.append((n, b["id"]))

if not want_closed and not want_open:
    print("sync_issues: state already matches; nothing to reconcile")
    sys.exit(0)

print("sync_issues: reconciling %d to close, %d to reopen"
      % (len(want_closed), len(want_open)))
if dry:
    for n, i in want_closed + want_open:
        print("  [dry-run] #%d (%s)" % (n, i))
    sys.exit(0)

bad = 0
for verb, rows in (("close", want_closed), ("reopen", want_open)):
    for n, i in rows:
        if sh(["gh", "issue", verb, str(n), "-R", repo]) is None:
            print("  FAILED to %s #%d (%s)" % (verb, n, i))
            bad += 1
print("sync_issues: reconciled, %d failure(s)" % bad)
sys.exit(1 if bad else 0)
PY
