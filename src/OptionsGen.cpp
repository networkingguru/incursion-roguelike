/* OPTIONSGEN.CPP -- See the Incursion LICENSE file for copyright information.

   The options file's version field, and the one operation on it.

   Player::LoadOptions reads a bare array of one byte per option with no header
   of any kind, so an option added later reads 0 from every file written before
   it existed -- and 0 is a perfectly good menu index, so the new option comes
   up silently at its FIRST choice instead of the default its OptionList row
   asks for. Before OPT_SETTINGS_GEN existed the only way round that was to
   promise 0 would keep its old meaning forever, which is what the note on
   OPT_SOFT_PALETTE in inc/Defines.h had to do, and which forces every new
   option's scale to be ordered around the byte rather than around the reader.

   This lives in its own file, away from the engine, so a check can link it on
   its own and measure it: src/Player.cpp names 143 symbols and cannot be
   loaded outside the game, and a migration that quietly stopped migrating
   would look exactly like one that worked. tools/check_options_migrate.sh is
   that check. Keep this file free of engine dependencies. */

#include "Incursion.h"

/* Bring an options array just read from disk up to OPT_GEN_CURRENT.

   OPT_SETTINGS_GEN records which options a file was written knowing about;
   anything newer gets the default its OptionList row asks for.

   This writes ONLY options whose generation is newer than the file's, so it
   can never overrule a choice the player actually made: at the moment a
   generation is introduced, every option in it is one this file has never
   held a value for. A file from a newer build than this one is left entirely
   alone, stamp included, so downgrading loses nothing. It is idempotent, and
   it must stay so: every path that reads the file calls it.

   Call it on every array read from the file, and nowhere else. Defaults for a
   file that does not exist are already applied from OptionList by the caller.

   TO ADD AN OPTION LATER: raise OPT_GEN_CURRENT by one, give the new value its
   own OPT_GEN_* name, and add one branch below. Never renumber an existing
   generation, and never lower OPT_GEN_CURRENT. */
void MigrateOptions(int8 *opt) {
    const int8 gen = opt[OPT_SETTINGS_GEN];
    if (gen >= OPT_GEN_CURRENT)
        return;
    if (gen < OPT_GEN_LIGHT_TRIM) {
        opt[OPT_LIGHT_EXPLORED] = LIGHT_STEP_NORMAL;
        opt[OPT_LIGHT_BRIGHT]   = LIGHT_STEP_NORMAL;
    }
    opt[OPT_SETTINGS_GEN] = OPT_GEN_CURRENT;
}
