/* Self-test for bead inc-5xn and upstream issue #40.
 *
 * The claim under test: random(int16 mx) returns an arbitrary int16 when mx is
 * negative, instead of a value bounded by mx. It is
 *
 *     return (int16)(genrand_int32() % mx);
 *
 * and genrand_int32() returns an unsigned 32-bit value. The usual arithmetic
 * conversions turn a negative mx into a huge unsigned modulus, so the
 * expression reduces to the raw random value, truncated to int16.
 *
 * That matters because Map::DrawPanel checks only the x extent of a furnishing
 * rect before passing it to Map::FurnishArea, so a rect inverted in y reaches
 * RANDOM_OPEN, which computes y = r.y1 + random(r.y2 - r.y1).
 *
 * Build and run:
 *     c++ -O2 -o /tmp/randneg docs/evidence/inc-5xn/random-negative-selftest.cpp
 *     /tmp/randneg    ->  exit 0 and "PASS", or exit 1 and the failing case
 *
 * genrand_int32 is stubbed with a settable value rather than linked from the
 * game, because the defect is in the arithmetic, not in the generator.
 */
#include <cstdio>
typedef short int16;

static unsigned long g_val;
static unsigned long genrand_int32(void) { return g_val; }

/* Copied verbatim from inc/Inline.h. */
static inline int16 random_(int16 mx)
  {
    if (!mx) return 0;
    return (int16)(genrand_int32() % mx);
  }

int main(void)
  {
    const int16 MAPSIZE = 128;
    const int16 y1 = 5, y2 = 4;         /* the first inverted rect observed */
    int i, escaped = 0, bounded = 1;
    int lo = 32767, hi = -32768;

    /* 1. A negative extent escapes the map. */
    for (i = 0; i < 20000; i++)
      {
        g_val = (unsigned long)i * 2654435761u;
        int16 y = (int16)(y1 + random_((int16)(y2 - y1)));
        if (y < lo) lo = y;
        if (y > hi) hi = y;
        if (y < 0 || y >= MAPSIZE)
          escaped++;
      }
    printf("random(%d): y ranged %d..%d; %d of 20000 left a %d-square map\n",
        (int)(y2 - y1), lo, hi, escaped, (int)MAPSIZE);

    /* 2. The same rect the right way round stays inside it. */
    for (i = 0; i < 20000; i++)
      {
        g_val = (unsigned long)i * 2654435761u;
        int16 y = (int16)(y2 + random_((int16)(y1 - y2)));
        if (y < y2 || y > y1)
          bounded = 0;
      }

    if (!escaped)
      { printf("FAIL: a negative extent stayed in bounds; the defect is gone "
               "or this test no longer reproduces it\n"); return 1; }
    if (!bounded)
      { printf("FAIL: a positive extent left its own range\n"); return 1; }
    printf("PASS: negative extent escapes, positive extent does not\n");
    return 0;
  }
