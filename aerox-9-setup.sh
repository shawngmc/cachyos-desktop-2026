#!/usr/bin/env bash
# Install (or remove) the Aerox 9 grid proxy on CachyOS / Arch.
#
# The proxy grabs the dongle's keyboard-type interfaces and re-emits them through
# one uinput device named "Aerox9 Grid Proxy", so input-remapper sees a device
# with its own name/hash and can grab it.
#
# Also installs rivalcfg (battery level, sleep timer, etc.) globally via pipx,
# along with its udev rules so it works without root, and a user timer that
# sends a desktop notification when the mouse battery runs low.
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
PM_RULE="/etc/udev/rules.d/72-aerox9-no-autosuspend.rules"
RIVAL_RULE="/etc/udev/rules.d/99-steelseries-rival.rules"
SLEEP_TIMER=0   # minutes idle before the mouse sleeps (0-20, 0 = never)
BATTERY_WARN=30 # notify when the battery drops below this percentage
BATTERY_REMIND=30 # minutes between repeat notifications while still low
BATT_BIN="/usr/local/bin/aerox9-battery-check"
BATT_UNIT="/etc/systemd/user/aerox9-battery.service"
BATT_TIMER="/etc/systemd/user/aerox9-battery.timer"

# run systemctl --user against the invoking user's session, if they have one
user_systemctl() {
    [[ -n "${SUDO_USER:-}" ]] || return 0
    systemctl --user --machine="${SUDO_USER}@" "$@" || true
}

reload_usb_pm() {
    udevadm control --reload-rules
    udevadm trigger --subsystem-match=usb --attr-match=idVendor=1038 --action=change
}

reload_hwdb() {
    systemd-hwdb update
    udevadm trigger --subsystem-match=input --action=change
    udevadm settle
}

if [[ "${1:-}" == "--uninstall" ]]; then
    systemctl disable --now aerox9-proxy.service 2>/dev/null || true
    rm -f "$UNIT" "$BIN"
    systemctl daemon-reload
    user_systemctl disable --now aerox9-battery.timer
    systemctl --global disable aerox9-battery.timer 2>/dev/null || true
    rm -f "$BATT_TIMER" "$BATT_UNIT" "$BATT_BIN"
    user_systemctl daemon-reload
    if pipx list --global --short 2>/dev/null | grep -q '^rivalcfg '; then
        pipx uninstall --global rivalcfg
        rm -f "$RIVAL_RULE"
        udevadm control --reload-rules
        echo "Removed rivalcfg and $RIVAL_RULE"
    fi
    if [[ -f "$PM_RULE" ]]; then
        rm -f "$PM_RULE"
        udevadm control --reload-rules
        echo "Removed $PM_RULE (autosuspend returns to default on replug)"
    fi
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

echo "==> Installing rivalcfg (pipx --global, into /usr/local/bin)"
pacman -S --needed --noconfirm python-pipx
pipx install --global rivalcfg
pipx upgrade --global rivalcfg
# Not 'rivalcfg --update-udev': it runs a bare 'udevadm trigger', which replays
# every input device and lets input-remapper autoload presets onto the real
# dongle before the proxy can grab it. Write the rules and trigger hidraw only.
/usr/local/bin/rivalcfg --print-udev > "$RIVAL_RULE"
udevadm control --reload-rules
udevadm trigger --subsystem-match=hidraw --action=change

# rivalcfg saves to the mouse's onboard memory, so this only needs to run once
echo "==> Setting mouse sleep timer to $SLEEP_TIMER min (0 = disabled)"
udevadm settle
/usr/local/bin/rivalcfg --sleep-timer "$SLEEP_TIMER" \
    || echo "    Mouse not reachable (off or asleep?); rerun: rivalcfg --sleep-timer $SLEEP_TIMER"

# rivalcfg saves to the mouse's onboard memory, so this only needs to run once
echo "==> Setting mouse to teal/green"
udevadm settle
/usr/local/bin/rivalcfg --z1 green --z2 teal --z3 green\
    || echo "    Mouse not reachable (off or asleep?); rerun: /usr/local/bin/rivalcfg --z1 green --z2 teal --z3 green

echo "==> Writing $BATT_BIN"
cat > "$BATT_BIN" <<'SH'
#!/usr/bin/env bash
# Notify when the Aerox 9 battery drops below $1 percent (default 30), and again
# every $2 minutes (default 30) while it stays low. The flag file's mtime is
# when we last notified; it is cleared once the mouse is charging or back above
# the threshold.
threshold=${1:-30}
remind=${2:-30}
state="${XDG_RUNTIME_DIR:-/tmp}/aerox9-battery-low"
out=$(/usr/local/bin/rivalcfg --battery-level 2>/dev/null) || exit 0
[[ $out =~ ([0-9]+)\ % ]] || exit 0   # mouse off or asleep
level=${BASH_REMATCH[1]}
# TODO: suppress alerts while the mouse is charging. rivalcfg doesn't report the
# change: it still says "Discharging" with the cable plugged in, so the Charging*
# check below never matches.
if [[ $out == Charging* || $level -ge $threshold ]]; then
    rm -f "$state"
elif [[ ! -e $state ]]; then
    notify-send --urgency=critical --app-name="Aerox 9" --icon=input-mouse \
        "Aerox 9 battery low" "${level}% remaining"
    touch "$state"
elif (( $(date +%s) - $(stat -c %Y "$state") >= remind * 60 )); then
    notify-send --urgency=critical --app-name="Aerox 9" --icon=input-mouse \
        "Aerox 9 battery still low" "${level}% remaining"
    touch "$state"
fi
SH
chmod 755 "$BATT_BIN"

echo "==> Writing $BATT_UNIT and $BATT_TIMER"
cat > "$BATT_UNIT" <<UNIT
[Unit]
Description=Aerox 9 low battery check

[Service]
Type=oneshot
ExecStart=$BATT_BIN $BATTERY_WARN $BATTERY_REMIND
UNIT
cat > "$BATT_TIMER" <<'UNIT'
[Unit]
Description=Check Aerox 9 battery every 5 minutes

[Timer]
OnStartupSec=1min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT

echo "==> Writing $BIN"
cat > "$BIN" <<'PY'
#!/usr/bin/python3
"""Proxy the Aerox 9 side-grid keyboard interfaces through one uinput device."""
import asyncio
import sys
import evdev
from evdev import ecodes as e, InputDevice, UInput

VENDOR, PRODUCT = 0x1038, 0x1874                # the real dongle
PROXY_NAME = "Aerox9 Grid Proxy"
PROXY_VENDOR, PROXY_PRODUCT = 0x1209, 0x0001    # must differ from the real IDs

last_error = None


def find_grid_nodes():
    nodes = []
    for path in evdev.list_devices():
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        # input-remapper's forwarded copies reuse the real IDs; only take the
        # physical USB interfaces
        if (dev.info.vendor, dev.info.product) != (VENDOR, PRODUCT) or not (
            dev.phys or ""
        ).startswith("usb-"):
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
    global last_error
    nodes = find_grid_nodes()
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
Description=Aerox 9 grid proxy (uinput)

[Service]
ExecStart=/usr/local/bin/aerox9-proxy
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

echo "==> Writing $PM_RULE"
cat > "$PM_RULE" <<'RULES'
# SteelSeries Aerox 9 - keep USB autosuspend off (1874 = wireless dongle, 185a = wired)
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1038", ATTR{idProduct}=="1874|185a", \
  TEST=="power/control", ATTR{power/control}="on"
RULES
reload_usb_pm

if [[ $KEEP_HWDB -eq 0 && -f "$HWDB" ]]; then
    echo "==> Disabling old hwdb remap ($HWDB -> $HWDB_OFF)"
    mv "$HWDB" "$HWDB_OFF"
    reload_hwdb
fi

echo "==> Enabling service"
systemctl daemon-reload
systemctl enable --now aerox9-proxy.service
systemctl restart aerox9-proxy.service

echo "==> Enabling battery timer (all users, and now for ${SUDO_USER:-nobody})"
systemctl --global enable aerox9-battery.timer
user_systemctl daemon-reload
user_systemctl restart aerox9-battery.timer

if systemctl list-unit-files input-remapper.service &>/dev/null; then
    echo "==> Restarting input-remapper"
    systemctl restart input-remapper.service || true
fi

sleep 1
echo
systemctl --no-pager --lines=5 status aerox9-proxy.service || true
echo
echo "Check autosuspend is off (expect 'on'):"
echo "  grep -l 1038 /sys/bus/usb/devices/*/idVendor | xargs -n1 dirname | xargs -I{} cat {}/power/control"
echo "Check rivalcfg can reach the mouse:"
echo "  rivalcfg --battery-level"
echo "Test the low-battery notification (fires if below 101%):"
echo "  rm -f \$XDG_RUNTIME_DIR/aerox9-battery-low; $BATT_BIN 101"
echo "Check that the proxy device exists:"
echo "  grep -A4 'Aerox9 Grid Proxy' /proc/bus/input/devices"
echo "Then open input-remapper, select 'Aerox9 Grid Proxy', and re-record your mappings."