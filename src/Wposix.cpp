/* WPOSIX.CPP -- See the Incursion LICENSE file for copyright information.

     Contains the class definition and member functions for the posixTerm
   class: a terminal backend that needs neither SDL nor libtcod, and that can
   run with no display and no keyboard at all.

     Why it exists. The other two backends both require a person. Wlibtcod.cpp
   opens a window; Wcurses.cpp expects a console and pdcurses, and is Windows
   only. The best defect finder this project has is a play session that fills
   logs/errors.log, and that log only grows while somebody plays. This backend
   takes its keystrokes from a file and writes its screen to a file, so a
   session can run unattended and be inspected afterwards with grep.

     The screen is a plain array of Glyph rather than a graphics library's own
   buffer, which is what lets the same drawing code serve both a file and a
   terminal, and what makes AGetChar exact -- see the comment on that function.

   Low-Level Read/Write
     void posixTerm::Update()          void posixTerm::PutChar(...)
     void posixTerm::CursorOn/Off()    Glyph posixTerm::AGetChar(...)
     void posixTerm::Save/Restore()    void posixTerm::Clear()
   Input Functions
     int16 posixTerm::GetCharCmd(KeyCmdMode mode)   -- reads the key script
   General Functions
     void posixTerm::Initialize()      void Fatal(...)  void Error(...)
   Screen Capture
     void posixTerm::DumpScreen(const char *label)
   File I/O
     POSIX: stat, unlink, opendir, fnmatch.
*/

#ifdef POSIX_TERM

#define _CRT_SECURE_NO_WARNINGS

#undef TRACE
#undef MIN
#undef MAX
#undef ERROR
#undef EV_BREAK

#include <stdarg.h>
#include <ctype.h>
#include <time.h>
#include <malloc.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>
#include <fnmatch.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "Incursion.h"
#include "KeyScript.h"
#undef ERROR
#undef MIN
#undef MAX

#include "ErrorLog.h"

/* curses.h defines lowercase macros -- clear, move, erase, box, timeout,
   instr -- that collide with nothing here only because the game spells its
   own functions in CamelCase. It goes last so the game headers are read
   first, and its own MIN/MAX/ERROR go the same way as the others above. */
#include <curses.h>
#undef ERROR
#undef MIN
#undef MAX

#define _mkdir(A) mkdir(A, 0755)

/* The game asserts on anything smaller (TextTerm::InitWindows), and every
   window position in that function is derived from these two numbers. */
#define SCREEN_W 80
#define SCREEN_H 48

/* A runaway game loop must not hold a machine all night. Both are overridable
   from the environment for a session that legitimately needs longer. */
#define DEFAULT_MAX_KEYS 20000
#define DEFAULT_TIMEOUT_S 300

/* Exit codes, so a harness can tell the three endings apart without parsing
   the log: 0 clean, 1 Fatal(), 3 out of budget, 4 out of time. */
#define EXIT_OUT_OF_KEYS 3
#define EXIT_OUT_OF_TIME 4
/* 5 is tools/headless.sh's own "the run never entered a map", assigned after
   the fact, so a code the binary raises itself starts at 6. This one says a
   directive was told to find something the screen never showed. */
#define EXIT_SCRIPT_FAILED 6

char __buffer[1600];
char __buff2[80];

/* Script tokens that are instructions to the harness rather than keystrokes.
   They are outside the range of any KY_ value. */
#define SK_WHILE (-3)
#define SK_UNTIL (-4)
#define SK_CHOOSE (-5)
#define SK_CURSOR (-6)
#define SK_EXPECT (-7)

/* How the two managers that a script has to drive mark their current row, and
   why a script must say which one it is looking at rather than let this file
   guess. See CursorOnRow. */
#define SK_CURSOR_MARK   '>'
#define SK_MENU_CURSOR   AZURE

/* A conditional that never ends would hang the run in place of the watchdog,
   which measures the gap between keystrokes and would never fire. The limit
   counts passes over the body, not keystrokes. */
#define SK_LOOP_MAX  200
class posixTerm : public TextTerm {
    friend void Error(const char* fmt, ...);
    friend void Fatal(const char* fmt, ...);

private:
    Glyph scr[SCREEN_H][SCREEN_W];
    Glyph sav[SCREEN_H][SCREEN_W];
    Glyph *scrollBuf;               /* MAX_SCROLL_LINES x SCROLL_WIDTH */
    bool showCursor;
    bool useCurses;                 /* draw to a real terminal */
    String debugText;

    /* Key script */
    ScriptKey *keys;
    int32 keyCount, keyAlloc, keyNext;
    int32 keysRead;                 /* including repeats of QueuedChar */
    int32 maxKeys;
    int32 dumpCount;

    /* File I/O */
    String CurrentDirectory;
    String CurrentFileName;
    FILE *fp;
    DIR *findDir;
    String findSpec;

    uint32 startMilli;

public:
    posixTerm() {
        struct timespec ts;
        memset(scr, 0, sizeof(scr));
        memset(sav, 0, sizeof(sav));
        scrollBuf = NULL;
        showCursor = false;
        useCurses = false;
        keys = NULL;
        keyCount = keyAlloc = keyNext = keysRead = dumpCount = 0;
        maxKeys = DEFAULT_MAX_KEYS;
        fp = NULL;
        findDir = NULL;
        initialised = false;
        sizeX = SCREEN_W;
        sizeY = SCREEN_H;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        startMilli = (uint32)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
    }

    /* Low-Level Read/Write */
    virtual void Update();
    virtual void CursorOn()  { showCursor = true; }
    virtual void CursorOff() { showCursor = false; }
    virtual int16 CursorX() { return cx; }
    virtual int16 CursorY() { return cy; }
    virtual void Save();
    virtual void Restore();
    virtual void PutChar(Glyph g);
    virtual void APutChar(int16 x, int16 y, Glyph g);
    virtual void PutChar(int16 x, int16 y, Glyph g);
    virtual Glyph AGetChar(int16 x, int16 y);
    virtual void GotoXY(int16 x, int16 y);
    virtual void Clear();
    virtual void Color(uint16 _attr) { attr = _attr; }
    virtual void StopWatch(int16 milli);
    virtual uint32 GetElapsedMilli();
    virtual int32 ConvertChar(Glyph g, char **out) { return 0; }

    /* Input Functions */
    virtual int16 GetCharRaw() { return GetCharCmd(KY_CMD_RAW); }
    virtual int16 GetCharCmd() { return GetCharCmd(KY_CMD_NORMAL_MODE); }
    virtual int16 GetCharCmd(KeyCmdMode mode);
    /* A script has no idea of "keys already buffered". Draining would eat the
       next real keystroke, so all three of these do nothing and CheckEscape
       never interrupts. The only thing they can skip is an animation. */
    virtual bool CheckEscape() { return false; }
    virtual void ClearKeyBuff() { }
    virtual void PrePrompt() { }

    /* General Functions */
    virtual void Initialize();
    virtual void ShutDown();
    virtual void Reset() { }
    virtual bool hideOption(int16 opt) { return false; }
    virtual void SetDebugText(const char *text) { debugText = text; }
    virtual void Title() { TextTerm::Title(); }

    /* Scroll Buffer */
    virtual void SPutChar(int16 x, int16 y, Glyph g);
    virtual uint16 SGetChar(int16 x, int16 y);
    virtual void SPutColor(int16 x, int16 y, uint16 col);
    virtual uint16 SGetColor(int16 x, int16 y);
    virtual void SClear();
    virtual void BlitScrollLine(int16 wn, int32 buffline, int32 winline);

    /* Screen Capture */
    void DumpScreen(const char *label);
    void RenderRow(int16 y, char *line);
    bool ScreenShows(const char *text);
    bool FindMenuEntry(const char *name, char *key, int16 *ey, int16 *ex,
                       const char **why);
    bool CursorOnRow(const char *text, bool byMark);
    void ScriptFailed(const char *what, const char *detail);
    void LoadKeyScript(const char *fn);
    void SetMaxKeys(int32 n) { maxKeys = n; }
    void UseTerminal(bool on) { useCurses = on; }
    bool HasKeyScript() { return keys != NULL; }

    /* System-Independant File I/O */
    virtual const char* SaveSubDir()    { return "save"; }
    virtual const char* ModuleSubDir()  { return "mod"; }
    virtual const char* LibraryPath() {
        char *envLibPath;
        static char s[MAX_PATH_LENGTH] = "";
        if (strlen(s) == 0) {
            envLibPath = getenv("INCURSIONLIBPATH");
            if (envLibPath != NULL && strlen(envLibPath)) {
                if (strcat(s, envLibPath)) {
                    if (s[strlen(s) - 1] == '/')
                        s[strlen(s) - 1] = '\0';
                }
            }
            if (strlen(s) == 0) {
                strcat(s, IncursionDirectory);
                strcat(s, "lib");
            }
        }
        return s;
    }
    virtual const char* LogSubDir()     { return "logs"; }
    virtual const char* ManualSubDir()  { return "man"; }
    virtual const char* OptionsSubDir() { return "."; }
    virtual void ChangeDirectory(const char * c, bool set) {
        if (set)
            CurrentDirectory = c;
        else {
            CurrentDirectory = (const char*)IncursionDirectory;
            if (CurrentDirectory != c)
                CurrentDirectory += c;
        }
        if (chdir(CurrentDirectory)) {
            char path[MAX_PATH_LENGTH];
            getcwd(path, MAX_PATH_LENGTH);
            Fatal("Unable to locate directory: '%s' (cwd: '%s').",
                (const char*)CurrentDirectory, path);
        }
    }
    virtual bool Exists(const char* fn);
    virtual void Delete(const char* fn);
    virtual void OpenRead(const char* fn);
    virtual void OpenWrite(const char* fn);
    virtual void OpenUpdate(const char* fn);
    virtual void Close();
    virtual void FRead(void*, size_t sz);
    virtual void FWrite(const void*, size_t sz);
    virtual void Seek(int32, int8);
    virtual void Cut(int32);
    virtual bool FirstFile(char * filespec);
    virtual bool NextFile();
    virtual char * MenuListFiles(const char * filespec, uint16 flags, const char *title);
    virtual const char* GetFileName() { return CurrentFileName; }
    virtual int32 Tell();

    void SetIncursionDirectory(const char *s);

private:
    ScriptKey NextKey();
    void AppendKey(const ScriptKey &k);
    void OutOfKeys();
};

Term *T1;
posixTerm *AT1;

/*****************************************************************************\
*                                  posixTerm                                  *
*                          Glyph to readable ASCII                            *
\*****************************************************************************/

/* The consumer of a dump is grep, not a font, so a glyph becomes the plainest
   ASCII that still reads as the thing it draws. The libtcod backend maps the
   same ids to CP437 code points, which are unreadable in a text file.

   Ids below GLYPH_FIRST are literal characters and pass straight through. */
static char glyph_to_ascii(Glyph g) {
    static char t[GLYPH_LAST + 2];
    int c = GLYPH_ID_VALUE(g);

    if (!t[GLYPH_LAST + 1]) {
        int i;
        for (i = 0; i <= GLYPH_LAST; i++)
            t[i] = 0;

        t[GLYPH_UNSEEN] = ' ';
        t[GLYPH_VLINE] = '|';
        t[GLYPH_HLINE] = '-';
        t[GLYPH_DIVIDE] = '/';
        t[GLYPH_APPROXIMATELY] = '~';
        t[GLYPH_BLACK_SQUARE] = '*';
        t[GLYPH_CHECK] = 'v';
        t[GLYPH_CHECKMARK] = 'v';

        t[GLYPH_PERSON] = 'P';
        t[GLYPH_BULK] = '+';
        t[GLYPH_WATER] = '~';
        t[GLYPH_FOG] = '~';
        t[GLYPH_ICE] = '*';
        t[GLYPH_WEB] = '#';
        t[GLYPH_LAVA] = '~';
        t[GLYPH_BLAST] = '*';
        t[GLYPH_WALL] = '#';
        t[GLYPH_ROCK] = '#';
        t[GLYPH_SOLID] = '#';
        t[GLYPH_PILLAR1] = 'o';
        t[GLYPH_PILLAR2] = 'o';
        t[GLYPH_VIEWPOINT] = 'o';
        t[GLYPH_GRAVE] = 'n';
        t[GLYPH_SHELF] = '+';

        t[GLYPH_POTION] = '!';
        t[GLYPH_SCROLL] = '?';
        t[GLYPH_WEAPON] = 'v';
        t[GLYPH_ROD] = '|';
        t[GLYPH_STAFF] = '/';
        t[GLYPH_WAND] = '-';
        t[GLYPH_FOOD] = '%';
        t[GLYPH_CORPSE] = '%';
        t[GLYPH_BOOK] = '*';
        t[GLYPH_TORCH] = '}';
        t[GLYPH_LARMOUR] = '[';
        t[GLYPH_MARMOUR] = '[';
        t[GLYPH_HARMOUR] = '[';
        t[GLYPH_SHIELD] = ']';
        t[GLYPH_GAUNTLETS] = ']';
        t[GLYPH_HELMET] = ']';
        t[GLYPH_HEADBAND] = ']';
        t[GLYPH_BOOTS] = ']';
        t[GLYPH_BRACERS] = ']';
        t[GLYPH_GIRDLE] = ']';
        t[GLYPH_CLOTHES] = '[';
        t[GLYPH_CONTAIN] = '(';
        t[GLYPH_CROWN] = '^';
        t[GLYPH_DUST] = '=';
        t[GLYPH_DECK] = '=';
        t[GLYPH_RING] = '=';
        t[GLYPH_AMULET] = '"';
        t[GLYPH_FIGURE] = '&';
        t[GLYPH_HORN] = '&';
        t[GLYPH_EYES] = '&';
        t[GLYPH_HERB] = '"';
        t[GLYPH_MUSH] = ',';
        t[GLYPH_GEM] = '*';
        t[GLYPH_COIN] = '$';
        t[GLYPH_TOOL] = '&';
        t[GLYPH_SWORD] = '(';
        t[GLYPH_BOW] = ')';
        t[GLYPH_JUNK] = '&';
        t[GLYPH_CHEST] = '(';
        t[GLYPH_CLOAK] = '[';
        t[GLYPH_STATUE] = '&';
        t[GLYPH_PILE] = '*';
        t[GLYPH_MULTI] = '&';
        t[GLYPH_ALTAR] = '_';
        t[GLYPH_FOUNTAIN] = '{';
        t[GLYPH_THRONE] = '\\';
        t[GLYPH_SYMBOL] = '0';

        t[GLYPH_HEDGE] = '"';
        t[GLYPH_RUBBLE] = ':';
        t[GLYPH_BRIDGE] = '=';
        t[GLYPH_FLOOR] = '.';
        t[GLYPH_FLOOR2] = ',';
        t[GLYPH_VDOOR] = '|';
        t[GLYPH_HDOOR] = '-';
        t[GLYPH_ODOOR] = '+';
        t[GLYPH_BDOOR] = 'x';
        t[GLYPH_PIT] = '0';
        t[GLYPH_PORTAL] = '=';
        t[GLYPH_SUMMONING_CIRCLE] = '0';

        t[GLYPH_STORE] = '$';
        t[GLYPH_GUILD] = '$';
        t[GLYPH_STORE_VWALL] = '|';
        t[GLYPH_STORE_HWALL] = '-';
        t[GLYPH_STORE_CORNER] = '+';

        t[GLYPH_USTAIRS] = '<';
        t[GLYPH_DSTAIRS] = '>';
        t[GLYPH_TREE] = 'T';
        t[GLYPH_FURNATURE] = '*';
        t[GLYPH_UNKNOWN] = '?';
        t[GLYPH_TRASH] = '&';
        t[GLYPH_BONES] = '&';

        t[GLYPH_TRAP] = '^';
        t[GLYPH_DISARMED] = '/';

        t[GLYPH_ARROW] = '^';
        t[GLYPH_ARROW_UP] = '^';
        t[GLYPH_ARROW_DOWN] = 'v';
        t[GLYPH_ARROW_RIGHT] = '>';
        t[GLYPH_ARROW_LEFT] = '<';
        t[GLYPH_POINTER_LEFT] = '<';
        t[GLYPH_POINTER_RIGHT] = '>';

        t[GLYPH_GUARD] = 'i';
        t[GLYPH_TOWNIE] = 'i';
        t[GLYPH_TOWNSCUM] = 'i';
        t[GLYPH_TOWN_NPC] = 'i';
        t[GLYPH_LDEMON] = 'u';
        t[GLYPH_GDEMON] = 'U';
        t[GLYPH_LDEVIL] = 'o';
        t[GLYPH_GDEVIL] = 'O';
        t[GLYPH_FIEND] = 'y';

        t[GLYPH_PLAYER] = '@';
        t[GLYPH_HUMAN] = 'h';
        t[GLYPH_ELF] = 'e';
        t[GLYPH_DWARF] = 'd';
        t[GLYPH_GNOME] = 'g';
        t[GLYPH_HOBBIT] = 'g';

        t[GLYPH_LAST + 1] = 1;
    }

    if (c == 0)
        return ' ';
    if (c < GLYPH_FIRST)
        return (c >= 32 && c < 127) ? (char)c : '?';
    if (c > GLYPH_LAST)
        return '?';
    return t[c] ? t[c] : '?';
}

/*****************************************************************************\
*                                  posixTerm                                  *
*                              main() Function                                *
\*****************************************************************************/

/* SIGALRM, so a game that stops asking for keys still ends. Only write() and
   _exit() are safe to call from a signal handler, so the message is a fixed
   string and the log line is left to the harness. */
static void OnTimeout(int sig) {
    const char msg[] = "incursion: watchdog timeout, no key read in time\n";
    ssize_t ignored = write(2, msg, sizeof(msg) - 1);
    (void)ignored;
    (void)sig;
    _exit(EXIT_OUT_OF_TIME);
}

/* src/Dump.cpp. Declared here rather than added to a header because it is
   used from exactly one call site, main(), the same way InitGodArrays() is
   forward-declared locally in src/Registry.cpp. */
extern bool RunSaveDump(const char *path);

/* src/SaveV1.cpp; declared locally for the same reason as RunSaveDump.
   Returns the process exit code directly (0 converted, 2 error, 3 refused
   -- the fixture guard), so main() passes it through unmapped. */
extern int RunSaveConvert(const char *path);

int main(int argc, char *argv[]) {
    char executablePath[MAX_PATH_LENGTH] = "";
    char *envPath = getenv("INCURSIONPATH");
    const char *keyScript = NULL;
    const char *loadSave = NULL;
    const char *dumpSave = NULL;
    const char *schemaTest = NULL;
    const char *schemaLoad = NULL;
    const char *convertSave = NULL;
    int i, retval = 0;
    bool forceHeadless = false;
    unsigned timeout = DEFAULT_TIMEOUT_S;

#ifdef DIVERGE_PROBE
    /* First thing, before the game builds anything: read INCURSION_LAYOUT, so
       that every Object allocated after this lands where that number says.
       Unset, this returns at once and nothing changes. See src/Base.cpp and
       tools/check_layout.sh. Only this backend calls it -- the hunt runs
       headless, and a knob nobody uses in the window build is a knob that
       rots. */
    { extern void SetHeapLayout(void); SetHeapLayout(); }
#endif

    if (envPath != NULL) {
        if (strlen(envPath) > 0 && strcat(executablePath, envPath)) {
            if (executablePath[strlen(executablePath) - 1] != '/')
                strncat(executablePath, "/", 1);
        }
    }

    if (strlen(executablePath) == 0 && argc >= 1) {
        const char *str = strrchr(argv[0], '/');
        if (str != NULL) {
            size_t n = str - argv[0];
            if (!strncpy(executablePath, argv[0], n))
                Error("Failed to locate Incursion directory for '%s'", argv[0]);
            executablePath[n] = '\0';
        }
    }

    if (strlen(executablePath) == 0) {
        if (!getcwd(executablePath, MAX_PATH_LENGTH))
            Error("Failed to locate Incursion directory (error 23)");
    }

    /* Must be absolute. ChangeDirectory() returns to the game folder by
       chdir()ing to IncursionDirectory, so a relative path makes that call a
       no-op and the next LoadModules() hits Fatal(). See src/Wlibtcod.cpp. */
    {
        char resolvedPath[MAX_PATH_LENGTH];
        if (realpath(executablePath, resolvedPath)) {
            strncpy(executablePath, resolvedPath, MAX_PATH_LENGTH - 1);
            executablePath[MAX_PATH_LENGTH - 1] = '\0';
        }
    }

    /* Parsed here rather than in TextTerm::RunOnCommandLine, which stops at ten
       options and knows nothing about a terminal. Unknown options are ignored
       there, so both parsers can read the same command line.

       -dump belongs here for the same reason -keys does: RunOnCommandLine's
       own parser (src/TextTerm.cpp:39) caps an option's value at 49 chars
       (option_values[10][50]), and a real save path -- an absolute one
       especially, which is what a sandboxed caller must pass -- routinely
       runs longer than that and would be silently truncated to a path that
       does not exist. */
    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-keys") && i + 1 < argc)
            keyScript = argv[++i];
        else if (!strcmp(argv[i], "-load") && i + 1 < argc)
            loadSave = argv[++i];
        else if (!strcmp(argv[i], "-timeout") && i + 1 < argc)
            timeout = (unsigned)atoi(argv[++i]);
        else if (!strcmp(argv[i], "-headless"))
            forceHeadless = true;
        else if (!strcmp(argv[i], "-dump") && i + 1 < argc)
            dumpSave = argv[++i];
        else if (!strcmp(argv[i], "-schematest") && i + 1 < argc)
            schemaTest = argv[++i];
        else if (!strcmp(argv[i], "-schemaload") && i + 1 < argc)
            schemaLoad = argv[++i];
        else if (!strcmp(argv[i], "-convert")) {
            /* Unlike its siblings, -convert with no value exits 2 rather
               than falling through to the menu: it REWRITES the named file,
               so a mangled invocation must stop, not play. */
            if (i + 1 >= argc) {
                fprintf(stderr, "usage: incursion -convert <file>\n");
                return 2;
            }
            convertSave = argv[++i];
        }
    }

    theGame = new Game();
    AT1 = new posixTerm;
    AT1->SetIncursionDirectory(executablePath);
    T1 = AT1;

    /* Draw to the terminal when there is one. A pipe, a cron job or a run
       under a harness has no tty, and there the game draws to files only --
       which means nobody has to remember a flag for the common case. */
    AT1->UseTerminal(!forceHeadless && isatty(1) && isatty(0));

    if (getenv("INCURSION_MAX_KEYS"))
        AT1->SetMaxKeys(atoi(getenv("INCURSION_MAX_KEYS")));

    if (keyScript)
        AT1->LoadKeyScript(keyScript);

    /* The watchdog guards an unattended run. A person sitting at a terminal
       is allowed to think for as long as they like. */
    if (timeout && (forceHeadless || !isatty(0))) {
        signal(SIGALRM, OnTimeout);
        alarm(timeout);
    }

    /* Anything that runs at this point should not use the display. -dump
       skips RunOnCommandLine entirely (see the comment above the -dump
       parse, on the 49-char option-value cap) but follows the same rule
       its sibling flags do: it exits before Initialize()/StartMenu() run,
       exactly the way -compile and -formatid do by returning true from
       RunOnCommandLine (src/TextTerm.cpp:39). */
    if (dumpSave) {
        retval = RunSaveDump(dumpSave) ? 0 : 22;
    } else if (schemaTest) {
        retval = RunSchemaTest(schemaTest) ? 0 : 22;
    } else if (schemaLoad) {
        retval = RunSchemaLoad(schemaLoad) ? 0 : 22;
    } else if (convertSave) {
        retval = RunSaveConvert(convertSave);
    } else if (!AT1->RunOnCommandLine(argc, argv, &retval)) {
        T1->Initialize();
        if (loadSave) {
            if (theGame->LoadModules() && theGame->LoadNamedGame(loadSave)) {
                theGame->Play();
                theGame->Cleanup();
            } else {
                retval = 2;
            }
        } else {
            theGame->StartMenu();
        }
        T1->ShutDown();
    }

    delete theGame;
    return retval;
}

/*****************************************************************************\
*                                  posixTerm                                  *
*                            Low-Level Read/Write                             *
\*****************************************************************************/

/* The game's sixteen colours are in CGA order; curses names them in ANSI
   order, which is not the same order. The eight bright colours are the eight
   dark ones with A_BOLD, which is all a terminal offers -- so a bright
   background cannot be shown, and is drawn as its dark twin. */
static const short CursesColour[8] = {
    COLOR_BLACK,    /* BLACK  */
    COLOR_BLUE,     /* BLUE   */
    COLOR_GREEN,    /* GREEN  */
    COLOR_CYAN,     /* CYAN   */
    COLOR_RED,      /* RED    */
    COLOR_MAGENTA,  /* PURPLE */
    COLOR_YELLOW,   /* BROWN  */
    COLOR_WHITE     /* GREY   */
};

static int ColourPair(uint16 fg, uint16 bg) {
    return 1 + (fg & 7) + 8 * (bg & 7);
}

void posixTerm::Update() {
    int16 x, y;

    if (useCurses) {
        for (y = 0; y < SCREEN_H; y++)
            for (x = 0; x < SCREEN_W; x++) {
                Glyph g = scr[y][x];
                uint16 fg = GLYPH_FORE_VALUE(g), bg = GLYPH_BACK_VALUE(g);
                /* ponytail: ASCII only, the same letters the screen dumps
                   use. Ceiling: the box-drawing and shading glyphs come out
                   as -, | and #, so the map reads but does not look like the
                   window build. Upgrade path: setlocale, build with the
                   wide-character curses and draw the Unicode code points
                   src/Wcurses.cpp already lists for every glyph. */
                chtype c = (unsigned char)glyph_to_ascii(g);
                c |= COLOR_PAIR(ColourPair(fg, bg));
                if (fg & 8)
                    c |= A_BOLD;
                mvaddch(y, x, c);
            }
        move(cy, cx);
        refresh();
    }

    updated = true;
}

void posixTerm::StopWatch(int16 milli) {
    /* Nothing to wait for with no display: the animation is being written to
       a file, and a scripted run should not spend its night asleep. */
    if (!useCurses)
        return;
    switch (p ? p->Opt(OPT_ANIMATION) : 0) {
    case 0: napms(milli); return;
    case 1: napms((milli + 3) / 4); return;
    case 2: return;
    }
}

void posixTerm::Save() {
    memcpy(sav, scr, sizeof(scr));
}

void posixTerm::Restore() {
    memcpy(scr, sav, sizeof(scr));
}

void posixTerm::PutChar(Glyph g) {
    APutChar(cx++, cy, g);
}

void posixTerm::APutChar(int16 x, int16 y, Glyph g) {
    uint16 fg = GLYPH_FORE_VALUE(g);
    uint16 bg = GLYPH_BACK_VALUE(g);

    if (x < 0 || x >= SCREEN_W || y < 0 || y >= SCREEN_H)
        return;

    /* A glyph with no colour of its own takes the current pen, exactly as the
       other two backends do. */
    if (fg == 0 && bg == 0)
        g = GLYPH_ID_VALUE(g)
          | GLYPH_FORE(attr & COLOUR_MASK)
          | GLYPH_BACK((attr >> COLOUR_BITS) & COLOUR_MASK);

    scr[y][x] = g;
    updated = false;
}

void posixTerm::PutChar(int16 x, int16 y, Glyph g) {
    APutChar(x + activeWin->Left, y + activeWin->Top, g);
}

/* Exact, where the other backends are not: they store the character their
   glyph table produced and cannot recover the glyph id from it. The five call
   sites (Term.cpp:2164, Term.cpp:2167, Magic.cpp:1324, Skills.cpp:1931 and
   Skills.cpp:2844)
   mask the result with GLYPH_ID_MASK and put it straight back, so an exact
   round trip is what they were written to expect. */
Glyph posixTerm::AGetChar(int16 x, int16 y) {
    if (x < 0 || x >= SCREEN_W || y < 0 || y >= SCREEN_H)
        return ' ';
    return scr[y][x];
}

void posixTerm::GotoXY(int16 x, int16 y) {
    cx = x + activeWin->Left;
    cy = y + activeWin->Top;
}

void posixTerm::Clear() {
    int16 x, y;

    for (y = activeWin->Top; y <= activeWin->Bottom; y++)
        for (x = activeWin->Left; x <= activeWin->Right; x++)
            if (x >= 0 && x < SCREEN_W && y >= 0 && y < SCREEN_H)
                scr[y][x] = ' ';

    cWrap = 0; cx = cy = 0;
    if (activeWin == &Windows[WIN_SCREEN] || activeWin == &Windows[WIN_MESSAGE])
        linepos = linenum = 0;
    updated = false;
}

uint32 posixTerm::GetElapsedMilli() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000) - startMilli;
}

/*****************************************************************************\
*                                  posixTerm                                  *
*                               Scroll Buffer                                 *
\*****************************************************************************/

void posixTerm::SPutChar(int16 x, int16 y, Glyph g) {
    if (!scrollBuf || x < 0 || x >= SCROLL_WIDTH || y < 0 || y >= MAX_SCROLL_LINES)
        return;
    scrollBuf[y * SCROLL_WIDTH + x] = g;
}

uint16 posixTerm::SGetChar(int16 x, int16 y) {
    if (!scrollBuf || x < 0 || x >= SCROLL_WIDTH || y < 0 || y >= MAX_SCROLL_LINES)
        return ' ';
    return (uint16)GLYPH_ID_VALUE(scrollBuf[y * SCROLL_WIDTH + x]);
}

void posixTerm::SPutColor(int16 x, int16 y, uint16 col) {
    if (!scrollBuf || x < 0 || x >= SCROLL_WIDTH || y < 0 || y >= MAX_SCROLL_LINES)
        return;
    scrollBuf[y * SCROLL_WIDTH + x] =
        GLYPH_ID_VALUE(scrollBuf[y * SCROLL_WIDTH + x]) | GLYPH_ATTR(col);
}

uint16 posixTerm::SGetColor(int16 x, int16 y) {
    if (!scrollBuf || x < 0 || x >= SCROLL_WIDTH || y < 0 || y >= MAX_SCROLL_LINES)
        return 0;
    return (uint16)GLYPH_COLOUR_VALUE(scrollBuf[y * SCROLL_WIDTH + x]);
}

void posixTerm::SClear() {
    int32 i;
    if (!scrollBuf)
        return;
    for (i = 0; i < MAX_SCROLL_LINES * SCROLL_WIDTH; i++)
        scrollBuf[i] = ' ';
}

void posixTerm::BlitScrollLine(int16 wn, int32 buffline, int32 winline) {
    int16 i, width = min((int16)SCROLL_WIDTH, WinSizeX());

    if (!scrollBuf)
        return;
    for (i = 0; i < width; i++)
        APutChar(Windows[wn].Left + i, Windows[wn].Top + (int16)winline,
            scrollBuf[buffline * SCROLL_WIDTH + i]);
}

/*****************************************************************************\
*                                  posixTerm                                  *
*                               Screen Capture                                *
\*****************************************************************************/

/* One numbered file per dump, under logs/screens. The path is built from
   IncursionDirectory because the game chdir()s into its own subdirectories
   while it runs, so the current directory is not a fixed point. */
/* One row of the screen as ASCII, NUL-terminated.

   Every screen-reading feature goes through this, so what a script can match
   is exactly what a dump in logs/screens shows. */
void posixTerm::RenderRow(int16 y, char *line) {
    int16 x;

    for (x = 0; x < SCREEN_W; x++)
        line[x] = glyph_to_ascii(scr[y][x]);
    line[SCREEN_W] = '\0';
}

void posixTerm::DumpScreen(const char *label) {
    char path[MAX_PATH_LENGTH], dir[MAX_PATH_LENGTH];
    char line[SCREEN_W + 2];
    int16 y, last;
    FILE *f;

    snprintf(dir, sizeof(dir), "%slogs/screens", (const char*)IncursionDirectory);
    _mkdir(dir);
    snprintf(path, sizeof(path), "%s/%04d%s%s.txt", dir, (int)++dumpCount,
        (label && *label) ? "-" : "", (label && *label) ? label : "");

    f = fopen(path, "w");
    if (!f)
        return;

    /* The turn counter goes in the header because a dump is otherwise blind
       to whether the session is still playing. A run can consume every
       keystroke it has while parked in a modal screen -- Inventory Mode, the
       death prompt, the threat-disengage prompt -- and produce a full set of
       dumps that look like a session and contain no gameplay. Comparing this
       number between two dumps is the only cheap way to tell the difference,
       and it is what tools/check_clock_advance.sh reads. See inc-2k3. */
    fprintf(f, "=== screen %04d %s  key %ld  mode %d  turn %u ===\n",
        (int)dumpCount, (label && *label) ? label : "", (long)keysRead,
        (int)Mode, theGame ? (unsigned)theGame->Turn : 0u);

    for (y = 0; y < SCREEN_H; y++) {
        RenderRow(y, line);
        /* Trailing blanks carry no information and make the file three times
           the size it needs to be. */
        for (last = SCREEN_W - 1; last >= 0 && line[last] == ' '; last--)
            ;
        line[last + 1] = '\0';
        fprintf(f, "%s\n", line);
    }

    fclose(f);
}

/* Is this text anywhere on the screen right now?

   The match is per row, so a phrase that wraps across two lines will not be
   found. Keep the text short and take it from the middle of a prompt rather
   than its ends: a prompt is often drawn with a border, a colour change or a
   trailing count, and any of those can sit between the words.

   This reads the same buffer DumpScreen writes, through the same conversion,
   so what a script can match is exactly what appears in logs/screens. */
bool posixTerm::ScreenShows(const char *text) {
    char line[SCREEN_W + 1];
    int16 y;

    if (!text || !*text)
        return false;

    for (y = 0; y < SCREEN_H; y++) {
        RenderRow(y, line);
        if (strstr(line, text))
            return true;
    }
    return false;
}

/* Compare only the overlap, and ignore case.

   The menus truncate. LMenu cuts every entry to the column width at
   src/TextTerm.cpp:1022, so the prestige list draws "[e] Celestial Initiat"
   for a class whose name is longer. A directive that reports "not found" for
   a name plainly on the screen is worse than the counting it replaces, so the
   comparison stops when either side runs out.

   The cost is that a short name is also a prefix of longer ones, and on the
   alignment screen that is not hypothetical: "[e] Neutral" sits beside
   "[b] Neutral Good" and "[h] Neutral Evil". So an overlap match is the
   weaker answer, and an entry that matches the name outright beats it.
   FindMenuEntry keeps the two apart and takes the exact one when there is
   one. Only a genuine tie stops the run.

   Returns 2 for an exact match, 1 for an overlap, 0 for neither. */
static int NameMatches(const char *want, const char *shown) {
    const char *w = want, *h = shown;

    if (!*w || !*h)
        return 0;

    while (*w && *h) {
        if (tolower((unsigned char)*w) != tolower((unsigned char)*h))
            return 0;
        w++;
        h++;
    }
    return (!*w && !*h) ? 2 : 1;
}

/* Where a menu entry's name ends: at two spaces, at the next '[', or at the
   end of the row. Menus put their second and third columns after a gap, and
   the character sheet writes "[P]restige Classes [PGUP/PGDN] Scroll" on one
   row, so both have to end a name. */
static void MenuLabel(const char *from, char *out, size_t sz) {
    size_t n = 0;

    while (*from && n < sz - 1) {
        if (from[0] == '[')
            break;
        if (from[0] == ' ' && from[1] == ' ')
            break;
        out[n++] = *from++;
    }
    while (n && out[n - 1] == ' ')
        n--;
    out[n] = '\0';
}

/* Find "[X] name" on the screen: report the letter, and where the name starts.

   The menu IS the mapping, and it is the only copy of it that is true at
   runtime. A script that names the entry it wants reads the letter the game
   has just printed beside that name, so adding a class to lib/ cannot make
   the script pick a different one. Counting keystrokes to the same place --
   DOWN nine times for the Loremaster -- silently picks the neighbour instead.

   Only "[X]" with exactly one character between the brackets is a menu key.
   That rejects "[ESC]", "[PGUP/PGDN]" and "[yn]", which share rows with real
   entries on the character sheet.

   A BLANK bracket, "[ ]", counts. It is not a decoration: LMenu draws it for
   every entry past the 52nd, because MenuLetters (src/TextTerm.cpp) runs out
   of letters there, and the feat list is long enough to reach it -- Toughness
   is drawn as "[ ] Toughness". Such an entry can be selected only by moving
   the cursor onto it and pressing ENTER (src/TextTerm.cpp:1164-1172); the
   space bar does nothing at all in a menu (:1198). So @cursorto must be able
   to find it, and @choose must refuse it rather than send a key that would
   land somewhere else.

   Two forms of name are tried per bracket, because the game writes both:
   "[e] Elf" puts the name after a space, and "[P]restige Classes" runs the
   bracketed letter straight into it. */
bool posixTerm::FindMenuEntry(const char *name, char *key, int16 *ey,
                              int16 *ex, const char **why) {
    char line[SCREEN_W + 1], label[SCREEN_W + 2], joined[SCREEN_W + 3];
    char best[2] = { 0, 0 };
    int16 bestY[2] = { 0, 0 }, bestX[2] = { 0, 0 };
    bool tied[2] = { false, false };
    const char *after;
    int16 x, y;
    int rank;

    *why = "@choose";
    for (y = 0; y < SCREEN_H; y++) {
        RenderRow(y, line);
        for (x = 0; x + 3 <= SCREEN_W; x++) {
            if (line[x] != '[' || line[x + 2] != ']')
                continue;
            if (line[x + 1] == '[' || line[x + 1] == ']')
                continue;

            MenuLabel(line + x + 3, label, sizeof(label));
            snprintf(joined, sizeof(joined), "%c%s", line[x + 1], label);
            for (after = label; *after == ' '; after++)
                ;

            rank = NameMatches(name, after);
            if (NameMatches(name, joined) > rank)
                rank = NameMatches(name, joined);
            if (!rank)
                continue;
            rank--;                             /* 0 overlap, 1 exact */

            /* The same letter twice is still one answer -- a menu may repeat
               an entry, and the character sheet draws its command bar on
               every page. Two different letters at the same strength is a
               name that does not pick one entry out. */
            if (best[rank] && best[rank] != line[x + 1]) {
                tied[rank] = true;
                continue;
            }
            best[rank] = line[x + 1];
            bestY[rank] = y;
            bestX[rank] = (int16)(x + 3 + (after - label));
        }
    }

    for (rank = 1; rank >= 0; rank--) {
        if (!best[rank])
            continue;
        if (tied[rank]) {
            *why = "@choose (the name matches two entries)";
            return false;
        }
        *key = best[rank];
        *ey = bestY[rank];
        *ex = bestX[rank];
        return true;
    }

    *why = "@choose (no entry with that name is on screen)";
    return false;
}

/* Is the cursor on the row that holds this text?

   Two ways of marking a row, and they cannot be merged, so a script says
   which one it is looking at. Guessing would drive the wrong row in silence,
   which is the failure this whole directive exists to end.

   A HIGHLIGHT is what a menu uses. LMenu draws the current entry's name in
   AZURE, having stripped its colour codes with Decolorize first, and every
   other entry in whatever colour its own text asks for
   (src/TextTerm.cpp:1094-1100). So the test is "this name is AZURE", and it
   must be that way round. The obvious alternative -- "this name is not the
   dim GREY the other entries use" -- is wrong, and the feat menu proves it:
   Player::GainFeat builds every entry as "<YELLOW>name<GREY>"
   (src/Create.cpp:2580-2584), so on that screen no name is GREY and a
   not-dimmed test reports the cursor as already arrived on the first row it
   is asked about, having moved nothing.

   It is anchored on the "[X] " bracket, which matters for the same reason:
   MENU_DESC menus print a description beside the list, and that description
   is neither highlighted nor bracketed. Without the anchor, a class whose
   description repeats its own name would satisfy the test by accident.

   A MARKER is what the Skill Manager uses. It writes a literal '>' beside the
   current skill (src/Managers.cpp:1664, and the two arrow cases at :1711 and
   :1724) and colours every in-class skill EMERALD whether it is current or
   not -- so colour means nothing there, and there is no bracket either. The
   test walks left from the name over the gap: on the current row the first
   thing it meets is the marker, and on any other row it is the window border,
   which stops the walk before it can reach the map behind the window and find
   a down-staircase '>'. The Spell Manager marks its rows the same way but
   puts a bracketed spell key between the marker and the name, so the walk
   steps over a "[X]" group as well as over spaces.

   Both fail closed. A mode used on the wrong screen finds nothing, so the
   caller keeps pressing and then stops with a message, rather than reporting
   an arrival that did not happen. */
bool posixTerm::CursorOnRow(const char *text, bool byMark) {
    char line[SCREEN_W + 1];
    const char *at, *why;
    char key;
    int16 x, y;

    if (!byMark) {
        if (!FindMenuEntry(text, &key, &y, &x, &why))
            return false;
        return GLYPH_FORE_VALUE(scr[y][x]) == SK_MENU_CURSOR;
    }

    for (y = 0; y < SCREEN_H; y++) {
        RenderRow(y, line);
        at = strstr(line, text);
        if (!at)
            continue;
        for (x = (int16)(at - line) - 1; x >= 0; x--) {
            if (line[x] == ' ')
                continue;
            if (line[x] == SK_CURSOR_MARK)
                return true;
            /* A bracketed key may sit between the marker and the name. The
               Spell Manager writes "> [b] Fiendish Servant": the marker at
               column 0 (src/Managers.cpp:313) and the spell's own key beside
               the name. Step over the whole "[X]" group and keep walking, so
               one directive reads both managers. Anything else stops the
               walk, which is what keeps it off the map behind the window. */
            if (line[x] == ']' && x >= 2 && line[x - 2] == '[') {
                x -= 2;
                continue;
            }
            break;
        }
    }
    return false;
}

/* A directive that could not do what it was told stops the run, and takes the
   screen it was reading with it. The alternative is the thing these
   directives exist to end: a script that misses its target, carries on, and
   produces a plausible run of the wrong character. */
void posixTerm::ScriptFailed(const char *what, const char *detail) {
    DumpScreen("script-failed");
    fprintf(stderr, "incursion: %s \"%s\" failed; see the last screen dump\n",
        what, detail);
    exit(EXIT_SCRIPT_FAILED);
}

/*****************************************************************************\
*                                  posixTerm                                  *
*                              Input Functions                                *
\*****************************************************************************/

/* The script is a token stream: whitespace separates tokens, '#' starts a
   comment, and a double-quoted run becomes one keystroke per character. A
   trailing *N repeats the token N times.

   @include pulls in another script, resolved next to the file that names it.
   Every test script starts by making a character, and that sequence is forty
   keystrokes long; without an include, changing it would mean editing every
   script that exists.

   @while "text" KEY and @until "text" KEY are the only conditionals, and they
   exist because a fixed stream cannot make a character reliably. Character
   generation does not ask the same questions every time: the number of feats
   offered varies with the class roll, and the god question appears only for
   some. One extra prompt puts every later keystroke against the wrong
   question, which is why 27 sessions in 906 never escaped chargen. A script
   that waits for the prompt it means to answer stays synchronised no matter
   what came before it.

       @until "Choose a domain" ENTER      # press ENTER until that appears
       d 3 ENTER                           # then answer it
       @while "wish to worship" y          # answer it only if it is asked

   The body is the rest of the line and may be several keys, because the case
   this was built for needs that: the Skill Manager will not let go while any
   rank is unspent, the size of the pool varies with the god, and draining it
   takes RIGHT to spend and DOWN to move on.

       @while "Unspent Skill Ranks" RIGHT RIGHT RIGHT DOWN

   Both are bounded by SK_LOOP_MAX passes and then give up, so a script cannot
   hang on a prompt that never comes or never clears.

   @choose, @cursorto and @expect read the screen the same way, and exist
   because counting does not survive the game changing. A menu letter is a
   position in a list built from lib/, so adding one prestige class moves
   every letter after it -- and a script that counted DOWN nine times to reach
   the Loremaster then reads a different class and passes.

       @choose "Loremaster"                 # press the letter beside the name
       @cursorto "Loremaster" DOWN          # highlight it without taking it
       @cursorto:mark "Ride" DOWN           # the Skill Manager's '>' cursor
       @expect "Choose a class:"            # stop here if this is the wrong screen

   Use @choose to pick from a menu: LMenu returns the moment its letter is
   pressed (src/TextTerm.cpp:1217-1231), so the entry is taken, not merely
   highlighted. Use @cursorto when the point is to look rather than to choose,
   or on a list that has no letters at all. See CursorOnRow for why the two
   cursor styles are named separately instead of being guessed at.

   A name is matched against what the menu drew, ignoring case, over the
   shorter of the two -- the menus truncate. A name that fits two entries, or
   fits none, stops the run with EXIT_SCRIPT_FAILED and a screen dump. */
/* The one argument every screen-driven directive takes: a quoted run of
   screen text. Reads up to and including the closing quote. */
static void ReadQuoted(FILE *f, const char *fn, const char *tok,
                       char *out, size_t sz) {
    int c, n = 0;

    while ((c = fgetc(f)) != EOF && isspace(c))
        ;
    if (c != '"') {
        printf("Key script '%s': %s needs a quoted screen text.\n", fn, tok);
        exit(2);
    }
    while ((c = fgetc(f)) != EOF && c != '"' && n < (int)sz - 1)
        out[n++] = (char)c;
    out[n] = '\0';
    if (!n) {
        printf("Key script '%s': %s was given an empty text.\n", fn, tok);
        exit(2);
    }
}

void posixTerm::AppendKey(const ScriptKey &k) {
    if (keyCount == keyAlloc) {
        ScriptKey *bigger;

        keyAlloc = keyAlloc ? keyAlloc * 2 : 1024;
        bigger = (ScriptKey*)realloc(keys, keyAlloc * sizeof(ScriptKey));
        if (!bigger) {
            printf("Out of memory reading the key script (%ld keys).\n",
                (long)keyCount);
            exit(2);
        }
        keys = bigger;
    }
    keys[keyCount++] = k;
}

void posixTerm::LoadKeyScript(const char *fn) {
    static int depth = 0;
    FILE *f = fopen(fn, "r");
    char tok[MAX_PATH_LENGTH];
    int c;

    if (!f) {
        printf("Cannot open key script '%s'.\n", fn);
        exit(2);
    }
    if (++depth > 8) {
        printf("Key script '%s': includes are nested too deeply.\n", fn);
        exit(2);
    }

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
            /* Each character of the string is its own keystroke. */
            while ((c = fgetc(f)) != EOF && c != '"') {
                char one[2] = { (char)c, 0 };
                if (TokenToKey(one, &k))
                    AppendKey(k);
            }
            continue;
        }

        tok[n++] = (char)c;
        while ((c = fgetc(f)) != EOF && !isspace(c) && n < (int)sizeof(tok) - 1)
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

            /* Resolved next to the including file, so a script can be moved
               with its parts. */
            slash = strrchr(fn, '/');
            if (inc[0] == '/' || !slash)
                snprintf(resolved, sizeof(resolved), "%s", inc);
            else
                snprintf(resolved, sizeof(resolved), "%.*s%s",
                    (int)(slash - fn + 1), fn, inc);
            LoadKeyScript(resolved);
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
                printf("Key script '%s': @pause needs a positive integer of "
                    "milliseconds, and got '%s'.\n", fn, ms);
                exit(2);
            }

            memset(&k, 0, sizeof(k));
            k.ch = SK_PAUSE;
            k.pauseMs = (int32)value;
            AppendKey(k);
            continue;
        }

        /* @choose "name"  -- press the letter the game printed beside name.
           @expect "text"   -- stop the run unless the screen shows text.

           Neither takes a key: @choose works out its own, and @expect is an
           assertion rather than a keystroke. */
        if (!strcmp(tok, "@choose") || !strcmp(tok, "@expect")) {
            memset(&k, 0, sizeof(k));
            k.ch = !strcmp(tok, "@choose") ? SK_CHOOSE : SK_EXPECT;
            ReadQuoted(f, fn, tok, k.label, sizeof(k.label));
            AppendKey(k);
            continue;
        }

        /* @while "text" KEY  -- send KEY for as long as the screen shows text.
           @until "text" KEY  -- send KEY until the screen shows text.
           @cursorto "name" KEY       -- send KEY until name is highlighted.
           @cursorto:mark "name" KEY  -- ...until a '>' marks name's row.

           Each takes one quoted screen text and then a body of ordinary
           keys. */
        if (!strcmp(tok, "@while") || !strcmp(tok, "@until") ||
            !strcmp(tok, "@cursorto") || !strcmp(tok, "@cursorto:mark")) {
            char keytok[MAX_PATH_LENGTH];
            ScriptKey loop;

            memset(&k, 0, sizeof(k));
            if (!strcmp(tok, "@while"))
                k.ch = SK_WHILE;
            else if (!strcmp(tok, "@until"))
                k.ch = SK_UNTIL;
            else {
                k.ch = SK_CURSOR;
                k.byMark = !strcmp(tok, "@cursorto:mark");
            }

            ReadQuoted(f, fn, tok, k.label, sizeof(k.label));

            /* The body is the rest of the LINE, so the newline is what ends
               it -- every other token in this format is whitespace-delimited
               and a body of one key would otherwise be indistinguishable from
               a body of the whole remaining script. */
            for (;;) {
                while ((c = fgetc(f)) != EOF && (c == ' ' || c == '\t'))
                    ;
                if (c == EOF || c == '\n')
                    break;
                if (c == '#') {
                    while ((c = fgetc(f)) != EOF && c != '\n')
                        ;
                    break;
                }

                n = 0;
                while (c != EOF && !isspace(c) && n < (int)sizeof(keytok) - 1) {
                    keytok[n++] = (char)c;
                    c = fgetc(f);
                }
                keytok[n] = '\0';

                /* A @dump or a @quit in a body would fire once per pass and is
                   always a mistake. */
                if (!TokenToKey(keytok, &loop) || loop.ch < 0) {
                    printf("Key script '%s': %s takes ordinary keys after its "
                        "text, and got '%s'.\n", fn, tok, keytok);
                    exit(2);
                }
                if (k.bodyCount >= SK_BODY_MAX) {
                    printf("Key script '%s': %s \"%s\" has more than %d keys "
                        "in its body.\n", fn, tok, k.label, SK_BODY_MAX);
                    exit(2);
                }
                k.bodyCh[k.bodyCount] = loop.ch;
                k.bodyMods[k.bodyCount] = loop.mods;
                k.bodyCount++;

                if (c == '\n' || c == EOF)
                    break;
            }

            if (!k.bodyCount) {
                printf("Key script '%s': %s \"%s\" has no keys after it.\n",
                    fn, tok, k.label);
                exit(2);
            }
            AppendKey(k);
            continue;
        }

        /* A trailing *N is a repeat count, but a bare '*' is the key that
           targets yourself, so only a token longer than one character can
           carry one. */
        if (n > 1) {
            char *star = strrchr(tok, '*');
            if (star && star != tok && isdigit((unsigned char)star[1])) {
                repeat = atoi(star + 1);
                *star = '\0';
                if (repeat < 1)
                    repeat = 1;
            }
        }

        if (!TokenToKey(tok, &k)) {
            printf("Key script '%s': cannot read token '%s'.\n", fn, tok);
            exit(2);
        }

        for (i = 0; i < repeat; i++)
            AppendKey(k);
    }

    fclose(f);
    depth--;
}

/* A run that has used its budget stops rather than spinning. The screen goes
   with it, because a run that ends without one cannot be diagnosed. */
void posixTerm::OutOfKeys() {
    DumpScreen("final");
    fprintf(stderr, "incursion: key script exhausted after %ld keys\n",
        (long)keysRead);
    exit(keyNext >= keyCount ? 0 : EXIT_OUT_OF_KEYS);
}

/* One keystroke from a real terminal, translated into the same values a
   script token produces, so everything downstream is unaware of the source.
   Control keys arrive as codes 1 to 26 and carry no modifier byte of their
   own, which is what the CONTROL flag is reconstructed from. */
static ScriptKey KeyFromTerminal() {
    ScriptKey k;
    int c = getch();

    memset(&k, 0, sizeof(k));

    switch (c) {
    case KEY_UP:        k.ch = KY_UP;        return k;
    case KEY_DOWN:      k.ch = KY_DOWN;      return k;
    case KEY_LEFT:      k.ch = KY_LEFT;      return k;
    case KEY_RIGHT:     k.ch = KY_RIGHT;     return k;
    case KEY_PPAGE:     k.ch = KY_PGUP;      return k;
    case KEY_NPAGE:     k.ch = KY_PGDN;      return k;
    case KEY_HOME:      k.ch = KY_HOME;      return k;
    case KEY_END:       k.ch = KY_END;       return k;
    case KEY_BACKSPACE:
    case 127:           k.ch = KY_BACKSPACE; return k;
    case 27:            k.ch = KY_ESC;       return k;
    case 10:
    case 13:
    case KEY_ENTER:     k.ch = KY_ENTER;     return k;
    case 9:             k.ch = KY_TAB;       return k;
    }

    if (c >= KEY_F(1) && c <= KEY_F(12)) {
        k.ch = KY_CMD_MACRO1 + (c - KEY_F(1));
        return k;
    }
    if (c >= 1 && c <= 26) {
        k.ch = 'a' + c - 1;
        k.mods = CONTROL;
        return k;
    }
    if (c >= KEY_MIN) {
        k.ch = KY_REDRAW;               /* a key with no meaning here */
        return k;
    }

    k.ch = c;
    if (isupper(c))
        k.mods = SHIFT;
    return k;
}

ScriptKey posixTerm::NextKey() {
    ScriptKey k;

    /* A script always wins, even on a terminal: that is how a scripted run
       can be watched as it plays. The keyboard is read only when no script
       was given. */
    if (useCurses && !keys)
        return KeyFromTerminal();

    if (keysRead >= maxKeys) {
        DumpScreen("maxkeys");
        fprintf(stderr, "incursion: key budget of %ld reached\n", (long)maxKeys);
        exit(EXIT_OUT_OF_KEYS);
    }

    /* A conditional stays put until its condition flips, so keyNext is not
       advanced while it is still firing. The screen it reads is the one the
       caller has just drawn -- GetCharCmd calls Update() before asking. */
    for (;;) {
        ScriptKey *e;

        if (!keys || keyNext >= keyCount)
            OutOfKeys();

        e = &keys[keyNext];

        if (e->ch == SK_PAUSE) {
            keyNext++;
            continue;
        }

        /* Neither of these is a keystroke. @expect asserts and steps aside;
           @choose reads the menu and becomes the letter it found there. */
        if (e->ch == SK_EXPECT) {
            if (!ScreenShows(e->label))
                ScriptFailed("@expect", e->label);
            keyNext++;
            continue;
        }
        if (e->ch == SK_CHOOSE) {
            const char *why;
            int16 ey, ex;
            char letter = 0;

            if (!FindMenuEntry(e->label, &letter, &ey, &ex, &why))
                ScriptFailed(why, e->label);

            /* The entry is there, but the menu ran out of letters before it
               reached it. Pressing space would not choose it -- a menu
               ignores the space bar -- so say so instead of sending a key
               that goes nowhere. */
            if (letter == ' ')
                ScriptFailed("@choose (that entry has no letter; use "
                             "@cursorto and ENTER)", e->label);

            memset(&k, 0, sizeof(k));
            k.ch = (unsigned char)letter;
            if (isupper((unsigned char)letter))
                k.mods = SHIFT;
            keyNext++;
            keysRead++;
            if (!useCurses)
                alarm(DEFAULT_TIMEOUT_S);
            return k;
        }

        if (e->ch != SK_WHILE && e->ch != SK_UNTIL && e->ch != SK_CURSOR)
            break;

        /* The condition is tested only at the top of a pass. Testing between
           the keys of one pass could stop halfway through RIGHT RIGHT RIGHT
           DOWN and leave the cursor on a half-spent skill. */
        if (e->bodyPos == 0) {
            bool fire;

            if (e->ch == SK_WHILE)
                fire = ScreenShows(e->label);
            else if (e->ch == SK_UNTIL)
                fire = !ScreenShows(e->label);
            else
                fire = !CursorOnRow(e->label, e->byMark);

            if (!fire || e->iter >= SK_LOOP_MAX) {
                if (fire) {
                    /* @while and @until shrug and move on, because a prompt
                       that never came is often a prompt that was never going
                       to be asked. @cursorto cannot shrug: the cursor is then
                       sitting on some other row, and every key after this one
                       would be spent on the wrong thing. */
                    if (e->ch == SK_CURSOR)
                        ScriptFailed(e->byMark ? "@cursorto:mark" : "@cursorto",
                            e->label);
                    fprintf(stderr, "incursion: %s \"%s\" gave up after %d "
                        "passes\n", e->ch == SK_WHILE ? "@while" : "@until",
                        e->label, SK_LOOP_MAX);
                }
                e->iter = 0;
                keyNext++;
                continue;
            }
            e->iter++;
        }

        memset(&k, 0, sizeof(k));
        k.ch = e->bodyCh[e->bodyPos];
        k.mods = e->bodyMods[e->bodyPos];
        e->bodyPos++;
        if (e->bodyPos >= e->bodyCount)
            e->bodyPos = 0;

        keysRead++;
        if (!useCurses)
            alarm(DEFAULT_TIMEOUT_S);
        return k;
    }

    keysRead++;
    k = keys[keyNext++];

    /* The watchdog measures the gap between keystrokes, not the whole run: a
       long session of real play is fine, a game that stops asking is not. It
       is never armed when a person is at the keyboard. */
    if (!useCurses)
        alarm(DEFAULT_TIMEOUT_S);
    return k;
}

int16 posixTerm::GetCharCmd(KeyCmdMode mode) {
    KeySetItem *keyset = theGame->Opt(OPT_ROGUELIKE) ? RoguelikeKeySet : StandardKeySet;
    int16 keyset_start = 0, keyset_delta = 0, keyset_last;
    int16 i, ox, oy, ch;
    TextWin *wn;

    ActionsSinceLastAutoSave++;
    if (p) p->GameTimeInfo.keystrokes++;

    if (QueuedChar) {
        ch = QueuedChar;
        QueuedChar = 0;
        return ch;
    }

    for (keyset_last = 0; keyset[keyset_last].cmd != KY_CMD_LAST; keyset_last++)
        ;
    keyset_last--;

    switch (mode) {
    case KY_CMD_NORMAL_MODE:
        keyset_start = keyset_last;
        keyset_delta = -1;
        break;
    case KY_CMD_TARGET_MODE:
    case KY_CMD_ARROW_MODE:
        keyset_start = 0;
        keyset_delta = +1;
        break;
    default:
        break;
    }

    ox = cx; oy = cy; wn = activeWin;
    if (theGame->InPlay()) {
        if (p->UpdateMap && Mode == MO_PLAY)
            RefreshMap();
        if (p->statiChanged) {
            ShowTraits();
            ShowStatus();
        }
    }

    Update();
    activeWin = wn;
    cx = ox; cy = oy;

    for (;;) {
        ScriptKey k = NextKey();

        if (k.ch == SK_DUMP) {
            DumpScreen(k.label);
            continue;
        }
        if (k.ch == SK_QUIT) {
            if (!theGame || !theGame->InPlay()) {
                ShutDown();
                exit(0);
            }
            if (GetMode() == MO_PLAY && mode == KY_CMD_NORMAL_MODE) {
                theGame->SetQuitFlag();
                return KY_CMD_QUICK_QUIT;
            }
            /* Not a moment the game can be quit from; take the next token. */
            continue;
        }

        if (Mode == MO_PLAY && p && p->UpdateMap)
            RefreshMap();
        if ((Mode == MO_PLAY || Mode == MO_INV) && p && p->statiChanged) {
            ShowTraits();
            ShowStatus();
        }

        /* No key repeat exists here, so clearing the message window is always
           safe -- the condition the window build tests for cannot arise. */
        ClearMsgOK = true;
        if (theGame->Opt(OPT_CLEAR_EVERY_TURN) && mode == KY_CMD_NORMAL_MODE
            && GetMode() == MO_PLAY) {
            ox = cx; oy = cy; wn = activeWin;
            linenum = linepos = 0;
            SetWin(WIN_MESSAGE);
            Clear();
            activeWin = wn;
            cx = ox; cy = oy;
            ClearMsgOK = false;
        }

        ControlKeys = k.mods;
        ch = k.ch;

        if (mode == KY_CMD_RAW)
            return ch;

        for (i = keyset_start; i >= 0 && keyset[i].cmd != KY_CMD_LAST; i += keyset_delta) {
            if (keyset[i].raw_key != toupper(ch))
                continue;
            if (keyset[i].raw_key_flags != -1)
                if (keyset[i].raw_key_flags != (ControlKeys & (CONTROL|SHIFT|ALT)))
                    continue;
            if (mode == KY_CMD_ARROW_MODE
                && (keyset[i].cmd < KY_CMD_FIRST_ARROW || keyset[i].cmd > KY_CMD_LAST_ARROW))
                continue;
            return keyset[i].cmd;
        }
        return ch;
    }
}

/*****************************************************************************\
*                                  posixTerm                                  *
*                             General Functions                               *
\*****************************************************************************/

/* One line of setup around the shared logger: only the backend knows which
   build it is, and IncursionDirectory lives on the terminal object. */
static void LogGameError(const char *msg) {
    char banner[256], stamp[32];
    time_t now;

    time(&now);
    strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", localtime(&now));
    snprintf(banner, sizeof(banner),
        "=== session %s  Incursion %s headless  built %s %s ===",
        stamp, VERSION_STRING, __DATE__, __TIME__);
    LogError((const char*)((posixTerm*)T1)->IncursionDirectory, msg, banner);
}

void Fatal(const char*fmt,...) {
    va_list argptr;

    va_start(argptr, fmt);
    vsnprintf(__buffer, sizeof(__buffer), fmt, argptr);
    va_end(argptr);

    if (!T1 || !((posixTerm*)T1)->initialised) {
        printf("%s\n", __buffer);
        exit(1);
    }

    LogGameError(__buffer);
    ((posixTerm*)T1)->DumpScreen("fatal");
    fprintf(stderr, "incursion: fatal: %s\n", __buffer);
    exit(1);
}

/* There is nobody to answer a prompt, so an error is logged and play goes on.
   This is the same policy the window build settled on, for the same reason:
   a single error used to freeze the game. */
void Error(const char*fmt,...) {
    va_list argptr;

    va_start(argptr, fmt);
    vsnprintf(__buffer, sizeof(__buffer), fmt, argptr);
    va_end(argptr);

    if (!T1 || !((posixTerm*)T1)->initialised) {
        printf("%s\n", __buffer);
        return;
    }

    LogGameError(__buffer);
}

void posixTerm::Initialize() {
    p = NULL;
    m = NULL;
    isHelp = false;
    ActionsSinceLastAutoSave = 0;
    cx = cy = 0;
    showCursor = false;
    OptionCount = 0;
    OffscreenC = 0;
    QueuedChar = 0;
    ControlKeys = 0;
    WViewListCount = 0;
    OptionsShown = false;
    XOff = YOff = 0;
    s1 = s2 = 0;
    MsgHistory[0] = 0;
    Mode = MO_SPLASH;
    sizeX = SCREEN_W;
    sizeY = SCREEN_H;

    if (!scrollBuf) {
        scrollBuf = (Glyph*)malloc(MAX_SCROLL_LINES * SCROLL_WIDTH * sizeof(Glyph));
        SClear();
    }

    if (useCurses) {
        int rows, cols;

        initscr();
        start_color();
        raw();
        noecho();
        keypad(stdscr, TRUE);
        curs_set(0);
        for (int fg = 0; fg < 8; fg++)
            for (int bg = 0; bg < 8; bg++)
                init_pair(ColourPair(fg, bg), CursesColour[fg], CursesColour[bg]);

        getmaxyx(stdscr, rows, cols);
        if (cols < SCREEN_W || rows < SCREEN_H) {
            endwin();
            printf("Incursion needs a terminal of at least %dx%d characters; "
                "this one is %dx%d.\n", SCREEN_W, SCREEN_H, cols, rows);
            exit(2);
        }
    }

    initialised = true;

    InitWindows();
    SetWin(WIN_SCREEN);
    Clear();
    Color(YELLOW);
}

void posixTerm::ShutDown() {
    DumpScreen("shutdown");
    if (useCurses)
        endwin();
}

void posixTerm::SetIncursionDirectory(const char *s) {
    char tmp[MAX_PATH_LENGTH] = "";

    IncursionDirectory = (const char *)s;
    if (IncursionDirectory.Right(1) != "/")
        IncursionDirectory += "/";

    strcpy(tmp, s); strcat(tmp, "/mod");  _mkdir(tmp);
    strcpy(tmp, s); strcat(tmp, "/logs"); _mkdir(tmp);
    strcpy(tmp, s); strcat(tmp, "/save"); _mkdir(tmp);
}

/*****************************************************************************\
*                                  posixTerm                                  *
*                               File I/O Code                                 *
\*****************************************************************************/

bool posixTerm::Exists(const char *fn) {
    struct stat st;
    return !stat(fn, &st) && !S_ISDIR(st.st_mode);
}

void posixTerm::Delete(const char *fn) {
    if (unlink(fn))
        Error("Can't delete file \"%s\".", fn);
}

void posixTerm::OpenRead(const char*fn) {
    fp = fopen(fn, "rb");
    if (!fp)
        throw ENOFILE;
    CurrentFileName = fn;
}

void posixTerm::OpenWrite(const char*fn) {
    fp = fopen(fn, "wb+");
    if (!fp)
        throw ENODIR;
    CurrentFileName = fn;
}

void posixTerm::OpenUpdate(const char*fn) {
    fp = fopen(fn, "rb+");
    if (!fp)
        fp = fopen(fn, "wb+");
    if (!fp)
        throw ENODIR;
    CurrentFileName = fn;
}

void posixTerm::Close() {
    if (fp) {
        fclose(fp);
        fp = NULL;
    }
}

void posixTerm::FRead(void *vp, size_t sz) {
    if (fread(vp, 1, sz, fp) != sz)
        throw EREADERR;
}

void posixTerm::FWrite(const void *vp, size_t sz) {
    if (!fp)
        return;
    if (fwrite(vp, 1, sz, fp) != sz)
        throw EWRIERR;
}

int32 posixTerm::Tell() {
    return ftell(fp);
}

void posixTerm::Seek(int32 pos, int8 rel) {
    if (fseek(fp, pos, rel))
        throw ECORRUPT;
}

void posixTerm::Cut(int32 amt) {
    int32 start, end;
    void *block;

    start = ftell(fp);
    fseek(fp, 0, SEEK_END);
    end = ftell(fp);
    fseek(fp, start + amt, SEEK_SET);
    block = malloc(end - (start + amt));
    fread(block, end - (start + amt), 1, fp);
    fseek(fp, start, SEEK_SET);
    fwrite(block, end - (start + amt), 1, fp);
    free(block);
}

char * posixTerm::MenuListFiles(const char * filespec, uint16 flags, const char * title) {
    static char persistent_retval[MAX_PATH_LENGTH];
    char *file_names[MAX_MENU_OPTIONS];
    int option_count = -1;
    struct dirent *ent;
    DIR *d;

    d = opendir(CurrentDirectory);
    if (!d) {
        Error("Problem listing files for user perusal.");
        return (char*)"";
    }
    while ((ent = readdir(d)) != NULL && option_count < MAX_MENU_OPTIONS - 1) {
        /* FNM_PERIOD keeps macOS AppleDouble sidecars (._*) and "."/".." out of
           this user-facing file list, for the same reason as NextFile() above. */
        if (fnmatch(filespec, ent->d_name, FNM_PERIOD))
            continue;
        option_count++;
        file_names[option_count] = (char *)alloca(strlen(ent->d_name) + 1);
        memcpy(file_names[option_count], ent->d_name, strlen(ent->d_name) + 1);
        LOption(file_names[option_count], option_count);
    }
    closedir(d);

    option_count = (int)LMenu(flags, title);
    if (option_count == -1)
        return NULL;
    persistent_retval[0] = '\0';
    memcpy(persistent_retval, file_names[option_count],
        strlen(file_names[option_count]) + 1);
    return persistent_retval;
}

/* FirstFile/NextFile walk a directory and leave each match open for reading,
   which is how the module loader reads every .mod in a folder. */
bool posixTerm::FirstFile(char * filespec) {
    if (findDir) {
        closedir(findDir);
        findDir = NULL;
    }
    findDir = opendir(CurrentDirectory);
    if (!findDir)
        return false;
    findSpec = filespec;
    return NextFile();
}

bool posixTerm::NextFile() {
    struct dirent *ent;

    if (!findDir)
        return false;

    while ((ent = readdir(findDir)) != NULL) {
        /* FNM_PERIOD: a wildcard must not match a leading '.'. Packaging the
           tree with tar on macOS (without COPYFILE_DISABLE=1) drops AppleDouble
           sidecar files next to the real ones -- ._Incursion.Mod beside
           Incursion.Mod, ._8x8.png beside the fonts. Each is 163 bytes and
           matches "*.Mod", so LoadModules() opened ._Incursion.Mod first,
           LoadGroup() rejected its header as "File Version Mismatch", and all
           module loading aborted. This is port code and a port/packaging
           artefact, not an upstream bug: no ._* file exists in an upstream
           Win32 distribution, and upstream enumerates with FindFirstFileA, not
           fnmatch. FNM_PERIOD also skips "." and "..", which no resource uses. */
        if (fnmatch(findSpec, ent->d_name, FNM_PERIOD))
            continue;
        try {
            OpenRead(ent->d_name);
        } catch (int) {
            fp = NULL;
            continue;
        }
        ASSERT(fp);
        return true;
    }

    closedir(findDir);
    findDir = NULL;
    return false;
}

#endif
