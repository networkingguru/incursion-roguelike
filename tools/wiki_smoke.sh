#!/bin/bash
# Reproduction for inc-k2le phases 1-2; uses the existing headless build.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
./incursion-headless -wikihelp "$tmp"

# The prose chapters and the sidebar (phase 1).
for page in Home _Sidebar Introduction Character-Generation Commands Interface \
            Adventuring Combat Magic Overland OGL; do
    if [[ ! -s "$tmp/$page.md" ]]; then
        echo "wiki_smoke: missing or empty $page.md" >&2
        exit 1
    fi
done

# Page name -> file name, exactly as WriteWikiPage / WikiFileName build it:
# spaces become '-', characters outside [A-Za-z0-9()'+,._-] are dropped.
wiki_file() {
    printf '%s' "$1" | sed -E "s/ /-/g; s/[^A-Za-z0-9()'+,._-]//g"
}

# The twelve index pages (spec section 1), each must exist and link at least
# one entry page whose file exists.
indexes=(Races Classes Gods Domains Feats Skills "Arcane Spells" \
         "Divine Spells" "Druid Spells" "Other Spells" Powers "Spell Index")
for index in "${indexes[@]}"; do
    file=$(wiki_file "$index").md
    if [[ ! -s "$tmp/$file" ]]; then
        echo "wiki_smoke: missing or empty index $file" >&2
        exit 1
    fi
    found=0
    while IFS= read -r target; do
        [[ -n "$target" ]] || continue
        if [[ -s "$tmp/$(wiki_file "$target").md" ]]; then
            found=1
            break
        fi
    done < <(grep -oE '\[\[[^]]+\]\]' "$tmp/$file" | sed -E 's/^\[\[//; s/\]\]$//')
    if [[ $found -eq 0 ]]; then
        echo "wiki_smoke: index $file links no existing entry page" >&2
        exit 1
    fi
done

# No page may contain a raw colour tag.
if grep -rlE '<[0-9]+>' "$tmp" > /dev/null; then
    echo "wiki_smoke: raw colour tag in $(grep -rlE '<[0-9]+>' "$tmp" | head -1)" >&2
    exit 1
fi

echo "wiki_smoke: PASS (11 prose pages, 12 index pages, no raw tags)"
