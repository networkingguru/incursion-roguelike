#!/usr/bin/env bash
# Install Incursion as a Steam shortcut with its controller layout, on SteamOS
# or any Linux box running Steam. Touches only $HOME — no root, no /usr.
#
# Run it from the folder you extracted:   ./install-steamos.sh
set -uo pipefail

GAME_NAME="Incursion: Halls of the Goblin King"
LAYOUT_SRC="incursion-steam-input.vdf"
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# The layout binds no back buttons and no trackpads, so the same file is valid
# for every device below. Deck-only or Ally-only hardware is never referenced.
CONTROLLER_TYPES=(
  neptune rog_ally legion_go legion_go_s zotac_zone steamos_handheld
  xbox360 xboxone xboxelite ps4 ps5 ps5_edge switch_pro switch2_pro
  generic 8bitdo hori_steam steamframe_pair
)

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\n  \033[31m✗ %s\033[0m\n\n' "$*" >&2; exit 1; }

printf '\n  Incursion — SteamOS installer\n\n'

# ---------------------------------------------------------------- sanity
[[ -x "$HERE/incursion" ]] || die "No 'incursion' binary beside this script. Run it from the extracted folder."
[[ -f "$HERE/$LAYOUT_SRC" ]] || die "Missing $LAYOUT_SRC beside this script."
command -v python3 >/dev/null || die "python3 is required (it ships with SteamOS)."

# ---------------------------------------------------------------- steam root
STEAM_ROOT=""
for c in "$HOME/.steam/steam" "$HOME/.local/share/Steam" "$HOME/.steam/root" \
         "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
  [[ -d "$c/userdata" ]] && { STEAM_ROOT="$c"; break; }
done
[[ -n "$STEAM_ROOT" ]] || die "Could not find a Steam installation with a userdata/ folder."
ok "Steam: $STEAM_ROOT"

mapfile -t USERS < <(find "$STEAM_ROOT/userdata" -maxdepth 1 -mindepth 1 -type d \
                     -not -name 'anonymous' -not -name '0' -printf '%f\n' 2>/dev/null | sort)
[[ ${#USERS[@]} -gt 0 ]] || die "No Steam user profiles under $STEAM_ROOT/userdata. Sign in to Steam once first."
ok "Steam account(s): ${USERS[*]}"

# ---------------------------------------------------------------- launcher
LAUNCHER="$HERE/launch-incursion.sh"
cat > "$LAUNCHER" <<'LEOF'
#!/bin/bash
# Keeps the working directory correct so mod/, fonts/ and save/ resolve.
cd "$(dirname "$(readlink -f "$0")")" || exit 1
exec ./incursion "$@"
LEOF
chmod +x "$LAUNCHER"
ok "Launcher: $LAUNCHER"

# macOS AppleDouble files break the module loader if the tarball carried any.
if find "$HERE" -name '._*' -print -quit | grep -q .; then
  find "$HERE" -name '._*' -delete
  ok "Removed stray ._* files (they break module loading)"
fi

# ---------------------------------------------------------------- controller layout
TEMPLATES="$STEAM_ROOT/controller_base/templates"
mkdir -p "$TEMPLATES" || die "Cannot write $TEMPLATES"

# Steam matches a template to a device by its controller_type field, so write
# one per type rather than hoping a single file is accepted for all of them.
n=0
for t in "${CONTROLLER_TYPES[@]}"; do
  dst="$TEMPLATES/controller_${t}_incursion.vdf"
  tmp="$(mktemp)"
  sed "s/\"controller_type\"\([[:space:]]*\)\"[a-z0-9_]*\"/\"controller_type\"\1\"controller_${t}\"/" \
      "$HERE/$LAYOUT_SRC" > "$tmp" || die "Failed generating layout for $t"
  # Only back up when the content actually changes, or repeated runs bury
  # Steam's template folder in identical .bak files.
  if [[ -f "$dst" ]] && ! cmp -s "$dst" "$tmp"; then
    cp -a "$dst" "$dst.bak-$(date +%Y%m%d-%H%M%S)"
  fi
  mv "$tmp" "$dst" || die "Failed writing $dst"
  n=$((n+1))
done
ok "Installed layout for $n controller types"

# Configset key is the app name, lowercased with punctuation stripped.
CFG_KEY="$(printf '%s' "$GAME_NAME" | tr '[:upper:]' '[:lower:]' \
           | tr -cd '[:alnum:] ' | tr -s ' ')"

for uid in "${USERS[@]}"; do
  CFGDIR="$STEAM_ROOT/steamapps/common/Steam Controller Configs/$uid/config"
  mkdir -p "$CFGDIR" || { warn "Cannot write configs for user $uid, skipping"; continue; }
  for t in "${CONTROLLER_TYPES[@]}"; do
    f="$CFGDIR/configset_controller_${t}.vdf"
    if [[ -f "$f" ]] && grep -qF "\"$CFG_KEY\"" "$f"; then
      python3 - "$f" "$CFG_KEY" "controller_${t}_incursion.vdf" <<'PYEOF'
import re, sys
path, key, tpl = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding='utf-8-sig').read()
s = re.sub(r'("%s"\s*\{\s*"template"\s*)"[^"]*"' % re.escape(key), r'\1"%s"' % tpl, s)
open(path, 'w', encoding='utf-8-sig').write(s)
PYEOF
    elif [[ -f "$f" ]]; then
      cp -a "$f" "$f.bak-$(date +%Y%m%d-%H%M%S)"
      python3 - "$f" "$CFG_KEY" "controller_${t}_incursion.vdf" <<'PYEOF'
import sys
path, key, tpl = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding='utf-8-sig').read().rstrip()
entry = '\t"%s"\n\t{\n\t\t"template"\t\t"%s"\n\t}\n' % (key, tpl)
i = s.rfind('}')
open(path, 'w', encoding='utf-8-sig').write(s[:i] + entry + '}\n')
PYEOF
    else
      printf '"controller_config"\n{\n\t"%s"\n\t{\n\t\t"template"\t\t"%s"\n\t}\n}\n' \
             "$CFG_KEY" "controller_${t}_incursion.vdf" > "$f"
    fi
  done
  ok "Selected the layout for user $uid"
done

# ---------------------------------------------------------------- shortcut
for uid in "${USERS[@]}"; do
  SC="$STEAM_ROOT/userdata/$uid/config/shortcuts.vdf"
  mkdir -p "$(dirname "$SC")"
  [[ -f "$SC" ]] && cp -a "$SC" "$SC.bak-$(date +%Y%m%d-%H%M%S)"
  out="$(python3 "$HERE/tools/steam_shortcut.py" upsert "$SC" "$GAME_NAME" "$LAUNCHER" "$HERE" 2>&1)" \
    && ok "Shortcut ${out%% *} for user $uid" \
    || warn "Could not write shortcut for user $uid: $out"
done

# ---------------------------------------------------------------- finish
printf '\n'
if pgrep -x steam >/dev/null 2>&1; then
  warn "Steam is running. RESTART STEAM to see the shortcut."
  say  "On SteamOS Game Mode:  systemctl --user restart steam-launcher.service"
  say  "(the screen goes black for ~20s; the session itself survives)"
else
  ok "Start Steam, and Incursion will be in your library."
fi
printf '\n  Then launch it from Steam — not from the desktop — or the controller\n'
printf '  layout will not be applied.\n\n'
