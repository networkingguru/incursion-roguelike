/* FMTCHECK.CPP -- See the Incursion LICENSE file for copyright information.

     Static format-string scanner for script-provided format strings.

     A script string or object argument is an int32 handle, never a C++
     pointer. __XPrint (src/Message.cpp) reads a <str...> tag as const char*
     and an <obj|mon|itm...> tag as Thing*, so a script that uses those tags
     makes the interpreter read a handle as a pointer and crash. This scanner
     reports the first such tag (or the first unsafe printf conversion) so the
     script dispatch can reject the format before it reaches __XPrint.

     Invariant: a script format never reaches a pointer-reading tag.
     inc-ac0l
     upstream: a script handle is not a pointer on Win32 either; Traced; inc-ac0l; not sent.
*/

#include "Defines.h"

#include <cctype>
#include <cstdlib>
#include <cstring>
#include <cstddef>
#include <cstdarg>

#include "Globals.h"

/* Tag1/Tag2 in __XPrint are 24-byte buffers; the scan stops at 23 chars and
   Fatals ("Formatted string with bad tag!", src/Message.cpp:128-129). */
#define FMT_TAG_LEN 23

static const char* FMT_MSG_STR =
    "<Str> reads a C++ pointer; a script must use <hText>";
static const char* FMT_MSG_OBJ =
    "<Obj>/<Mon>/<Itm> read a C++ pointer; a script must use <hObj>/<hMon>/<hItm>";

/* Params in __XPrint is a union (src/Message.cpp:82-87) of int32 i,
   const char* s and Thing* o. The hazard is the STORAGE, not the width of the
   va_arg read. <Num>, <hText> and <Res>/<rID> store Params[n].i (4 bytes;
   :174, :213, :233) and read it back (num -> .i :177, hText -> .i :219,
   rid/res -> .i :236). <hObj>/<hMon>/<hItm> store Params[n].o = oThing(...)
   (8 bytes; :494) and read it back (:497). A numbered tag whose slot is
   already filled (i <= n) does not read va_args; it reads the union member of
   ITS kind from that slot (:498), so the two storage classes are not
   interchangeable. A later tag that reuses a filled slot of the other class is
   rejected. Reusing a slot of the same class stays accepted. Every
   pointer-reading tag (str, obj/mon/itm) is rejected before a slot is
   recorded, so only these two classes reach the recorder. */
enum SlotKind {
    SLOT_NONE = 0,
    SLOT_INT32 = 1,
    SLOT_POINTER = 2
};

static SlotKind FmtTagKind(const char* tag1) {
    if (tag1[0] == 's' && tag1[1] == 't' && tag1[2] == 'r')
        return SLOT_POINTER;
    if (tag1[0] == 'n' && tag1[1] == 'u' && tag1[2] == 'm')
        return SLOT_INT32;
    if (tag1[0] == 'h' && tag1[1] == 't')
        return SLOT_INT32;
    if (tag1[0] == 'r' &&
        ((tag1[1] == 'i' && tag1[2] == 'd') ||
         (tag1[1] == 'e' && tag1[2] == 's')))
        return SLOT_INT32;
    if ((tag1[0] == 'h' && tag1[1] == 'o' && tag1[2] == 'b') ||
        (tag1[0] == 'h' && tag1[1] == 'm' && tag1[2] == 'o') ||
        (tag1[0] == 'h' && tag1[1] == 'i' && tag1[2] == 't'))
        return SLOT_POINTER;
    return SLOT_NONE;
}

static bool FmtStartsWith(const char* s, const char* pre) {
    while (*pre)
        if (*s++ != *pre++)
            return false;
    return true;
}

/* Scan an XPrint-language format exactly as __XPrint parses tags. Returns NULL
   when safe, else a static message. */
static const char* FmtCheckXPrint(const char* fmt) {
    const char* cc = fmt;
    SlotKind slots[16];
    memset(slots, 0, sizeof(slots));
    int nextSlot = 0;

    while (*cc) {
        if (*cc != '<')
            { cc++; continue; }

        /* src/Message.cpp:117 -- a '<' is a tag start unless the byte two back
           is the LITERAL_CHAR escape marker. */
        if (!(cc == fmt || cc == fmt + 1 || (*(cc - 2) != (char)LITERAL_CHAR)))
            { cc++; continue; }

        char Tag1[24], Tag2[24];
        const char* ts = cc;
        cc++;

        Tag2[0] = 0;
        char* tag = Tag1;
        int count = 0;
        for (;;) {
            count = 0;
            while (*cc && *cc != ':' && *cc != '>' && count != FMT_TAG_LEN)
                { *tag++ = (char)tolower((unsigned char)*cc++); count++; }
            if (count == FMT_TAG_LEN) {
                /* __XPrint Fatals; the format is unusable. Report the tag. */
                return FMT_MSG_STR;
            }
            *tag = 0;
            if (!*cc) {
                /* Null terminator inside tag: __XPrint Fatals. */
                return FMT_MSG_STR;
            }
            if (*cc == ':') {
                tag = Tag2;
                cc++;
                continue;
            }
            cc++;
            break;
        }
        (void)ts;

        /* Number-only tag: <13> etc. writes a raw colour byte, no argument. */
        if (isdigit((unsigned char)Tag1[0]))
            continue;

        /* Reject a <str...> tag before anything else: it reads a const char*. */
        if (Tag1[0] == 's' && Tag1[1] == 't' && Tag1[2] == 'r')
            return FMT_MSG_STR;

        /* The object check uses Tag2 when present, else Tag1
           (src/Message.cpp:465). */
        const char* selected = Tag2[0] ? Tag2 : Tag1;
        if (FmtStartsWith(selected, "obj") ||
            FmtStartsWith(selected, "mon") ||
            FmtStartsWith(selected, "itm"))
            return FMT_MSG_OBJ;

        /* Record the slot kind for every argument-consuming tag. The slot
           number is 1-based; a bare tag takes the next slot. Parsing the
           trailing decimal mirrors __XPrint's atoi of the suffix. The kind and
           suffix come from `selected` (Tag2 when present), as __XPrint does at
           src/Message.cpp:465. */
        SlotKind kind = FmtTagKind(selected);
        if (kind != SLOT_NONE) {
            int suffix = 0;
            if (selected[0] == 's' && selected[1] == 't' && selected[2] == 'r')
                suffix = selected[3] ? atoi(selected + 3) : 0;
            else if (selected[0] == 'n' && selected[1] == 'u' && selected[2] == 'm')
                suffix = selected[3] ? atoi(selected + 3) : 0;
            else if (selected[0] == 'h' && selected[1] == 't')
                { const char* q = selected; while (isalpha((unsigned char)*q)) q++;
                  suffix = *q ? atoi(q) : 0; }
            else if (selected[0] == 'r')
                suffix = selected[3] ? atoi(selected + 3) : 0;
            else
                suffix = selected[4] ? atoi(selected + 4) : 0;

            /* Effective slot: a bare tag takes the next one; a numbered tag
               that skips ahead leaves the skipped slots filled too (__XPrint's
               while (i > n) n++). */
            int slot = suffix > 0 ? suffix : nextSlot + 1;
            if (suffix > nextSlot)
                nextSlot = suffix;
            else if (suffix == 0)
                nextSlot++;

            if (slot > 0 && slot < (int)(sizeof(slots) / sizeof(slots[0]))) {
                if (slots[slot] != SLOT_NONE && slots[slot] != kind) {
                    static char msg[160];
                    int n = 0;

                    msg[n++] = '<';
                    for (const char* t = selected; *t && n < (int)sizeof(msg) - 1; t++)
                        msg[n++] = *t;
                    msg[n++] = '>';

                    const char* pre = " reuses slot ";
                    for (const char* t = pre; *t && n < (int)sizeof(msg) - 1; t++)
                        msg[n++] = *t;

                    char d[12];
                    int dn = 0, sn = slot;
                    while (sn && dn < 11) { d[dn++] = (char)('0' + sn % 10); sn /= 10; }
                    while (dn && n < (int)sizeof(msg) - 1) msg[n++] = d[--dn];

                    const char* post = slots[slot] == SLOT_POINTER
                        ? ", which holds an object handle; give each argument "
                          "its own slot"
                        : ", which holds a number; give each argument its own slot";
                    for (const char* t = post; *t && n < (int)sizeof(msg) - 1; t++)
                        msg[n++] = *t;

                    msg[n] = 0;
                    return msg;
                }
                slots[slot] = kind;
            }
        }
    }
    return NULL;
}

/* Scan a printf-language format. Only the int conversions the engine's own
   Format/Error/Fatal accept are safe with int32 script arguments. */
static const char* FmtCheckPrintf(const char* fmt) {
    static char msg[96];
    const char* cc = fmt;

    while (*cc) {
        if (*cc != '%')
            { cc++; continue; }
        cc++;
        if (*cc == '%')
            { cc++; continue; }

        while (*cc == '-' || *cc == '+' || *cc == ' ' ||
               *cc == '#' || *cc == '0')
            cc++;
        if (*cc == '*')
            return "printf conversion uses '*'; script arguments are fixed int32";
        while (isdigit((unsigned char)*cc))
            cc++;
        if (*cc == '.') {
            cc++;
            if (*cc == '*')
                return "printf conversion uses '*'; script arguments are fixed int32";
            while (isdigit((unsigned char)*cc))
                cc++;
        }

        if (*cc == 'h' || *cc == 'l' || *cc == 'z' || *cc == 'j' ||
            *cc == 't' || *cc == 'L')
            return "printf conversion uses a length modifier; not safe for a script";

        if (*cc == 'd' || *cc == 'i' || *cc == 'u' || *cc == 'x' ||
            *cc == 'X' || *cc == 'c')
            { cc++; continue; }

        if (*cc == 0)
            return "printf format ends with a bare percent sign";

        static const char* bad = "printf conversion CHAR is not safe for a "
                                 "script (only d i u x X c)";
        msg[0] = 0;
        /* Build the message without snprintf, which is not used in this old
           tree; overwrite the CHAR placeholder manually. No '%' appears in the
           message: these texts are passed to Error/Fatal, which format. */
        const char* tpl = bad;
        int n = 0;
        for (; *tpl && n < (int)sizeof(msg) - 1; tpl++) {
            if (*tpl == 'C' && tpl[1] == 'H' && tpl[2] == 'A' && tpl[3] == 'R') {
                msg[n++] = *cc;
                tpl += 3;
                continue;
            }
            msg[n++] = *tpl;
        }
        msg[n] = 0;
        return msg;
    }
    return NULL;
}

const char* ScriptFormatProblem(const char* fmt, bool printfStyle) {
    if (!fmt)
        return NULL;
    if (printfStyle)
        return FmtCheckPrintf(fmt);
    return FmtCheckXPrint(fmt);
}

/* Bindings keyed by API function name; fmtPos holds the STACK(k) indices of the
   format arguments in the generated dispatch case. GodMessage is handled
   separately via ScriptGodMessageDepth. inc-ac0l */
static const ScriptFormatBinding ScriptFormatBindings[] = {
    { "enWarn",        false, { 1, 0, 0 } },
    { "IPrint",        false, { 1, 0, 0 } },
    { "IDPrint",       false, { 1, 2, 0 } },
    { "XPrint",        false, { 1, 0, 0 } },
    { "DPrint",        false, { 2, 3, 0 } },
    { "VPrint",        false, { 2, 3, 0 } },
    { "TPrint",        false, { 2, 3, 4 } },
    { "APrint",        false, { 2, 0, 0 } },
    { "SinglePrintXY", false, { 2, 0, 0 } },
    { "Format",        true,  { 1, 0, 0 } },
    { "Error",         true,  { 1, 0, 0 } },
    { "Fatal",         true,  { 1, 0, 0 } },
    { NULL,            false, { 0, 0, 0 } }
};

const ScriptFormatBinding* FindScriptFormatBinding(const char* name) {
    int i;
    if (!name)
        return NULL;
    for (i = 0; ScriptFormatBindings[i].name; i++)
        if (!strcmp(ScriptFormatBindings[i].name, name))
            return &ScriptFormatBindings[i];
    return NULL;
}

int16 ScriptGodMessageDepth = 0;
