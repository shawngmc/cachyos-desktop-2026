#!/usr/bin/env bash
#
# desktop-cachyos-setup.sh
#
# Driver / support-software installer for Shawn's desktop on CachyOS.
# Covers: MSI X870E Tomahawk WIFI, Ryzen 7 9800X3D, RX 7900 XT, Corsair
# HX1000i, Lian-Li GA II Lite 240, Samsung 990 Pro / WD SN850X, plus
# peripherals (DualSense, Canon MF642Cdw, ASUS BD-RW) and OS-wide input
# remapping via Input Remapper. Section 4 runs the per-device scripts in
# devices/ for the Keychron C3 Pro 8K, Razer Tartarus Pro, SteelSeries
# Aerox 9, Elgato Stream Deck Plus and Elgato 4K X.
#
# Review before running. Designed to be run section-by-section rather
# than blindly executed — comment out anything you don't want.
#
# Usage: chmod +x desktop-cachyos-setup.sh && ./desktop-cachyos-setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
# 1. Official repo packages (core system + monitoring + media)
# ---------------------------------------------------------------------

sudo pacman -S --needed --noconfirm \
  lm_sensors \
  smartmontools \
  nvme-cli \
  ddcutil \
  sane \
  sane-airscan \
  k3b \
  vlc \
  mpv \
  libbluray \
  liquidctl \
  corectrl \
  keyd \
  cups \
  cups-pdf \
  system-config-printer

# lm_sensors first-time config (safe to skip/re-run; answers mostly YES)
sudo sensors-detect --auto || true

# ---------------------------------------------------------------------
# 2. AUR packages — GPU / RGB / cooling
# ---------------------------------------------------------------------

$AUR_HELPER -S --needed --noconfirm \
  lact \
  openrgb \
  zenpower3-dkms

# LACT (AMD GPU monitoring/control) and liquidctl (Corsair HX1000i PSU
# monitoring) both need their services enabled:
sudo systemctl enable --now lactd.service
# corectrl needs the user added to its polkit-managed group in some
# configs; if the GUI prompts for a password every launch, see the
# ArchWiki CoreCtrl page for the polkit rule to avoid that.

# ---------------------------------------------------------------------
# 3. OS-wide input remapping — Input Remapper (Tartarus Pro, Aerox 9)
# ---------------------------------------------------------------------
#
# input-remapper runs as a systemd service (root-level daemon reading
# evdev) with a GTK front-end for building per-device presets. It works
# under both X11 and Wayland since it operates below the display server.
# The -bin AUR package has occasionally lagged behind current Python
# versions; -git tends to be the more reliable pick.

$AUR_HELPER -S --needed --noconfirm input-remapper-git

sudo systemctl enable --now input-remapper.service

cat <<'EOF'
>>> Input Remapper installed.
    Launch the GUI with: input-remapper-gtk
    The device scripts in section 4 create the "Tartarus Pro Proxy"
    and "Aerox9 Grid Proxy" devices.
    Steps for each device:
      1. Select the proxy device from the device dropdown (not the
         real Razer/SteelSeries device, which the proxy grabs).
      2. Create a new preset, map each physical button/key to the
         target key/macro.
      3. Enable "autoload" for that device so the preset applies on
         every login/reconnect.
    Note: keyd (installed in step 1) is an alternative for pure
    keyboard-level remaps if you ever want something lighter-weight
    than Input Remapper's GUI+daemon for the Tartarus specifically.
EOF

# ---------------------------------------------------------------------
# 4. Per-device setup (devices/)
# ---------------------------------------------------------------------
#
# Each script can also be rerun on its own; see its header for options.
# The proxy scripts restart input-remapper, so they run after section 3.
# A failure (e.g. device unplugged) is reported but doesn't stop this
# script. The Aerox/Tartarus scripts sudo themselves; the others run as
# you (AUR/cargo builds, the Keychron's session-owned hidraw nodes) and
# sudo only where needed.

for dev_script in keychron-c3-setup.sh tartarus-pro-setup.sh aerox-9-setup.sh \
                  elgato-stream-deck-setup.sh elgato-4k-x-setup.sh; do
  echo ">>> Running devices/$dev_script"
  "$SCRIPT_DIR/devices/$dev_script" \
    || echo ">>> devices/$dev_script failed (exit $?); rerun it once the device is connected."
done

# ---------------------------------------------------------------------
# 5. Sound BlasterX G6 (community CLI, pip install)
# ---------------------------------------------------------------------

cat <<'EOF'
>>> Sound BlasterX G6 works as a plain USB audio device with no
    package needed for sound. For LED/HID control, install the
    community CLI:
      pip install --user soundblaster-x-g6-cli
    (No official Creative Linux driver exists; BlasterX Acoustic
    Engine EQ/RGB features are Windows-only otherwise.)
EOF

# ---------------------------------------------------------------------
# 6. Canon imageCLASS MF642Cdw (official Linux driver, manual download)
# ---------------------------------------------------------------------

cat <<'EOF'
>>> Canon provides an official "UFR II/UFRII LT Printer Driver for
    Linux" package that explicitly lists the MF642Cdw as supported.
    Download from Canon's support site (search "imageCLASS MF642Cdw
    Linux driver"), then:
      tar xf linux-UFRII*.tar.gz
      cd linux-UFRII*/
      sudo ./install.sh
    It installs as a CUPS backend — after install, add the printer via
    system-config-printer (already installed in step 1) or the CUPS
    web UI (http://localhost:631). Since it's networked via Ethernet,
    use the IPP/socket queue with its LAN IP or add it via mDNS/Bonjour
    discovery if avahi is running.
EOF

echo ""
echo "=== Done. Reboot recommended before testing input-remapper. ==="
