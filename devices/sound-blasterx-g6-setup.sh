#!/usr/bin/env bash
# Set up the Creative Sound BlasterX G6 on CachyOS / Arch.
#
# Sound works as a plain USB audio device with no package needed. This adds the
# community soundblaster-x-g6-cli (https://github.com/nils-skowasch/soundblaster-x-g6-cli)
# for LED/HID control, via pipx for the current user, plus the udev rule it
# needs to reach the device without root. There's no official Creative Linux
# driver; BlasterX Acoustic Engine EQ/RGB features are Windows-only otherwise.
#
# Usage:
#   ./sound-blasterx-g6-setup.sh              install / upgrade
#   ./sound-blasterx-g6-setup.sh --uninstall  remove the CLI and udev rule
set -euo pipefail

# pipx installs for the invoking user; this script sudoes only where it has to
if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not root." >&2
    exit 1
fi

RULE="/etc/udev/rules.d/50-soundblaster-x-g6.rules"

reload_udev() {
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=041e --action=change
}

if [[ "${1:-}" == "--uninstall" ]]; then
    pipx uninstall soundblaster-x-g6-cli || true
    sudo rm -f "$RULE"
    reload_udev
    echo "Removed soundblaster-x-g6-cli and $RULE."
    exit 0
fi

echo "==> Installing soundblaster-x-g6-cli (pipx, for $USER)"
sudo pacman -S --needed --noconfirm python-pipx libusb
pipx install soundblaster-x-g6-cli
pipx upgrade soundblaster-x-g6-cli

echo "==> Writing $RULE"
sudo tee "$RULE" >/dev/null <<'RULES'
# Sound BlasterX G6 (041e:3256) - access for the logged-in user, for soundblaster-x-g6-cli
SUBSYSTEM=="usb", ATTRS{idVendor}=="041e", ATTRS{idProduct}=="3256", TAG+="uaccess"
RULES
reload_udev

echo
echo "Check the CLI can reach the G6 (pipx puts it in ~/.local/bin):"
echo "  soundblaster-x-g6-cli --help"
