#!/usr/bin/env python3
"""A scoped, budget-capped DeepSeek client for this project (bead inc-3dgz).

Sends ONE chat completion to DeepInfra, writes the reply to a file, and
records what it cost in an append-only ledger. The ledger is read and its
running sum is checked against a fixed budget BEFORE any network call is
made, every time -- a call this script cannot price is treated as a poison
that stops every later call until a human fixes the ledger by hand.

Standard library only. No --model flag: one model, one constant. The
spending cap and the model allowlist are enforced on the API key itself,
server side; a flag here would only add a way to get it wrong.
"""

import argparse
import datetime
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

MODEL = "deepseek-ai/DeepSeek-V4.1-Flash"
URL = "https://api.deepinfra.com/v1/openai/chat/completions"
BUDGET = 20.00  # US dollars
SERVICE = "incursion-deepseek-scoped"  # macOS Keychain service name
ACCOUNT = "incursion"  # macOS Keychain account name

REPO_ROOT = Path(__file__).resolve().parent.parent

# The default ledger lives in the MAIN checkout's logs/, not this worktree's:
# with one git worktree per bead, a per-worktree ledger would let each
# worktree's check_budget see only its own spend, and the spend would vanish
# when the worktree is deleted. The main checkout is derived from git (the
# parent of the shared git common dir), so every worktree resolves the same
# path. resolve_ledger_path() computes it lazily; INCURSION_DEEPSEEK_LEDGER
# overrides it first, and if git is unavailable we fall back to REPO_ROOT.


def resolve_url():
    return os.environ.get("INCURSION_DEEPSEEK_URL") or URL


def default_ledger_path():
    """The main checkout's ledger, found from git. Falls back to
    REPO_ROOT/logs/ when git is missing or REPO_ROOT is not a checkout."""
    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(REPO_ROOT),
                "rev-parse",
                "--path-format=absolute",
                "--git-common-dir",
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            common_dir = result.stdout.strip()
            if common_dir:
                main = Path(common_dir).parent
                return main / "logs" / "deepseek-ledger.jsonl"
    except Exception:
        pass
    return REPO_ROOT / "logs" / "deepseek-ledger.jsonl"


def resolve_ledger_path():
    override = os.environ.get("INCURSION_DEEPSEEK_LEDGER")
    return Path(override) if override else default_ledger_path()


def resolve_budget():
    override = os.environ.get("INCURSION_DEEPSEEK_BUDGET")
    return float(override) if override else BUDGET


def resolve_key():
    """Step 1: get the API key, from the env override or the Keychain.
    Exits 2 and prints the fix command on failure. Never prints the key."""
    env_key = os.environ.get("INCURSION_DEEPSEEK_KEY")
    if env_key:
        return env_key

    fix_cmd = (
        f"  security add-generic-password -a {ACCOUNT} -s {SERVICE} -w <API_KEY>"
    )
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-a", ACCOUNT, "-s", SERVICE, "-w"],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except Exception:
        print("could not run `security` to read the Keychain.", file=sys.stderr)
        print("Add the key with:", file=sys.stderr)
        print(fix_cmd, file=sys.stderr)
        sys.exit(2)

    key = result.stdout.strip() if result.returncode == 0 else ""
    if result.returncode != 0 or not key:
        print(
            f"no DeepSeek API key in the Keychain (service {SERVICE!r}, "
            f"account {ACCOUNT!r}).",
            file=sys.stderr,
        )
        print("Add it with:", file=sys.stderr)
        print(fix_cmd, file=sys.stderr)
        sys.exit(2)
    return key


def check_budget(ledger_path, budget):
    """Step 2: sum the ledger's cost column and refuse to spend past budget.
    Exits 1 on refusal or poison, exits 2 on a malformed line. Returns
    nothing on success -- the caller may proceed."""
    if not ledger_path.exists():
        return
    text = ledger_path.read_text()
    total = 0.0
    for lineno, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            print(
                f"malformed ledger line {lineno} in {ledger_path}: not valid JSON",
                file=sys.stderr,
            )
            sys.exit(2)
        cost = row.get("cost")
        if cost is None:
            print(
                f"ledger is POISONED at line {lineno} of {ledger_path}: "
                "cost is null, a call was billed and its price is unknown. "
                "A human must resolve this row before any further call.",
                file=sys.stderr,
            )
            sys.exit(1)
        total += cost
    if total >= budget:
        print(
            f"refused: ledger sum {total} is at or past the budget {budget}; "
            "making no request.",
            file=sys.stderr,
        )
        sys.exit(1)


def build_body(prompt_path, system_path, max_tokens, temperature):
    messages = []
    if system_path:
        messages.append({"role": "system", "content": Path(system_path).read_text()})
    messages.append({"role": "user", "content": Path(prompt_path).read_text()})
    return {
        "model": MODEL,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
    }


def send_request(url, key, body, timeout):
    """Step 4. Returns (status, response_text) on any HTTP response, or
    exits 2 directly on a network failure (no response at all)."""
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", errors="replace")
    except urllib.error.URLError as exc:
        print(f"network failure calling DeepInfra: {exc.reason}", file=sys.stderr)
        sys.exit(2)


def append_ledger_row(ledger_path, row):
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    with ledger_path.open("a") as fh:
        fh.write(json.dumps(row, separators=(",", ":")) + "\n")


def write_output(out_path, content):
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(content)


def run(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompt", required=True, help="path to the prompt text")
    parser.add_argument("--out", required=True, help="path to write the reply to")
    parser.add_argument("--system", help="path to an optional system prompt")
    parser.add_argument("--max-tokens", type=int, default=8000)
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--timeout", type=float, default=300)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    # Step 1: resolve the key.
    key = resolve_key()

    # Step 2: read the ledger and decide whether to spend. Exits on refusal.
    ledger_path = resolve_ledger_path()
    budget = resolve_budget()
    check_budget(ledger_path, budget)

    body = build_body(args.prompt, args.system, args.max_tokens, args.temperature)

    # Step 3: --dry-run prints the body and stops. No request, no ledger row.
    if args.dry_run:
        print(json.dumps(body, indent=2))
        return 0

    # Step 4: send the request.
    status, resp_text = send_request(resolve_url(), key, body, args.timeout)

    if status < 200 or status >= 300:
        print(f"DeepInfra returned HTTP {status}", file=sys.stderr)
        print(resp_text[:2000], file=sys.stderr)
        sys.exit(2)

    try:
        payload = json.loads(resp_text)
    except json.JSONDecodeError:
        print("bad reply: response body is not valid JSON", file=sys.stderr)
        sys.exit(2)

    usage = payload.get("usage") or {}
    prompt_tokens = usage.get("prompt_tokens")
    completion_tokens = usage.get("completion_tokens")
    details = usage.get("prompt_tokens_details") or {}
    cached_tokens = details.get("cached_tokens", 0)
    cost = usage.get("estimated_cost")
    resp_id = payload.get("id")

    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    row = {
        "ts": ts,
        "model": MODEL,
        "prompt": args.prompt,
        "out": args.out,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "cached_tokens": cached_tokens,
        "cost": cost,
        "id": resp_id,
    }

    # Step 5: record the spend before anything else can fail. The money is
    # spent either way, so the row goes in even if a later step exits.
    append_ledger_row(ledger_path, row)

    content = None
    try:
        content = payload["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        content = None

    # Step 6: an unpriced call poisons the ledger and fails closed.
    if cost is None:
        if content:
            write_output(Path(args.out), content)
        print(
            "usage.estimated_cost was absent; wrote the ledger row with "
            "cost=null. The ledger is now POISONED until a human fixes that "
            "row.",
            file=sys.stderr,
        )
        sys.exit(2)

    # Step 7: write the output.
    if not content:
        print(
            "bad reply: choices[0].message.content is absent or empty",
            file=sys.stderr,
        )
        sys.exit(2)

    write_output(Path(args.out), content)
    print(
        f"wrote {args.out}  prompt_tokens={prompt_tokens} "
        f"completion_tokens={completion_tokens} cached_tokens={cached_tokens} "
        f"cost={cost}"
    )
    return 0


def main():
    try:
        sys.exit(run(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 - fail closed, never a traceback
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
