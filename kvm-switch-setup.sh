#!/usr/bin/env bash
#
# kvm-switch-setup.sh
#
# Turns the Stream Deck into a KVM controller. Installs /usr/local/bin/kvm-switch,
# which moves everything to one of four machines (GAMING, FLEX, WORK, MAC) in a
# single call:
#   - HDMI matrix (192.168.1.147): output 2 -> the target's input
#   - USB matrix  (192.168.1.72):  USB outputs 1 and 2 (keyboard/mouse) -> target
#   - Dell monitor (DDC/CI):       DP for GAMING, HDMI (from the matrix) otherwise
# Then prints the StreamController steps to bind one key per target.
#
# Plug the Stream Deck straight into this PC, NOT through the USB matrix. If it
# goes through the matrix it switches away with the keyboard, and you lose the
# keys that switch back.
#
# Usage: chmod +x kvm-switch-setup.sh && ./kvm-switch-setup.sh

set -euo pipefail

BIN="/usr/local/bin/kvm-switch"

# ---------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------
#
# ddcutil is also in hardware.sh; --needed makes a repeat a no-op.
# streamcontroller (AUR) comes from devices/elgato-stream-deck-setup.sh.

sudo pacman -S --needed --noconfirm ddcutil jq curl libnotify

# ---------------------------------------------------------------------
# 2. DDC/CI access without root
# ---------------------------------------------------------------------
#
# ddcutil talks to the monitor over /dev/i2c-*, and those nodes exist only
# once i2c-dev is loaded. ddcutil's packaged udev rule (60-ddcutil-i2c.rules)
# tags the GPU's i2c buses "uaccess", which lets the logged-in user read and
# write them, so StreamController can run kvm-switch without sudo.

echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
sudo modprobe i2c-dev
sudo udevadm trigger --subsystem-match=i2c-dev

# ---------------------------------------------------------------------
# 3. kvm-switch
# ---------------------------------------------------------------------

echo "==> Writing $BIN"
sudo tee "$BIN" >/dev/null <<'SH'
#!/usr/bin/env bash
# Switch the HDMI matrix, the USB (keyboard/mouse) matrix and the Dell monitor to
# one machine. Every step runs even if an earlier one fails, so a matrix that's
# down doesn't block the others. Failures show up as a desktop notification,
# since output from a Stream Deck key press goes nowhere.
#
# Usage: kvm-switch <GAMING|FLEX|WORK|MAC>

HDMI_HOST="192.168.1.147"
USB_HOST="192.168.1.72"
DELL_DISPLAY=1     # ddcutil display number (see `ddcutil detect`)

TARGET="${1^^}"
case "$TARGET" in
  GAMING) SWITCH_ID=1; DELL_INPUT=0x0f ;;   # DisplayPort 1 (direct)
  FLEX)   SWITCH_ID=2; DELL_INPUT=0x11 ;;   # HDMI 1 (from the matrix)
  WORK)   SWITCH_ID=3; DELL_INPUT=0x11 ;;
  MAC)    SWITCH_ID=4; DELL_INPUT=0x11 ;;
  *)
    echo "Usage: $0 <GAMING|FLEX|WORK|MAC>" >&2
    exit 1
    ;;
esac

# Serialize key presses so mashing the button can't interleave two switches
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/kvm-switch.lock"
flock 9

CURL=(curl -s -o /dev/null --connect-timeout 1 --max-time 3)
errors=()

# Set HDMI out
# TODO: skip when already on this input (switching causes a blank); the web UI
# reads status in an odd binary format, so there's no easy query yet
TS=$(date +%s%3N)
"${CURL[@]}" -X POST "http://${HDMI_HOST}/video_set${TS}" \
  -d "#video_d out2 matrix=${SWITCH_ID}" || errors+=("HDMI matrix")

# Get USB status via CGI, e.g. Outputbuttom="1122" = outputs 1-4 on inputs 1,1,2,2.
# If the query fails, the outputs stay unknown and both get set anyway.
usb_output=""
if usb_raw=$(curl -s --connect-timeout 1 --max-time 3 -X POST \
    "http://${USB_HOST}/cgi-bin/MUH44TP_getsetparams.cgi" -d "lcc"); then
  usb_raw_json="${usb_raw:2:-1}"
  usb_output=$(jq -r .Outputbuttom <<<"${usb_raw_json//\'/\"}" 2>/dev/null)
fi

# Set KB/mouse outs only if necessary
for out in 1 2; do
  if [[ "${usb_output:out-1:1}" != "$SWITCH_ID" ]]; then
    "${CURL[@]}" -X POST "http://${USB_HOST}/cgi-bin/MMX32_Keyvalue.cgi" \
      -d "CMD=>SetUSB 0${out}:${SWITCH_ID}"$'\n' || errors+=("USB out ${out}")
    sleep 0.1
  fi
done

# Set monitor input only if necessary (--brief prints e.g. "VCP 60 SNC x0f")
CURRENT_DELL_INPUT=0$(ddcutil -d "$DELL_DISPLAY" getvcp 60 --brief 2>/dev/null | awk '{print $NF}')
if [[ "$CURRENT_DELL_INPUT" != "$DELL_INPUT" ]]; then
  ddcutil -d "$DELL_DISPLAY" setvcp 60 "$DELL_INPUT" || errors+=("Dell input")
fi

if (( ${#errors[@]} )); then
  msg="Failed: ${errors[*]}"
  echo "kvm-switch $TARGET: $msg" >&2
  command -v notify-send >/dev/null && notify-send -a kvm-switch -i dialog-error "KVM → $TARGET" "$msg"
  exit 1
fi
SH
sudo chmod 755 "$BIN"

# ---------------------------------------------------------------------
# 4. Sanity check
# ---------------------------------------------------------------------
#
# Reads only (nothing switches): confirms this user can reach the Dell without
# sudo. If it fails, log out and back in so the uaccess ACLs apply.

echo "==> Checking DDC/CI access to the Dell (display 1)"
if ddcutil -d 1 getvcp 60 --brief; then
  echo "    OK"
else
  echo "    Couldn't read the monitor input. Run 'ddcutil detect' to find the Dell's"
  echo "    display number (set DELL_DISPLAY in $BIN), and re-login if it's a permissions error."
fi

cat <<EOF

>>> kvm-switch installed. Try it from a terminal first:
      kvm-switch GAMING
      kvm-switch WORK

    StreamController setup (one key per target):
      1. Open StreamController, go to Store > Plugins, and install "OS".
      2. For each of GAMING, FLEX, WORK, MAC, pick a key and add the action
         OS > Run Command with the command:
           $BIN GAMING      (or FLEX / WORK / MAC)
      3. Put the target name in the key's label, or set an icon.

    If a key does nothing, run the same command in a terminal. Failures also
    show up as a desktop notification.
EOF

echo ""
echo "=== Done. ==="
