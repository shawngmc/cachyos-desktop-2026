#!/usr/bin/env bash
# Install (or remove) the Razer Tartarus Pro proxy on CachyOS / Arch.
#
# The keypad shows up as three evdev nodes (keys, extra/consumer keys, and the
# scroll wheel as a mouse). The proxy grabs all of them and re-emits them through
# one uinput device named "Tartarus Pro Proxy", so input-remapper sees a single
# device with its own name/hash and can grab it.
#
# Also installs OpenRazer + Polychromatic (lighting) from the AUR and adds the
# invoking user to the 'plugdev' group they require.
#
# Usage:
#   ./tartarus-pro-setup.sh              install
#   ./tartarus-pro-setup.sh --uninstall  remove the proxy (OpenRazer stays)
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

BIN="/usr/local/bin/tartarus-proxy"
UNIT="/etc/systemd/system/tartarus-proxy.service"

if [[ "${1:-}" == "--uninstall" ]]; then
    systemctl disable --now tartarus-proxy.service 2>/dev/null || true
    rm -f "$UNIT" "$BIN"
    systemctl daemon-reload
    echo "Removed tartarus-proxy. Replug the keypad if the keys misbehave."
    exit 0
fi

echo "==> Installing python-evdev"
pacman -S --needed --noconfirm python-evdev

# AUR helpers refuse to run as root, so build as the user who ran the script
if [[ -z "${SUDO_USER:-}" ]]; then
    echo "Run this as your normal user (it re-execs with sudo) so AUR packages can build." >&2
    exit 1
fi
AUR_HELPER=$(command -v paru || command -v yay || true)
if [[ -z "$AUR_HELPER" ]]; then
    echo "No AUR helper (yay/paru) found; install one first." >&2
    exit 1
fi

echo "==> Installing OpenRazer + Polychromatic (AUR, as $SUDO_USER)"
sudo -u "$SUDO_USER" "$AUR_HELPER" -S --needed --noconfirm openrazer-meta polychromatic

# openrazer requires the user in 'plugdev' + a re-login
echo "==> Adding $SUDO_USER to plugdev"
gpasswd -a "$SUDO_USER" plugdev

echo "==> Writing $BIN"
cat > "$BIN" <<'PY'
#!/usr/bin/python3
"""Proxy all Razer Tartarus Pro interfaces through one uinput device."""
import asyncio
import sys
import evdev
from evdev import InputDevice, UInput

VENDOR, PRODUCT = 0x1532, 0x0244                # the real keypad
PROXY_NAME = "Tartarus Pro Proxy"
PROXY_VENDOR, PROXY_PRODUCT = 0x1209, 0x0002    # must differ from the real IDs

last_error = None


def find_nodes():
    nodes = []
    for path in evdev.list_devices():
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        # input-remapper's forwarded copies reuse the real IDs; only take the
        # physical USB interfaces
        if (dev.info.vendor, dev.info.product) == (VENDOR, PRODUCT) and (
            dev.phys or ""
        ).startswith("usb-"):
            nodes.append(dev)
        else:
            dev.close()
    return nodes


async def forward(dev, ui):
    async for ev in dev.async_read_loop():
        ui.write_event(ev)


async def run_once():
    global last_error
    nodes = find_nodes()
    if not nodes:
        return
    ui = None
    tasks = []
    try:
        # grab first, so a node held by something else (e.g. an input-remapper
        # preset on the real device) doesn't make the proxy appear and vanish
        for n in nodes:
            n.grab()
        ui = UInput.from_device(
            *nodes, name=PROXY_NAME, vendor=PROXY_VENDOR, product=PROXY_PRODUCT
        )
        last_error = None
        tasks = [asyncio.create_task(forward(n, ui)) for n in nodes]
        await asyncio.gather(*tasks)
    except OSError as err:
        # unplugged, or a node is grabbed elsewhere; log once, then rescan
        msg = f"{err} (nodes: {', '.join(n.path for n in nodes)})"
        if msg != last_error:
            print(msg, file=sys.stderr, flush=True)
            last_error = msg
    finally:
        for t in tasks:
            t.cancel()
        if ui:
            ui.close()
        for n in nodes:
            try:
                n.close()
            except OSError:
                pass


async def main():
    while True:
        await run_once()
        await asyncio.sleep(2)


asyncio.run(main())
PY
chmod 755 "$BIN"

echo "==> Writing $UNIT"
cat > "$UNIT" <<'UNIT'
[Unit]
Description=Razer Tartarus Pro proxy (uinput)
Before=input-remapper.service

[Service]
ExecStart=/usr/local/bin/tartarus-proxy
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

echo "==> Enabling service"
systemctl daemon-reload
systemctl enable --now tartarus-proxy.service
if systemctl list-unit-files input-remapper.service &>/dev/null; then
    # input-remapper may already hold the real nodes; stop it so the proxy can grab them
    systemctl stop input-remapper.service || true
fi
systemctl restart tartarus-proxy.service

if systemctl list-unit-files input-remapper.service &>/dev/null; then
    sleep 1
    echo "==> Restarting input-remapper"
    systemctl start input-remapper.service || true
fi

sleep 1
echo
systemctl --no-pager --lines=5 status tartarus-proxy.service || true
echo
echo "Check that the proxy device exists:"
echo "  grep -A4 'Tartarus Pro Proxy' /proc/bus/input/devices"
echo "Then open input-remapper, select 'Tartarus Pro Proxy', and re-record your mappings."
echo "Turn off autoload for any old 'Razer Razer Tartarus Pro' preset."
echo
cat <<'EOF'
Lighting (OpenRazer + Polychromatic):
  Log out/in (or reboot) for the plugdev group change to apply, then launch
  Polychromatic once to let it detect the Tartarus Pro and build/save lighting
  profiles there. polychromatic-cli is deprecated upstream but still works for
  a one-shot autostart script, e.g.:
    polychromatic-cli -o brightness -p 60
    polychromatic-cli -o static -c 00A2FF
  OpenRazer does not do button remapping; that's what the proxy + input-remapper
  are for.
EOF
