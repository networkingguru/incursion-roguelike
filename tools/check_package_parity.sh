#!/bin/bash
# gate: cheap
# Every packager must ship every directory the game reads at run time.
#
# WHY THIS EXISTS. graphics/logo.png landed on 2026-09-04 and only
# tools/package_linux.sh was taught to copy it. Release 4 therefore shipped a
# macOS build whose title screen fell back to the ASCII wordmark while Linux,
# the Deck and Windows showed the real logo, and no check failed: the fallback
# is silent by design (src/Wlibtcod.cpp:1571-1577 loads the PNG if it is there
# and simply does not if it is not). inc-ntjr.
#
# tools/check_package.sh inspects one BUILT folder, so it can only speak for the
# package in front of it and only after a build. This script reads the packager
# SCRIPTS, so it answers the question that actually bit -- "does every platform
# ship the same data?" -- with no build at all, and it answers it for platforms
# this machine cannot build.
#
# Usage: tools/check_package_parity.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# Directories the shipped game opens at run time. lib/ and lang/ are absent on
# purpose: they are resource-compiler input and nothing in src/ opens them.
RUNTIME_DIRS="mod fonts graphics"

# Every script that assembles a shippable package. A new one MUST be added here;
# the unknown-packager check below is what forces that.
PACKAGERS="tools/package_macos.sh tools/package_macos_app.sh tools/package_linux.sh"

FAIL=0
note_fail() { echo "FAIL: $1"; FAIL=1; }

for pkgr in $PACKAGERS; do
    if [ ! -f "$pkgr" ]; then
        note_fail "$pkgr is listed here but does not exist"
        continue
    fi
    for d in $RUNTIME_DIRS; do
        # Match the DESTINATION, not the source: package_linux.sh copies the module
        # out of its Docker staging dir, so a $ROOT-only pattern misses it.
        if grep -qE "^[[:space:]]*cp .*/$d/\"" "$pkgr"; then
            echo "PASS: $(basename "$pkgr") ships $d/"
        else
            note_fail "$(basename "$pkgr") never copies $d/ -- that platform ships without it"
        fi
    done
done

# A packager nobody listed is the same defect wearing a different hat: it will
# drift from the others exactly as the macOS pair drifted from the Linux one.
for found in tools/package_*.sh; do
    case " $PACKAGERS " in
        *" $found "*) ;;
        *) note_fail "$found exists but is not in PACKAGERS; add it and re-run" ;;
    esac
done

# The built-package check must demand every runtime directory too, or a package
# can pass it while missing one.
for d in $RUNTIME_DIRS; do
    grep -qE "^ *(for f in |         )[^#]*$d/" tools/check_package.sh \
        || note_fail "tools/check_package.sh does not require anything from $d/"
done

if [ "$FAIL" -eq 0 ]; then
    echo
    echo "package parity: every packager ships every runtime directory"
    exit 0
fi
echo
echo "package parity: FAILED"
exit 1
