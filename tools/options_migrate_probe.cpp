/* inc-4mxm: exercise MigrateOptions over options arrays of each generation
   and print what it did to them.

   Links against the REAL src/OptionsGen.o from a completed build, so it
   measures the shipped migration rather than a copy of it. MigrateOptions
   touches nothing but the array it is handed, so the object's many other
   symbols are left to resolve at load time and are never entered.

   Rows are "<case> <explored> <bright> <auto-terms> <gen>", the bytes the
   migration is allowed to touch. tools/check_options_migrate.sh holds the
   assertions. The generations themselves are printed as "<NAME> <value>" so
   the check never hard-codes them. */

#include "Incursion.h"

#include <stdio.h>
#include <string.h>

static void Show(const char *tag, const int8 *opt) {
    printf("%s %d %d %d %d\n", tag,
           (int)opt[OPT_LIGHT_EXPLORED], (int)opt[OPT_LIGHT_BRIGHT],
           (int)opt[OPT_AUTO_TERMS], (int)opt[OPT_SETTINGS_GEN]);
}

/* A few neighbouring options, so the cases below can show that the migration
   leaves everything it was not asked to touch exactly alone. OPT_WARN_DROP
   (311) and OPT_HIGH_HIDE (350) straddle OPT_AUTO_TERMS (312): 311 is the
   byte just before it and the next defined option is 350, so 313 is chosen as
   the first byte after the 312 field that the file actually carries. */
static void Fill(int8 *opt) {
    memset(opt, 0, OPT_LAST);
    opt[OPT_SOFT_PALETTE] = PALETTE_MUTED;
    opt[OPT_ANIMATION]    = 1;
    opt[OPT_CENTER_MAP]   = 1;
    opt[OPT_WARN_DROP]    = 1;
    opt[OPT_AUTO_TERMS + 1] = 1;
}

static bool Untouched(const int8 *opt) {
    return opt[OPT_SOFT_PALETTE] == PALETTE_MUTED
        && opt[OPT_ANIMATION] == 1
        && opt[OPT_CENTER_MAP] == 1
        && opt[OPT_WARN_DROP] == 1
        && opt[OPT_AUTO_TERMS + 1] == 1;
}

int main(void) {
    int8 opt[OPT_LAST];

    /* The generations this build knows, so the check measures against them
       rather than a copy. */
    printf("GEN_NONE %d\n", (int)OPT_GEN_NONE);
    printf("GEN_LIGHT_TRIM %d\n", (int)OPT_GEN_LIGHT_TRIM);
    printf("GEN_AUTO_TERMS %d\n", (int)OPT_GEN_AUTO_TERMS);
    printf("GEN_CURRENT %d\n", (int)OPT_GEN_CURRENT);

    /* 1. The case every existing installation is in: a file written before
          these options existed, so all the touched bytes read 0. Both the
          light step and the generation-2 step must apply. */
    Fill(opt);
    MigrateOptions(opt);
    Show("old", opt);
    printf("old-neighbours %d\n", Untouched(opt) ? 1 : 0);

    /* 2. A file stamped at generation 1, in which the player has chosen the
          darkest light setting on purpose. Byte-for-byte the light bytes look
          exactly like case 1 apart from the stamp, so this is the case that
          says whether the stamp is really being read. It now also gets the
          generation-2 step, which must set byte 312 without touching the
          chosen light values. */
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

    /* 6. A file stamped at generation 1 (the light trim) gets byte 312 set to
          1 and its light options left exactly as written. */
    Fill(opt);
    opt[OPT_LIGHT_EXPLORED] = LIGHT_STEP_BRIGHTEST;
    opt[OPT_LIGHT_BRIGHT]   = LIGHT_STEP_DIMMER;
    opt[OPT_SETTINGS_GEN]   = OPT_GEN_LIGHT_TRIM;
    MigrateOptions(opt);
    Show("gen1", opt);

    /* 7. A file already at generation 2 with byte 312 = 0: a player who
          turned Auto-Offer Terms off. The stamp is current, so the migration
          must leave the zero alone. */
    Fill(opt);
    opt[OPT_AUTO_TERMS]   = 0;
    opt[OPT_SETTINGS_GEN] = OPT_GEN_AUTO_TERMS;
    MigrateOptions(opt);
    Show("off-at-gen2", opt);

    /* 8. A file stamped at generation 0: both the light step and the
          generation-2 step apply. */
    Fill(opt);
    opt[OPT_SETTINGS_GEN] = OPT_GEN_NONE;
    MigrateOptions(opt);
    Show("gen0", opt);

    return 0;
}
