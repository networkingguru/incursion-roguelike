/* ERRORLOG.H -- See the Incursion LICENSE file for copyright information.

     Rotation and retention for logs/errors.log. Split out of Wlibtcod.cpp so
   the naming and pruning rules can be tested without linking a terminal, a
   window system or the game itself. See tools/check_logrotate.sh.
*/

#ifndef INCURSION_ERRORLOG_H
#define INCURSION_ERRORLOG_H

/* Archived sessions to keep. Older ones are deleted oldest-first. */
#define ERRLOG_KEEP 10

/* True only for names this rotator itself produced: exactly
   "errors-YYYYMMDD-HHMMSS.log". Anything else in logs/ is somebody's
   deliberate keepsake and must survive pruning. */
bool isRotatedLogName(const char *name);

/* Move `live` aside, naming the archive after its last write rather than the
   current time, then prune the archive to ERRLOG_KEEP entries. Does nothing
   when `live` is absent or empty. `dir` must end in a path separator. */
void RotateErrorLog(const char *dir, const char *live);

/* Append one error to `dir`logs/errors.log, and echo it to stderr. Rotates on
   the first call of a run, then writes `banner` as the session header. Records
   one call stack per distinct message: without it the log says what went wrong
   but not which caller did it, and these fire hundreds of times.

     `banner` carries the version and build stamp rather than this file reading
   them, because every backend has its own, and because ErrorLog.cpp depends on
   nothing from the game -- which is what lets tools/check_logrotate.sh compile
   it on its own. `dir` must end in a path separator. */
void LogError(const char *dir, const char *msg, const char *banner);

#endif
