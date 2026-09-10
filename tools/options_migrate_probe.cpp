/* inc-4mxm: exercise MigrateOptions over options arrays of each generation
   and print what it did to them.

   Links against the REAL src/Player.o from a completed build, so it measures
   the shipped migration rather than a copy of it. MigrateOptions touches
   nothing but the array it is handed, so Player.o's many other symbols are
   left to resolve at load time and are never entered.

   Rows are "<case> <explored> <bright> <gen>", the three bytes the migration
   is allowed to touch. tools/check_options_migrate.sh holds the assertions. */

#include "Incursion.h"

#include <stdio.h>
#include <string.h>

static void Show(const char *tag, const int8 *opt) {
    printf("%s %d %d %d\n", tag,
           (int)opt[OPT_LIGHT_EXPLORED], (int)opt[OPT_LIGHT_BRIGHT],
           (int)opt[OPT_SETTINGS_GEN]);
}

/* A few neighbouring display options, so the cases below can show that the
   migration leaves everything it was not asked to touch exactly alone. */
static void Fill(int8 *opt) {
    memset(opt, 0, OPT_LAST);
    opt[OPT_SOFT_PALETTE] = PALETTE_MUTED;
    opt[OPT_ANIMATION]    = 1;
    opt[OPT_CENTER_MAP]   = 1;
}

static bool Untouched(const int8 *opt) {
    return opt[OPT_SOFT_PALETTE] == PALETTE_MUTED
        && opt[OPT_ANIMATION] == 1
        && opt[OPT_CENTER_MAP] == 1;
}

int main(void) {
    int8 opt[OPT_LAST];

    /* 1. The case every existing installation is in: a file written before
          these options existed, so all three bytes read 0. */
    Fill(opt);
    MigrateOptions(opt);
    Show("old", opt);
    printf("old-neighbours %d\n", Untouched(opt) ? 1 : 0);

    /* 2. A file already at this generation, in which the player has chosen
          the darkest setting on purpose. Byte-for-byte that looks exactly
          like case 1 apart from the stamp, so this is the case that says
          whether the stamp is really being read. */
    Fill(opt);
    opt[OPT_LIGHT_EXPLORED] = LIGHT_STEP_DIMMEST;
    opt[OPT_LIGHT_BRIGHT]   = LIGHT_STEP_DIMMEST;
    opt[OPT_SETTINGS_GEN]   = OPT_GEN_LIGHT_TRIM;
    MigrateOptions(opt);
    Show("chosen", opt);

    /* 3. A file from a newer build than this one. Downgrading must lose
          nothing, so the migration has to leave it entirely alone. */
    Fill(opt);
    opt[OPT_LIGHT_EXPLORED] = LIGHT_STEP_BRIGHTEST;
    opt[OPT_LIGHT_BRIGHT]   = LIGHT_STEP_BRIGHTER;
    opt[OPT_SETTINGS_GEN]   = OPT_GEN_CURRENT + 7;
    MigrateOptions(opt);
    Show("future", opt);

    /* 4. Running it twice must change nothing the second time, because every
          read path calls it and a file is loaded many times over its life. */
    Fill(opt);
    MigrateOptions(opt);
    MigrateOptions(opt);
    Show("twice", opt);

    /* 5. A migrated file in which the player then picked a setting, saved,
          and loaded again -- the round trip that only works if the stamp
          persisted. */
    Fill(opt);
    MigrateOptions(opt);
    opt[OPT_LIGHT_BRIGHT] = LIGHT_STEP_BRIGHTEST;
    MigrateOptions(opt);
    Show("kept", opt);

    return 0;
}
