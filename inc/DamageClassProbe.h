/* inc-kx693: read-only observation hooks for src/DamageClassProbe.cpp.
   Each hook returns at once unless the probe is running a case. A hook only
   reads and logs; it never decides, never returns early on behalf of its site
   and never changes game state. */
#ifndef INCURSION_DAMAGECLASSPROBE_H
#define INCURSION_DAMAGECLASSPROBE_H

#define DC_SITE_MIEN_BEFORE 0
#define DC_SITE_MIEN_AFTER  1
#define DC_SITE_TAH_BEFORE  2
#define DC_SITE_TAH_AFTER   3
#define DC_SITE_GOD_AFTER   4
#define DC_SITE_ILL_PASSED  5
#define DC_SITE_COUNT       6

void DamageClassCheckpoint(int site, EventInfo &e);
void DamageClassDamageEntry(EventInfo &e);
void DamageClassItemDamage(Item *it);
void DamageClassHandler(rID xID, EventInfo &e);
void DamageClassGodEntry(EventInfo &e);

#endif
