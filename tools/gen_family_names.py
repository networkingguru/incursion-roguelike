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
for the families the observer and the planter use. Without python3 the build writes no header and the
observer prints bare numbers; the planter then refuses every name.

USAGE  gen_family_names.py [--out FILE]
Exit: 0 written; 2 the family marks could not be read.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_define_dups as cdd  # noqa: E402

# the families the observer and planter use, and the table name each is written under
WANTED = ["stati", "ss", "ft", "sk", "attr", "ca", "sl", "ma", "kn", "if_flag", "target_why_type"]
# families that continue a wanted family's number line under the same table (skills 800 and up)
ALSO = {"sk": ["sk_high_first"]}


def build_text():
    fams, problems = cdd.load_families()
    out = ["// written by tools/gen_family_names.py on every build; do not edit",
           "#define FAMNAMES_MEASURED 1",
           "struct FamName { int value; const char *name; };"]
    for f in WANTED:
        if f not in fams:
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
