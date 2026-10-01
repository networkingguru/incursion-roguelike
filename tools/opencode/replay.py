#!/usr/bin/env python3
"""replay.py -- re-send one captured chat-completions request to DeepInfra.

    tools/opencode/replay.py --request PATH --runs N --out-dir DIR
        [--set KEY=JSON ...] [--unset KEY ...] [--dry-run] [--timeout SECONDS]
        [--price-in USD --price-cached USD --price-out USD]

PATH is a NNNN.request.json written by tools/opencode/record_proxy.py. The body
is sent byte-for-byte as captured, except for top-level fields changed with
--set (value parsed as JSON) or removed with --unset. The request is sent N
times; every streamed reply is saved under DIR as run-NN.*, every call's cost
is recorded in the shared ledger, and one summary line is printed per run.

When the streamed usage carries estimated_cost it is used as-is. When it does
not, and all three --price-* flags are given, the cost is computed from the
token counts at those USD-per-million prices and the row is tagged
cost_source="price-flags". With no prices an unpriced call still writes a null
row and exits 2, exactly as before.

This is a measuring tool: it reports numbers (finish reason, token counts, cost,
tool calls, DSML markup leaks, repeated lines). It judges nothing.

Standard library only. Reuses tools/deepseek.py for key/URL/ledger/budget
resolution and ledger appending; that file is never modified.
"""

import argparse
import datetime
import json
import sys
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent.parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from deepseek import (  # noqa: E402
    append_ledger_row,
    check_budget,
    resolve_budget,
    resolve_key,
    resolve_ledger_path,
    resolve_url,
)

MAX_RUNS = 30


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Replay one captured DeepInfra chat-completions request N times."
    )
    parser.add_argument("--request", required=True, help="path to NNNN.request.json")
    parser.add_argument("--runs", required=True, type=int, help="number of runs, 1..30")
    parser.add_argument("--out-dir", required=True, help="directory for run-NN.* files")
    parser.add_argument(
        "--set",
        action="append",
        default=[],
        metavar="KEY=JSON",
        help="set a top-level body field; the value is parsed as JSON. Repeatable.",
    )
    parser.add_argument(
        "--unset",
        action="append",
        default=[],
        metavar="KEY",
        help="remove a top-level body field. Repeatable.",
    )
    parser.add_argument(
        "--price-in",
        type=float,
        help="USD per million prompt tokens, when the provider reports no cost",
    )
    parser.add_argument(
        "--price-cached",
        type=float,
        help="USD per million cached prompt tokens, when the provider reports no cost",
    )
    parser.add_argument(
        "--price-out",
        type=float,
        help="USD per million completion tokens, when the provider reports no cost",
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--timeout", type=float, default=300)
    args = parser.parse_args(argv)

    if not (1 <= args.runs <= MAX_RUNS):
        print(
            f"--runs must be between 1 and {MAX_RUNS}, got {args.runs}",
            file=sys.stderr,
        )
        sys.exit(2)

    given = [
        name
        for name in ("price_in", "price_cached", "price_out")
        if getattr(args, name) is not None
    ]
    if given and len(given) != 3:
        print(
            "--price-in, --price-cached and --price-out must be given together, "
            f"got only {', '.join('--' + n.replace('_', '-') for n in given)}",
            file=sys.stderr,
        )
        sys.exit(2)
    return args


def load_body(request_path):
    try:
        raw = Path(request_path).read_bytes()
    except OSError as exc:
        print(f"cannot read --request {request_path}: {exc}", file=sys.stderr)
        sys.exit(2)
    try:
        body = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"--request {request_path} is not valid JSON: {exc}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(body, dict):
        print(f"--request {request_path} is not a JSON object", file=sys.stderr)
        sys.exit(2)
    return body


def apply_sets(body, sets, unsets):
    changes = []
    for spec in sets:
        key, sep, value_text = spec.partition("=")
        if not sep or not key:
            print(f"--set must be KEY=JSON, got {spec!r}", file=sys.stderr)
            sys.exit(2)
        try:
            value = json.loads(value_text)
        except json.JSONDecodeError as exc:
            print(f"--set {spec!r}: value is not valid JSON: {exc}", file=sys.stderr)
            sys.exit(2)
        body[key] = value
        changes.append(("set", key, value))
    for key in unsets:
        if not key:
            print("--unset needs a non-empty KEY", file=sys.stderr)
            sys.exit(2)
        body.pop(key, None)
        changes.append(("unset", key, None))
    return changes


def refuse_overwrite(out_dir, run):
    stamp = f"run-{run:02d}."
    for path in out_dir.glob(f"{stamp}*"):
        print(
            f"refusing to overwrite existing file {path} in {out_dir}",
            file=sys.stderr,
        )
        sys.exit(2)


def send_stream(url, key, body, timeout):
    """POST the body and stream the reply to disk as it arrives. Returns
    (status, response_path) on a 2xx, and prints+exits 2 on a non-2xx after
    saving the body. A network failure with no response also exits 2."""
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        },
    )
    try:
        resp = urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError as exc:
        status = exc.code
        body_bytes = exc.read()
        return status, body_bytes
    except urllib.error.URLError as exc:
        print(f"network failure calling DeepInfra: {exc.reason}", file=sys.stderr)
        sys.exit(2)
    return resp.status, resp


def read_chunks(resp):
    """Yield raw bytes read from a streaming response, flushing each to the
    caller immediately (read1 returns as soon as anything is available)."""
    while True:
        chunk = resp.read1(8192)
        if not chunk:
            break
        yield chunk


def parse_sse(raw):
    """Reassemble an SSE stream into the fields the summary needs.

    Returns a dict with content, reasoning, tool_names (ordered, distinct
    indexes), tool_count, finish_reason (last non-null) and usage."""
    content_parts = []
    reasoning_parts = []
    tool_names = {}
    finish_reason = None
    usage = None
    first_id = None

    text = raw.decode("utf-8", errors="replace")
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("data:"):
            continue
        payload = line[len("data:"):].strip()
        if not payload or payload == "[DONE]":
            continue
        try:
            obj = json.loads(payload)
        except json.JSONDecodeError:
            continue
        if first_id is None:
            first_id = obj.get("id")
        if obj.get("usage"):
            usage = obj["usage"]
        for choice in obj.get("choices") or []:
            delta = choice.get("delta") or {}
            if isinstance(delta.get("content"), str):
                content_parts.append(delta["content"])
            if isinstance(delta.get("reasoning_content"), str):
                reasoning_parts.append(delta["reasoning_content"])
            for call in delta.get("tool_calls") or []:
                idx = call.get("index")
                if idx not in tool_names:
                    fn = call.get("function") or {}
                    tool_names[idx] = fn.get("name")
            if choice.get("finish_reason") is not None:
                finish_reason = choice["finish_reason"]

    return {
        "content": "".join(content_parts),
        "reasoning": "".join(reasoning_parts),
        "tool_names": [tool_names[k] for k in sorted(tool_names)],
        "tool_count": len(tool_names),
        "finish_reason": finish_reason,
        "usage": usage or {},
        "id": first_id,
    }


def markup_leak(content, reasoning):
    """True when the reply printed native tool-call markup as text: some line
    of content or reasoning, after its leading whitespace is stripped, begins
    with "<|dsml|" or "</|" (U+FF5C FULLWIDTH VERTICAL LINE in place of the
    pipe). Prose that merely quotes the token mid-line does not count. This is
    the same shape tools/opencode/loop_check.py rule 2 applies; it is
    duplicated here so replay.py stays a standalone measuring tool."""
    for text in (content, reasoning):
        for line in text.splitlines():
            stripped = line.lstrip()
            if stripped.startswith("<\uFF5CDSML\uFF5C") or stripped.startswith("</\uFF5C"):
                return True
    return False


def top_line_repeats(content, reasoning, min_len=3):
    """The highest count of an identical non-blank stripped line across
    content+reasoning, among lines at least min_len characters long, plus
    that line (or None)."""
    counts = Counter()
    for text in (content, reasoning):
        for line in text.splitlines():
            stripped = line.strip()
            if len(stripped) >= min_len:
                counts[stripped] += 1
    if not counts:
        return 0, None
    line, count = max(counts.items(), key=lambda kv: (kv[1], kv[0]))
    return count, line


def write_text(path, text):
    path.write_text(text, encoding="utf-8")


def run_one(args, body, run, key, ledger_path, budget, request_path, out_dir):
    response_path = out_dir / f"run-{run:02d}.response.txt"
    summary_path = out_dir / f"run-{run:02d}.summary.json"
    content_path = out_dir / f"run-{run:02d}.content.txt"
    reasoning_path = out_dir / f"run-{run:02d}.reasoning.txt"

    # Step 1: every run re-checks the budget, not just once per invocation.
    check_budget(ledger_path, budget)

    # Step 2 and 3: POST and stream the raw reply to disk as it arrives.
    status, resp = send_stream(resolve_url(), key, body, args.timeout)

    if isinstance(resp, bytes) or not (200 <= status < 300):
        if isinstance(resp, bytes):
            raw = resp
        else:
            raw = resp.read()
            resp.close()
        try:
            response_path.write_bytes(raw)
        except OSError:
            pass
        print(f"run {run}: DeepInfra returned HTTP {status}", file=sys.stderr)
        print(raw.decode("utf-8", errors="replace")[:2000], file=sys.stderr)
        sys.exit(2)

    parts = []
    with response_path.open("wb") as fh:
        try:
            for chunk in read_chunks(resp):
                fh.write(chunk)
                fh.flush()
                parts.append(chunk)
        finally:
            resp.close()
    raw = b"".join(parts)

    # Step 4: parse the stream.
    parsed = parse_sse(raw)
    usage = parsed["usage"]
    prompt_tokens = usage.get("prompt_tokens")
    completion_tokens = usage.get("completion_tokens")
    details = usage.get("prompt_tokens_details") or {}
    cached_tokens = details.get("cached_tokens", 0)
    cost = usage.get("estimated_cost")
    cost_source = "provider" if cost is not None else "none"
    prices = None

    # When the provider reports no cost, the caller may supply per-million
    # prices; compute the cost from the token counts and mark its source.
    if cost is None and usage and args.price_in is not None:
        uncached = (prompt_tokens or 0) - (cached_tokens or 0)
        cost = (
            uncached * args.price_in
            + (cached_tokens or 0) * args.price_cached
            + (completion_tokens or 0) * args.price_out
        ) / 1e6
        cost_source = "price-flags"
        prices = [args.price_in, args.price_cached, args.price_out]

    # Step 5: record the spend as soon as usage is known.
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    row = {
        "ts": ts,
        "model": body.get("model"),
        "prompt": str(request_path),
        "out": str(response_path),
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "cached_tokens": cached_tokens,
        "cost": cost,
        "id": parsed["id"],
        "harness": "replay",
    }
    if cost is not None:
        row["cost_source"] = cost_source
    if prices is not None:
        row["prices"] = prices
    append_ledger_row(ledger_path, row)

    # Step 6: summary.
    content = parsed["content"]
    reasoning = parsed["reasoning"]
    leaked = markup_leak(content, reasoning)
    repeats, repeat_line = top_line_repeats(content, reasoning)

    write_text(content_path, content)
    if reasoning:
        write_text(reasoning_path, reasoning)

    summary = {
        "run": run,
        "finish_reason": parsed["finish_reason"],
        "completion_tokens": completion_tokens,
        "cost": cost,
        "cost_source": cost_source,
        "tool_calls": parsed["tool_count"],
        "tool_names": parsed["tool_names"],
        "markup_leak": leaked,
        "top_line_repeats": repeats,
        "top_line": repeat_line,
    }
    summary_path.write_text(json.dumps(summary) + "\n", encoding="utf-8")

    line_display = ""
    if repeat_line:
        line_display = json.dumps(repeat_line[:60])
    print(
        f"run {run}: finish={parsed['finish_reason']} "
        f"completion_tokens={completion_tokens} cost={cost} "
        f"cost_source={cost_source} "
        f"tool_calls={parsed['tool_count']} {parsed['tool_names']} "
        f"markup_leak={str(leaked).lower()} "
        f"top_line_repeats={repeats} {line_display}"
    )

    # Step 6/7 exit rule: an unpriced call poisons the ledger and fails closed.
    if not usage or cost is None:
        print(
            "usage/estimated_cost was absent; wrote the ledger row with "
            "cost=null. The ledger is now POISONED until a human fixes that row.",
            file=sys.stderr,
        )
        sys.exit(2)


def main(argv):
    args = parse_args(argv)
    request_path = Path(args.request)
    out_dir = Path(args.out_dir)
    body = load_body(request_path)
    changes = apply_sets(body, args.set, args.unset)

    if args.dry_run:
        if not changes:
            print("no top-level field changes")
        for kind, key, value in changes:
            if kind == "set":
                print(f"set {key} = {json.dumps(value)}")
            else:
                print(f"unset {key}")
        print(f"runs: {args.runs}")
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    for run in range(1, args.runs + 1):
        refuse_overwrite(out_dir, run)

    key = resolve_key()
    ledger_path = resolve_ledger_path()
    budget = resolve_budget()

    total_cost = 0.0
    leaks = 0
    lengths = 0
    zero_tools = 0
    for run in range(1, args.runs + 1):
        run_one(args, body, run, key, ledger_path, budget, request_path, out_dir)

    for run in range(1, args.runs + 1):
        summary_path = out_dir / f"run-{run:02d}.summary.json"
        try:
            summary = json.loads(summary_path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if summary.get("cost"):
            total_cost += summary["cost"]
        if summary.get("markup_leak"):
            leaks += 1
        if summary.get("finish_reason") == "length":
            lengths += 1
        if summary.get("tool_calls") == 0:
            zero_tools += 1

    print(
        f"totals: runs={args.runs} total_cost={total_cost} "
        f"markup_leak={leaks} finish_length={lengths} zero_tool_calls={zero_tools}"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 - fail closed, never a traceback
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(2)
