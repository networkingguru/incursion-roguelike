/* Probe: does libtcod recalculate its copy rectangle after a mode change?
 *
 * inc-i2h1. A key script cannot reach this defect -- injected keys enter at
 * MapKey (src/Wlibtcod.cpp:2088) and skip the Alt-Enter branch -- and @shot
 * cannot see it, because @shot saves the console surface captured before the
 * faulty copy. So this probe calls libtcod directly, in the same order
 * libtcodTerm::Reset() (src/Wlibtcod.cpp:1479) calls it, and reads the numbers
 * that decide what SDL puts on the screen.
 *
 * It needs a real display. Phase C opens a fullscreen window for a moment.
 *
 * Exit: 0 every assertion held, 1 one did not.
 */
#include <stdio.h>
#include <string.h>
#include "libtcod.h"
#include "libtcod_int.h"

static int failures = 0;

/* The console's pixel size is the only correct source rectangle: every pixel
   of the console, and no pixel outside it. */
static int console_px_w(void) { return TCOD_ctx.root->w * TCOD_ctx.font_width; }
static int console_px_h(void) { return TCOD_ctx.root->h * TCOD_ctx.font_height; }

static void open_root(int cols, int rows, const char *font, bool fullscreen) {
    TCOD_console_set_custom_font(font, TCOD_FONT_LAYOUT_ASCII_INROW, 16, 16);
    TCOD_console_init_root(cols, rows, "libtcod mode change probe", fullscreen,
                           TCOD_RENDERER_SDL);
    TCOD_console_flush();  /* render() is what computes scale_data */
}

static void show(const char *phase) {
    printf("  %-22s console=%dx%d  src_copy=%dx%d  dst=%dx%d  is_fullscreen=%d\n",
           phase, console_px_w(), console_px_h(),
           scale_data.src_copy_width, scale_data.src_copy_height,
           scale_data.dst_display_width, scale_data.dst_display_height,
           (int)TCOD_console_is_fullscreen());
}

static void want_whole_console(const char *phase) {
    if (scale_data.src_copy_width == console_px_w() &&
        scale_data.src_copy_height == console_px_h())
        return;
    printf("FAIL: %s copies %dx%d of a %dx%d console\n", phase,
           scale_data.src_copy_width, scale_data.src_copy_height,
           console_px_w(), console_px_h());
    failures++;
}

int main(int argc, char **argv) {
    int selftest = (argc > 1 && strcmp(argv[1], "--selftest") == 0);

    /* A. First window. 100x75 cells of an 8x8 font is 800x600 pixels. This
          one has always been right: the recalculation runs once, at startup. */
    open_root(100, 75, "fonts/8x8.png", false);
    show("A windowed 800x600");
    want_whole_console("A windowed");

    /* B. The Options-manager resize (src/Managers.cpp:2022): windowed to
          windowed, new console size, no Alt-Enter anywhere. 85x48 cells of a
          12x16 font is 1020x768 pixels. */
    TCOD_console_delete(NULL);
    open_root(85, 48, "fonts/12x16.png", false);
    show("B windowed 1020x768");
    want_whole_console("B windowed resize");

    /* C. The Alt-Enter toggle asks for the same console fullscreen. The flag
          is what decides whether libtcod measures against the window or
          against the console, so it must tell the truth. */
    TCOD_console_delete(NULL);
    open_root(85, 48, "fonts/12x16.png", true);
    show("C fullscreen 1020x768");
    if (!TCOD_console_is_fullscreen()) {
        printf("FAIL: C is_fullscreen() is false for a fullscreen window\n");
        failures++;
    }
    /* The console's shape almost never matches the screen's, so this is the
       assertion that the surplus becomes margin at the sides instead of rows
       taken off the top and the bottom. Unfixed, a 1020x768 console in a
       1920x1080 window copied rows 97..669 and lost the message log and the
       status line. */
    want_whole_console("C fullscreen");

    /* D. The shape the shipped default now asks for: the largest listed
          widescreen resolution this display can take. On a 1280x800 screen
          the step-down loop in libtcodTerm::Reset (src/Wlibtcod.cpp:1522)
          settles on 1280x800, which with a 12x16 font is 106x50 cells, or
          1272x800 pixels. A console that nearly matches the screen should
          need almost no margin at all. */
    TCOD_console_delete(NULL);
    open_root(106, 50, "fonts/12x16.png", true);
    show("D fullscreen 1272x800");
    want_whole_console("D fullscreen wide");

    if (selftest) {
        /* Prove the harness can fail: assert something known to be false. */
        printf("--selftest: asserting a deliberately wrong console width\n");
        scale_data.src_copy_width = console_px_w() + 1;
        want_whole_console("selftest");
    }

    TCOD_console_delete(NULL);
    return failures ? 1 : 0;
}
