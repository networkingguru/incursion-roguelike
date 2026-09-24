#!/usr/bin/env python3
"""Measure how well the Jev decision model tells duplicate bead pairs apart.

    tools/bead_dupe_judge.py                     judge the frozen fixture
    tools/bead_dupe_judge.py --dry-run           print the first request, send nothing
    tools/bead_dupe_judge.py --mode full         send whole descriptions
    tools/bead_dupe_judge.py --selftest          prove the response parser still bites

WHY THIS EXISTS. inc-zu0r asks whether a language model can do the job
`bd find-duplicates` does by word overlap alone: given two beads, decide whether
they describe the same defect. This is a MEASUREMENT, not a gate. It sends each
pair in tools/fixtures/bead-dupe-pairs.tsv to the TypeSafe Jev decision endpoint
on OpenRouter, one request per pair, and prints the separation between the 13
known-duplicate pairs and the 13 hard negatives chosen to look like them.

The fixture and the request body are frozen as of 2026-09-24; the verified
response shape is:

    {"model":"typesafe/jev-1.13-20260917",
     "answers":{"same_defect":{"type":"noul","noul":0.52}},
     "usage":{"input_tokens":329,"output_tokens":22,"cost":0.000013818},
     "id":"gen-dec-...","provider":"TypeSafe"}

The probability is answers.same_defect.noul. If that path is missing, or is not
a number in [0,1], the pair is recorded as an error and its raw body is printed
-- the script never guesses a value. An HTTP error records the status and body
for that pair and moves on. A bead id named in the fixture but absent from the
bead data fails the whole run with exit 2 before any request is sent.

Standard library only. The API key is read from OPENROUTER_API_KEY, or from the
macOS Keychain (account `incursion`, service `incursion-openrouter`). It is
never printed, logged or written.

Exit: 0 every pair judged
      1 one or more pairs errored
      2 could not measure (no key, unreadable fixture, missing bead id, bad reply)
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bead_dupes  # noqa: E402  (the shared engine: key, request, parse)
from bead_dupes import (  # noqa: E402
    parse_response, resolve_key,
)

REPO_ROOT = Path(__file__).resolve().parent.parent

# The key, request and parse functions live in tools/bead_dupes.py; this file
# imports them so there is one copy of each. Its behaviour is unchanged.

SHORT_DESCRIPTION_CAP = 800  # characters, for --mode short


# ---------------------------------------------------------------- fixture

def load_pairs(path):
    """Parse the tab-separated fixture. Returns a list of dicts.

    `#` lines and blank lines are skipped; the first surviving line is the
    header, which must name the four columns. A malformed row or a label that
    is not 0 or 1 is exit 2 -- a silently dropped pair would corrupt every
    number printed afterwards.
    """
    rows = []
    text = Path(path).read_text()
    lines = [ln for ln in text.splitlines()
             if ln.strip() and not ln.lstrip().startswith("#")]
    if not lines:
        print("bead_dupe_judge: fixture %s is empty" % path, file=sys.stderr)
        sys.exit(2)

    header = lines[0].split("\t")
    if header[:4] != ["a", "b", "label", "source"]:
        print("bead_dupe_judge: fixture %s has header %r, wanted "
              "['a','b','label','source']" % (path, header), file=sys.stderr)
        sys.exit(2)

    for lineno, line in enumerate(lines[1:], 2):
        cols = line.split("\t")
        if len(cols) < 4:
            print("bead_dupe_judge: fixture %s line %d has %d columns, wanted 4"
                  % (path, lineno, len(cols)), file=sys.stderr)
            sys.exit(2)
        a, b, label, source = cols[0], cols[1], cols[2], cols[3]
        if label not in ("0", "1"):
            print("bead_dupe_judge: fixture %s line %d has label %r, wanted 0 "
                  "or 1" % (path, lineno, label), file=sys.stderr)
            sys.exit(2)
        rows.append({"a": a, "b": b, "label": int(label), "source": source})
    return rows


def load_beads(beads_json, pairs):
    """The bead data, from --beads-json or `bd list`. Exit 2 on any failure.

    Checks here, before a single request is sent, that every id named in the
    fixture is present, and names the first missing one.
    """
    if beads_json:
        try:
            data = json.loads(Path(beads_json).read_text())
        except (OSError, ValueError) as exc:
            print("bead_dupe_judge: cannot read %s: %s" % (beads_json, exc),
                  file=sys.stderr)
            sys.exit(2)
    else:
        try:
            proc = subprocess.run(
                ["bd", "list", "--all", "--limit", "0", "--json"],
                capture_output=True, text=True, cwd=str(REPO_ROOT),
            )
        except OSError as exc:
            print("bead_dupe_judge: cannot run `bd`: %s" % exc, file=sys.stderr)
            sys.exit(2)
        if proc.returncode != 0:
            print("bead_dupe_judge: `bd list` failed: %s"
                  % proc.stderr.strip(), file=sys.stderr)
            sys.exit(2)
        try:
            data = json.loads(proc.stdout)
        except ValueError as exc:
            print("bead_dupe_judge: `bd list` did not print JSON: %s" % exc,
                  file=sys.stderr)
            sys.exit(2)

    if isinstance(data, dict):
        data = data.get("issues") or []
    if not isinstance(data, list):
        print("bead_dupe_judge: bead data is not an array", file=sys.stderr)
        sys.exit(2)

    by_id = {}
    for bead in data:
        if isinstance(bead, dict) and bead.get("id"):
            by_id[bead["id"]] = bead

    wanted = []
    for row in pairs:
        for bead_id in (row["a"], row["b"]):
            if bead_id not in wanted:
                wanted.append(bead_id)
    for bead_id in wanted:
        if bead_id not in by_id:
            print("bead_dupe_judge: bead id %s from the fixture is missing from "
                  "the bead data" % bead_id, file=sys.stderr)
            sys.exit(2)
    return by_id


# ---------------------------------------------------------------- body

def short_description(text):
    """The first paragraph, up to the first blank line, cut to 800 chars.

    The judge's short mode differs from the engine's bead_state(): the engine
    cuts the whole description to DESCRIPTION_CAP, while --mode short wants the
    FIRST PARAGRAPH and an 800-character cap. Kept here so the frozen
    measurement stays reproducible.
    """
    if text is None:
        text = ""
    para = []
    for line in text.splitlines():
        if line.strip() == "":
            break
        para.append(line)
    joined = "\n".join(para).strip()
    return joined[:SHORT_DESCRIPTION_CAP]


def bead_state(bead, mode):
    """One bead's contribution to `state`."""
    title = bead.get("title") or ""
    description = bead.get("description") or ""
    if mode == "short":
        description = short_description(description)
    return {"title": title, "description": description}


def build_body(bead_a, bead_b, mode):
    """The request body for one pair. Frozen shape; see the verified response.

    Built on the engine's MODEL, QUESTION and INSTRUCTIONS so the two cannot
    drift; bead_state stays local because short mode is the judge's own.
    """
    return {
        "model": bead_dupes.MODEL,
        "state": {
            "bead_a": bead_state(bead_a, mode),
            "bead_b": bead_state(bead_b, mode),
        },
        "questions": {
            bead_dupes.QUESTION: {"type": "noul",
                                  "instructions": bead_dupes.INSTRUCTIONS},
        },
    }


# ---------------------------------------------------------------- parser

# parse_response and resolve_key are imported from bead_dupes; the judge keeps
# none of its own. The judge's send_request wraps the engine's so a network
# failure still exits 2 here (the engine raises, so its callers can record the
# pair as unavailable instead).


# ---------------------------------------------------------------- transport

def send_request(key, body, timeout=120):
    """POST one body. Returns (status, response_text).

    An HTTP error is a response and is returned like any other; only a failure
    to reach a server at all exits 2, because no pair can be judged against a
    network that is down.
    """
    try:
        return bead_dupes.send_request(key, body, timeout=timeout)
    except OSError as exc:
        print("bead_dupe_judge: %s" % exc, file=sys.stderr)
        sys.exit(2)


# ---------------------------------------------------------------- statistics

def auc(results):
    """ROC AUC over the judged pairs, ties counted as 0.5.

    Defined as (wins + 0.5*ties) / (positives * negatives). Pairs that errored
    carry no probability and are excluded; the denominator counts the
    positives and negatives that were actually judged.
    """
    pos = [r["probability"] for r in results
           if r["label"] == 1 and r["probability"] is not None]
    neg = [r["probability"] for r in results
           if r["label"] == 0 and r["probability"] is not None]
    if not pos or not neg:
        return None
    wins = ties = 0
    for p in pos:
        for n in neg:
            if p > n:
                wins += 1
            elif p == n:
                ties += 1
    return (wins + 0.5 * ties) / (len(pos) * len(neg))


def separation(results):
    """Lowest positive probability and highest negative probability."""
    pos = [r["probability"] for r in results
           if r["label"] == 1 and r["probability"] is not None]
    neg = [r["probability"] for r in results
           if r["label"] == 0 and r["probability"] is not None]
    lo_pos = min(pos) if pos else None
    hi_neg = max(neg) if neg else None
    if lo_pos is None or hi_neg is None:
        return lo_pos, hi_neg, None
    return lo_pos, hi_neg, lo_pos > hi_neg


def threshold_counts(results, threshold):
    """(true positives, false positives, false negatives) at a threshold."""
    tp = fp = fn = 0
    for r in results:
        p = r["probability"]
        if p is None:
            continue
        predicted = p >= threshold
        if r["label"] == 1:
            if predicted:
                tp += 1
            else:
                fn += 1
        elif predicted:
            fp += 1
    return tp, fp, fn


# ---------------------------------------------------------------- selftest

VERIFIED_RESPONSE = (
    '{"model":"typesafe/jev-1.13-20260917",'
    '"answers":{"same_defect":{"type":"noul","noul":0.52}},'
    '"usage":{"input_tokens":329,"output_tokens":22,"cost":0.000013818},'
    '"id":"gen-dec-...","provider":"TypeSafe"}'
)


def selftest():
    """Feed the parser the shapes that matter and prove it still bites."""
    fail = 0

    prob, cost, resp_id = parse_response(VERIFIED_RESPONSE)
    if prob != 0.52:
        print("SELFTEST FAIL: verified response gave %r, wanted 0.52" % prob)
        fail = 1
    if abs((cost or 0.0) - 0.000013818) > 1e-12:
        print("SELFTEST FAIL: verified response cost was %r" % cost)
        fail = 1
    if resp_id != "gen-dec-...":
        print("SELFTEST FAIL: verified response id was %r" % resp_id)
        fail = 1

    try:
        parse_response('{"id":"gen-dec-x","usage":{"cost":0.1}}')
        print("SELFTEST FAIL: a body missing answers did not raise")
        fail = 1
    except ValueError:
        pass

    try:
        parse_response('{"answers":{"same_defect":{"type":"noul","noul":1.7}}}')
        print("SELFTEST FAIL: noul 1.7 (out of range) did not raise")
        fail = 1
    except ValueError:
        pass

    for bad in ('{"answers":{"same_defect":{"type":"noul"}}}',
                '{"answers":{"same_defect":{"noul":"high"}}}',
                'not json'):
        try:
            parse_response(bad)
            print("SELFTEST FAIL: %r did not raise" % bad)
            fail = 1
        except ValueError:
            pass

    if fail == 0:
        print("SELFTEST PASS: the response parser accepts the verified body "
              "and rejects four broken ones")
    return fail


# ---------------------------------------------------------------- report

def fmt(value):
    return "n/a" if value is None else "%.4f" % value


def report(results, total_cost, error_count):
    """Print the table, separation, thresholds, AUC and costs."""
    print("")
    print("a\tb\tlabel\tprobability")
    for r in sorted(results, key=lambda x: (x["probability"] is None,
                                            -(x["probability"] or 0.0))):
        print("%s\t%s\t%d\t%s" % (r["a"], r["b"], r["label"], fmt(r["probability"])))

    lo_pos, hi_neg, clean = separation(results)
    print("")
    print("separation:")
    print("  lowest positive probability:  %s" % fmt(lo_pos))
    print("  highest negative probability: %s" % fmt(hi_neg))
    if clean is None:
        print("  every positive above every negative: unknown (a label missing)")
    elif clean:
        print("  every positive above every negative: YES")
    else:
        print("  every positive above every negative: NO")

    print("")
    print("thresholds:")
    print("  threshold\ttp\tfp\tfn")
    for t in (0.5, 0.7, 0.9):
        tp, fp, fn = threshold_counts(results, t)
        print("  %.1f\t\t%d\t%d\t%d" % (t, tp, fp, fn))

    a = auc(results)
    print("")
    print("ROC AUC: %s" % ("n/a" if a is None else "%.4f" % a))
    print("total cost: $%.6f" % total_cost)
    print("errors: %d" % error_count)


# ---------------------------------------------------------------- main

def run(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pairs", default="tools/fixtures/bead-dupe-pairs.tsv")
    parser.add_argument("--beads-json")
    parser.add_argument("--mode", choices=["full", "short"], default="short")
    parser.add_argument("--out")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--max-cost", type=float, default=0.05)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)

    if args.selftest:
        return selftest()

    pairs_path = (REPO_ROOT / args.pairs
                  if not os.path.isabs(args.pairs) else Path(args.pairs))
    out_path = Path(args.out) if args.out else (
        REPO_ROOT / "logs" / ("bead-dupe-judge-%s.jsonl" % args.mode))

    pairs = load_pairs(pairs_path)
    beads = load_beads(args.beads_json, pairs)

    if args.dry_run:
        first = pairs[0]
        body = build_body(beads[first["a"]], beads[first["b"]], args.mode)
        print(json.dumps(body, indent=2))
        return 0

    key = resolve_key()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    results = []
    total_cost = 0.0
    error_count = 0

    with out_path.open("w") as out:
        for row in pairs:
            if total_cost >= args.max_cost:
                print("bead_dupe_judge: stopping before %s/%s -- cost $%.6f has "
                      "reached the cap $%.6f"
                      % (row["a"], row["b"], total_cost, args.max_cost),
                      file=sys.stderr)
                break

            body = build_body(beads[row["a"]], beads[row["b"]], args.mode)
            status, text = send_request(key, body)

            record = {"a": row["a"], "b": row["b"], "label": row["label"],
                      "probability": None, "cost": None, "id": None,
                      "error": None, "http_status": status}

            if status < 200 or status >= 300:
                record["error"] = "HTTP %d" % status
                error_count += 1
                print("bead_dupe_judge: HTTP %d for %s/%s"
                      % (status, row["a"], row["b"]), file=sys.stderr)
                print(text[:2000], file=sys.stderr)
            else:
                try:
                    prob, cost, resp_id = parse_response(text)
                    record["probability"] = prob
                    record["cost"] = cost
                    record["id"] = resp_id
                    if cost:
                        total_cost += cost
                except ValueError as exc:
                    record["error"] = str(exc)
                    error_count += 1
                    print("bead_dupe_judge: bad reply for %s/%s: %s"
                          % (row["a"], row["b"], exc), file=sys.stderr)
                    print(text[:2000], file=sys.stderr)

            results.append(record)
            out.write(json.dumps(record, separators=(",", ":")) + "\n")
            out.flush()

    report(results, total_cost, error_count)
    return 1 if error_count else 0


def main():
    try:
        sys.exit(run(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 - fail closed, never a traceback
        print("bead_dupe_judge: error: %s" % exc, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
