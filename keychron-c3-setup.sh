#!/usr/bin/env bash
# Set the Keychron C3 Pro 8K backlight from the command line.
#
# Talks to the keyboard's VIA raw-HID interface (the same protocol Keychron
# Launcher uses) and saves the result to the keyboard, so it survives replugs
# and works on other machines. No root needed: the desktop session already has
# read/write access to the keyboard's hidraw nodes.
#
# Usage:
#   ./keychron-c3-setup.sh                 apply the settings below and save them
#   ./keychron-c3-setup.sh --show          print the keyboard's current settings
#   ./keychron-c3-setup.sh --list-effects  print the effect names and numbers
set -euo pipefail

# Effect name or number (see --list-effects). 0 / "None" turns the backlight off.
EFFECT="Solid Color"
BRIGHTNESS=255      # 0-255
SPEED=223           # 0-255, for animated effects
COLOR="#00FFF0"     # hex; only hue/saturation are used (brightness sets the level).
                    # Applies to Solid Color, Breathing, Band Spiral Val,
                    # Reactive Simple/Multiwide/Multinexus and Solid Splash.

if ! pacman -Q python-hidapi &>/dev/null; then
    echo "==> Installing python-hidapi"
    sudo pacman -S --needed --noconfirm python-hidapi
fi

ACTION="apply"
case "${1:-}" in
    --show) ACTION="show" ;;
    --list-effects) ACTION="list" ;;
    "") ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
esac

python3 - "$ACTION" "$EFFECT" "$BRIGHTNESS" "$SPEED" "$COLOR" <<'PY'
import colorsys
import sys

import hid

VENDOR, PRODUCT = 0x3434, 0x0530    # Keychron C3 Pro 8K
RAW_USAGE_PAGE = 0xFF60             # VIA / QMK raw HID interface

# VIA commands, and the RGB matrix channel/value ids (QMK quantum/via.h)
SET_VALUE, GET_VALUE, SAVE = 0x07, 0x08, 0x09
RGB_MATRIX = 3
BRIGHTNESS, EFFECT, SPEED, COLOR = 1, 2, 3, 4

# From Keychron's c3_pro_8k_ansi_via.json (qmk_firmware 2025q3)
EFFECTS = [
    "None", "Solid Color", "Breathing", "Band Spiral Val", "Cycle All",
    "Cycle Left Right", "Cycle Up Down", "Rainbow Moving Chevron",
    "Cycle Out In", "Cycle Out In Dual", "Cycle Pinwheel", "Cycle Spiral",
    "Dual Beacon", "Rainbow Beacon", "Jellybean Raindrops", "Pixel Rain",
    "Typing Heatmap", "Digital Rain", "Reactive Simple", "Reactive Multiwide",
    "Reactive Multinexus", "Splash", "Solid Splash", "Per Key RGB", "Mix RGB",
]


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def open_keyboard():
    for info in hid.enumerate(VENDOR, PRODUCT):
        if info["usage_page"] == RAW_USAGE_PAGE:
            dev = hid.device()
            try:
                dev.open_path(info["path"])
            except OSError as err:
                die(f"can't open {info['path'].decode()} ({err}); try with sudo")
            return dev
    die("Keychron C3 Pro 8K not found")


def command(dev, *data):
    dev.write(bytes([0, *data]) + bytes(32 - len(data)))
    reply = dev.read(32, 1000)
    if not reply or reply[0] != data[0]:
        die(f"keyboard rejected command {data[:3]} (reply {reply[:3]})")
    return reply


def get(dev, value_id):
    return command(dev, GET_VALUE, RGB_MATRIX, value_id)[3:5]


def set_(dev, value_id, *values):
    command(dev, SET_VALUE, RGB_MATRIX, value_id, *values)


def parse_effect(text):
    if text.isdigit() and int(text) < len(EFFECTS):
        return int(text)
    for i, name in enumerate(EFFECTS):
        if name.lower() == text.lower():
            return i
    die(f"unknown effect {text!r}; see --list-effects")


def parse_byte(text, what):
    if not text.isdigit() or int(text) > 255:
        die(f"{what} must be 0-255, got {text!r}")
    return int(text)


def parse_color(text):
    hexstr = text.lstrip("#")
    try:
        r, g, b = (int(hexstr[i:i + 2], 16) / 255 for i in (0, 2, 4))
    except ValueError:
        die(f"color must be #RRGGBB, got {text!r}")
    h, s, _ = colorsys.rgb_to_hsv(r, g, b)
    return round(h * 255), round(s * 255)


def show(dev):
    effect = get(dev, EFFECT)[0]
    hue, sat = get(dev, COLOR)
    r, g, b = colorsys.hsv_to_rgb(hue / 255, sat / 255, 1)
    name = EFFECTS[effect] if effect < len(EFFECTS) else "?"
    print(f"Effect:     {effect} ({name})")
    print(f"Brightness: {get(dev, BRIGHTNESS)[0]}")
    print(f"Speed:      {get(dev, SPEED)[0]}")
    print(f"Color:      #{round(r * 255):02X}{round(g * 255):02X}{round(b * 255):02X}"
          f" (hue {hue}, sat {sat})")


action, effect, brightness, speed, color = sys.argv[1:6]

if action == "list":
    for i, name in enumerate(EFFECTS):
        print(f"{i:3}  {name}")
    sys.exit(0)

# validate everything before touching the keyboard
if action == "apply":
    effect = parse_effect(effect)
    brightness = parse_byte(brightness, "BRIGHTNESS")
    speed = parse_byte(speed, "SPEED")
    hue, sat = parse_color(color)

dev = open_keyboard()
try:
    if action == "apply":
        set_(dev, EFFECT, effect)
        set_(dev, BRIGHTNESS, brightness)
        set_(dev, SPEED, speed)
        set_(dev, COLOR, hue, sat)
        command(dev, SAVE, RGB_MATRIX)   # write to the keyboard's EEPROM
        print("Saved to keyboard:")
    show(dev)
finally:
    dev.close()
PY
