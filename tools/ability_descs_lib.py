"""Parsing and checking logic for tools/check_ability_descs.sh (inc-nbjf).

No C++ build or execution: every function here reads plain text -- src/
Tables.cpp for the two name/description tables, tools/ability_descs.live and
tools/ability_descs.exempt for the two hand-maintained lists, and lib/*.irh
for the "granted to a player" derivation the spec's Scope section gives.

Kept import-only and side-effect-free (module-level code just defines things)
so tools/check_ability_descs.sh's --selftest can import it, point every
function at a temp-directory COPY of the files it would otherwise read from
the real tree, and prove each of the four assertions can fail without ever
writing to a tracked file.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The nine player-facing lib/ files the spec's Scope section names for the
# "granted to a player" derivation.
GRANT_FILES = [
    "lib/classes.irh", "lib/prestige.irh", "lib/races.irh",
    "lib/subraces.irh", "lib/domains.irh", "lib/religion.irh",
    "lib/pspells.irh", "lib/wspells.irh", "lib/abilities.irh",
]

CA_RE = r"CA_[A-Z_]+"
GRANT_LINE_RE = re.compile(r"Ability\[" + CA_RE + r"|ABILITY\(" + CA_RE)
COMMENT_LEADER_RE = re.compile(r"^\s*(//|/\*|\*)")


class TableError(Exception):
    """A source table could not be parsed. Always fatal -- see run_all()."""


def _strip_comments(text):
    """Remove C++ /* */ and // comments. DOTALL so a multi-line block goes."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    text = re.sub(r"//[^\n]*", "", text)
    return text


def _unescape(raw):
    """Undo the handful of C string escapes this codebase's prose ever uses."""
    out = []
    i = 0
    mapping = {'"': '"', "\\": "\\", "n": "\n", "t": "\t", "'": "'"}
    while i < len(raw):
        c = raw[i]
        if c == "\\" and i + 1 < len(raw):
            out.append(mapping.get(raw[i + 1], raw[i + 1]))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def _extract_block(text, start_re, end_re, label):
    start = re.search(start_re, text)
    if not start:
        raise TableError(f"could not find the start of {label}")
    end = re.search(end_re, text[start.end():])
    if not end:
        raise TableError(f"could not find the terminator row of {label}")
    return text[start.end():start.end() + end.start()]


def parse_class_abilities(path):
    """id -> display name, for every UNCOMMENTED row of ClassAbilities[]."""
    text = Path(path).read_text()
    block = _extract_block(
        text,
        r"TextVal\s+ClassAbilities\[\]\s*=\s*\{",
        r"\{\s*0\s*,\s*NULL\s*\}",
        "ClassAbilities[]",
    )
    block = _strip_comments(block)
    out = {}
    for m in re.finditer(r"\{\s*(CA_[A-Z_]+)\s*,\s*\"((?:\\.|[^\"\\])*)\"\s*\}", block):
        out[m.group(1)] = _unescape(m.group(2))
    if not out:
        raise TableError("ClassAbilities[] parsed to zero rows")
    return out


def parse_abil_info(path):
    """id -> (name, description), for every row of AbilInfo[].

    The description is every quoted string literal between the name and the
    closing brace, concatenated -- C adjacent-string-literal concatenation,
    which is how the real table wraps Devouring's paragraph across lines.
    """
    text = Path(path).read_text()
    block = _extract_block(
        text,
        r"struct\s+AbilityInfoStruct\s+AbilInfo\[\]\s*=\s*\{",
        r"\{\s*0\s*,\s*NULL\s*,\s*NULL\s*\}",
        "AbilInfo[]",
    )
    block = _strip_comments(block)
    out = {}
    entry_re = re.compile(
        r"\{\s*(CA_[A-Z_]+)\s*,\s*\"((?:\\.|[^\"\\])*)\"\s*,"
        r"\s*((?:\"(?:\\.|[^\"\\])*\"\s*)+)\}",
        re.DOTALL,
    )
    for m in entry_re.finditer(block):
        ca, name, desc_blob = m.group(1), m.group(2), m.group(3)
        parts = re.findall(r"\"((?:\\.|[^\"\\])*)\"", desc_blob)
        desc = "".join(_unescape(p) for p in parts)
        out[ca] = (_unescape(name), desc)
    if not out:
        raise TableError("AbilInfo[] parsed to zero rows")
    return out


def read_name_list(path):
    """The bare CA_ names in a tools/ability_descs.{live,exempt} file.

    Format shared by both files: one name per line, first token only (so a
    trailing inline comment such as "CA_X  # note" still yields CA_X), a line
    whose first non-space character is '#' is a full-line comment, blank
    lines are ignored.
    """
    names = set()
    for line in Path(path).read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        tok = stripped.split()[0]
        if re.fullmatch(r"CA_[A-Z_]+", tok):
            names.add(tok)
    if not names:
        raise TableError(f"{path} contains no CA_ names")
    return names


def granted_in_lib(root=ROOT):
    """Every CA_ granted to a player, from uncommented lines of GRANT_FILES.

    Mirrors the spec's first derivation command exactly: grep the nine
    player-facing lib files for Ability[CA_X] or ABILITY(CA_X, drop any line
    whose first non-space characters open a comment, then collect the CA_
    names that appear on what is left.
    """
    root = Path(root)
    found = set()
    missing = []
    for rel in GRANT_FILES:
        p = root / rel
        if not p.is_file():
            missing.append(rel)
            continue
        for line in p.read_text(errors="replace").splitlines():
            if COMMENT_LEADER_RE.match(line):
                continue
            if not GRANT_LINE_RE.search(line):
                continue
            found.update(re.findall(CA_RE, line))
    if missing:
        raise TableError(f"missing lib file(s) for the grant derivation: {missing}")
    if not found:
        raise TableError("the grant derivation over lib/ found nothing")
    return found


def run_all(tables_path, live_path, exempt_path, lib_root=ROOT):
    """Run all four assertions. Returns (ok, list-of-failure-lines)."""
    fails = []

    try:
        class_abilities = parse_class_abilities(tables_path)
    except TableError as e:
        return False, [f"FAIL: could not parse ClassAbilities[] in {tables_path}: {e}"]

    try:
        abil_info = parse_abil_info(tables_path)
    except TableError as e:
        return False, [f"FAIL: could not parse AbilInfo[] in {tables_path}: {e}"]

    try:
        live = read_name_list(live_path)
    except TableError as e:
        return False, [f"FAIL: could not read {live_path}: {e}"]

    try:
        exempt = read_name_list(exempt_path)
    except TableError as e:
        return False, [f"FAIL: could not read {exempt_path}: {e}"]

    try:
        granted = granted_in_lib(lib_root)
    except TableError as e:
        return False, [f"FAIL: could not derive the granted-in-lib set: {e}"]

    # 1. Every live ability has an AbilInfo row with a non-empty description.
    for ca in sorted(live):
        if ca not in abil_info:
            fails.append(f"FAIL[1]: {ca} is in {Path(live_path).name} but has no AbilInfo row")
        elif not abil_info[ca][1].strip():
            fails.append(f"FAIL[1]: {ca} has an AbilInfo row with an empty description")

    # 2. Every AbilInfo row's name matches its ClassAbilities name exactly.
    for ca, (name, _desc) in sorted(abil_info.items()):
        if ca in class_abilities and name != class_abilities[ca]:
            fails.append(
                f"FAIL[2]: {ca} AbilInfo name {name!r} != ClassAbilities name "
                f"{class_abilities[ca]!r}"
            )

    # 3. Every AbilInfo row names an ability that exists in ClassAbilities.
    for ca in sorted(abil_info):
        if ca not in class_abilities:
            fails.append(f"FAIL[3]: {ca} has an AbilInfo row but no ClassAbilities row")

    # 4. Every ability granted in lib/ is classified as live or exempt.
    for ca in sorted(granted):
        if ca not in live and ca not in exempt:
            fails.append(
                f"FAIL[4]: {ca} is granted in lib/ and is in neither "
                f"{Path(live_path).name} nor {Path(exempt_path).name}"
            )

    return (len(fails) == 0), fails
