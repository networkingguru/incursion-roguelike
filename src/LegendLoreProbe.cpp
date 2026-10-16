/* inc-8chz: diagnostic only; writes nothing unless INCURSION_LEGEND_LORE_PROBE
   is set. Logs each Character::LegendIdent pass over a magic item: the item
   handle, whether the once-only roll fired, the roll and its margin over the
   item level, and which knowledge bits the item holds before and after.
   Read by tools/check_legend_lore.sh. */
#include "Incursion.h"

static void llBits(char *out, Item *it) {
    static const uint8 kn[7] = { KN_NATURE, KN_CURSE, KN_BLESS, KN_MAGIC,
                                 KN_PLUS, KN_PLUS2, KN_ARTI };
    for (int k = 0; k < 7; k++)
        out[k] = it->isKnown(kn[k]) ? '1' : '0';
    out[7] = 0;
}

void LegendLoreProbe(const char *stage, Item *it, int rolled, int check,
                     int margin, const char *bitsBefore)
{
    if (!getenv("INCURSION_LEGEND_LORE_PROBE")) return;
    char path[1024], bits[8];
    snprintf(path, sizeof(path), "%slogs/legend-lore.log",
        (const char*)T1->IncursionDirectory);
    FILE *log = fopen(path, "a");
    if (!log) return;
    llBits(bits, it);
    fprintf(log, "%s item=%d level=%d rolled=%d check=%d margin=%d before=%s after=%s flag=%d\n",
        stage, (int)it->myHandle, (int)it->ItemLevel(), rolled, check, margin,
        bitsBefore ? bitsBefore : "-", bits, (it->IFlags & IF_LEGEND_ROLLED) ? 1 : 0);
    fclose(log);
}

void LegendLoreProbeBits(char *out, Item *it) { llBits(out, it); }
