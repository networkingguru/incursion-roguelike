#!/bin/bash
# Produce Incursion.app -- a macOS app bundle that Gatekeeper can actually
# approve, inside a disk image you drag to /Applications.
#
# WHY THIS EXISTS AND package_macos.sh IS NOT ENOUGH. That script ships a plain
# folder containing a bare executable. A bare Mach-O cannot be assessed by
# Gatekeeper at all -- `spctl -a -t exec` answers "the code is valid but does not
# seem to be an app" -- and a notarisation ticket can only be stapled to a disk
# image, an installer package or an app bundle, never to a loose executable. So
# the first release was correctly signed, correctly notarised, and still refused
# to launch on a machine that downloaded it, with "the app has been modified or
# damaged". See inc-g1y.
#
# An app bundle fixes that, but only if nothing writes inside it: the first write
# into a signed bundle produces the same refusal. tools/app_launcher.c is what
# keeps the writes out -- read its header for the layout and the ceiling.
#
# Usage:
#     tools/package_macos_app.sh            build, assemble, sign, verify
#     DMG=yes tools/package_macos_app.sh    also notarise a disk image
#
# Signing is automatic when a Developer ID Application certificate is present,
# and skipped with a note when it is not.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ARCH="$(uname -m)"
NAME="Incursion-macOS-$ARCH-app"
DIST="$ROOT/dist"
APP="$DIST/$NAME/Incursion.app"
STAGE="$DIST/$NAME"
NOTARY_PROFILE="${NOTARY_PROFILE:-incursion-notary}"

# HOW WE AUTHENTICATE TO THE NOTARY SERVICE, and why there are two ways.
#
# A keychain profile (notarytool store-credentials) only works for a process the
# keychain item's ACL permits. On 2026-08-17 a release could be notarised from
# Terminal.app and NOT from an agent shell on the same machine, same user, same
# second -- and macOS reports a denied ACL as "No Keychain password item found",
# so it looks like the credential is missing rather than unreadable. That cost an
# hour and made every release depend on a human sitting at a terminal.
#
# An App Store Connect API key is a .p8 file. Any process can read a file, so the
# pipeline stops caring which application is asking. That is the supported path
# and the default here whenever the key is configured.
#
# Configure it once, OUTSIDE the repository, in ~/.config/incursion/notary.env:
#     NOTARY_KEY=/Users/you/.private_keys/AuthKey_XXXXXXXXXX.p8
#     NOTARY_KEY_ID=XXXXXXXXXX
#     NOTARY_ISSUER=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# Create the key at App Store Connect > Users and Access > Integrations.
NOTARY_ENV="${NOTARY_ENV:-$HOME/.config/incursion/notary.env}"
# shellcheck disable=SC1090
[ -f "$NOTARY_ENV" ] && . "$NOTARY_ENV"

NOTARY_AUTH=()
if [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
    if [ ! -f "$NOTARY_KEY" ]; then
        echo "FAIL: NOTARY_KEY points at a file that is not there: $NOTARY_KEY"
        echo "      Fix $NOTARY_ENV, or unset NOTARY_KEY to fall back to the"
        echo "      keychain profile. Refusing rather than silently falling back,"
        echo "      because a silent fallback reintroduces the Terminal-only"
        echo "      dependency this exists to remove."
        exit 1
    fi
    NOTARY_AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
    NOTARY_HOW="API key $NOTARY_KEY_ID"
elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
    # An app-specific password read from the config file. Same credential the
    # keychain profile holds, but a file has no ACL, so any process can use it
    # and a release no longer has to be cut from Terminal.
    NOTARY_AUTH=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID"
                 --password "$NOTARY_PASSWORD")
    NOTARY_HOW="app-specific password for $NOTARY_APPLE_ID"
else
    NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
    NOTARY_HOW="keychain profile '$NOTARY_PROFILE' (Terminal only -- see above)"
fi

BUNDLE_ID="${BUNDLE_ID:-com.brianhill.incursion}"
VERSION="${VERSION:-1.0}"

# ------------------------------------------------------------------ build ----
echo "=== 1/7  developer binary ==="
./build_macos.sh >/dev/null

echo "=== 2/7  game data module ==="
# Rebuilt every time. A stale module from an older tree would sail through, and
# a mismatched one is exactly what broke the previous release (inc-tm4).
./incursion -compile main.irc >/dev/null
[ -f "$ROOT/mod/Incursion.Mod" ] || { echo "FAIL: -compile produced no module"; exit 1; }

echo "=== 3/7  shipping binary ==="
COMPILER=no OUT=incursion-ship ./build_macos.sh >/dev/null

# --------------------------------------------------------------- assemble ----
echo "=== 4/7  assembling $APP ==="
rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/mod" "$APP/Contents/Resources/fonts"

# NOT "incursion". macOS filesystems are case-insensitive by default, so
# Contents/MacOS/Incursion (the launcher, and CFBundleExecutable) and
# Contents/MacOS/incursion would be THE SAME FILE, and whichever was written
# second would silently replace the other. Caught by the SDL2 guard below on the
# first run of this script, which reported "the binary references no SDL2".
cp "$ROOT/incursion-ship"    "$APP/Contents/MacOS/incursion-game"
cp "$ROOT/mod/Incursion.Mod" "$APP/Contents/Resources/mod/"
cp "$ROOT"/fonts/*.png       "$APP/Contents/Resources/fonts/"
cp "$ROOT/Options.Dat"       "$APP/Contents/Resources/"
cp "$ROOT/LICENSE"           "$APP/Contents/Resources/"
cp "$ROOT/Incursion.txt"     "$APP/Contents/Resources/"
# Ours, beside upstream's. Incursion.txt is the original project's readme and
# still sends people to a Bitbucket tracker that is not where anything lives; it
# is left unedited so the fork does not rewrite upstream's words, and this file
# carries what a Mac player actually needs -- where saves live, and where to
# report a problem with THIS build.
cp "$ROOT/Incursion-macOS.txt" "$APP/Contents/Resources/"

# The launcher is the bundle's entry point. Built here rather than checked in as
# a binary, so it always matches its source.
clang -O2 -Wall -Wextra -o "$APP/Contents/MacOS/Incursion" "$ROOT/tools/app_launcher.c"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Incursion</string>
    <key>CFBundleDisplayName</key>       <string>Incursion</string>
    <key>CFBundleExecutable</key>        <string>Incursion</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>11.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.role-playing-games</string>
</dict>
</plist>
PLIST

# ------------------------------------------------------------------- SDL2 ----
# Beside the game binary rather than in Contents/Frameworks, because the game's
# load command already says @executable_path and both end up in the same
# directory. Fewer moving parts than rewriting it twice.
SDL_REF="$(otool -L "$APP/Contents/MacOS/incursion-game" | awk '/libSDL2/ {print $1}' | head -1)"
[ -n "$SDL_REF" ] || { echo "FAIL: the binary references no SDL2; the link line changed"; exit 1; }
case "$SDL_REF" in
    /*) ;;
    *)  echo "FAIL: SDL2 reference '$SDL_REF' is not an absolute path"; exit 1 ;;
esac

SDL_LIB="$(basename "$SDL_REF")"
cp "$SDL_REF" "$APP/Contents/MacOS/$SDL_LIB"
chmod u+w "$APP/Contents/MacOS/$SDL_LIB"
install_name_tool -id "@executable_path/$SDL_LIB" "$APP/Contents/MacOS/$SDL_LIB" 2>/dev/null
install_name_tool -change "$SDL_REF" "@executable_path/$SDL_LIB" \
                  "$APP/Contents/MacOS/incursion-game" 2>/dev/null
echo "bundled $SDL_LIB from $(dirname "$SDL_REF")"

# install_name_tool invalidates any signature the file carried, and Apple Silicon
# refuses a Mach-O whose signature is present but broken.
codesign --force --sign - "$APP/Contents/MacOS/$SDL_LIB"
codesign --force --sign - "$APP/Contents/MacOS/incursion-game"

# ------------------------------------------------------------------- sign ----
echo "=== 5/7  signing ==="
IDENTITY="$(security find-identity -v -p codesigning \
            | grep 'Developer ID Application' | head -1 \
            | sed 's/.*"\(.*\)"/\1/' || true)"

if [ -z "$IDENTITY" ]; then
    echo "SKIPPED: no 'Developer ID Application' certificate on this keychain."
    SIGNED=no
else
    # Inside out. The bundle is signed LAST, and signing it seals the whole
    # Contents tree -- which is why nothing may write in there afterwards.
    codesign --force --timestamp --options runtime --sign "$IDENTITY" \
             "$APP/Contents/MacOS/$SDL_LIB"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" \
             "$APP/Contents/MacOS/incursion-game"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" \
             "$APP/Contents/MacOS/Incursion"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
    codesign --verify --strict --deep --verbose=2 "$APP"
    echo "signed with: $IDENTITY"
    SIGNED=yes
fi

# -------------------------------------------------------- notarise the app ----
# THE APP GETS ITS OWN TICKET, not just the disk image. A ticket stapled only to
# the DMG covers the image; the moment a user drags Incursion.app out of it onto
# a machine that is offline, Gatekeeper has nothing local to consult and refuses.
# Stapling the bundle itself is what makes the copied app work anywhere.
#
# This must happen BEFORE check_app.sh, not after. The gate asks Gatekeeper for a
# verdict, and an unstapled bundle is answered "rejected, source=Unnotarized
# Developer ID" no matter how correctly it is signed -- which is exactly what the
# first run of this script reported.
echo "=== 6/8  notarising the app ==="
if [ "$SIGNED" = yes ]; then
    ZIP="$DIST/$NAME-notarise.zip"
    rm -f "$ZIP"
    # ditto, not zip: it preserves the bundle structure and extended attributes
    # that notarisation needs to see.
    /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
    echo "authenticating with: $NOTARY_HOW"
    if xcrun notarytool submit "$ZIP" "${NOTARY_AUTH[@]}" --wait; then
        xcrun stapler staple "$APP"
        echo "notarised and stapled: $APP"
    else
        echo "WARNING: notarisation failed. The bundle is signed but Gatekeeper"
        echo "  will refuse it on any machine that downloads it. check_app.sh"
        echo "  below will fail, and it is right to."
    fi
    rm -f "$ZIP"
else
    echo "SKIPPED: not signed, so there is nothing to notarise."
fi

# ----------------------------------------------------------------- verify ----
echo "=== 7/8  verifying ==="
"$ROOT/tools/check_app.sh" "$APP"

# -------------------------------------------------------------------- dmg ----
echo "=== 8/8  disk image ==="
if [ "${DMG:-no}" = yes ]; then
    DMG_PATH="$DIST/$NAME.dmg"
    rm -f "$DMG_PATH"
    # An /Applications alias, so the image looks like every other Mac download
    # and the drag target is right there.
    ln -sfn /Applications "$STAGE/Applications" 2>/dev/null || true
    hdiutil create -quiet -volname "Incursion" -srcfolder "$STAGE" \
                   -ov -format UDZO "$DMG_PATH"

    if [ "$SIGNED" = yes ]; then
        codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
        if xcrun notarytool submit "$DMG_PATH" "${NOTARY_AUTH[@]}" --wait; then
            xcrun stapler staple "$DMG_PATH"
            echo "notarised and stapled: $DMG_PATH"
        else
            echo "WARNING: notarisation failed; a downloader will still be blocked."
        fi
    else
        echo "unsigned disk image: $DMG_PATH"
    fi
    echo
    echo "Image: $DMG_PATH"
fi

echo
echo "App:   $APP"
echo "Size:  $(du -sh "$APP" | awk '{print $1}')"
