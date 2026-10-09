#!/usr/bin/env python3
"""Mark the ruling ledger with the fidelity-check results.

Backs up the ledger to `<ledger stem>-pre-fidelity-<date>.md` beside it and
refuses (exit 2) when that backup already exists.

Each ADDED_NOTES row from the check output files is placed in the ledger entry
with the greatest header offset <= the row's byte offset in the notes (found by
locating the pair's ruling_text in the notes); rows whose text is not found, or
whose nearest entry is more than 200 bytes away, are skipped and reported.

Each line is inserted directly after its entry's `- Status:` line; the same line
is never inserted twice. After insertion, the new file must equal the old lines
plus the inserted lines, in order (asserted).

`--extra` names a text file, one line per entry: `<ledger id>\t<line text>`.
The line `- Fidelity (<date>): <line text>` is inserted after that entry's
Status line. Exit 1 and name it when an id is not in the ledger.

Standard library only. See brief.

Usage:
    python3 -I tools/fidelity/mark_ledger.py --selftest
    python3 -I tools/fidelity/mark_ledger.py --ledger L --notes N --pairs P \\
        --checks C... [--extra E] --date YYYY-MM-DD
"""

import argparse
import json
import os
import re
import sys

HEADER_RE = re.compile(r"^###\s+(.*)$")
OFFSET_RE = re.compile(r"@offset\s+(\d+)")
NID_RE = re.compile(r"^(N@\d+)")
RID_RE = re.compile(r"^(R[0-9A-Za-z-]+)\b")
STATUS_PREFIX = "- Status:"


class MissingId(Exception):
    def __init__(self, rid):
        super().__init__("missing required entry id: " + rid)
        self.rid = rid


def parse_headers(lines):
    """Return list of (header_id, offset_or_None).

    header_id is 'R71' for offset headers, 'N@<N>' for unnumbered ones, else
    the raw header text.
    """
    out = []
    for ln in lines:
        m = HEADER_RE.match(ln)
        if not m:
            continue
        hdr = m.group(1)
        mo = OFFSET_RE.search(hdr)
        if mo:
            mr = RID_RE.match(hdr)
            out.append((mr.group(1) if mr else hdr, int(mo.group(1))))
        else:
            mn = NID_RE.match(hdr)
            if mn:
                out.append((mn.group(1), int(mn.group(1)[2:])))
            else:
                out.append((hdr, None))
    return out


def status_indices(lines):
    """Map header_id -> index of its '- Status:' line (first after header)."""
    result = {}
    cur = None
    for i, ln in enumerate(lines):
        m = HEADER_RE.match(ln)
        if m:
            hdr = m.group(1)
            mo = OFFSET_RE.search(hdr)
            if mo:
                mr = RID_RE.match(hdr)
                cur = mr.group(1) if mr else hdr
            else:
                mn = NID_RE.match(hdr)
                cur = mn.group(1) if mn else hdr
            continue
        if cur is not None and ln.startswith(STATUS_PREFIX):
            result.setdefault(cur, i)
            cur = None
    return result


def find_entry_for_offset(headers, offset):
    """Greatest header offset <= offset. Returns (header_id, offset) or None."""
    best = None
    for hid, off in headers:
        if off is None or off > offset:
            continue
        if best is None or off > best[1]:
            best = (hid, off)
    return best


def compute_insertions(rows, pairs, headers, notes_bytes, date):
    """Return (insertions_by_id, matched, unmatched).

    insertions_by_id: dict header_id -> list of Fidelity lines.
    matched: list of (pair_id, header_id).
    unmatched: list of pair_id.
    """
    ins = {}

    def add(hid, line):
        bucket = ins.setdefault(hid, [])
        if line not in bucket:
            bucket.append(line)

    matched = []
    unmatched = []
    for row in rows:
        pid = row["pair_id"]
        rt = pairs.get(pid)
        if rt is None:
            unmatched.append(pid)
            continue
        key = rt[:80].strip().encode("utf-8")
        if not key:
            unmatched.append(pid)
            continue
        off = notes_bytes.find(key)
        if off < 0:
            unmatched.append(pid)
            continue
        best = find_entry_for_offset(headers, off)
        if best is None or (off - best[1]) > 200:
            unmatched.append(pid)
            continue
        hid = best[0]
        line = (
            "- Fidelity (" + date + "): Claude's own material, not Brian's ruling: "
            + row.get("item", "") + ". " + row.get("note", "")
        )
        add(hid, line)
        matched.append((pid, hid))

    return ins, matched, unmatched


def load_extra(path):
    """Return list of (ledger_id, line_text) from a `id\\ttext` file."""
    out = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            if "\t" not in line:
                raise ValueError("extra line has no tab: " + line)
            rid, text = line.split("\t", 1)
            out.append((rid, text))
    return out


def compute_extra_insertions(extra_rows, date):
    """Return dict ledger_id -> list of Fidelity lines from --extra rows."""
    ins = {}
    for rid, text in extra_rows:
        line = "- Fidelity (" + date + "): " + text
        bucket = ins.setdefault(rid, [])
        if line not in bucket:
            bucket.append(line)
    return ins


def check_extra_ids(ins, sidx):
    """Return the first id in ins that has no Status line, else None."""
    for rid in ins:
        if rid not in sidx:
            return rid
    return None


def apply_insertions(lines, ins):
    """Insert each Fidelity line directly after the entry's '- Status:' line.

    Never inserts the same Fidelity line twice into one entry. Returns new list
    of lines. Raises MissingId if an insertion id has no entry.
    """
    sidx = status_indices(lines)

    insert_after = {}
    for hid, fid_lines in ins.items():
        if hid not in sidx:
            raise MissingId(hid)
        idx = sidx[hid]
        insert_after.setdefault(idx, [])
        for fl in fid_lines:
            if fl not in insert_after[idx]:
                insert_after[idx].append(fl)

    out = []
    for i, ln in enumerate(lines):
        out.append(ln)
        if i in insert_after:
            out.extend(insert_after[i])
    return out


def assert_sequence(old, new, inserted_count):
    """New must equal old plus inserted lines, in the same order."""
    oi = 0
    added = 0
    for ln in new:
        if oi < len(old) and ln == old[oi]:
            oi += 1
        else:
            added += 1
    assert oi == len(old), "old lines missing or reordered in new file"
    assert added == inserted_count, (
        "inserted-line count mismatch: expected %d, got %d" % (inserted_count, added)
    )


def load_checks(paths):
    """Return the ADDED_NOTES rows from the given check output files."""
    rows = []
    for f in paths:
        with open(f, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                o = json.loads(line)
                if o.get("verdict") == "ADDED_NOTES":
                    rows.append(o)
    return rows


def load_pairs(path):
    pairs = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            o = json.loads(line)
            pairs[o["pair_id"]] = o.get("ruling_text", "")
    return pairs


def backup_path(ledger_path, date):
    stem, ext = os.path.splitext(ledger_path)
    return "%s-pre-fidelity-%s%s" % (stem, date, ext)


def run(args):
    try:
        with open(args.notes, "r", encoding="utf-8") as fh:
            notes_bytes = fh.read().encode("utf-8")
        with open(args.ledger, "r", encoding="utf-8") as fh:
            ledger_text = fh.read()
    except OSError as e:
        sys.stderr.write("cannot read input: %s\n" % e)
        return 2

    pairs = load_pairs(args.pairs)
    rows = load_checks(args.checks)

    extra_rows = load_extra(args.extra) if args.extra else []

    bpath = backup_path(args.ledger, args.date)
    if os.path.exists(bpath):
        sys.stderr.write("refusing: backup already exists: " + bpath + "\n")
        return 2

    old_lines = ledger_text.split("\n")
    headers = parse_headers(old_lines)
    sidx = status_indices(old_lines)

    ins, matched, unmatched = compute_insertions(
        rows, pairs, headers, notes_bytes, args.date
    )

    extra_ins = compute_extra_insertions(extra_rows, args.date)
    bad = check_extra_ids(extra_ins, sidx)
    if bad is not None:
        sys.stderr.write("missing required entry id: " + bad + "\n")
        return 1

    for hid, lines in extra_ins.items():
        ins.setdefault(hid, [])
        for fl in lines:
            if fl not in ins[hid]:
                ins[hid].append(fl)

    try:
        new_lines = apply_insertions(old_lines, ins)
    except MissingId as e:
        sys.stderr.write("missing required entry id: " + e.rid + "\n")
        return 1

    inserted_count = len(new_lines) - len(old_lines)
    assert_sequence(old_lines, new_lines, inserted_count)

    with open(bpath, "w", encoding="utf-8") as fh:
        fh.write(ledger_text)
    with open(args.ledger, "w", encoding="utf-8") as fh:
        fh.write("\n".join(new_lines))

    print("inserted lines:", inserted_count)
    by_id = {}
    for pid, hid in matched:
        by_id.setdefault(hid, []).append(pid)
    for hid in sorted(by_id, key=lambda h: min(
            (o for i, o in headers if i == h and o is not None), default=0)):
        print("  %-10s <- %s" % (hid, ", ".join(by_id[hid])))
    print("unmatched pairs:", len(unmatched))
    for pid in unmatched:
        print("  " + pid)
    return 0


def selftest():
    """In-memory checks. Each has a stated red-before failure."""
    failures = []

    def check(name, cond):
        if not cond:
            failures.append(name)

    DATE = "2026-10-09"

    # --- Feature 1: an ADDED_NOTES row lands in the right entry by offset.
    notes = b"alpha entry text here\nbeta entry text here\n"
    alpha_off = 0
    beta_off = notes.index(b"beta")
    lines = [
        "### R10 (d) @offset %d" % alpha_off,
        "- Says: alpha",
        "- Status: LIVE",
        "- Replaces: none",
        "",
        "### R20 (d) @offset %d" % beta_off,
        "- Says: beta",
        "- Status: LIVE",
        "- Replaces: none",
    ]
    headers = parse_headers(lines)
    row = {
        "pair_id": "p1",
        "verdict": "ADDED_NOTES",
        "item": "ITEM",
        "note": "NOTE",
    }
    pairs = {"p1": "beta entry text here"}
    ins, matched, unmatched = compute_insertions(
        [row], pairs, headers, notes, DATE
    )
    # RED if offset bucketing used the wrong side: would land in R10.
    check("f1-bucket", "R20" in ins)
    check("f1-not-alpha", "R10" not in ins)
    check("f1-matched", matched == [("p1", "R20")])
    check("f1-no-unmatched", unmatched == [])

    # Ensure the full apply path puts the line right after R20's Status line.
    new = apply_insertions(lines, ins)
    r20 = next(k for k, v in enumerate(new) if v.startswith("### R20"))
    i = new.index("- Status: LIVE", r20)
    # RED if inserted before Status or at the wrong entry.
    check("f1-position", new[i + 1].startswith("- Fidelity"))
    check("f1-text", new[i + 1] ==
          "- Fidelity (" + DATE + "): Claude's own material, not Brian's "
          "ruling: ITEM. NOTE")

    # --- Feature 2: an unmatched text is skipped and reported.
    pairs2 = {"p1": "no-such-text-anywhere"}
    ins2, matched2, unmatched2 = compute_insertions(
        [row], pairs2, headers, notes, DATE
    )
    # RED if a not-found text were inserted: matched2 would be non-empty.
    check("f2-skipped", all("ITEM" not in x for x in ins2.get("R20", []))
          and matched2 == [])
    check("f2-reported", unmatched2 == ["p1"])

    # --- Feature 2b: a match more than 200 bytes from any header is skipped.
    far_notes = b"alpha\n" + b"x" * 400 + b"beta entry text here\n"
    far_off = far_notes.index(b"beta")
    far_lines = [
        "### R10 (d) @offset 0",
        "- Says: alpha",
        "- Status: LIVE",
    ]
    far_headers = parse_headers(far_lines)
    _, far_matched, far_unm = compute_insertions(
        [row], {"p1": "beta entry text here"}, far_headers, far_notes, DATE
    )
    # RED if the 200-byte limit were dropped: far_matched would contain p1.
    check("f2b-far-skipped", far_matched == [])
    check("f2b-far-reported", far_unm == ["p1"])

    # --- Feature 3: same line never inserted twice.
    dup = apply_insertions(lines, {"R20": [ins["R20"][0], ins["R20"][0]]})
    check("f3-dedup",
          sum(1 for x in dup if x.startswith("- Fidelity")) == 1)

    # --- Feature 4: --extra id not in ledger raises MissingId (exit 1 path).
    extra_ins = {"R999": ["- Fidelity (%s): x" % DATE]}
    try:
        apply_insertions(lines, extra_ins)
        check("f4-missing-raises", False)
    except MissingId as e:
        # RED if a missing id were silently ignored: no exception would raise.
        check("f4-missing-raises", e.rid == "R999")

    # --- Feature 5: assert_sequence catches a reorder/loss.
    seq_ok = True
    try:
        assert_sequence(["a", "b"], ["a", "NEW", "b"], 1)
    except AssertionError:
        seq_ok = False
    check("f5-seq-ok", seq_ok)
    seq_bad = False
    try:
        assert_sequence(["a", "b"], ["b", "a"], 0)
    except AssertionError:
        seq_bad = True
    # RED if the order assertion were removed: seq_bad would stay False.
    check("f5-seq-catches-reorder", seq_bad)

    print("selftest:", "PASS" if not failures else "FAIL " + ", ".join(failures))
    return 0 if not failures else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--ledger")
    ap.add_argument("--notes")
    ap.add_argument("--pairs")
    ap.add_argument("--checks", nargs="+")
    ap.add_argument("--extra")
    ap.add_argument("--date")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    missing = [n for n in ("ledger", "notes", "pairs", "checks", "date")
               if not getattr(args, n)]
    if missing:
        ap.error("required: " + ", ".join("--" + n for n in missing))
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
