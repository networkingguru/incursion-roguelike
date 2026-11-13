#!/usr/bin/env bash
# gate: live
#
# Does a fixture build leave the reincarnation gallery alone, and does the
# character it saves carry GallerySlot -1?
#
# WHAT IS BEING PROVED. A character made by the File creation source is not a
# gallery character (bead inc-10v7f, spec section 5 step 2 and A12): the File
# source's Finish sets GallerySlot to -1 and writes no gallery.dat entry, and
# Player::TouchGallery (which Game::SaveGame calls) returns at its
# `if (GallerySlot < 0) return;` before it opens gallery.dat. Three cases, one
# build each:
#   1. no gallery.dat in the sandbox: the build creates none;
#   2. a gallery.dat holding one real entry, its modification time set to 2001:
#      its bytes AND its modification time are unchanged after the build (a
#      TouchGallery without the early return opens the file for writing, which
#      moves the time, or crashes on the negative slot);
#   3. the saved character's canonical dump says `GallerySlot: -1`.
#
# THE RED. Remove the two lines `if (GallerySlot < 0) return;` from
# Player::TouchGallery (src/Create.cpp), build to another binary (OUT=...
# ./build_macos.sh) and run this script with INCURSION_BIN=<that binary>: case
# 2 goes red. The run that proved it is logs/phase7/gallery-red.txt.
#
# fact: the character -- a .char recorded now by tools/headless.sh from tools/keys/chargen-default-save.keys at seed 1 under tools/fixtures/options-2026-08-22.dat; the check reads no value of it but GallerySlot, which the File source fixes at -1 (inc-10v7f)
# fact: the gallery entry -- the gallery.dat that same recording run wrote; the check compares it with itself, byte for byte and by time, never with a value
# fact: the sandbox -- a run directory the check makes (INCURSION_BUILD_RUN_DIR), so no real save/ is touched
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_build_gallery.sh
# Exit: 0 pass; 1 fail; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
O22=tools/fixtures/options-2026-08-22.dat

W="$(mktemp -d "$ROOT/logs/gallery-check.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT

# A real character recorded by a normal run, and the gallery entry that run wrote.
INCURSION_RECORD_CHAR="$W/chr.char" INCURSION_OPTIONS="$O22" INCURSION_BIN="$BIN" \
    INCURSION_RUN_DIR="$W/walk" tools/headless.sh tools/keys/chargen-default-save.keys 1 \
    > "$W/walk.log" 2>&1 < /dev/null
[ -f "$W/chr.char" ] && [ -f "$W/walk/save/gallery.dat" ] || { echo "INCONCLUSIVE: the recording run left no .char or no gallery.dat"; exit 2; }

fail=0
build() {   # <sandbox dir> <out dir>
    INCURSION_BIN="$BIN" INCURSION_BUILD_RUN_DIR="$1" tools/build_fixture.sh "$W/chr.char" "$2" > "$2.log" 2>&1
}

# 1. No gallery in the sandbox: none is made.
mkdir -p "$W/run1/save"
if ! build "$W/run1" "$W/out1"; then
    echo "FAIL case 1: the build did not finish: $(grep -m1 'BUILD FAILED' "$W/out1.log" || tail -1 "$W/out1.log")"; exit 1
fi
if [ -e "$W/run1/save/gallery.dat" ]; then
    echo "FAIL case 1: the build created save/gallery.dat"; fail=1
else
    echo "ok   case 1: no gallery.dat was created"
fi

# 2. A gallery with one entry: untouched, bytes and time.
mkdir -p "$W/run2/save"
cp "$W/walk/save/gallery.dat" "$W/run2/save/gallery.dat"
touch -t 200101010000 "$W/run2/save/gallery.dat"
before_sum="$(cksum < "$W/run2/save/gallery.dat")"
before_time="$(stat -f %m "$W/run2/save/gallery.dat" 2>/dev/null || stat -c %Y "$W/run2/save/gallery.dat")"
if ! build "$W/run2" "$W/out2"; then
    echo "FAIL case 2: the build did not finish: $(grep -m1 'BUILD FAILED' "$W/out2.log" || tail -1 "$W/out2.log")"; fail=1
else
    after_sum="$(cksum < "$W/run2/save/gallery.dat")"
    after_time="$(stat -f %m "$W/run2/save/gallery.dat" 2>/dev/null || stat -c %Y "$W/run2/save/gallery.dat")"
    if [ "$before_sum" = "$after_sum" ] && [ "$before_time" = "$after_time" ]; then
        echo "ok   case 2: gallery.dat is unchanged (bytes and time)"
    else
        echo "FAIL case 2: gallery.dat changed (sum $before_sum -> $after_sum, time $before_time -> $after_time)"; fail=1
    fi
fi

# 3. The saved character says GallerySlot -1.
if [ -f "$W/out1/chr.sav" ]; then
    INCURSION_OPTIONS="$O22" INCURSION_BIN="$BIN" tools/char_dump.sh "$W/out1/chr.sav" "$W/chr.canon" > /dev/null 2>&1
    if grep -q 'GallerySlot: -1 ' "$W/chr.canon"; then
        echo "ok   case 3: the saved character has GallerySlot: -1"
    else
        echo "FAIL case 3: $(grep -m1 'GallerySlot' "$W/chr.canon" || echo 'no GallerySlot line in the dump')"; fail=1
    fi
else
    echo "FAIL case 3: no saved character"; fail=1
fi

[ $fail -eq 0 ] && { echo "PASS: a File build leaves the gallery alone and saves GallerySlot -1"; exit 0; }
exit 1
