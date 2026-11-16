#!/usr/bin/env python3
# gate: cheap
# gate-fast: reads the files of inc/ and src/ that hold a family mark; well under 1 s
# fact: family members -- the marked #define and enum text of inc/ and src/, read by tools/check_define_dups.py load_families; no game run, no seed
# fact: which name a shared value prints as -- the first member of the family in file order; an alias line never goes first
"""Write the value -> name table the field-value observer prints (bead inc-cjos0, phase 8, D3).

WHY. tools/pressure/field_values.sh shows what each saved member holds. A status number, a skill index
or a feat bit is only a number to it; the same 251 can name one status on one branch and another on
the next. The observer (src/SaveV1.cpp, INCURSION_FIELD_VALUES) prints `251(AC8_RACE_A)` so a change of
meaning shows as a changed line. The names come from the family marks of inc/Defines.h on every build,
never from a hand table.

WRITES (default build/gen/FamilyNames.h):
    #define FAMNAMES_MEASURED 1
    static const FamName FamNames_<family>[] = { {value, "NAME"}, ... };
    static const int FamNames_<family>_n = N;
for every family classed `stored`, then v1FamTabsGen[], the table of tables (with a bits flag per family),
then v1StatSlotsGen[]: status number -> the family of its val and of its mag, from the `val-of` and `mag-of`
attributes of the marks (a status with no row holds a plain number in val and mag), then v1FieldFamsGen[]: saved field -> family and mode, then v1AtFamsGen[]: array element -> family (`at-of`). Without python3 the build writes no header and the
observer prints bare numbers; the planter then refuses every name.

USAGE  gen_family_names.py [--out FILE]
Exit: 0 written; 2 the family marks could not be read.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_define_dups as cdd  # noqa: E402

# every family the define-dup check classes `stored` gets a table; no hand list
# families that continue a wanted family's number line under the same table (skills 800 and up)
ALSO = {"sk": ["sk_high_first"]}


def build_text():
    fams, problems = cdd.load_families()
    bad = cdd.saved_field_problems(fams)   # a mark naming a field the writer never emits stops the build
    if bad:
        raise cdd.Unmeasurable("; ".join(bad))
    out = ["// written by tools/gen_family_names.py on every build; do not edit",
           "#define FAMNAMES_MEASURED 1",
           "struct FamName { int value; const char *name; };",
           "struct V1FamTab { const char *fam; const struct FamName *rows; int n; int bits; int wbits; int sgn; };",
           "struct V1FieldFam { const char *key; const char *fam; int mode; };",
           "struct V1StatSlot { int stati; const char *valFam; const char *magFam; };",
           "struct V1AtFam { const char *key; long idx; const char *fam; };"]
    wanted = [f for f, d in fams.items() if d["class"] == "stored"]
    if not wanted:
        raise cdd.Unmeasurable("no family is classed stored")
    for f in wanted:
        if not fams[f]["members"]:
            raise cdd.Unmeasurable("family %s has no members in the tree" % f)
        seen, rows = set(), []
        members = list(fams[f]["members"])
        for extra in ALSO.get(f, []):
            members += fams[extra]["members"] if extra in fams else []
        for name, value, _file, _line in members:
            # every name stays: the planter looks a name up (SOCIAL_MOD shares 234 with MAGIC_AURA); the number-to-name
            # lookup returns the first row of a value, so the name printed beside a value is unchanged
            if (int(value), name) in seen:
                continue
            seen.add((int(value), name))
            rows.append((int(value), name))
        out.append("static const FamName FamNames_%s[] = {" % f)
        out.append("    " + ",\n    ".join('{%d, "%s"}' % r for r in rows))
        out.append("};")
        out.append("static const int FamNames_%s_n = %d;" % (f, len(rows)))
    out.append("static const V1FamTab v1FamTabsGen[] = {")
    out.append(",\n".join('    { "%s", FamNames_%s, FamNames_%s_n, %d, %s, %d }'
                           % (f, f, f, fams[f]["shape"] == "bits", fams[f]["width"][1:], fams[f]["width"][0] == "i")
                           for f in wanted))
    out.append("};")
    # which family names the val and the mag of a status (the `val-of` / `mag-of` attributes of the marks)
    number = {name: int(value) for name, value, _f, _l in fams["stati"]["members"]}
    slots = {}
    for f in wanted:
        for slot in ("val", "mag"):
            for st in fams[f][slot + "_of"]:
                slots.setdefault(number[st], {})[slot] = f
    out.append("static const V1StatSlot v1StatSlotsGen[] = {")
    out.append(",\n".join('    { %d, %s, %s }' % (n, *(('"%s"' % s[k]) if k in s else "NULL" for k in ("val", "mag")))
                          for n, s in sorted(slots.items())) or "    { -1, NULL, NULL }")
    out.append("};")
    # which saved field a family fills (the `field-of` / `index-of` / `elem-of` attributes): mode 0 the field's value,
    # 1 the array index, 2 each array element, 3 a glyph word (field or element), 100+N the word at byte N of a blob
    rows = []
    for f in wanted:
        for mode, attr in enumerate(("field_of", "index_of", "elem_of", "glyph_of")):
            rows += ['    { "%s", "%s", %d }' % (key, f, mode) for key in fams[f][attr]]
        for key in fams[f]["word_of"]:   # word-of Scope.Blob@<byte>: mode 100 + the byte offset of the 32-bit word
            rows.append('    { "%s", "%s", %d }' % (key.split("@")[0], f, 100 + int(key.split("@")[1])))
    out.append("static const V1FieldFam v1FieldFamsGen[] = {")
    out.append(",\n".join(rows) or '    { NULL, NULL, 0 }')
    out.append("};")
    # which family names the element at one index of a saved array (the `at-of` attributes): the index NAME is a member of
    # the family whose `index-of` mark claims the same array (Player.Options[OPT_DIFFICULTY]: OPT_DIFFICULTY is a member of opt)
    index_fam = {key: f for f in wanted for key in fams[f]["index_of"]}
    at_rows = []
    for f in wanted:
        for key in fams[f]["at_of"]:
            arr, idx = key[:-1].split("[")
            members = {n: int(v) for n, v, _f, _l in fams[index_fam[arr]]["members"]} if arr in index_fam else {}
            if idx not in members:
                raise cdd.Unmeasurable("family %s says at-of %s but %s names no index %s" % (f, key, arr, idx))
            value = members[idx]
            at_rows.append('    { "%s", %d, "%s" }' % (arr, value, f))
    out.append("static const V1AtFam v1AtFamsGen[] = {")
    out.append(",\n".join(at_rows) or '    { NULL, 0, NULL }')
    out.append("};")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(cdd.ROOT, "build", "gen", "FamilyNames.h"))
    a = ap.parse_args()
    try:
        text = build_text()
    except (cdd.Unmeasurable, OSError) as e:
        print("gen_family_names: UNMEASURED: %s" % e, file=sys.stderr)
        return 2
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    tmp = a.out + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, a.out)
    print("gen_family_names: wrote %s" % a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
