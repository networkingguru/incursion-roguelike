#!/usr/bin/env python3
# gate: cheap
# gate-fast: static, reads the files of inc/ and src/ that hold a family mark, well under 1 s
"""Do two #define names in one explicitly marked family share one value?

WHY THIS EXISTS. Two worktrees can each add a stati (status effect) define
with the next free number, and both merge cleanly because the lines differ.
The game then treats two effects as one. Spec: docs/superpowers/specs/
2026-10-31-no-shared-tail-design.md section 4.5 (bead inc-mhn1w). The old
check guessed each define's family from its position or name prefix. This
one reads the family from comment marks in inc/Defines.h (bead inc-60xq9).
Since inc-cjos0 phase 5a each mark also carries a CLASS: whether a value of
the family reaches a save or another file on disk (spec docs/superpowers/specs/
2026-11-07-names-in-the-file-design.md section 6).

RULE FOR IMPLEMENTERS. A new #define goes inside its family's marks; a
deliberate second name for an existing value carries `/* alias of <NAME> */`; a
value that is not a code (a size, a cap, a probe-local index) goes in a no-family
block, and rule 4 below governs what may go there.

MARKS (whitespace is free). Own-line block marks use `//` (`/* */` also works).
A TRAILING mark on a #define line MAY use `/* */` or `//`.
  // family: <name> <class>     opens a block; `// end family: <name>` closes it
  // family: <n1> <class1>, <n2> <class2>
                                one block whose defines join several families,
                                each with its OWN class (a comma ends a class);
                                the end line names the families only
  // no-family                  opens a block never compared with anything;
                                `// end no-family` closes it
  alias of <NAME>               on a define line (trailing, /* */) or the line just
                                above it: skipped. NAME MUST be a define in a
                                shared family with the same value, else FAIL.
  known collision: <bead>       same placement: reported KNOWN with the bead.
                                Mark every member of a colliding group but one.
  not a code: <reason>          same placement: a no-family define that starts with
                                a family's prefix (rule 4) is allowed. The reason
                                MUST be non-empty prose.
CLASS (one per family on every open mark; the end mark carries none):
  internal                                  no value of the family reaches a file
  stored <ordinal|bits|enum> <u8|i8|u16|i16|u32|i32>
                                            some value reaches a save,
                                            Options.Dat or another file; the
                                            shape says how a new value is chosen
                                            (ordinal: next number; bits: next
                                            free bit; enum: an enumerator list),
                                            the width is that of the storage
  sentinel <NAME>      (stored only, repeatable) NAME is a define or enumerator
                                            of the family that sizes memory only,
                                            so it is not a stored value. A
                                            sentinel that sizes a stored array
                                            carries NO sentinel clause.
  grows <NAME>         (stored only, repeatable) NAME is a define or enumerator
                                            of the family that sizes a saved
                                            array (spec 6.1). It may grow and
                                            must never shrink:
                                            tools/check_stored_values.py
                                            refuses a tree value below the
                                            base's and accepts one above, and a
                                            new member may take the value the
                                            limit had on the base.
                                            tools/move_branch_values.py raises
                                            it when it moves a value past it.
  bound <NAME>         (stored ordinal or enum only, once) NAME is a define or
                                            enumerator of the family that is the
                                            EXCLUSIVE upper limit of its values
                                            because it sizes the array they index
                                            (OPT_LAST sizes Options[], so no option
                                            may have a value >= OPT_LAST). NAME is
                                            a stored value itself, never rewritten:
                                            tools/check_stored_values.py refuses a
                                            member value >= it, and
                                            tools/move_branch_values.py takes a
                                            free value below it or refuses.
  block <N>            (stored ordinal or enum only, once) N is a positive decimal
                                            integer. The family's values live in
                                            blocks of N, and a value that moves
                                            stays in its own block (family opt:
                                            the OPC_ category decides where an
                                            option shows and whether a character
                                            save keeps it). tools/move_branch_values.py
                                            takes the lowest free value of the
                                            old value's block or refuses
                                            (inc-cjos0).
  val-of <STATI>[+<STATI>]  (stored only) Status.val of each named status holds a member of
                                            this family (BLINDNESS holds a BLIND_ value).
  mag-of <STATI>[+<STATI>]  (stored only) the same for Status.mag. Each name MUST be a member
                                            of family stati, and one (status, slot) MUST
                                            have one family; either breach exits 1. A comma
                                            ends a class, so `+` joins the names. The
                                            observer and the planter read these (inc-cjos0).
  field-of <Scope.Field>[+<Scope.Field>]  (stored only) the saved scalar member(s) whose whole value is a member of this
                                            family. A name is the observer's scope path with every `#N` dropped, a dot,
                                            then the field name (Creature.LastMoveDir, Thing.Flags, Envelope.Type for the
                                            record type byte). index-of <Scope.Array>: the array INDEX is the family value
                                            (IntStudy). elem-of <Scope.Array>: each element holds the value (Qualities,
                                            godFlags, Spells, MMArray). One field MUST have one family; two families may
                                            share it only when each says `shares <other>` (wq and aq share Qualities).
                                            The observer prints the name, the planter's `set` verb refuses a field no family
                                            claims (inc-cjos0 9f-pre P3).
  glyph-of <Scope.Field>[+...]  (stored only, on glyph_word) the saved field, or each element of the saved array, holds
                                            a whole glyph word: id in bits 0-11 (family glyph), fore color in bits 12-15
                                            and back color in bits 16-19 (family colour), bits 20-31 unused. The observer
                                            decodes it `(GLYPH_X/fore=RED/back=BLACK)` and `/hi=0x..` for a bit above 19.
  word-of <Scope.Blob>@<byte>[+...]  (stored only) a saved byte blob holds one 32-bit little-endian word of this family
                                            at that byte offset (the Hostility fields inside Target t_why_data). The
                                            observer prints it as its own line, only for a why type that carries one.
  at-of <Scope.Array>[<NAME>][+...]  (stored only) the element of a saved array at the index NAME holds a member of this
                                            family (Player.Options[OPT_DIFFICULTY] holds a DIFF_ value). NAME MUST be a member
                                            of the family another family's `index-of` gives that same array (family opt), and
                                            one (array, NAME) MUST have one family. The observer prints the value's name
                                            beside the element and the planter's `option` verb reads it (inc-cjos0 9f-pre P5b).
A mark with no class, a bad class, a bad shape or a bad width exits 1 naming
the line. Every block of one family MUST carry the same class, shape and width.
A `sentinel`, `grows` or `bound` clause MUST name a member of the same family.
A name MUST NOT carry both `sentinel` and `grows`.
An `enum` family holds enumerators only, and any other shape holds defines only.
An enumerator takes the value the compiler gives it (previous + 1, or its
explicit `= expr`, first one 0). Only enums wholly inside a family block count.
Blocks do not nest. A family may have several blocks; they form one family.
An open with no close, a close with no open, a mismatched name, or nesting
exits 2 UNMEASURED naming the line. It never passes.

RULES.
1. Every integer #define of inc/Defines.h (the file named by --defines, or the
   default) sits inside a family block or a no-family block. A define in
   neither FAILS, naming the define and its line. Other files that hold marks
   (inc/Target.h, inc/RComp.h, inc/Base.h) are read only inside their blocks.
1b. Rule 5 (inc-cjos0 F06): in every file of inc/ and src/ an integer constant
   outside every block FAILS, naming file, line and name, unless
   tools/define_baseline.txt lists its file and name. Forms: `#define NAME
   <integer expr>` (Defines.h defines are rule 1), enum members, and scalar
   integer `const`/`constexpr`/`static const` variables with an `=` at namespace
   or class scope. A function-local const is NOT listed: the brace stack tells
   it apart reliably (a block is class scope when its head holds class, struct,
   union, namespace or extern and no `(`; `#if 0` text is skipped; an unbalanced
   file exits 2), and the local ones are runtime values, not codes. A define
   counts when its body has a number or char literal, or is one earlier integer
   define, and holds no string, call, `->`, `::`, `;{}[].,=` or sizeof. The
   baseline only shrinks: the check FAILS when it gains an entry against
   `master:tools/define_baseline.txt` (skipped when master lacks the file or the
   tree has no .git). Nothing regenerates it. Delete a line when a constant goes.
2. In one family, two names with one value FAIL, unless a name is an alias
   or a known collision.
3. The same value in two different families passes.
4. A no-family block is never compared with a family, and two rules guard it
   (bead inc-x39wn). (a) PREFIX: a define or enumerator in a no-family block FAILS,
   naming file, line and name, when its name starts with the prefix of any family
   and its line (trailing comment) or the line just above carries no `not a code:
   <reason>`. A family's prefix is the leading `<TOKEN>_` (letters and digits, then
   one underscore) that EVERY member of the family shares; a family whose members
   share no such prefix has none; a prefix that two or more families use is still a
   prefix. (b) BASELINE: every no-family define MUST be listed in
   tools/nofamily_baseline.txt (columns file, name, form `define` or `enum`, tab
   separated, key file plus name). The baseline only shrinks, by the code of rule 5
   (gain_problems): the check FAILS when it gains an entry against
   `master:tools/nofamily_baseline.txt` (skipped when master lacks the file or the
   tree has no .git). So a new no-family define needs one baseline line, and the
   branch that adds it FAILS until Brian lets the gain through; put a define in its
   family instead. Nothing regenerates the file. Delete a line when a define goes.
   The baseline applies to the full run only, as rule 5 does (not to --defines).
4b. A comment on a #define line, or on the comment-only line just above it, that
   holds the word `renumbered` (any case) FAILS, naming file:line: a value moves
   only through tools/move_branch_values.py, never by hand. It applies to every
   file the run reads, and with --defines to that file.

WHAT COUNTS AS A CONSTANT. Every integer `#define NAME <expr>`, comments
removed (`/* */` across lines, and `//`). Values are evaluated, including
expressions over earlier defines, parentheses, + - * / << >> | & ^ ~, hex,
octal, decimal and char literals. The evaluator walks a whitelisted `ast`;
it never calls eval. #if/#ifdef lines are not interpreted. NOT constants, so
rule 1 ignores them: an include guard or any define with an empty body, a
function-like macro `NAME(x)` (but one inside a block of a STORED family FAILS,
naming file:line and family: the inventory cannot see its value, so put it in a
no-family block), a body holding a string literal, a body
holding `; { } [ ] . , =` or `this`/`sizeof`, a body of two or more bare
words (a type such as `unsigned char`), and a single bare word that names no
earlier integer define (a type alias). A single bare word that names an
earlier integer define is a constant. An integer-looking expression that
cannot be evaluated exits 2 naming the line.

Usage: tools/check_define_dups.py [--defines FILE] [--selftest]
       --defines FILE reads that one file only (no rule 5, no no-family baseline); without it the check reads
       inc/Defines.h and every other file of inc/ and src/ that holds a mark, and
       applies rule 5 to every file of inc/ and src/.
Exit:  0 clean   1 unmarked define, duplicate, bad alias, or bad class
       2 could not measure (bad marks, unevaluable expression)

IMPORT. load_families(defines=None) returns (families, problems). families maps
a family name to {"class": "internal"|"stored", "shape": str|None, "width":
str|None, "sentinels": [NAME], "bounds": [NAME], "grows": [NAME], "block": int|None,
"val_of": [STATI], "mag_of": [STATI], "field_of"/"index_of"/"elem_of": [Scope.Field], "at_of": [Scope.Array[NAME]], "shares": [family], "members": [(name, value, file, line)]}.
problems is the list of FAIL lines (empty when the marks are sound).
tools/check_stored_values.py imports it.

# fact: the define values -- read from the text of inc/ and src/ files; no game run, no seed
# fact: each define's family and class -- read from the marks in those same texts; no randomness
# fact: which statuses a family's val or mag holds -- the val-of and mag-of attributes of those same marks, checked against family stati; no game run, no seed
# fact: which names the saved fields have -- the string literals of the FIELD_* and V1EmbedBegin* macros and ARCHIVE_CLASS blocks in inc/ and src/; no game run, no seed
# fact: which saved field a family fills -- the field-of, index-of and elem-of attributes of those same marks; no game run, no seed
# fact: which names share a value -- computed from those values and marks
# fact: enumerator values -- counted from the enum text as the compiler counts; no build, no seed
# fact: constants outside every block -- read from the text of inc/ and src/ against tools/define_baseline.txt; no game run, no seed
# fact: the base baseline -- `git show master:tools/define_baseline.txt`, a committed ref, not a clock or a random value
# fact: the no-family members -- read from the text of inc/ and src/ against tools/nofamily_baseline.txt; no game run, no seed
# fact: the base no-family baseline -- `git show master:tools/nofamily_baseline.txt`, a committed ref, not a clock or a random value
# fact: a family's prefix and a `not a code` or `renumbered` comment -- read from the member names and comments of the same text; no game run, no seed
"""
import ast
import bisect
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEF_DEFAULT = os.path.join(ROOT, "inc", "Defines.h")


class Unmeasurable(Exception):
    pass


def strip_comments(text):
    """Remove comments, keep newlines so line numbers survive."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':  # string literal: copy through
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1]); i = j + 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join("\n" for ch in text[i:j] if ch == "\n") or " ")
            i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(c); i += 1
    return "".join(out)


def logical_lines(text):
    """Yield (first line number, text) joining backslash continuations."""
    buf, start = "", 0
    for no, line in enumerate(text.split("\n"), 1):
        if not buf:
            start = no
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        yield start, buf + line
        buf = ""
    if buf:
        yield start, buf


TOKEN = re.compile(r"\s*(0[xX][0-9a-fA-F]+[uUlL]*|\d+[uUlL]*|'(?:\\.|[^'\\])'"
                   r"|[A-Za-z_]\w*|<<|>>|[-+*/&|^~()%]|\S)")


STMT_TOKENS = set(";{}[].,=")


def tokens(body):
    pos, out = 0, []
    body = body.strip()
    while pos < len(body):
        m = TOKEN.match(body, pos)
        out.append(m.group(1)); pos = m.end()
    return out


def to_python(toks, lineno):
    py = []
    for t in toks:
        if t[0].isdigit():
            t = t.rstrip("uUlL")
            if t[:2].lower() == "0x":
                py.append(str(int(t, 16)))
            elif len(t) > 1 and t[0] == "0":
                try:
                    py.append(str(int(t, 8)))
                except ValueError:
                    raise Unmeasurable("line %d: bad octal literal %s" % (lineno, t))
            else:
                py.append(t)
        elif t[0] == "'":
            ch = ast.literal_eval(t) if t[1] != "\\" else ast.literal_eval(t)
            py.append(str(ord(ch)))
        else:
            py.append(t)
    return " ".join(py)


OK_BIN = {ast.Add: lambda a, b: a + b, ast.Sub: lambda a, b: a - b,
          ast.Mult: lambda a, b: a * b, ast.LShift: lambda a, b: a << b,
          ast.RShift: lambda a, b: a >> b, ast.BitOr: lambda a, b: a | b,
          ast.BitAnd: lambda a, b: a & b, ast.BitXor: lambda a, b: a ^ b,
          ast.Div: lambda a, b: int(a / b), ast.Mod: lambda a, b: a % b}
OK_UN = {ast.USub: lambda a: -a, ast.UAdd: lambda a: a, ast.Invert: lambda a: ~a}


def evaluate(src, env, lineno, name):
    def ev(node):
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.Name) and node.id in env:
            return env[node.id]
        if isinstance(node, ast.BinOp) and type(node.op) in OK_BIN:
            return OK_BIN[type(node.op)](ev(node.left), ev(node.right))
        if isinstance(node, ast.UnaryOp) and type(node.op) in OK_UN:
            return OK_UN[type(node.op)](ev(node.operand))
        what = node.id if isinstance(node, ast.Name) else type(node).__name__
        raise Unmeasurable("line %d: %s: cannot evaluate (%s) in: %s"
                           % (lineno, name, what, src))
    try:
        tree = ast.parse(src, mode="eval")
    except SyntaxError:
        raise Unmeasurable("line %d: %s: not a parsable integer expression: %s"
                           % (lineno, name, src))
    try:
        return ev(tree.body)
    except ZeroDivisionError:
        raise Unmeasurable("line %d: %s: division by zero" % (lineno, name))


MARK = re.compile(r"^\s*(?://|/\*)\s*(end\s+)?(?:(family)\s*:\s*(.*?)|(no-family))"
                  r"\s*(?:\*/)?\s*$")
ALIAS = re.compile(r"(?://|/\*).*?\balias\s+of\s+([A-Za-z_]\w*)")
KNOWN = re.compile(r"(?://|/\*).*?\bknown\s+collision\s*:\s*([A-Za-z0-9_.-]+)")
COMMENT_ONLY = re.compile(r"^\s*(?://|/\*)")
FAM_NAME = re.compile(r"[A-Za-z_][\w-]*")
IDENT = re.compile(r"[A-Za-z_]\w*")
KEY_LIST = re.compile(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*(?:@\d+)?(?:\+[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*(?:@\d+)?)*")
AT_ONE = r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\[[A-Za-z_]\w*\]"
AT_LIST = re.compile(AT_ONE + r"(?:\+" + AT_ONE + r")*")
FAM_LIST = re.compile(r"[A-Za-z_][\w-]*(?:\+[A-Za-z_][\w-]*)*")
IDENT_LIST = re.compile(r"[A-Za-z_]\w*(?:\+[A-Za-z_]\w*)*")   # `+` joins names: a comma ends a class
NOT_CODE = re.compile(r"(?://|/\*).*?\bnot\s+a\s+code\s*:\s*(.*?)\s*(?:\*/)?\s*$", re.I)
RENUMBERED = re.compile(r"(?://|/\*).*\brenumbered\b", re.I)
FUNC_DEFINE = re.compile(r"\s*#\s*define\s+([A-Za-z_]\w*)\(")
SHAPES = ("ordinal", "bits", "enum")
WIDTHS = ("u8", "i8", "u16", "i16", "u32", "i32")
HOW = ("Fix: write '// family: %s internal' or '// family: %s stored "
       "<ordinal|bits|enum> <u8|i8|u16|i16|u32|i32>'.")


def parse_class(fam, rest, no):
    """rest: the tokens after the family name. Return (spec, problem). spec is
    {"class","shape","width","sentinels"}; problem is a message or None."""
    spec = {"class": None, "shape": None, "width": None, "sentinels": [], "bounds": [],
            "grows": [], "block": None, "val_of": [], "mag_of": [], "field_of": [], "index_of": [],
            "elem_of": [], "glyph_of": [], "word_of": [], "at_of": [], "shares": []}
    if not rest:
        return spec, ("line %d: family %s has no class. " % (no, fam)) + HOW % (fam, fam)
    if rest[0] == "internal":
        if len(rest) > 1:
            return spec, ("line %d: family %s is internal, so '%s' is not allowed "
                          "after it (a sentinel belongs to a stored family)"
                          % (no, fam, " ".join(rest[1:])))
        spec["class"] = "internal"
        return spec, None
    if rest[0] != "stored":
        return spec, ("line %d: family %s has a bad class '%s'. " % (no, fam, rest[0])
                      ) + HOW % (fam, fam)
    if len(rest) < 2 or rest[1] not in SHAPES:
        return spec, ("line %d: family %s has a bad shape '%s' (use ordinal, bits "
                      "or enum)" % (no, fam, rest[1] if len(rest) > 1 else ""))
    if len(rest) < 3 or rest[2] not in WIDTHS:
        return spec, ("line %d: family %s has a bad width '%s' (use u8, i8, u16, i16, "
                      "u32 or i32)" % (no, fam, rest[2] if len(rest) > 2 else ""))
    tail = rest[3:]
    while tail:
        if tail[0] in ("val-of", "mag-of") and len(tail) >= 2 and IDENT_LIST.fullmatch(tail[1]):
            spec[tail[0].replace("-", "_")] += tail[1].split("+")
            tail = tail[2:]
            continue
        if tail[0] in ("field-of", "index-of", "elem-of", "glyph-of", "word-of") and len(tail) >= 2 and KEY_LIST.fullmatch(tail[1]) \
                and all(("@" in k) == (tail[0] == "word-of") for k in tail[1].split("+")):   # only word-of takes a byte offset, and it must
            spec[tail[0].replace("-", "_")] += tail[1].split("+")
            tail = tail[2:]
            continue
        if tail[0] == "at-of" and len(tail) >= 2 and AT_LIST.fullmatch(tail[1]):
            spec["at_of"] += tail[1].split("+")
            tail = tail[2:]
            continue
        if tail[0] == "shares" and len(tail) >= 2 and FAM_LIST.fullmatch(tail[1]):
            spec["shares"] += tail[1].split("+")
            tail = tail[2:]
            continue
        if tail[0] == "block":
            if len(tail) < 2 or not re.fullmatch(r"[1-9][0-9]*", tail[1]):
                return spec, ("line %d: family %s says 'block %s' but a block size is a "
                              "positive decimal integer" % (no, fam, tail[1] if len(tail) > 1 else ""))
            if rest[1] == "bits":
                return spec, ("line %d: family %s is a bits family, so 'block %s' has no "
                              "meaning (use shape ordinal or enum)" % (no, fam, tail[1]))
            if spec["block"] is not None:
                return spec, ("line %d: family %s names two block sizes (%d and %s); a family has one"
                              % (no, fam, spec["block"], tail[1]))
            spec["block"] = int(tail[1])
            tail = tail[2:]
            continue
        if tail[0] not in ("sentinel", "bound", "grows") or len(tail) < 2 \
                or not IDENT.fullmatch(tail[1]):
            return spec, ("line %d: family %s has a bad word '%s' after its width "
                          "(only 'sentinel <NAME>', 'grows <NAME>', 'bound <NAME>', "
                          "'block <N>', 'val-of <STATI>[+<STATI>]', 'mag-of <STATI>[+<STATI>]', "
                          "'field-of|index-of|elem-of|glyph-of|word-of <Scope.Field>[+...]', 'at-of <Scope.Array>[<NAME>][+...]' or 'shares <family>' "
                          "may follow)" % (no, fam, " ".join(tail)))
        if tail[0] == "bound" and rest[1] == "bits":
            return spec, ("line %d: family %s is a bits family, so 'bound %s' has no "
                          "meaning (use shape ordinal or enum)" % (no, fam, tail[1]))
        spec[{"sentinel": "sentinels", "bound": "bounds", "grows": "grows"}[tail[0]]].append(tail[1])
        tail = tail[2:]
    spec.update({"class": "stored", "shape": rest[1], "width": rest[2]})
    return spec, None


def read_marks(raw_lines):
    """Return (events, notes, specs, bad). events: sorted (lineno, 'open'|
    'close', kind, tuple of family names). notes: lineno of a define ->
    (alias, known). specs: lineno of an open mark -> {family: spec}. bad: list
    of (lineno, message) for classes that do not parse (exit 1)."""
    events, open_at, specs, bad = [], None, {}, []
    for no, line in enumerate(raw_lines, 1):
        m = MARK.match(line)
        if not m:
            continue
        closing = bool(m.group(1))
        if m.group(4):
            kind, fams = "no-family", ()
        else:
            kind = "family"
            entries = [x.strip().split() for x in m.group(3).split(",")]
            names = [e[0] if e else "" for e in entries]
            if not names or not all(FAM_NAME.fullmatch(x) for x in names):
                raise Unmeasurable("line %d: bad family name list: %s" % (no, line.strip()))
            if closing:
                if any(len(e) != 1 for e in entries):
                    raise Unmeasurable("line %d: an end mark names families only, "
                                       "no class: %s" % (no, line.strip()))
            else:
                specs[no] = {}
                for e in entries:
                    spec, problem = parse_class(e[0], e[1:], no)
                    specs[no][e[0]] = spec
                    if problem:
                        bad.append((no, problem))
            fams = tuple(sorted(names))
        if not closing:
            if open_at:
                raise Unmeasurable("line %d: a block opens inside the block opened at "
                                   "line %d (blocks do not nest)" % (no, open_at[0]))
            open_at = (no, kind, fams)
            events.append((no, "open", kind, fams))
        else:
            if not open_at:
                raise Unmeasurable("line %d: close mark with no open block" % no)
            if (kind, fams) != open_at[1:]:
                raise Unmeasurable("line %d: close mark does not match the block opened "
                                   "at line %d" % (no, open_at[0]))
            open_at = None
            events.append((no, "close", kind, fams))
    if open_at:
        raise Unmeasurable("line %d: block never closed" % open_at[0])
    notes = {}
    for no, line in enumerate(raw_lines, 1):
        if not re.match(r"\s*#\s*define\b", line):
            continue
        texts = [line]
        if no >= 2 and COMMENT_ONLY.match(raw_lines[no - 2]):
            texts.append(raw_lines[no - 2])
        alias = known = None
        for t in texts:
            a, k = ALIAS.search(t), KNOWN.search(t)
            alias = alias or (a.group(1) if a else None)
            known = known or (k.group(1) if k else None)
        if alias or known:
            notes[no] = (alias, known)
    return events, notes, specs, bad


def not_code_reason(raw_lines, no):
    """The reason of a `not a code: <reason>` note on define line `no` (1-based:
    trailing comment, or the comment-only line just above), or None. An empty reason
    is None."""
    texts = [raw_lines[no - 1]]
    if no >= 2 and COMMENT_ONLY.match(raw_lines[no - 2]):
        texts.append(raw_lines[no - 2])
    for t in texts:
        m = NOT_CODE.search(t)
        if m and m.group(1).strip():
            return m.group(1).strip()
    return None


def find_enums(text):
    """Return a list of (first line, last line, [(line, name, expr or None)])
    for every `enum [tag] { ... }` of the comment-free text."""
    out = []
    for m in re.finditer(r"\benum\b[^;{}()]*\{", text):
        j = text.find("}", m.end())
        if j < 0:
            continue
        members, pos = [], m.end()
        for piece in text[m.end():j].split(","):
            at = pos
            pos += len(piece) + 1
            mm = re.match(r"\s*([A-Za-z_]\w*)\s*(?:=(.*))?$", piece, re.S)
            if not mm:
                if piece.strip():
                    members = None  # not a plain enumerator list: skip the enum
                    break
                continue
            line = text.count("\n", 0, at + mm.start(1)) + 1
            members.append((line, mm.group(1), mm.group(2)))
        if members:
            out.append((text.count("\n", 0, m.start()) + 1,
                        text.count("\n", 0, j) + 1, members))
    return out


def read_defines(raw_text, strict=True, in_block=None):
    """Return list of (lineno, name, value, kind), kind 'define' or 'enum'.
    strict: an integer-looking define that cannot be evaluated exits 2. When
    not strict, such a define and any enum or define outside a block (in_block
    is a function of a line number) is skipped without a word."""
    text = strip_comments(raw_text)
    env, rows = {}, []
    enums = sorted(find_enums(text))
    en = 0

    def do_enum(first, members):
        nxt = 0
        for no, name, expr in members:
            if expr is not None and expr.strip():
                nxt = evaluate(to_python(tokens(expr), no), env, no, name)
            env[name] = nxt
            rows.append((no, name, nxt, "enum"))
            nxt += 1

    for no, line in logical_lines(text):
        while en < len(enums) and enums[en][0] <= no:
            if in_block is None or in_block(enums[en][0]):
                do_enum(enums[en][0], enums[en][2])
            en += 1
        m = re.match(r"\s*#\s*define\s+([A-Za-z_]\w*)(\(?)(.*)$", line)
        if not m:
            continue
        name, paren, body = m.group(1), m.group(2), m.group(3)
        if paren or not body.strip() or '"' in body:
            continue
        toks = tokens(body)
        if any(t in STMT_TOKENS or t in ("this", "sizeof") for t in toks):
            continue  # a statement or initializer, not an expression
        has_num_or_op = any(t[0].isdigit() or t[0] in "'-+*/&|^~()<>%" for t in toks)
        try:
            if not has_num_or_op:
                # bare words only: an alias of an integer define, or a type
                if len(toks) == 1 and toks[0] in env:
                    value = env[toks[0]]
                else:
                    continue
            else:
                value = evaluate(to_python(toks, no), env, no, name)
        except Unmeasurable:
            if strict or (in_block is not None and in_block(no)):
                raise
            continue
        env[name] = value
        rows.append((no, name, value, "define"))
    while en < len(enums):
        if in_block is None or in_block(enums[en][0]):
            do_enum(enums[en][0], enums[en][2])
        en += 1
    rows.sort(key=lambda r: r[0])
    return rows


def where(path, no, multi):
    return "line %d" % no if not multi else "%s line %d" % (rel(path), no)


def rel(path):
    try:
        r = os.path.relpath(path, ROOT)
        return path if r.startswith("..") else r
    except ValueError:
        return path


def scan_file(path, strict, multi):
    """Read one file. Return (placed, outside, specs, bad, nofam). placed: list of
    (lineno, name, value, kind, fams, alias, known) of the members of family
    blocks. outside: FAIL messages for defines in no block (strict only).
    specs: list of (lineno, family, spec). bad: list of FAIL messages. nofam: list
    of (lineno, name, kind, `not a code` reason or None) of the no-family members."""
    with open(path, encoding="latin-1") as f:
        raw = f.read()
    raw_lines = raw.split("\n")
    events, notes, specs_by, bad = read_marks(raw_lines)
    spans, start = [], None
    for no, what, _kind, _f in events:
        if what == "open":
            start = no
        else:
            spans.append((start, no))

    def in_block(n):
        return any(a < n < b for a, b in spans)
    rows = read_defines(raw, strict, in_block)
    for no, line in logical_lines(strip_comments(raw)):
        fm = FUNC_DEFINE.match(line)
        if not fm:
            continue
        for a, b in spans:
            stored = sorted(f for f, sp in specs_by.get(a, {}).items()
                            if sp["class"] == "stored")
            if a < no < b and stored:
                bad.append((no, "line %d: the function-like macro %s at %s:%d sits inside "
                            "the stored family %s, where the inventory cannot see its "
                            "value. Fix: move it to a no-family block."
                            % (no, fm.group(1), rel(path), no, " ".join(stored))))
    placed, outside, nofam = [], [], []
    ev, cur = 0, None
    for no, name, value, kind in rows:
        while ev < len(events) and events[ev][0] < no:
            cur = events[ev][2:] if events[ev][1] == "open" else None
            ev += 1
        if cur is None:
            if strict and kind == "define":
                outside.append("FAIL: %s: %s is outside every family block. Fix: put it "
                               "inside its family's marks ('// family: <name> <class>' "
                               "... '// end family: <name>'), or inside a no-family "
                               "block ('// no-family' ... '// end no-family')."
                               % (where(path, no, multi), name))
            continue
        ckind, fams = cur
        if ckind == "no-family":
            nofam.append((no, name, kind, not_code_reason(raw_lines, no)))
            continue
        alias, known = notes.get(no, (None, None))
        placed.append((no, name, value, kind, fams, alias, known))
    specs = [(no, fam, sp) for no, d in sorted(specs_by.items()) for fam, sp in d.items()]
    return placed, outside, specs, ["FAIL: %s: %s" % (where(path, n, multi), m.split(": ", 1)[1])
                                    for n, m in bad], nofam


def marked_files(root=ROOT):
    """Every file of inc/ and src/ (but Defines.h) that holds a family mark."""
    out = []
    for sub in ("inc", "src"):
        for dp, _dn, fns in os.walk(os.path.join(root, sub)):
            for fn in sorted(fns):
                p = os.path.join(dp, fn)
                if p == DEF_DEFAULT or not fn.endswith(SOURCE_EXT):
                    continue  # the compiler never reads a backup such as X.h.orig
                try:
                    with open(p, encoding="latin-1") as f:
                        if any(MARK.match(l) for l in f.read().split("\n")):
                            out.append(p)
                except OSError:
                    pass
    return sorted(out)


def scan_all(files):
    """Read the files; return (fams, problems, kinds, notes). fams: see
    load_families, with extra keys 'marks' [(file, line)] and 'rows' (the
    placed members with alias/known) used by check()."""
    multi = len(files) > 1
    fams, problems, nofam = {}, [], []
    for k, path in enumerate(files):
        try:
            placed, outside, specs, bad, nf = scan_file(path, k == 0, multi)
        except OSError as e:
            raise Unmeasurable("cannot read %s: %s" % (path, e))
        except Unmeasurable as e:
            raise Unmeasurable("%s%s" % ("" if not multi else rel(path) + ": ", e))
        problems += outside + bad
        nofam += [(path, no, name, kind, why) for no, name, kind, why in nf]
        for no, fam, spec in specs:
            d = fams.setdefault(fam, {"class": None, "shape": None, "width": None,
                                      "sentinels": [], "bounds": [], "grows": [], "blocks": [], "members": [],
                                      "marks": [], "rows": [], "first": None,
                                      "val_of": [], "mag_of": [], "field_of": [],
                                      "index_of": [], "elem_of": [], "glyph_of": [], "word_of": [], "at_of": [], "shares": []})
            d["marks"].append((path, no))
            if spec["class"] is None:
                continue  # already reported as a bad mark
            key = (spec["class"], spec["shape"], spec["width"])
            if d["first"] is None:
                d["first"] = (key, path, no)
                d["class"], d["shape"], d["width"] = key
            elif d["first"][0] != key:
                problems.append("FAIL: %s: family %s says %s but %s says %s. Every block "
                                "of one family MUST carry one class."
                                % (where(path, no, multi), fam, " ".join(x for x in key if x),
                                   where(d["first"][1], d["first"][2], multi),
                                   " ".join(x for x in d["first"][0] if x)))
            for s in spec["sentinels"]:
                d["sentinels"].append((s, path, no))
            for s in spec["bounds"]:
                d["bounds"].append((s, path, no))
            for s in spec["grows"]:
                d["grows"].append((s, path, no))
            if spec["block"] is not None:
                d["blocks"].append((spec["block"], path, no))
            for s in spec["val_of"]:
                d["val_of"].append((s, path, no))
            for s in spec["mag_of"]:
                d["mag_of"].append((s, path, no))
            for kind in ("field_of", "index_of", "elem_of", "glyph_of", "word_of", "at_of", "shares"):
                for s in spec[kind]:
                    d[kind].append((s, path, no))
        for no, name, value, kind, fams_here, alias, known in placed:
            for fam in fams_here:
                d = fams.setdefault(fam, {"class": None, "shape": None, "width": None,
                                          "sentinels": [], "bounds": [], "grows": [], "blocks": [], "members": [],
                                          "marks": [], "rows": [], "first": None,
                                          "val_of": [], "mag_of": [], "field_of": [],
                                          "index_of": [], "elem_of": [], "glyph_of": [], "word_of": [], "at_of": [], "shares": []})
                d["rows"].append((no, name, value, kind, alias, known, path))
                d["members"].append((name, value, rel(path), no))
    multi_files = multi
    problems += prefix_problems(fams, nofam, multi)
    # val-of / mag-of: the statuses whose val or mag holds a member of the family (inc-cjos0 9f-pre P2)
    stati_val = {m[0]: m[1] for m in fams.get("stati", {}).get("members", [])}
    claims = {}
    for fam, d in sorted(fams.items()):
        for slot in ("val", "mag"):
            for s, path, no in d[slot + "_of"]:
                if s not in stati_val:
                    problems.append("FAIL: %s: family %s says '%s-of %s' but %s is not a member of "
                                    "family stati" % (where(path, no, multi_files), fam, slot, s, s))
                    continue
                other = claims.setdefault((stati_val[s], slot), (fam, s))
                if other[0] != fam:
                    problems.append("FAIL: %s: the %s %s is claimed by both family %s and family %s "
                                    "(one family per status and slot)"
                                    % (where(path, no, multi_files), s, slot, other[0], fam))
    # field-of / index-of / elem-of: one saved field, one family, unless both families say `shares` (9f-pre P3)
    field_claims = {}
    for fam, d in sorted(fams.items()):
        for kind in FIELD_ATTRS:
            for key, path, no in d[kind]:
                other = field_claims.setdefault(key, (fam, kind))
                if other[0] == fam:
                    if other[1] != kind:
                        problems.append("FAIL: %s: family %s claims %s as both %s and %s"
                                        % (where(path, no, multi_files), fam, key,
                                           other[1].replace("_", "-"), kind.replace("_", "-")))
                    continue
                theirs = fams[other[0]]
                if other[0] in [x for x, _p, _n in d["shares"]] and fam in [x for x, _p, _n in theirs["shares"]]:
                    continue
                problems.append("FAIL: %s: the field %s is claimed by both family %s and family %s "
                                "(one family per saved field; two share one only when each says "
                                "'shares <other>')" % (where(path, no, multi_files), key, other[0], fam))
        for s, path, no in d["shares"]:
            if s not in fams:
                problems.append("FAIL: %s: family %s says 'shares %s' but there is no family %s"
                                % (where(path, no, multi_files), fam, s, s))
    # at-of: the array must have an index-of family, NAME must be its member, and (array, NAME) has one family (9f-pre P5b)
    index_fam = {}
    for fam, d in sorted(fams.items()):
        for key, _p, _n in d["index_of"]:
            index_fam.setdefault(key, fam)
    at_claims = {}
    for fam, d in sorted(fams.items()):
        for key, path, no in d["at_of"]:
            arr, idx = key[:-1].split("[")
            ifam = index_fam.get(arr)
            if ifam is None:
                problems.append("FAIL: %s: family %s says 'at-of %s' but no family says 'index-of %s', so %s has no names"
                                % (where(path, no, multi_files), fam, key, arr, idx))
            elif idx not in {m[0] for m in fams[ifam]["members"]}:
                problems.append("FAIL: %s: family %s says 'at-of %s' but %s is not a member of family %s (the index-of family of %s)"
                                % (where(path, no, multi_files), fam, key, idx, ifam, arr))
            other = at_claims.setdefault(key, fam)
            if other != fam:
                problems.append("FAIL: %s: the element %s is claimed by both family %s and family %s (one family per element)"
                                % (where(path, no, multi_files), key, other, fam))
    for fam, d in sorted(fams.items()):
        names = {m[0] for m in d["members"]}
        for s, path, no in d["sentinels"]:
            if s not in names:
                problems.append("FAIL: %s: family %s says 'sentinel %s' but %s is not a "
                                "define or enumerator of the family"
                                % (where(path, no, multi_files), fam, s, s))
        for s, path, no in d["grows"]:
            if s not in names:
                problems.append("FAIL: %s: family %s says 'grows %s' but %s is not a "
                                "define or enumerator of the family"
                                % (where(path, no, multi_files), fam, s, s))
            if s in {x for x, _p, _n in d["sentinels"]}:
                problems.append("FAIL: %s: family %s says both 'sentinel %s' and 'grows %s'; "
                                "a limit that sizes a saved array is not a sentinel"
                                % (where(path, no, multi_files), fam, s, s))
        for s, path, no in d["bounds"]:
            if s not in names:
                problems.append("FAIL: %s: family %s says 'bound %s' but %s is not a "
                                "define or enumerator of the family"
                                % (where(path, no, multi_files), fam, s, s))
        if len(d["bounds"]) > 1:
            problems.append("FAIL: family %s names %d bounds (%s); a family has one"
                            % (fam, len(d["bounds"]), " ".join(b[0] for b in d["bounds"])))
        if len({b[0] for b in d["blocks"]}) > 1:
            problems.append("FAIL: family %s names %d block sizes (%s); a family has one"
                            % (fam, len({b[0] for b in d["blocks"]}),
                               " ".join(str(b[0]) for b in d["blocks"])))
        kinds = {r[3] for r in d["rows"]}
        if d["shape"] == "enum" and "define" in kinds:
            problems.append("FAIL: family %s has shape enum but holds a #define (%s)"
                            % (fam, next(r[1] for r in d["rows"] if r[3] == "define")))
        if d["shape"] in ("ordinal", "bits") and "enum" in kinds:
            problems.append("FAIL: family %s has shape %s but holds an enumerator (%s). "
                            "Fix: shape enum." % (fam, d["shape"],
                                                  next(r[1] for r in d["rows"] if r[3] == "enum")))
        d["sentinels"] = [s for s, _p, _n in d["sentinels"]]
        d["bounds"] = [s for s, _p, _n in d["bounds"]]
        d["grows"] = [s for s, _p, _n in d["grows"]]
        d["block"] = d["blocks"][0][0] if d["blocks"] else None
        d["val_of"] = [s for s, _p, _n in d["val_of"]]
        d["mag_of"] = [s for s, _p, _n in d["mag_of"]]
        for kind in ("field_of", "index_of", "elem_of", "glyph_of", "word_of", "at_of", "shares"):
            d[kind] = [s for s, _p, _n in d[kind]]
    return fams, problems, multi, nofam


def family_prefixes(fams):
    """{prefix: [family]}. A family's prefix is the leading `<TOKEN>_` (letters and
    digits, then an underscore) that EVERY member shares. A family whose members share
    none contributes none. A prefix that 2+ families use is still a prefix."""
    out = {}
    for fam, d in fams.items():
        firsts = {(re.match(r"[A-Za-z0-9]+_", m[0]) or [None])[0] for m in d["members"]}
        if len(firsts) == 1 and None not in firsts:
            out.setdefault(firsts.pop(), []).append(fam)
    return out


def prefix_problems(fams, nofam, multi):
    """Rule 4: FAIL lines for a no-family define named like a family's members that
    carries no `not a code: <reason>`."""
    pre, out = family_prefixes(fams), []
    for path, no, name, _kind, why in nofam:
        hit = [p for p in sorted(pre) if name.startswith(p)]
        if hit and not why:
            out.append("FAIL: %s: %s sits in a no-family block but starts with %s, the prefix of "
                       "family %s. Fix: put it in that family, or write `not a code: <reason>` "
                       "on its line (or the line above)."
                       % (where(path, no, multi), name, hit[0], " ".join(pre[hit[0]])))
    return out


# Names a field-of / index-of / elem-of mark may use that no FIELD_ macro declares. Each needs the reason here.
FIELD_ATTRS = ("field_of", "index_of", "elem_of", "glyph_of", "word_of")
SAVED_FIELD_ALLOW = {
    # a script variable's type byte: one byte per variable inside the Game segment's Variables blob
    # (v1PutU8(d->DataType), src/SaveV1.cpp); the observer prints each variable's line under this name (V1FvVariable)
    "Game.ScriptVariable",
    # the record's type byte: the writer emits it with v1PutU8(o->Type) in the record envelope (src/SaveV1.cpp), not a
    # FIELD_ macro, and the observer prints it as its own line under this name (V1FvRec)
    "Envelope.Type",
}
FIELD_LIT = re.compile(r'\b(?:FIELD_[A-Z0-9_]+|V1EmbedBegin(?:_AT)?)\s*\(\s*"([^"]+)"')
ARCHIVE_BLOCK = re.compile(r'ARCHIVE_CLASS\(\s*(\w+)\s*,.*?END_ARCHIVE', re.S)


def saved_field_problems(fams, root=ROOT):
    """FAIL lines for a field-of / index-of / elem-of name that no saved field matches (9f-pre P3). The saved fields
    are the string literals of the FIELD_* and V1EmbedBegin* macros in inc/ and src/. A name Class.Field must have
    Field declared inside ARCHIVE_CLASS(Class ...) .. END_ARCHIVE; a longer name Class.Embed.Field needs Class to be
    an archive class and every later part to be a declared literal. SAVED_FIELD_ALLOW names the rest."""
    text = ""
    for sub in ("inc", "src"):
        for dp, _dn, fns in os.walk(os.path.join(root, sub)):
            for fn in sorted(fns):
                if fn.endswith((".h", ".cpp")):
                    with open(os.path.join(dp, fn), encoding="latin-1") as f:
                        text += f.read() + "\n"
    literals = set(FIELD_LIT.findall(text))
    classes = {}
    for m in ARCHIVE_BLOCK.finditer(text):
        classes.setdefault(m.group(1), set()).update(FIELD_LIT.findall(m.group(0)))
    problems = []
    for fam, d in sorted(fams.items()):
        for kind in FIELD_ATTRS + ("at_of",):
            for key in d.get(kind, []):
                key = re.sub(r"\[\w+\]$", "", key)   # at-of Player.Options[OPT_X]: the saved field is the array
                parts = key.split("@")[0].split(".")
                if key.split("@")[0] in SAVED_FIELD_ALLOW:
                    continue
                if len(parts) < 2 or parts[0] not in classes:
                    why = "%s is not a class with an ARCHIVE_CLASS block" % parts[0]
                elif len(parts) == 2 and parts[1] not in classes[parts[0]]:
                    why = "no FIELD_ macro in class %s declares %s" % (parts[0], parts[1])
                else:
                    gone = [x for x in parts[1:] if x not in literals]
                    why = ("no FIELD_ or V1EmbedBegin macro declares %s" % ", ".join(gone)) if gone else None
                if why:
                    problems.append("FAIL: family %s says '%s %s' but %s (a saved field is a FIELD_ macro name, "
                                    "or on SAVED_FIELD_ALLOW in tools/check_define_dups.py)"
                                    % (fam, kind.replace("_", "-"), key, why))
    return problems


def load_families(defines=None, files=None):
    """See IMPORT in the docstring. Exits 2 conditions raise Unmeasurable."""
    if files is None:
        files = [defines or DEF_DEFAULT]
        if defines is None:
            files += marked_files()
    fams, problems, _multi, _nofam = scan_all(files)
    out = {f: {"class": d["class"], "shape": d["shape"], "width": d["width"],
               "sentinels": list(d["sentinels"]), "bounds": list(d["bounds"]),
               "grows": list(d["grows"]), "block": d["block"], "val_of": list(d["val_of"]), "mag_of": list(d["mag_of"]),
               "field_of": list(d["field_of"]), "index_of": list(d["index_of"]),
               "elem_of": list(d["elem_of"]), "glyph_of": list(d["glyph_of"]), "word_of": list(d["word_of"]), "at_of": list(d["at_of"]), "shares": list(d["shares"]),
               "members": list(d["members"])}
           for f, d in fams.items()}
    return out, problems


BASELINE_REL = "tools/define_baseline.txt"
BASELINE = os.path.join(ROOT, *BASELINE_REL.split("/"))
NOFAM_REL = "tools/nofamily_baseline.txt"
NOFAM_BASELINE = os.path.join(ROOT, *NOFAM_REL.split("/"))
BASE_REF = "master"
SOURCE_EXT = (".h", ".hpp", ".cpp", ".c", ".inc")
INT_TYPE = (r"(?:unsigned|signed|int|short|long|char|size_t|rID|hObj|uchar|ushort|uint|ulong|"
            r"u?int(?:8|16|32|64)(?:_t)?|u?intptr_t)")
CONST_VAR = re.compile(r"(?<!\w)(?:static\s+)?(?:constexpr|const)\s+(?:static\s+)?"
                       r"((?:" + INT_TYPE + r"\s+)*" + INT_TYPE + r")\s+([A-Za-z_]\w*)\s*=(?!=)")
DIRECTIVE = re.compile(r"^[ \t]*#[ \t]*(\w*)((?:\\\n|[^\n])*)|[;{}]", re.M)
SCOPE_HEAD = re.compile(r"\b(class|struct|union|namespace|extern)\b")
LOOSE_HOW = ("Fix: put it inside its family's marks ('// family: <name> <class>' ... "
             "'// end family: <name>'), or inside a no-family block ('// no-family' ... "
             "'// end no-family'). The baseline %s only shrinks.")


def blank_strings(t):
    """Replace the inside of string and char literals by spaces; offsets stay."""
    out, i, n = [], 0, len(t)
    while i < n:
        ch = t[i]
        if ch in "\"'":
            j = i + 1
            while j < n and t[j] != ch and t[j] != "\n":
                j += 2 if t[j] == "\\" else 1
            end = j + 1 if j < n and t[j] == ch else j
            out.append(ch + " " * max(0, end - i - 2) + (ch if end - i >= 2 else ""))
            i = end
        else:
            out.append(ch); i += 1
    return "".join(out)


def scope_events(t):
    """t: blanked, comment-free text. Return (events, depth). events: sorted
    (offset, True when every open brace is a class, struct, union, namespace or
    extern block) after each ; { } outside a directive. `#if 0` text is skipped;
    `#else` and `#elif` restart from the stack at the `#if`. depth: braces left
    open at the end (not 0: the file is unmeasurable)."""
    stack, events, conds, last = [], [], [], 0
    for m in DIRECTIVE.finditer(t):
        g = m.group(0)
        if g[0] in " \t#":
            d = m.group(1)
            if d in ("if", "ifdef", "ifndef"):
                conds.append([list(stack), d == "if" and m.group(2).strip() == "0"])
            elif d in ("else", "elif") and conds:
                stack = list(conds[-1][0]); conds[-1][1] = False
            elif d == "endif" and conds:
                conds.pop()
            last = m.end()
            continue
        if any(c[1] for c in conds):
            last = m.end()
            continue
        if g == "{":
            head = t[last:m.start()]
            stack.append("(" not in head and bool(SCOPE_HEAD.search(head)))
        elif g == "}" and stack:
            stack.pop()
        last = m.end()
        events.append((m.start(), all(stack)))
    return events, len(stack)


def is_constant_define(toks, known):
    """toks: tokens of a define body. known: integer defines of this file so far."""
    if not toks or any(t in STMT_TOKENS or t in ("this", "sizeof", "?") for t in toks):
        return False
    if any(a == "-" and b == ">" or a == ":" and b == ":" for a, b in zip(toks, toks[1:])):
        return False
    if any(IDENT.fullmatch(a) and b == "(" for a, b in zip(toks, toks[1:])):
        return False  # a call
    if any(t[0].isdigit() or t[0] == "'" for t in toks):
        return True
    return len(toks) == 1 and toks[0] in known


def loose_scan(path, skip_defines=False):
    """Every integer constant of the file that sits outside every family and
    no-family block. Return a list of (line, name, form), form 'define', 'enum'
    or 'const'. The form 'const' is a scalar integer `const`/`constexpr`/`static
    const` variable with an `=` initializer at namespace or class scope; one in
    a function body is not listed (the brace stack tells them apart: a block is
    namespace or class scope when its head, back to the last ; { }, holds
    class/struct/union/namespace/extern and no `(`). An unbalanced file exits 2."""
    with open(path, encoding="latin-1") as f:
        raw = f.read()
    events, _notes, _specs, _bad = read_marks(raw.split("\n"))
    spans, start = [], None
    for no, what, _kind, _f in events:
        if what == "open":
            start = no
        else:
            spans.append((start, no))
    text = strip_comments(raw)
    out, known = [], set()
    for no, line in logical_lines(text):
        m = re.match(r"\s*#\s*define\s+([A-Za-z_]\w*)(\(?)(.*)$", line)
        if not m or m.group(2) or not m.group(3).strip() or '"' in m.group(3):
            continue
        if is_constant_define(tokens(m.group(3)), known):
            known.add(m.group(1))
            if not skip_defines:
                out.append((no, m.group(1), "define"))
    for _a, _b, members in find_enums(text):
        out += [(no, name, "enum") for no, name, _expr in members]
    t = blank_strings(text)
    ev, depth = scope_events(t)
    if depth:
        raise Unmeasurable("%d brace(s) never closed, so a const variable cannot be placed "
                           "in a function or a class" % depth)
    offs = [e[0] for e in ev]
    for m in CONST_VAR.finditer(t):
        k = bisect.bisect_left(offs, m.start()) - 1
        if k >= 0 and not ev[k][1]:
            continue  # inside a function body
        cut = max(t.rfind(c, 0, m.start()) for c in ";{}")
        pre = t[cut + 1:m.start()]
        if pre.count("(") > pre.count(")"):
            continue  # a parameter with a default
        out.append((t.count("\n", 0, m.start(2)) + 1, m.group(2), "const"))
    return sorted((no, name, form) for no, name, form in out
                  if not any(a < no < b for a, b in spans))


def source_files(root=ROOT):
    """Every source file of inc/ and src/, sorted."""
    out = []
    for sub in ("inc", "src"):
        for dp, _dn, fns in os.walk(os.path.join(root, sub)):
            out += [os.path.join(dp, fn) for fn in fns if fn.endswith(SOURCE_EXT)]
    return sorted(out)


def load_baseline(path=BASELINE):
    """Return {(file, name): form}. Key is file plus name, never a line."""
    known = {}
    try:
        with open(path) as f:
            for raw in f:
                if not raw.strip() or raw.lstrip().startswith("#"):
                    continue
                parts = raw.rstrip("\n").split("\t")
                if len(parts) != 3:
                    raise Unmeasurable("%s: bad line (want file, name, form with tabs): %r"
                                       % (rel(path), raw.rstrip("\n")))
                known.setdefault((parts[0], parts[1]), parts[2])
    except OSError as e:
        raise Unmeasurable("cannot read the baseline %s: %s" % (rel(path), e))
    return known


def master_baseline_keys(root=ROOT, ref=BASE_REF, relpath=BASELINE_REL):
    """The baseline keys of `ref`, or None when the tree is not a git checkout or
    `ref` does not hold the file yet (the first landing). A checkout with no `ref`,
    or a git failure, exits 2."""
    if not os.path.exists(os.path.join(root, ".git")) or shutil.which("git") is None:
        return None  # no history to read, or no git program: the same as no history
    def git(*a):
        return subprocess.run(["git", "-C", root] + list(a), capture_output=True, text=True)
    r = git("rev-parse", "--verify", "--quiet", ref + "^{commit}")
    if r.returncode != 0:
        raise Unmeasurable("git has no %s to compare the baseline against" % ref)
    if git("cat-file", "-e", "%s:%s" % (ref, relpath)).returncode != 0:
        return None
    r = git("show", "%s:%s" % (ref, relpath))
    if r.returncode != 0:
        raise Unmeasurable("git show %s:%s failed: %s" % (ref, relpath, r.stderr.strip()))
    keys = set()
    for raw in r.stdout.split("\n"):
        if raw.strip() and not raw.lstrip().startswith("#"):
            parts = raw.split("\t")
            if len(parts) == 3:
                keys.add((parts[0], parts[1]))
    return keys


def loose_problems(files, strict_file, baseline, base_keys):
    """FAIL lines: a constant outside every block that the baseline does not list,
    and a baseline entry that master's baseline does not have. strict_file: the
    file whose #defines the first rule already covers."""
    msgs = []
    for path in files:
        for no, name, form in loose_scan(path, skip_defines=(path == strict_file)):
            if (rel(path), name) not in baseline:
                what = {"define": "#define", "enum": "enum member",
                        "const": "const variable"}[form]
                msgs.append("FAIL: %s line %d: unclassified constant %s (%s). %s"
                            % (rel(path), no, name, what, LOOSE_HOW % BASELINE_REL))
    return msgs + gain_problems(baseline, base_keys, BASELINE_REL,
                                "put the constant in a family block or a no-family block instead")


def gain_problems(baseline, base_keys, relpath, instead):
    """FAIL lines for every entry of `baseline` that `master:relpath` (base_keys) lacks.
    Shared by rule 5 (define_baseline.txt) and rule 4 (nofamily_baseline.txt)."""
    if base_keys is None:
        return []
    return ["FAIL: %s gained the entry %s %s that %s does not have. The baseline only "
            "shrinks; %s." % (relpath, key[0], key[1], BASE_REF, instead)
            for key in sorted(set(baseline) - base_keys)]


def nofamily_problems(nofam, baseline, base_keys, multi):
    """Rule 4: a no-family define the baseline does not list FAILS; so does a baseline
    that gained an entry against master."""
    msgs = []
    for path, no, name, _kind, _why in nofam:
        if (rel(path), name) not in baseline:
            msgs.append("FAIL: %s: %s is a no-family define that %s does not list. Fix: put it "
                        "in its family's marks. A constant that is not a code needs one "
                        "baseline line (file, name, form, tab-separated), and the baseline "
                        "only shrinks."
                        % (where(path, no, multi), name, NOFAM_REL))
    return msgs + gain_problems(baseline, base_keys, NOFAM_REL,
                                "put the define in a family block instead")


def renumber_problems(paths):
    """Rule 4b: a comment on a define line, or the comment-only line above it, that holds
    the word `renumbered` records a hand move. Values move only through move_branch_values.py."""
    out = []
    for path in paths:
        with open(path, encoding="latin-1") as f:
            lines = f.read().split("\n")
        for no, line in enumerate(lines, 1):
            if not re.match(r"\s*#\s*define\b", line):
                continue
            here = RENUMBERED.search(line) or (no >= 2 and COMMENT_ONLY.match(lines[no - 2])
                                               and RENUMBERED.search(lines[no - 2]))
            if here:
                out.append("FAIL: %s:%d: the comment records a hand renumber. Values move only "
                           "through tools/move_branch_values.py; never edit a stored number by "
                           "hand. Fix: delete the hand move or run the tool." % (rel(path), no))
    return out


def check(defines, others=(), loose=None):
    """Return (exit code, list of message lines). loose: None, or (files,
    baseline, base_keys, nofam_baseline, nofam_base_keys) for the closed-world rules
    over every file (rule 5 and the no-family baseline of rule 4)."""
    files = [defines] + list(others)
    try:
        fams, bad_msgs, multi, nofam = scan_all(files)
        bad_msgs = list(bad_msgs) + renumber_problems(
            files if loose is None else sorted(set(files) | set(loose[0])))
        if loose is not None:
            bad_msgs += loose_problems(loose[0], defines, loose[1], loose[2]) \
                + nofamily_problems(nofam, loose[3], loose[4], multi) + saved_field_problems(fams)
    except Unmeasurable as e:
        return 2, ["check_define_dups: UNMEASURED: %s" % e]
    except OSError as e:
        return 2, ["check_define_dups: UNMEASURED: cannot read %s: %s" % (defines, e)]
    msgs, bad = list(bad_msgs), bool(bad_msgs)
    nknown = 0
    for fam in sorted(fams):
        rows_f = sorted(fams[fam]["rows"], key=lambda r: (files.index(r[6]), r[0]))
        by_name = {}
        for no, name, value, _k, _a, _kn, _p in rows_f:
            by_name.setdefault(name, []).append(value)
        groups = {}
        for no, name, value, _kind, alias, known, path in rows_f:
            if alias:
                if value not in by_name.get(alias, []) or alias == name:
                    bad = True
                    msgs.append("FAIL: family %s %s: %s says 'alias of %s' but %s"
                                % (fam, where(path, no, multi), name, alias,
                                   "no such define in the family with value %d" % value
                                   if alias not in by_name else
                                   "its value is %s, not %d"
                                   % (",".join(map(str, by_name[alias])), value)
                                   if alias != name else "a name cannot alias itself"))
                continue
            if known:
                nknown += 1
                msgs.append("KNOWN: family %s %s: %s = %d, collision tracked by %s"
                            % (fam, where(path, no, multi), name, value, known))
                continue
            groups.setdefault(value, []).append((no, name, path))
        for value, g in sorted(groups.items()):
            if len(g) > 1:
                bad = True
                msgs.append("FAIL: family %s: %s all = %d (lines %s). Renumber your own "
                            "entry; master's number stays. A deliberate second name "
                            "carries '/* alias of <NAME> */'."
                            % (fam, " ".join(n for _l, n, _p in g), value,
                               ", ".join(str(l) if not multi else "%s:%d" % (rel(p), l)
                                         for l, _n, p in g)))
    if not bad:
        msgs.append("check_define_dups: PASS (%d families, %d known collisions%s)"
                    % (len(fams), nknown, "" if loose is None else
                       ", %d baseline constants outside every block, %d no-family baseline"
                       % (len(loose[1]), len(loose[3]))))
    return (1 if bad else 0), msgs


def selftest():
    os.makedirs(os.path.join(ROOT, "logs"), exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="define_dups.", dir=os.path.join(ROOT, "logs"))
    n = [0]

    def run(text):
        n[0] += 1
        d = os.path.join(tmp, "d%d.h" % n[0])
        with open(d, "w") as f:
            f.write(text)
        c, m = check(d)
        return c, "\n".join(m)

    def fam(name, body, cls="internal"):
        return "// family: %s %s\n%s// end family: %s\n" % (name, cls, body, name)
    try:
        # a. two names, one value, one family: fail
        c, m = run(fam("stati", "#define A_X 234\n#define B_X 234\n"))
        assert c == 1 and "family stati: A_X B_X all = 234" in m, (c, m)
        assert run(fam("stati", "#define A_X 234\n#define B_X 235\n"))[0] == 0
        # a backup copy (X.h.orig, left by patch) is not a second header
        mroot = os.path.join(tmp, "mroot")
        os.makedirs(os.path.join(mroot, "inc"))
        for nm in ("Twin.h", "Twin.h.orig"):
            with open(os.path.join(mroot, "inc", nm), "w") as f:
                f.write(fam("a", "#define A_X 7\n"))
        got = marked_files(mroot)
        assert got == [os.path.join(mroot, "inc", "Twin.h")], got
        # b. one value in two families: pass
        c, m = run(fam("a", "#define A_X 7\n") + fam("b", "#define B_X 7\n"))
        assert c == 0 and "PASS" in m, (c, m)
        # a family in two separate blocks is one family
        c, m = run(fam("a", "#define A_X 7\n") + fam("b", "#define B_X 8\n")
                   + fam("a", "#define A_Y 7\n"))
        assert c == 1 and "family a: A_X A_Y all = 7" in m, (c, m)
        # c. alias with target's value passes (trailing and line-above forms)
        c, m = run(fam("a", "#define A_X 7\n#define A_Y 7 /* alias of A_X */\n"))
        assert c == 0, (c, m)
        c, m = run(fam("a", "#define A_X 7\n/* alias of A_X */\n#define A_Y 7\n"))
        assert c == 0, (c, m)
        c, m = run(fam("a", "#define A_X 7\n#define A_Y 8 /* alias of A_X */\n"))
        assert c == 1 and "A_Y says 'alias of A_X'" in m and "not 8" in m, (c, m)
        c, m = run(fam("a", "#define A_Y 7 /* alias of NOPE */\n"))
        assert c == 1 and "no such define" in m, (c, m)
        c, m = run(fam("a", "#define A_X 7\n") + fam("b", "#define B_Y 7 /* alias of A_X */\n"))
        assert c == 1 and "family b" in m, (c, m)  # target must share the family
        # trailing // mark on a define line: accepted, and still recognized
        c, m = run(fam("a", "#define A_X 7\n#define A_Y 7 // alias of A_X\n"))
        assert c == 0, (c, m)
        c, m = run(fam("a", "#define A_X 7\n#define A_Y 8 // alias of A_X\n"))
        assert c == 1 and "A_Y says 'alias of A_X'" in m and "not 8" in m, (c, m)
        c, m = run(fam("a", "#define A_X 7\n#define A_Y 7 // known collision: inc-x\n"))
        assert c == 0 and "inc-x" in m, (c, m)
        # d. unmarked define: fail, names it
        c, m = run("#define LOOSE 3\n" + fam("a", "#define A_X 7\n"))
        assert c == 1 and "line 1: LOOSE is outside every family block" in m, (c, m)
        c, m = run(fam("a", "#define A_X 7\n") + "#define LATE 9\n")
        assert c == 1 and "LATE is outside" in m, (c, m)
        # e. no-family block: equal values pass, and are not compared to a family
        c, m = run("// no-family\n#define N_A 5\n#define N_B 5\n// end no-family\n"
                   + fam("a", "#define A_X 5\n"))
        assert c == 0, (c, m)
        # e2. rule 4a (inc-x39wn): a no-family define named like a family's members needs `not a code: <why>`
        nofam = lambda body: "// no-family\n" + body + "// end no-family\n"
        ef = fam("ef", "#define EF_GLOW 114\n#define EF_X 5\n")
        c, m = run(ef + nofam("#define EF_ARTIFACT 114\n"))   # the epic case: red
        assert c == 1 and "EF_ARTIFACT sits in a no-family block" in m and "prefix of family ef" in m, (c, m)
        c, m = run(ef + nofam("#define EF_CAP 9 /* not a code: a Hit Dice cap */\n"))   # green: trailing reason
        assert c == 0, (c, m)
        c, m = run(ef + nofam("// not a code: a Hit Dice cap\n#define EF_CAP 9\n"))     # green: reason on the line above
        assert c == 0, (c, m)
        c, m = run(ef + nofam("#define EF_CAP 9 /* not a code: */\n"))                     # red: an empty reason is no reason
        assert c == 1 and "EF_CAP sits in a no-family block" in m, (c, m)
        c, m = run(ef + nofam("/* not a code: a cap */\n\n#define EF_CAP 9\n"))           # red: the note is two lines away
        assert c == 1 and "EF_CAP" in m, (c, m)
        c, m = run(ef + nofam("enum { EF_E1 = 40 };\n"))                                    # red: an enumerator counts too
        assert c == 1 and "EF_E1" in m, (c, m)
        c, m = run(ef + nofam("#define OTHER_CAP 9\n#define EFFECT_CAP 9\n"))             # green: another prefix; EFFECT_ is not EF_
        assert c == 0, (c, m)
        # no shared prefix, no prefix: members A_X and B_Y share none
        c, m = run(fam("mix", "#define A_X 1\n#define B_Y 2\n") + nofam("#define A_CAP 9\n#define B_CAP 9\n"))
        assert c == 0, (c, m)
        # two families on one prefix: still a prefix, and both are named
        c, m = run(fam("p1", "#define P_A 1\n") + fam("p2", "#define P_B 1\n") + nofam("#define P_CAP 9\n"))
        assert c == 1 and "family p1 p2" in m, (c, m)
        # rule 4b: a comment that records a hand renumber (trailing, line above, any case)
        c, m = run(fam("a", "#define A_X 7 /* renumbered from 5 */\n"))
        assert c == 1 and "hand renumber" in m and "tools/move_branch_values.py" in m and ".h:2" in m, (c, m)
        c, m = run(fam("a", "// Renumbered by hand\n#define A_X 7\n"))
        assert c == 1 and "hand renumber" in m, (c, m)
        c, m = run(fam("a", "// renumbered\n\n#define A_X 7\n"))                        # green: not on the line above
        assert c == 0, (c, m)
        c, m = run(fam("a", "#define A_X 7 /* the number is not a renumber */\n"))
        assert c == 0, (c, m)
        # f. known collision: pass, reported with the bead id
        c, m = run(fam("stati", "#define A_X 234\n#define B_X 234 /* known collision: inc-upw.57 */\n"))
        assert c == 0 and "KNOWN" in m and "B_X" in m and "inc-upw.57" in m, (c, m)
        # known mark does not excuse a third name
        c, m = run(fam("stati", "#define A_X 234\n#define B_X 234 /* known collision: inc-x */\n"
                       "#define C_X 234\n"))
        assert c == 1 and "A_X C_X all = 234" in m, (c, m)
        # g. multi-family block: a duplicate against a member of either family fails
        multi = "// family: a internal, b internal\n#define M_X 9\n// end family: a, b\n"
        c, m = run(multi + fam("a", "#define A_X 9\n"))
        assert c == 1 and "family a: M_X A_X all = 9" in m, (c, m)
        c, m = run(multi + fam("b", "#define B_X 9\n"))
        assert c == 1 and "family b: M_X B_X all = 9" in m, (c, m)
        assert run(multi + fam("c", "#define C_X 9\n"))[0] == 0
        # h. unbalanced or nested marks: exit 2
        for bad in ("// family: a\n#define A_X 1\n",
                    "#define A_X 1\n// end family: a\n",
                    "// family: a\n// end family: b\n",
                    "// family: a\n// family: b\n// end family: b\n// end family: a\n",
                    "// no-family\n// family: a\n// end family: a\n// end no-family\n",
                    "// family: a\n// end no-family\n"):
            c, m = run(bad)
            assert c == 2 and "UNMEASURED" in m and "line" in m, (bad, c, m)
        # i. bard-step red/green from the bead
        stati = "#define SICKNESS 1\n#define POISONED 2\n"
        c, m = run(fam("stati", stati) + fam("bard-step", "#define BARD_CHORUS 2\n"))
        assert c == 0, (c, m)
        c, m = run(fam("stati", stati + "#define NEW_STATUS 2\n"))
        assert c == 1 and "POISONED NEW_STATUS all = 2" in m, (c, m)
        # evaluator, comments, continuation, skipped shapes
        c, m = run(fam("q", "#define Q_A 8\n#define Q_B ((1 << 2) | (Q_A / 2)) + 4\n"))
        assert c == 1 and "Q_A Q_B all = 8" in m, (c, m)
        c, m = run(fam("q", "#define Q_C 0x0C\n#define Q_D (Q_C+1)\n#define Q_E 014\n"
                       "#define Q_F 'A'\n#define Q_G 66\n"))
        assert c == 1 and "Q_C Q_E all = 12" in m and "Q_F" not in m, (c, m)
        c, m = run(fam("q", "/* a\n #define HID_A 9\n */ #define V_A 4 // x\n"
                       "#define V_B \\\n 4\n"))
        assert c == 1 and "V_A V_B all = 4" in m and "HID_A" not in m, (c, m)
        c, m = run('#ifndef GUARD_H\n#define GUARD_H\n#define S_A "hi"\n'
                   "#define S_B(x) ((x)+1)\n#define S_C\n#define S_D unsigned char\n"
                   "#define S_E int\n#endif\n")
        assert c == 0, (c, m)  # guards, strings, macros, types are not constants
        c, m = run(fam("u", "#define U_A UNKNOWN_THING + 1\n"))
        assert c == 2 and "line 2" in m, (c, m)
        assert run(fam("u", "#define U_A 1 ? 2 : 3\n"))[0] == 2
        assert check(os.path.join(tmp, "missing.h"))[0] == 2
        # j. classes (inc-cjos0 phase 5a). The cases above run with `internal`.
        stored = "stored ordinal u8"
        c, m = run("// family: a\n#define A_X 1\n// end family: a\n")
        assert c == 1 and "line 1" in m and "family a has no class" in m, (c, m)
        c, m = run("// family: a stored\n#define A_X 1\n// end family: a\n")
        assert c == 1 and "bad shape" in m, (c, m)
        c, m = run("// family: a stored sideways u8\n#define A_X 1\n// end family: a\n")
        assert c == 1 and "line 1" in m and "bad shape 'sideways'" in m, (c, m)
        c, m = run("// family: a stored ordinal\n#define A_X 1\n// end family: a\n")
        assert c == 1 and "bad width" in m, (c, m)
        c, m = run("// family: a stored ordinal u7\n#define A_X 1\n// end family: a\n")
        assert c == 1 and "bad width 'u7'" in m, (c, m)
        c, m = run("// family: a maybe\n#define A_X 1\n// end family: a\n")
        assert c == 1 and "bad class 'maybe'" in m, (c, m)
        # the class of a multi-family mark is per family: only b is unclassified
        c, m = run("// family: a internal, b\n#define A_X 1\n// end family: a, b\n")
        assert c == 1 and "family b has no class" in m and "family a has no" not in m, (c, m)
        # an end mark carries no class
        c, m = run("// family: a internal\n#define A_X 1\n// end family: a internal\n")
        assert c == 2 and "names families only" in m, (c, m)
        # sentinel: must name a member of its own family, only on a stored family
        c, m = run(fam("a", "#define A_X 1\n#define A_LAST 2\n", stored + " sentinel A_LAST"))
        assert c == 0, (c, m)
        c, m = run(fam("a", "#define A_X 1\n", stored + " sentinel B_LAST")
                   + fam("b", "#define B_LAST 2\n"))
        assert c == 1 and "sentinel B_LAST" in m and "not a define or enumerator" in m, (c, m)
        c, m = run(fam("a", "#define A_X 1\n", stored + " sentinel NOPE"))
        assert c == 1 and "sentinel NOPE" in m, (c, m)
        c, m = run("// family: a internal sentinel A_X\n#define A_X 1\n// end family: a\n")
        assert c == 1 and "is internal" in m, (c, m)
        # grows (inc-cjos0 phase 7f): a member of its own family, stored only, never a sentinel
        c, m = run(fam("a", "#define A_X 1\n#define A_LAST 2\n", stored + " grows A_LAST"))
        assert c == 0, (c, m)
        c, m = run(fam("a", "#define A_X 1\n", stored + " grows NOPE"))
        assert c == 1 and "grows NOPE" in m and "not a define or enumerator" in m, (c, m)
        c, m = run(fam("a", "#define A_X 1\n#define A_LAST 2\n",
                       stored + " sentinel A_LAST grows A_LAST"))
        assert c == 1 and "both 'sentinel A_LAST' and 'grows A_LAST'" in m, (c, m)
        c, m = run("// family: a internal grows A_X\n#define A_X 1\n// end family: a\n")
        assert c == 1 and "is internal" in m, (c, m)
        c, m = run(fam("a", "#define A_X 1\n#define A_LAST 2\n",
                       stored + " grows A_LAST bound A_LAST"))
        assert c == 0, (c, m)
        fams, problems = load_families(files=[os.path.join(tmp, "d%d.h" % (n[0] - 4))])
        assert problems == [] and fams["a"]["grows"] == ["A_LAST"], (problems, fams)
        # one class per family across its blocks
        c, m = run(fam("a", "#define A_X 1\n", stored) + fam("a", "#define A_Y 2\n", "internal"))
        assert c == 1 and "family a says" in m, (c, m)
        c, m = run(fam("a", "#define A_X 1\n", stored) + fam("a", "#define A_Y 2\n", "stored ordinal u16"))
        assert c == 1 and "family a says" in m, (c, m)
        c, m = run(fam("a", "#define A_X 1\n", stored) + fam("a", "#define A_Y 2\n", stored))
        assert c == 0, (c, m)
        # bound: a member of its own family, ordinal or enum only, one per family (F05)
        c, m = run(fam("a", "#define A_X 1\n#define A_LAST 2\n", stored + " bound A_LAST"))
        assert c == 0, (c, m)
        c, m = run(fam("a", "#define A_X 1\n", stored + " bound NOPE"))
        assert c == 1 and "bound NOPE" in m and "not a define or enumerator" in m, (c, m)
        c, m = run(fam("a", "#define A_X 1\n#define A_LAST 2\n", "stored bits u8 bound A_LAST"))
        assert c == 1 and "bits family" in m, (c, m)
        c, m = run(fam("a", "#define A_X 1\n#define A_L 2\n#define A_M 3\n",
                       stored + " bound A_L bound A_M"))
        assert c == 1 and "names 2 bounds" in m, (c, m)
        fams, problems = load_families(files=[os.path.join(tmp, "d%d.h" % (n[0] - 3))])
        assert problems == [] and fams["a"]["bounds"] == ["A_LAST"], (problems, fams)
        # block <N> (inc-cjos0): a positive decimal size, ordinal or enum only, one size per family
        c, m = run(fam("a", "#define A_X 1\n", stored + " block 100"))
        assert c == 0, (c, m)
        fams, problems = load_families(files=[os.path.join(tmp, "d%d.h" % n[0])])
        assert problems == [] and fams["a"]["block"] == 100, (problems, fams)
        c, m = run(fam("a", "#define A_X 1\n", stored + " block x"))
        assert c == 1 and "block x" in m and "positive decimal" in m, (c, m)
        c, m = run(fam("a", "#define A_X 1\n", "stored bits u8 block 4"))
        assert c == 1 and "bits family" in m and "block 4" in m, (c, m)
        c, m = run(fam("a", "#define A_X 1\n", stored + " block 10") + fam("a", "#define A_Y 2\n", stored + " block 20"))
        assert c == 1 and "2 block sizes" in m, (c, m)
        c, m = run(fam("a", "#define A_X 1\n", stored + " block 10") + fam("a", "#define A_Y 2\n", stored))
        assert c == 0, (c, m)
        # val-of / mag-of (inc-cjos0 9f-pre P2): a stored family names the statuses whose val or mag
        # holds its members; each must be a member of family stati, and a (status, slot) has one family
        st = fam("stati", "#define BLINDNESS 3\n#define SLEEPING 7\n#define ASLEEP 7 /* alias of SLEEPING */\n",
                 "stored ordinal u8")
        c, m = run(st + fam("vb", "#define VB_A 1\n", stored + " val-of BLINDNESS"))
        assert c == 0, (c, m)
        fams, problems = load_families(files=[os.path.join(tmp, "d%d.h" % n[0])])
        assert problems == [] and fams["vb"]["val_of"] == ["BLINDNESS"] and fams["vb"]["mag_of"] == [], (problems, fams)
        c, m = run(st + fam("vb", "#define VB_A 1\n", stored + " val-of BLINDNESS+SLEEPING mag-of BLINDNESS"))
        assert c == 0, (c, m)
        c, m = run(st + fam("vb", "#define VB_A 1\n", stored + " val-of NOPE"))
        assert c == 1 and "val-of NOPE" in m and "not a member of family stati" in m, (c, m)
        c, m = run(fam("vb", "#define VB_A 1\n", stored + " mag-of BLINDNESS"))
        assert c == 1 and "mag-of BLINDNESS" in m and "not a member of family stati" in m, (c, m)
        c, m = run(st + fam("vb", "#define VB_A 1\n", stored + " val-of BLINDNESS")
                   + fam("vc", "#define VC_A 1\n", stored + " val-of BLINDNESS"))
        assert c == 1 and "BLINDNESS val is claimed by both" in m, (c, m)
        c, m = run(st + fam("vb", "#define VB_A 1\n", stored + " val-of SLEEPING")
                   + fam("vc", "#define VC_A 1\n", stored + " val-of ASLEEP"))
        assert c == 1 and "val is claimed by both" in m, (c, m)   # an alias is the same status
        c, m = run(st + fam("vb", "#define VB_A 1\n", stored + " val-of BLINDNESS")
                   + fam("vc", "#define VC_A 1\n", stored + " mag-of BLINDNESS"))
        assert c == 0, (c, m)   # the other slot is free
        c, m = run(st + "// family: vb internal val-of BLINDNESS\n#define VB_A 1\n// end family: vb\n")
        assert c == 1 and "is internal" in m, (c, m)
        c, m = run(st + fam("vb", "#define VB_A 1\n", stored + " val-of"))
        assert c == 1 and "bad word" in m, (c, m)
        # field-of / index-of / elem-of (inc-cjos0 9f-pre P3): a saved field has one family unless both say `shares`
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " field-of Creature.Dir"))
        assert c == 0, (c, m)
        fams, problems = load_families(files=[os.path.join(tmp, "d%d.h" % n[0])])
        assert problems == [] and fams["fa"]["field_of"] == ["Creature.Dir"], (problems, fams)
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " elem-of Item.Q+Item.R index-of Item.S"))
        assert c == 0, (c, m)
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " field-of Creature.Dir")
                   + fam("fb", "#define FB_A 1\n", stored + " field-of Creature.Dir"))
        assert c == 1 and "Creature.Dir is claimed by both" in m, (c, m)   # red: two families, one field
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " elem-of Item.Q")
                   + fam("fb", "#define FB_A 1\n", stored + " field-of Item.Q"))
        assert c == 1 and "Item.Q is claimed by both" in m, (c, m)   # a different attribute is the same field
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " elem-of Item.Q shares fb")
                   + fam("fb", "#define FB_A 1\n", stored + " elem-of Item.Q shares fa"))
        assert c == 0, (c, m)   # both say so: allowed
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " elem-of Item.Q shares fb")
                   + fam("fb", "#define FB_A 1\n", stored + " elem-of Item.Q"))
        assert c == 1 and "claimed by both" in m, (c, m)   # only one says so: refused
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " elem-of Item.Q shares nope"))
        assert c == 1 and "no family nope" in m, (c, m)
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " field-of"))
        assert c == 1 and "bad word" in m, (c, m)
        c, m = run("// family: fa internal field-of Creature.Dir\n#define FA_A 1\n// end family: fa\n")
        assert c == 1 and "is internal" in m, (c, m)
        # glyph-of / word-of (inc-cjos0 9f-pre P5a): the same one-family-per-field rule, and a word-of offset names a byte
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " glyph-of Item.Q+Item.R word-of Item.B@8"))
        assert c == 0, (c, m)
        fams, problems = load_families(files=[os.path.join(tmp, "d%d.h" % n[0])])
        assert fams["fa"]["glyph_of"] == ["Item.Q", "Item.R"] and fams["fa"]["word_of"] == ["Item.B@8"], fams
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " glyph-of Item.Q")
                   + fam("fb", "#define FB_A 1\n", stored + " field-of Item.Q"))
        assert c == 1 and "Item.Q is claimed by both" in m, (c, m)   # red: a glyph field is one family's
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " word-of Item.B@0")
                   + fam("fb", "#define FB_A 1\n", stored + " word-of Item.B@0"))
        assert c == 1 and "Item.B@0 is claimed by both" in m, (c, m)   # red: one word, two families
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " word-of Item.B@0")
                   + fam("fb", "#define FB_A 1\n", stored + " word-of Item.B@4"))
        assert c == 0, (c, m)   # two offsets of one blob are two words
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " glyph-of"))
        assert c == 1 and "bad word" in m, (c, m)
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " word-of Item.B"))
        assert c == 1 and "bad word" in m, (c, m)   # red: a blob word with no byte offset
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " glyph-of Item.B@4"))
        assert c == 1 and "bad word" in m, (c, m)   # red: an offset on a field that is not a blob
        # at-of (inc-cjos0 9f-pre P5b): an element of an index-of array holds a value family; the index must be a member
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " index-of Item.S")
                   + fam("fb", "#define FB_A 1\n", stored + " at-of Item.S[FA_A]+Item.S[FA_B]"))
        assert c == 1 and "FA_B is not a member of family fa" in m, (c, m)   # red: an unknown index name
        c, m = run(fam("fa", "#define FA_A 1\n#define FA_B 2\n", stored + " index-of Item.S")
                   + fam("fb", "#define FB_A 1\n", stored + " at-of Item.S[FA_A]+Item.S[FA_B]"))
        assert c == 0, (c, m)
        fams, problems = load_families(files=[os.path.join(tmp, "d%d.h" % n[0])])
        assert fams["fb"]["at_of"] == ["Item.S[FA_A]", "Item.S[FA_B]"], fams
        c, m = run(fam("fb", "#define FB_A 1\n", stored + " at-of Item.S[FA_A]"))
        assert c == 1 and "no family says 'index-of Item.S'" in m, (c, m)   # red: the array has no index family
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " index-of Item.S")
                   + fam("fb", "#define FB_A 1\n", stored + " at-of Item.S[FA_A]")
                   + fam("fc", "#define FC_A 1\n", stored + " at-of Item.S[FA_A]"))
        assert c == 1 and "Item.S[FA_A] is claimed by both" in m, (c, m)   # red: one element, two families
        c, m = run(fam("fa", "#define FA_A 1\n", stored + " index-of Item.S") + fam("fb", "#define FB_A 1\n", stored + " at-of Item.S"))
        assert c == 1 and "bad word" in m, (c, m)   # red: no index name
        # saved_field_problems: a claimed name must match a FIELD_ / V1EmbedBegin literal (9f-pre P3)
        sroot = os.path.join(tmp, "sroot")
        os.makedirs(os.path.join(sroot, "inc"), exist_ok=True)
        os.makedirs(os.path.join(sroot, "src"), exist_ok=True)
        with open(os.path.join(sroot, "inc", "k.h"), "w") as f:
            f.write('class Foo { ARCHIVE_CLASS(Foo,Bar,r)\n FIELD_I8("Dir", Dir);\n FIELD_OBJ("ts", ts);\n END_ARCHIVE };\n'
                    'class Baz { ARCHIVE_CLASS(Baz,Bar,r)\n FIELD_I8("Other", o);\n END_ARCHIVE };\n')
        with open(os.path.join(sroot, "src", "k.cpp"), "w") as f:
            f.write('void g() { r.V1EmbedBegin_AT("t", i, &t, 4); FIELD_I32("t_type", x); }\n')
        def sf(key, kind="field_of"):
            return saved_field_problems({"fa": {"field_of": [], "index_of": [], "elem_of": [], kind: [key]}}, sroot)
        assert sf("Foo.Dir") == [] and sf("Foo.ts.t.t_type") == [] and sf("Envelope.Type") == []
        assert "Foo.Dirr" in sf("Foo.Dirr")[0] and "declares Dirr" in sf("Foo.Dirr")[0]   # red: a misspelt field
        assert "declares Dir" in sf("Baz.Dir")[0]   # red: a field of another class
        assert "not a class" in sf("Nope.Dir")[0]   # red: no such class
        assert "declares tt" in sf("Foo.ts.tt.t_type")[0]   # red: a misspelt embed
        assert len(sf("Foo.Dirr", "elem_of")) == 1 and len(sf("Foo.Dirr", "index_of")) == 1
        assert sf("Foo.Dir", "glyph_of") == [] and sf("Foo.ts.t.t_type@4", "word_of") == []
        assert len(sf("Foo.Dirr", "glyph_of")) == 1 and len(sf("Foo.Dirr@4", "word_of")) == 1   # red: a misspelt field
        # a function-like macro inside a STORED family is refused, naming file:line and
        # family; in an internal family or a no-family block it is left alone (F07)
        c, m = run(fam("a", "#define A_X 1\n#define A_F() 1\n", stored))
        assert c == 1 and "function-like macro A_F" in m and ".h:3" in m \
            and "stored family a" in m, (c, m)
        c, m = run(fam("a", "#define A_X 1\n#define A_G(x) \\\n  ((x) + 1)\n", stored))
        assert c == 1 and "A_G" in m and "line 3" in m, (c, m)
        assert run(fam("a", "#define A_X 1\n#define A_F() 1\n", "internal"))[0] == 0
        assert run(fam("a", "#define A_X 1\n", stored)
                   + "// no-family\n#define A_F() 1\n// end no-family\n")[0] == 0
        # valid classified file: green
        good = ("// family: a stored bits u16, b internal\n#define M_X 1\n#define M_Y 2\n"
                "// end family: a, b\n"
                + fam("e", "typedef enum { E_A, E_B, E_C = 10, E_D, E_NEG = -1, E_LAST = 50 } E;\n",
                      "stored enum i32 sentinel E_LAST"))
        c, m = run(good)
        assert c == 0 and "PASS (3 families" in m, (c, m)
        # enumerators count as the compiler counts them
        d = os.path.join(tmp, "enum.h")
        with open(d, "w") as f:
            f.write("// no-family\n#define BASE 5\n// end no-family\n" + fam("e", "enum { E_A, E_B = BASE, E_C, E_D = E_C + 3, E_E,\n"
                                              "  E_F /* last */ };\n", "stored enum u8"))
        fams, problems = load_families(files=[d])
        assert problems == [], problems
        assert dict((n, v) for n, v, _f, _l in fams["e"]["members"]) == {
            "E_A": 0, "E_B": 5, "E_C": 6, "E_D": 9, "E_E": 10, "E_F": 11}, fams["e"]
        assert fams["e"]["class"] == "stored" and fams["e"]["shape"] == "enum" \
            and fams["e"]["width"] == "u8" and fams["e"]["members"][5][3] == 6, fams["e"]
        # two enumerators of one value: duplicate rule applies to enum families
        c, m = run(fam("e", "enum { E_A, E_B = 0 };\n", "stored enum u8"))
        assert c == 1 and "E_A E_B all = 0" in m, (c, m)
        # shape and member kind must agree
        c, m = run(fam("e", "#define E_A 1\n", "stored enum u8"))
        assert c == 1 and "shape enum but holds a #define" in m, (c, m)
        c, m = run(fam("a", "enum { A_X };\n", stored))
        assert c == 1 and "holds an enumerator" in m, (c, m)
        # an enum outside every block is ignored; so is a define outside a block in a
        # file that is not the first (only the first file is strict)
        first = os.path.join(tmp, "first.h")
        second = os.path.join(tmp, "second.h")
        with open(first, "w") as f:
            f.write(fam("a", "#define A_X 1\n", stored))
        with open(second, "w") as f:
            f.write("enum { LOOSE_E = 3 };\n#define LOOSE_D 4\n#define LOOSE_X UNKNOWN + 1\n"
                    + fam("b", "#define B_X 1\n", "internal"))
        c, m = check(first, [second])
        assert c == 0, (c, m)
        third = os.path.join(tmp, "third.h")
        with open(third, "w") as f:
            f.write("#define LOOSE_D 4\n" + fam("b", "#define B_X 1\n"))
        c, m = check(third, [first])
        assert c == 1 and "LOOSE_D is outside" in "\n".join(m), (c, m)
        # one family across two files: classes must agree, members join
        with open(second, "w") as f:
            f.write(fam("a", "#define A_Y 1\n", stored))
        c, m = check(first, [second])
        assert c == 1 and "family a: A_X A_Y all = 1" in "\n".join(m), (c, m)
        with open(second, "w") as f:
            f.write(fam("a", "#define A_Y 2\n", "stored bits u8"))
        c, m = check(first, [second])
        assert c == 1 and "family a says" in "\n".join(m), (c, m)
        # an unevaluable define inside a block of a later file still exits 2
        with open(second, "w") as f:
            f.write(fam("c", "#define C_X UNKNOWN + 1\n"))
        c, m = check(first, [second])
        assert c == 2 and "second.h" in "\n".join(m), (c, m)
        # k. rule 5 (F06): every constant of every file sits in a block or the baseline
        anchor = os.path.join(tmp, "anchor.h")
        with open(anchor, "w") as f:
            f.write(fam("a", "#define A_X 1\n"))

        def loose_run(text, baseline=(), base_keys=None, nf=(), nf_base=None):
            n[0] += 1
            path = os.path.join(tmp, "L%d.h" % n[0])
            with open(path, "w") as f:
                f.write(text)
            bl = {(rel(path), name): "define" for name in baseline}
            nbl = {(rel(path), name): "define" for name in nf}
            if callable(base_keys):
                base_keys = base_keys(rel(path))
            if callable(nf_base):
                nf_base = nf_base(rel(path))
            code, msgs = check(anchor, [path], ([anchor, path], bl, base_keys, nbl, nf_base))
            return code, "\n".join(msgs), path
        c, m, _p = loose_run("#define NEWD 61\n")
        assert c == 1 and "L%d.h line 1: unclassified constant NEWD (#define)" % n[0] in m, (c, m)
        c, m, _p = loose_run("\n  #define NEWI 61\n")  # indented, as inside a class
        assert c == 1 and "line 2: unclassified constant NEWI" in m, (c, m)
        c, m, _p = loose_run("enum { NEWE = 3, NEWF };\n")
        assert c == 1 and "NEWE (enum member)" in m and "NEWF (enum member)" in m, (c, m)
        c, m, _p = loose_run("const int NEWC = 5;\n")
        assert c == 1 and "NEWC (const variable)" in m, (c, m)
        for decl in ("static const uint16 NEWC = 5;", "constexpr int NEWC = 5;",
                     "const unsigned long NEWC = 5;", "class K { static const int NEWC = 2; };",
                     "namespace N { const int NEWC = 2; }", "const static int NEWC = 2;"):
            c, m, _p = loose_run(decl + "\n")
            assert c == 1 and "NEWC (const variable)" in m, (decl, c, m)
        # not a constant: a function-local const, a default argument, a string, an array,
        # a function-like macro, a type alias, a call
        for text in ("void f() { const int LOC = 3; }\n",
                     "struct S { void f() { const int LOC = 3; } };\n",
                     "void g(const int d = 4);\n", "const char *NAME = \"x\";\n",
                     "static const int TAB[2] = {1, 2};\n", "#define MAC(x) ((x) + 1)\n",
                     "#define TYPE unsigned char\n", "#define CALL foo(3)\n",
                     "#define STR \"a\"\n", "#define EMPTY\n"):
            c, m, _p = loose_run(text)
            assert c == 0, (text, c, m)
        # `#if 0` text is skipped; an `#else` restarts from the `#if`
        c, m, _p = loose_run("#if 0\nstruct S {\n#endif\nconst int ZZ = 1;\n")
        assert c == 1 and "ZZ (const variable)" in m, (c, m)
        c, m, _p = loose_run("#ifdef X\nvoid f() {\n#else\nvoid g() {\n#endif\n}\n"
                             "const int YY = 1;\n")
        assert c == 1 and "YY (const variable)" in m, (c, m)
        # an unbalanced file cannot place a const variable: exit 2
        c, m, _p = loose_run("void f() {\n")
        assert c == 2 and "UNMEASURED" in m and "never closed" in m, (c, m)
        # green: a baseline constant, on any line (the key holds no line number)
        c, m, _p = loose_run("#define NEWD 61\n", ["NEWD"])
        assert c == 0 and "1 baseline constants" in m, (c, m)
        c, m, _p = loose_run("\n\n\n#define NEWD 61\n", ["NEWD"])
        assert c == 0, (c, m)
        # red: a renamed baseline constant is a new constant
        c, m, _p = loose_run("#define NEWD2 61\n", ["NEWD"])
        assert c == 1 and "unclassified constant NEWD2" in m, (c, m)
        # green: the same constant inside a no-family block, or a family block
        c, m, _p = loose_run("// no-family\n#define NEWD 61\nenum { NEWE };\n"
                             "const int NEWC = 5;\n// end no-family\n", nf=["NEWD", "NEWE"])
        assert c == 0, (c, m)
        c, m, _p = loose_run(fam("b", "#define B_X 61\n"))
        assert c == 0, (c, m)
        # red: a baseline that gained an entry against the base; green when it did not
        c, m, p = loose_run("#define NEWD 61\n", ["NEWD"], set())
        assert c == 1 and "gained the entry" in m and "NEWD" in m, (c, m)
        c, m, p = loose_run("#define NEWD 61\n", ["NEWD"],
                            lambda r: {(r, "NEWD"), ("x.h", "GONE")})
        assert c == 0, (c, m)
        # rule 4 baseline (inc-x39wn): a no-family define the baseline does not list is red; listed is green
        nfblock = "// no-family\n#define NEWD 61\n// end no-family\n"
        c, m, _p = loose_run(nfblock)
        assert c == 1 and "NEWD is a no-family define that tools/nofamily_baseline.txt does not list" in m, (c, m)
        c, m, _p = loose_run(nfblock, nf=["NEWD"])
        assert c == 0 and "1 no-family baseline" in m, (c, m)
        # red: a renamed baseline define is a new define
        c, m, _p = loose_run("// no-family\n#define NEWD2 61\n// end no-family\n", nf=["NEWD"])
        assert c == 1 and "NEWD2 is a no-family define" in m, (c, m)
        # red: the no-family baseline gained an entry against the base; green when master has it
        c, m, _p = loose_run(nfblock, nf=["NEWD"], nf_base=set())
        assert c == 1 and "tools/nofamily_baseline.txt gained the entry" in m and "NEWD" in m, (c, m)
        c, m, _p = loose_run(nfblock, nf=["NEWD"], nf_base=lambda r: {(r, "NEWD"), ("x.h", "GONE")})
        assert c == 0, (c, m)
        # the prefix rule and the baseline are independent: a listed define with a family's prefix is still red
        c, m, _p = loose_run("// no-family\n#define A_NEW 61\n// end no-family\n", nf=["A_NEW"])
        assert c == 1 and "A_NEW sits in a no-family block" in m, (c, m)
        c, m, _p = loose_run("// no-family\n#define A_NEW 61 /* not a code: x */\n// end no-family\n", nf=["A_NEW"])
        assert c == 0, (c, m)
        # the base baseline comes from git: a scratch repo whose master holds the file
        repo = os.path.join(tmp, "repo")
        os.makedirs(os.path.join(repo, "tools"))

        def git(*a):
            r = subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t",
                                "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"]
                               + list(a), capture_output=True, text=True)
            assert r.returncode == 0, (a, r.stderr)
        git("init", "-q", "-b", "master")
        with open(os.path.join(repo, BASELINE_REL), "w") as f:
            f.write("# c\na.h\tONE\tdefine\nb.h\tTWO\tenum\n")
        git("add", "."); git("commit", "-q", "-m", "base")
        assert master_baseline_keys(repo) == {("a.h", "ONE"), ("b.h", "TWO")}
        git("checkout", "-q", "-b", "work")
        os.remove(os.path.join(repo, BASELINE_REL))
        git("add", "-A"); git("commit", "-q", "-m", "drop")
        assert master_baseline_keys(repo) == {("a.h", "ONE"), ("b.h", "TWO")}  # master, not HEAD
        assert master_baseline_keys(repo, relpath="tools/none.txt") is None  # first landing
        try:
            master_baseline_keys(repo, ref="nope")
            assert False, "a missing ref must exit 2"
        except Unmeasurable:
            pass
        assert master_baseline_keys(tmp) is None  # not a git checkout: no ratchet
        bad_bl = os.path.join(tmp, "bad.txt")
        with open(bad_bl, "w") as f:
            f.write("a.h\tONE\n")
        try:
            load_baseline(bad_bl)
            assert False, "a bad baseline line must exit 2"
        except Unmeasurable:
            pass
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("check_define_dups: selftest PASS")
    return 0


def main(argv):
    defines, st, only = DEF_DEFAULT, False, False
    it = iter(argv)
    for a in it:
        if a == "--defines":
            defines = next(it, None)
            if defines is None:
                print("--defines needs a file", file=sys.stderr)
                return 2
            only = True
        elif a == "--selftest":
            st = True
        else:
            print(__doc__.split("Usage:")[1].split("Exit:")[0], file=sys.stderr)
            return 2
    if st:
        return selftest()
    loose = None
    if not only:
        try:
            loose = (source_files(), load_baseline(), master_baseline_keys(),
                     load_baseline(NOFAM_BASELINE),
                     master_baseline_keys(relpath=NOFAM_REL))
        except Unmeasurable as e:
            print("check_define_dups: UNMEASURED: %s" % e, file=sys.stderr)
            return 2
    code, msgs = check(defines, [] if only else marked_files(), loose)
    print("\n".join(msgs), file=sys.stderr if code else sys.stdout)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
