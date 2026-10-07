#!/usr/bin/env bash
# Set up the Elgato 4K X capture card on CachyOS / Arch.
#
# Video and audio need nothing extra: the card is a standard UVC (/dev/video*)
# and USB audio device, usable directly in OBS. This builds the community
# elgato4k-linux tool (HDR tone mapping, HDMI range, EDID source, USB speed;
# https://github.com/13bm/elgato4k-linux, not in the AUR) from a pinned release
# tag, and adds a udev rule so the logged-in user can run it without sudo.
#
# The card's PID follows its USB speed mode: 009b = 10Gbps, 009c = 5Gbps,
# 009d = USB 2.0. If the kernel doesn't pick it up at 10Gbps, switch it to 5Gbps
# (elgato4k-linux --usb-speed 5g), or add usbcore.quirks=0fd9:009b:o to the
# kernel command line.
#
# Usage:
#   ./elgato-4k-x-setup.sh              install, or rebuild after bumping VERSION
#   ./elgato-4k-x-setup.sh --uninstall  remove the tool, its source and the udev rule
set -euo pipefail

# cargo builds as you; this script sudoes only where it has to
if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not root." >&2
    exit 1
fi

VERSION="v0.2.5"   # elgato4k-linux release tag to build; bump to upgrade
REPO="https://github.com/13bm/elgato4k-linux.git"
SRC="${XDG_CACHE_HOME:-$HOME/.cache}/elgato4k-linux"
BIN="/usr/local/bin/elgato4k-linux"
RULE="/etc/udev/rules.d/70-elgato-4k-x.rules"
# vendor-wide, world-writable rule from older hardware.sh runs
OLD_RULE="/etc/udev/rules.d/70-streamdeck.rules"

reload_udev() {
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=0fd9 --action=change
}

if [[ "${1:-}" == "--uninstall" ]]; then
    sudo rm -f "$BIN" "$RULE"
    rm -rf "$SRC"
    reload_udev
    echo "Removed $BIN, $SRC and $RULE."
    exit 0
fi

echo "==> Installing build dependencies"
sudo pacman -S --needed --noconfirm base-devel git libusb pkgconf
# 'rust' conflicts with 'rustup'; skip it if any cargo is already installed
if ! command -v cargo &>/dev/null; then
    sudo pacman -S --needed --noconfirm rust
fi

echo "==> Fetching elgato4k-linux $VERSION"
if [[ -d "$SRC/.git" ]]; then
    git -C "$SRC" fetch --quiet --tags --force origin
else
    git clone --quiet "$REPO" "$SRC"
fi
git -C "$SRC" checkout --quiet --detach "refs/tags/$VERSION"

# --no-default-features drops the update check, which queries the GitHub API
# after every command; the version is pinned above instead.
echo "==> Building"
(cd "$SRC" && cargo build --release --locked --no-default-features)

echo "==> Installing $BIN"
sudo install -Dm755 "$SRC/target/release/elgato4k-linux" "$BIN"

if [[ -f "$OLD_RULE" ]]; then
    echo "==> Removing old vendor-wide rule $OLD_RULE"
    sudo rm -f "$OLD_RULE"
fi

echo "==> Writing $RULE"
sudo tee "$RULE" >/dev/null <<'RULES'
# Elgato 4K X - access for the logged-in user, so elgato4k-linux runs without
# sudo. PID follows the USB speed mode: 009b = 10Gbps, 009c = 5Gbps, 009d = USB 2.0.
SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="009b|009c|009d", TAG+="uaccess"
RULES
reload_udev

echo
echo "Check the card is detected and readable without sudo:"
echo "  lsusb | grep 0fd9"
echo "  elgato4k-linux --status"
