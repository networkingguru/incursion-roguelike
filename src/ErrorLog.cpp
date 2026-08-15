/* ERRORLOG.CPP -- See the Incursion LICENSE file for copyright information.

     bool isRotatedLogName(const char *name)
     void RotateErrorLog(const char *dir, const char *live)

     Every run used to append to a single logs/errors.log, so isolating what
   happened in one session meant editing the file by hand -- logs/ still holds
   two archives named that way. One file per run, named for when that run's
   errors happened rather than for now, makes a session report a matter of
   picking a file.

     This deletes files, so it is deliberately conservative: it prunes only
   names it produced itself, and it leaves the live log alone if anything
   fails. Depends on nothing from the game, so tools/check_logrotate.sh can
   exercise it directly.
*/

#include "ErrorLog.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cctype>
#include <ctime>
#include <dirent.h>
#include <execinfo.h>   /* backtrace(), for the call stack in the log */
#include <unistd.h>
#include <sys/stat.h>

/* "errors-YYYYMMDD-HHMMSS.log" is 26 characters, with the only non-digits at
   a fixed separator and the suffix. Matching the whole shape rather than the
   "errors-" prefix is what protects a hand-named file such as
   logs/errors-before-boundsfix.log from being pruned. */
bool isRotatedLogName(const char *name) {
    int i;

    if (!name || strlen(name) != 26)
        return false;
    if (strncmp(name, "errors-", 7) || strcmp(name + 22, ".log"))
        return false;
    for (i = 7; i != 22; i++) {
        if (i == 15) {
            if (name[i] != '-')
                return false;
        } else if (!isdigit((unsigned char)name[i]))
            return false;
    }
    return true;
}

/* Delete the oldest archives beyond ERRLOG_KEEP.

   Kept separate from archiving, and called unconditionally, because the two
   are independent: an archive that has grown past the limit still needs
   trimming on a run that has nothing of its own to file away. Folding this
   into the archiving path meant a run that declined to rotate also silently
   skipped pruning. */
static void PruneArchive(const char *dir) {
    char logdir[1200], victim[1500];
    char names[256][32];
    const int maxNames = (int)(sizeof(names) / sizeof(names[0]));
    struct dirent *ent;
    DIR *d;
    int n = 0, i, j;

    snprintf(logdir, sizeof(logdir), "%slogs", dir);
    d = opendir(logdir);
    if (!d)
        return;
    while ((ent = readdir(d)) != NULL && n < maxNames)
        if (isRotatedLogName(ent->d_name))
            snprintf(names[n++], sizeof(names[0]), "%s", ent->d_name);
    closedir(d);

    /* The timestamp format sorts lexicographically in time order, so a plain
       string sort puts the oldest first. */
    for (i = 1; i < n; i++) {
        char tmp[32];
        snprintf(tmp, sizeof(tmp), "%s", names[i]);
        for (j = i; j > 0 && strcmp(names[j - 1], tmp) > 0; j--)
            snprintf(names[j], sizeof(names[0]), "%s", names[j - 1]);
        snprintf(names[j], sizeof(names[0]), "%s", tmp);
    }
    for (i = 0; i < n - ERRLOG_KEEP; i++) {
        snprintf(victim, sizeof(victim), "%s/%s", logdir, names[i]);
        unlink(victim);
    }
}

void RotateErrorLog(const char *dir, const char *live) {
    struct stat st;
    char stamp[32], dest[1400];

    if (!stat(live, &st) && st.st_size > 0) {
        /* Name the archive for the previous run, not for this one. */
        strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", localtime(&st.st_mtime));
        snprintf(dest, sizeof(dest), "%slogs/errors-%s.log", dir, stamp);

        /* Two runs inside the same second produce the same archive name.
           Overwriting would destroy the earlier one, so leave the live log in
           place instead and let this run append to it. Losing the separation
           between two runs beats losing a run. */
        if (stat(dest, &st))
            rename(live, dest);   /* on failure, keep appending rather than lose it */
    }

    PruneArchive(dir);
}

/* Moved here from src/Wlibtcod.cpp, where it was a static: the headless
   backend needs the same logger, and two copies of an error log would drift. */
void LogError(const char *dir, const char *msg, const char *banner) {
    static FILE *errLog = NULL;
    static char seen[24][160];
    static int seenCount = 0;
    char stamp[32];
    time_t now;
    int i;

    if (!errLog) {
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/errors.log", dir);
        RotateErrorLog(dir, path);
        errLog = fopen(path, "a");
        if (!errLog)
            return;
        /* Head the file with what produced it. A log that does not say which
           build wrote it cannot be compared against another run. */
        fprintf(errLog, "%s\n", banner ? banner : "=== session ===");
    }
    time(&now);
    strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", localtime(&now));
    fprintf(errLog, "%s  %s\n", stamp, msg);

    for (i = 0; i < seenCount; i++)
        if (!strcmp(seen[i], msg))
            break;
    if (i == seenCount && seenCount < (int)(sizeof(seen)/sizeof(seen[0]))) {
        void *frames[24];
        int n = backtrace(frames, 24);
        char **names = backtrace_symbols(frames, n);

        snprintf(seen[seenCount++], sizeof(seen[0]), "%s", msg);
        fprintf(errLog, "    --- first occurrence, call stack ---\n");
        if (names) {
            for (i = 0; i < n; i++)
                fprintf(errLog, "    %s\n", names[i]);
            free(names);
        }
        fprintf(errLog, "    --- end ---\n");
    }

    fflush(errLog);
    fprintf(stderr, "Incursion error: %s\n", msg);
}
