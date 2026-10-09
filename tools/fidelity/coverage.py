#!/usr/bin/env python3
"""Check that every ruling number in the notes has a ledger header.

A ruling number is `R<digits>` followed by a space, comma or `(` in the notes
(the pattern from cover.py). Every ruling number found in the notes MUST have a
ledger header `### R<n>` (word boundary after the number). Every number found is
taken; there is no upper limit. The lower bound R1 is kept: `R0` is not a ruling
number (in the notes it only appears as a rung reference, "at R0").

Exit 0 when none missing, 1 when any missing, 2 when a file cannot be read or
the notes hold no ruling number at all (a check that finds nothing to check
MUST NOT pass).

Standard library only. See brief.

Usage:
    python3 -I tools/fidelity/coverage.py --selftest
    python3 -I tools/fidelity/coverage.py --notes <notes.txt> --ledger <ledger.md>
"""

import argparse
import re
import sys

NOTES_R_RE = re.compile(r"\bR(\d+)(?=[ ,(])")
LEDGER_R_RE = re.compile(r"^### R(\d+)\b", re.M)


def find_want(notes_text):
    """Sorted unique ruling numbers found in the notes (R1 or higher)."""
    return sorted({int(x) for x in NOTES_R_RE.findall(notes_text) if int(x) >= 1})


def find_have(ledger_text):
    """Set of ruling numbers with a `### R<n>` header in the ledger."""
    return {int(x) for x in LEDGER_R_RE.findall(ledger_text)}


def check(notes_text, ledger_text):
    """Return (want, have, missing)."""
    want = find_want(notes_text)
    have = find_have(ledger_text)
    missing = [r for r in want if r not in have]
    return want, have, missing


def run(notes_path, ledger_path):
    try:
        with open(notes_path, "r", encoding="utf-8") as fh:
            notes_text = fh.read()
    except OSError as e:
        sys.stderr.write("cannot read notes: %s: %s\n" % (notes_path, e))
        return 2
    try:
        with open(ledger_path, "r", encoding="utf-8") as fh:
            ledger_text = fh.read()
    except OSError as e:
        sys.stderr.write("cannot read ledger: %s: %s\n" % (ledger_path, e))
        return 2

    want, have, missing = check(notes_text, ledger_text)

    if not want:
        sys.stderr.write("nothing to check: notes hold no ruling number\n")
        return 2

    print("want %d have %d missing %s" % (len(want), len(have), missing))
    return 1 if missing else 0


def selftest():
    """In-memory checks. Each has a stated red-before failure."""
    failures = []

    def check_eq(name, got, want):
        if got != want:
            failures.append("%s: got %r want %r" % (name, got, want))

    notes = (
        "R1 is a ruling. R2, too. See R3(here). R100 (later). "
        "R2 again, deduplicated. NotR4 nope. R5x no boundary. R6\n"
    )
    # RED if boundary dropped or lookahead widened: R5/R6 would appear.
    check_eq("want-set", find_want(notes), [1, 2, 3, 100])

    ledger = (
        "### R1 (d) @offset 0\n- Status: LIVE\n\n"
        "### R2 (d) @offset 5\n- Status: LIVE\n\n"
        "### R3 (d) @offset 9\n- Status: LIVE\n\n"
        "### R100 (d) @offset 12\n- Status: LIVE\n"
    )
    w, h, m = check(notes, ledger)
    check_eq("full-want", w, [1, 2, 3, 100])
    check_eq("full-missing", m, [])

    # RED for the header word-boundary: `### R10` must not satisfy R100.
    bad_ledger = ledger.replace("### R100", "### R10")
    _, _, m2 = check(notes, bad_ledger)
    check_eq("boundary-missing", m2, [100])

    # RED for taking every number: a >266 number must be required.
    notes_hi = "R266 yes. R300, yes. R9999 (yes).\n"
    ledger_hi = "### R266 x\n### R300 x\n"
    _, _, m3 = check(notes_hi, ledger_hi)
    check_eq("no-upper-limit", m3, [9999])

    # R0 is a rung reference, not a ruling number, and must be excluded.
    # RED if the lower bound is dropped: want would then include 0.
    check_eq("r0-excluded", find_want("a rung, at R0 (base). R1 is a ruling.\n"),
             [1])

    # RED for "nothing to check must not pass": empty want.
    check_eq("empty-want", find_want("no ruling here"), [])

    print("selftest:", "PASS" if not failures else "FAIL " + "; ".join(failures))
    return 0 if not failures else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--notes")
    ap.add_argument("--ledger")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    if not args.notes or not args.ledger:
        ap.error("--notes and --ledger are required")
    return run(args.notes, args.ledger)


if __name__ == "__main__":
    sys.exit(main())
