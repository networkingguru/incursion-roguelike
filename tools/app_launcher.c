/* Entry point for Incursion.app.
 *
 * WHY THIS EXISTS. The game keeps ONE directory and uses it for both reading and
 * writing: mod/ and fonts/ are read from it, Options.Dat, save/ and logs/ are
 * written into it, and the engine chdir()s into its own subdirectories
 * (src/Wposix.cpp:769). Inside an app bundle that is fatal twice over -- a
 * standard user cannot write into /Applications, and a bundle that writes inside
 * itself breaks its own code signature, which is the exact "app has been
 * modified or damaged" refusal that took the first release down (inc-g1y).
 *
 * So this launcher puts that single directory somewhere writable, and makes the
 * read-only data appear inside it:
 *
 *     ~/Library/Application Support/Incursion/
 *         mod    -> <bundle>/Contents/Resources/mod     symlink
 *         fonts  -> <bundle>/Contents/Resources/fonts   symlink
 *         Options.Dat   real file, seeded on first run
 *         save/         real directory
 *         logs/         real directory
 *
 * The game then sees one ordinary directory holding all five things and never
 * learns that two of them live inside a signed bundle. INCURSIONPATH is the
 * engine's own override (src/Wlibtcod.cpp:419) and is already exercised by the
 * headless harness, so this is a tested path rather than new machinery.
 *
 * ponytail: the real fix is to split the read root from the write root, so the
 * game reads from the bundle and writes to Application Support with no symlinks
 * at all. That is 65 call sites in the save system plus removing the reliance on
 * chdir(), tracked separately. The ceiling of THIS approach: the links are
 * rebuilt on every launch, so a moved or replaced bundle is fine, but anything
 * that resolves the game directory and then expects to write into mod/ or
 * fonts/ would fail. Nothing does today -- Game::SaveModule is the only writer
 * under mod/ and its one caller, RComp.cpp:223, is inside #ifdef DEBUG and so
 * is not in a shipping build.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <libgen.h>
#include <sys/stat.h>
#include <mach-o/dyld.h>

static void die(const char *what, const char *path) {
    fprintf(stderr, "Incursion could not start: %s (%s): %s\n",
            what, path ? path : "-", strerror(errno));
    exit(1);
}

static void ensure_dir(const char *path) {
    struct stat st;
    if (lstat(path, &st) == 0) {
        if (S_ISDIR(st.st_mode))
            return;
        errno = ENOTDIR;
        die("not a directory", path);
    }
    if (mkdir(path, 0755) != 0 && errno != EEXIST)
        die("could not create directory", path);
}

/* Rebuilt on EVERY launch, not just the first: the bundle can be replaced by an
   update or dragged somewhere else, and a stale link would leave the game
   unable to find its own data. A real directory here is left untouched, because
   that is a user who put their own data in the way and we must not delete it. */
static void relink(const char *target, const char *linkpath) {
    struct stat st;
    if (lstat(linkpath, &st) == 0) {
        if (S_ISLNK(st.st_mode)) {
            if (unlink(linkpath) != 0)
                die("could not replace stale link", linkpath);
        } else {
            return;
        }
    }
    if (symlink(target, linkpath) != 0)
        die("could not link data into place", linkpath);
}

static void seed_file(const char *from, const char *to) {
    FILE *in, *out;
    char buf[65536];
    size_t n;
    struct stat st;

    if (stat(to, &st) == 0)
        return;                       /* the player's own settings; never clobber */
    in = fopen(from, "rb");
    if (!in)
        return;                       /* nothing to seed from is not fatal */
    out = fopen(to, "wb");
    if (!out) {
        fclose(in);
        die("could not write settings", to);
    }
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0)
        if (fwrite(buf, 1, n, out) != n) {
            fclose(in);
            fclose(out);
            die("could not write settings", to);
        }
    fclose(in);
    fclose(out);
}

int main(int argc, char *argv[]) {
    char exec_path[4096];
    uint32_t sz = sizeof(exec_path);
    char macos_dir[4096], resources[4096], support[4096], path[4096], game[4096];
    char link_target[4096];
    const char *home;
    char **child_argv;
    int i;

    if (_NSGetExecutablePath(exec_path, &sz) != 0)
        die("could not locate the application", NULL);

    /* .../Contents/MacOS/Incursion -> .../Contents/MacOS */
    snprintf(macos_dir, sizeof(macos_dir), "%s", dirname(exec_path));
    snprintf(resources, sizeof(resources), "%s/../Resources", macos_dir);
    /* incursion-game, not incursion: macOS filesystems are case-insensitive, so
       a binary named "incursion" beside a launcher named "Incursion" is the same
       file and one silently overwrites the other. */
    snprintf(game, sizeof(game), "%s/incursion-game", macos_dir);

    home = getenv("HOME");
    if (!home || !*home) {
        errno = ENOENT;
        die("no home directory", NULL);
    }

    /* Build the path a level at a time: mkdir does not create parents, and on a
       fresh account "Application Support" may genuinely not exist yet. */
    snprintf(path, sizeof(path), "%s/Library", home);
    ensure_dir(path);
    snprintf(path, sizeof(path), "%s/Library/Application Support", home);
    ensure_dir(path);
    snprintf(support, sizeof(support), "%s/Library/Application Support/Incursion", home);
    ensure_dir(support);

    snprintf(path, sizeof(path), "%s/save", support);
    ensure_dir(path);
    /* logs/ must exist before the game builds "logs/screens" (Wposix.cpp:777). */
    snprintf(path, sizeof(path), "%s/logs", support);
    ensure_dir(path);

    snprintf(link_target, sizeof(link_target), "%s/mod", resources);
    snprintf(path, sizeof(path), "%s/mod", support);
    relink(link_target, path);

    snprintf(link_target, sizeof(link_target), "%s/fonts", resources);
    snprintf(path, sizeof(path), "%s/fonts", support);
    relink(link_target, path);

    snprintf(link_target, sizeof(link_target), "%s/Options.Dat", resources);
    snprintf(path, sizeof(path), "%s/Options.Dat", support);
    seed_file(link_target, path);

    /* The engine reads this and uses it as its one directory. The trailing
       slash is optional -- main() appends one if it is missing -- but being
       explicit costs nothing. */
    snprintf(path, sizeof(path), "%s/", support);
    if (setenv("INCURSIONPATH", path, 1) != 0)
        die("could not set INCURSIONPATH", path);

    /* Hand every argument through, so `open -a Incursion --args -whatever`
       still reaches the game. argv[0] becomes the game's own path, which is
       what its argv[0] data-directory fallback expects if INCURSIONPATH is ever
       unset. */
    child_argv = calloc((size_t)argc + 1, sizeof(char *));
    if (!child_argv)
        die("out of memory", NULL);
    child_argv[0] = game;
    for (i = 1; i < argc; i++)
        child_argv[i] = argv[i];
    child_argv[argc] = NULL;

    execv(game, child_argv);
    die("could not start the game binary", game);
    return 1;
}
