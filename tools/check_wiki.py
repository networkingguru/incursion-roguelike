#!/usr/bin/env python3
# gate: live
# With no argument it runs ./incursion-headless -wikihelp, so it needs the built binary.
"""Validate the wiki help export (inc-k2le, spec docs/specs/2026-10-04-wiki-help-spec.md).

Run:
    python3 tools/check_wiki.py <dir>     # check an already-generated directory
    python3 tools/check_wiki.py           # generate into a temp dir and check it
    python3 tools/check_wiki.py --selftest

Faults (exit 1, one line each):
  * an index page lists no entries;
  * a [[link]] names a page with no file (dangling link);
  * an entry page has an empty body;
  * Home.md or _Sidebar.md is missing;
  * a byte sequence that is not valid UTF-8;
  * a raw colour tag (a run of digits between angle brackets);
  * unbalanced <b> / </b> on a line.

The page-name -> file-name mapping is the C++ WikiFileName in src/Help.cpp:
spaces become '-', characters outside [A-Za-z0-9()'+,._-] are dropped.
"""
import os
import re
import subprocess
import sys
import tempfile
import shutil

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Spec section 1: the twelve index page names.
INDEX_PAGES = [
    "Races", "Classes", "Gods", "Domains", "Feats", "Skills",
    "Arcane Spells", "Divine Spells", "Druid Spells", "Other Spells",
    "Powers", "Spell Index",
]

LINK_RE = re.compile(r"\[\[([^\]]+)\]\]")
COLOUR_TAG_RE = re.compile(r"<[0-9]+>")


def wiki_file(page):
    """The file name WikiFileName builds for a page name."""
    out = []
    for c in page:
        if c == " ":
            out.append("-")
        elif ("A" <= c <= "Z") or ("a" <= c <= "z") or ("0" <= c <= "9") \
                or c in "()'+,._-":
            out.append(c)
    return "".join(out) + ".md"


def check_dir(directory):
    """Return a list of fault strings for a generated wiki directory."""
    faults = []
    try:
        names = sorted(os.listdir(directory))
    except OSError as exc:
        return ["cannot read %s: %s" % (directory, exc)]
    files = [n for n in names if n.endswith(".md")]

    if "Home.md" not in files:
        faults.append("Home.md is missing")
    if "_Sidebar.md" not in files:
        faults.append("_Sidebar.md is missing")

    contents = {}
    for name in files:
        path = os.path.join(directory, name)
        try:
            raw = open(path, "rb").read()
        except OSError as exc:
            faults.append("%s: cannot read: %s" % (name, exc))
            continue
        contents[name] = raw
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            faults.append("%s: not valid UTF-8 (%s)" % (name, exc))
            continue
        if COLOUR_TAG_RE.search(text):
            faults.append("%s: raw colour tag" % name)
        for lineno, line in enumerate(text.split("\n"), 1):
            if line.count("<b>") != line.count("</b>"):
                faults.append("%s:%d: unbalanced <b>/</b>"
                              % (name, lineno))
        if text.strip() == "":
            faults.append("%s: empty body" % name)

    present = set(files)
    for name in INDEX_PAGES:
        fname = wiki_file(name)
        if fname not in present:
            continue
        links = LINK_RE.findall(contents.get(fname, b"").decode("utf-8", "replace"))
        if not links:
            faults.append("%s: index page lists no entries" % name)

    # Every link, anywhere, must resolve to a file.
    for name in files:
        text = contents.get(name, b"").decode("utf-8", "replace")
        for target in LINK_RE.findall(text):
            if wiki_file(target) not in present:
                faults.append("%s: [[%s]] names a page with no file"
                              % (name, target))

    return faults


def selftest():
    """Build a good fixture and four broken ones; assert pass/fail."""
    base = tempfile.mkdtemp(prefix="check_wiki_")
    try:
        good = os.path.join(base, "good")
        os.makedirs(good)
        # An index page (needs an entry), its entry page, Home and the sidebar.
        with open(os.path.join(good, "Races.md"), "w") as fh:
            fh.write("# Races\n* [[Human]]\n")
        with open(os.path.join(good, "Human.md"), "w") as fh:
            fh.write("A human.\n")
        with open(os.path.join(good, "Home.md"), "w") as fh:
            fh.write("# Home\n")
        with open(os.path.join(good, "_Sidebar.md"), "w") as fh:
            fh.write("* [[Home]]\n")

        failures = []
        faults = check_dir(good)
        if faults:
            failures.append("good fixture unexpectedly failed: %s" % faults)

        def broken(name, mutate):
            path = os.path.join(base, name)
            shutil.copytree(good, path)
            mutate(path)
            result = check_dir(path)
            if not result:
                failures.append("%s fixture unexpectedly passed" % name)

        def empty_index(path):
            with open(os.path.join(path, "Races.md"), "w") as fh:
                fh.write("# Races\n")

        def dangling_link(path):
            with open(os.path.join(path, "Races.md"), "w") as fh:
                fh.write("# Races\n* [[Human]]\n* [[Ghost]]\n")

        def empty_page(path):
            with open(os.path.join(path, "Human.md"), "w") as fh:
                fh.write("")

        def missing_sidebar(path):
            os.remove(os.path.join(path, "_Sidebar.md"))

        def bad_utf8(path):
            with open(os.path.join(path, "Human.md"), "wb") as fh:
                fh.write(b"\xff\xfe not utf8")

        def colour_tag(path):
            with open(os.path.join(path, "Human.md"), "w") as fh:
                fh.write("a <7>colour\n")

        def unbalanced_bold(path):
            with open(os.path.join(path, "Human.md"), "w") as fh:
                fh.write("a <b>bold line\n")

        broken("empty_index", empty_index)
        broken("dangling_link", dangling_link)
        broken("empty_page", empty_page)
        broken("missing_sidebar", missing_sidebar)
        broken("bad_utf8", bad_utf8)
        broken("colour_tag", colour_tag)
        broken("unbalanced_bold", unbalanced_bold)

        if failures:
            for line in failures:
                print(line)
            return 1
        print("check_wiki: selftest PASS")
        return 0
    finally:
        shutil.rmtree(base, ignore_errors=True)


def generate_and_check():
    """Run the headless wiki generator into a temp dir, then check it."""
    binary = os.path.join(REPO, "incursion-headless")
    if not os.path.exists(binary):
        print("check_wiki: %s not found" % binary)
        return 1
    out = tempfile.mkdtemp(prefix="check_wiki_gen_")
    try:
        proc = subprocess.run([binary, "-wikihelp", out],
                              cwd=REPO, capture_output=True)
        if proc.returncode != 0:
            sys.stderr.write(proc.stderr.decode("utf-8", "replace"))
            print("check_wiki: generator exited %d" % proc.returncode)
            return 1
        faults = check_dir(out)
        if faults:
            for line in faults:
                print(line)
            return 1
        print("check_wiki: PASS")
        return 0
    finally:
        shutil.rmtree(out, ignore_errors=True)


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) == 1:
        return generate_and_check()
    if len(argv) == 2:
        faults = check_dir(argv[1])
        if faults:
            for line in faults:
                print(line)
            return 1
        print("check_wiki: PASS")
        return 0
    sys.stderr.write("usage: check_wiki.py [<dir> | --selftest]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
