#!/usr/bin/env python3
"""Print the comma-separated ids of the public beads that need a GitHub write.

usage: sync_select.py BEADS.json ISSUES.json OWNER/REPO [--new-only]

A non-mirrored bead is selected when it has no usable issue link, or when its
issue title, trimmed body, or type:: / priority:: label differs from the
bead's. Plain labels are not compared (bd never updates them, inc-fcecz). Mirrored beads are
never selected. With --new-only, only a bead with an empty external_ref is.
"""
import json
import sys


def rows(path):
    d = json.load(open(path))
    return d if isinstance(d, list) else d.get("issues", [])


PRIORITY = ["critical", "high", "medium", "low", "none"]


def label_names(issue):
    return {(x.get("name") if isinstance(x, dict) else x)
            for x in issue.get("labels") or []}


def labels_stale(b, issue):
    names = label_names(issue)
    t = b.get("issue_type")
    if t and "type::%s" % t not in names:
        return True
    p = b.get("priority")
    if isinstance(p, int) and 0 <= p <= 4:
        return "priority::%s" % PRIORITY[p] not in names
    return False


def select(beads, issues, repo, new_only):
    prefix = "https://github.com/%s/issues/" % repo
    by_num = {i["number"]: i for i in issues}
    out = []
    for b in beads:
        if "mirrored" in set(b.get("labels") or []):
            continue
        ref = b.get("external_ref") or ""
        if new_only:
            if not ref:
                out.append(b["id"])
            continue
        issue = None
        if ref.startswith(prefix):
            try:
                issue = by_num.get(int(ref[len(prefix):]))
            except ValueError:
                pass
        if (issue is None
                or labels_stale(b, issue)
                or issue.get("title") != b.get("title")
                or (issue.get("body") or "").strip()
                != (b.get("description") or "").strip()):
            out.append(b["id"])
    return out


def main(argv):
    args = [a for a in argv[1:] if a != "--new-only"]
    if len(args) != 3:
        sys.exit(__doc__)
    beads = rows(args[0])
    issues = [] if "--new-only" in argv else rows(args[1])
    print(",".join(select(beads, issues, args[2], "--new-only" in argv)))


if __name__ == "__main__":
    main(sys.argv)
