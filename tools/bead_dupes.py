#!/usr/bin/env python3
"""The one engine that checks whether a bead duplicates an existing one.

    tools/bead_dupes.py check-draft --title T --description-file F [--parent P]
    tools/bead_dupes.py check-bead ID --against open
    tools/bead_dupes.py sweep --all
    tools/bead_dupes.py sweep --since-last
    tools/bead_dupes.py draft-args [--stdin-temp PATH] -- <bd create argv...>
    tools/bead_dupes.py --selftest

check-draft's --json-out PATH writes the judged hits (or {"unavailable": reason})
for bead_new.sh to read; the wrapper never scrapes stdout.

A sweep prints each hit as a PAIR (both ids, both statuses, probability, both
titles) because a sweep has many subjects. `sweep --json-out PATH` writes EVERY
judged pair, not only hits, plus totals and failures, so a full record survives
and a re-run is never needed to recover a result.

WHY THIS EXISTS. inc-zu0r measured Jev (typesafe/jev-1.13 on OpenRouter) as
the decision model that tells duplicate bead pairs apart (AUC 0.976 on the
frozen fixture) where word overlap alone does not (0.548). Word overlap only
PRESELECTS candidates; Jev judges; Jev sees full title and description.

Every subcommand takes --beads-json PATH so it can run offline on a file
instead of the live `bd list --all --limit 0 --json`. Without it, the live
database is read. Bead links (duplicates / relates-to / parent-child) are NOT
in `bd list --json`, so they are read from `bd show <id> [<id>...] --json`,
batched at most 50 ids per call; with --beads-json they come from each bead
object's optional `dependencies` field.

Standard library only. The API key is read from OPENROUTER_API_KEY, or from
the macOS Keychain (account `incursion`, service `incursion-openrouter`). It is
NEVER printed, logged or written. Any error body printed is cut to 500 chars.

This file is the home of the key, request and parse functions; tools/
bead_dupe_judge.py imports them from here rather than keeping its own copies.

Exit: 0 no candidate reached the threshold
      1 at least one candidate reached the threshold
      2 bad input (bad argument, unreadable bead data, missing bead id)
      3 Jev unavailable (no key, network/HTTP error, unparseable reply, or the
        --max-cost guard reached before every pair was judged)
"""

import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------- Jev

URL = "https://openrouter.ai/api/alpha/decisions"
MODEL = "typesafe/jev-1.13"
QUESTION = "same_defect"
INSTRUCTIONS = (
    "Do bead_a and bead_b describe the same defect or the same piece of work, "
    "so that fixing one would also resolve the other?"
)

KEYCHAIN_ACCOUNT = "incursion"
KEYCHAIN_SERVICE = "incursion-openrouter"

BLOCK_AT = 0.7          # a pair at or above this is reported
DESCRIPTION_CAP = 12000  # characters; the context is 32000 tokens
TOP_K_DEFAULT = 20
TOP_K_SWEEP = 10
MAX_WORKERS = 8
REQUEST_COST_ESTIMATE = 0.0002   # per-request, for the cost guard
LINK_BATCH = 50                  # ids per `bd show` call
ERROR_BODY_CAP = 500             # characters of any error body we print

RELATED_LINK_TYPES = {"duplicates", "relates-to", "parent-child"}

TOKEN_FLOOR = 3
STOPWORDS = {
    "the", "and", "for", "are", "but", "not", "you", "all", "any", "can",
    "her", "his", "was", "one", "our", "out", "who", "why", "how", "when",
    "with", "from", "that", "this", "they", "them", "then", "than", "there",
    "their", "into", "onto", "over", "under", "have", "has", "had", "does",
    "did", "done", "its", "it's", "itself", "will", "would", "should",
    "could", "must", "may", "might", "about", "after", "before", "between",
    "because", "which", "while", "where", "what", "your", "yours", "been",
    "being", "were", "isn", "aren", "wasn", "weren", "the", "too", "via",
    "per", "off", "own", "same", "using", "use", "used", "get", "got",
    "add", "added", "fix", "fixed", "bug", "bead", "issue", "inc",
}

SWEEP_STATE_REL = "logs/bead-dupes-sweep.state"

# The verified response shape, frozen 2026-09-24:
#   {"model":"typesafe/jev-1.13-20260917",
#    "answers":{"same_defect":{"type":"noul","noul":0.52}},
#    "usage":{"input_tokens":329,"output_tokens":22,"cost":0.000013818},
#    "id":"gen-dec-...","provider":"TypeSafe"}
VERIFIED_RESPONSE = (
    '{"model":"typesafe/jev-1.13-20260917",'
    '"answers":{"same_defect":{"type":"noul","noul":0.52}},'
    '"usage":{"input_tokens":329,"output_tokens":22,"cost":0.000013818},'
    '"id":"gen-dec-...","provider":"TypeSafe"}'
)


# ---------------------------------------------------------------- key

def resolve_key(required=True):
    """The API key, from the env or the Keychain. Never printed.

    Returns None when required is False and neither source holds one. When
    required is True (the default) it exits 2, naming BOTH sources so the
    reader knows which lever to pull.
    """
    env_key = os.environ.get("OPENROUTER_API_KEY")
    if env_key:
        return env_key

    try:
        result = subprocess.run(
            ["security", "find-generic-password",
             "-a", KEYCHAIN_ACCOUNT, "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=10,
        )
    except OSError:
        result = None

    key = result.stdout.strip() if result is not None and result.returncode == 0 else ""
    if not key:
        if not required:
            return None
        print("bead_dupes: no OpenRouter API key.", file=sys.stderr)
        print("  looked in the environment variable OPENROUTER_API_KEY, and in",
              file=sys.stderr)
        print("  the macOS Keychain (account %r, service %r)."
              % (KEYCHAIN_ACCOUNT, KEYCHAIN_SERVICE), file=sys.stderr)
        print("  Add it to either, e.g.:", file=sys.stderr)
        print("    security add-generic-password -a %s -s %s -w <KEY>"
              % (KEYCHAIN_ACCOUNT, KEYCHAIN_SERVICE), file=sys.stderr)
        sys.exit(2)
    return key


# ---------------------------------------------------------------- request

def short_description(text):
    """The first paragraph, up to the first blank line. Used by the judge."""
    if text is None:
        text = ""
    para = []
    for line in text.splitlines():
        if line.strip() == "":
            break
        para.append(line)
    return "\n".join(para).strip()


def bead_state(bead, mode="full"):
    """One bead's contribution to `state`."""
    title = bead.get("title") or ""
    description = bead.get("description") or ""
    if mode == "short":
        description = short_description(description)[:800]
    else:
        description = description[:DESCRIPTION_CAP]
    return {"title": title, "description": description}


def build_body(bead_a, bead_b, mode="full"):
    """The request body for one pair. Frozen shape; see the verified response."""
    return {
        "model": MODEL,
        "state": {
            "bead_a": bead_state(bead_a, mode),
            "bead_b": bead_state(bead_b, mode),
        },
        "questions": {
            QUESTION: {"type": "noul", "instructions": INSTRUCTIONS},
        },
    }


def send_request(key, body, timeout=120):
    """POST one body. Returns (status, response_text).

    An HTTP error is a response and is returned like any other; only a failure
    to reach a server at all raises, so the caller can record the pair as
    unavailable rather than guessing a probability.
    """
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        URL, data=data, method="POST",
        headers={"Authorization": "Bearer %s" % key,
                 "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", errors="replace")
    except urllib.error.URLError as exc:
        raise OSError("network failure: %s" % exc.reason)


# ---------------------------------------------------------------- parser

def parse_response(text):
    """(probability, cost, id) from a decision response body.

    Probability is answers.same_defect.noul, a number in [0,1]. Anything else
    -- missing path, wrong type, out of range -- is a ValueError, so the caller
    records an error and prints the raw body rather than guessing. A caller
    that defaulted a broken reply to 0.5 would report a made-up number as a
    measurement.
    """
    try:
        payload = json.loads(text)
    except ValueError as exc:
        raise ValueError("response is not JSON: %s" % exc)
    if not isinstance(payload, dict):
        raise ValueError("response is not a JSON object")

    answers = payload.get("answers")
    if not isinstance(answers, dict):
        raise ValueError("answers is missing or not an object")
    answer = answers.get(QUESTION)
    if not isinstance(answer, dict):
        raise ValueError("answers.%s is missing or not an object" % QUESTION)

    if "noul" not in answer:
        raise ValueError("answers.%s.noul is missing" % QUESTION)
    prob = answer["noul"]
    if isinstance(prob, bool) or not isinstance(prob, (int, float)):
        raise ValueError("answers.%s.noul is not a number: %r" % (QUESTION, prob))
    if not (0.0 <= prob <= 1.0):
        raise ValueError("answers.%s.noul is out of range [0,1]: %r"
                         % (QUESTION, prob))

    usage = payload.get("usage") or {}
    cost = usage.get("cost") if isinstance(usage, dict) else None
    if isinstance(cost, bool) or not isinstance(cost, (int, float)):
        cost = None
    return float(prob), cost, payload.get("id")


# ---------------------------------------------------------------- tokens

def tokenize(text):
    """Tokens: lowercase [a-z0-9]+, length >= TOKEN_FLOOR, minus stopwords."""
    if not text:
        return set()
    return {tok for tok in re.findall(r"[a-z0-9]+", text.lower())
            if len(tok) >= TOKEN_FLOOR and tok not in STOPWORDS}


def jaccard(a, b):
    """Jaccard similarity of two token sets. 0.0 when either is empty."""
    if not a or not b:
        return 0.0
    union = len(a | b)
    return len(a & b) / union if union else 0.0


def rank_candidates(subject, candidates, k):
    """The top-k candidates by Jaccard over title + description.

    Returns a list of (score, bead) highest first. Ties are broken by id so
    the order is deterministic (the sweep deduplicates pairs by id).
    """
    subject_tokens = tokenize((subject.get("title") or "") + " "
                              + (subject.get("description") or ""))
    scored = []
    for bead in candidates:
        tokens = tokenize((bead.get("title") or "") + " "
                          + (bead.get("description") or ""))
        scored.append((jaccard(subject_tokens, tokens), bead))
    scored.sort(key=lambda item: (-item[0], item[1].get("id") or ""))
    return scored[:k]


# ---------------------------------------------------------------- links

def _link_id(item):
    """The other bead's id, whichever key the link object uses."""
    if not isinstance(item, dict):
        return None
    return item.get("id") or item.get("depends_on_id")


def _link_type(item):
    """The link's type, whichever key the link object uses."""
    if not isinstance(item, dict):
        return None
    return item.get("type") or item.get("dependency_type")


def related_pairs(bead):
    """The set of ids already linked to `bead` by a related link type.

    A pair already joined by a duplicates, relates-to or parent-child link is
    never judged or reported. Reads each link object's optional `dependencies`
    and `dependents` fields (the shape of `bd show --json`).
    """
    linked = set()
    for field in ("dependencies", "dependents"):
        for item in bead.get(field) or []:
            if _link_type(item) in RELATED_LINK_TYPES:
                other = _link_id(item)
                if other:
                    linked.add(other)
    return linked


def pair_is_related(by_id, a, b):
    """True if a and b are already joined by a related link, either way."""
    if a not in by_id or b not in by_id:
        return False
    return b in related_pairs(by_id[a]) or a in related_pairs(by_id[b])


def _mentions_id(text, bead_id):
    """True if `text` names `bead_id` as a whole token.

    A trailing `.`, `,`, `)` or `:` still counts as a mention, but the id must
    be a whole token: `inc-hzy1` must not match `inc-hzy12`, and `inc-upw.4`
    must not match `inc-upw.43`. A dot inside an id (inc-upw.4) is part of the
    token, while a dot that ends a sentence ("see inc-upw.4.") must not extend
    it -- so the character after the id may not be a word character or a dot
    followed by a word character.
    """
    if not text or not bead_id:
        return False
    pattern = r"(?<![\w.])" + re.escape(bead_id) + r"(?!\w|\.\w)"
    return re.search(pattern, text) is not None


def pair_names_id(by_id, a, b):
    """True if either bead's title or description names the other's id.

    A filer who writes a bead's id already knows it exists, so the check has
    nothing to tell them. Unknown ids (a draft subject has none) can name no id.
    """
    if a in by_id and _bead_names_id(by_id[a], b):
        return True
    if b in by_id and _bead_names_id(by_id[b], a):
        return True
    return False


def _bead_names_id(bead, bead_id):
    if not bead_id:
        return False
    return (_mentions_id(bead.get("title") or "", bead_id)
            or _mentions_id(bead.get("description") or "", bead_id))


# ---------------------------------------------------------------- bead data

def _run_bd(args):
    """Run a bd command from REPO_ROOT. Returns parsed JSON or exits 2."""
    try:
        proc = subprocess.run(
            ["bd"] + args, capture_output=True, text=True, cwd=str(REPO_ROOT),
        )
    except OSError as exc:
        print("bead_dupes: cannot run `bd`: %s" % exc, file=sys.stderr)
        sys.exit(2)
    if proc.returncode != 0:
        print("bead_dupes: `bd %s` failed: %s"
              % (" ".join(args), proc.stderr.strip()), file=sys.stderr)
        sys.exit(2)
    try:
        return json.loads(proc.stdout)
    except ValueError as exc:
        print("bead_dupes: `bd %s` did not print JSON: %s"
              % (" ".join(args), exc), file=sys.stderr)
        sys.exit(2)


def load_beads(beads_json):
    """Beads by id, from --beads-json or `bd list --all --limit 0 --json`.

    `bd list --json` does NOT carry dependency links, so when reading the live
    database the links for the SUBJECT beads are fetched separately by
    fill_links() (a `bd show` record carries both directions, so subject-only
    is enough). With --beads-json the links (if wanted) are already on each
    bead object.

    Exits 2 on any unreadable data. A dict with an `issues` list is accepted,
    matching `bd list`.
    """
    if beads_json:
        try:
            data = json.loads(Path(beads_json).read_text())
        except (OSError, ValueError) as exc:
            print("bead_dupes: cannot read %s: %s" % (beads_json, exc),
                  file=sys.stderr)
            sys.exit(2)
    else:
        data = _run_bd(["list", "--all", "--limit", "0", "--json"])

    if isinstance(data, dict):
        data = data.get("issues") or []
    if not isinstance(data, list):
        print("bead_dupes: bead data is not an array", file=sys.stderr)
        sys.exit(2)

    by_id = {}
    for bead in data:
        if isinstance(bead, dict) and bead.get("id"):
            by_id[bead["id"]] = bead
    return by_id


def fill_links(by_id, ids, beads_json):
    """Ensure each id in `ids` has its dependency links on its bead object.

    Called with the SUBJECT beads only: a `bd show` record carries both
    `dependencies` and `dependents`, so the subject's own record already shows
    every link to any candidate, and pair_is_related reads both directions.
    Fetching candidate links too was wasted work.

    With --beads-json the links are already there (or absent); nothing is
    fetched. Against the live database, `bd list --json` omits links, so they
    are read from `bd show <id> [<id>...] --json`, batched at most LINK_BATCH
    ids per call. Exits 2 if a batch cannot be read.
    """
    if beads_json:
        return
    wanted = [b for b in dict.fromkeys(ids) if b in by_id]
    for start in range(0, len(wanted), LINK_BATCH):
        batch = wanted[start:start + LINK_BATCH]
        if not batch:
            continue
        data = _run_bd(["show"] + batch + ["--json"])
        if isinstance(data, dict):
            data = data.get("issues") or []
        if not isinstance(data, list):
            print("bead_dupes: `bd show` data is not an array", file=sys.stderr)
            sys.exit(2)
        for bead in data:
            if isinstance(bead, dict) and bead.get("id") in by_id:
                by_id[bead["id"]]["dependencies"] = bead.get("dependencies") or []
                by_id[bead["id"]]["dependents"] = bead.get("dependents") or []


# ---------------------------------------------------------------- judging

def _status_of(bead):
    return bead.get("status") or ""


def _type_of(bead):
    return bead.get("issue_type") or bead.get("type") or ""


def is_epic(bead):
    return _type_of(bead).lower() == "epic"


def _candidate_filter(beads, against, exclude, subject_id=None):
    """Candidates per the subcommand: epics never; `against` open/closed/all."""
    out = []
    for bead in beads.values():
        bead_id = bead.get("id")
        if not bead_id or bead_id == subject_id:
            continue
        if bead_id in exclude:
            continue
        if is_epic(bead):
            continue
        status = _status_of(bead)
        if against == "open" and status != "open":
            continue
        # against == "all": no status filter
        out.append(bead)
    return out


def judge_pairs(key, pairs, max_cost, mode="full"):
    """Judge each (subject, candidate) pair, up to MAX_WORKERS at a time.

    The cost guard is checked before each submit, using the sum of the costs of
    COMPLETED requests plus REQUEST_COST_ESTIMATE (0.0002) for the request about
    to be submitted. Returns (results, total_cost, failures).

    A result is {"id", "status", "title", "probability", "cost", "resp_id"} for
    the candidate, plus {"a_id", "a_status", "a_title"} for the subject. The
    candidate fields are what check-draft/check-bead report; the a_* fields let
    a sweep name BOTH beads of each pair. A failure is a string, worded for the
    caller, naming the pair and the reason. A pair that did not get judged
    (guard reached, HTTP error, network error, unparseable reply) is left out of
    results and has a matching failure, so a partial run is never reported as
    "no duplicates".
    """
    results = []
    failures = []
    total_cost = [0.0]
    lock = __import__("threading").Lock()

    def work(pair):
        subject, candidate = pair
        body = build_body(subject, candidate, mode)
        status, text = send_request(key, body)
        if status < 200 or status >= 300:
            raise RuntimeError("HTTP %d: %s" % (status, text[:ERROR_BODY_CAP]))
        prob, cost, resp_id = parse_response(text)
        return {
            "id": candidate.get("id"),
            "status": _status_of(candidate),
            "title": candidate.get("title") or "",
            "probability": prob,
            "cost": cost,
            "resp_id": resp_id,
            "a_id": subject.get("id"),
            "a_status": _status_of(subject),
            "a_title": subject.get("title") or "",
        }

    def collect(futures):
        done, _ = concurrent.futures.wait(
            futures, return_when=concurrent.futures.FIRST_COMPLETED)
        for fut in done:
            subj, cand = futures.pop(fut)
            try:
                result = fut.result()
                results.append(result)
                with lock:
                    if result["cost"]:
                        total_cost[0] += result["cost"]
            except (OSError, ValueError, RuntimeError) as exc:
                failures.append("pair %s/%s: %s"
                                % (subj.get("id"), cand.get("id"), exc))

    pending = list(pairs)
    index = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {}
        while index < len(pending):
            with lock:
                spent = total_cost[0] + REQUEST_COST_ESTIMATE
            if spent > max_cost:
                # Everything not yet submitted is a failure; the guard was
                # reached before every pair was judged.
                for subject, candidate in pending[index:]:
                    failures.append(
                        "pair %s/%s not judged: --max-cost %s reached"
                        % (subject.get("id"), candidate.get("id"), max_cost))
                break
            subject, candidate = pending[index]
            futures[pool.submit(work, (subject, candidate))] = (subject, candidate)
            index += 1
            # Keep the pool full, and drain a completed one so its cost counts
            # toward the running total before the next submit.
            if len(futures) >= MAX_WORKERS:
                collect(futures)

        # Drain whatever is still in flight after the loop.
        while futures:
            collect(futures)

    return results, total_cost[0], failures


# ---------------------------------------------------------------- reporting

def report_blocked(results):
    """Print the candidates at or above BLOCK_AT, highest first."""
    hits = [r for r in results if r["probability"] >= BLOCK_AT]
    hits.sort(key=lambda r: -r["probability"])
    for r in hits:
        print("%s\t%s\t%s\t%.3f"
              % (r["id"], r["status"], r["title"], r["probability"]))
    return hits


def _hits_json(results):
    """The judged hits as JSON-able dicts, highest probability first."""
    hits = [r for r in results if r["probability"] >= BLOCK_AT]
    hits.sort(key=lambda r: -r["probability"])
    return [{"id": r["id"], "status": r["status"], "title": r["title"],
             "probability": r["probability"]} for r in hits]


def report_pairs(results):
    """Print each hit as a PAIR: both ids, both statuses, both titles.

    A sweep judges many subjects, so a candidate-only line cannot say which
    bead each hit duplicates. Tab-separated, titles last, highest first:

        a_id  a_status  b_id  b_status  probability  a_title || b_title
    """
    hits = [r for r in results if r["probability"] >= BLOCK_AT]
    hits.sort(key=lambda r: -r["probability"])
    for r in hits:
        print("%s\t%s\t%s\t%s\t%.3f\t%s || %s"
              % (r["a_id"], r["a_status"], r["id"], r["status"],
                 r["probability"], r["a_title"], r["title"]))
    return hits


def _pairs_json(results, cost, failures):
    """Every judged pair as JSON-able dicts, highest probability first.

    The full sweep record: not only hits, and the failures that mean the run
    was not complete. A re-run is then never needed to recover a result.
    """
    ordered = sorted(results, key=lambda r: -r["probability"])
    return {
        "pairs": [{"a": r["a_id"], "b": r["id"],
                   "a_title": r["a_title"], "b_title": r["title"],
                   "a_status": r["a_status"], "b_status": r["status"],
                   "probability": r["probability"]} for r in ordered],
        "totals": {"judged": len(results), "hits":
                   len([r for r in results if r["probability"] >= BLOCK_AT]),
                   "failures": len(failures), "cost": cost},
        "failures": list(failures),
    }


def _write_json_out(path, payload):
    """Write `payload` as JSON to `path`, tolerating any failure.

    --json-out is how bead_new.sh reads the candidates and the unavailable
    reason without scraping stdout. A write that fails must not change the
    check's own verdict, so this only warns.
    """
    if not path:
        return
    try:
        Path(path).write_text(json.dumps(payload) + "\n")
    except OSError as exc:
        print("bead_dupes: could not write %s: %s" % (path, exc),
              file=sys.stderr)


def _unavailable_exit(reason, failures, results):
    """Print the reason and the failures, then exit 3."""
    print("bead_dupes: Jev unavailable: %s" % reason, file=sys.stderr)
    for failure in failures[:50]:
        print("  %s" % failure, file=sys.stderr)
    if len(failures) > 50:
        print("  ... and %d more" % (len(failures) - 50), file=sys.stderr)
    return 3


def _judge_or_unavailable(pairs, max_cost, mode="full", judge=None):
    """Resolve the key and judge; no key is Jev unavailable, not bad input.

    Returns (exit_code, results, cost, reason, failures). exit_code is None when
    every pair was judged and the caller should report the hits; otherwise it is
    3 and the reason has already been printed (reason is the short unavailable
    reason, for bead_new.sh's --json-out). A missing key is exit 3, NOT exit 2
    -- exit 2 is reserved for bad input, and "no key" is precisely the Jev
    unavailable condition the caller must not read as "no duplicates".

    `judge` is the seam for tests: it defaults to judge_pairs, but a caller may
    pass a stub so a sweep of a --beads-json fixture is judged without a key or
    a network. It is a function argument, never an environment switch. When a
    judge IS injected, key resolution is skipped and the stub is handed an
    empty key: the stub is the whole judging step, so no key is needed.
    """
    if judge is not None:
        try:
            results, cost, failures = judge("", pairs, max_cost, mode=mode)
        except OSError as exc:
            reason = str(exc)
            return _unavailable_exit(reason, [], []), [], 0.0, reason, []
        if failures:
            reason = "a pair could not be judged"
            return (_unavailable_exit(reason, failures, results),
                    results, cost, reason, failures)
        return None, results, cost, None, failures
    key = resolve_key(required=False)
    if not key:
        reason = "no OpenRouter API key"
        return _unavailable_exit(reason, [], []), [], 0.0, reason, []
    try:
        results, cost, failures = judge_pairs(key, pairs, max_cost, mode=mode)
    except OSError as exc:
        reason = str(exc)
        return _unavailable_exit(reason, [], []), [], 0.0, reason, []
    if failures:
        reason = "a pair could not be judged"
        return (_unavailable_exit(reason, failures, results),
                results, cost, reason, failures)
    return None, results, cost, None, failures


# ---------------------------------------------------------------- extract_draft

def extract_draft(argv):
    """Pull a draft's (title, description_source, parent, not_a_duplicate, bulk)
    out of bead_new.sh's arguments. Pure; phase 2 calls it.

    title: the first positional argument, or --title.
    description_source: ("inline", text) for -d/--description; ("file", path)
        for --body-file; ("stdin", None) for --stdin or --body-file -.
    parent: --parent's value or None.
    not_a_duplicate: True if --not-a-duplicate is present.
    bulk: True if -f/--file/--graph is present (bulk create, no pre-check).
    """
    title = None
    inline = None
    body_file = None
    stdin = False
    parent = None
    not_a_duplicate = False
    bulk = False
    positional = []

    # Flags that consume the next argv element's value.
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--":
            positional.extend(argv[i + 1:])
            break
        if arg == "--not-a-duplicate":
            not_a_duplicate = True
            i += 1
            continue
        if arg == "--stdin":
            stdin = True
            i += 1
            continue
        if arg in ("--file", "-f", "--graph"):
            bulk = True
            # --file may or may not take a value; a following non-flag counts
            # as bulk input, which we ignore. --graph takes none.
            if arg != "--graph" and i + 1 < len(argv) and not argv[i + 1].startswith("-"):
                i += 2
            else:
                i += 1
            continue
        if "=" in arg and arg.startswith(("--", "-d")):
            name, _, value = arg.partition("=")
            if name == "--title":
                title = value
            elif name in ("--description", "-d"):
                inline = value
            elif name == "--body-file":
                body_file = value
            elif name == "--parent":
                parent = value
            i += 1
            continue
        if arg in ("-d", "--title", "--description", "--body-file", "--parent"):
            value = argv[i + 1] if i + 1 < len(argv) else None
            if arg == "--title":
                title = value
            elif arg in ("-d", "--description"):
                inline = value
            elif arg == "--body-file":
                body_file = value
            elif arg == "--parent":
                parent = value
            i += 2
            continue
        if arg.startswith("-") and arg != "-":
            i += 1
            continue
        positional.append(arg)
        i += 1

    if title is None and positional:
        title = positional[0]

    if stdin or body_file == "-":
        description_source = ("stdin", None)
    elif body_file is not None:
        description_source = ("file", body_file)
    elif inline is not None:
        description_source = ("inline", inline)
    else:
        description_source = (None, None)

    return title, description_source, parent, not_a_duplicate, bulk


def bd_argv_for(argv, kind, stdin_temp):
    """bd create's argv with the wrapper-only and stdin spellings removed.

    `--not-a-duplicate` is never bd's; `--stdin` / `--body-file -` are replaced
    by `--body-file <stdin_temp>`, the temp file the wrapper filled from stdin.
    Everything else, including `--`, passes through untouched. Pure.
    """
    out = []
    i = 0
    n = len(argv)
    while i < n:
        a = argv[i]
        if a == "--":
            out.extend(argv[i:])
            break
        if a == "--not-a-duplicate" or a == "--stdin":
            i += 1
            continue
        if a == "--body-file":
            val = argv[i + 1] if i + 1 < n else None
            if val == "-":
                i += 2
                continue
            out.append(a)
            if val is not None:
                out.append(val)
                i += 2
            else:
                i += 1
            continue
        if a == "--body-file=-":
            i += 1
            continue
        out.append(a)
        i += 1
    if kind == "stdin":
        out.extend(["--body-file", stdin_temp])
    return out


def cmd_draft_args(argv):
    """Print the draft JSON for bead_new.sh; argv is everything after `--`.

    Shape: {"title", "description_source": {"kind", "text", "path"}, "parent",
    "not_a_duplicate", "bulk", "bd_argv"}. The wrapper reads stdin into
    --stdin-temp and lets bd_argv point bd at it, so no flag is re-parsed in
    bash. A stdin draft with no --stdin-temp is exit 2: bd_argv cannot name
    the temp file.
    """
    stdin_temp = None
    rest = list(argv)
    if rest and rest[0] == "--stdin-temp":
        if len(rest) < 2 or rest[1] == "":
            print("bead_dupes: draft-args --stdin-temp needs a path",
                  file=sys.stderr)
            return 2
        stdin_temp = rest[1]
        rest = rest[2:]
    if rest and rest[0] == "--":
        rest = rest[1:]

    title, source, parent, not_a_duplicate, bulk = extract_draft(rest)
    kind, text = source
    if kind == "stdin" and not stdin_temp:
        print("bead_dupes: draft-args: the draft is read from stdin but no "
              "--stdin-temp was given", file=sys.stderr)
        return 2

    bd_argv = bd_argv_for(rest, kind, stdin_temp)
    payload = {
        "title": title or "",
        "description_source": {"kind": kind or "none",
                               "text": text if kind == "inline" else None,
                               "path": text if kind == "file" else None},
        "parent": parent,
        "not_a_duplicate": not_a_duplicate,
        "bulk": bulk,
        "bd_argv": bd_argv,
    }
    print(json.dumps(payload))
    return 0


# ---------------------------------------------------------------- state file

def state_path():
    """logs/bead-dupes-sweep.state in the SHARED checkout.

    $(git rev-parse --git-common-dir)/.. -- a linked worktree shares this with
    the main checkout, so a sweep in a worktree records against the shared tree.
    """
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"],
            capture_output=True, text=True, cwd=str(REPO_ROOT),
        )
        if proc.returncode == 0 and proc.stdout.strip():
            common = proc.stdout.strip()
            common_path = (REPO_ROOT / common) if not os.path.isabs(common) \
                else Path(common)
            return common_path.parent / SWEEP_STATE_REL
    except OSError:
        pass
    return REPO_ROOT / SWEEP_STATE_REL


def read_state():
    path = state_path()
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def write_state(data):
    path = state_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2) + "\n")
    except OSError as exc:
        print("bead_dupes: could not write %s: %s" % (path, exc), file=sys.stderr)


# ---------------------------------------------------------------- subcommands

def _load_and_prepare(args):
    by_id = load_beads(args.beads_json)
    return by_id


def cmd_check_draft(args):
    json_out = getattr(args, "json_out", None)

    def bad(reason):
        print("bead_dupes: check-draft %s" % reason, file=sys.stderr)
        _write_json_out(json_out, {"unavailable": "bad input: %s" % reason})
        return 2

    if not args.title:
        return bad("needs --title")
    if not args.description_file:
        return bad("needs --description-file")
    try:
        description = Path(args.description_file).read_text()
    except OSError as exc:
        return bad("cannot read %s: %s" % (args.description_file, exc))

    by_id = _load_and_prepare(args)
    subject = {"id": None, "title": args.title, "description": description,
               "status": "draft", "issue_type": "task"}

    exclude = set(args.exclude)
    if args.parent:
        exclude.add(args.parent)
    candidates = _candidate_filter(by_id, "all", exclude, subject_id=None)

    ranked = rank_candidates(subject, candidates, args.top_k)
    pairs = [(subject, bead) for _score, bead in ranked
             if not pair_is_related(by_id, subject["id"], bead["id"])
             and not pair_names_id(by_id, subject["id"], bead["id"])]

    if not pairs:
        print("bead_dupes: no candidates to judge", file=sys.stderr)
        _write_json_out(json_out, {"hits": []})
        return 0

    code, results, cost, reason, _failures = _judge_or_unavailable(
        pairs, args.max_cost)
    if code is not None:
        _write_json_out(json_out, {"unavailable": reason})
        return code
    hits = report_blocked(results)
    _write_json_out(json_out, {"hits": _hits_json(results)})
    print("bead_dupes: judged %d pair(s), cost $%.6f" % (len(results), cost),
          file=sys.stderr)
    return 1 if hits else 0


def cmd_check_bead(args):
    if not args.bead:
        print("bead_dupes: check-bead needs a bead id", file=sys.stderr)
        return 2
    by_id = _load_and_prepare(args)
    if args.bead not in by_id:
        print("bead_dupes: bead %s is missing from the bead data" % args.bead,
              file=sys.stderr)
        return 2
    subject = by_id[args.bead]

    exclude = set(args.exclude)
    against = args.against
    candidates = _candidate_filter(by_id, against, exclude,
                                   subject_id=subject["id"])
    fill_links(by_id, [subject["id"]], args.beads_json)

    ranked = rank_candidates(subject, candidates, args.top_k)
    pairs = [(subject, bead) for _score, bead in ranked
             if not pair_is_related(by_id, subject["id"], bead["id"])
             and not pair_names_id(by_id, subject["id"], bead["id"])]

    if not pairs:
        print("bead_dupes: no candidates to judge", file=sys.stderr)
        return 0

    code, results, cost, _reason, _failures = _judge_or_unavailable(
        pairs, args.max_cost)
    if code is not None:
        return code
    hits = report_blocked(results)
    print("bead_dupes: judged %d pair(s), cost $%.6f" % (len(results), cost),
          file=sys.stderr)
    return 1 if hits else 0


def _sweep_subjects(by_id, args):
    """The open beads subject to a sweep.

    --all: every open non-epic bead. --since-last: open non-epic beads created
    or updated after the state's timestamp, plus any whose notes hold
    `duplicate check skipped` (a bead the filing check could not judge). A pair
    whose beads are both closed is dropped later, in cmd_sweep.
    """
    state = read_state()
    since = state.get("last_sweep") if args.since_last else None

    subjects = []
    for bead in by_id.values():
        if _status_of(bead) != "open" or is_epic(bead):
            continue
        if args.all:
            subjects.append(bead)
            continue
        created = bead.get("created_at") or ""
        updated = bead.get("updated_at") or bead.get("updated") or ""
        notes = bead.get("notes") or ""
        touched = bool(since) and (
            (created and created > since) or (updated and updated > since))
        if touched or "duplicate check skipped" in notes:
            subjects.append(bead)
    return subjects


def cmd_sweep(args, judge=None, record_state=True):
    if not args.all and not args.since_last:
        print("bead_dupes: sweep needs --all or --since-last", file=sys.stderr)
        return 2
    by_id = _load_and_prepare(args)

    subjects = _sweep_subjects(by_id, args)
    fill_links(by_id, [s["id"] for s in subjects], args.beads_json)

    # Every subject against its top K (open and closed), pairs deduplicated.
    seen = set()
    pairs = []
    for subject in subjects:
        candidates = _candidate_filter(by_id, "all", set(args.exclude),
                                       subject_id=subject["id"])
        ranked = rank_candidates(subject, candidates, args.top_k)
        for _score, bead in ranked:
            a, b = subject["id"], bead["id"]
            if a == b or pair_is_related(by_id, a, b) or pair_names_id(by_id, a, b):
                continue
            key_tuple = tuple(sorted((a, b)))
            if key_tuple in seen:
                continue
            # A pair whose beads are both closed is dropped.
            if _status_of(by_id[a]) == "closed" and _status_of(by_id[b]) == "closed":
                continue
            seen.add(key_tuple)
            pairs.append((subject, bead))

    if not pairs:
        print("sweep: no pairs to judge")
        _write_json_out(getattr(args, "json_out", None),
                        _pairs_json([], 0.0, []))
        if record_state:
            write_state({"last_sweep": _now()})
        return 0

    code, results, cost, _reason, failures = _judge_or_unavailable(
        pairs, args.max_cost, judge=judge)
    if code is not None:
        # The full record is still written: every judged pair and the failures
        # mean a re-run is never needed to recover what did complete.
        _write_json_out(getattr(args, "json_out", None),
                        _pairs_json(results, cost, failures))
        return code

    hits = report_pairs(results)
    _write_json_out(getattr(args, "json_out", None),
                    _pairs_json(results, cost, failures))
    print("")
    print("sweep: pairs judged %d, cost $%.6f, failures %d"
          % (len(results), cost, len(failures)))
    # The state is written only after a complete sweep (all pairs judged).
    if record_state:
        write_state({"last_sweep": _now()})
    return 1 if hits else 0


def _now():
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------- selftest

def _selftest_tokens():
    fail = 0
    ts = tokenize("The Cat sat on the MAT with three")
    if "cat" not in ts or "sat" not in ts or "mat" not in ts:
        print("SELFTEST FAIL: tokenize lost a real token: %r" % ts)
        fail = 1
    if "the" in ts or "on" in ts or "with" in ts:
        print("SELFTEST FAIL: tokenize kept a stopword: %r" % ts)
        fail = 1
    # length floor: a two-letter token is dropped
    if "at" in tokenize("at cat"):
        print("SELFTEST FAIL: tokenize kept a token shorter than the floor")
        fail = 1
    return fail


def _selftest_ranking():
    fail = 0
    subject = {"id": "s", "title": "dragon fire breath crashes the game",
               "description": "dragon fire breath crashes the game"}
    near = {"id": "n", "title": "dragon fire breath crash",
            "description": "the game crashes on dragon fire breath"}
    far = {"id": "f", "title": "unrelated kobold horn loot",
           "description": "kobold horn loot table"}
    ranked = rank_candidates(subject, [far, near], 2)
    if not ranked or ranked[0][1]["id"] != "n":
        print("SELFTEST FAIL: ranking did not put the near bead first: %r"
              % [(round(s, 3), b["id"]) for s, b in ranked])
        fail = 1
    return fail


def _selftest_links():
    fail = 0
    by_id = {
        "a": {"id": "a", "dependencies": [
            {"type": "duplicates", "id": "b"},
            {"type": "blocks", "id": "c"}]},
        "b": {"id": "b", "dependents": [
            {"dependency_type": "duplicates", "depends_on_id": "a"}]},
        "c": {"id": "c", "dependencies": []},
    }
    if not pair_is_related(by_id, "a", "b"):
        print("SELFTEST FAIL: a duplicates link did not mark the pair related")
        fail = 1
    if not pair_is_related(by_id, "b", "a"):
        print("SELFTEST FAIL: a duplicates link was not seen from the other side")
        fail = 1
    if pair_is_related(by_id, "a", "c"):
        print("SELFTEST FAIL: a blocks link wrongly marked the pair related")
        fail = 1

    # Subject-only fetch is enough: the link may be recorded ONLY on the
    # subject's `dependents` list, with the candidate carrying no links at
    # all. A `bd show` of the subject returns both `dependencies` and
    # `dependents`, so reading the subject alone must still skip the pair.
    subject_only = {
        "s": {"id": "s", "dependents": [
            {"dependency_type": "duplicates", "depends_on_id": "t"}]},
        "t": {"id": "t"},
    }
    if not pair_is_related(subject_only, "s", "t"):
        print("SELFTEST FAIL: a link on the subject's dependents list alone did "
              "not mark the pair related (subject-only fetch must suffice)")
        fail = 1
    return fail


def _selftest_names_id():
    """A pair names each other's ids: never judged, in either direction."""
    fail = 0

    def expect(got, want, label):
        nonlocal fail
        if got != want:
            print("SELFTEST FAIL: %s -> %r, wanted %r" % (label, got, want))
            fail = 1

    # names-by-id skipped, both directions
    by_id = {
        "inc-hzy1": {"id": "inc-hzy1", "title": "the hzy1 creature fix",
                     "description": "fixed already"},
        "inc-3jk3": {"id": "inc-3jk3", "title": "verify the inc-hzy1 fix",
                     "description": "on six creatures"},
    }
    expect(pair_names_id(by_id, "inc-hzy1", "inc-3jk3"), True,
           "names-by-id (candidate title names subject)")
    expect(pair_names_id(by_id, "inc-3jk3", "inc-hzy1"), True,
           "names-by-id (subject title names candidate)")

    # inc-hzy12 does not count as naming inc-hzy1
    near = {"inc-hzy1": {"id": "inc-hzy1", "title": "a", "description": ""},
            "inc-hzy12": {"id": "inc-hzy12", "title": "watch inc-hzy12",
                          "description": ""}}
    expect(pair_names_id(near, "inc-hzy1", "inc-hzy12"), False,
           "inc-hzy12 must not name inc-hzy1")
    expect(pair_names_id(near, "inc-hzy12", "inc-hzy1"), False,
           "inc-hzy1 must not match inc-hzy12")

    # inc-upw.43 does not count as naming inc-upw.4
    dot = {"inc-upw.4": {"id": "inc-upw.4", "title": "a", "description": ""},
           "inc-upw.43": {"id": "inc-upw.43", "title": "see inc-upw.43",
                          "description": ""}}
    expect(pair_names_id(dot, "inc-upw.4", "inc-upw.43"), False,
           "inc-upw.43 must not name inc-upw.4")

    # "see inc-upw.4." at sentence end DOES count
    end = {"inc-upw.4": {"id": "inc-upw.4", "title": "a", "description": ""},
           "inc-x": {"id": "inc-x", "title": "followup",
                     "description": "see inc-upw.4."}}
    expect(pair_names_id(end, "inc-upw.4", "inc-x"), True,
           "\"see inc-upw.4.\" at sentence end must count")

    # an exact id with trailing , ) : still counts
    for trailer in (",", ")", ":"):
        ment = {"inc-z1": {"id": "inc-z1", "title": "a", "description": ""},
                "inc-y": {"id": "inc-y", "title": "note",
                          "description": "relates to inc-z1%s done" % trailer}}
        expect(pair_names_id(ment, "inc-z1", "inc-y"), True,
               "trailing %r after an id must count" % trailer)
    return fail


def _selftest_parser():
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
    for bad in ('{"id":"gen-dec-x","usage":{"cost":0.1}}',
                '{"answers":{"same_defect":{"type":"noul","noul":1.7}}}',
                '{"answers":{"same_defect":{"type":"noul"}}}',
                '{"answers":{"same_defect":{"noul":"high"}}}',
                'not json'):
        try:
            parse_response(bad)
            print("SELFTEST FAIL: %r did not raise" % bad)
            fail = 1
        except ValueError:
            pass
    return fail


def _selftest_extract_draft():
    fail = 0

    def check(argv, want, label):
        nonlocal fail
        got = extract_draft(argv)
        if got != want:
            print("SELFTEST FAIL: extract_draft %s gave %r, wanted %r"
                  % (label, got, want))
            fail = 1

    # positional title + -d
    check(["a title", "-d", "a body"],
          ("a title", ("inline", "a body"), None, False, False), "positional+-d")
    # --title + --body-file
    check(["--title", "T", "--body-file", "x"],
          ("T", ("file", "x"), None, False, False), "--title+--body-file")
    # --stdin
    check(["T", "--stdin"],
          ("T", ("stdin", None), None, False, False), "--stdin")
    # --body-file - (stdin)
    check(["T", "--body-file", "-"],
          ("T", ("stdin", None), None, False, False), "--body-file-")
    # -f plan.md (bulk)
    check(["T", "-f", "plan.md"],
          ("T", (None, None), None, False, True), "-f plan.md")
    # --not-a-duplicate present
    check(["T", "-d", "b", "--not-a-duplicate"],
          ("T", ("inline", "b"), None, True, False), "--not-a-duplicate")
    # --parent inc-x
    check(["T", "-d", "b", "--parent", "inc-x"],
          ("T", ("inline", "b"), "inc-x", False, False), "--parent inc-x")
    # -d=text / --description=text forms
    check(["T", "-d=text"],
          ("T", ("inline", "text"), None, False, False), "-d=text")
    check(["T", "--description=text"],
          ("T", ("inline", "text"), None, False, False), "--description=text")
    return fail


def _selftest_bd_argv():
    """bd_argv_for strips --not-a-duplicate/--stdin and names the stdin temp."""
    fail = 0

    def check(argv, kind, temp, want, label):
        nonlocal fail
        got = bd_argv_for(argv, kind, temp)
        if got != want:
            print("SELFTEST FAIL: bd_argv_for %s gave %r, wanted %r"
                  % (label, got, want))
            fail = 1

    check(["T", "--stdin", "--type", "bug"], "stdin", "/tmp/b",
          ["T", "--type", "bug", "--body-file", "/tmp/b"], "--stdin")
    check(["T", "--body-file", "-"], "stdin", "/tmp/b",
          ["T", "--body-file", "/tmp/b"], "--body-file -")
    check(["T", "--body-file=-", "--not-a-duplicate"], "stdin", "/tmp/b",
          ["T", "--body-file", "/tmp/b"], "--body-file=-")
    check(["T", "-d", "body", "--not-a-duplicate"], "inline", None,
          ["T", "-d", "body"], "--not-a-duplicate with -d")
    check(["T", "--body-file", "real.md"], "file", None,
          ["T", "--body-file", "real.md"], "--body-file real.md")
    check(["T", "-d", "b", "--parent", "inc-x", "--not-a-duplicate"],
          "inline", None, ["T", "-d", "b", "--parent", "inc-x"], "--parent")
    # Everything after `--` passes through untouched.
    check(["T", "--not-a-duplicate", "--", "--stdin"], "inline", None,
          ["T", "--", "--stdin"], "after --")
    return fail


def _selftest_cost_guard():
    """The --max-cost guard must stop before every pair is judged.

    send_request is stubbed so no network is touched: every request "costs"
    $0.05, and the cap is $0.06. The pool runs up to MAX_WORKERS at once, so
    the guard can only bite once a completed request's cost is seen; with more
    pairs than workers, the rest must be recorded as failures (Jev
    unavailable), never as no-dup.
    """
    fail = 0
    original = send_request

    def stub_send(key, body, timeout=120):
        return 200, json.dumps({
            "answers": {QUESTION: {"type": "noul", "noul": 0.1}},
            "usage": {"cost": 0.05},
            "id": "gen-dec-stub",
        })

    globals()["send_request"] = stub_send
    cap = 0.06
    per_request = 0.05
    try:
        count = MAX_WORKERS * 3
        pairs = [({"id": "a%d" % i, "title": "t%d" % i, "description": ""},
                  {"id": "b%d" % i, "title": "u%d" % i, "description": ""})
                 for i in range(count)]
        results, cost, failures = judge_pairs("key", pairs, max_cost=cap)
    finally:
        globals()["send_request"] = original

    if len(results) + len(failures) != len(pairs):
        print("SELFTEST FAIL: cost guard lost a pair: %d results + %d failures "
              "!= %d pairs" % (len(results), len(failures), len(pairs)))
        fail = 1
    if not failures:
        print("SELFTEST FAIL: cost guard did not trigger; every pair was judged")
        fail = 1
    if len(results) == 0:
        print("SELFTEST FAIL: cost guard judged nothing; a completed request's "
              "cost was never seen")
        fail = 1
    # Up to MAX_WORKERS requests are in flight when the first cost is seen, so
    # the spend can overshoot the cap by at most that many requests.
    overshoot = cap + per_request * MAX_WORKERS
    if cost > overshoot:
        print("SELFTEST FAIL: cost guard spent $%.4f, over the bound $%.4f"
              % (cost, overshoot))
        fail = 1
    return fail


def _selftest_sweep_report():
    """A sweep over a --beads-json fixture must name BOTH beads of each hit.

    The judge is stubbed through the `judge` argument of cmd_sweep, so no key
    and no network are touched. Every printed hit line must carry the subject's
    id AND the candidate's id: a candidate-only line is exactly the defect this
    selftest guards.
    """
    fail = 0
    fixture = [
        {"id": "inc-sub", "title": "dragon fire breath crashes the game",
         "description": "dragon fire breath crashes the game", "status": "open",
         "issue_type": "task"},
        {"id": "inc-dup", "title": "dragon fire breath crash",
         "description": "the game crashes on dragon fire breath",
         "status": "open", "issue_type": "task"},
        {"id": "inc-far", "title": "unrelated kobold horn loot",
         "description": "kobold horn loot table", "status": "open",
         "issue_type": "task"},
    ]

    def stub_judge(key, pairs, max_cost, mode="full"):
        results = []
        for subject, candidate in pairs:
            prob = 0.9 if candidate.get("id") == "inc-dup" else 0.1
            results.append({
                "id": candidate.get("id"),
                "status": _status_of(candidate),
                "title": candidate.get("title") or "",
                "probability": prob, "cost": None, "resp_id": "gen-dec-stub",
                "a_id": subject.get("id"),
                "a_status": _status_of(subject),
                "a_title": subject.get("title") or "",
            })
        return results, 0.0, []

    import argparse
    import contextlib
    import io
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        beads_json = os.path.join(tmp, "beads.json")
        with open(beads_json, "w") as fh:
            json.dump(fixture, fh)
        args = argparse.Namespace(
            beads_json=beads_json, all=True, since_last=False,
            max_cost=1.00, top_k=TOP_K_SWEEP, exclude=[],
            json_out=os.path.join(tmp, "out.json"))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            cmd_sweep(args, judge=stub_judge, record_state=False)

    lines = [ln for ln in out.getvalue().splitlines() if ln.strip()]
    hit_lines = [ln for ln in lines if "\t0.9" in ln or ln.endswith("0.900")]
    if not hit_lines:
        print("SELFTEST FAIL: sweep printed no hit line for the known duplicate:\n"
              "%s" % out.getvalue())
        return 1
    for line in hit_lines:
        fields = line.split("\t")
        if len(fields) < 5:
            print("SELFTEST FAIL: sweep hit line is not tab-separated pairs: %r"
                  % line)
            fail = 1
            continue
        if fields[0] != "inc-sub" or fields[2] != "inc-dup":
            print("SELFTEST FAIL: sweep hit line does not name BOTH ids "
                  "(a=%r b=%r): %r" % (fields[0], fields[2] if len(fields) > 2
                                       else None, line))
            fail = 1
    return fail


def selftest():
    """Tokeniser, ranking, link-skip, parser, cost guard and extract_draft."""
    fail = 0
    fail |= _selftest_tokens()
    fail |= _selftest_ranking()
    fail |= _selftest_links()
    fail |= _selftest_names_id()
    fail |= _selftest_parser()
    fail |= _selftest_cost_guard()
    fail |= _selftest_extract_draft()
    fail |= _selftest_bd_argv()
    fail |= _selftest_sweep_report()
    if fail == 0:
        print("SELFTEST PASS: tokeniser, ranking, link-skip, parser, cost guard, "
              "extract_draft, bd_argv and the sweep pair report all accept "
              "their fixed inputs")
    return fail


# ---------------------------------------------------------------- main

def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    sub = parser.add_subparsers(dest="command")

    def add_common(p):
        p.add_argument("--beads-json")
        p.add_argument("--max-cost", type=float, default=None)
        p.add_argument("--top-k", type=int, default=TOP_K_DEFAULT)
        p.add_argument("--exclude", action="append", default=[],
                       metavar="ID",
                       help="a bead never offered as a candidate; repeatable")

    p_draft = sub.add_parser("check-draft")
    p_draft.add_argument("--title")
    p_draft.add_argument("--description-file")
    p_draft.add_argument("--parent")
    p_draft.add_argument("--json-out", metavar="PATH",
                         help="write the hits, or {\"unavailable\": reason}, "
                              "as JSON to PATH (for bead_new.sh)")
    add_common(p_draft)
    p_draft.set_defaults(max_cost=0.05)

    p_bead = sub.add_parser("check-bead")
    p_bead.add_argument("bead")
    p_bead.add_argument("--against", choices=["open"], default="open")
    add_common(p_bead)
    p_bead.set_defaults(max_cost=0.05)

    p_sweep = sub.add_parser("sweep")
    p_sweep.add_argument("--all", action="store_true")
    p_sweep.add_argument("--since-last", action="store_true")
    p_sweep.add_argument("--json-out", metavar="PATH",
                         help="write every judged pair, with totals and "
                              "failures, as JSON to PATH")
    add_common(p_sweep)
    # sweep resolves its own defaults in run(): --since-last 0.25, --all 1.00.
    p_sweep.set_defaults(top_k=TOP_K_SWEEP, max_cost=None)
    return parser


def run(argv):
    # draft-args carries bd create's own flags after `--`, which argparse
    # would reject; hand the raw remainder straight to it.
    if argv and argv[0] == "draft-args":
        return cmd_draft_args(argv[1:])

    parser = build_parser()
    args = parser.parse_args(argv)

    if args.selftest:
        return selftest()

    if args.command == "check-draft":
        return cmd_check_draft(args)
    if args.command == "check-bead":
        return cmd_check_bead(args)
    if args.command == "sweep":
        if args.max_cost is None:
            args.max_cost = 1.00 if args.all else 0.25
        return cmd_sweep(args)

    parser.print_help()
    return 2


def main():
    try:
        sys.exit(run(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 - fail closed, never a traceback
        print("bead_dupes: error: %s" % exc, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
