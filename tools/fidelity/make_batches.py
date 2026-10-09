#!/usr/bin/env python3
"""Deal ruling pairs into judge and flag batches.

Two subcommands:

    judge --pairs <pairs.jsonl> --batches <N> --outdir <dir>
        Write <dir>/batch<i>.jsonl for i in 0..N-1, pairs dealt round-robin in
        file order. Each line: blind_id (= pair_id), question_text, brian_text,
        ruling_text, nothing else. Print the count per batch.

    flags --pairs <pairs.jsonl> --scores <out files...> --threshold 0.3
          --batches <N> --outdir <dir>
        Read every judge output line {"blind_id","probability","reason"} from
        the score files IN THE ORDER GIVEN; a later file's line for the same id
        replaces an earlier one (a re-judge supersedes the first run). Exit 1 and
        name the ids when a pair has no score, or a score id is not in pairs.
        Keep pairs with probability >= threshold, sorted by probability
        descending, dealt round-robin into <dir>/flags<i>.jsonl. Each line:
        pair_id, score, judge_reason, r_numbers, pairing, brian_reused,
        write_ts, brian_ts, question_text (last 6000 chars), brian_text,
        ruling_text (first 8000 chars). Print the flag count.

Standard library only. See brief.

Usage:
    python3 -I tools/fidelity/make_batches.py --selftest
    python3 -I tools/fidelity/make_batches.py judge --pairs P --batches N --outdir D
    python3 -I tools/fidelity/make_batches.py flags --pairs P --scores S... --threshold 0.3 --batches N --outdir D
"""

import argparse
import json
import os
import sys

JUDGE_FIELDS = ("blind_id", "question_text", "brian_text", "ruling_text")
FLAG_FIELDS = (
    "pair_id",
    "score",
    "judge_reason",
    "r_numbers",
    "pairing",
    "brian_reused",
    "write_ts",
    "brian_ts",
    "question_text",
    "brian_text",
    "ruling_text",
)


def load_pairs(path):
    """Read pairs.jsonl into a list of dicts, in file order."""
    out = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def deal_round_robin(items, n):
    """Deal items into n buckets round-robin in order. Returns list of buckets."""
    buckets = [[] for _ in range(n)]
    for i, item in enumerate(items):
        buckets[i % n].append(item)
    return buckets


def write_jsonl(path, rows):
    with open(path, "w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")


def judge(pairs, batches, outdir):
    rows = [
        {
            "blind_id": p["pair_id"],
            "question_text": p.get("question_text"),
            "brian_text": p.get("brian_text"),
            "ruling_text": p.get("ruling_text"),
        }
        for p in pairs
    ]
    os.makedirs(outdir, exist_ok=True)
    buckets = deal_round_robin(rows, batches)
    for i, bucket in enumerate(buckets):
        write_jsonl(os.path.join(outdir, "batch%d.jsonl" % i), bucket)
        print("batch%d: %d" % (i, len(bucket)))


def load_scores(paths):
    """Return dict blind_id -> {"probability","reason"}; later file wins."""
    scores = {}
    order = []
    for path in paths:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                o = json.loads(line)
                bid = o["blind_id"]
                if bid not in scores:
                    order.append(bid)
                scores[bid] = {
                    "probability": o["probability"],
                    "reason": o.get("reason", ""),
                }
    return scores


def flags(pairs, scorepaths, threshold, batches, outdir):
    scores = load_scores(scorepaths)
    by_id = {p["pair_id"]: p for p in pairs}

    missing = [p["pair_id"] for p in pairs if p["pair_id"] not in scores]
    extra = [b for b in scores if b not in by_id]
    bad = False
    if missing:
        sys.stderr.write("no score for pair ids: %s\n" % ", ".join(missing))
        bad = True
    if extra:
        sys.stderr.write("score ids not in pairs: %s\n" % ", ".join(extra))
        bad = True
    if bad:
        return 1

    kept = []
    for p in pairs:
        pid = p["pair_id"]
        s = scores[pid]
        if s["probability"] >= threshold:
            kept.append((p, s))
    kept.sort(key=lambda t: t[1]["probability"], reverse=True)

    rows = []
    for p, s in kept:
        rows.append({
            "pair_id": p["pair_id"],
            "score": s["probability"],
            "judge_reason": s["reason"],
            "r_numbers": p.get("r_numbers"),
            "pairing": p.get("pairing"),
            "brian_reused": p.get("brian_reused"),
            "write_ts": p.get("write_ts"),
            "brian_ts": p.get("brian_ts"),
            "question_text": (p.get("question_text") or "")[-6000:],
            "brian_text": p.get("brian_text"),
            "ruling_text": (p.get("ruling_text") or "")[:8000],
        })

    os.makedirs(outdir, exist_ok=True)
    buckets = deal_round_robin(rows, batches)
    for i, bucket in enumerate(buckets):
        write_jsonl(os.path.join(outdir, "flags%d.jsonl" % i), bucket)
    print("flags: %d" % len(rows))
    return 0


def run_judge(args):
    pairs = load_pairs(args.pairs)
    judge(pairs, args.batches, args.outdir)
    return 0


def run_flags(args):
    pairs = load_pairs(args.pairs)
    return flags(pairs, args.scores, args.threshold, args.batches, args.outdir)


def selftest():
    """In-memory checks. Each has a stated red-before failure."""
    failures = []

    def check_eq(name, got, want):
        if got != want:
            failures.append("%s: got %r want %r" % (name, got, want))

    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        # --- judge: round-robin order and exact field set.
        pairs = [
            {"pair_id": "a", "question_text": "qa", "brian_text": "ba",
             "ruling_text": "ra", "extra": "DROP"},
            {"pair_id": "b", "question_text": "qb", "brian_text": "bb",
             "ruling_text": "rb"},
            {"pair_id": "c", "question_text": "qc", "brian_text": "bc",
             "ruling_text": "rc"},
            {"pair_id": "d", "question_text": "qd", "brian_text": "bd",
             "ruling_text": "rd"},
            {"pair_id": "e", "question_text": "qe", "brian_text": "be",
             "ruling_text": "re"},
        ]
        judge(pairs, 2, tmp)
        b0 = [json.loads(l) for l in open(os.path.join(tmp, "batch0.jsonl"))]
        b1 = [json.loads(l) for l in open(os.path.join(tmp, "batch1.jsonl"))]
        # RED if deal were sequential or off-by-one: ids would differ.
        check_eq("judge-b0-ids", [r["blind_id"] for r in b0], ["a", "c", "e"])
        check_eq("judge-b1-ids", [r["blind_id"] for r in b1], ["b", "d"])
        # RED if an extra field leaked: set would not equal JUDGE_FIELDS.
        check_eq("judge-fields", set(b0[0].keys()), set(JUDGE_FIELDS))
        check_eq("judge-count", len(b0) + len(b1), 5)

        # --- flags: later score file supersedes earlier.
        sp1 = os.path.join(tmp, "s1.jsonl")
        sp2 = os.path.join(tmp, "s2.jsonl")
        with open(sp1, "w") as fh:
            fh.write(json.dumps({"blind_id": "a", "probability": 0.9,
                                 "reason": "old"}) + "\n")
            fh.write(json.dumps({"blind_id": "b", "probability": 0.1,
                                 "reason": "low"}) + "\n")
        with open(sp2, "w") as fh:
            fh.write(json.dumps({"blind_id": "a", "probability": 0.2,
                                 "reason": "new"}) + "\n")
            fh.write(json.dumps({"blind_id": "c", "probability": 0.5,
                                 "reason": "mid"}) + "\n")
        # pairs a,b,c,d all need scores; d has none -> failure naming d.
        pairs4 = [{"pair_id": x, "question_text": "q", "brian_text": "b",
                   "ruling_text": "r", "r_numbers": [1], "pairing": "quote",
                   "brian_reused": False, "write_ts": "wt",
                   "brian_ts": "bt"} for x in ("a", "b", "c", "d")]
        rc = flags(pairs4, [sp1, sp2], 0.3, 2, os.path.join(tmp, "f"))
        # RED if missing scores were tolerated: rc would be 0.
        check_eq("flags-missing-rc", rc, 1)

        # add d's score so all present; a must take the NEW 0.2 (below thresh),
        # so only c (0.5) survives. RED if earlier file won: a would be 0.9.
        with open(sp2, "a") as fh:
            fh.write(json.dumps({"blind_id": "d", "probability": 0.31,
                                 "reason": "d"}) + "\n")
        outdir = os.path.join(tmp, "f2")
        rc2 = flags(pairs4, [sp1, sp2], 0.3, 2, outdir)
        check_eq("flags-rc", rc2, 0)
        allflags = []
        for i in range(2):
            p = os.path.join(outdir, "flags%d.jsonl" % i)
            if os.path.exists(p):
                allflags += [json.loads(l) for l in open(p)]
        ids = sorted(r["pair_id"] for r in allflags)
        # RED if supersede failed: "a" would appear with score 0.9.
        check_eq("flags-supersede", ids, ["c", "d"])
        check_eq("flags-sorted", [r["pair_id"] for r in allflags[:2]]
                 if len(allflags) == 2 else ids, ["c", "d"])
        check_eq("flags-fields", set(allflags[0].keys()), set(FLAG_FIELDS))

        # --- threshold is inclusive: a score exactly 0.3 must be kept.
        # RED if `>` replaced `>=`: "e" would drop and rc-e would report 1.
        spb = os.path.join(tmp, "sb.jsonl")
        with open(spb, "w") as fh:
            fh.write(json.dumps({"blind_id": "e", "probability": 0.3,
                                 "reason": "edge"}) + "\n")
        pairs_e = [{"pair_id": "e", "question_text": "q", "brian_text": "b",
                    "ruling_text": "r"}]
        outdir_e = os.path.join(tmp, "fe")
        rc_e = flags(pairs_e, [spb], 0.3, 1, outdir_e)
        check_eq("flags-threshold-rc", rc_e, 0)
        erow = json.loads(open(os.path.join(outdir_e, "flags0.jsonl")).readline())
        check_eq("flags-threshold-kept", erow["pair_id"], "e")

        # RED for score id not in pairs.
        pairs_short = [{"pair_id": "a", "question_text": "q",
                        "brian_text": "b", "ruling_text": "r"}]
        rc3 = flags(pairs_short, [sp1, sp2], 0.3, 1, os.path.join(tmp, "f3"))
        check_eq("flags-extra-rc", rc3, 1)

        # RED for truncation windows: 6000 tail / 8000 head.
        long_q = "x" * 7000
        long_r = "y" * 9000
        pairs_trunc = [{"pair_id": "a", "question_text": long_q,
                        "brian_text": "b", "ruling_text": long_r}]
        with open(os.path.join(tmp, "st.jsonl"), "w") as fh:
            fh.write(json.dumps({"blind_id": "a", "probability": 1.0,
                                 "reason": ""}) + "\n")
        flags(pairs_trunc, [os.path.join(tmp, "st.jsonl")], 0.5, 1,
              os.path.join(tmp, "f4"))
        row = json.loads(open(os.path.join(tmp, "f4", "flags0.jsonl")).readline())
        check_eq("flags-q-len", len(row["question_text"]), 6000)
        check_eq("flags-r-len", len(row["ruling_text"]), 8000)
        check_eq("flags-q-tail", row["question_text"], long_q[-6000:])

    print("selftest:", "PASS" if not failures else "FAIL " + "; ".join(failures))
    return 0 if not failures else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--selftest", action="store_true")
    sub = ap.add_subparsers(dest="cmd")

    pj = sub.add_parser("judge")
    pj.add_argument("--pairs", required=True)
    pj.add_argument("--batches", type=int, required=True)
    pj.add_argument("--outdir", required=True)

    pf = sub.add_parser("flags")
    pf.add_argument("--pairs", required=True)
    pf.add_argument("--scores", nargs="+", required=True)
    pf.add_argument("--threshold", type=float, default=0.3)
    pf.add_argument("--batches", type=int, required=True)
    pf.add_argument("--outdir", required=True)

    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if args.cmd == "judge":
        return run_judge(args)
    if args.cmd == "flags":
        return run_flags(args)
    ap.error("a subcommand (judge or flags) is required")


if __name__ == "__main__":
    sys.exit(main())
