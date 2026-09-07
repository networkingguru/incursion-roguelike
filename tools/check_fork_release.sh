#!/bin/sh
# Does the release number the game prints match the release actually cut?
#
# FORK_RELEASE (inc/Defines.h) is compiled into the binary and drawn on the
# title page (src/Term.cpp), printed by src/TextTerm.cpp, and stamped on every
# map-entry line in the log (src/Main.cpp). Nothing else derives from it, so it
# only changes when somebody remembers to change it -- and on 2026-09-07 nobody
# did: release 4 was built, signed and notarised with a title page that still
# read "iNCURSION release 3". Brian saw it on the title screen; no check did.
#
# The oracle is the git tag, because that is what names a release here:
# release-1, release-2, release-3. The highest one must equal FORK_RELEASE.
#
# ONLY A BARE release-N COUNTS. A build-point tag such as release-4-windows
# names where a platform's artifact was cut, not a release of the game, and the
# title screen must not be asked to print it. The first pattern here was
# 'release-[0-9]*', whose trailing * swallowed the suffix: release-4-windows
# became "4-windows", which sort -n ranks alongside 4 and tail -1 then picked,
# so a correct tree failed and told the reader to set FORK_RELEASE to
# "4-windows".
#
# A clone with no release tag cannot answer the question, so it says so and
# passes. Failing there would make a fresh clone red for a reason that has
# nothing to do with the tree.
#
# The other half of this guard is in tools/package_macos_app.sh, which refuses
# to build a bundle whose VERSION disagrees with FORK_RELEASE. That one stops a
# wrong artifact; this one reports the drift before anybody packages anything.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

FORK_RELEASE="$(sed -n 's/^#define FORK_RELEASE  *"\(.*\)"/\1/p' inc/Defines.h)"
if [ -z "$FORK_RELEASE" ]; then
    echo "FAIL: cannot read FORK_RELEASE from inc/Defines.h; the #define moved"
    exit 1
fi

TAG="$(git tag --list 'release-*' | grep -E '^release-[0-9]+$' |
       sed 's/^release-//' | sort -n | tail -1)"
if [ -z "$TAG" ]; then
    echo "SKIP: no release-N tag in this clone, so there is nothing to compare"
    echo "  the game's release $FORK_RELEASE against."
    exit 0
fi

if [ "$TAG" != "$FORK_RELEASE" ]; then
    echo "FAIL: the newest tag is release-$TAG but the game prints release $FORK_RELEASE."
    echo "  The title screen would lie to a player. Set FORK_RELEASE to \"$TAG\""
    echo "  in inc/Defines.h, or cut the tag the tree actually claims."
    exit 1
fi

echo "PASS: the game prints release $FORK_RELEASE and the newest tag is release-$TAG"
exit 0
