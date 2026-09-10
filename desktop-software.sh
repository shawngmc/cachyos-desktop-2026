#!/usr/bin/env bash
#
# desktop-software.sh
#
# Desktop app installer for Shawn's desktop on CachyOS. Covers: Discord,
# Claude desktop, Google Chrome, Firefox, VSCode, Tabby (terminal),
# Bitwarden desktop, Warehouse + Flatseal (Flatpak manager and
# permissions editor), Tor Browser, and Ungoogled Chromium.
#
# Review before running. Designed to be run section-by-section rather
# than blindly executed — comment out anything you don't want.
#
# Usage: chmod +x desktop-software.sh && ./desktop-software.sh

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

# ---------------------------------------------------------------------
# 1. Firefox
# ---------------------------------------------------------------------

sudo pacman -S --needed --noconfirm firefox

# ---------------------------------------------------------------------
# 2. Discord
# ---------------------------------------------------------------------

sudo pacman -S --needed --noconfirm discord

# ---------------------------------------------------------------------
# 3. Google Chrome
# ---------------------------------------------------------------------
#
# Not in the official repos — Google only ships it as a .rpm/.deb, so
# this pulls the AUR packaging that wraps Google's own installer.

$AUR_HELPER -S --needed --noconfirm google-chrome

# ---------------------------------------------------------------------
# 4. Visual Studio Code
# ---------------------------------------------------------------------
#
# visual-studio-code-bin is Microsoft's official build (MS branding,
# telemetry, and marketplace access). The official repos also carry
# `code`, the telemetry-free OSS build without marketplace access —
# swap to that if you'd rather avoid the MS build.

$AUR_HELPER -S --needed --noconfirm visual-studio-code-bin

# ---------------------------------------------------------------------
# 5. Tabby (terminal)
# ---------------------------------------------------------------------

$AUR_HELPER -S --needed --noconfirm tabby-bin

# ---------------------------------------------------------------------
# 6. Claude desktop
# ---------------------------------------------------------------------
#
# claude-desktop repackages Anthropic's official Linux .deb (announced
# 2026-07). The old claude-desktop-bin (a community repack of the Mac/
# Windows Electron app) has been deleted from the AUR in favor of this.
# Review before trusting it: https://aur.archlinux.org/packages/claude-desktop

$AUR_HELPER -S --needed --noconfirm claude-desktop

# ---------------------------------------------------------------------
# 7. Bitwarden desktop
# ---------------------------------------------------------------------
#
# GUI vault app — complements the bitwarden-cli from packages.yaml.

$AUR_HELPER -S --needed --noconfirm bitwarden

# ---------------------------------------------------------------------
# 8. Warehouse (Flatpak manager)
# ---------------------------------------------------------------------
#
# Distributed as a Flatpak itself. gaming-software.sh also installs
# flatpak (for RomMix's emulator downloads) — this is safe to run
# whether or not that script has run yet.

sudo pacman -S --needed --noconfirm flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y --noninteractive flathub io.github.flattool.Warehouse

# ---------------------------------------------------------------------
# 8a. Flatseal (Flatpak permissions manager)
# ---------------------------------------------------------------------
#
# Also a Flatpak itself — pairs with Warehouse above.

flatpak install -y --noninteractive flathub com.github.tchx84.Flatseal

# ---------------------------------------------------------------------
# 9. Tor Browser
# ---------------------------------------------------------------------
#
# torbrowser-launcher is the standard Arch packaging — it downloads,
# verifies (GPG signature), and keeps the actual Tor Browser bundle
# updated, rather than shipping the binary directly.

$AUR_HELPER -S --needed --noconfirm torbrowser-launcher

# ---------------------------------------------------------------------
# 10. Ungoogled Chromium
# ---------------------------------------------------------------------

$AUR_HELPER -S --needed --noconfirm ungoogled-chromium-bin

echo ""
echo "=== Done. ==="
