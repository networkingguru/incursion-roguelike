#!/usr/bin/env python3
"""Red-before proof for the tools/fidelity selftests.

Copies each tool, applies one targeted mutation that breaks a feature, and
shows the matching selftest assertion fails (non-zero exit). With no mutation
the selftest passes. Standard library only.

Usage:
    python3 -I tools/fidelity/red_proof.py --outdir <dir>
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

# (tool, mutation label, old substring, new substring)
MUTATIONS = [
    ("coverage.py", "break-lookahead",
     r'NOTES_R_RE = re.compile(r"\bR(\d+)(?=[ ,(])")',
     r'NOTES_R_RE = re.compile(r"\bR(\d+)")'),
    ("coverage.py", "break-header-boundary",
     r'LEDGER_R_RE = re.compile(r"^### R(\d+)\b", re.M)',
     'LEDGER_R_RE = re.compile(r"^### R(\\\\d+)", re.M)'),
    ("coverage.py", "break-upper-limit",
     'if int(x) >= 1})', 'if 1 <= int(x) <= 266})'),
    ("coverage.py", "break-lower-bound",
     'if int(x) >= 1})', 'if int(x) >= 0})'),
    ("make_batches.py", "break-round-robin",
     'buckets[i % n].append(item)', 'buckets[i % 1].append(item)'),
    ("make_batches.py", "break-judge-id",
     '"blind_id": p["pair_id"],', '"blind_id": p.get("question_text"),'),
    ("make_batches.py", "break-supersede",
     'scores[bid] = {', 'scores.setdefault(bid, {'),
    ("make_batches.py", "break-threshold",
     'if s["probability"] >= threshold:', 'if s["probability"] > threshold:'),
    ("make_batches.py", "break-sort",
     'kept.sort(key=lambda t: t[1]["probability"], reverse=True)',
     'kept.sort(key=lambda t: t[1]["probability"], reverse=False)'),
    ("make_batches.py", "break-q-window",
     '(p.get("question_text") or "")[-6000:]',
     '(p.get("question_text") or "")[-6001:]'),
    ("make_batches.py", "break-r-window",
     '(p.get("ruling_text") or "")[:8000]',
     '(p.get("ruling_text") or "")[:8001]'),
    ("mark_ledger.py", "break-offset-side",
     'if off is None or off > offset:', 'if off is None or off >= offset:'),
    ("mark_ledger.py", "break-200-byte",
     '(off - best[1]) > 200', '(off - best[1]) > 10**9'),
    ("mark_ledger.py", "break-dedup",
     'if fl not in insert_after[idx]:', 'if True:'),
    ("mark_ledger.py", "break-insertion-pos",
     'insert_after.setdefault(idx, [])', 'insert_after.setdefault(idx - 1, [])'),
    ("mark_ledger.py", "break-seq-reorder",
     '    assert oi == len(old), "old lines missing or reordered in new file"\n'
     '    assert added == inserted_count, (\n'
     '        "inserted-line count mismatch: expected %d, got %d" % (inserted_count, added)\n'
     '    )',
     '    pass  # mut: both sequence assertions removed'),
    ("mark_ledger.py", "break-missing-id",
     'raise MissingId(hid)', 'pass'),
]


def run_selftest(path):
    p = subprocess.run([sys.executable, "-I", path, "--selftest"],
                       capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    rows = []
    for tool, label, old, new in MUTATIONS:
        src = os.path.join(HERE, tool)
        with open(src, "r", encoding="utf-8") as fh:
            text = fh.read()
        if old not in text:
            rows.append((tool, label, "MUTATION-NOT-FOUND", ""))
            continue
        with tempfile.TemporaryDirectory() as tmp:
            broken = os.path.join(tmp, tool)
            with open(broken, "w", encoding="utf-8") as fh:
                fh.write(text.replace(old, new, 1))
            rc, out, err = run_selftest(broken)
        verdict = "RED-OK" if rc != 0 else "NOT-RED"
        rows.append((tool, label, verdict, out or err))

    print("%-16s %-22s %-18s %s" % ("tool", "mutation", "verdict", "selftest"))
    for tool, label, verdict, out in rows:
        print("%-16s %-22s %-18s %s" % (tool, label, verdict, out))

    bad = [r for r in rows if r[2] != "RED-OK"]
    print("\nred-proof:", "PASS" if not bad else "FAIL (%d not red)" % len(bad))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
