#!/usr/bin/env python3
"""Compare every script API declaration in inc/Api.h with the real C++ one.

WHY THIS EXISTS. inc/Api.h declares the script-callable API in its own syntax.
The resource compiler turns it into lib/dispatch.h, which is real C++ that calls
the real method. Nothing checks that the two agree. When they disagree about
parameters, the generated call still COMPILES, because the trailing C++
parameters carry default arguments -- so the script's argument silently binds to
the wrong parameter and the one it meant to set keeps its default.

The instance that produced this tool (inc-xkd):

    inc/Api.h:122     system bool T_MAP::FindOpenAreas(Rect Area, uint16 Flags=0);
    inc/Map.h:359     bool FindOpenAreas(Rect r, rID regID=0, int16 Flags=0);

The script's second argument is its Flags. In C++ it lands in regID. Tree Stride
asks for trees-only, the engine hears "region 128", nothing matches, and the
spell fails for any caster not already standing under a tree. No warning, ever.

WHAT IS REPORTED, and the discriminator matters more than the counts.

A C++ method may legitimately carry trailing defaulted parameters that the
script does not expose. MoveDepth is the benign shape:

    inc/Api.h:226     system void T_THING::MoveDepth(int16 NewDepth);
    inc/Map.h:712     virtual void MoveDepth(int16 NewDepth, bool safe=false);

The script's one argument binds to NewDepth, exactly as intended, and `safe`
takes its default. Counting parameters alone calls that a defect. It is not.

What separates it from FindOpenAreas is POSITIONAL NAMES. Compare the script's
parameters against the C++ ones one slot at a time, over however many they
share:

    MoveDepth        script [NewDepth]      C++ [NewDepth, safe]    slot 1 agrees
    FindOpenAreas    script [Area, Flags]   C++ [r, regID, Flags]   slot 2: the
                     script says Flags, the C++ says regID          DISAGREES

So the report is:

  MISALIGNED   a slot where both sides name the parameter and the names differ.
               This is the defect. The script's argument is landing somewhere
               the script did not mean.
  extra-only   the shared slots all agree and C++ merely has more, all
               defaulted. Benign by design; shown with --all.

Names carry the intent, so a pure rename on one side is a false positive. Read
each hit. This tool reports and does not judge: it exits 0 unless it could parse
nothing at all.

USAGE
    tools/check_api_arity.py            report every disagreement
    tools/check_api_arity.py --all      also list the pairs that agree
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The script's type names to the C++ classes that implement them. Read from the
# dispatch macros in lib/dispatch.h (oMap, oCreature ...) and from the class
# declarations themselves.
CLASS_MAP = {
    "T_OBJECT": "Object",
    "T_THING": "Thing",
    "T_MAP": "Map",
    "T_CREATURE": "Creature",
    "T_CHARACTER": "Character",
    "T_PLAYER": "Player",
    "T_MONSTER": "Monster",
    "T_ITEM": "Item",
    "T_CONTAIN": "Container",
    "T_FEATURE": "Feature",
    "T_DOOR": "Door",
    "T_TRAP": "Trap",
    "T_PORTAL": "Portal",
    "T_GAME": "Game",
    "T_TERM": "Term",
    "T_EVENTINFO": "EventInfo",
    "T_TMONSTER": "TMonster",
    "T_TITEM": "TItem",
    "T_TEFFECT": "TEffect",
    "T_TTERRAIN": "TTerrain",
    "T_TREGION": "TRegion",
    "T_TFEATURE": "TFeature",
    "T_TDUNGEON": "TDungeon",
    "T_TTEMPLATE": "TTemplate",
    "T_TRACE": "TRace",
}

# Script-side types that are spelled differently in C++. Only used to keep the
# name comparison from firing on a pure spelling difference.
API_DECL = re.compile(
    r"^system\s+[A-Za-z_0-9:]+\s*\*?\s*(T_[A-Z_]+)::([A-Za-z_0-9]+)\s*\((.*?)\)\s*;"
)


def split_params(text):
    """Split a parameter list on commas that are not inside brackets."""
    out, depth, cur = [], 0, ""
    for ch in text:
        if ch in "([<":
            depth += 1
        elif ch in ")]>":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [p.strip() for p in out if p.strip()]


def param_name(p):
    """The declared name of one parameter, or '' when it has none.

    Handles 'int16 x', 'int16 fl=0', 'hObj:T_PLAYER' (script side, unnamed),
    and 'const char *s'.
    """
    p = p.split("=")[0].strip()
    p = p.split(":")[0].strip()          # script's 'hObj:T_PLAYER' form
    m = re.search(r"([A-Za-z_][A-Za-z_0-9]*)\s*(\[\s*\])?$", p)
    if not m:
        return ""
    name = m.group(1)
    # A bare type with no name: 'Rect', 'hObj', 'int16'.
    if name == p.replace("*", "").replace("&", "").strip():
        return ""
    return name


def has_default(p):
    return "=" in p


def norm(name):
    """Compare names without punishing house style.

    The C++ side often writes a parameter as _m, _x or _y where the script
    writes m, x, y. That is the same intent spelled differently, so it must not
    read as a misalignment.
    """
    return name.lstrip("_").lower()


# The type classes that actually carry meaning. Names are style; types are
# semantics, and this is what separates FindOpenAreas from a rename:
#
#   FindOpenAreas slot 2   script uint16   C++ rID     -> different classes
#   LineOfFire    slot 1   script int16    C++ int16   -> same class, just named
#                                                          x on one side, sx on
#                                                          the other
#
# rID is deliberately NOT lumped in with the integers. It is a uint32
# underneath, which is exactly why the compiler cannot see the defect: a
# resource id and a flags word are indistinguishable to it and completely
# different to the game.
INT_TYPES = {
    "int8", "int16", "int32", "int64",
    "uint8", "uint16", "uint32", "uint64",
    "char", "short", "long", "int", "dir", "evreturn",
}

# Spellings of one type on the two sides. Api.h's '#define GlyphType uint32'
# (inc/Api.h:22) is the C++ Glyph; without this every glyph parameter reads as a
# disagreement.
SAME_TYPE = {"glyphtype": "glyph"}


def type_class(p):
    """Reduce one parameter declaration to the class of thing it carries."""
    t = p.split("=")[0].strip()
    t = re.sub(r"\b(const|static|register|virtual|inline)\b", " ", t)

    # Classify by the BASE type, before any pointer or reference marker. The
    # script writes 'Rect r' where C++ writes 'Rect &r'; that is one type passed
    # two ways, not two types. Getting this order wrong reports all eighteen
    # Write* map builders as defects.
    indirect = "*" in t or "&" in t
    t = t.replace("*", " ").replace("&", " ")

    words = [w for w in re.split(r"[\s]+", t) if w]
    if not words:
        return "?"
    base = words[0].lower().split(":")[0]

    if base in ("rect", "dice"):
        return base
    if base in ("string", "char") and (indirect or base == "string"):
        return "string"
    if base == "hobj":
        return "handle"
    if base == "rid":
        return "rid"
    if base == "bool":
        return "bool"
    if base in INT_TYPES:
        return "int"
    base = SAME_TYPE.get(base, base)
    if base in INT_TYPES:
        return "int"
    # A pointer to anything else is an object handle on the C++ side.
    return "handle" if indirect else base


def parse_api(path):
    decls = []
    for n, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        m = API_DECL.match(line.strip())
        if m:
            cls, name, params = m.groups()
            decls.append((n, cls, name, split_params(params), line.strip()))
    return decls


def cpp_declarations(headers):
    """Every 'name(params)' declaration in the headers, by method name.

    Deliberately loose: it collects candidates, and the caller narrows them by
    which class body they fall inside. A declaration split over two lines is
    joined first, because several in inc/Creature.h are.
    """
    found = {}
    for path in headers:
        text = path.read_text(errors="replace")
        # Join a declaration that wraps: '(' with no ')' before end of line.
        text = re.sub(r"\(([^)\n]*)\n\s*", r"(\1 ", text)
        class_at = []
        for n, line in enumerate(text.splitlines(), 1):
            cm = re.match(r"\s*class\s+([A-Za-z_0-9]+)", line)
            if cm:
                class_at.append((n, cm.group(1)))
            dm = re.match(
                # The trailing part is optional: several declarations in
                # inc/Map.h put the opening brace on the NEXT line, and
                # requiring it here hid Thing::DirTo(Thing*) at inc/Map.h:748.
                # A DECLARATION HAS A RETURN TYPE. Requiring at least one word
                # before the name is what separates
                #   int8 Exercise(int16 at, ...)      a declaration
                # from
                #   Exercise(at, -amt, 0, 0);         a call, inc/Creature.h:212
                r"\s*(?:virtual\s+|inline\s+|static\s+)*"
                r"[A-Za-z_][A-Za-z_0-9:<>]*[\s\*&]+"
                r"\b([A-Za-z_][A-Za-z_0-9]*)\s*\((.*?)\)\s*(?:const)?\s*[;{=]?\s*$",
                line,
            )
            if not dm:
                continue
            name, params = dm.groups()
            if name in ("if", "for", "while", "switch", "return", "sizeof"):
                continue
            # A CALL is not a declaration. Creature.h:240 holds
            # 'return HasMFlag(M_BLIND) || HasStati(BLIND);', which otherwise
            # reads as a one-parameter declaration of HasMFlag.
            if re.match(r"\s*(return|\}|else)\b", line):
                continue
            enclosing = class_at[-1][1] if class_at else ""
            found.setdefault(name, []).append(
                (path.name, n, enclosing, split_params(params), line.strip())
            )
    return found


def main():
    show_all = "--all" in sys.argv
    api_path = ROOT / "inc" / "Api.h"
    # Api.h is the thing under test, not evidence about C++. Leaving it in the
    # scan makes the free-function forms in it (Left(String s, int32 sz)) look
    # like the C++ declaration of the method forms (T_STRING::Left(int32 sz)).
    headers = [p for p in sorted((ROOT / "inc").glob("*.h")) if p.name != "Api.h"]

    api = parse_api(api_path)
    cpp = cpp_declarations(headers)

    if not api:
        print("check_api_arity: parsed nothing out of inc/Api.h", file=sys.stderr)
        return 1

    misaligned, extra_only, unmatched, agreed = [], [], [], 0

    for line_no, cls, name, params, raw in api:
        want_class = CLASS_MAP.get(cls)
        cands = cpp.get(name, [])
        if want_class:
            narrowed = [c for c in cands if c[2] == want_class]
            if narrowed:
                cands = narrowed
        if not cands:
            unmatched.append((line_no, cls, name, raw))
            continue

        # OVERLOADS, and this selection rule is the difference between a useful
        # report and a noisy one. Creature declares BOTH
        #   WepSkill(rID wep, bool ignore_str=false)
        #   WepSkill(Item *it)
        # and the script calls the first. Picking by parameter count alone lands
        # on the second and reports a defect that does not exist. Pick instead
        # the overload the script's arguments FIT BEST -- fewest type-class
        # disagreements -- and only then ask whether even that one misaligns.
        api_types = [type_class(p) for p in params]

        def misfit(cand):
            ct = [type_class(p) for p in cand[3]]
            shared = min(len(api_types), len(ct))
            bad = sum(1 for i in range(shared) if api_types[i] != ct[i])
            # A count difference is a weaker signal than a type clash, so it
            # only breaks ties.
            return (bad, abs(len(ct) - len(params)))

        fname, fline, fclass, fparams, fraw = min(cands, key=misfit)

        api_names = [norm(param_name(p)) for p in params]
        cpp_names = [norm(param_name(p)) for p in fparams]
        cpp_types = [type_class(p) for p in fparams]

        # Compare slot by slot over however many the two sides share, on TYPE.
        # A differing name is house style; a differing type class means the slot
        # carries a different kind of thing on each side, which is the defect.
        shared = min(len(params), len(fparams))
        mismatched = [
            (i + 1, api_types[i], cpp_types[i], api_names[i], cpp_names[i])
            for i in range(shared)
            if api_types[i] != cpp_types[i]
        ]

        if mismatched:
            misaligned.append(
                (line_no, cls, name, raw, fname, fline, fraw,
                 len(params), len(fparams), mismatched)
            )
        elif len(params) != len(fparams):
            surplus = fparams[len(params):]
            extra_only.append(
                (line_no, cls, name, raw, fname, fline, fraw,
                 len(params), len(fparams),
                 all(has_default(p) for p in surplus) if surplus else False)
            )
        else:
            agreed += 1

    print(f"inc/Api.h: {len(api)} method declarations checked against inc/*.h")
    print(f"  every shared slot agrees:            {agreed}")
    print(f"  MISALIGNED, a slot means two things: {len(misaligned)}")
    print(f"  C++ has extra trailing params only:  {len(extra_only)}")
    print(f"  no C++ declaration found to compare: {len(unmatched)}")
    print()

    if misaligned:
        print("=== MISALIGNED: a script argument lands in the wrong parameter ===")
        print("The script names a slot one thing and the C++ names it another, so")
        print("the value goes somewhere the script did not intend. Default")
        print("arguments keep the compiler silent about all of it.")
        print()
        for (ln, cls, nm, raw, fn, fl, fraw, na, nc, mism) in misaligned:
            where = "; ".join(
                f"slot {i}: script {at} '{an}' vs C++ {ct} '{cn}'"
                for i, at, ct, an, cn in mism
            )
            print(f"{cls}::{nm}   script {na} params, C++ {nc}")
            print(f"    {where}")
            print(f"    inc/Api.h:{ln}   {raw}")
            print(f"    inc/{fn}:{fl}   {fraw}")
            print()

    if show_all and extra_only:
        print("=== C++ HAS EXTRA TRAILING PARAMETERS, shared slots agree ===")
        print("Benign by design: the script does not expose an option that")
        print("defaults. Listed so a future change to one of them is visible.")
        print()
        for (ln, cls, nm, raw, fn, fl, fraw, na, nc, defaulted) in extra_only:
            note = "" if defaulted else "   <-- surplus is NOT all defaulted"
            print(f"    {cls}::{nm}  script {na}, C++ {nc}{note}")
            print(f"      inc/Api.h:{ln}   {raw}")
            print(f"      inc/{fn}:{fl}   {fraw}")

    if show_all and unmatched:
        print("=== NO C++ DECLARATION FOUND ===")
        print("Not necessarily a defect: the method may be declared in a form this")
        print("tool does not parse, or on a class it could not map.")
        print()
        for (ln, cls, nm, raw) in unmatched:
            print(f"    inc/Api.h:{ln}   {cls}::{nm}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
