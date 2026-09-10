/* inc-4mxm: exercise the two display-only lighting trims, LightGain and
   LightMemoryBase, and print what they return.

   This links against the REAL src/Light.o from a completed build, so it
   measures the shipped arithmetic and not a copy of it. Light.o names about a
   dozen engine symbols; none of them is reachable from either function under
   test, so the stubs below exist only to satisfy the linker and abort if they
   are ever entered -- a stub that runs is itself a failure, and says so.

   No game session, no options file, no seed: both functions are pure, and a
   fixture would only add a way for the check to pass without measuring.

   tools/check_light_trim.sh is the only caller and holds the assertions. */

#include "Incursion.h"

#include <stdio.h>
#include <stdlib.h>

/* --- linker stubs. Entering one means the code under test grew a dependency
       it must not have, so each aborts loudly rather than returning. ------- */
static void Unreachable(const char *who) {
    fprintf(stderr, "PROBE BUG: %s was called; "
                    "the trims must touch no engine state\n", who);
    abort();
}

Term *T1 = NULL;
Game *theGame = NULL;
Registry *theRegistry = NULL;
long ZeroValue = 0;

void Error(const char *, ...) { Unreachable("Error"); }
int16 Player::Opt(int16) { Unreachable("Player::Opt"); return 0; }
bool Map::OpaqueAt(int16, int16) { Unreachable("Map::OpaqueAt"); return false; }
bool Map::LineOfLight(int16, int16, int16, int16)
    { Unreachable("Map::LineOfLight"); return false; }

static void Show(const char *tag, LightRGB c) {
    printf("%s %d %d %d\n", tag, (int)c.r, (int)c.g, (int)c.b);
}

int main(void) {
    /* A spread that covers the corners the assertions care about: pure black
       and pure white (the two fixed points of the gain curve), a saturated
       hue (ratios must survive), and a mid grey. */
    struct { const char *name; LightRGB c; } probe[] = {
        { "black",  {   0,   0,   0 } },
        { "white",  { 255, 255, 255 } },
        { "orange", { 255, 160,  60 } },   /* LIGHT_LEGACY_COLOUR */
        { "grey",   { 128, 128, 128 } },
        { "dim",    {  20,  12,   6 } },
    };
    const int nprobe = (int)(sizeof(probe) / sizeof(probe[0]));

    /* Every in-range step, then four out-of-range bytes. The options file is
       unversioned and one byte wide, so a foreign or corrupt file can hand
       these functions any int8 at all; each MUST fall back to Normal. */
    const int steps[] = { 0, 1, 2, 3, 4, -1, -128, 5, 127 };
    const int nsteps = (int)(sizeof(steps) / sizeof(steps[0]));

    for (int i = 0; i < nprobe; i++)
        for (int s = 0; s < nsteps; s++) {
            char tag[64];
            snprintf(tag, sizeof(tag), "gain %s %d", probe[i].name, steps[s]);
            Show(tag, LightGain(probe[i].c, steps[s]));
        }

    /* LIGHT_UNLIT_FLOOR and LIGHT_UNLIT_SOLID are the two unlit levels the
       renderer actually passes, so the memory sweep uses both. */
    const float floors[] = { LIGHT_UNLIT_FLOOR, LIGHT_UNLIT_SOLID };
    for (int i = 0; i < nprobe; i++)
        for (int f = 0; f < 2; f++)
            for (int s = 0; s < nsteps; s++) {
                char tag[64];
                snprintf(tag, sizeof(tag), "memory %s %d %d",
                         probe[i].name, f, steps[s]);
                Show(tag, LightMemoryBase(probe[i].c, floors[f], steps[s]));
            }

    return 0;
}
