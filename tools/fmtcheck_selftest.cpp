/* FMTCHECK_SELFTEST.CPP -- self-test for src/FmtCheck.cpp (inc-ac0l).

     Standalone: compiles against src/FmtCheck.cpp and nothing else from the
     engine. Run by tools/check_fmtcheck.sh. Exits 0 when every case passes.
*/

#include "Defines.h"

#include <cstdio>
#include <cstring>

const char* ScriptFormatProblem(const char* fmt, bool printfStyle);

static int g_fail = 0;

static void expectAccept(const char* what, const char* fmt, bool printfStyle) {
    const char* p = ScriptFormatProblem(fmt, printfStyle);
    if (p != NULL) {
        std::printf("FAIL accept %-22s \"%s\" -> %s\n", what, fmt ? fmt : "(null)", p);
        g_fail++;
    } else {
        std::printf("ok   accept %-22s \"%s\"\n", what, fmt ? fmt : "(null)");
    }
}

static void expectReject(const char* what, const char* fmt, bool printfStyle) {
    const char* p = ScriptFormatProblem(fmt, printfStyle);
    if (p == NULL) {
        std::printf("FAIL reject %-22s \"%s\" (was accepted)\n", what, fmt);
        g_fail++;
    } else {
        if (std::strchr(p, '%') != NULL) {
            std::printf("FAIL reject %-22s \"%s\" -> message contains '%%': %s\n",
                        what, fmt, p);
            g_fail++;
        } else {
            std::printf("ok   reject %-22s \"%s\" -> %s\n", what, fmt, p);
        }
    }
}

int main() {
    /* XPrint language: reject pointer-reading tags. */
    expectReject("xprint <Str>", "<Str>", false);
    expectReject("xprint <str2>", "<str2>", false);
    expectReject("xprint <STR>", "<STR>", false);
    expectReject("xprint <Obj>", "<Obj>", false);
    expectReject("xprint <His:Obj>", "<His:Obj>", false);
    expectReject("xprint <He:Mon2>", "<He:Mon2>", false);
    expectReject("xprint <Itm>", "<Itm>", false);

    /* Params is a union (src/Message.cpp:82-87). A numbered tag whose slot is
       already filled (i <= n) reads the union member of ITS storage class from
       that slot: int-like kinds (num/hText/rid/res) use .i, object-handle kinds
       (hObj/hMon/hItm) use .o. So reusing a slot of the other class reads
       garbage. Cross-class reuse is rejected; same-class reuse is accepted. */
    expectReject("xprint <Num> <hObj1>", "<Num> <hObj1>", false);
    expectReject("xprint <hObj> <Num1>", "<hObj> <Num1>", false);
    expectReject("xprint <hObj> <hText1>", "<hObj> <hText1>", false);
    expectAccept("xprint <Num> <Num1>", "<Num> <Num1>", false);
    expectAccept("xprint <hObj> <He:hObj1>", "<hObj> <He:hObj1>", false);
    expectAccept("xprint <hText> <hText1>", "<hText> <hText1>", false);

    /* printf language: reject unsafe conversions. */
    expectReject("printf %s", "%s", true);
    expectReject("printf %p", "%p", true);
    expectReject("printf %n", "%n", true);
    expectReject("printf %f", "%f", true);
    expectReject("printf %ld", "%ld", true);
    expectReject("printf %*d", "%*d", true);

    /* XPrint language: accept handle-safe tags. */
    expectAccept("xprint <hText>", "<hText>", false);
    expectAccept("xprint <hObj>", "<hObj>", false);
    expectAccept("xprint <Num>", "<Num>", false);
    expectAccept("xprint <Res>", "<Res>", false);
    expectAccept("xprint <His:hObj>", "<His:hObj>", false);

    /* The lexer stores an escaped \< as LITERAL_CHAR, 0xFF, '<'
       (lang/Tokens.lex:455-457), which is exactly what __XPrint's guard at
       src/Message.cpp:117 keys on. Build that byte sequence here. */
    {
        char esc[8];
        esc[0] = (char)LITERAL_CHAR;
        esc[1] = (char)0xFF;
        esc[2] = '<';
        esc[3] = 'S';
        esc[4] = 't';
        esc[5] = 'r';
        esc[6] = '>';
        esc[7] = 0;
        expectAccept("xprint escaped <Str>", esc, false);
    }

    /* printf language: accept int conversions, flags, width and %%. */
    expectAccept("printf %d", "%d", true);
    expectAccept("printf %+d", "%+d", true);
    expectAccept("printf %5d", "%5d", true);
    expectAccept("printf %%", "%%", true);
    expectAccept("printf %x", "%x", true);
    expectAccept("printf plain text", "plain text", true);
    expectAccept("xprint plain text", "plain text", false);
    expectAccept("NULL xprint", NULL, false);
    expectAccept("NULL printf", NULL, true);

    /* Cross-language: the other language's own rules apply. */
    expectAccept("printf <Str> (printf rules)", "<Str>", true);
    expectAccept("xprint %s (xprint rules)", "%s", false);

    if (g_fail) {
        std::printf("\n%d case(s) FAILED\n", g_fail);
        return 1;
    }
    std::printf("\nall cases passed\n");
    return 0;
}
