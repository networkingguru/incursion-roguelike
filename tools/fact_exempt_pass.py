#!/usr/bin/env python3
"""PreToolUse hook (matcher Bash): mint a one-use pass for tools/check_fact_lines.py.

It NEVER blocks. It always exits 0 with no stdout, on every path, errors included.

Ruling (bead inc-131k2): a tools/check_* file whose fact lines leave a hole in
the seed controls may be exempted only as the last step, after both the session
and the owner found no way to close the hole. The session asks the owner in
chat, in the form "Is tools/check_<name> exempt? ... hole ...". When the
owner's next real message is a bare yes and the commit follows, this hook
writes <git-common-dir>/fact-exempt/<staged-blob-sha> for each file the
question named. check_fact_lines.py consumes that pass at the next commit.

One yes mints once: the user message id goes in <git-common-dir>/fact-exempt/minted.

Self-test: python3 tools/fact_exempt_pass.py --selftest
"""
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HOOKS_DIR = "/Users/brianhill/.claude/hooks"
GATE_PATH = os.environ.get("INCURSION_COMMIT_GATE_PATH",
                           os.path.join(HOOKS_DIR, "commit-gate.py"))
COMMIT_RE = re.compile(r"\bgit\b((?:\s+-C\s+\S+|\s+-c\s+\S+)*)\s+commit\b")
DASH_C_RE = re.compile(r"\s-C\s+(\S+)")
ASK_RE = re.compile(r"Is (tools/check_[A-Za-z0-9_.-]+) exempt\?")


def load_gate():
    gate_dir = os.path.dirname(GATE_PATH)
    if gate_dir not in sys.path:
        sys.path.insert(0, gate_dir)
    if HOOKS_DIR not in sys.path:
        sys.path.insert(0, HOOKS_DIR)
    spec = importlib.util.spec_from_file_location("commit_gate", GATE_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo] + list(args), capture_output=True,
                       text=True, timeout=10)
    return r.stdout.strip() if r.returncode == 0 else None


def find_answer(gate, transcript):
    """-> (user message id, [paths]) when the latest user message is a yes to
    an exemption question about a hole; else None."""
    user = None
    for line in gate._iter_tail_lines(transcript):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if not isinstance(entry, dict):
            continue
        if user is None:
            if not gate._is_real_user(entry):
                continue
            text = gate._entry_text(entry)
            if not gate._is_assent(text):
                return None
            ident = entry.get("uuid") or hashlib.sha1(
                (text + str(entry.get("timestamp", ""))).encode()).hexdigest()
            user = ident
            continue
        if gate._is_real_user(entry):
            return None
        if gate._is_assistant(entry):
            text = gate._entry_text(entry)
            if not text.strip():
                continue
            if "hole" not in text.lower():
                return None
            paths = list(dict.fromkeys(ASK_RE.findall(text)))
            return (user, paths) if paths else None
    return None


def mint(payload):
    command = payload["tool_input"]["command"]
    m = COMMIT_RE.search(command)
    if not m:
        return
    cwd = payload.get("cwd") or os.getcwd()
    c = DASH_C_RE.search(m.group(1))
    repo = cwd
    if c:
        repo = c.group(1)
        if not os.path.isabs(repo):
            repo = os.path.join(cwd, repo)
    transcript = payload.get("transcript_path")
    if not transcript:
        return
    gate = load_gate()
    found = find_answer(gate, transcript)
    if not found:
        return
    ident, paths = found
    common = git(repo, "rev-parse", "--git-common-dir")
    if not common:
        return
    passdir = os.path.join(os.path.abspath(os.path.join(repo, common)),
                           "fact-exempt")
    os.makedirs(passdir, exist_ok=True)
    ledger = os.path.join(passdir, "minted")
    try:
        with open(ledger) as f:
            if ident in f.read().split():
                return
    except OSError:
        pass
    for p in paths:
        sha = git(repo, "rev-parse", ":" + p)
        if not sha:
            continue
        with open(os.path.join(passdir, sha), "w") as f:
            f.write("%s\n%s\n" % (p, ident))
    with open(ledger, "a") as f:
        f.write(ident + "\n")


def main():
    try:
        raw = sys.stdin.read()
        mint(json.loads(raw))
    except BaseException:                                  # noqa: BLE001
        pass
    return 0


# ---------------------------------------------------------------- selftest

def selftest():
    me = os.path.abspath(__file__)
    here = os.path.dirname(me)
    checker = os.path.join(here, "check_fact_lines.py")
    work = tempfile.mkdtemp(prefix="factpass")
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    fails = [0]
    seq = [0]

    def g(repo, *a):
        return subprocess.run(["git"] + list(a), cwd=repo, env=env,
                              capture_output=True, text=True)

    repo = os.path.join(work, "repo")
    os.makedirs(os.path.join(repo, "tools"))
    g(repo, "init", "-q")
    g(repo, "config", "user.email", "t@t")
    g(repo, "config", "user.name", "t")
    CK = "tools/check_x.sh"
    with open(os.path.join(repo, CK), "w") as f:
        f.write("#!/bin/sh\necho hi\n")
    g(repo, "add", CK)
    sha = g(repo, "rev-parse", ":" + CK).stdout.strip()
    passdir = os.path.join(repo, ".git", "fact-exempt")
    passpath = os.path.join(passdir, sha)

    def entries(*items):
        seq[0] += 1
        out = []
        for i, (kind, text) in enumerate(items):
            if kind == "u":
                out.append({"type": "user", "origin": "human",
                            "uuid": "u%d-%d" % (seq[0], i),
                            "message": {"content": text}})
            else:
                out.append({"type": "assistant", "uuid": "a%d-%d" % (seq[0], i),
                            "message": {"content": [{"type": "text", "text": text}]}})
        return out

    def transcript(items):
        path = os.path.join(work, "t%d.jsonl" % seq[0])
        with open(path, "w") as f:
            for e in items:
                f.write(json.dumps(e) + "\n")
        return path

    def hook(t, command="git commit -m x", raw=None):
        payload = raw if raw is not None else json.dumps({
            "tool_name": "Bash", "cwd": repo, "transcript_path": t,
            "tool_input": {"command": command}})
        r = subprocess.run([sys.executable, me], input=payload, env=env,
                           capture_output=True, text=True, timeout=30)
        return r.returncode, r.stdout

    def reset():
        shutil.rmtree(passdir, ignore_errors=True)

    def case(label, want, got):
        ok = got == want
        print("  %s  %s" % ("ok  " if ok else "FAIL", label)
              + ("" if ok else " (got %s, wanted %s)" % (got, want)))
        if not ok:
            fails[0] += 1

    ask = "Is %s exempt? The seed control has a hole nobody can close." % CK

    try:
        for ans, want in (("y", True), ("yy", True), ("uy", True), ("ty", True),
                          ("yg", True), ("y.", True), ("n", False),
                          ("ny", False), ("no", False)):
            reset()
            t = transcript(entries(("u", "go on"), ("a", ask), ("u", ans)))
            rc, out = hook(t)
            case("answer %r -> pass %s" % (ans, "minted" if want else "not minted"),
                 want, os.path.exists(passpath))
            case("  exit 0, no stdout", (0, ""), (rc, out))

        reset()
        t = transcript(entries(("a", "Is %s exempt? Fine." % CK), ("u", "y")))
        hook(t)
        case("question without the word hole", False, os.path.exists(passpath))

        reset()
        t = transcript(entries(
            ("a", "Is tools/check_other.sh exempt? It has a hole."), ("u", "y")))
        hook(t)
        case("question naming a different file", False, os.path.exists(passpath))

        reset()
        t = transcript(entries(("u", "y")))
        hook(t)
        case("no assistant question", False, os.path.exists(passpath))

        reset()
        t = transcript(entries(("a", ask), ("u", "y")))
        hook(t)
        first = os.path.exists(passpath)
        os.remove(passpath)
        hook(t)
        case("same transcript twice: first mints", True, first)
        case("  second run mints nothing", False, os.path.exists(passpath))

        reset()
        t = transcript(entries(("a", ask), ("u", "y")))
        hook(t, command="git status")
        case("non-commit command", False, os.path.exists(passpath))

        reset()
        rc, out = hook(None, raw="{not json")
        case("malformed payload: exit 0, no output, no pass", (0, "", False),
             (rc, out, os.path.exists(passpath)))

        # Chain: mint, then the checker passes the file once and refuses it next.
        reset()
        t = transcript(entries(("a", ask), ("u", "y")))
        hook(t)
        def chk():
            return subprocess.run([sys.executable, checker], cwd=repo, env=env,
                                  capture_output=True, text=True).returncode
        case("chain: first check run passes the non-conforming file", 0, chk())
        case("chain: next run refuses it", 1, chk())
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print()
    if fails[0]:
        print("SELFTEST FAIL: %d" % fails[0])
        return 1
    print("SELFTEST PASS")
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    sys.exit(main())
