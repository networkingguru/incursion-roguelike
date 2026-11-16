// inc/SaveRetiredNames.h -- the engine's copy of tools/retired_field_names.txt (inc-cjos0).
// tools/check_field_names.sh --selftest fails when this table and that file differ.
// A retired name is a saved field master stopped reading: the reader ignores it instead of
// refusing the file. A retired name is never reused. A rename keeps its old name here, and
// the reader matches either side.
#ifndef SAVERETIREDNAMES_H
#define SAVERETIREDNAMES_H

struct RetiredFieldName  { const char *scope, *name; };
struct RenamedFieldName  { const char *scope, *oldName, *newName; };

static const RetiredFieldName RETIRED_FIELD_NAMES[] = {
  { "Character", "SpellsU16" },
  { NULL, NULL }
};

static const RenamedFieldName RENAMED_FIELD_NAMES[] = {
  { NULL, NULL, NULL }
};

#endif
