#!/usr/bin/env bash
#
# gaming-software.sh
#
# Gaming stack installer for Shawn's desktop on CachyOS. Covers: Steam,
# Battle.net (via Lutris) + World of Warcraft, WowUp for CurseForge addon
# management, Heroic Games Launcher (Epic/GOG/Amazon), RomMix as an
# emulation frontend backed by a RomM server, and perf/streaming tooling
# (ProtonUp-Qt, MangoHud + Goverlay, Sunshine).
#
# Review before running. Designed to be run section-by-section rather
# than blindly executed — comment out anything you don't want.
#
# Usage: chmod +x gaming-software.sh && ./gaming-software.sh

set -euo pipefail

# ---------------------------------------------------------------------
# 0. Preflight
# ---------------------------------------------------------------------

if ! command -v yay >/dev/null 2>&1 && ! command -v paru >/dev/null 2>&1; then
  echo "No AUR helper (yay/paru) found. Install one first, e.g.:"
  echo "  git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si"
  exit 1
fi

AUR_HELPER="yay"
command -v paru >/dev/null 2>&1 && AUR_HELPER="paru"

echo "Using AUR helper: $AUR_HELPER"

if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
  echo "multilib repo is not enabled in /etc/pacman.conf — Steam needs it." >&2
  echo "Uncomment [multilib] (and the Include line under it), then:" >&2
  echo "  sudo pacman -Sy" >&2
  exit 1
fi

# ---------------------------------------------------------------------
# 1. Steam
# ---------------------------------------------------------------------

sudo pacman -S --needed --noconfirm steam

# ---------------------------------------------------------------------
# 2. Heroic Games Launcher (Epic / GOG / Amazon Games)
# ---------------------------------------------------------------------

$AUR_HELPER -S --needed --noconfirm heroic-games-launcher-bin

# ---------------------------------------------------------------------
# 3. Battle.net + World of Warcraft (via Lutris)
# ---------------------------------------------------------------------
#
# Blizzard doesn't ship a native Linux client. Lutris's community
# install script is the current standard way to run Battle.net on
# Linux — it sets up a known-good wine prefix/runner and drives the
# Battle.net installer. This step is interactive (Lutris's GUI opens,
# and Battle.net itself needs your login), so it can't be fully
# unattended.

sudo pacman -S --needed --noconfirm lutris

# If Lutris errors with a protobuf mismatch when talking to the
# Battle.net service integration, work around it with:
#   PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python lutris

lutris -i battlenet || true

cat <<'EOF'
>>> Lutris launched the Battle.net install script.
    1. Let the script finish setting up the wine prefix and installing
       Battle.net, then log in with your Blizzard account.
    2. From inside Battle.net, install World of Warcraft as normal.
    3. If the installer window didn't appear, open Lutris and search
       "Battle.net" in the install-script browser instead.
EOF

# ---------------------------------------------------------------------
# 4. WowUp — CurseForge addon management for WoW
# ---------------------------------------------------------------------
#
# The official CurseForge desktop app is Overwolf-based and has a rocky
# install/FUSE history on Arch. WowUp is a native Linux app that manages
# WoW addons from the same CurseForge catalog without needing wine —
# wowup-cf-bin bundles the CurseForge (Twitch) provider.

$AUR_HELPER -S --needed --noconfirm wowup-cf-bin

cat <<'EOF'
>>> WowUp installed. On first launch, point it at the WoW install
    inside your Battle.net wine prefix, e.g.:
      ~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft
    (exact path depends on where the Lutris installer put it — check
    the Battle.net game's wine prefix from Lutris if unsure).
EOF

# ---------------------------------------------------------------------
# 5. Emulation frontend — RomMix (built directly against a RomM backend)
# ---------------------------------------------------------------------
#
# RomMix is a Big Picture-style frontend purpose-built to browse,
# download, and launch games from a personal RomM server — unlike
# ES-DE/Pegasus, it talks to RomM natively instead of needing a
# separate sync script. It drives RetroArch/RetroDECK/Eden/shadPS4
# (installed via Flatpak/AppImage from within RomMix itself) or EmuDeck
# (installed separately) to actually run games.
#
# This assumes you already have a RomM server running somewhere on
# your network — this script only sets up the client side.

sudo pacman -S --needed --noconfirm fuse2 flatpak

ROMMIX_DIR="$HOME/.local/bin"
mkdir -p "$ROMMIX_DIR"

ROMMIX_URL="$(curl -fsSL https://api.github.com/repos/leclercb/rommix/releases/latest \
  | grep -oP '"browser_download_url":\s*"\K[^"]*RomMix-x86_64\.AppImage')"

if [[ -n "$ROMMIX_URL" ]]; then
  curl -fsSL "$ROMMIX_URL" -o "$ROMMIX_DIR/RomMix-x86_64.AppImage"
  chmod +x "$ROMMIX_DIR/RomMix-x86_64.AppImage"
  echo "RomMix installed to $ROMMIX_DIR/RomMix-x86_64.AppImage"
else
  echo "Could not resolve latest RomMix AppImage URL — grab it manually from" >&2
  echo "https://github.com/leclercb/rommix/releases" >&2
fi

cat <<'EOF'
>>> RomMix installed.
    1. Run ~/.local/bin/RomMix-x86_64.AppImage. On first launch, enter
       your RomM server address and authenticate (device pairing, an
       rmm_... API token from RomM's Administration > Client tokens,
       or username/password).
    2. On the Emulators screen, install at least one of
       RetroArch/RetroDECK/Eden/shadPS4 (Flatpak/AppImage, one click);
       RomMix auto-adds the Flathub remote if needed.
    3. On the Platforms screen, assign an emulator to each system —
       the first installed emulator becomes the default for anything
       unassigned.
    4. To add it as a Steam entry instead: grab rommix-steam.sh from
       the same release, put it next to the AppImage, and add that
       script (not the AppImage) as a non-Steam game — Steam's
       sandboxing prevents the AppImage mounting itself directly.
EOF

# ---------------------------------------------------------------------
# 6. Performance / streaming tooling
# ---------------------------------------------------------------------
#
# ProtonUp-Qt manages GE-Proton/Wine-GE builds for Steam and Lutris.
# MangoHud is the in-game perf overlay (needs the 32-bit lib too, since
# multilib is already enabled per the preflight check above); Goverlay
# is a GUI for configuring MangoHud/vkBasalt instead of hand-editing
# config files. Sunshine is a self-hosted game-stream host (pairs with
# a Moonlight client on another device).

sudo pacman -S --needed --noconfirm mangohud lib32-mangohud

$AUR_HELPER -S --needed --noconfirm protonup-qt goverlay sunshine

cat <<'EOF'
>>> Sunshine installed. It needs a one-time setup before it'll accept
    Moonlight connections — enabling the sunshine service (user or
    system, depending on the AUR package's postinstall) and granting
    capture capabilities. Check the AUR package's post-install notes
    (or pacman -Qi sunshine) and the upstream setup guide:
      https://docs.lizardbyte.dev/projects/sunshine/latest/about/setup.html
    Once running, visit https://localhost:47990 to set a web UI
    password and pair your Moonlight client(s).
EOF

echo ""
echo "=== Done. ==="
