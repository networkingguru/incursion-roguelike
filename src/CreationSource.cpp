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
#define X(n,k,d) #n,
    CREATION_KEY_LIST(X)
#undef X
};
static const CreationKind keyKind[CK_COUNT] = {
#define X(n,k,d) CKIND_##k,
    CREATION_KEY_LIST(X)
#undef X
};
static const char *keyDefault[CK_COUNT] = {
#define X(n,k,d) d,
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

const char *CreationKeyDefault(CreationKey k)
{
    return (k < 0 || k >= CK_COUNT || !keyDefault[k]) ? "" : keyDefault[k];
}

bool CreationKeyIsInput(CreationKey k)
{
    return k >= 0 && k < CK_COUNT && keyDefault[k] != NULL;
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

CreationContext CreationMakeContext(CreationKey k, const char *sub);
static CreationContext MakeContext(CreationKey k, const char *sub)
{
    return CreationMakeContext(k, sub);
}

CreationContext CreationMakeContext(CreationKey k, const char *sub)
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
    { return CreationContextText(c); }

std::string CreationContextText(const CreationContext &c)
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
    if (!CreationKeyIsInput(k))
        return;
    RecordedDecision d; d.key = k; d.ctx = c; d.text = text;
    recorded.push_back(d);
}

/* ESC backed creation up (Player::AbandonCreation answered no, then the site
   calls PopResponse): the step the player left recorded the abandon decision,
   and nothing after it. AbandonCreation marks where the step began; dropping
   it gives each ordinal back, so the .char of a walk that ESCs and picks again
   holds only the final picks (phase 6c). The mark is a position, not a key. */
static size_t stepMark = 0;
static bool haveStepMark = false;

void CreationMarkStep()
{
    stepMark = recorded.size();
    haveStepMark = true;
}

static void DropAbandonedStep()
{
    if (!haveStepMark)
        return;
    haveStepMark = false;
    while (recorded.size() > stepMark) {
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

/* The resource's name in full, ";tag" included. NAME() drops the tag, and two
   resources can share a name without it (the potion "Healing" and the spell
   "Healing"), so the file states the full name (spec S3). */
std::string CreationFullName(rID x)
{
    if (!x)
        return "none";
    Resource *r = RES(x);
    return std::string(theGame->Modules[r->ModNum]->GetText(r->Name));
}
static std::string FullName(rID x) { return CreationFullName(x); }

static std::string ItemText(const CreationItem &it)
{
    std::string s = it.iID ? FullName(it.iID) : "none";
    if (it.eID) s += std::string(", effect ") + FullName(it.eID);
    if (it.plus) s += Format(", plus %d", (int)it.plus);
    if (it.bane) s += Format(", bane %d", (int)it.bane);
    if (it.flags & IF_BLESSED) s += ", flag blessed";
    if (it.flags & IF_CURSED) s += ", flag cursed";
    if (it.flags & IF_MASTERWORK) s += ", flag masterwork";
    if (it.flags & IF_RUNIC) s += ", flag runic";
    for (int i = 0; i != 8; i++)
        if (it.q[i]) s += ", quality " + QualityName(it.iID, it.q[i]);
    if (it.quantity) s += Format(", quantity %d", (int)it.quantity);
    if (it.charges) s += Format(", charges %d", (int)it.charges);
    for (size_t i = 0; i != it.stati.size(); i++) {
        const CreationStati &st = it.stati[i];
        const char *nm = Lookup(STATI_CONSTNAMES, st.nature);
        s += Format(", stati %s val %d mag %d duration %d",
            nm ? nm : "?", (int)st.val, (int)st.mag, (int)st.duration);
        if (st.eID) s += std::string(" effect ") + FullName(st.eID);
    }
    return s;
}

std::string CreationItemText(const CreationItem &it) { return ItemText(it); }

/* ---- reading the names back ---------------------------------------------- */

enum { FIND_ITEM, FIND_EFFECT };

/* The one resource of `which` kind named `name` across every loaded module.
   Fails on none and on more than one. */
static bool FindResource(int which, const std::string &name, rID &out, std::string &err)
{
    int count = 0;
    for (int q = 0; q != MAX_MODULES; q++) {
        Module *m = theGame->Modules[q];
        if (!m)
            continue;
        int n = (which == FIND_ITEM) ? m->szItm : m->szEff;
        for (int i = 0; i != n; i++) {
            rID x = (which == FIND_ITEM) ? m->ItemID((uint16)i) : m->EffectID((uint16)i);
            if (name == FullName(x)) {
                out = x;
                count++;
            }
        }
    }
    if (count == 0)
        err = std::string("no ") + (which == FIND_ITEM ? "item" : "effect") +
            " named \"" + name + "\" in the module";
    else if (count > 1)
        err = std::string("\"") + name + "\" names " + (const char*)Format("%d", count) +
            (which == FIND_ITEM ? " items" : " effects") + ", so it is ambiguous";
    return count == 1;
}

static bool TextValFind(TextVal *list, const std::string &name, int32 &val, int &count)
{
    count = 0;
    for (; list->Text; list++)
        if (name == list->Text) {
            val = list->Val;
            count++;
        }
    return count == 1;
}

static bool QualityValue(rID iID, const std::string &name, int16 &q, std::string &err)
{
    int t = iID ? TITEM(iID)->IType : 0;
    TextVal *first = IQ_CONSTNAMES;
    if (t == T_ARMOUR || t == T_SHIELD)
        first = AQ_CONSTNAMES;
    else if (t == T_WEAPON || t == T_MISSILE || t == T_BOW)
        first = WQ_CONSTNAMES;
    int32 v; int count;
    if (TextValFind(first, name, v, count) ||
        (first != IQ_CONSTNAMES && TextValFind(IQ_CONSTNAMES, name, v, count)))
        { q = (int16)v; return true; }
    char *end;
    long n = strtol(name.c_str(), &end, 10);
    if (!name.empty() && *end == 0) { q = (int16)n; return true; }
    err = "no quality named \"" + name + "\" for this item";
    return false;
}

static bool ReadInt(const std::string &t, int32 &v)
{
    if (t.empty()) return false;
    char *end;
    long n = strtol(t.c_str(), &end, 10);
    if (*end) return false;
    v = (int32)n;
    return true;
}

/* Split the item text at each ", <word> " where <word> starts a field. The
   first piece is the item's name. */
static bool SplitItemText(const std::string &text, std::vector<std::string> &pieces)
{
    static const char *words[] = { "effect", "plus", "bane", "flag", "quality", "quantity",
        "charges", "stati", NULL };
    size_t start = 0, pos = 0;
    while ((pos = text.find(", ", pos)) != std::string::npos) {
        bool field = false;
        for (int w = 0; words[w]; w++) {
            std::string kw = std::string(words[w]) + " ";
            if (text.compare(pos + 2, kw.size(), kw) == 0)
                field = true;
        }
        if (field) {
            pieces.push_back(text.substr(start, pos - start));
            start = pos + 2;
        }
        pos += 2;
    }
    pieces.push_back(text.substr(start));
    return true;
}

bool CreationItemRead(const std::string &text, CreationItem &it, std::string &err)
{
    it = CreationItem();
    std::vector<std::string> pieces;
    SplitItemText(text, pieces);
    std::string name = pieces[0];
    if (name == "none")
        return pieces.size() == 1 ? true : (err = "\"none\" takes no fields", false);
    if (!FindResource(FIND_ITEM, name, it.iID, err))
        return false;
    int nq = 0;
    for (size_t i = 1; i != pieces.size(); i++) {
        const std::string &f = pieces[i];
        size_t sp = f.find(' ');
        std::string word = f.substr(0, sp), rest = f.substr(sp + 1);
        int32 n;
        if (word == "effect") {
            if (!FindResource(FIND_EFFECT, rest, it.eID, err)) return false;
        } else if (word == "plus" || word == "bane" || word == "quantity" || word == "charges") {
            if (!ReadInt(rest, n)) { err = word + " wants a whole number, not \"" + rest + "\""; return false; }
            if (word == "plus") it.plus = (int16)n;
            else if (word == "bane") it.bane = (int16)n;
            else if (word == "quantity") it.quantity = n;
            else it.charges = n;
        } else if (word == "flag") {
            if (rest == "blessed") it.flags |= IF_BLESSED;
            else if (rest == "cursed") it.flags |= IF_CURSED;
            else if (rest == "masterwork") it.flags |= IF_MASTERWORK;
            else if (rest == "runic") it.flags |= IF_RUNIC;
            else { err = "unknown item flag \"" + rest + "\" (blessed, cursed, masterwork, runic)"; return false; }
        } else if (word == "quality") {
            if (nq == 8) { err = "more than eight qualities"; return false; }
            if (!QualityValue(it.iID, rest, it.q[nq], err)) return false;
            nq++;
        } else if (word == "stati") {
            /* stati <NATURE> val V mag M duration D [effect NAME] */
            CreationStati st; st.nature = 0; st.val = st.mag = st.duration = 0; st.eID = 0;
            size_t vpos = rest.find(" val ");
            if (vpos == std::string::npos) { err = "stati wants: <name> val V mag M duration D"; return false; }
            std::string nat = rest.substr(0, vpos);
            int32 nv; int count;
            if (!TextValFind(STATI_CONSTNAMES, nat, nv, count)) {
                err = "no status named \"" + nat + "\""; return false; }
            st.nature = (int16)nv;
            std::string tail = rest.substr(vpos + 5);
            std::string eff;
            size_t epos = tail.find(" effect ");
            if (epos != std::string::npos) { eff = tail.substr(epos + 8); tail.erase(epos); }
            int a = 0, b = 0, c = 0;
            if (sscanf(tail.c_str(), "%d mag %d duration %d", &a, &b, &c) != 3) {
                err = "stati wants: <name> val V mag M duration D"; return false; }
            st.val = a; st.mag = b; st.duration = c;
            if (!eff.empty() && !FindResource(FIND_EFFECT, eff, st.eID, err)) return false;
            it.stati.push_back(st);
        } else {
            err = "unknown item field \"" + word + "\"";
            return false;
        }
    }
    return true;
}

/* An answered CreationItem becomes the item, through the engine's own item
   functions: Item::Create, MakeMagical, SetInherentPlus, SetBane, AddQuality,
   SetQuantity, SetCharges and GainPermStati / GainTempStati. */
Item *CreationMakeItem(const CreationItem &d)
{
    if (!d.iID)
        return NULL;
    Item *it;
    {
        unstatedDraw("overwritten by stated charges and quantity");
        it = Item::Create(d.iID);
    }
    if (!it)
        return NULL;
    if (d.eID)
        it->MakeMagical(d.eID, d.plus > 0 ? d.plus : 0);
    if (it->GetInherentPlus() != d.plus)
        it->SetInherentPlus((int8)d.plus);
    if (d.quantity)
        it->SetQuantity((uint32)d.quantity);
    it->SetCharges((int8)d.charges);
    /* The bane goes in first: adding a bane quality to a weapon with none
       draws a random one. */
    if (d.bane)
        it->SetBane(d.bane);
    for (int i = 0; i != 8; i++)
        if (d.q[i])
            it->AddQuality((int8)d.q[i]);
    it->IFlags = (uint16)((it->IFlags & ~CREATION_ITEM_FLAGS) | d.flags);
    for (size_t i = 0; i != d.stati.size(); i++) {
        const CreationStati &st = d.stati[i];
        if (st.duration)
            it->GainTempStati(st.nature, NULL, (int16)st.duration, SS_MISC,
                (int16)st.val, (int16)st.mag, st.eID);
        else
            it->GainPermStati(st.nature, NULL, SS_MISC, (int16)st.val,
                (int16)st.mag, st.eID);
    }
    return it;
}

/* ---- the Perk fields: ONE table, walked by the serializer and the parser --- */

static const char *perkTypeNames[] = { "PERK_NONE", "PERK_ITEM", "PERK_FEAT",
    "PERK_ABILITY", "PERK_SPELL", "PERK_RESIST", "PERK_IMMUNE", "PERK_TALENT" };

const char *CreationPerkTypeName(int t)
    { return (t >= 0 && t < 8) ? perkTypeNames[t] : "?"; }

int CreationPerkTypeFromName(const std::string &name)
{
    for (int i = 0; i != 8; i++)
        if (name == perkTypeNames[i])
            return i;
    return -1;
}

static std::string PerkItemWrite(const Perk &p)
{
    CreationItem it;
    it.iID = p.p.i.iID; it.eID = p.p.i.eID;
    it.plus = p.p.i.Plus; it.bane = p.p.i.Bane;
    for (int q = 0; q != 8; q++) it.q[q] = p.p.i.q[q];
    return ItemText(it);
}
static bool PerkItemRead(const std::string &t, Perk &p, std::string &err)
{
    CreationItem it;
    if (!CreationItemRead(t, it, err))
        return false;
    if (!it.iID) { err = "a perk item is not \"none\""; return false; }
    p.p.i.iID = it.iID; p.p.i.eID = it.eID;
    p.p.i.Plus = it.plus; p.p.i.Bane = it.bane;
    for (int q = 0; q != 8; q++) p.p.i.q[q] = it.q[q];
    return true;
}

static std::string PerkFeatWrite(const Perk &p) { return FeatName(p.p.feat); }
static bool PerkFeatRead(const std::string &t, Perk &p, std::string &err)
{
    int found = 0;
    for (int i = 0; FeatInfo[i].feat; i++)
        if (t == FeatInfo[i].name) {
            p.p.feat = (int16)FeatInfo[i].feat;
            found++;
        }
    if (found != 1)
        err = found ? "feat \"" + t + "\" is ambiguous" : "no feat named \"" + t + "\"";
    return found == 1;
}

static std::string PerkAbilityWrite(const Perk &p)
{
    return (const char*)Format("%s %d", Lookup(ClassAbilities, p.p.ability.ca_ability),
        (int)p.p.ability.ability_value);
}
static bool PerkAbilityRead(const std::string &t, Perk &p, std::string &err)
{
    size_t sp = t.rfind(' ');
    int32 v, a; int count;
    if (sp == std::string::npos || !ReadInt(t.substr(sp + 1), v)) {
        err = "an ability line is: <ability> <value>"; return false; }
    if (!TextValFind(ClassAbilities, t.substr(0, sp), a, count)) {
        err = "no class ability named \"" + t.substr(0, sp) + "\""; return false; }
    p.p.ability.ca_ability = (int16)a;
    p.p.ability.ability_value = v;
    return true;
}

static std::string PerkSpellWrite(const Perk &p) { return FullName(p.p.spell); }
static bool PerkSpellRead(const std::string &t, Perk &p, std::string &err)
    { return FindResource(FIND_EFFECT, t, p.p.spell, err); }

static std::string PerkResistWrite(const Perk &p)
{
    if (p.p.resist < 0)
        return std::string("save ") + Lookup(SaveBonusNames, -p.p.resist);
    return Lookup(DTypeNames, p.p.resist);
}
static bool PerkResistRead(const std::string &t, Perk &p, std::string &err)
{
    int32 v; int count;
    if (t.compare(0, 5, "save ") == 0) {
        if (!TextValFind(SaveBonusNames, t.substr(5), v, count)) {
            err = "no save bonus named \"" + t.substr(5) + "\""; return false; }
        p.p.resist = -v;
        return true;
    }
    if (!TextValFind(DTypeNames, t, v, count)) {
        err = "no damage type named \"" + t + "\""; return false; }
    p.p.resist = v;
    return true;
}

static std::string PerkImmuneWrite(const Perk &p) { return Lookup(DTypeNames, p.p.immune); }
static bool PerkImmuneRead(const std::string &t, Perk &p, std::string &err)
{
    int32 v; int count;
    if (!TextValFind(DTypeNames, t, v, count)) {
        err = "no damage type named \"" + t + "\""; return false; }
    p.p.immune = v;
    return true;
}

const CreationPerkField CreationPerkFields[] = {
    { PERK_ITEM,    CK_PERK_ITEM,    PerkItemWrite,    PerkItemRead },
    { PERK_FEAT,    CK_PERK_FEAT,    PerkFeatWrite,    PerkFeatRead },
    { PERK_ABILITY, CK_PERK_ABILITY, PerkAbilityWrite, PerkAbilityRead },
    { PERK_SPELL,   CK_PERK_SPELL,   PerkSpellWrite,   PerkSpellRead },
    { PERK_TALENT,  CK_PERK_SPELL,   PerkSpellWrite,   PerkSpellRead },
    { PERK_RESIST,  CK_PERK_RESIST,  PerkResistWrite,  PerkResistRead },
    { PERK_IMMUNE,  CK_PERK_IMMUNE,  PerkImmuneWrite,  PerkImmuneRead },
};
const int CreationPerkFieldCount = (int)(sizeof(CreationPerkFields) / sizeof(CreationPerkFields[0]));

/* The retained perk set, one named line per field (spec section 3). */
static void EmitPerks(const PerkSet &set)
{
    for (int j = 0; j != NUM_PERKS_PER_SET; j++) {
        const Perk &p = set.elt[j];
        if (p.type == PERK_NONE)
            continue;
        CreationContext c = MakeContext(CK_PERK_TYPE, Format("%d", j));
        Emit(CK_PERK_TYPE, c, CreationPerkTypeName(p.type));
        Advance(CK_PERK_TYPE, c);
        for (int f = 0; f != CreationPerkFieldCount; f++) {
            const CreationPerkField &pf = CreationPerkFields[f];
            if (pf.perkType != p.type)
                continue;
            CreationContext fc = MakeContext(pf.key, Format("%d", j));
            Emit(pf.key, fc, pf.write(p));
            Advance(pf.key, fc);
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

static std::string optionsBytes;
static bool haveOptions = false;

std::string CreationNormalize(const std::string &label)
{
    std::string s;
    for (size_t i = 0; i != label.size(); i++) {
        unsigned char c = (unsigned char)label[i];
        if (c < 32 || c >= 0xF0) {
            if (c == '\n' || c == '\t') s += ' ';
            continue;
        }
        if (c == '<') {
            size_t j = i + 1;
            while (j < label.size() && j - i <= 7 && isalnum((unsigned char)label[j]))
                j++;
            if (j < label.size() && label[j] == '>' && j > i + 1) {
                i = j;
                continue;
            }
        }
        s += (char)c;
    }
    size_t a = s.find_first_not_of(' '), b = s.find_last_not_of(' ');
    return a == std::string::npos ? std::string() : s.substr(a, b - a + 1);
}

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
    /* The two lines that are data, not decisions (spec 3, B11): the settings
       file the session ran under, or the changed copy written beside this
       file, and the session seed. */
    {
        const char *opts = getenv("INCURSION_OPTIONS");
        const char *seed = getenv("INCURSION_SEED");
        if (haveOptions)
            fprintf(f, "options: %s\n", (OptionsBase(path) + ".options.dat").c_str());
        else if (opts && *opts)
            fprintf(f, "options: %s\n", opts);
        if (seed && *seed)
            fprintf(f, "seed: %s\n", seed);
    }
    for (size_t i = 0; i != recorded.size(); i++) {
        std::string ctx = ContextText(recorded[i].ctx);
        std::string text = recorded[i].text;
        if (CreationKeyKind(recorded[i].key) == CKIND_PICK)
            text = CreationNormalize(text);
        if (ctx.empty())
            fprintf(f, "%s: %s\n", CreationKeyName(recorded[i].key), text.c_str());
        else
            fprintf(f, "%s [%s]: %s\n", CreationKeyName(recorded[i].key),
                ctx.c_str(), text.c_str());
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

    bool AnswerRoll(CreationKey, const CreationContext&, int32&,
        const CreationRange&) { return false; }
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

    bool AnswerRoll(CreationKey k, const CreationContext &c, int32 &v,
        const CreationRange&)
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
    haveStepMark = false;
    haveOptions = false;
    optionsBytes.clear();
    /* The tripwires arm with the File source, and only then. T1 stays armed to
       the end of the build (the NewGame tail reads keys too); T2 is the window. */
    if (activeSource == &CreationFileSource()) {
        g_t1Armed = true;
        g_t2Armed = true;
    }
}

CreationWindow::~CreationWindow()
{
    activeSource->Close(done);
    windowOpen = false;
    g_t2Armed = false;
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
    io.flags = (uint16)(it->IFlags & CREATION_ITEM_FLAGS);
    io.stati.clear();
    StatiIter(it)
        CreationStati st;
        st.nature = S->Nature; st.val = S->Val; st.mag = S->Mag;
        st.duration = S->Duration; st.eID = S->eID;
        io.stati.push_back(st);
    StatiIterEnd(it)
}

/* ---- the primitive halves -------------------------------------------------- */

bool CreationAnswerRoll(CreationKey k, const char *sub, int32 &v,
    const CreationRange &range)
{
    if (!windowOpen || itemDepth > 0)
        return false;
    CreationContext c = MakeContext(k, sub);
    if (!activeSource->AnswerRoll(k, c, v, range))
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

/* While a multi-answer pick asks for its answers one at a time, an empty queue
   is the end of the answers, not a missing line (the File backend reads it). */
static int pickManyDepth = 0;
bool CreationInPickMany() { return pickManyDepth > 0; }

bool CreationAnswerPickMany(CreationKey k, const char *sub, const CreationPickList &list,
    std::vector<int32> &values)
{
    values.clear();
    pickManyDepth++;
    for (size_t n = 0; n != list.names.size(); n++) {
        int32 v; std::string text; bool inList;
        if (!CreationAnswerPick(k, sub, list, v, text, inList))
            break;
        if (!inList) {
            values.clear();
            pickManyDepth--;
            return false;
        }
        values.push_back(v);
    }
    pickManyDepth--;
    /* A source that never runs `live` has answered, even with no value. */
    return !values.empty() || (windowOpen && activeSource->NeverLive());
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

/* ---- the tripwires (spec section 2; bead inc-10v7f phase 7b) ---------------- */

#ifndef _WIN32
#include <dlfcn.h>
#include <cxxabi.h>
#endif

bool g_t1Armed = false;
bool g_t2Armed = false;
int  g_unstatedDepth = 0;

/* The function that holds a return address, demangled, with the offset into it. */
static void NameCaller(void *ra, char *out, size_t n)
{
    snprintf(out, n, "?");
#ifndef _WIN32
    Dl_info di;
    if (ra && dladdr(ra, &di) && di.dli_sname) {
        int status = 0;
        char *dm = abi::__cxa_demangle(di.dli_sname, NULL, NULL, &status);
        snprintf(out, n, "%s+0x%lx", (status == 0 && dm) ? dm : di.dli_sname,
            (long)((char*)ra - (char*)di.dli_saddr));
        free(dm);
    }
#endif
}

static const char *BaseName(const char *f)
{
    const char *s = strrchr(f, '/');
    return s ? s + 1 : f;
}

/* T2. A draw is stated when a sourced decision's `live` is running (the draw
   is part of that decision) or an unstatedDraw scope names it as deciding no
   saved fact. Every other draw in the window fails the build. A Dice::Roll
   names its caller, not Roll, so the dice enter this with the return address
   they were called from. */
static void *t2DiceCaller = NULL;

void creation_t2_dice_enter(void *ra, void **prev)
{
    *prev = t2DiceCaller;
    t2DiceCaller = ra;
}
void creation_t2_dice_leave(void *prev) { t2DiceCaller = prev; }

void creation_t2_draw(const char *f, int l, const char *fn)
{
    if (CreationInsideLive() || g_unstatedDepth > 0)
        return;
    if (t2DiceCaller) {
        char who[300];
        NameCaller(t2DiceCaller, who, sizeof who);
        CreationBuildFail("T2 unstated dice roll called from %s: state it in the .char "
            "file or wrap the draw in unstatedDraw(\"<reason>\")", who);
    }
    CreationBuildFail("T2 unstated random draw in %s at %s:%d: state it in the .char "
        "file or wrap the draw in unstatedDraw(\"<reason>\")", fn, BaseName(f), l);
}

/* T1. ScreenTopText is the nearest the shared layer comes to a screen title:
   the first row with text on it, trimmed. */
void TextTerm::ScreenTopText(char *out, int n)
{
    int16 x, y;
    snprintf(out, n, "(blank screen)");
    for (y = Windows[WIN_SCREEN].Top; y <= Windows[WIN_SCREEN].Bottom; y++) {
        char row[256]; int len = 0;
        for (x = Windows[WIN_SCREEN].Left; x <= Windows[WIN_SCREEN].Right && len < (int)sizeof(row) - 1; x++) {
            int c = GLYPH_ID_VALUE(AGetChar(x, y));
            row[len++] = (c >= 32 && c < 127) ? (char)c : ' ';
        }
        row[len] = 0;
        const char *b = row;
        while (*b == ' ') b++;
        char *e = row + len;
        while (e > b && e[-1] == ' ') e--;
        *e = 0;
        if (*b) {
            snprintf(out, n, "%s", b);
            return;
        }
    }
}

static const char *ackKind = NULL, *ackText = NULL;
CreationAck::CreationAck(const char *kind, const char *text)
    : prevKind(ackKind), prevText(ackText)
{
    ackKind = kind;
    ackText = text ? text : "";
}
CreationAck::~CreationAck() { ackKind = prevKind; ackText = prevText; }

static void LogAck(const char *dir, const char *kind, const char *text)
{
    static int acks = 0;
    acks++;
    char path[1024], shown[80];
    snprintf(shown, sizeof shown, "%s", text);
    for (char *c = shown; *c; c++)
        if (*c == '"' || (unsigned char)*c < 32 || (unsigned char)*c > 126)
            *c = ' ';
    snprintf(path, sizeof path, "%slogs/build-acks.log", dir);
    FILE *f = fopen(path, "a");
    if (f) {
        fprintf(f, "ack %d window=%d %s \"%s\"\n", acks, windowOpen ? 1 : 0, kind, shown);
        fclose(f);
    }
    if (acks > 500)
        CreationBuildFail("T1 more than 500 acknowledgments; see %s", path);
}

/* The one gate every key read passes (the three wrappers in src/Term.cpp).
   False: let the backend read (a sourced decision's `live` is running).
   True: an acknowledgment, answered here with Enter. Otherwise the build fails
   and this does not return. */
bool TextTerm::T1Gate(const char *what, void *ra, int16 &key)
{
    if (CreationInsideLive())
        return false;
    if (ackKind) {
        LogAck((const char*)IncursionDirectory, ackKind, ackText);
        key = KY_ENTER;
        return true;
    }
    char who[300], screen[100];
    NameCaller(ra, who, sizeof who);
    ScreenTopText(screen, sizeof screen);
    CreationBuildFail("T1 key read outside a sourced decision: %s called from %s; the screen "
        "shows \"%s\" (nearest text, first row with text)", what, who, screen);
    return false;
}

__attribute__((noinline)) void CreationTripwireRawKeyScreen(Term *t)
{
    t->SetWin(WIN_SCREEN);
    t->Clear();
    t->Write(0, 0, "Tripwire probe screen");
    volatile int16 key = t->GetCharRaw();   /* not a tail call: T1 names this function */
    (void)key;
}

/* INCURSION_TRIPWIRE_PROBE: the fault-insertion switch of tools/check_fixture_tripwires.sh
   (inc-10v7f). Unset, no probe site does anything. */
bool CreationTripwireProbe(const char *name)
{
    static const char *probe = NULL;
    static bool read = false;
    if (!read) {
        read = true;
        const char *p = getenv("INCURSION_TRIPWIRE_PROBE");
        if (p && *p)
            probe = p;
    }
    if (!probe || strcmp(probe, name))
        return false;
    fprintf(stderr, "tripwire probe %s: fault inserted\n", name);
    fflush(stderr);
    return true;
}
