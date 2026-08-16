#!/bin/bash
# Verify that a packaged macOS folder is one a stranger can actually run.
#
# This checks the ARTIFACT, not the build tree, so it works on a folder that has
# been downloaded and unzipped on some other machine. Every check here failed at
# least once during development, and each one has a specific victim:
#
#   1. no ACCENT symbols    src/Art.cpp:2-7 is GPLv2 and says it must not be
#                           distributed. Shipping it is a licence violation, not
#                           a size problem. See inc-9df.5.
#   2. no absolute dylib    a /opt/homebrew (or /usr/local) reference means the
#                           game dies in dyld on any Mac but the build machine,
#                           before a line of our code runs. See inc-9df.6.
#   3. data files present   a folder that launches and then cannot find its own
#                           module is worse than one that does not launch.
#
# Usage: tools/check_package.sh <folder>    (exits 0 on pass, 1 on fail)
set -uo pipefail

PKG="${1:-}"
if [ -z "$PKG" ] || [ ! -d "$PKG" ]; then
    echo "usage: tools/check_package.sh <package folder>"
    exit 1
fi

BIN="$PKG/incursion"
FAIL=0
note_fail() { echo "FAIL: $1"; FAIL=1; }

[ -x "$BIN" ] || { echo "FAIL: no executable at $BIN"; exit 1; }

# --- 1. the GPLv2 resource compiler must not be in the shipped binary --------
# These three are every function src/Art.cpp defines. Do NOT grep for 'accent':
# no symbol carries that word, so it reports 0 whether or not the file is in.
ACCENT="$(nm "$BIN" 2>/dev/null | grep -c 'yyparse\|yyselect\|yymallocerror')"
if [ "$ACCENT" -ne 0 ]; then
    note_fail "binary carries $ACCENT ACCENT symbol(s); it was not built with COMPILER=no"
else
    echo "PASS: no ACCENT runtime in the shipped binary"
fi

# --- 2. every load path must be an OS library or beside the executable -------
# /usr/lib and /System/Library exist on every Mac. Anything else absolute is a
# build-machine path that will not resolve on someone else's disk.
STRAY="$(otool -L "$BIN" | tail -n +2 | awk '{print $1}' \
         | grep '^/' | grep -v '^/usr/lib/' | grep -v '^/System/Library/')"
if [ -n "$STRAY" ]; then
    note_fail "binary loads libraries from outside the OS:"
    echo "$STRAY" | sed 's/^/    /'
else
    echo "PASS: no build-machine library paths in the binary"
fi

# A bundled dylib is only useful if it is actually there. @executable_path is
# relative to the binary, so the file must sit in this same folder.
for ref in $(otool -L "$BIN" | tail -n +2 | awk '{print $1}' | grep '^@executable_path/'); do
    f="$PKG/${ref#@executable_path/}"
    if [ ! -f "$f" ]; then
        note_fail "binary wants $ref but $f is missing from the package"
    else
        echo "PASS: bundled $(basename "$f") is present"
    fi
done

# --- 3. the data the game reads at run time ---------------------------------
# lib/ and lang/ are deliberately NOT here. They are resource-compiler input,
# and nothing in src/ opens them at run time; the module already holds the data.
for f in mod/Incursion.Mod fonts/8x8.png fonts/12x16.png fonts/16x12.png fonts/16x16.png Options.Dat; do
    if [ ! -f "$PKG/$f" ]; then
        note_fail "missing data file: $f"
    fi
done
[ "$FAIL" -eq 0 ] && echo "PASS: module, fonts and options are present"

# The game writes beside itself (Wlibtcod.cpp:302 returns "." for OptionsSubDir).
# Both directories must exist and be writable or the first run loses data.
for d in save logs; do
    if [ ! -d "$PKG/$d" ]; then
        note_fail "missing writable directory: $d"
    elif [ ! -w "$PKG/$d" ]; then
        note_fail "not writable: $d"
    fi
done

# --- 4. the binary must be able to READ the module it ships with -------------
# Checks 1-3 all passed on a package that could not start a game. The shipped
# folder went out with a module the shipping binary rejects: the developer
# binary compiles the module with -DDEBUG, the shipping binary is built
# COMPILER=no and therefore WITHOUT it, and inc/Base.h gave class Registry a
# DEBUG-only member -- so sizeof(Registry), an input to SaveLayoutDigest()
# (src/AbiCheck.cpp), differed between the two halves of the same release. The
# game reported "File Version Mismatch" only after the title screen, so it
# looked like a runtime fault on the user's Mac. Reported as networkingguru#6,
# tracked as inc-tm4.
#
# Asking the binary is the point. A check that recomputed the digest from these
# sources would agree with itself and pass while the artifact stayed broken.
STAMP_BIN="$("$BIN" -formatid 2>/dev/null | tr -d '\r' | head -1)"
STAMP_MOD="$(dd if="$PKG/mod/Incursion.Mod" bs=1 skip=4 count=10 2>/dev/null | tr -d '\0')"

if [ -z "$STAMP_BIN" ]; then
    note_fail "binary does not answer -formatid; it predates this check, so the module cannot be verified"
elif [ -z "$STAMP_MOD" ]; then
    note_fail "could not read a format stamp from mod/Incursion.Mod"
elif [ "$STAMP_BIN" != "$STAMP_MOD" ]; then
    note_fail "the binary cannot load its own module: it demands $STAMP_BIN, the module carries $STAMP_MOD"
    echo "      Both halves of the release must be built from one layout. Check"
    echo "      that no member of a digested class sits inside #ifdef DEBUG."
else
    echo "PASS: binary and module agree on the save layout ($STAMP_BIN)"
fi

echo
if [ "$FAIL" -ne 0 ]; then
    echo "PACKAGE REJECTED: $PKG"
    exit 1
fi
echo "PACKAGE OK: $PKG"
exit 0
