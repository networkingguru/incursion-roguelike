/* CharFile.cpp -- the .char parser and the File creation source (bead
   inc-10v7f, phase 7a; spec sections 1, 3, 5 and amendments A1, A5, A7, A8,
   A12, B1, B2, B4, B11, B18).

   A .char file states a character as `<key> [<context>]: <value>` lines. The
   File source answers every creation decision from it, by (key, context)
   queue: lines of one queue are consumed in file order, and the order of
   lines between different queues does not matter. It never lets a site run
   its `live` code. Anything it cannot answer is a build failure: one stderr
   line beginning `BUILD FAILED:` and a non-zero exit.

   Nothing here branches on one key (spec B18). The key name is looked up in
   the X-macro table (inc/CreationSource.h); the context text is the exact
   text the recorder writes (CreationContextText); the value is parsed by the
   key's KIND only: a ROLL is an integer, a PICK is a label, an ITEM is the
   text form CreationItemText writes. The two lines that are data, not
   decisions, are `options:` and `seed:`. */
#include "Incursion.h"
#include <map>
#include <stdarg.h>
#include <unistd.h>

// no-family
#define EXIT_BUILD_FAILED 10
// end no-family

void CreationBuildFail(const char *fmt, ...)
{
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    for (char *c = buf; *c; c++)
        if (*c == '\n' || *c == '\r')
            *c = ' ';
    fflush(stdout);
    fprintf(stderr, "BUILD FAILED: %s\n", buf);
    fflush(stderr);
    _exit(EXIT_BUILD_FAILED);
}

/* ---- the parsed file ------------------------------------------------------ */

struct StatedLine {
    CreationKey  key;
    std::string  ctx, text;
    int          line;
    bool         used;
    int32        num;          /* ROLL */
    CreationItem item;         /* ITEM */
};

struct CharFileData {
    std::string path;
    std::vector<StatedLine> lines;                       /* in file order */
    std::map<std::string, std::vector<size_t> > queue;   /* id -> indices into lines */
    std::map<std::string, size_t> next;                  /* id -> next unconsumed position */
    std::map<std::string, std::string> lastGiven;        /* id -> last value handed out */
    bool hasOptions, hasSeed;
    std::string options, seed;
    CharFileData() : hasOptions(false), hasSeed(false) {}
};
static CharFileData cf;

static std::string QueueId(CreationKey k, const std::string &ctx)
{
    return std::string(CreationKeyName(k)) + "\n" + ctx;
}

static std::string KeyText(CreationKey k, const std::string &ctx)
{
    if (ctx.empty())
        return CreationKeyName(k);
    return std::string(CreationKeyName(k)) + " [" + ctx + "]";
}

static std::string LineText(CreationKey k, const std::string &ctx, const std::string &value)
{
    if (ctx.empty())
        return std::string(CreationKeyName(k)) + ": " + value;
    return std::string(CreationKeyName(k)) + " [" + ctx + "]: " + value;
}

static std::string Trim(const std::string &s)
{
    size_t a = s.find_first_not_of(" \t\r\n"), b = s.find_last_not_of(" \t\r\n");
    return a == std::string::npos ? std::string() : s.substr(a, b - a + 1);
}

static bool KeyByName(const std::string &name, CreationKey &out)
{
    for (int k = 0; k != CK_COUNT; k++)
        if (name == CreationKeyName((CreationKey)k)) {
            out = (CreationKey)k;
            return true;
        }
    return false;
}

static bool ReadWholeFile(const char *path, std::vector<std::string> &lines)
{
    FILE *f = fopen(path, "r");
    if (!f)
        return false;
    std::string cur;
    int c;
    while ((c = fgetc(f)) != EOF) {
        if (c == '\n') { lines.push_back(cur); cur.clear(); }
        else cur += (char)c;
    }
    if (!cur.empty())
        lines.push_back(cur);
    fclose(f);
    return true;
}

/* One line split into key, context and value. False when it is malformed. */
static bool SplitLine(const std::string &line, std::string &key, std::string &ctx,
    bool &hasCtx, std::string &value)
{
    size_t i = 0;
    while (i < line.size() && (islower((unsigned char)line[i]) || isdigit((unsigned char)line[i])
        || line[i] == '_'))
        i++;
    if (i == 0)
        return false;
    key = line.substr(0, i);
    hasCtx = false;
    if (i + 1 < line.size() && line[i] == ' ' && line[i + 1] == '[') {
        size_t close = line.find("]:", i + 2);
        if (close == std::string::npos)
            return false;
        ctx = Trim(line.substr(i + 2, close - (i + 2)));
        hasCtx = true;
        i = close + 1;
    }
    if (i >= line.size() || line[i] != ':')
        return false;
    value = Trim(line.substr(i + 1));
    return true;
}

/* Parse `path`. `full` false reads only options: and seed: (before the
   modules are loaded); true parses every line. Fails the build on any fault. */
static void ParseCharFile(const char *path, bool full)
{
    std::vector<std::string> raw;
    cf = CharFileData();
    cf.path = path;
    if (!ReadWholeFile(path, raw))
        CreationBuildFail("cannot read %s", path);
    for (size_t n = 0; n != raw.size(); n++) {
        int lineNo = (int)n + 1;
        std::string line = Trim(raw[n]);
        if (line.empty() || line[0] == '#')
            continue;
        std::string key, ctx, value;
        bool hasCtx;
        if (!SplitLine(line, key, ctx, hasCtx, value))
            CreationBuildFail("%s:%d: malformed line (want `key [context]: value`): %s",
                path, lineNo, line.c_str());
        if (key == "options" || key == "seed") {
            if (hasCtx)
                CreationBuildFail("%s:%d: %s: takes no context", path, lineNo, key.c_str());
            if (value.empty())
                CreationBuildFail("%s:%d: %s: has no value", path, lineNo, key.c_str());
            bool &have = (key == "options") ? cf.hasOptions : cf.hasSeed;
            if (have)
                CreationBuildFail("%s:%d: duplicate %s: line", path, lineNo, key.c_str());
            have = true;
            ((key == "options") ? cf.options : cf.seed) = value;
            if (key == "seed")
                for (size_t i = 0; i != value.size(); i++)
                    if (!isdigit((unsigned char)value[i]))
                        CreationBuildFail("%s:%d: seed: wants a whole number, not \"%s\"",
                            path, lineNo, value.c_str());
            continue;
        }
        if (!full)
            continue;
        CreationKey k;
        if (!KeyByName(key, k))
            CreationBuildFail("%s:%d: unknown key \"%s\"", path, lineNo, key.c_str());
        if (!CreationKeyIsInput(k))
            CreationBuildFail("%s:%d: \"%s\" is observed, not stated: remove the line", path,
                lineNo, key.c_str());
        StatedLine sl;
        sl.key = k; sl.ctx = ctx; sl.text = value; sl.line = lineNo;
        sl.used = false; sl.num = 0;
        if (CreationKeyKind(k) == CKIND_ROLL) {
            char *end;
            long v = strtol(value.c_str(), &end, 10);
            if (value.empty() || *end)
                CreationBuildFail("%s:%d: %s wants a whole number, not \"%s\"", path,
                    lineNo, CreationKeyName(k), value.c_str());
            sl.num = (int32)v;
        } else if (CreationKeyKind(k) == CKIND_ITEM) {
            std::string err;
            if (!CreationItemRead(value, sl.item, err))
                CreationBuildFail("%s:%d: %s: %s", path, lineNo, CreationKeyName(k), err.c_str());
        } else if (value.empty()) {
            CreationBuildFail("%s:%d: %s has no value", path, lineNo, CreationKeyName(k));
        }
        cf.queue[QueueId(k, ctx)].push_back(cf.lines.size());
        cf.lines.push_back(sl);
    }
}

/* ---- the File source -------------------------------------------------------- */

class CreationFile : public CreationSource {
public:
    const char *Backend() const { return "File"; }
    /* MO_CREATE, not MO_RECREATE: an unsourced prompt must read a real key
       (and stop the build), never consume the reincarnation record. */
    int  TermMode() const { return MO_CREATE; }
    bool CanBackUp() const { return false; }
    bool Reseeds() const { return false; }
    bool NeverLive() const { return true; }
    void BeginState(Player*) { memset(&RInf, 0, sizeof(ReincarnationInfo)); }
    void PopResponse(Player*) {}
    /* A build writes no gallery entry: the character keeps GallerySlot -1. */
    void Finish(Player*, int16 *slot) { *slot = -1; }

    bool AnswerRoll(CreationKey k, const CreationContext &c, int32 &v,
        const CreationRange &range)
    {
        StatedLine *sl = Take(k, c, CreationKeyDefault(k));
        if (!sl)
            return false;
        if (range.Set() && (sl->num < range.lo || sl->num > range.hi))
            CreationBuildFail("%s:%d: %s is outside %d to %d", cf.path.c_str(), sl->line,
                LineText(k, sl->ctx, sl->text).c_str(), (int)range.lo, (int)range.hi);
        v = sl->num;
        return true;
    }

    bool AnswerPick(CreationKey k, const CreationContext &c, const CreationPickList &list,
        int32 &value, std::string &text, bool &inList)
    {
        std::string def = CreationKeyDefault(k);
        if (def.empty() && !list.names.empty())
            def = CreationNormalize(list.names[0]);
        StatedLine *sl = Take(k, c, def.c_str(), true);
        if (!sl)
            return false;
        std::string want = CreationNormalize(sl->text);
        int hits = 0;
        size_t at = 0;
        for (size_t i = 0; i != list.names.size(); i++)
            if (CreationNormalize(list.names[i]) == want) {
                hits++;
                at = i;
            }
        if (hits == 0 && CreationInPickMany()) {
            /* Not one of this table's rows: it belongs to a later table. */
            Unlike(sl);
            return false;
        }
        if (hits == 0) {
            std::string all;
            for (size_t i = 0; i != list.names.size(); i++)
                all += (i ? ", " : "") + CreationNormalize(list.names[i]);
            CreationBuildFail("%s:%d: %s: \"%s\" matches no candidate; candidates: %s",
                cf.path.c_str(), sl->line, KeyText(k, sl->ctx).c_str(),
                want.c_str(), all.c_str());
        }
        if (hits > 1)
            CreationBuildFail("%s:%d: %s: \"%s\" is ambiguous, %d candidates carry that name",
                cf.path.c_str(), sl->line, KeyText(k, sl->ctx).c_str(),
                want.c_str(), hits);
        value = list.values[at];
        text = list.names[at];
        inList = true;
        return true;
    }

    bool AnswerItem(CreationKey k, const CreationContext &c, CreationItem &it)
    {
        StatedLine *sl = Take(k, c, CreationKeyDefault(k));
        if (!sl)
            return false;
        it = sl->item;
        return true;
    }

    /* The retained perk set: one block per perk, found by walking the Perk
       field table the recorder walks (spec 3, B18). */
    bool AnswerPerks(PerkSet &out)
    {
        memset(&out, 0, sizeof(out));
        bool any = false;
        for (int j = 0; j != NUM_PERKS_PER_SET; j++) {
            std::string sub = (const char*)Format("%d", j);
            std::string tctx = CreationContextText(CreationMakeContext(CK_PERK_TYPE, sub.c_str()));
            if (!HasLine(CK_PERK_TYPE, tctx))
                continue;
            StatedLine *tl = Take(CK_PERK_TYPE, CreationMakeContext(CK_PERK_TYPE, sub.c_str()),
                CreationKeyDefault(CK_PERK_TYPE));
            int type = CreationPerkTypeFromName(tl->text);
            if (type <= 0)
                CreationBuildFail("%s:%d: %s: unknown perk type \"%s\"", cf.path.c_str(),
                    tl->line, LineText(CK_PERK_TYPE, tl->ctx, tl->text).c_str(), tl->text.c_str());
            out.elt[j].type = (PerkType)type;
            for (int f = 0; f != CreationPerkFieldCount; f++) {
                const CreationPerkField &pf = CreationPerkFields[f];
                if (pf.perkType != type)
                    continue;
                CreationContext fc = CreationMakeContext(pf.key, sub.c_str());
                StatedLine *fl = Take(pf.key, fc, CreationKeyDefault(pf.key));
                std::string err;
                if (!pf.read(fl->text, out.elt[j], err))
                    CreationBuildFail("%s:%d: %s: %s", cf.path.c_str(), fl->line,
                        LineText(pf.key, fl->ctx, fl->text).c_str(), err.c_str());
            }
            any = true;
        }
        return any;
    }

    void NoteRoll(CreationKey, const CreationContext&, int32, const CreationRange&) {}
    void NotePick(CreationKey, const CreationContext&, const std::string&) {}
    void NotePerks(const PerkSet&) {}
    void NoteItem(CreationKey, const CreationContext&, const CreationItem&) {}
    void NoteOptions(const int8*, int) {}

    /* Every stated value MUST have been used (spec 3). */
    void Close(bool completed)
    {
        if (!completed)
            return;
        for (size_t i = 0; i != cf.lines.size(); i++)
            if (!cf.lines[i].used)
                CreationBuildFail("%s:%d: surplus: this stated value was never used: %s",
                    cf.path.c_str(), cf.lines[i].line,
                    LineText(cf.lines[i].key, cf.lines[i].ctx, cf.lines[i].text).c_str());
    }

private:
    bool HasLine(CreationKey k, const std::string &ctx)
    {
        std::string id = QueueId(k, ctx);
        std::map<std::string, std::vector<size_t> >::iterator q = cf.queue.find(id);
        return q != cf.queue.end() && cf.next[id] < q->second.size();
    }

    /* Hand out the next value of (key, context). With none left: in a
       multi-answer pick that is the end of the answers; elsewhere the game
       either asked again after taking the last value (rejected, B4) or the
       file is missing the line (A5). */
    StatedLine *Take(CreationKey k, const CreationContext &c, const char *def,
        bool allowEnd = false)
    {
        std::string ctx = CreationContextText(c);
        std::string id = QueueId(k, ctx);
        std::map<std::string, std::vector<size_t> >::iterator q = cf.queue.find(id);
        size_t &pos = cf.next[id];
        if (q == cf.queue.end() || pos >= q->second.size()) {
            if (allowEnd && CreationInPickMany())
                return NULL;
            std::map<std::string, std::string>::iterator last = cf.lastGiven.find(id);
            if (last != cf.lastGiven.end())
                CreationBuildFail("stated value rejected by the game: %s was asked again with "
                    "no value left; the last value given was \"%s\" (to state more, add the "
                    "line: %s)", KeyText(k, ctx).c_str(), last->second.c_str(),
                    LineText(k, ctx, def).c_str());
            CreationBuildFail("missing line in %s; add: %s", cf.path.c_str(),
                LineText(k, ctx, def).c_str());
        }
        StatedLine *sl = &cf.lines[q->second[pos]];
        pos++;
        sl->used = true;
        cf.lastGiven[id] = sl->text;
        return sl;
    }

    /* Give a value back: a pick-many looked at it and it is not for this table. */
    void Unlike(StatedLine *sl)
    {
        std::string id = QueueId(sl->key, sl->ctx);
        cf.next[id]--;
        sl->used = false;
    }
};

static CreationFile fileSource;
CreationSource &CreationFileSource() { return fileSource; }

/* ---- build mode ---------------------------------------------------------------- */

/* Before the game exists: read options: and seed:, put the settings file in
   the run directory as Options.Dat with OPT_AUTOMORE forced on (A8), and give
   the process its seed (B11). */
bool CharFilePrepare(const char *charPath, const char *runDir)
{
    ParseCharFile(charPath, false);
    if (!cf.hasOptions)
        CreationBuildFail("%s: no options: line (name the settings file)", charPath);
    if (!cf.hasSeed)
        CreationBuildFail("%s: no seed: line", charPath);

    std::string opts = cf.options;
    if (access(opts.c_str(), R_OK) != 0 && opts[0] != '/') {
        std::string here = charPath;
        size_t slash = here.find_last_of('/');
        std::string beside = (slash == std::string::npos ? std::string() : here.substr(0, slash + 1)) + opts;
        if (access(beside.c_str(), R_OK) == 0)
            opts = beside;
    }
    FILE *in = fopen(opts.c_str(), "rb");
    if (!in)
        CreationBuildFail("%s: options: %s is not a readable file", charPath, cf.options.c_str());
    std::string bytes;
    char buf[4096];
    size_t got;
    while ((got = fread(buf, 1, sizeof buf, in)) > 0)
        bytes.append(buf, got);
    fclose(in);
    if (bytes.size() <= (size_t)OPT_AUTOMORE)
        CreationBuildFail("%s: options: %s is too short to be a settings file", charPath,
            cf.options.c_str());
    bytes[OPT_AUTOMORE] = 1;

    std::string dir = runDir;
    if (!dir.empty() && dir[dir.size() - 1] != '/')
        dir += '/';
    FILE *out = fopen((dir + "Options.Dat").c_str(), "wb");
    if (!out)
        CreationBuildFail("cannot write %sOptions.Dat", dir.c_str());
    fwrite(bytes.data(), 1, bytes.size(), out);
    fclose(out);
    setenv("INCURSION_SEED", cf.seed.c_str(), 1);
    return true;
}

/* The build itself: the same Game::NewGame a player runs, with the File
   source installed, then Game::SaveGame and DumpCharacter. */
int RunCharBuild(const char *charPath)
{
    T1->Initialize();
    if (!theGame->LoadModules())
        CreationBuildFail("the game modules did not load");
    ParseCharFile(charPath, true);
    SetCreationSource(&CreationFileSource());
    theGame->NewGame(0, false);
    SetCreationSource(NULL);
    Player *pl = theGame->GetPlayer(0);
    if (!pl || !theGame->m[0])
        CreationBuildFail("%s: creation did not finish", charPath);
    {
        String base = "sheet";
        T1->DumpCharacter(base);
    }
    if (!theGame->SaveGame(*pl))
        CreationBuildFail("the character did not save");
    fprintf(stdout, "BUILT %s\n", (const char*)theGame->SaveFile);
    theGame->Cleanup();
    T1->ShutDown();
    return 0;
}

/* `-charpicktest <file.char>`: put every PICK line of a file to a fixed list of
   candidates -- two named "Fire Bolt", one "<5>Cold Bolt" (a colour code), one
   "Ice Bolt" -- and print what each resolves to. It proves the label rules
   (colour codes stripped, case kept, two matches ambiguous, no match listed)
   without a game: tools/check_char_build_failures.sh drives it. With asks > 0
   the first PICK line's (key, context) is asked that many times instead, which
   shows the repeated-request rule (spec B4): a request with a value left in
   its queue takes it; with the queue empty it fails as rejected. */
int RunCharPickTest(const char *charPath, int asks)
{
    ParseCharFile(charPath, true);
    CreationPickList list;
    list.Add("Fire Bolt", 10);
    list.Add("Fire Bolt", 11);
    list.Add("<5>Cold Bolt", 12);
    list.Add("Ice Bolt", 13);
    for (size_t i = 0, n = 0; i != cf.lines.size(); i++) {
        StatedLine &sl = cf.lines[i];
        if (CreationKeyKind(sl.key) != CKIND_PICK)
            continue;
        CreationContext c;
        c.event = 0; c.ordinal = 0; c.resource = sl.ctx;
        for (int again = (asks > 0 && n == 0) ? asks : 1; again > 0; again--) {
            int32 v = -1; std::string text; bool inList = false;
            if (fileSource.AnswerPick(sl.key, c, list, v, text, inList))
                fprintf(stdout, "asked %s: \"%s\" is candidate %d (value %d)\n",
                    CreationKeyName(sl.key), CreationNormalize(text).c_str(), (int)v - 10, (int)v);
        }
        n++;
        if (asks > 0)
            break;
    }
    return 0;
}
