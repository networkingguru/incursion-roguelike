#!/bin/bash
# Regression check for error-log rotation and retention.
#
# This code DELETES FILES in logs/, so it gets a real test rather than a
# read-through. Two properties matter, and only one of them is obvious:
#
#   1. It keeps the most recent ERRLOG_KEEP archives and prunes older ones.
#   2. It prunes ONLY names it produced itself. logs/ also holds files a human
#      named by hand -- errors-before-boundsfix.log is a deliberate keepsake
#      from the save-corruption investigation. Deleting one of those would be
#      losing evidence, which is worse than keeping too many logs.
#
# src/ErrorLog.cpp depends on nothing from the game, so this compiles it
# directly against a temporary directory. No terminal, no window, no module.
#
# Usage: tools/check_logrotate.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/t.cpp" <<'EOF'
#include "ErrorLog.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <sys/stat.h>
#include <unistd.h>

static int failures = 0;

static void expect(bool got, bool want, const char *what) {
    if (got != want) {
        printf("  FAIL %s: got %d want %d\n", what, (int)got, (int)want);
        failures++;
    }
}

static void touchFile(const char *path, const char *body) {
    FILE *f = fopen(path, "w");
    if (!f) { printf("  FAIL cannot write %s\n", path); failures++; return; }
    fputs(body, f);
    fclose(f);
}

static bool exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

int main(int argc, char **argv) {
    char dir[1024], logs[1100], live[1200], p[1400];
    int i;

    snprintf(dir, sizeof(dir), "%s/", argv[1]);
    snprintf(logs, sizeof(logs), "%slogs", dir);
    mkdir(logs, 0755);
    snprintf(live, sizeof(live), "%s/errors.log", logs);

    /* --- the name matcher, which is what guards deletion --- */
    expect(isRotatedLogName("errors-20260814-103000.log"), true,  "canonical name");
    expect(isRotatedLogName("errors-before-boundsfix.log"), false, "hand-named keepsake");
    expect(isRotatedLogName("errors-17-15.log"),            false, "hand-named short");
    expect(isRotatedLogName("errors.log"),                  false, "the live log");
    expect(isRotatedLogName("errors-20260814-103000.txt"),  false, "wrong suffix");
    expect(isRotatedLogName("errors-2026081-4103000.log"),  false, "separator moved");
    expect(isRotatedLogName("errors-2026081a-103000.log"),  false, "non-digit");
    expect(isRotatedLogName("saveprobe.log"),               false, "unrelated log");
    expect(isRotatedLogName(""),                            false, "empty");
    expect(isRotatedLogName(NULL),                          false, "null");

    /* --- an absent live log must not produce an archive --- */
    RotateErrorLog(dir, live);
    /* --- an empty live log is not worth keeping --- */
    touchFile(live, "");
    RotateErrorLog(dir, live);
    expect(exists(live), true, "empty live log left in place");

    /* --- a non-empty live log gets archived --- */
    touchFile(live, "one error\n");
    RotateErrorLog(dir, live);
    expect(exists(live), false, "live log moved aside");

    /* --- pruning keeps ERRLOG_KEEP and spares hand-named files --- */
    snprintf(p, sizeof(p), "%s/errors-before-boundsfix.log", logs);
    touchFile(p, "keepsake\n");
    snprintf(p, sizeof(p), "%s/errors-17-15.log", logs);
    touchFile(p, "keepsake\n");
    for (i = 0; i < ERRLOG_KEEP + 5; i++) {
        snprintf(p, sizeof(p), "%s/errors-202608%02d-120000.log", logs, i + 1);
        touchFile(p, "archived\n");
    }
    touchFile(live, "trigger\n");
    RotateErrorLog(dir, live);

    /* The oldest five must be gone. */
    for (i = 0; i < 5; i++) {
        snprintf(p, sizeof(p), "%s/errors-202608%02d-120000.log", logs, i + 1);
        expect(exists(p), false, "oldest archive pruned");
    }
    /* The newest must remain. */
    snprintf(p, sizeof(p), "%s/errors-202608%02d-120000.log", logs, ERRLOG_KEEP + 5);
    expect(exists(p), true, "newest archive kept");
    /* Both hand-named files must be untouched. */
    snprintf(p, sizeof(p), "%s/errors-before-boundsfix.log", logs);
    expect(exists(p), true, "hand-named keepsake survived pruning");
    snprintf(p, sizeof(p), "%s/errors-17-15.log", logs);
    expect(exists(p), true, "hand-named short name survived pruning");

    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
EOF

if ! clang++ -std=c++17 -w -Iinc -o "$TMP/t" "$TMP/t.cpp" src/ErrorLog.cpp 2>"$TMP/build.log"; then
    echo "FAIL: could not build the log-rotation test"
    cat "$TMP/build.log"
    exit 1
fi

if "$TMP/t" "$TMP"; then
    echo "PASS: log rotation keeps the recent archives and spares hand-named files"
    exit 0
else
    echo "FAIL: log rotation misbehaved (see above)"
    exit 1
fi
