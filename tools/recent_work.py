#!/usr/bin/env python3
# recent_work.py -- list open beads Brian named in recent Claude Code sessions (inc-bsgy).
# Reads the session transcripts, not bead update times: nightly runs touch dozens of
# beads a day, so update times do not show what Brian worked on. Stdlib only.
# Usage: tools/recent_work.py [--days N] [--top K] [--projects-dir DIR]
#        [--beads-json FILE] [--exclude-session ID]
# Exit 0 on success; exit 2 when the projects dir or the bead list cannot be read.
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import time

ID_RE = re.compile(r"\binc-[a-z0-9]{3,4}(?:\.\d+)*\b")
DEFAULT_PROJECTS = os.path.expanduser("~/.claude/projects/-Users-brianhill-Scripts-Incursion")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAX_RELATED = 10


def die(msg):
    print(f"recent_work: {msg}", file=sys.stderr)
    sys.exit(2)


def load_beads(path):
    if path:
        try:
            with open(path, encoding="utf-8") as f:
                raw = f.read()
        except OSError as e:
            die(f"cannot read --beads-json {path}: {e}")
    else:
        try:
            r = subprocess.run(["bd", "list", "--all", "--json", "--limit", "0"],
                               cwd=REPO, capture_output=True, text=True)
        except OSError as e:
            die(f"cannot run bd: {e}")
        if r.returncode != 0:
            die(f"bd list failed (exit {r.returncode}): {r.stderr.strip()}")
        raw = r.stdout
    try:
        beads = json.loads(raw)
    except ValueError as e:
        die(f"bead list is not JSON: {e}")
    if not isinstance(beads, list):
        die("bead list is not a JSON array")
    for b in beads:
        if not isinstance(b, dict) or not isinstance(b.get("id"), str):
            die("bead list has an entry without a string id")
    return beads


def message_texts(obj):
    """Return the text parts of one transcript line that count as Brian's signal."""
    if not isinstance(obj, dict) or not isinstance(obj.get("message"), dict):
        return []
    kind = obj.get("type")
    content = obj["message"].get("content")
    out = []
    if kind == "user":
        if isinstance(content, str):
            out.append(content)
        elif isinstance(content, list):
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text" and isinstance(item.get("text"), str):
                    out.append(item["text"])
    elif kind == "assistant" and isinstance(content, list):
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") == "text" and isinstance(item.get("text"), str):
                out.append(item["text"])
            elif item.get("type") == "tool_use":
                out.append(json.dumps(item.get("input"), ensure_ascii=False))
    return out


def scan_sessions(projects_dir, days, exclude):
    if not os.path.isdir(projects_dir):
        die(f"projects dir not found: {projects_dir}")
    cutoff = time.time() - days * 86400
    sessions = []
    for name in sorted(os.listdir(projects_dir)):
        path = os.path.join(projects_dir, name)
        if not name.endswith(".jsonl") or not os.path.isfile(path):
            continue
        sid = name[: -len(".jsonl")]
        mtime = os.path.getmtime(path)
        if mtime < cutoff or sid == exclude:
            continue
        mentions = set()
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    try:
                        obj = json.loads(line)
                    except ValueError:
                        continue
                    for text in message_texts(obj):
                        mentions.update(ID_RE.findall(text))
        except OSError as e:
            die(f"cannot read session {path}: {e}")
        sessions.append((sid, mtime, mentions))
    return sessions


def title_of(b):
    return str(b.get("title") or "")


def main():
    ap = argparse.ArgumentParser(description="Open beads named in recent Claude Code sessions.")
    ap.add_argument("--days", type=int, default=10)
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--projects-dir", default=DEFAULT_PROJECTS)
    ap.add_argument("--beads-json")
    ap.add_argument("--exclude-session")
    args = ap.parse_args()

    beads = load_beads(args.beads_json)
    by_id = {b["id"]: b for b in beads}
    sessions = scan_sessions(args.projects_dir, args.days, args.exclude_session)

    print(f"recent work: {len(sessions)} sessions in last {args.days} days")
    if not sessions:
        print("no sessions in window")
        return 0

    count, last = {}, {}
    for _sid, mtime, mentions in sessions:
        for bid in mentions & set(by_id):
            count[bid] = count.get(bid, 0) + 1
            last[bid] = max(last.get(bid, 0), mtime)

    def related(bid):
        return [b for b in beads
                if b.get("status") != "closed" and b["id"] != bid
                and (b.get("parent") == bid
                     or bid in ID_RE.findall(str(b.get("description") or "")))]

    rel_of = {}
    for bid in count:
        rel = related(bid)
        if by_id[bid].get("status") != "closed" or rel:
            rel_of[bid] = rel
    ranked = sorted(rel_of, key=lambda i: (-count[i], -last[i], i))

    for bid in ranked[: args.top]:
        b = by_id[bid]
        day = datetime.date.fromtimestamp(last[bid]).isoformat()
        print(f"{bid}  {b.get('status', '?')}  {count[bid]}s  last {day}  {title_of(b)[:80]}")
        rel = rel_of[bid]
        for r in rel[:MAX_RELATED]:
            print(f"  -> {r['id']}  {r.get('status', '?')}  {title_of(r)[:70]}")
        if len(rel) > MAX_RELATED:
            print(f"  ... and {len(rel) - MAX_RELATED} more")
        parent = b.get("parent")
        if parent:
            p = by_id.get(parent)
            ptitle = title_of(p) if p else "(not in bead list)"
            print(f"  parent: {parent} {ptitle[:70]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
