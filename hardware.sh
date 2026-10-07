#!/usr/bin/env bash
#
# desktop-cachyos-setup.sh
#
# Driver / support-software installer for Shawn's desktop on CachyOS.
# Covers: MSI X870E Tomahawk WIFI, Ryzen 7 9800X3D, RX 7900 XT, Corsair
# HX1000i, Lian-Li GA II Lite 240, Samsung 990 Pro / WD SN850X, plus
# peripherals (Stream Deck Plus, Keychron C3 Pro 8K, Razer Tartarus Pro,
# DualSense, Elgato 4K X, Canon MF642Cdw, ASUS BD-RW) and OS-wide input
# remapping for the Tartarus Pro via Input Remapper. The SteelSeries
# Aerox 9 (rivalcfg settings, grid proxy, battery alerts) is set up by
# aerox-9-setup.sh.
#
# Review before running. Designed to be run section-by-section rather
# than blindly executed — comment out anything you don't want.
#
# Usage: chmod +x desktop-cachyos-setup.sh && ./desktop-cachyos-setup.sh

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
# 3. AUR packages — Razer (Tartarus Pro)
# ---------------------------------------------------------------------

$AUR_HELPER -S --needed --noconfirm \
  openrazer-meta \
  polychromatic

# openrazer requires your user in the 'plugdev' group + a re-login
sudo gpasswd -a "$USER" plugdev
echo ">>> Log out/in (or reboot) for the plugdev group change to apply."

# ---------------------------------------------------------------------
# 3.1 OpenRazer lighting profiles — Tartarus Pro (Polychromatic)
# ---------------------------------------------------------------------
#
# Polychromatic's GUI is the primary way to build/save lighting profiles
# and is what's recommended day-to-day. It also ships polychromatic-cli
# for scripting, though upstream has marked the CLI deprecated (still
# functional, just not guaranteed long-term) — fine for a one-shot
# startup script, less ideal to build new automation around going
# forward. Examples below run after the openrazer daemon is up and the
# devices are recognized (reboot/re-login after step 3 first).

cat <<'EOF'
>>> OpenRazer + Polychromatic installed.
    Launch the GUI once first to let it detect the Tartarus Pro,
    then build/save lighting profiles there.

    Optional scripted examples (polychromatic-cli, deprecated but
    functional) to set a static color + brightness on all Razer
    devices at login — add to an autostart script if wanted:
      polychromatic-cli -o brightness -p 60
      polychromatic-cli -o static -c 00A2FF

    Note: OpenRazer intentionally does NOT handle button remapping —
    upstream explicitly points users to Input Remapper (section 5
    below) for mapping the Tartarus Pro's keys to actions/macros.
EOF

# ---------------------------------------------------------------------
# 4. AUR packages — Stream Deck Plus
# ---------------------------------------------------------------------

$AUR_HELPER -S --needed --noconfirm streamcontroller

# ---------------------------------------------------------------------
# 5. OS-wide input remapping — Input Remapper (Tartarus Pro)
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
    Steps for each device:
      1. Select the Razer Tartarus Pro from the device dropdown — it
         will likely show up as multiple sub-devices (keyboard + mouse
         HID interfaces); pick the one that reports the extra button
         events (use `sudo evtest` to identify it if unsure).
      2. Create a new preset, map each physical button/key to the
         target key/macro.
      3. Enable "autoload" for that device so the preset applies on
         every login/reconnect.
    Note: keyd (installed in step 1) is an alternative for pure
    keyboard-level remaps if you ever want something lighter-weight
    than Input Remapper's GUI+daemon for the Tartarus specifically.
EOF

# ---------------------------------------------------------------------
# 6. Elgato Stream Deck / capture card udev rules
# ---------------------------------------------------------------------

sudo tee /etc/udev/rules.d/70-streamdeck.rules >/dev/null <<'EOF'
# Elgato Stream Deck devices - allow non-root access
SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", MODE="0666"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0fd9", MODE="0666"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

# ---------------------------------------------------------------------
# 7. Elgato 4K X capture card (community CLI, build from source)
# ---------------------------------------------------------------------

cat <<'EOF'
>>> Elgato 4K X has no official Linux driver. Community project:
    https://github.com/13bm/elgato4k-linux

    Build steps:
      sudo pacman -S --needed base-devel libusb rust
      git clone https://github.com/13bm/elgato4k-linux.git
      cd elgato4k-linux
      cargo build --release
      sudo cp target/release/elgato4k-linux /usr/local/bin/

    If the card isn't detected in 10Gbps mode, force 5Gbps mode with
    the tool's --usb-speed flag, or add the USB_QUIRK_NO_BOS kernel
    quirk as a GRUB_CMDLINE_LINUX boot parameter (see the repo README).
    Once recognized it appears as a normal /dev/video* (V4L2) + ALSA
    device usable directly in OBS Studio.
EOF

# ---------------------------------------------------------------------
# 8. Sound BlasterX G6 (community CLI, pip install)
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
# 9. Canon imageCLASS MF642Cdw (official Linux driver, manual download)
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
echo "=== Done. Reboot recommended before testing OpenRazer/plugdev/input-remapper. ==="
