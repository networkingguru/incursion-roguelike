#!/usr/bin/env python3
"""Is every newly created bead classified for publication, and fit to publish?

    tools/check_bead_publish.py              check the beads created since HEAD
    tools/check_bead_publish.py --audit      advise on the WHOLE database
    tools/check_bead_publish.py --selftest   prove this script still bites

WHY THIS EXISTS. `tools/sync_issues.sh` publishes every bead labelled `public`
to the GitHub Issues tab of this fork, and never publishes one labelled
`internal`. The label is the whole filter, so a bead nobody labelled is a bead
that silently does not exist to the outside world -- and an over-suppressed
bead is the failure no hold list can ever show you, because it simply never
appears anywhere.

A paragraph in AGENTS.md does not stop that. This project has watched an agent
walk past a written rule twice on record (2026-08-15, the publishing rule;
2026-08-23, the standing order). A required field that fails the commit is a
different kind of thing: it cannot be walked past, only answered.

WHAT IT CHECKS.

  A. DESCRIBED. Every bead created since the last commit has a non-empty
     description. `tools/sync_issues.sh` publishes the DESCRIPTION and never
     the notes, so a bead whose content lives only in its notes reaches the
     public tracker with an empty body. That is not hypothetical: on
     2026-09-03 inc-b12m became GitHub issue #381 with nothing in it, while
     its notes ran to several paragraphs. Asked of every new bead, not only
     the public ones, because a lane label can be changed later and the
     description is what a stranger reads.

  B. CLASSIFIED. Every bead created since the last commit carries exactly one
     of `public` or `internal`. Neither is unclassified; both is a
     contradiction. Beads that already existed at HEAD are not asked -- editing
     an old bead must not fail a commit.

  C. FIT TO PUBLISH. Every newly created `public` bead passes `bd lint`, which
     asks a bug for "## Steps to Reproduce" and "## Acceptance Criteria". A
     defect that reaches a public tracker with no way to reproduce it reads as
     noise.

     This is deliberately asked of NEW beads only. 423 of the 434 beads already
     in the database fail `bd lint`, including beads that cite the exact file,
     line and formula; the check measures a heading and not the presence of
     content, so demanding it of the backlog would suppress nearly everything.
     Draining that backlog is bead inc-uh76, and it is not a commit gate.

  D. ADVISORY, NEVER BLOCKING. The label is a human's judgement, so the script
     does not overrule it. It prints, in both directions, the beads whose title
     disagrees with their label: a `public` bead that sounds like the harness,
     and an `internal` bead that sounds like the game. Print only. A wrong
     label is fixed by a person, not by a word list.

     On a commit it advises about the NEW beads only. Sweeping the whole
     database prints about forty lines every time, and an advisory nobody reads
     advises nobody; `--audit` sweeps everything when you actually want it.
     The second direction is the one that matters: an over-suppressed bead is
     the failure no hold list can show you, because it never appears anywhere.

Exit: 0 every new bead is described, classified and fit
      1 a new bead has no description, is unclassified, is doubly classified,
        or fails lint
      2 could not measure
"""

import json
import os
import re
import subprocess
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# A title that sounds like the harness, the scripts, or the agent process.
HARNESS_WORDS = [
    "tools/", "check_", ".keys", ".sh", "soak", "harness", "subagent",
    "nightly", "key script", "options.dat", "codex", "claude", "bead",
    "agent", "session", "gate", "probe",
]

# A title that sounds like the game itself.
GAME_WORDS = [
    "spell", "weapon", "armour", "armor", "monster", "dungeon", "potion",
    "scroll", "wand", "ring", "amulet", "feat", "skill", "creature",
    "damage", "attack", "hit point", "character", "class", "god", "altar",
    "corpse", "dwarf", "elf", "monk", "cleric", "wizard", "paladin",
]


def run(cmd):
    """Run a command, return stdout, or None when it fails."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    except OSError:
        return None
    return p.stdout if p.returncode == 0 else None


def load_beads():
    out = run(["bd", "list", "--all", "--limit", "0", "--flat", "--json"])
    if out is None:
        return None
    try:
        d = json.loads(out)
    except ValueError:
        return None
    return d if isinstance(d, list) else (d.get("issues") or [])


def head_time():
    """HEAD's commit time, in seconds. None when git cannot be asked."""
    out = run(["git", "-C", ROOT, "log", "-1", "--format=%ct"])
    if not out:
        return None
    try:
        return int(out.strip())
    except ValueError:
        return None


def lint_failures(ids):
    """Bead ids among `ids` that bd lint reports as missing a section."""
    if not ids:
        return {}
    out = run(["bd", "lint", "--status", "all", "--json"] + list(ids))
    if out is None:
        return {}
    try:
        d = json.loads(out)
    except ValueError:
        return {}
    return {r["id"]: r.get("missing", []) for r in (d.get("results") or [])}


# ---------------------------------------------------------------- pure part

def epoch(stamp):
    """RFC3339 -> seconds. None when it will not parse.

    Never compare these two as strings. git prints HEAD's time in the
    machine's local offset ("...T11:40:36-07:00") and bd prints bead times in
    UTC ("...T18:40:05Z"). Lexically the UTC one always looks later, so a
    string comparison calls EVERY bead in the database newly created, and this
    check then reports on beads that were committed weeks ago. Caught by the
    matching hook's own test on 2026-09-01, after this file had already
    claimed in a comment that the two sort correctly. They do not.
    """
    try:
        return datetime.fromisoformat(stamp.strip().replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None


def is_new(bead, cutoff):
    """Was this bead created after HEAD? Unparseable timestamps are not new."""
    created = epoch(bead.get("created_at") or "")
    return created is not None and created > cutoff


def classify(beads, cutoff):
    """Split the beads created after `cutoff` into the three answers.

    Returns (unclassified, doubly, new_public). Each is a list of ids.
    `cutoff` is HEAD's commit time in seconds, from head_time().
    """
    unclassified, doubly, new_public = [], [], []
    for b in beads:
        if not is_new(b, cutoff):
            continue
        labels = set(b.get("labels") or [])
        pub, internal = "public" in labels, "internal" in labels
        if pub and internal:
            doubly.append(b["id"])
        elif not pub and not internal:
            unclassified.append(b["id"])
        elif pub:
            new_public.append(b["id"])
    return unclassified, doubly, new_public


def undescribed(beads, cutoff):
    """Beads created after `cutoff` whose description is empty.

    Whitespace is not a description. `bd` returns the field as an empty string
    when it was never written, and sync_issues.sh sends that field and nothing
    else to the public tracker.
    """
    return [b["id"] for b in beads
            if is_new(b, cutoff) and not (b.get("description") or "").strip()]


def undescribed_all(beads):
    """Every bead with an empty description, whatever its age or status.

    Used by --audit as a regression check. Split into the ones labelled
    `public`, which would publish an empty body, and the rest, which are only
    untidy. Counting all statuses is deliberate: `bd list --label public`
    returns the open ones alone and would miss a third of the database.
    """
    bad = [b for b in beads if not (b.get("description") or "").strip()]
    pub = [b["id"] for b in bad if "public" in set(b.get("labels") or [])]
    rest = [b["id"] for b in bad if "public" not in set(b.get("labels") or [])]
    return pub, rest


def disagreements(beads):
    """Beads whose title argues with their label, in both directions."""
    loud, quiet = [], []
    for b in beads:
        title = (b.get("title") or "").lower()
        labels = set(b.get("labels") or [])
        if "public" in labels:
            hit = [w for w in HARNESS_WORDS if w in title]
            if hit:
                loud.append((b["id"], hit, b.get("title") or ""))
        elif "internal" in labels:
            hit = [w for w in GAME_WORDS if re.search(r"\b" + re.escape(w), title)]
            if hit:
                quiet.append((b["id"], hit, b.get("title") or ""))
    return loud, quiet


# ---------------------------------------------------------------- selftest

FIXTURE = [
    # created before the cutoff: never asked, whatever its labels
    {"id": "old-none", "created_at": "2026-01-01T00:00:00Z", "labels": [],
     "description": "an old bead, described", "title": "an old bead nobody ever labelled"},
    # created before the cutoff and undescribed: still never asked
    {"id": "old-nodesc", "created_at": "2026-01-01T00:00:00Z",
     "labels": ["public"], "description": "",
     "title": "an old entry with an empty body"},
    # created after: the three answers
    {"id": "new-public", "created_at": "2026-06-01T00:00:00Z",
     "labels": ["public"], "description": "the potion heals nothing at all",
     "title": "the potion of healing does nothing"},
    {"id": "new-internal", "created_at": "2026-06-01T00:00:00Z",
     "labels": ["internal"], "description": "it exits 0 on a real failure",
     "title": "check_foo.sh exits silently"},
    {"id": "new-none", "created_at": "2026-06-01T00:00:00Z", "labels": [],
     "description": "described, but no lane",
     "title": "somebody forgot to classify this one"},
    {"id": "new-both", "created_at": "2026-06-01T00:00:00Z",
     "labels": ["public", "internal"], "description": "described, two lanes",
     "title": "two answers is not an answer"},
    # created after, labelled, and empty: the failure that reached GitHub
    {"id": "new-nodesc", "created_at": "2026-06-01T00:00:00Z",
     "labels": ["public"], "description": "   ",
     "title": "all its content is in the notes"},
    # advisory, both directions, and neither may change the exit status
    {"id": "loud", "created_at": "2026-01-01T00:00:00Z", "labels": ["public"],
     "description": "it swallows a real failure",
     "title": "tools/check_bar.sh swallows its own failure"},
    {"id": "quiet", "created_at": "2026-01-01T00:00:00Z", "labels": ["internal"],
     "description": "undead take no damage from it",
     "title": "the paladin's weapon deals no damage to undead"},
]


def selftest():
    cutoff = epoch("2026-03-01T00:00:00Z")
    st = 0

    # The bug this check shipped with: a UTC bead time and a cutoff written in
    # a negative local offset name the same instant, and the bead must NOT
    # count as new. Compared as strings, "18:00:00Z" > "11:00:00-07:00" and
    # every bead in the database looks newly created.
    same_instant = epoch("2026-03-01T11:00:00-07:00")
    older = [{"id": "tz-old", "created_at": "2026-03-01T17:59:59Z", "labels": []}]
    if classify(older, same_instant)[0]:
        print("SELFTEST FAIL: a bead older than HEAD counted as new "
              "(local-offset vs UTC comparison)")
        st = 1
    unclassified, doubly, new_public = classify(FIXTURE, cutoff)

    if unclassified != ["new-none"]:
        print("SELFTEST FAIL: unclassified is %r, wanted ['new-none']" % unclassified)
        st = 1
    if doubly != ["new-both"]:
        print("SELFTEST FAIL: doubly is %r, wanted ['new-both']" % doubly)
        st = 1
    if new_public != ["new-public", "new-nodesc"]:
        print("SELFTEST FAIL: new_public is %r, wanted "
              "['new-public', 'new-nodesc']" % new_public)
        st = 1

    # The failure that put an empty body on the public tracker as issue #381.
    nodesc = undescribed(FIXTURE, cutoff)
    if nodesc != ["new-nodesc"]:
        print("SELFTEST FAIL: undescribed is %r, wanted ['new-nodesc']" % nodesc)
        st = 1
    if "old-nodesc" in nodesc:
        print("SELFTEST FAIL: an old bead with an empty description "
              "failed the commit")
        st = 1
    pub_empty, rest_empty = undescribed_all(FIXTURE)
    if sorted(pub_empty) != ["new-nodesc", "old-nodesc"]:
        print("SELFTEST FAIL: --audit missed an empty public description: %r"
              % pub_empty)
        st = 1
    if "old-none" in unclassified:
        print("SELFTEST FAIL: an old unlabelled bead failed the commit")
        st = 1

    loud, quiet = disagreements(FIXTURE)
    loud_ids, quiet_ids = [x[0] for x in loud], [x[0] for x in quiet]
    if "loud" not in loud_ids:
        print("SELFTEST FAIL: did not flag a public bead that names a check script")
        st = 1
    if "quiet" not in quiet_ids:
        print("SELFTEST FAIL: did not flag an internal bead that talks about the game")
        st = 1
    if "new-public" in loud_ids:
        print("SELFTEST FAIL: flagged a plain game bug as harness work")
        st = 1
    if "new-internal" in quiet_ids:
        print("SELFTEST FAIL: flagged a plain check-script bead as game work")
        st = 1

    if st == 0:
        print("SELFTEST PASS: check_bead_publish.py bites on all six failures")
    return st


# ---------------------------------------------------------------- main

def main(argv):
    audit = False
    if len(argv) > 1 and argv[1] == "--selftest":
        return selftest()
    if len(argv) > 1 and argv[1] == "--audit":
        audit = True
    elif len(argv) > 1:
        print("usage: %s [--audit|--selftest]" % argv[0], file=sys.stderr)
        return 2

    beads = load_beads()
    if beads is None:
        print("check_bead_publish: cannot read the bead database", file=sys.stderr)
        return 2
    cutoff = head_time()
    if not cutoff:
        print("check_bead_publish: cannot read the time of HEAD", file=sys.stderr)
        return 2

    unclassified, doubly, new_public = classify(beads, cutoff)
    fresh = [b for b in beads if is_new(b, cutoff)]
    print("check_bead_publish: %d bead(s) created since HEAD" % len(fresh))

    fail = 0
    nodesc = undescribed(beads, cutoff)
    if nodesc:
        print("FAIL: these new beads have an empty description:")
        for i in nodesc:
            print("  %s" % i)
        print("sync_issues.sh publishes the DESCRIPTION and never the notes,")
        print("so this bead would reach the public tracker with an empty body.")
        print("Write it: bd update <id> --description \"...\"")
        fail = 1
    if unclassified:
        print("FAIL: these new beads carry neither `public` nor `internal`:")
        for i in unclassified:
            print("  %s" % i)
        print("Decide: `public` is a defect or wanted feature IN THE GAME;")
        print("`internal` is the harness, the scripts, the docs checks, the")
        print("bead machinery. Then: bd tag <id> public|internal")
        fail = 1
    if doubly:
        print("FAIL: these new beads carry BOTH `public` and `internal`:")
        for i in doubly:
            print("  %s" % i)
        print("Remove one: bd label remove <id> public|internal")
        fail = 1

    missing = lint_failures(new_public)
    if missing:
        print("FAIL: these new `public` beads are not fit for a public tracker:")
        for i, sections in sorted(missing.items()):
            print("  %s missing %s" % (i, ", ".join(sections) or "a section"))
        print("A defect a stranger cannot reproduce reads as noise. Write the")
        print("sections, or re-type the bead if it is not really a bug.")
        fail = 1

    if audit:
        scope = beads
        pub_empty, rest_empty = undescribed_all(beads)
        print("")
        print("audit: %d bead(s) in the database, all statuses" % len(beads))
        if pub_empty:
            print("FAIL: these `public` beads have an empty description and")
            print("would publish an empty body:")
            for i in sorted(pub_empty):
                print("  %s" % i)
            fail = 1
        else:
            print("audit: no `public` bead has an empty description")
        if rest_empty:
            print("advisory, not public, so nothing leaks:")
            for i in sorted(rest_empty):
                print("  %s has an empty description" % i)
    else:
        scope = fresh

    loud, quiet = disagreements(scope)
    if loud or quiet:
        print("")
        print("advisory only, nothing here fails the commit:")
        for i, hit, title in loud:
            print("  public  but sounds like the harness: %-12s (%s) %s"
                  % (i, ",".join(hit)[:24], title[:60]))
        for i, hit, title in quiet:
            print("  internal but sounds like the game:  %-12s (%s) %s"
                  % (i, ",".join(hit)[:24], title[:60]))

    if fail:
        return 1
    print("PASS: every new bead is described, classified and fit to publish")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
