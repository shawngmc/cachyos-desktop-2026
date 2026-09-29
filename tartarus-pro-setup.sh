#!/usr/bin/env bash
# Install (or remove) the Razer Tartarus Pro proxy on CachyOS / Arch.
#
# The keypad shows up as three evdev nodes (keys, extra/consumer keys, and the
# scroll wheel as a mouse). The proxy grabs all of them and re-emits them through
# one uinput device named "Tartarus Pro Proxy", so input-remapper sees a single
# device with its own name/hash and can grab it.
#
# Usage:
#   ./tartarus-pro-setup.sh              install
#   ./tartarus-pro-setup.sh --uninstall  remove the proxy
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

echo "==> Writing $BIN"
cat > "$BIN" <<'PY'
#!/usr/bin/python3
"""Proxy all Razer Tartarus Pro interfaces through one uinput device."""
import asyncio
import evdev
from evdev import InputDevice, UInput

VENDOR, PRODUCT = 0x1532, 0x0244                # the real keypad
PROXY_NAME = "Tartarus Pro Proxy"
PROXY_VENDOR, PROXY_PRODUCT = 0x1209, 0x0002    # must differ from the real IDs


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
    nodes = find_nodes()
    if not nodes:
        return
    ui = UInput.from_device(
        *nodes, name=PROXY_NAME, vendor=PROXY_VENDOR, product=PROXY_PRODUCT
    )
    tasks = []
    try:
        for n in nodes:
            n.grab()
        tasks = [asyncio.create_task(forward(n, ui)) for n in nodes]
        await asyncio.gather(*tasks)
    except OSError:
        pass  # keypad unplugged or a node was busy; clean up and rescan
    finally:
        for t in tasks:
            t.cancel()
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
