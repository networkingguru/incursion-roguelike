#!/bin/bash
# Produce a macOS folder that someone else can download and run.
#
# No user should ever build anything, not even once. This script turns the
# source tree into dist/Incursion-macOS-arm64/, a folder that contains the game,
# its data, and the one library macOS does not ship. See inc-9df.4.
#
# WHY IT BUILDS TWICE. The module is a memory image welded to the struct layout
# of the binary that wrote it (Registry.cpp:474 writes whole C++ objects as raw
# bytes), so only a matching binary can produce it -- and only a DEVELOPER binary
# has the resource compiler at all. But that compiler is the GPLv2 ACCENT runtime
# which src/Art.cpp:2-7 says must never be distributed. So:
#
#     1. build the developer binary          it alone can run -compile
#     2. run -compile to write the module    ~5 seconds
#     3. build the shipping binary           COMPILER=no, no ACCENT runtime
#     4. assemble, de-Homebrew, verify
#
# Step 3 must follow step 2: a shipping binary cannot compile the module, and
# build_macos.sh refuses rather than producing a package with no data.
#
# WHY A PLAIN FOLDER AND NOT A .app. The game writes Options.Dat, save/ and
# logs/ beside itself -- Wlibtcod.cpp:302 returns "." for OptionsSubDir(). An app
# bundle that writes inside itself breaks its own code signature, and a standard
# user cannot write into /Applications at all. Shipping a .app needs the game to
# put its writable state under ~/Library/Application Support first, which is a
# separate change. It finds its data by argv[0] (Wlibtcod.cpp:436-443), so the
# folder works wherever it is put.
#
# Usage:
#     tools/package_macos.sh            build, package, verify
#     DMG=yes tools/package_macos.sh    also produce a signed disk image
#
# Signing is automatic when a Developer ID Application certificate is on the
# keychain, and skipped with a note when it is not.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="Incursion-macOS-$(uname -m)"
DIST="$ROOT/dist"
PKG="$DIST/$NAME"

# The notarisation credential, stored once with:
#     xcrun notarytool store-credentials incursion-notary \
#         --apple-id <id> --team-id <team> --password <app-specific-password>
NOTARY_PROFILE="${NOTARY_PROFILE:-incursion-notary}"

# ------------------------------------------------------------------ build ----
echo "=== 1/6  developer binary ==="
./build_macos.sh >/dev/null

echo "=== 2/6  game data module ==="
# Rebuilt every time rather than reused. build_macos.sh only compiles a module
# when none exists, so a stale one from an older source tree would sail through
# unnoticed -- and nothing in the format would reject it at run time.
./incursion -compile main.irc >/dev/null
[ -f "$ROOT/mod/Incursion.Mod" ] || { echo "FAIL: -compile produced no module"; exit 1; }

echo "=== 3/6  shipping binary ==="
COMPILER=no OUT=incursion-ship ./build_macos.sh >/dev/null

# --------------------------------------------------------------- assemble ----
echo "=== 4/6  assembling $PKG ==="
rm -rf "$PKG"
mkdir -p "$PKG/mod" "$PKG/fonts" "$PKG/save" "$PKG/logs"

cp "$ROOT/incursion-ship"      "$PKG/incursion"
cp "$ROOT/mod/Incursion.Mod"   "$PKG/mod/"
cp "$ROOT"/fonts/*.png         "$PKG/fonts/"
cp "$ROOT/Options.Dat"         "$PKG/"
cp "$ROOT/LICENSE"             "$PKG/"
cp "$ROOT/Incursion.txt"       "$PKG/"

# lib/ and lang/ are NOT copied. They are resource-compiler input -- .irh, .irc,
# the ACCENT grammar -- and no code in src/ opens them at run time. The module
# already contains everything they describe.

# ------------------------------------------------------------------- SDL2 ----
# The one dependency that is not part of macOS. Read the reference out of the
# binary rather than assuming a Homebrew prefix, so this works on an Intel Mac
# (/usr/local) as well as an Apple Silicon one (/opt/homebrew).
SDL_REF="$(otool -L "$PKG/incursion" | awk '/libSDL2/ {print $1}' | head -1)"
if [ -z "$SDL_REF" ]; then
    echo "FAIL: the binary references no SDL2 at all; the link line changed"
    exit 1
fi
case "$SDL_REF" in
    /*) ;;
    *)  echo "FAIL: SDL2 reference '$SDL_REF' is not an absolute path."
        echo "      This script can only bundle a library it can locate on disk."
        exit 1 ;;
esac

SDL_LIB="$(basename "$SDL_REF")"
cp "$SDL_REF" "$PKG/$SDL_LIB"
chmod u+w "$PKG/$SDL_LIB"          # Homebrew installs dylibs read-only
install_name_tool -id "@executable_path/$SDL_LIB" "$PKG/$SDL_LIB" 2>/dev/null
install_name_tool -change "$SDL_REF" "@executable_path/$SDL_LIB" "$PKG/incursion" 2>/dev/null
echo "bundled $SDL_LIB from $(dirname "$SDL_REF")"

# install_name_tool rewrites load commands, which invalidates whatever signature
# the file already carried. That is not cosmetic: Apple Silicon refuses to run a
# Mach-O whose signature is present but broken, so a package left in this state
# dies in dyld. Re-sign both files ad-hoc immediately; a Developer ID signature,
# if there is one, goes on top of this a few lines further down.
codesign --force --sign - "$PKG/$SDL_LIB"
codesign --force --sign - "$PKG/incursion"

# ------------------------------------------------------------------- sign ----
echo "=== 5/6  signing ==="
# Only a Developer ID Application certificate can sign something distributed
# outside the App Store. An "Apple Development" certificate cannot: it is for
# local builds and registered devices.
# '|| true' because grep exits 1 when it matches nothing, and this script runs
# under 'set -e -o pipefail' -- without it, having no certificate would abort the
# whole run instead of taking the SKIPPED branch three lines below.
IDENTITY="$(security find-identity -v -p codesigning \
            | grep 'Developer ID Application' | head -1 \
            | sed 's/.*"\(.*\)"/\1/' || true)"

if [ -z "$IDENTITY" ]; then
    echo "SKIPPED: no 'Developer ID Application' certificate on this keychain."
    echo "  The package still runs, but macOS shows a Gatekeeper warning on a"
    echo "  machine that downloaded it. Create the certificate in Xcode:"
    echo "    Settings > Accounts > Manage Certificates > + > Developer ID Application"
    SIGNED=no
else
    # Inner to outer: the library first, then the executable that loads it.
    # --options runtime enables the hardened runtime, which notarisation requires.
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$PKG/$SDL_LIB"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$PKG/incursion"
    codesign --verify --strict --verbose=2 "$PKG/incursion"
    echo "signed with: $IDENTITY"
    SIGNED=yes
fi

# ----------------------------------------------------------------- verify ----
echo "=== 6/6  verifying ==="
"$ROOT/tools/check_package.sh" "$PKG"

# -------------------------------------------------------------------- dmg ----
# A disk image, not a zip, because a notarisation ticket can only be STAPLED to
# a disk image, an installer package or an app bundle -- never to a bare
# executable or a zip. Without a stapled ticket the first launch needs the user
# to be online for Gatekeeper to check Apple's service.
if [ "${DMG:-no}" = yes ]; then
    DMG_PATH="$DIST/$NAME.dmg"
    rm -f "$DMG_PATH"
    hdiutil create -quiet -volname "Incursion" -srcfolder "$PKG" \
                   -ov -format UDZO "$DMG_PATH"

    if [ "$SIGNED" = yes ]; then
        codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
        if xcrun notarytool submit "$DMG_PATH" \
               --keychain-profile "$NOTARY_PROFILE" --wait; then
            xcrun stapler staple "$DMG_PATH"
            echo "notarised and stapled: $DMG_PATH"
        else
            echo "WARNING: notarisation failed. The disk image is signed but a"
            echo "  downloader will still see a Gatekeeper warning. Check the"
            echo "  credential profile '$NOTARY_PROFILE'."
        fi
    else
        echo "unsigned disk image: $DMG_PATH"
    fi
fi

echo
echo "Package: $PKG"
[ "${DMG:-no}" = yes ] && echo "Image:   $DIST/$NAME.dmg"
echo "Size:    $(du -sh "$PKG" | awk '{print $1}')"
