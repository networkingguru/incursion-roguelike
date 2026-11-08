/* CreationSource.cpp -- the creation decision source, its Live and Replay
   backends and the recorder (bead inc-10v7f, phase 4; spec section 1, A6, B5,
   B18). The interface and the contract are in inc/CreationSource.h.

   The recorder has two serializers. The RInf one writes the fields the
   reincarnation gallery has always held, byte for byte as Create.cpp wrote
   them before; it is data driven, by the binding table below, so no key has
   its own branch. The .char one writes `<key> [<context>]: <value>` lines to
   the path in INCURSION_RECORD_CHAR, and writes nothing when that variable is
   unset (B5). */
#include "Incursion.h"
#include <stddef.h>
#include <map>

/* ---- the key table ------------------------------------------------------ */

static const char *keyUpper[CK_COUNT] = {
#define X(n,k) #n,
    CREATION_KEY_LIST(X)
#undef X
};
static const CreationKind keyKind[CK_COUNT] = {
#define X(n,k) CKIND_##k,
    CREATION_KEY_LIST(X)
#undef X
};

const char *CreationKeyName(CreationKey k)
{
    static std::string lower[CK_COUNT];
    if (k < 0 || k >= CK_COUNT)
        return "?";
    if (lower[k].empty()) {
        for (const char *s = keyUpper[k]; *s; s++)
            lower[k] += (char)tolower((unsigned char)*s);
    }
    return lower[k].c_str();
}

CreationKind CreationKeyKind(CreationKey k)
{
    return (k < 0 || k >= CK_COUNT) ? CKIND_ROLL : keyKind[k];
}

/* ---- the RInf bindings --------------------------------------------------
   A key with a binding is held by RInf: Replay answers it from there, and the
   recorder writes it there. `off` is the byte offset in ReincarnationInfo,
   `width` the field's width, `stride` the step between ordinals (a key that
   holds an array), `count` how many ordinals fit. `isText` marks a string;
   `constText` is a fixed answer Replay gives with no RInf field at all. */
struct CreationBinding {
    int off, width, stride, count;
    bool isText;
    const char *constText;
    bool equip;   /* one shared cursor over RInf.EquipRolls (GrantGear) */
};
static CreationBinding bindings[CK_COUNT];
static bool bindingsReady = false;

static void Bind(CreationKey k, int off, int width, int stride = 0, int count = 1)
{
    bindings[k].off = off; bindings[k].width = width;
    bindings[k].stride = stride; bindings[k].count = count;
}

static void InitBindings()
{
    if (bindingsReady)
        return;
    bindingsReady = true;
    for (int k = 0; k != CK_COUNT; k++) {
        bindings[k].off = -1; bindings[k].width = 0;
        bindings[k].stride = 0; bindings[k].count = 0;
        bindings[k].isText = false; bindings[k].constText = NULL;
        bindings[k].equip = false;
    }
    Bind(CK_FORMULA_SEED, (int)offsetof(ReincarnationInfo, formulaSeed), 4);
    Bind(CK_STORE_SEED,   (int)offsetof(ReincarnationInfo, storeSeed), 4);
    Bind(CK_STAT_METHOD,  (int)offsetof(ReincarnationInfo, statMethod), 4);
    Bind(CK_REROLLS,      (int)offsetof(ReincarnationInfo, rerollCount), 4);
    Bind(CK_REROLLED_PERKS, (int)offsetof(ReincarnationInfo, rerolledPerks), 1);
    Bind(CK_WIZARD_MODE,  (int)offsetof(ReincarnationInfo, WizMode), 1);
    Bind(CK_EXPLORE_MODE, (int)offsetof(ReincarnationInfo, ExpMode), 1);
    Bind(CK_SKILL_RANKS,  (int)offsetof(ReincarnationInfo, SkillRanks), 1, 1, SK_LASTSKILL);
    for (int i = 0; i != 7; i++)
        Bind((CreationKey)(CK_ATTR_STR + i),
             (int)offsetof(ReincarnationInfo, Attr) + i, 1);
    /* GrantGear's stream seed and its NN% rolls share RInf.EquipRolls, in the
       order the draws are made: one cursor, not one array per key. */
    bindings[CK_GEAR_STREAM].equip = true;
    bindings[CK_GEAR_CHANCE].equip = true;
    Bind(CK_CHARACTER_NAME, (int)offsetof(ReincarnationInfo, Name), 32);
    bindings[CK_CHARACTER_NAME].isText = true;
    /* A reincarnation never opens the option screen and never asks the
       Explore Mode question (spec A6, D2). */
    bindings[CK_ALTER_OPTIONS].constText = "no";
    bindings[CK_EXPLORE_CONTINUE].constText = "yes";
}

static bool ReadBinding(CreationKey k, int ordinal, int32 &v)
{
    const CreationBinding &b = bindings[k];
    if (b.equip) {
        v = RInf.EquipRolls[RInf.nEquipRolls++];
        ASSERT(RInf.nEquipRolls < 256);
        return true;
    }
    if (b.off < 0 || b.isText || ordinal < 0 || ordinal >= b.count)
        return false;
    const char *src = (const char*)&RInf + b.off + ordinal * b.stride;
    switch (b.width) {
    case 1: v = *(const int8*)src; return true;
    case 4: memcpy(&v, src, 4); return true;
    }
    return false;
}

static void WriteBinding(CreationKey k, int ordinal, int32 v)
{
    const CreationBinding &b = bindings[k];
    if (b.equip) {
        RInf.EquipRolls[RInf.cEquipRolls++] = (int8)v;
        ASSERT(RInf.cEquipRolls < 256);
        return;
    }
    if (b.off < 0 || b.isText || ordinal < 0 || ordinal >= b.count)
        return;
    char *dst = (char*)&RInf + b.off + ordinal * b.stride;
    switch (b.width) {
    case 1: *(int8*)dst = (int8)v; break;
    case 4: memcpy(dst, &v, 4); break;
    }
}

/* ---- window, context stack, ordinals ------------------------------------ */

static bool windowOpen = false;
static std::vector<std::pair<std::string,int> > scopeStack;
static std::map<std::string,int> ordinals;

CreationScope::CreationScope(const char *resource, int event, bool active) : pushed(active)
    {
        if (active)
            scopeStack.push_back(std::make_pair(std::string(resource ? resource : ""), event));
    }
CreationScope::~CreationScope()
    { if (pushed && !scopeStack.empty()) scopeStack.pop_back(); }

static std::string OrdinalKey(CreationKey k, const CreationContext &c)
{
    return std::string(keyUpper[k]) + "|" + c.resource + "|" + (const char*)Format("%d", c.event);
}

static CreationContext MakeContext(CreationKey k, const char *sub)
{
    CreationContext c;
    c.event = 0;
    if (!scopeStack.empty()) {
        c.resource = scopeStack.back().first;
        c.event = scopeStack.back().second;
    }
    c.sub = sub ? sub : "";
    std::map<std::string,int>::iterator it = ordinals.find(OrdinalKey(k, c));
    c.ordinal = (it == ordinals.end()) ? 0 : it->second;
    return c;
}

static void Advance(CreationKey k, const CreationContext &c)
    { ordinals[OrdinalKey(k, c)] = c.ordinal + 1; }

/* ---- the recorder's .char serializer ------------------------------------ */

struct RecordedDecision {
    CreationKey key; CreationContext ctx; std::string text;
};
static std::vector<RecordedDecision> recorded;

static std::string ContextText(const CreationContext &c)
{
    std::string s;
    if (!c.resource.empty()) s += c.resource;
    if (c.event) {
        if (!s.empty()) s += ";";
        s += Format("EV_%d", c.event);
    }
    if (!c.sub.empty()) {
        if (!s.empty()) s += ";";
        s += c.sub;
    }
    return s;
}

static void Emit(CreationKey k, const CreationContext &c, const std::string &text)
{
    RecordedDecision d; d.key = k; d.ctx = c; d.text = text;
    recorded.push_back(d);
}

/* ESC backed creation up (Player::AbandonCreation answered no, then the site
   calls PopResponse): the step the player left recorded the abandon line, and
   nothing after it. Drop that line and give its ordinal back, so the .char of
   a walk that ESCs and picks again holds only the final picks (phase 6c). */
static void DropAbandonedStep()
{
    size_t from = recorded.size();
    while (from != 0 && recorded[from - 1].key != CK_ABANDON)
        from--;
    if (from == 0)
        return;
    from--;
    while (recorded.size() > from) {
        const RecordedDecision &d = recorded.back();
        ordinals[OrdinalKey(d.key, d.ctx)] = d.ctx.ordinal;
        recorded.pop_back();
    }
}

/* The engine's own table choice (Debug.cpp quality entry, Dump.cpp): armor and
   shields use AQ, weapons, missiles and bows use WQ, then IQ for the rest. */
static const char *FindName(TextVal *list, int q)
{
    for (; list->Text; list++)
        if (list->Val == q)
            return list->Text;
    return NULL;
}

static std::string QualityName(rID iID, int q)
{
    const char *n = NULL;
    int t = iID ? TITEM(iID)->IType : 0;
    if (t == T_ARMOUR || t == T_SHIELD)
        n = FindName(AQ_CONSTNAMES, q);
    else if (t == T_WEAPON || t == T_MISSILE || t == T_BOW)
        n = FindName(WQ_CONSTNAMES, q);
    if (!n)
        n = FindName(IQ_CONSTNAMES, q);
    return n ? std::string(n) : std::string((const char*)Format("%d", q));
}

static std::string ItemText(const CreationItem &it)
{
    std::string s = it.iID ? NAME(it.iID) : "none";
    if (it.eID) s += std::string(", effect ") + NAME(it.eID);
    if (it.plus) s += Format(", plus %d", (int)it.plus);
    if (it.bane) s += Format(", bane %d", (int)it.bane);
    for (int i = 0; i != 8; i++)
        if (it.q[i]) s += ", quality " + QualityName(it.iID, it.q[i]);
    if (it.quantity) s += Format(", quantity %d", (int)it.quantity);
    if (it.charges) s += Format(", charges %d", (int)it.charges);
    for (size_t i = 0; i != it.stati.size(); i++) {
        const CreationStati &st = it.stati[i];
        const char *nm = Lookup(STATI_CONSTNAMES, st.nature);
        s += Format(", stati %s val %d mag %d duration %d",
            nm ? nm : "?", (int)st.val, (int)st.mag, (int)st.duration);
        if (st.eID) s += std::string(" effect ") + NAME(st.eID);
    }
    return s;
}

/* The retained perk set, one named line per field (spec section 3). */
static void EmitPerks(const PerkSet &set)
{
    for (int j = 0; j != NUM_PERKS_PER_SET; j++) {
        const Perk &p = set.elt[j];
        if (p.type == PERK_NONE)
            continue;
        CreationContext c = MakeContext(CK_PERK_TYPE, Format("%d", j));
        static const char *typeName[] = { "PERK_NONE", "PERK_ITEM", "PERK_FEAT",
            "PERK_ABILITY", "PERK_SPELL", "PERK_RESIST", "PERK_IMMUNE", "PERK_TALENT" };
        Emit(CK_PERK_TYPE, c, typeName[p.type]);
        Advance(CK_PERK_TYPE, c);
        switch (p.type) {
        case PERK_ITEM: {
            CreationItem it;
            it.iID = p.p.i.iID; it.eID = p.p.i.eID;
            it.plus = p.p.i.Plus; it.bane = p.p.i.Bane;
            for (int q = 0; q != 8; q++) it.q[q] = p.p.i.q[q];
            CreationContext ic = MakeContext(CK_PERK_ITEM, Format("%d", j));
            Emit(CK_PERK_ITEM, ic, ItemText(it));
            Advance(CK_PERK_ITEM, ic);
            } break;
        case PERK_FEAT: {
            CreationContext fc = MakeContext(CK_PERK_FEAT, Format("%d", j));
            Emit(CK_PERK_FEAT, fc, FeatName(p.p.feat));
            Advance(CK_PERK_FEAT, fc);
            } break;
        case PERK_ABILITY: {
            CreationContext ac = MakeContext(CK_PERK_ABILITY, Format("%d", j));
            Emit(CK_PERK_ABILITY, ac, (const char*)Format("%s %d",
                Lookup(ClassAbilities, p.p.ability.ca_ability),
                (int)p.p.ability.ability_value));
            Advance(CK_PERK_ABILITY, ac);
            } break;
        case PERK_SPELL:
        case PERK_TALENT: {
            CreationContext sc = MakeContext(CK_PERK_SPELL, Format("%d", j));
            Emit(CK_PERK_SPELL, sc, NAME(p.p.spell));
            Advance(CK_PERK_SPELL, sc);
            } break;
        case PERK_RESIST: {
            CreationContext rc = MakeContext(CK_PERK_RESIST, Format("%d", j));
            if (p.p.resist < 0)
                Emit(CK_PERK_RESIST, rc, std::string("save ") +
                    Lookup(SaveBonusNames, -p.p.resist));
            else
                Emit(CK_PERK_RESIST, rc, Lookup(DTypeNames, p.p.resist));
            Advance(CK_PERK_RESIST, rc);
            } break;
        case PERK_IMMUNE: {
            CreationContext mc = MakeContext(CK_PERK_IMMUNE, Format("%d", j));
            Emit(CK_PERK_IMMUNE, mc, Lookup(DTypeNames, p.p.immune));
            Advance(CK_PERK_IMMUNE, mc);
            } break;
        default: break;
        }
    }
}

/* The changed options file sits beside the .char: same directory, same base
   name, `.options.dat` (spec B11). */
static std::string OptionsBase(const char *path)
{
    std::string s = path;
    size_t dot = s.rfind('.'), slash = s.find_last_of("/\\");
    if (dot != std::string::npos && (slash == std::string::npos || dot > slash))
        s.erase(dot);
    return s;
}

static std::string OptionsFileName(const char *path)
{
    std::string s = OptionsBase(path) + ".options.dat";
    size_t slash = s.find_last_of("/\\");
    return slash == std::string::npos ? s : s.substr(slash + 1);
}

static std::string optionsBytes;
static bool haveOptions = false;

static void WriteCharFile()
{
    const char *path = getenv("INCURSION_RECORD_CHAR");
    if (!path || !*path)
        return;
    if (haveOptions) {
        std::string op = OptionsBase(path) + ".options.dat";
        FILE *of = fopen(op.c_str(), "wb");
        if (!of)
            Error("INCURSION_RECORD_CHAR: cannot write %s", op.c_str());
        else {
            fwrite(optionsBytes.data(), 1, optionsBytes.size(), of);
            fclose(of);
        }
    }
    FILE *f = fopen(path, "w");
    if (!f) {
        Error("INCURSION_RECORD_CHAR: cannot write %s", path);
        return;
    }
    fprintf(f, "# recorded by INCURSION_RECORD_CHAR: the creation decisions, in the order made\n");
    for (size_t i = 0; i != recorded.size(); i++) {
        std::string ctx = ContextText(recorded[i].ctx);
        if (ctx.empty())
            fprintf(f, "%s: %s\n", CreationKeyName(recorded[i].key), recorded[i].text.c_str());
        else
            fprintf(f, "%s [%s]: %s\n", CreationKeyName(recorded[i].key),
                ctx.c_str(), recorded[i].text.c_str());
    }
    fclose(f);
}

/* ---- private Player state the gallery entry needs ------------------------ */

struct CreationAccess {
    static void FinishLive(Player *p, int16 *slot)
    {
        ReincarnationInfo *ri;
        size_t sz; int16 i;
        RInf.RaceID = p->RaceID;
        RInf.ClassID = p->ClassID[0];
        memcpy(RInf.CharGenOpts, &(p->Options[OPC_CHARGEN]), sizeof(int8)*100);
        for (i = 0; i != 7; i++)
            RInf.Attr[i] = (int8)p->BAttr[i];
        time(&RInf.Touched);
        time(&RInf.Created);
        p->MyTerm->ChangeDirectory(
            p->MyTerm->SaveSubDir());
        if (p->MyTerm->Exists("gallery.dat")) {
            p->MyTerm->OpenRead("gallery.dat");
            p->MyTerm->Seek(0,SEEK_END);
            sz = p->MyTerm->Tell() / sizeof(ReincarnationInfo);
            ASSERT(sz);
            ri = new ReincarnationInfo[sz + 1];
            p->MyTerm->Seek(0,SEEK_SET);
            p->MyTerm->FRead(ri,sz * sizeof(ReincarnationInfo));
            p->MyTerm->Close();

            if (sz >= MAX_GALLERY_SIZE) {
                int16 o_index = 0; time_t oldest;
                /* Find the oldest, or any disabled */
                time(&oldest);
                for (i=0;i!=sz;i++) {
                    if (difftime(oldest,ri[i].Touched) >= 1)
                    { oldest = ri[i].Touched; o_index = i; }
                    if (ri[i].Disabled)
                        o_index = i;
                }

                /* Overwrite the Oldest */
                memcpy(&ri[o_index],&RInf,sizeof(ReincarnationInfo));
                *slot = o_index;
            } else {
                memcpy(&ri[sz],&RInf,sizeof(ReincarnationInfo));
                *slot = (int16)sz;
                sz++;
            }
        } else {
            ri = new ReincarnationInfo[1];
            memcpy(&ri[0],&RInf,sizeof(ReincarnationInfo));
            sz = 1;
            *slot = 0;
        }
        p->MyTerm->OpenWrite("gallery.dat");
        p->MyTerm->FWrite(ri,sz * sizeof(ReincarnationInfo));
        p->MyTerm->Close();
        delete[] ri;
    }

    static void FinishReplay(Player *p)
    {
        p->MyTerm->ShowStatus();
        p->MyTerm->ShowTraits();
    }

    static void BeginReplay(Player *p)
    {
        memcpy(&(p->Options[OPC_CHARGEN]), RInf.CharGenOpts, sizeof(int8)*100);
    }
};

/* ---- the backends --------------------------------------------------------- */

class CreationBase : public CreationSource {
public:
    bool AnswerPerks(PerkSet &out)
    {
        if (!RInf.usedPerks)
            return false;
        memcpy(&out, &(RInf.Perks), sizeof(out));
        return true;
    }
    bool AnswerItem(CreationKey, const CreationContext&, CreationItem&)
        { return false; }
};

class CreationLive : public CreationBase {
public:
    const char *Backend() const { return "Live"; }
    int  TermMode() const { return MO_CREATE; }
    bool CanBackUp() const { return true; }
    void BeginState(Player*) { memset(&RInf, 0, sizeof(ReincarnationInfo)); }
    void PopResponse(Player *p)
    {
        if (p->MyTerm->GetMode() == MO_CREATE && RInf.nRsp > 0)
            RInf.nRsp--;
        DropAbandonedStep();
    }
    void Finish(Player *p, int16 *slot) { CreationAccess::FinishLive(p, slot); }

    bool AnswerRoll(CreationKey, const CreationContext&, int32&) { return false; }
    bool AnswerPick(CreationKey, const CreationContext&, const CreationPickList&,
        int32&, std::string&, bool&) { return false; }

    void NoteRoll(CreationKey k, const CreationContext &c, int32 v)
    {
        WriteBinding(k, c.ordinal, v);
        Emit(k, c, (const char*)Format("%d", (int)v));
    }
    void NotePick(CreationKey k, const CreationContext &c, const std::string &text)
    {
        const CreationBinding &b = bindings[k];
        if (b.off >= 0 && b.isText)
            strncpy((char*)&RInf + b.off, text.c_str(), 31);
        Emit(k, c, text);
    }
    void NotePerks(const PerkSet &set)
    {
        memcpy(&(RInf.Perks), &set, sizeof(RInf.Perks));
        RInf.usedPerks = true;
        EmitPerks(set);
    }
    void NoteItem(CreationKey k, const CreationContext &c, const CreationItem &it)
        { Emit(k, c, ItemText(it)); }
    void NoteOptions(const int8 *opts, int n)
    {
        const char *path = getenv("INCURSION_RECORD_CHAR");
        if (!path || !*path)
            return;
        optionsBytes.assign((const char*)opts, (size_t)n);
        if (haveOptions)
            return;
        haveOptions = true;
        CreationContext c = MakeContext(CK_OPTIONS_FILE, NULL);
        Emit(CK_OPTIONS_FILE, c, OptionsFileName(path));
        Advance(CK_OPTIONS_FILE, c);
    }
    void Close(bool completed)
    {
        if (completed)
            WriteCharFile();
    }
};

class CreationReplay : public CreationBase {
public:
    const char *Backend() const { return "Replay"; }
    int  TermMode() const { return MO_RECREATE; }
    bool CanBackUp() const { return false; }
    void BeginState(Player *p) { CreationAccess::BeginReplay(p); }
    void PopResponse(Player*) {}
    void Finish(Player *p, int16*) { CreationAccess::FinishReplay(p); }

    bool AnswerRoll(CreationKey k, const CreationContext &c, int32 &v)
        { return ReadBinding(k, c.ordinal, v); }
    bool AnswerPick(CreationKey k, const CreationContext&, const CreationPickList &list,
        int32 &value, std::string &text, bool &inList)
    {
        const CreationBinding &b = bindings[k];
        if (b.constText)
            text = b.constText;
        else if (b.off >= 0 && b.isText) {
            char buf[40];
            strncpy(buf, (const char*)&RInf + b.off, 31); buf[31] = 0;
            text = buf;
        } else
            return false;
        inList = false;
        for (size_t i = 0; i != list.names.size(); i++)
            if (list.names[i] == text) {
                value = list.values[i];
                inList = true;
                break;
            }
        return true;
    }

    void NoteRoll(CreationKey, const CreationContext&, int32) {}
    void NotePick(CreationKey, const CreationContext&, const std::string&) {}
    void NotePerks(const PerkSet&) {}
    void NoteItem(CreationKey, const CreationContext&, const CreationItem&) {}
    void NoteOptions(const int8*, int) {}
    void Close(bool) {}
};

static CreationLive liveSource;
static CreationReplay replaySource;
static CreationSource *activeSource = &liveSource;

CreationSource *CreationSourceNow() { return activeSource; }
CreationSource *SetCreationSource(CreationSource *s)
{
    CreationSource *old = activeSource;
    activeSource = s ? s : &liveSource;
    return old;
}
CreationSource &CreationLiveSource() { return liveSource; }
CreationSource &CreationReplaySource() { return replaySource; }

CreationWindow::CreationWindow() : done(false)
{
    InitBindings();
    windowOpen = true;
    scopeStack.clear();
    ordinals.clear();
    recorded.clear();
    haveOptions = false;
    optionsBytes.clear();
}

CreationWindow::~CreationWindow()
{
    activeSource->Close(done);
    windowOpen = false;
}

bool CreationWindowOpen() { return windowOpen; }

static int liveDepth = 0;
CreationLiveDepth::CreationLiveDepth() { liveDepth++; }
CreationLiveDepth::~CreationLiveDepth() { liveDepth--; }
bool CreationInsideLive() { return liveDepth > 0; }

static int itemDepth = 0;
CreationItemDepth::CreationItemDepth() { itemDepth++; }
CreationItemDepth::~CreationItemDepth() { itemDepth--; }
bool CreationInsideItem() { return itemDepth > 0; }

void CreationDescribeItem(CreationItem &io, Item *it)
{
    if (!windowOpen || !it)
        return;
    io.iID = it->iID; io.eID = it->eID;
    io.plus = it->GetInherentPlus();
    io.bane = it->GetBane();
    for (int i = 0; i != 8; i++) io.q[i] = it->GetQuality(i);
    io.quantity = (int32)it->GetQuantity();
    io.charges = it->GetCharges();
    io.stati.clear();
    StatiIter(it)
        CreationStati st;
        st.nature = S->Nature; st.val = S->Val; st.mag = S->Mag;
        st.duration = S->Duration; st.eID = S->eID;
        io.stati.push_back(st);
    StatiIterEnd(it)
}

/* ---- the primitive halves -------------------------------------------------- */

bool CreationAnswerRoll(CreationKey k, const char *sub, int32 &v)
{
    if (!windowOpen || itemDepth > 0)
        return false;
    CreationContext c = MakeContext(k, sub);
    if (!activeSource->AnswerRoll(k, c, v))
        return false;
    Advance(k, c);
    return true;
}

void CreationNoteRoll(CreationKey k, const char *sub, int32 v)
{
    if (!windowOpen || itemDepth > 0)
        return;
    CreationContext c = MakeContext(k, sub);
    activeSource->NoteRoll(k, c, v);
    Advance(k, c);
}

bool CreationAnswerPick(CreationKey k, const char *sub, const CreationPickList &list,
    int32 &value, std::string &text, bool &inList)
{
    if (!windowOpen || itemDepth > 0)
        return false;
    CreationContext c = MakeContext(k, sub);
    if (!activeSource->AnswerPick(k, c, list, value, text, inList))
        return false;
    Advance(k, c);
    return true;
}

void CreationNotePick(CreationKey k, const char *sub, const std::string &text)
{
    if (!windowOpen || itemDepth > 0)
        return;
    CreationContext c = MakeContext(k, sub);
    activeSource->NotePick(k, c, text);
    Advance(k, c);
}

bool CreationAnswerItem(CreationKey k, const char *sub, CreationItem &it)
{
    if (!windowOpen || itemDepth > 0)
        return false;
    CreationContext c = MakeContext(k, sub);
    if (!activeSource->AnswerItem(k, c, it))
        return false;
    Advance(k, c);
    return true;
}

void CreationNoteItem(CreationKey k, const char *sub, const CreationItem &it)
{
    if (!windowOpen || itemDepth > 0)
        return;
    CreationContext c = MakeContext(k, sub);
    activeSource->NoteItem(k, c, it);
    Advance(k, c);
}

bool CreationAnswerPerks(PerkSet &out)
{
    if (!windowOpen)
        return false;
    return activeSource->AnswerPerks(out);
}

void CreationNotePerks(const PerkSet &set)
{
    if (!windowOpen)
        return;
    activeSource->NotePerks(set);
}

bool CreationAnswerPickMany(CreationKey k, const char *sub, const CreationPickList &list,
    std::vector<int32> &values)
{
    values.clear();
    for (size_t n = 0; n != list.names.size(); n++) {
        int32 v; std::string text; bool inList;
        if (!CreationAnswerPick(k, sub, list, v, text, inList))
            break;
        if (!inList) {
            values.clear();
            return false;
        }
        values.push_back(v);
    }
    return !values.empty();
}

void CreationNotePickMany(CreationKey k, const char *sub, const CreationPickList &list,
    const std::vector<int32> &values)
{
    for (size_t i = 0; i != values.size(); i++)
        for (size_t j = 0; j != list.values.size(); j++)
            if (list.values[j] == values[i]) {
                CreationNotePick(k, sub, list.names[j]);
                break;
            }
}

void CreationNoteOptions(const int8 *opts, int n)
{
    if (!windowOpen || itemDepth > 0)
        return;
    activeSource->NoteOptions(opts, n);
}
