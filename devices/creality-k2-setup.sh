#!/usr/bin/env bash
# Set up the Creality K2 on CachyOS / Arch.
#
# Installs the latest Creality Print AppImage from Creality's GitHub releases
# and integrates it with Gear Lever (from desktop-software.sh), replacing any
# copy Gear Lever already has. The K2 talks to Creality Print over the LAN, so
# there's no udev rule to add. Releases often carry several AppImage builds
# (e.g. V7.3.0.6149 and .6157); this picks the highest-numbered plain Release
# one, skipping the Beta and distro-specific (ubuntu2404, flatpak-wayland)
# variants. Re-run to update.
#
# Usage: ./creality-k2-setup.sh
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not root." >&2
    exit 1
fi

GEARLEVER="it.mijorus.gearlever"
# under $HOME rather than /tmp, so the Gear Lever flatpak can read it
DOWNLOAD_DIR="$HOME/.cache/creality-print"

gearlever() { flatpak run "$GEARLEVER" "$@"; }

# Paths of integrated AppImages whose name (ignoring case/spaces) starts with $1
gearlever_paths() {
    gearlever --list-installed --json 2>/dev/null | python3 -c '
import json, sys
for app in json.load(sys.stdin)["installed"]:
    if app["name"].lower().replace(" ", "").startswith(sys.argv[1]):
        print(app["path"])' "$1"
}

if ! flatpak info "$GEARLEVER" &>/dev/null; then
    echo "Gear Lever isn't installed; run desktop-software.sh first." >&2
    exit 1
fi

echo "==> Installing fuse2 (AppImage runtime)"
sudo pacman -S --needed --noconfirm fuse2

echo "==> Finding the latest Creality Print AppImage"
URL=$(curl -fsSL https://api.github.com/repos/CrealityOfficial/CrealityPrint/releases/latest \
    | grep -oP '"browser_download_url":\s*"\K[^"]*/CrealityPrint-V[0-9.]+-x86_64-Release\.AppImage' \
    | sort -V | tail -n 1 || true)
if [[ -z "$URL" ]]; then
    echo "Could not resolve the latest AppImage; grab it manually from" >&2
    echo "https://github.com/CrealityOfficial/CrealityPrint/releases" >&2
    exit 1
fi
FILE="$DOWNLOAD_DIR/${URL##*/}"

echo "==> Downloading ${URL##*/}"
mkdir -p "$DOWNLOAD_DIR"
curl -fL --progress-bar "$URL" -o "$FILE.part"
mv "$FILE.part" "$FILE"
chmod +x "$FILE"

# Gear Lever's non-interactive --integrate never overwrites; an existing copy
# would leave a second, version-suffixed install. Remove it first.
while IFS= read -r old; do
    echo "==> Removing previous install $old"
    gearlever --remove "$old" --delete -y
done < <(gearlever_paths crealityprint)

echo "==> Integrating with Gear Lever"
gearlever --integrate "$FILE" -y
rm -f "$FILE"

echo
echo "Launch Creality Print and add the K2; if LAN discovery doesn't find it,"
echo "add it by the IP address shown on the printer's network settings screen."
