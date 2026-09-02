#include <ctype.h>

#include "Incursion.h"
#include "KeyScript.h"

static const struct { const char *name; int16 ch; } NamedKeys[] = {
    { "ESC", KY_ESC }, { "ENTER", KY_ENTER }, { "RETURN", KY_ENTER },
    { "TAB", KY_TAB }, { "SPACE", KY_SPACE }, { "BKSP", KY_BACKSPACE },
    { "BACKSPACE", KY_BACKSPACE },
    { "UP", KY_UP }, { "DOWN", KY_DOWN }, { "LEFT", KY_LEFT },
    { "RIGHT", KY_RIGHT }, { "HOME", KY_HOME }, { "END", KY_END },
    { "PGUP", KY_PGUP }, { "PGDN", KY_PGDN },
    { "F1", KY_CMD_MACRO1 }, { "F2", KY_CMD_MACRO2 }, { "F3", KY_CMD_MACRO3 },
    { "F4", KY_CMD_MACRO4 }, { "F5", KY_CMD_MACRO5 }, { "F6", KY_CMD_MACRO6 },
    { "F7", KY_CMD_MACRO7 }, { "F8", KY_CMD_MACRO8 }, { "F9", KY_CMD_MACRO9 },
    { "F10", KY_CMD_MACRO10 }, { "F11", KY_CMD_MACRO11 }, { "F12", KY_CMD_MACRO12 },
    { NULL, 0 }
};

/* Turn one script token into a keystroke.

   SHIFT is not cosmetic here. StandardKeySet matches toupper(ch) against
   raw_key and then compares the modifier flags exactly, so
   { KY_CMD_ACTIVATE, 'A', 0 } is reached by lowercase 'a' and never by 'A'.
   Setting SHIFT for an uppercase letter is what a real keyboard does, and
   without it a script silently dispatches the wrong commands. Punctuation is
   left alone: every punctuation entry in both keysets uses flags -1, which
   ignores modifiers. */
bool TokenToKey(const char *tok, ScriptKey *out) {
    int i;

    memset(out, 0, sizeof(*out));

    if (tok[0] == '@') {
        /* "@dump" or "@dump:label", and nothing else that merely starts that
           way -- a misspelling should be reported, not silently obeyed. */
        if (!strncmp(tok + 1, "dump", 4) && (!tok[5] || tok[5] == ':')) {
            out->ch = SK_DUMP;
            if (tok[5] == ':')
                snprintf(out->label, sizeof(out->label), "%s", tok + 6);
            return true;
        }
        if (!strcmp(tok + 1, "quit")) {
            out->ch = SK_QUIT;
            return true;
        }
        return false;
    }

    if (tok[0] == '^' && tok[1] && !tok[2]) {
        out->ch = tolower((unsigned char)tok[1]);
        out->mods = CONTROL;
        return true;
    }

    for (i = 0; NamedKeys[i].name; i++)
        if (!strcasecmp(tok, NamedKeys[i].name)) {
            out->ch = NamedKeys[i].ch;
            return true;
        }

    if (tok[0] && !tok[1]) {
        out->ch = (unsigned char)tok[0];
        if (isupper((unsigned char)tok[0]))
            out->mods = SHIFT;
        return true;
    }

    return false;
}

static bool KeyQueueError(char *err, size_t errsz, const char *fmt,
                          const char *a, const char *b = NULL) {
    if (err && errsz)
        snprintf(err, errsz, fmt, a, b ? b : "");
    return false;
}

static bool LoadKeyQueueFile(const char *fn, std::vector<ScriptKey> &out,
                             char *err, size_t errsz, int depth) {
    FILE *f;
    char tok[MAX_PATH_LENGTH];
    int c;

    if (depth > 8)
        return KeyQueueError(err, errsz,
            "Key script '%s': includes are nested too deeply.", fn);

    f = fopen(fn, "r");
    if (!f)
        return KeyQueueError(err, errsz, "Cannot open key script '%s'.", fn);

    for (;;) {
        int n = 0, repeat = 1, i;
        ScriptKey k;

        c = fgetc(f);
        if (c == EOF)
            break;
        if (isspace(c))
            continue;
        if (c == '#') {
            while (c != EOF && c != '\n')
                c = fgetc(f);
            continue;
        }

        if (c == '"') {
            while ((c = fgetc(f)) != EOF && c != '"') {
                char one[2] = { (char)c, 0 };
                if (!TokenToKey(one, &k)) {
                    fclose(f);
                    return KeyQueueError(err, errsz,
                        "Key script '%s': cannot read quoted character.", fn);
                }
                out.push_back(k);
            }
            if (c == EOF) {
                fclose(f);
                return KeyQueueError(err, errsz,
                    "Key script '%s': unterminated quoted run.", fn);
            }
            continue;
        }

        tok[n++] = (char)c;
        while ((c = fgetc(f)) != EOF && !isspace(c) &&
               n < (int)sizeof(tok) - 1)
            tok[n++] = (char)c;
        tok[n] = '\0';

        if (!strcmp(tok, "@include")) {
            char inc[MAX_PATH_LENGTH], resolved[MAX_PATH_LENGTH];
            const char *slash;

            n = 0;
            while ((c = fgetc(f)) != EOF && isspace(c))
                ;
            while (c != EOF && !isspace(c) && n < (int)sizeof(inc) - 1) {
                inc[n++] = (char)c;
                c = fgetc(f);
            }
            inc[n] = '\0';
            if (!inc[0]) {
                fclose(f);
                return KeyQueueError(err, errsz,
                    "Key script '%s': @include needs a filename.", fn);
            }

            slash = strrchr(fn, '/');
            if (inc[0] == '/' || !slash)
                snprintf(resolved, sizeof(resolved), "%s", inc);
            else
                snprintf(resolved, sizeof(resolved), "%.*s%s",
                    (int)(slash - fn + 1), fn, inc);
            if (!LoadKeyQueueFile(resolved, out, err, errsz, depth + 1)) {
                fclose(f);
                return false;
            }
            continue;
        }

        if (!strcmp(tok, "@pause")) {
            char ms[MAX_PATH_LENGTH];
            uint32 value = 0;
            bool tooLarge = false;

            n = 0;
            while ((c = fgetc(f)) != EOF && isspace(c))
                ;
            while (c != EOF && !isspace(c) && n < (int)sizeof(ms) - 1) {
                ms[n++] = (char)c;
                c = fgetc(f);
            }
            ms[n] = '\0';
            for (i = 0; ms[i] && isdigit((unsigned char)ms[i]); i++) {
                if (value > 214748364 ||
                    (value == 214748364 && ms[i] > '7')) {
                    tooLarge = true;
                    break;
                }
                value = value * 10 + ms[i] - '0';
            }
            if (!ms[0] || ms[i] || tooLarge || value < 1) {
                fclose(f);
                if (err && errsz)
                    snprintf(err, errsz, "Key script '%s': @pause needs a positive integer of milliseconds, and got '%s'.", fn, ms);
                return false;
            }
            memset(&k, 0, sizeof(k));
            k.ch = SK_PAUSE;
            k.pauseMs = (int32)value;
            out.push_back(k);
            continue;
        }

        if (!strcmp(tok, "@choose") || !strcmp(tok, "@expect") ||
            !strcmp(tok, "@cursorto") || !strcmp(tok, "@cursorto:mark") ||
            !strcmp(tok, "@while") || !strcmp(tok, "@until")) {
            fclose(f);
            if (err && errsz)
                snprintf(err, errsz,
                    "%s is not supported in the SDL build (movement scripts only)",
                    tok);
            return false;
        }

        if (n > 1) {
            char *star = strrchr(tok, '*');
            if (star && star != tok && isdigit((unsigned char)star[1])) {
                repeat = atoi(star + 1);
                *star = '\0';
                if (repeat < 1)
                    repeat = 1;
            }
        }

        if (!TokenToKey(tok, &k) || (k.ch < 0 && k.ch != SK_QUIT)) {
            fclose(f);
            return KeyQueueError(err, errsz,
                "Key script '%s': cannot read token '%s'.", fn, tok);
        }
        for (i = 0; i < repeat; i++)
            out.push_back(k);
    }

    fclose(f);
    return true;
}

bool LoadKeyQueue(const char *fn, std::vector<ScriptKey> &out,
                  char *err, size_t errsz) {
    out.clear();
    if (err && errsz)
        err[0] = '\0';
    return LoadKeyQueueFile(fn, out, err, errsz, 1);
}
