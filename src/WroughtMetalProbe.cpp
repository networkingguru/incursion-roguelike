/* inc-8fl6: opt-in material/primal penalty reproduction; see check_wrought_metal.sh. */
#define protected public
#include "Incursion.h"
#undef protected

void WroughtMetalProbe(Player *pl) {
    const char *enabled = getenv("INCURSION_WROUGHT_METAL_PROBE");
    static bool ran = false;
    if (!enabled || strcmp(enabled, "1") || ran) return;
    ran = true;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/wrought-metal.log", (const char*)T1->IncursionDirectory);
    FILE *lg = fopen(path, "w");
    if (!lg) return;
    auto stop = [&](const char *why) {
        fprintf(lg, "INCONCLUSIVE %s\n", why); fclose(lg);
    };
    if (!pl || !pl->m || !pl->LevelAs(FIND("druid"))) {
        stop("requires loaded druid"); return;
    }
    rID base = FIND("chainmail shirt");
    if (!base || TITEM(base)->Material != MAT_IRON) {
        stop("chainmail shirt base is not iron"); return;
    }
    const char *names[] = { "iron", "orcish", "wrought", "none" };
    const int qualities[] = { 0, IQ_ORCISH, IQ_WROUGHT, 0 };
    int pri[4];
    for (int c = 0; c < 4; ++c) {
        for (int s = 0; s < SL_LAST; ++s)
            if (pl->InSlot(s)) pl->InSlot(s)->Remove(false);
        for (int s = 0; s < SL_LAST; ++s)
            if (pl->InSlot(s)) { stop("could not clear equipment"); return; }
        Item *armor = NULL;
        if (c != 3) {
            armor = Item::Create(base);
            if (!armor || !armor->isType(T_ARMOUR)) {
                stop("could not create body armor"); return;
            }
            if (qualities[c]) armor->AddQuality(qualities[c]);
            if (armor->Material() != (c ? MAT_WROUGHT : MAT_IRON) ||
                (qualities[c] && !armor->HasQuality(qualities[c]))) {
                stop("unexpected quality or material"); return;
            }
            armor->MakeKnown(0xff);
            pl->Inv[SL_ARMOUR] = armor->myHandle;
            armor->SetOwner(pl->myHandle);
            armor->IFlags |= IF_WORN;
            if (pl->EInSlot(SL_ARMOUR) != armor || !armor->activeSlot(SL_ARMOUR)) {
                stop("body armor is not active"); return;
            }
        }
        pl->CalcValues();
        pri[c] = pl->GetAttr(A_PRI);
        fprintf(lg, "%s Material=%d isMetallic=%d A_PRI=%d\n", names[c],
            armor ? armor->Material() : -1, armor ? armor->isMetallic() : 0, pri[c]);
        if (c == 0 && !armor->isMetallic()) {
            stop("iron is not metallic"); return;
        }
    }
    if (pri[0] >= pri[3]) { stop("iron control has no primal penalty"); return; }
    fprintf(lg, "COMPLETE\n");
    fclose(lg);
}
