#ifndef KEYSCRIPT_H
#define KEYSCRIPT_H

#include <stddef.h>
/* Incursion.h has already defined array, min and max as macros. libstdc++
   declares std::min/std::max in <bits/stl_algobase.h>, and the macros mangle
   those declarations, so the Linux build fails where libc++ tolerates it.
   Hide all three across the include, then restore them. */
#pragma push_macro("array")
#pragma push_macro("min")
#pragma push_macro("max")
#undef array
#undef min
#undef max
#include <vector>
#pragma pop_macro("max")
#pragma pop_macro("min")
#pragma pop_macro("array")

/* Script tokens that both backends treat as instructions rather than
   keystrokes. They are outside the range of any KY_ value. */
#define SK_DUMP  (-1)
#define SK_QUIT  (-2)
#define SK_PAUSE (-8)
#define SK_SHOT  (-9)

#define SK_BODY_MAX 8

typedef struct ScriptKey {
    int16 ch;        /* a KY_ value, a character, or SK_ above */
    uint8 mods;      /* SHIFT | CONTROL | ALT, as the keyset expects */
    char  label[64]; /* SK_DUMP: dump label; SK_SHOT: screenshot filename. */
    bool  byMark;    /* SK_CURSOR: look for a marker, not a highlight. */
    int32 pauseMs;   /* SK_PAUSE: milliseconds to pause. */

    /* SK_WHILE and SK_UNTIL only. The body is a sequence rather than a single
       key because the case this exists for needs one: draining the Skill
       Manager takes RIGHT to spend a rank and DOWN to move to the next skill,
       and neither alone makes progress. The screen is tested once per pass,
       at the top, so a pass always completes. */
    int16 bodyCh[SK_BODY_MAX];
    uint8 bodyMods[SK_BODY_MAX];
    int8  bodyCount;
    int8  bodyPos;
    int16 iter;      /* passes completed */
} ScriptKey;

bool TokenToKey(const char *tok, ScriptKey *out);
bool LoadKeyQueue(const char *fn, std::vector<ScriptKey> &out,
                  char *err, size_t errsz);

#endif
