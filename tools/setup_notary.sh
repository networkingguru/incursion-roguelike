#!/bin/bash
# Store the notarisation credential where any process can read it, so a release
# does not have to be cut by hand from Terminal.
#
# WHY THIS EXISTS. notarytool store-credentials puts the credential in the
# keychain, and a keychain item only answers to processes on its ACL. On
# 2026-08-17 a release notarised fine from Terminal.app and failed from an agent
# shell on the same machine, same user, same second -- and macOS reports a denied
# ACL as "No Keychain password item found", so it reads as a missing credential
# rather than an unreadable one. A plain file with mode 600 has no ACL.
#
# Run this ONCE, in a real terminal, because it prompts:
#     tools/setup_notary.sh
#
# It validates against Apple BEFORE saving, so a bad password fails here rather
# than halfway through a release.
set -uo pipefail

DEST="$HOME/.config/incursion/notary.env"

# No identity is hardcoded here. This file is public, and a maintainer's Apple ID
# and Team ID have no business shipping in it. Both defaults come off the machine
# instead: the Apple ID from a credential file written by an earlier run, and the
# Team ID from the Developer ID certificate in the keychain, which is where the
# authoritative value lives in any case -- the Team ID must match that
# certificate, and reading it from there cannot disagree with it.
APPLE_ID_DEFAULT=""
if [ -r "$DEST" ]; then
    APPLE_ID_DEFAULT="$(sed -n 's/^NOTARY_APPLE_ID=//p' "$DEST" | head -1)"
fi
TEAM_ID_DEFAULT="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' | sed 's/.*(\(.*\))\"/\1/' | head -1)"

echo "Notarisation credential setup"
echo

if [ -n "$APPLE_ID_DEFAULT" ]; then
    read -r -p "Apple ID [$APPLE_ID_DEFAULT]: " APPLE_ID
    APPLE_ID="${APPLE_ID:-$APPLE_ID_DEFAULT}"
else
    read -r -p "Apple ID: " APPLE_ID
fi

if [ -n "$TEAM_ID_DEFAULT" ]; then
    read -r -p "Team ID [$TEAM_ID_DEFAULT]: " TEAM_ID
    TEAM_ID="${TEAM_ID:-$TEAM_ID_DEFAULT}"
else
    read -r -p "Team ID: " TEAM_ID
fi

# Neither has a fallback any more, so an empty answer must stop here rather than
# reach Apple as a blank field and come back as an unexplained 401.
if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ]; then
    echo "Apple ID and Team ID are both required. Nothing was saved."
    echo "The Team ID is the parenthesised code in:"
    echo "  security find-identity -v -p codesigning"
    exit 1
fi

echo
echo "App-specific password (NOT your Apple ID password)."
echo "Make one at appleid.apple.com > Sign-In and Security > App-Specific Passwords."
echo "It will not echo as you type or paste."
# -s so it never appears on screen, and never in shell history because it is read
# rather than passed as an argument.
read -r -s -p "Password: " PASSWORD
echo
echo

# Trim whitespace a paste can carry. A stray space or newline is indistinguishable
# from a wrong password in Apple's 401, which is a bad half-hour to spend.
PASSWORD="$(printf '%s' "$PASSWORD" | tr -d '[:space:]')"

if [ -z "$PASSWORD" ]; then
    echo "Nothing entered. Note that this script must be run in a REAL terminal:"
    echo "an agent shell has no tty, so the prompt reads end-of-file and you get"
    echo "an empty password and a confusing 401 from Apple."
    exit 1
fi

echo "Checking it against Apple before saving..."
if ! xcrun notarytool history \
        --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$PASSWORD" \
        >/dev/null 2>&1; then
    echo
    echo "REJECTED by Apple. Nothing was saved."
    echo "  * it must be an APP-SPECIFIC password, not your Apple ID password"
    echo "  * app-specific passwords are revoked when the Apple ID password changes"
    echo "  * check the Team ID: it must match the Developer ID certificate, which"
    echo "    on this machine is $(security find-identity -v -p codesigning 2>/dev/null \
            | grep 'Developer ID Application' | sed 's/.*(\(.*\))\"/\1/' | head -1)"
    exit 1
fi

mkdir -p "$(dirname "$DEST")"
# Create with restrictive permissions BEFORE the secret goes in, so it is never
# briefly world-readable.
umask 077
cat > "$DEST" <<EOF
# Written by tools/setup_notary.sh. Mode 600, outside the repository.
# Read by tools/package_macos_app.sh so notarisation works from any process.
NOTARY_APPLE_ID=$APPLE_ID
NOTARY_TEAM_ID=$TEAM_ID
NOTARY_PASSWORD=$PASSWORD
EOF
chmod 600 "$DEST"

echo
echo "Accepted by Apple and saved: $DEST"
echo "Permissions: $(stat -f '%Sp %Su' "$DEST")"
echo
echo "Releases can now be built from anywhere, including an agent session."
echo "Nothing else is needed from you."
