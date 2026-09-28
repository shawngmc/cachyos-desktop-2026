#!/usr/bin/env bash
# Install (or remove) the Aerox 9 grid proxy on CachyOS / Arch.
#
# The proxy grabs the dongle's keyboard-type interfaces and re-emits them through
# one uinput device named "Aerox9 Grid Proxy", so input-remapper sees a device
# with its own name/hash and can grab it.
#
# Usage:
#   ./aerox9-proxy-setup.sh              install, and disable the old hwdb remap
#   ./aerox9-proxy-setup.sh --keep-hwdb  install, leave the hwdb remap in place
#   ./aerox9-proxy-setup.sh --uninstall  remove the proxy, restore the hwdb file
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

BIN="/usr/local/bin/aerox9-proxy"
UNIT="/etc/systemd/system/aerox9-proxy.service"
HWDB="/etc/udev/hwdb.d/90-aerox9.hwdb"
HWDB_OFF="${HWDB}.disabled"

reload_hwdb() {
    systemd-hwdb update
    udevadm trigger --subsystem-match=input --action=change
    udevadm settle
}

if [[ "${1:-}" == "--uninstall" ]]; then
    systemctl disable --now aerox9-proxy.service 2>/dev/null || true
    rm -f "$UNIT" "$BIN"
    systemctl daemon-reload
    if [[ -f "$HWDB_OFF" ]]; then
        mv "$HWDB_OFF" "$HWDB"
        reload_hwdb
        echo "Restored $HWDB"
    fi
    echo "Removed aerox9-proxy. Replug the dongle if the buttons misbehave."
    exit 0
fi

KEEP_HWDB=0
[[ "${1:-}" == "--keep-hwdb" ]] && KEEP_HWDB=1

echo "==> Installing python-evdev"
pacman -S --needed --noconfirm python-evdev

echo "==> Writing $BIN"
cat > "$BIN" <<'PY'
#!/usr/bin/python3
"""Proxy the Aerox 9 side-grid keyboard interfaces through one uinput device."""
import asyncio
import evdev
from evdev import ecodes as e, InputDevice, UInput

VENDOR, PRODUCT = 0x1038, 0x1874                # the real dongle
PROXY_NAME = "Aerox9 Grid Proxy"
PROXY_VENDOR, PROXY_PRODUCT = 0x1209, 0x0001    # must differ from the real IDs


def find_grid_nodes():
    nodes = []
    for path in evdev.list_devices():
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        if (dev.info.vendor, dev.info.product) != (VENDOR, PRODUCT):
            dev.close()
            continue
        keys = dev.capabilities().get(e.EV_KEY, [])
        # keyboard-type interface: has KEY_1, is not the mouse node (BTN_LEFT)
        if e.KEY_1 in keys and e.BTN_LEFT not in keys:
            nodes.append(dev)
        else:
            dev.close()
    return nodes


async def forward(dev, ui):
    async for ev in dev.async_read_loop():
        ui.write_event(ev)


async def run_once():
    nodes = find_grid_nodes()
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
        pass  # dongle unplugged; clean up and rescan
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
Description=Aerox 9 grid proxy (uinput)

[Service]
ExecStart=/usr/local/bin/aerox9-proxy
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

if [[ $KEEP_HWDB -eq 0 && -f "$HWDB" ]]; then
    echo "==> Disabling old hwdb remap ($HWDB -> $HWDB_OFF)"
    mv "$HWDB" "$HWDB_OFF"
    reload_hwdb
fi

echo "==> Enabling service"
systemctl daemon-reload
systemctl enable --now aerox9-proxy.service
systemctl restart aerox9-proxy.service

if systemctl list-unit-files input-remapper.service &>/dev/null; then
    echo "==> Restarting input-remapper"
    systemctl restart input-remapper.service || true
fi

sleep 1
echo
systemctl --no-pager --lines=5 status aerox9-proxy.service || true
echo
echo "Check that the proxy device exists:"
echo "  grep -A4 'Aerox9 Grid Proxy' /proc/bus/input/devices"
echo "Then open input-remapper, select 'Aerox9 Grid Proxy', and re-record your mappings."