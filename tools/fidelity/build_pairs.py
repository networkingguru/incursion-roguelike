#!/usr/bin/env python3
"""Build ruling-exchange pairs from Claude Code session transcripts.

For a given god's bead, find every notes-write (a Bash tool call whose
command runs ``bd update <bead> ... --append-notes ...``), pair each with
the last real Brian message before it and the Claude question prose that
preceded that Brian message, and write pairs.jsonl.

Standard library only. See brief for the full specification.
"""

import argparse
import glob
import json
import os
import re
import sys

RULING_RE = re.compile(r"\bR(\d{1,3})(?=[ ,(])")
SYSREM_RE = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)

BAD_PREFIXES = (
    "<system-reminder>",
    "<command-",
    "<local-command",
    "<task-notification>",
    "Another Claude session sent a message",
    "[Request interrupted",
    "Caveat:",
)


# --------------------------------------------------------------------------
# text helpers
# --------------------------------------------------------------------------
def _clean_human(text):
    """Strip system-reminder spans, then strip. Return the cleaned string."""
    return SYSREM_RE.sub("", text).strip()


def _human_text(content):
    """Join human text blocks from a user message content.

    Returns "" if there is no human text.
    """
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text":
                t = b.get("text")
                if isinstance(t, str):
                    parts.append(t)
        return "\n".join(parts) if parts else ""
    return ""


def _real_brian(text):
    cleaned = _clean_human(text)
    if not cleaned:
        return None
    for p in BAD_PREFIXES:
        if cleaned.startswith(p):
            return None
    return cleaned


def _extract_rulings(text):
    nums = set()
    for m in RULING_RE.finditer(text):
        nums.add(int(m.group(1)))
    return sorted(nums)


# --------------------------------------------------------------------------
# Brian-quote fragments
# --------------------------------------------------------------------------
BRIAN_WORD_RE = re.compile(r"Brian(?:'s| on\b)?")
QUOTE_JOINS = (" ... ", " then ")


def _normalise(s):
    """Lowercase, collapse whitespace, strip surrounding punctuation."""
    s = s.lower()
    s = re.sub(r"\s+", " ", s).strip()
    return s.strip(" \t.,;:!?\"'()[]{}<>-—–")


def _fragment_matches(frag, message):
    """True when a normalised fragment matches a normalised message.

    A fragment of >= 12 normalised characters matches as a substring (its
    first 60 normalised characters if longer). A shorter fragment matches
    only when the whole normalised message equals it.
    """
    nf = _normalise(frag)
    if not nf:
        return False
    nm = _normalise(message)
    if not nm:
        return False
    if len(nf) >= 12:
        return nf[:60] in nm
    return nm == nf


def extract_brian_fragments(text):
    """Return quoted fragments that belong to Brian in a ruling text.

    Every single- or double-quoted span that starts within 60 characters
    after an occurrence of ``Brian`` (including ``Brian's`` and
    ``Brian on X:``) is taken, plus further quoted spans joined to it by
    `` ... `` or ``then``.
    """
    frags = []
    for bm in BRIAN_WORD_RE.finditer(text):
        window_end = min(bm.end() + 60, len(text))
        i = bm.end()
        first = None
        while i < window_end:
            # skip to the next quote character
            qi = i
            while qi < window_end and text[qi] not in ("'", '"'):
                qi += 1
            if qi >= window_end:
                break
            q = text[qi]
            close = text.find(q, qi + 1)
            if close < 0:
                break
            frags.append(text[qi + 1:close])
            first = len(frags) - 1
            # follow the join chain: ' ... ' or ' then ' then a quote
            j = close + 1
            while True:
                join_at = None
                for join in QUOTE_JOINS:
                    if text.startswith(join, j):
                        join_at = j + len(join)
                        break
                if join_at is None:
                    break
                k = join_at
                while k < len(text) and text[k] not in ("'", '"'):
                    k += 1
                if k >= len(text):
                    break
                q2 = text[k]
                close2 = text.find(q2, k + 1)
                if close2 < 0:
                    break
                frags.append(text[k + 1:close2])
                j = close2 + 1
            i = close + 1
    return frags


def match_brian(frags, brian):
    """Return (index, pairing) for the newest matching Brian message.

    ``brian`` is the session's ordered list of Brian dicts. Returns
    (index, "quote") when a fragment matches, else (None, status) where
    status is "quote-unmatched" when fragments exist and "fallback" when
    there are none. The fallback index (last message) is chosen by caller.
    """
    if not frags:
        return None, "fallback"
    for idx in range(len(brian) - 1, -1, -1):
        msg = brian[idx]["text"]
        for frag in frags:
            if _fragment_matches(frag, msg):
                return idx, "quote"
    return None, "quote-unmatched"


# --------------------------------------------------------------------------
# notes extraction
# --------------------------------------------------------------------------
def _read_cat_file(path):
    """Return the contents of ``path`` when readable, else None."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return None


def _frozen_recover(prefix, frozen_text, next_ruling):
    """Recover the text spliced by an unreadable ``$(cat ...)``.

    Find ``prefix`` in frozen_text, then take everything after it up to the
    start of the next notes-write's ruling text (``next_ruling``); if there
    is no next write or it is not found, take to end of file.
    """
    if not frozen_text:
        return None
    at = frozen_text.find(prefix)
    if at < 0:
        return None
    start = at + len(prefix)
    if next_ruling:
        probe = next_ruling[:60]
        nxt = frozen_text.find(probe, start)
        if nxt >= 0:
            return frozen_text[start:nxt]
    return frozen_text[start:]


def extract_notes(command, frozen_text="", next_ruling=""):
    """Extract appended notes text from a Bash command.

    Returns (text, extract_ok, extract_src). Handles double-quoted,
    single-quoted and heredoc bodies. Inside a double-quoted argument a
    ``$( ... )`` substitution is treated as one unit; a ``$(cat ...)``
    substitution is spliced in from disk or recovered from frozen_text.
    """
    idx = command.find("--append-notes")
    if idx < 0:
        return command, False, "command"
    rest = command[idx + len("--append-notes"):]
    rest = rest.lstrip()

    # heredoc: $(cat <<'EOF' ... EOF) or $(cat <<EOF ... EOF)
    if rest.startswith("$("):
        hd = re.search(r"<<-?\s*'?([A-Za-z_][A-Za-z0-9_]*)'?", rest)
        if hd:
            delim = hd.group(1)
            after = rest[hd.end():]
            if after.startswith("\n"):
                after = after[1:]
            lines = after.split("\n")
            body = []
            found = False
            for ln in lines:
                if ln.strip() == delim:
                    found = True
                    break
                body.append(ln)
            if found:
                return "\n".join(body), True, "command"
            return command, False, "command"

    if rest.startswith('"'):
        # Scan for the unescaped closing double quote, treating $( ... )
        # as one unit; splice $(cat ...) and recover unreadable ones.
        i = 1
        buf = []
        src = "command"
        while i < len(rest):
            c = rest[i]
            if c == "\\" and i + 1 < len(rest):
                nxt = rest[i + 1]
                if nxt in ('"', "\\"):
                    buf.append(nxt)
                else:
                    buf.append(c)
                    buf.append(nxt)
                i += 2
                continue
            if c == "$" and i + 1 < len(rest) and rest[i + 1] == "(":
                depth = 1
                j = i + 2
                inner = []
                while j < len(rest) and depth > 0:
                    cj = rest[j]
                    if cj == "\\" and j + 1 < len(rest):
                        inner.append(cj)
                        inner.append(rest[j + 1])
                        j += 2
                        continue
                    if cj == "(":
                        depth += 1
                    elif cj == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    inner.append(cj)
                    j += 1
                inner = "".join(inner)
                cat = re.match(r"\s*cat\s+(.*)$", inner.strip())
                path = None
                if cat:
                    arg = cat.group(1).strip()
                    if (len(arg) >= 2 and arg[0] == arg[-1]
                            and arg[0] in ("'", '"')):
                        arg = arg[1:-1]
                    path = arg
                spliced = None
                if path is not None:
                    spliced = _read_cat_file(path)
                    if spliced is not None:
                        src = "file"
                    else:
                        spliced = _frozen_recover(
                            "".join(buf), frozen_text, next_ruling)
                        if spliced is not None:
                            src = "frozen"
                if spliced is not None:
                    buf.append(spliced)
                if j < len(rest) and rest[j] == ")":
                    i = j + 1
                else:
                    i = j
                continue
            if c == '"':
                return "".join(buf), True, src
            buf.append(c)
            i += 1
        return command, False, "command"

    if rest.startswith("'"):
        end = rest.find("'", 1)
        if end >= 0:
            return rest[1:end], True, "command"
        return command, False, "command"

    return command, False, "command"


# --------------------------------------------------------------------------
# event readers
# --------------------------------------------------------------------------
def parse_lines(text):
    """Yield (event, ok). Counts parse failures by returning ok=False."""
    events = []
    bad = 0
    for line in text.split("\n"):
        if not line.strip():
            continue
        try:
            events.append(json.loads(line))
        except Exception:
            bad += 1
    return events, bad


def _blocks(event):
    m = event.get("message")
    if not isinstance(m, dict):
        return []
    c = m.get("content")
    if isinstance(c, list):
        return [b for b in c if isinstance(b, dict)]
    return []


# --------------------------------------------------------------------------
# notes-write matching
# --------------------------------------------------------------------------
def bead_update_re(bead):
    """Regex matching ``bd update <bead>`` with a boundary after the id.

    The id must be followed by a space, tab or newline, so ``inc-pu6v.9``
    never matches ``inc-pu6v.91``.
    """
    return re.compile(r"\bbd\s+update\s+" + re.escape(bead) + r"(?=[ \t\n])")


# --------------------------------------------------------------------------
# core builder
# --------------------------------------------------------------------------
def build_from_events(events, session, frozen_text="", bead=None):
    """Return (pairs, bad_json_count). events is a list of parsed objects.

    Two passes over the session: the first collects the ordered Brian
    messages and the raw notes-writes, so that each write's ``next_ruling``
    (the following write's ruling text) is known; the second re-extracts the
    notes with that context and pairs each write.
    """
    update_re = bead_update_re(bead) if bead else None
    brian = []  # list of dicts: {ts, text, q_text}
    writes = []  # list of dicts: {ts, cmd}
    pending_q = []

    for ev in events:
        if ev.get("isSidechain") is True:
            continue
        typ = ev.get("type")
        ts = ev.get("timestamp")
        if typ == "user":
            content = ev.get("message", {}).get("content")
            human = _human_text(content)
            cleaned = _clean_human(human)
            if cleaned:
                bt = _real_brian(human)
                if bt is not None:
                    q = "\n\n".join(pending_q)
                    brian.append({"ts": ts, "text": bt, "q_text": q})
                    pending_q = []
            continue
        if typ == "assistant":
            blocks = _blocks(ev)
            for b in blocks:
                if b.get("type") == "text":
                    t = b.get("text")
                    if isinstance(t, str) and t.strip():
                        pending_q.append(t)
            for b in blocks:
                if b.get("type") != "tool_use" or b.get("name") != "Bash":
                    continue
                inp = b.get("input") or {}
                cmd = inp.get("command") if isinstance(inp, dict) else None
                if not isinstance(cmd, str):
                    continue
                if update_re is not None and not update_re.search(cmd):
                    continue
                if "--append-notes" not in cmd:
                    continue
                writes.append({"ts": ts, "cmd": cmd,
                               "brian_count": len(brian)})
            continue

    # Pass 1: raw extract to learn each write's ruling text (for next_ruling).
    raw_texts = []
    for w in writes:
        text, _ok, _src = extract_notes(w["cmd"])
        raw_texts.append(text)

    pairs = []
    n = 0
    used = set()  # brian indices already chosen by an earlier write
    for k, w in enumerate(writes):
        next_ruling = raw_texts[k + 1] if k + 1 < len(raw_texts) else ""
        text, ok, src = extract_notes(w["cmd"], frozen_text, next_ruling)
        n += 1
        # Only Brian messages seen up to the moment this write's event was
        # reached are eligible: a write can never pair with a later message.
        earlier_brian = brian[:w.get("brian_count", len(brian))]
        frags = extract_brian_fragments(text)
        idx, pairing = match_brian(frags, earlier_brian)
        if idx is None:
            idx = len(earlier_brian) - 1  # last Brian message so far (or none)
        if idx < 0:
            idx = None
        # A quote match can land on an early message of a multi-turn
        # exchange.  When it does, `i` is that message and `L` is the last
        # Brian message before the write; the pair must carry the whole
        # span i..L, not just message i.
        span_end = None
        if idx is not None and pairing == "quote":
            last_before = len(earlier_brian) - 1
            if idx < last_before:
                span_end = last_before
                pairing = "quote-span"
        pair = {
            "pair_id": "%s-%d" % (session, n),
            "session": session,
            "write_ts": w["ts"],
            "ruling_text": text,
            "extract_ok": ok,
            "extract_src": src,
            "brian_ts": "",
            "brian_text": "",
            "question_ts": "",
            "question_text": "",
            "r_numbers": _extract_rulings(text),
            "pairing": pairing,
            "brian_reused": False,
            "brian_index": -1 if idx is None else idx,
            "brian_index_end": -1 if idx is None else idx,
        }
        if idx is not None:
            chosen = brian[idx]
            pair["brian_ts"] = chosen["ts"] if chosen["ts"] else ""
            if span_end is not None:
                pair["brian_text"] = "\n---\n".join(
                    brian[j]["text"] for j in range(idx, span_end + 1))
                pair["brian_index_end"] = span_end
            else:
                pair["brian_text"] = chosen["text"]
            pair["question_ts"] = chosen["ts"] if chosen["ts"] else ""
            pair["question_text"] = chosen["q_text"]
            if idx in used:
                pair["brian_reused"] = True
            used.add(idx)
        pairs.append(pair)
    return pairs, 0


def load_session(path, frozen_text="", bead=None):
    session = os.path.basename(path)[:8]
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    events, bad = parse_lines(text)
    pairs, _ = build_from_events(events, session, frozen_text, bead)
    return session, pairs, bad


# --------------------------------------------------------------------------
# transcript discovery
# --------------------------------------------------------------------------
DEFAULT_PROJECT_GLOB = os.path.join(
    "~", ".claude", "projects", "-Users-brianhill-Scripts-Incursion*")


def _expand_transcripts(specs):
    """Expand --transcripts specs into a sorted list of .jsonl paths.

    A spec is a .jsonl file or a directory of them.
    """
    out = []
    for spec in specs:
        path = os.path.expanduser(spec)
        if os.path.isdir(path):
            out.extend(sorted(glob.glob(os.path.join(path, "*.jsonl"))))
        else:
            out.append(path)
    return sorted(set(out))


def _default_transcripts():
    """Every *.jsonl directly inside each matching default project dir."""
    out = []
    for root in glob.glob(os.path.expanduser(DEFAULT_PROJECT_GLOB)):
        if os.path.isdir(root):
            out.extend(sorted(glob.glob(os.path.join(root, "*.jsonl"))))
    return sorted(set(out))


def _file_has_bead(path, bead):
    """Cheap byte check: does this file contain the bead id string at all?"""
    needle = bead.encode("utf-8", "replace")
    try:
        with open(path, "rb") as fh:
            prev = b""
            while True:
                chunk = fh.read(1 << 20)
                if not chunk:
                    return False
                if needle in prev + chunk:
                    return True
                prev = chunk[-(len(needle) - 1):] if len(needle) > 1 else b""
    except OSError:
        return False


# --------------------------------------------------------------------------
# session-prefix disambiguation
# --------------------------------------------------------------------------
def assign_sessions(paths):
    """Map each transcript path to its session id.

    The default is the first 8 characters of the file name. If two files
    share those 8 characters, both use the full file stem instead.
    """
    prefixes = {}
    for path in paths:
        stem = os.path.splitext(os.path.basename(path))[0]
        prefixes.setdefault(stem[:8], []).append(path)
    result = {}
    for path in paths:
        stem = os.path.splitext(os.path.basename(path))[0]
        prefix = stem[:8]
        if len(prefixes[prefix]) > 1:
            result[path] = stem
        else:
            result[path] = prefix
    return result


# --------------------------------------------------------------------------
# coverage
# --------------------------------------------------------------------------
def frozen_rulings(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        txt = fh.read()
    return set(_extract_rulings(txt))


def _counts(pairs, field):
    c = {}
    for p in pairs:
        v = p.get(field)
        c[v] = c.get(v, 0) + 1
    return ", ".join("%s=%d" % (k, c[k]) for k in sorted(c, key=str))


def run(args):
    if args.transcripts:
        files = _expand_transcripts(args.transcripts)
    else:
        files = _default_transcripts()
    if not files:
        sys.stderr.write("no transcript files found\n")
        return 2
    try:
        with open(args.notes, "r", encoding="utf-8", errors="replace") as fh:
            frozen_text = fh.read()
    except OSError as exc:
        sys.stderr.write("cannot read notes %s: %s\n" % (args.notes, exc))
        return 2

    sessions = assign_sessions(files)

    all_pairs = []
    bad_json = 0
    per_session = {}
    scanned = 0
    held = 0
    for path in files:
        # Cheap byte check: skip transcripts that never mention the bead.
        if not _file_has_bead(path, args.bead):
            continue
        scanned += 1
        session = sessions[path]
        try:
            _s, pairs, bad = load_session(path, frozen_text, args.bead)
        except OSError as exc:
            sys.stderr.write("cannot read %s: %s\n" % (path, exc))
            return 2
        if not pairs:
            continue
        held += 1
        bad_json += bad
        per_session[session] = len(pairs)
        all_pairs.extend(pairs)

    if not all_pairs:
        sys.stderr.write(
            "no transcript holds a notes-write for bead %s\n" % args.bead)
        return 2

    found = set()
    for p in all_pairs:
        found.update(p["r_numbers"])

    try:
        with open(args.out, "w", encoding="utf-8") as fh:
            for p in all_pairs:
                fh.write(json.dumps(p, ensure_ascii=False) + "\n")
    except OSError as exc:
        sys.stderr.write("cannot write %s: %s\n" % (args.out, exc))
        return 2

    frozen = frozen_rulings(args.notes)
    missing = sorted(n for n in frozen if n not in found)

    # Time-order check: a pair's Brian message must not postdate the write.
    # ISO-8601 strings compare lexicographically in chronological order.
    violations = 0
    for p in all_pairs:
        bts = p.get("brian_ts")
        wts = p.get("write_ts")
        if bts and wts and bts > wts:
            violations += 1

    print("transcript files scanned: %d" % scanned)
    print("transcript files with notes-writes: %d" % held)
    print("pairs: %d" % len(all_pairs))
    print("pairs per session:")
    for s in sorted(per_session):
        print("  %s: %d" % (s, per_session[s]))
    print("unparseable JSONL lines: %d" % bad_json)
    print("extract_ok false: %d" % sum(1 for p in all_pairs if not p["extract_ok"]))
    print("extract_src counts: %s" % _counts(all_pairs, "extract_src"))
    print("pairing counts: %s" % _counts(all_pairs, "pairing"))
    print("brian_reused true: %d" % sum(1 for p in all_pairs if p["brian_reused"]))
    print("frozen ruling numbers found: %d" % len(frozen))
    print("missing ruling numbers: %s" % (missing if missing else "none"))
    print("time-order violations: %d" % violations)

    return 1 if (missing or violations) else 0


# --------------------------------------------------------------------------
# selftest
# --------------------------------------------------------------------------
def _selftest():
    # Fixture: two Brian messages, one Claude question, one notes-write with
    # a double-quoted argument containing \" and R12, one sidechain event
    # that must be ignored, one <system-reminder> user event ignored.
    cmd = 'bd update inc-pu6v.9 --append-notes "DOSSIER R12, a \\"quoted\\" ruling" -q'
    events = [
        {"type": "user", "isSidechain": False, "timestamp": "t0",
         "message": {"content": "first brian"}},
        {"type": "assistant", "isSidechain": False, "timestamp": "t1",
         "message": {"content": [{"type": "text", "text": "the question prose"}]}},
        {"type": "user", "isSidechain": False, "timestamp": "t2",
         "message": {"content": "second brian"}},
         {"type": "assistant", "isSidechain": False, "timestamp": "t3",
          "message": {"content": [
              {"type": "text", "text": "question before write"},
              {"type": "tool_use", "name": "Bash", "input": {"command": cmd}},
          ]}},
        {"type": "user", "isSidechain": True, "timestamp": "t4",
         "message": {"content": "sidechain brian"}},
        {"type": "user", "isSidechain": False, "timestamp": "t5",
         "message": {"content": "<system-reminder>ignore me</system-reminder>"}},
    ]
    pairs, _ = build_from_events(events, "fixture1", bead="inc-pu6v.9")
    assert len(pairs) == 1, "expected exactly one pair, got %d" % len(pairs)
    p = pairs[0]
    assert p["extract_ok"] is True, "extract_ok must be True"
    assert p["ruling_text"] == 'DOSSIER R12, a "quoted" ruling', \
        "bad ruling_text: %r" % p["ruling_text"]
    assert p["r_numbers"] == [12], "r_numbers must be [12], got %r" % p["r_numbers"]
    assert p["brian_text"] == "second brian", \
        "brian_text wrong: %r" % p["brian_text"]
    assert p["question_text"] == "the question prose", \
        "question_text wrong: %r" % p["question_text"]

    # Now delete the notes-write: coverage must report R12 missing, exit 1.
    events2 = [e for e in events
               if not (e.get("type") == "assistant"
                       and any(isinstance(b, dict) and b.get("type") == "tool_use"
                               for b in e.get("message", {}).get("content", [])))]
    pairs2, _ = build_from_events(events2, "fixture1", bead="inc-pu6v.9")
    assert pairs2 == [], "notes-write should be gone"
    found = set()
    for q in pairs2:
        found.update(q["r_numbers"])
    frozen = {12}
    missing = sorted(n for n in frozen if n not in found)
    assert missing == [12], "coverage should report R12 missing, got %r" % missing
    rc = 1 if missing else 0
    assert rc == 1, "coverage exit code should be 1"

    # ------------------------------------------------------------------
    # Pairing fixtures
    # ------------------------------------------------------------------
    def _bmsg(ts, text):
        return {"type": "user", "isSidechain": False, "timestamp": ts,
                "message": {"content": text}}

    def _aq(ts, prose, cmd):
        blocks = []
        if prose is not None:
            blocks.append({"type": "text", "text": prose})
        if cmd is not None:
            blocks.append({"type": "tool_use", "name": "Bash",
                           "input": {"command": cmd}})
        return {"type": "assistant", "isSidechain": False, "timestamp": ts,
                "message": {"content": blocks}}

    # (a) A write quoting 'alpha message long enough' pairs with that earlier
    # message, not with a later 'y' message; question_text is the prose before
    # the matched message.
    cmd_a = ('bd update inc-pu6v.9 --append-notes '
             '"R1 (Brian: \'alpha message long enough\'): done" -q')
    events_a = [
        _aq("a0", None, None),  # placeholder
        _aq("a0", "prose before alpha", None),
        _bmsg("a1", "alpha message long enough"),
        _aq("a2", "prose before y", None),
        _bmsg("a3", "y"),
        _aq("a4", "claude question", cmd_a),
    ]
    events_a = [e for e in events_a[1:]]
    pairs_a, _ = build_from_events(events_a, "fixtureA", bead="inc-pu6v.9")
    assert len(pairs_a) == 1, "fixtureA: expected 1 pair, got %d" % len(pairs_a)
    pa = pairs_a[0]
    # Under the span rule, quoting the earlier 'alpha' message when a later
    # 'y' message exists makes i(0) < L(1), so the pair is a quote-span.
    assert pa["pairing"] == "quote-span", \
        "fixtureA: pairing must be quote-span, got %r" % pa["pairing"]
    assert pa["brian_text"] == "alpha message long enough\n---\ny", \
        "fixtureA: brian_text wrong: %r" % pa["brian_text"]
    assert pa["question_text"] == "prose before alpha", \
        "fixtureA: question_text wrong: %r" % pa["question_text"]
    assert pa["brian_index"] == 0, \
        "fixtureA: brian_index must be 0, got %r" % pa["brian_index"]

    # (b) A write quoting 'y' pairs with a message that is exactly 'y',
    # not a message 'yes but no'.
    cmd_b = ('bd update inc-pu6v.9 --append-notes '
             '"R2 (Brian: \'y\'): ok" -q')
    events_b = [
        _bmsg("b0", "yes but no"),
        _bmsg("b1", "y"),
        _aq("b2", "claude question", cmd_b),
    ]
    pairs_b, _ = build_from_events(events_b, "fixtureB", bead="inc-pu6v.9")
    pb = pairs_b[0]
    assert pb["pairing"] == "quote", \
        "fixtureB: pairing must be quote, got %r" % pb["pairing"]
    assert pb["brian_text"] == "y", \
        "fixtureB: must pair with exact 'y', got %r" % pb["brian_text"]
    assert pb["brian_index"] == 1, \
        "fixtureB: brian_index must be 1, got %r" % pb["brian_index"]

    # (c) A write with no quote gets pairing == 'fallback' and, when the
    # previous write already took the same message, brian_reused == true.
    cmd_c1 = 'bd update inc-pu6v.9 --append-notes "R3 first, no quotes" -q'
    cmd_c2 = 'bd update inc-pu6v.9 --append-notes "R4 second, no quotes" -q'
    events_c = [
        _bmsg("c0", "only brian"),
        _aq("c1", "q1", cmd_c1),
        _aq("c2", "q2", cmd_c2),
    ]
    pairs_c, _ = build_from_events(events_c, "fixtureC", bead="inc-pu6v.9")
    assert len(pairs_c) == 2, "fixtureC: expected 2 pairs, got %d" % len(pairs_c)
    pc1, pc2 = pairs_c
    assert pc1["pairing"] == "fallback" and pc2["pairing"] == "fallback", \
        "fixtureC: pairing must be fallback, got %r/%r" % (
            pc1["pairing"], pc2["pairing"])
    assert pc1["brian_reused"] is False, "fixtureC: first must not be reused"
    assert pc2["brian_reused"] is True, "fixtureC: second must be reused"
    assert pc1["brian_text"] == pc2["brian_text"] == "only brian", \
        "fixtureC: both must pair with 'only brian'"

    # (d) A $(cat "/nonexistent/x.md") write with fixture frozen text
    # recovers the body (extract_src == 'frozen'), no file needed.
    cmd_d = ('bd update inc-pu6v.9 --append-notes '
             '"CLOSING SECTION:\n$(cat \"/nonexistent/x.md\")" >/dev/null')
    frozen_fixture = (
        "CLOSING SECTION:\n"
        "# Body line one\n"
        "# Body line two\n"
        "NEXT WRITE start marker rest\n"
        "trailing junk\n"
    )
    events_d = [
        _bmsg("d0", "brian"),
        _aq("d1", "q", cmd_d),
    ]
    pairs_d, _ = build_from_events(
        events_d, "fixtureD", frozen_fixture, bead="inc-pu6v.9")
    pd = pairs_d[0]
    assert pd["extract_src"] == "frozen", \
        "fixtureD: extract_src must be frozen, got %r" % pd["extract_src"]
    assert "# Body line one" in pd["ruling_text"], \
        "fixtureD: body not recovered: %r" % pd["ruling_text"]
    assert "# Body line two" in pd["ruling_text"], \
        "fixtureD: body truncated: %r" % pd["ruling_text"]

    # (d2) Same recovery but with a following write, so the next ruling's
    # first 60 characters cut the frozen extraction.
    cmd_d2 = 'bd update inc-pu6v.9 --append-notes "NEXT WRITE start marker rest" -q'
    events_d2 = [
        _bmsg("d0", "brian"),
        _aq("d1", "q", cmd_d),
        _aq("d2", "q2", cmd_d2),
    ]
    pairs_d2, _ = build_from_events(
        events_d2, "fixtureD2", frozen_fixture, bead="inc-pu6v.9")
    pd2 = pairs_d2[0]
    assert pd2["extract_src"] == "frozen", \
        "fixtureD2: extract_src must be frozen, got %r" % pd2["extract_src"]
    assert "# Body line two" in pd2["ruling_text"], \
        "fixtureD2: body should be present: %r" % pd2["ruling_text"]
    assert "trailing junk" not in pd2["ruling_text"], \
        "fixtureD2: next ruling must cut extraction: %r" % pd2["ruling_text"]

    # (e) '...' and 'then' joins extend the fragment list; a fragment joined
    # after a Brian quote matches a message even when the first fragment
    # matches nothing.
    long_first = ("nothing matches this phrase and it is deliberately "
                  "made long so the joined fragment lies beyond the window")
    cmd_e = ('bd update inc-pu6v.9 --append-notes '
             '"R5 (Brian: \'' + long_first + '\' ... '
             '\'the joined ruling text\'): done" -q')
    events_e = [
        _bmsg("e0", "an unrelated earlier message"),
        _bmsg("e1", "the joined ruling text"),
        _aq("e2", "q", cmd_e),
    ]
    pairs_e, _ = build_from_events(events_e, "fixtureE", bead="inc-pu6v.9")
    pe = pairs_e[0]
    assert pe["pairing"] == "quote", \
        "fixtureE: pairing must be quote, got %r" % pe["pairing"]
    assert pe["brian_text"] == "the joined ruling text", \
        "fixtureE: joined fragment must match: %r" % pe["brian_text"]

    # (f) A write quoting 'y' must pair with the FIRST 'y' (index 0), not
    # with a later 'y' that came after the write.
    cmd_f = ('bd update inc-pu6v.9 --append-notes '
             '"R6 (Brian: \'y\'): done" -q')
    events_f = [
        _bmsg("f0", "y"),
        _aq("f1", "q", cmd_f),
        _bmsg("f2", "y"),
    ]
    pairs_f, _ = build_from_events(events_f, "fixtureF", bead="inc-pu6v.9")
    assert len(pairs_f) == 1, "fixtureF: expected 1 pair, got %d" % len(pairs_f)
    pf = pairs_f[0]
    assert pf["pairing"] == "quote", \
        "fixtureF: pairing must be quote, got %r" % pf["pairing"]
    assert pf["brian_index"] == 0, \
        "fixtureF: must pair with first 'y', got index %r" % pf["brian_index"]
    assert pf["brian_text"] == "y", \
        "fixtureF: brian_text wrong: %r" % pf["brian_text"]
    assert pf["brian_ts"] == "f0", \
        "fixtureF: brian_ts must be f0, got %r" % pf["brian_ts"]

    # (g) A write with no quote followed by a later Brian message must pair
    # with the last message BEFORE the write, not the later one.
    cmd_g = 'bd update inc-pu6v.9 --append-notes "R7 no quotes here" -q'
    events_g = [
        _bmsg("g0", "before one"),
        _bmsg("g1", "before two"),
        _aq("g2", "q", cmd_g),
        _bmsg("g3", "after write"),
    ]
    pairs_g, _ = build_from_events(events_g, "fixtureG", bead="inc-pu6v.9")
    assert len(pairs_g) == 1, "fixtureG: expected 1 pair, got %d" % len(pairs_g)
    pg = pairs_g[0]
    assert pg["pairing"] == "fallback", \
        "fixtureG: pairing must be fallback, got %r" % pg["pairing"]
    assert pg["brian_text"] == "before two", \
        "fixtureG: must pair with last before write, got %r" % pg["brian_text"]
    assert pg["brian_index"] == 1, \
        "fixtureG: brian_index must be 1, got %r" % pg["brian_index"]
    assert pg["brian_ts"] == "g1", \
        "fixtureG: brian_ts must be g1, got %r" % pg["brian_ts"]

    # (h) A write quoting only an EARLY message of a multi-turn exchange
    # must carry the whole span through the last message before the write.
    cmd_h = ('bd update inc-pu6v.9 --append-notes '
             '"R8 (Brian: \'first draft reply long enough\'): done" -q')
    events_h = [
        _aq("hp", "claude prose", None),
        _bmsg("h0", "first draft reply long enough"),
        _aq("h1", "claude middle", None),
        _bmsg("h2", "good"),
        _aq("h3", "claude question", cmd_h),
    ]
    pairs_h, _ = build_from_events(events_h, "fixtureH", bead="inc-pu6v.9")
    assert len(pairs_h) == 1, "fixtureH: expected 1 pair, got %d" % len(pairs_h)
    ph = pairs_h[0]
    assert ph["pairing"] == "quote-span", \
        "fixtureH: pairing must be quote-span, got %r" % ph["pairing"]
    assert ph["brian_text"] == "first draft reply long enough\n---\ngood", \
        "fixtureH: span text wrong: %r" % ph["brian_text"]
    assert ph["brian_index"] == 0, \
        "fixtureH: brian_index must be 0, got %r" % ph["brian_index"]
    assert ph["brian_index_end"] == 1, \
        "fixtureH: brian_index_end must be 1, got %r" % ph["brian_index_end"]
    assert ph["brian_ts"] == "h0", \
        "fixtureH: brian_ts must be h0, got %r" % ph["brian_ts"]
    assert ph["question_text"] == "claude prose", \
        "fixtureH: question_text wrong: %r" % ph["question_text"]

    # (h2) A quote match on the LAST message before the write is unchanged:
    # pairing stays "quote", no span, brian_index_end == brian_index.
    cmd_h2 = ('bd update inc-pu6v.9 --append-notes '
              '"R9 (Brian: \'good\'): done" -q')
    events_h2 = [
        _bmsg("h0", "first draft reply long enough"),
        _bmsg("h2", "good"),
        _aq("h3", "claude question", cmd_h2),
    ]
    pairs_h2, _ = build_from_events(events_h2, "fixtureH2", bead="inc-pu6v.9")
    ph2 = pairs_h2[0]
    assert ph2["pairing"] == "quote", \
        "fixtureH2: pairing must stay quote, got %r" % ph2["pairing"]
    assert ph2["brian_text"] == "good", \
        "fixtureH2: brian_text wrong: %r" % ph2["brian_text"]
    assert ph2["brian_index_end"] == ph2["brian_index"] == 1, \
        "fixtureH2: index_end must equal index, got %r/%r" % (
            ph2["brian_index"], ph2["brian_index_end"])

    # ------------------------------------------------------------------
    # (i) Bead-id boundary: inc-pu6v.9 must NOT match inc-pu6v.91.
    # Positive control first: the exact bead DOES match.
    cmd_i = 'bd update inc-pu6v.9 --append-notes "R10 exact bead" -q'
    events_i = [_bmsg("i0", "brian"), _aq("i1", "q", cmd_i)]
    pairs_i, _ = build_from_events(events_i, "fixtureI", bead="inc-pu6v.9")
    assert len(pairs_i) == 1, \
        "fixtureI: exact bead must match, got %d pairs" % len(pairs_i)

    # Negative: a longer id that merely starts with the bead must not match.
    cmd_i2 = ('bd update inc-pu6v.91 --append-notes "R11 wrong bead" -q')
    events_i2 = [_bmsg("i0", "brian"), _aq("i1", "q", cmd_i2)]
    pairs_i2, _ = build_from_events(events_i2, "fixtureI2", bead="inc-pu6v.9")
    assert pairs_i2 == [], \
        "fixtureI2: inc-pu6v.91 must NOT match bead inc-pu6v.9, got %d" % (
            len(pairs_i2))

    # ------------------------------------------------------------------
    # (j) Duplicate 8-character session prefixes use the full file stem.
    dup_paths = [
        "/tmp/abcdef01-aaaa.jsonl",
        "/tmp/abcdef01-bbbb.jsonl",
        "/tmp/unique99-cccc.jsonl",
    ]
    sessions = assign_sessions(dup_paths)
    assert sessions["/tmp/abcdef01-aaaa.jsonl"] == "abcdef01-aaaa", \
        "fixtureJ: colliding file must use full stem, got %r" % (
            sessions["/tmp/abcdef01-aaaa.jsonl"])
    assert sessions["/tmp/abcdef01-bbbb.jsonl"] == "abcdef01-bbbb", \
        "fixtureJ: colliding file must use full stem, got %r" % (
            sessions["/tmp/abcdef01-bbbb.jsonl"])
    assert sessions["/tmp/unique99-cccc.jsonl"] == "unique99", \
        "fixtureJ: non-colliding file must use 8-char prefix, got %r" % (
            sessions["/tmp/unique99-cccc.jsonl"])

    # Positive control for the non-colliding case: a lone file gets its
    # 8-character prefix.
    lone = assign_sessions(["/tmp/orphan00-zzzz.jsonl"])
    assert lone["/tmp/orphan00-zzzz.jsonl"] == "orphan00", \
        "fixtureJ: lone file must use 8-char prefix, got %r" % (
            lone["/tmp/orphan00-zzzz.jsonl"])

    print("selftest OK")
    return 0


# --------------------------------------------------------------------------
def _build_parser():
    parser = argparse.ArgumentParser(
        description="Build ruling-exchange pairs from session transcripts.")
    parser.add_argument("--bead", help="bead id to find notes-writes for")
    parser.add_argument("--notes", help="notes snapshot file")
    parser.add_argument("--out", help="where pairs.jsonl goes")
    parser.add_argument("--transcripts", action="append", default=None,
                        help="a .jsonl file or a directory of them "
                             "(repeatable; default: matching project dirs)")
    parser.add_argument("--selftest", action="store_true",
                        help="run the built-in selftest and exit")
    return parser


if __name__ == "__main__":
    parser = _build_parser()
    args = parser.parse_args()
    if args.selftest:
        sys.exit(_selftest())
    missing = []
    if not args.bead:
        missing.append("--bead")
    if not args.notes:
        missing.append("--notes")
    if not args.out:
        missing.append("--out")
    if missing:
        parser.error("the following arguments are required: %s"
                     % ", ".join(missing))
    sys.exit(run(args))
