/* inc-rddai: read-only observation hook for src/QualityClassProbe.cpp.
   The hook returns at once unless the probe is running a case. It only reads
   and logs; it never decides, never returns early on behalf of its site and
   never changes game state. */
#ifndef INCURSION_QUALITYCLASSPROBE_H
#define INCURSION_QUALITYCLASSPROBE_H

/* Character::CraftItem calls this once per quality it offers, immediately
   before the LOption call that adds the quality to the menu. */
void QualityClassOffered(int q);

#endif
