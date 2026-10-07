#!/usr/bin/env bash
# Set up the Elgato Stream Deck Plus on CachyOS / Arch.
#
# Installs StreamController from the AUR, plus a udev rule that gives the
# logged-in user access to the deck's USB/hidraw nodes (the AUR package doesn't
# ship one). kvm-switch-setup.sh also relies on StreamController.
#
# Usage:
#   ./elgato-stream-deck-setup.sh              install
#   ./elgato-stream-deck-setup.sh --uninstall  remove the udev rule (StreamController stays)
set -euo pipefail

# AUR helpers refuse to run as root; this script sudoes only where it has to
if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not root." >&2
    exit 1
fi

RULE="/etc/udev/rules.d/70-elgato-stream-deck.rules"
# vendor-wide, world-writable rule from older hardware.sh runs
OLD_RULE="/etc/udev/rules.d/70-streamdeck.rules"

reload_udev() {
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=0fd9 --action=change
    sudo udevadm trigger --subsystem-match=hidraw --action=change
}

if [[ "${1:-}" == "--uninstall" ]]; then
    sudo rm -f "$RULE"
    reload_udev
    echo "Removed $RULE. StreamController is still installed."
    exit 0
fi

AUR_HELPER=$(command -v paru || command -v yay || true)
if [[ -z "$AUR_HELPER" ]]; then
    echo "No AUR helper (yay/paru) found; install one first." >&2
    exit 1
fi

echo "==> Installing StreamController (AUR)"
"$AUR_HELPER" -S --needed --noconfirm streamcontroller

if [[ -f "$OLD_RULE" ]]; then
    echo "==> Removing old vendor-wide rule $OLD_RULE"
    sudo rm -f "$OLD_RULE"
fi

echo "==> Writing $RULE"
sudo tee "$RULE" >/dev/null <<'RULES'
# Elgato Stream Deck Plus (0fd9:0084) - access for the logged-in user
SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="0084", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0084", TAG+="uaccess"
RULES
reload_udev

echo
echo "Launch StreamController and check the deck shows up; replug it if not."
