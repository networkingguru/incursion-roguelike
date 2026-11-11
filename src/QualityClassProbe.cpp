/* inc-rddai: before/after observation of every place the engine decides
   "is this quality a weapon quality / an armor quality?" (formerly a
   number line). Off unless INCURSION_QUALITY_CLASS_PROBE is set;
   called once from Main.cpp at the start of Game::Play. The value picks a mode:
     1      full log: sites 1-3 (ItemLevel), site 4 (the Augment quality menu),
            site 5 (Oil of Transformation); writes logs/quality-class.log
     stage  put marker items in the pack, for the save test
     pack   log every pack item that has a quality, for the save test
   Lines: SETUP_ERROR case=<id> why=<text>, `QC <site> ...`, and a final
   `END lines=<n> errors=<n>`.

   Each case calls the REAL production method or script handler and reads its
   result. This file holds NO copy of the quality test; the one hook
   (inc/QualityClassProbe.h) reads and logs. The log must be byte-identical
   before and after the table replaces the number lines
   (tools/check_quality_class.sh). */
#include <vector>
#include <string>
#define protected public /* the probe writes Qualities[] */
#include "Incursion.h"
#include "QualityClassProbe.h"

static bool qcRun = false;
static FILE *qcLog = NULL;
static int qcLines = 0, qcErrors = 0, qcOffered = 0;
static const char *qcCase = "";

static void QCLine(const char *fmt, ...)
{
    va_list ap;
    fputs("QC ", qcLog);
    va_start(ap, fmt);
    vfprintf(qcLog, fmt, ap);
    va_end(ap);
    fputc('\n', qcLog);
    fflush(qcLog);
    qcLines++;
}

static bool QCErr(const char *id, const char *why)
{
    fprintf(qcLog, "SETUP_ERROR case=%s why=%s\n", id, why);
    fflush(qcLog);
    qcErrors++;
    return false;
}

void QualityClassOffered(int q)
{
    if (!qcRun) return;
    qcOffered++;
    QCLine("s4 item=%s n=%d", qcCase, q);
}

static const char *QCRet(EvReturn r)
{
    switch (r) {
        case NOTHING: return "NOTHING";
        case DONE:    return "DONE";
        case ABORT:   return "ABORT";
        case NOMSG:   return "NOMSG";
        case ERROR:   return "ERROR";
        default:      return "OTHER";
    }
}

static Item *QCMake(const char *id, const char *name, int plus)
{
    rID iID = FIND(name);
    Item *it = iID ? Item::Create(iID) : NULL;
    if (!it) { QCErr(id, "missing item resource"); return NULL; }
    it->SetInherentPlus(plus);
    it->SetQuantity(1);
    it->MakeKnown(0xFF);
    return it;
}

static void QCSlots(Item *it, char *out, size_t n)
{
    snprintf(out, n, "%d,%d,%d,%d,%d,%d,%d,%d",
        (int)it->GetQuality(0), (int)it->GetQuality(1), (int)it->GetQuality(2),
        (int)it->GetQuality(3), (int)it->GetQuality(4), (int)it->GetQuality(5),
        (int)it->GetQuality(6), (int)it->GetQuality(7));
}

/* Sites 1, 2, 3: one real ItemLevel call per quality number. */
static void QCLevels(int site)
{
    char id[8];
    snprintf(id, sizeof(id), "s%d", site);
    for (int q = 0; q <= 82; q++) {
        Item *it = QCMake(id, site == 1 ? "long sword" : "leather armour", 0);
        if (!it) return;
        QItem *qi = (QItem *)it;
        for (int i = 0; i < 8; i++) qi->Qualities[i] = 0;
        qi->Qualities[0] = (int8)q;
        if (qi->Qualities[0] != q) { delete it; QCErr(id, "quality readback"); return; }
        int lvl;
        if (site == 3) {
            if (!it->isType(T_ARMOUR)) { delete it; QCErr(id, "not armor"); return; }
            lvl = ((Armour *)it)->QItem::ItemLevel(true);
        } else
            lvl = it->ItemLevel();
        if (q == 0) QCLine("%s base lvl=%d", id, lvl);
        else        QCLine("%s q=%d lvl=%d", id, q, lvl);
        delete it;
    }
}

/* Site 4: one CraftItem(Augment) call. The key script answers the prompts. */
static void QCOffer(Player *p, const char *which, const char *name)
{
    Item *it = QCMake("s4", name, 1);
    if (!it) return;
    std::vector<std::pair<Item *, uint16> > others;
    for (Item *o = p->FirstInv(); o; o = p->NextInv()) {
        others.push_back(std::make_pair(o, o->Known));
        o->Known = 0;
    }
    p->GainItem(it, true);
    qcCase = which;
    qcOffered = 0;
    qcRun = true;
    EvReturn r = p->CraftItem(CA_WEAPONCRAFT + ABIL_VAL);
    qcRun = false;
    for (size_t i = 0; i < others.size(); i++)
        others[i].first->Known = others[i].second;
    QCLine("s4 item=%s ret=%s count=%d", which, QCRet(r), qcOffered);
    it->Remove(true);
}

static void QCOil(Player *p, const char *cname, const int *quals, int nq)
{
    rID oil = FIND("Oil of Transformation"), sword = FIND("long sword");
    Item *it = QCMake("s5", "light mace", 1);
    if (!it || !oil || !sword) { QCErr(cname, "missing resource"); return; }
    QItem *qi = (QItem *)it;
    for (int i = 0; i < 8; i++) qi->Qualities[i] = i < nq ? (int8)quals[i] : 0;
    p->GainItem(it, true);
    EventInfo e;
    e.Clear();
    e.Event = EV_MAGIC_HIT;
    e.EActor = p;
    e.ETarget = it;
    e.EMap = p->m;
    EvReturn r = RES(oil)->Event(e, oil, EV_MAGIC_HIT);
    if (it->iID != sword) QCErr(cname, "the oil did not choose a long sword");
    char slots[40];
    QCSlots(it, slots, sizeof(slots));
    QCLine("s5 case=%s ret=%s slots=%s", cname, QCRet(r), slots);
    it->Remove(true);
}

static void QCStage(Player *p)
{
    struct { const char *name; int n; int q[5]; } S[2] = {
        { "light mace",    5, { 7, 15, 26, 34, 60 } },
        { "leather armour", 2, { 15, 25, 0, 0, 0 } } };
    for (int k = 0; k < 2; k++) {
        Item *it = QCMake("stage", S[k].name, 1);
        if (!it) return;
        for (int i = 0; i < S[k].n; i++) it->AddQuality((int8)S[k].q[i]);
        for (int i = 0; i < 8; i++)
            if (it->GetQuality(i) != (i < S[k].n ? S[k].q[i] : 0)) {
                QCErr("stage", "quality readback");
                return;
            }
        p->GainItem(it, true);
        char slots[40];
        QCSlots(it, slots, sizeof(slots));
        QCLine("stage item=%s slots=%s", S[k].name, slots);
    }
}

static void QCPack(Player *p)
{
    int n = 0;
    for (Item *it = p->FirstInv(); it; it = p->NextInv(), n++) {
        bool any = false;
        for (int i = 0; i < 8; i++) if (it->GetQuality(i)) any = true;
        if (!any) continue;
        char slots[40];
        QCSlots(it, slots, sizeof(slots));
        QCLine("pack n=%d type=%d plus=%d slots=%s lvl=%d", n, (int)it->Type,
            (int)it->GetInherentPlus(), slots, (int)it->ItemLevel());
    }
}

void QualityClassProbe(Player *pl)
{
    /* inc-rddai */
    const char *mode = getenv("INCURSION_QUALITY_CLASS_PROBE");
    if (!mode || !*mode) return;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/quality-class.log",
        (const char *)T1->IncursionDirectory);
    qcLog = fopen(path, "w");
    if (!qcLog) return;
    if (!pl || !pl->m) {
        fprintf(qcLog, "SETUP_ERROR case=all why=no player or map\n");
        fclose(qcLog); qcLog = NULL;
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    const int8 autoMore = pl->Options[OPT_AUTOMORE];
    pl->Options[OPT_AUTOMORE] = 1;

    if (!strcmp(mode, "stage"))
        QCStage(pl);
    else if (!strcmp(mode, "pack"))
        QCPack(pl);
    else {
        QCLevels(1);
        QCLevels(2);
        QCLevels(3);
        pl->GainPermStati(INNATE_KIT, NULL, SS_MISC, SK_CRAFT);
        QCOffer(pl, "weapon", "light mace");
        QCOffer(pl, "armor", "leather armour");
        pl->RemoveStati(INNATE_KIT, SS_MISC, SK_CRAFT);
        const int plain[3] = { WQ_FLAMING, WQ_DISRUPTION, IQ_SILVER };
        const int unnamed[4] = { WQ_FLAMING, 15, 34, 60 };
        const int eight[8] = { WQ_FLAMING, 17, 19, 22, 23, 28, 29, 31 };
        QCOil(pl, "plain", plain, 3);
        QCOil(pl, "unnamed", unnamed, 4);
        QCOil(pl, "eight", eight, 8);
    }

    pl->Options[OPT_AUTOMORE] = autoMore;
    fprintf(qcLog, "END lines=%d errors=%d\n", qcLines, qcErrors);
    fclose(qcLog); qcLog = NULL;
    theGame->PlayMode = wasInPlay;
}
