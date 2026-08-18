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

The comparison is on the TYPE CLASS of each slot, not on the name: a name
difference is house style ('fl' against 'flags'), while a slot that is an
integer to the script and an rID to the C++ is the defect the compiler cannot
see. `norm()` and the name columns survive only to make the report readable.

THIS IS A GATE, AND IT CAN FAIL. It used to return 0 on every path, printing
two MISALIGNED slots and exiting green, so anything running it as a gate got a
pass no matter what happened. It now compares what it finds against a checked-in
BASELINE of the misalignments we already know about and have filed.

    a MISALIGNED slot in the BASELINE   reported as KNOWN, tolerated
    a MISALIGNED slot not in it         FAIL: a new defect, or a real change
    a BASELINE entry that no longer
      misaligns, or whose types moved   FAIL: a stale suppression

The last one is the part usually forgotten, and it is how a gate rots: an entry
kept after its defect is gone quietly widens the hole for the next one.

WHY A BASELINE AND NOT A HARD ZERO. About a fifth of the declarations (94 of
460 at the time of writing) find no C++ declaration this parser can match, so a
clean run is not a clean bill of health, and the two known slots are separately
tracked engine bugs that are not this tool's to fix. The baseline makes the
tolerance explicit, dated and attributable instead of implicit in an exit code.

EXIT CODES
    0   every misalignment found is in the baseline, and every baseline entry
        still misaligns exactly as recorded
    1   a misalignment outside the baseline, a baseline entry whose slots moved,
        or a baseline entry that no longer fires
    2   the tool could not parse inc/Api.h, so it examined nothing

ADDING OR REMOVING A BASELINE ENTRY. Add one only for a misalignment that is
real, filed and deliberately not being fixed now: run the tool, copy the symbol
and the `slots` tuple it prints in the FAIL message, and give it the `issue` id
and a `why` that says what the defect is and why it is tolerated. Never add one
to silence a hit you have not read. Remove an entry the moment the tool reports
it stale -- that report means the underlying defect is fixed, and the entry is
now hiding the next one.

USAGE
    tools/check_api_arity.py            report every disagreement
    tools/check_api_arity.py --all      also list the pairs that agree
    tools/check_api_arity.py --selftest prove the baseline logic still fires
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# THE BASELINE. Every misalignment we already know about, have filed, and are
# deliberately not fixing in this tool's run. Anything else fails the run, and
# so does an entry here that stops firing. See the module docstring for how to
# add or remove one.
#
# key    "T_CLASS::Method" as inc/Api.h declares it
# slots  every misaligned slot, exactly as reported: (slot number counting from
#        1, the script's type class, the C++ type class). The types are part of
#        the key on purpose: if a slot starts disagreeing in a DIFFERENT way,
#        that is a new fact and must not inherit this entry's tolerance.
# issue  the bd id that tracks the underlying defect
# why    what the defect is, and why it is tolerated rather than fixed
BASELINE = {
    "T_MAP::FindOpenAreas": {
        "slots": ((2, "int", "rid"),),
        "issue": "inc-xkd",
        "why": (
            "The script's second argument is its Flags; in C++ it lands in "
            "regID. Live: Tree Stride asks for trees-only, the engine hears "
            "'region 128', and the spell fails for any caster not already "
            "standing under a tree. Fixing it means changing either inc/Api.h "
            "or Map::FindOpenAreas and every caller, which is an engine change "
            "tracked on its own bead, not a tooling change."
        ),
    },
    "T_MAP::SetGlyphAt": {
        "slots": ((3, "int", "glyph"),),
        "issue": "inc-upw.22",
        "why": (
            "Glyph is 32 bits; inc/Api.h declares the slot uint16, so the "
            "generated call truncates. Not live -- no script in lib/ calls "
            "SetGlyphAt -- which is why it is tolerated rather than urgent."
        ),
    },
}

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


def audit(found, baseline):
    """Compare what this run found against the checked-in baseline.

    `found` maps "T_CLASS::Method" to a tuple of misaligned slots, each
    (slot, api_type, cpp_type). Pure: it touches no files and no globals, which
    is what lets --selftest drive it with synthetic input.

    Returns (known, unexpected, changed, stale):
        known       symbols whose misalignment is exactly what the baseline records
        unexpected  symbols that misalign and are not in the baseline at all
        changed     baseline symbols that misalign in some OTHER way now
        stale       baseline symbols that do not misalign any more
    """
    known, unexpected, changed, stale = [], [], [], []
    for sym, slots in sorted(found.items()):
        entry = baseline.get(sym)
        if entry is None:
            unexpected.append(sym)
        elif tuple(entry["slots"]) == tuple(slots):
            known.append(sym)
        else:
            changed.append(sym)
    for sym in sorted(baseline):
        if sym not in found:
            stale.append(sym)
    return known, unexpected, changed, stale


def selftest():
    """Prove the baseline logic still fires. No framework, no fixtures.

    Same shape as tools/check_citations.sh --selftest and
    tools/check_upstream_marks.sh --selftest: synthetic inputs inline, one
    pass/fail line each, and an end-to-end run against the real tree at the end.
    """
    rc = 0

    def case(name, found, base, want):
        nonlocal rc
        got = tuple(tuple(x) for x in audit(found, base))
        if got == want:
            print(f"selftest ok    {name}")
        else:
            print(f"selftest FAIL  {name}\n  wanted: {want}\n  got:    {got}")
            rc = 1

    base = {
        "T_X::Known": {"slots": ((2, "int", "rid"),), "issue": "inc-000", "why": "x"},
    }
    exact = {"T_X::Known": ((2, "int", "rid"),)}

    case("baseline entry still fires -> known",
         exact, base, (("T_X::Known",), (), (), ()))
    case("a slot outside the baseline -> unexpected",
         {**exact, "T_Y::Fresh": ((1, "int", "string"),)}, base,
         (("T_X::Known",), ("T_Y::Fresh",), (), ()))
    case("a baseline entry that stopped firing -> stale",
         {}, base, ((), (), (), ("T_X::Known",)))
    case("a baseline entry that moved -> changed, not tolerated",
         {"T_X::Known": ((3, "int", "handle"),)}, base,
         ((), (), ("T_X::Known",), ()))
    case("empty baseline, empty run -> nothing at all",
         {}, {}, ((), (), (), ()))

    # End to end, against the real headers: the tree as it stands must pass,
    # otherwise the four cases above prove nothing about the wiring.
    real = main(["--quiet"])
    if real == 0:
        print("selftest ok    real tree passes                 -> exit 0")
    else:
        print(f"selftest FAIL  real tree passes                 -> exit {real}")
        rc = 1

    print()
    print("selftest: pass" if rc == 0 else "selftest: FAIL")
    return rc


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    show_all = "--all" in argv
    quiet = "--quiet" in argv
    api_path = ROOT / "inc" / "Api.h"
    # Api.h is the thing under test, not evidence about C++. Leaving it in the
    # scan makes the free-function forms in it (Left(String s, int32 sz)) look
    # like the C++ declaration of the method forms (T_STRING::Left(int32 sz)).
    headers = [p for p in sorted((ROOT / "inc").glob("*.h")) if p.name != "Api.h"]

    api = parse_api(api_path)
    cpp = cpp_declarations(headers)

    if not api:
        print("check_api_arity: parsed nothing out of inc/Api.h", file=sys.stderr)
        print("check_api_arity: nothing was examined, so this is not a pass",
              file=sys.stderr)
        return 2

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

    def say(*a):
        if not quiet:
            print(*a)

    # One record per misaligned symbol, in the shape the baseline stores. The
    # detail for the report is kept alongside, keyed the same way.
    found, detail = {}, {}
    for rec in misaligned:
        (ln, cls, nm, raw, fn, fl, fraw, na, nc, mism) = rec
        sym = f"{cls}::{nm}"
        # inc/Api.h should declare each method once. If it does not, do not let
        # the second one vanish into the first one's baseline tolerance -- give
        # it a key of its own so it reports as unexpected and fails the run.
        if sym in found:
            sym = f"{sym}@Api.h:{ln}"
        found[sym] = tuple((i, at, ct) for i, at, ct, an, cn in mism)
        detail[sym] = rec

    known, unexpected, changed, stale = audit(found, BASELINE)

    say(f"inc/Api.h: {len(api)} method declarations checked against inc/*.h")
    say(f"  every shared slot agrees:            {agreed}")
    say(f"  MISALIGNED, a slot means two things: {len(misaligned)}"
        f"   ({len(known)} known, {len(unexpected) + len(changed)} not)")
    say(f"  C++ has extra trailing params only:  {len(extra_only)}")
    say(f"  no C++ declaration found to compare: {len(unmatched)}")
    say()

    def show(sym, prefix=""):
        (ln, cls, nm, raw, fn, fl, fraw, na, nc, mism) = detail[sym]
        where = "; ".join(
            f"slot {i}: script {at} '{an}' vs C++ {ct} '{cn}'"
            for i, at, ct, an, cn in mism
        )
        say(f"{prefix}{cls}::{nm}   script {na} params, C++ {nc}")
        say(f"{prefix}    {where}")
        say(f"{prefix}    inc/Api.h:{ln}   {raw}")
        say(f"{prefix}    inc/{fn}:{fl}   {fraw}")
        say()

    if unexpected or changed:
        say("=== MISALIGNED, AND NOT IN THE BASELINE ===")
        say("The script names a slot one kind of thing and the C++ names it")
        say("another, so the value goes somewhere the script did not intend.")
        say("Default arguments keep the compiler silent about all of it. Read")
        say("each one: fix it, or file it and add a BASELINE entry saying why")
        say("it is tolerated.")
        say()
        for sym in unexpected:
            show(sym)
        for sym in changed:
            say(f"{sym} IS in the baseline, but not with these slots.")
            say(f"    baseline records: {tuple(BASELINE[sym]['slots'])}")
            say(f"    this run found:   {found[sym]}")
            say("    A slot that disagrees in a new way is a new fact. Read it,")
            say("    then update the entry deliberately.")
            say()
            show(sym, "    ")

    if stale:
        say("=== STALE BASELINE ENTRIES ===")
        say("These are recorded as known misalignments and no longer misalign.")
        say("The defect is fixed, or the parser stopped matching the C++")
        say("declaration. Either way the entry is now a suppression covering")
        say("nothing, and the next real defect would hide behind it. Delete it,")
        say("or find out why the tool stopped seeing it.")
        say()
        for sym in stale:
            say(f"    {sym}   (baseline cites {BASELINE[sym]['issue']})")
        say()

    if known:
        say("=== MISALIGNED, KNOWN AND TOLERATED ===")
        say("In the baseline, with a tracked issue. Not a pass for the defect --")
        say("only a statement that this run found nothing new about it.")
        say()
        for sym in known:
            say(f"    {sym}   {BASELINE[sym]['issue']}")
            show(sym, "    ")

    if show_all and extra_only:
        say("=== C++ HAS EXTRA TRAILING PARAMETERS, shared slots agree ===")
        say("Benign by design: the script does not expose an option that")
        say("defaults. Listed so a future change to one of them is visible.")
        say()
        for (ln, cls, nm, raw, fn, fl, fraw, na, nc, defaulted) in extra_only:
            note = "" if defaulted else "   <-- surplus is NOT all defaulted"
            say(f"    {cls}::{nm}  script {na}, C++ {nc}{note}")
            say(f"      inc/Api.h:{ln}   {raw}")
            say(f"      inc/{fn}:{fl}   {fraw}")

    if show_all and unmatched:
        say("=== NO C++ DECLARATION FOUND ===")
        say("Not necessarily a defect: the method may be declared in a form this")
        say("tool does not parse, or on a class it could not map.")
        say()
        for (ln, cls, nm, raw) in unmatched:
            say(f"    inc/Api.h:{ln}   {cls}::{nm}")

    if unexpected or changed or stale:
        say(f"FAIL: {len(unexpected)} misalignment(s) outside the baseline, "
            f"{len(changed)} changed, {len(stale)} stale entr(ies).")
        return 1
    say(f"PASS: every misalignment found ({len(known)}) is in the baseline, "
        f"and every baseline entry still fires.")
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    sys.exit(main())
