#!/usr/bin/env bash
#
# smb-mounts.sh
#
# CIFS/SMB automount for Shawn's desktop on CachyOS — mounts the Hitoma
# TrueNAS "ReliquaryTowerFull" share on demand via a systemd .mount /
# .automount unit pair, with credentials kept in a root-only file
# outside the unit itself.
#
# Review before running. Designed to be run section-by-section rather
# than blindly executed — comment out anything you don't want.
#
# Usage: chmod +x smb-mounts.sh && ./smb-mounts.sh

set -euo pipefail

# ---------------------------------------------------------------------
# 0. Config — adjust for the share being mounted
# ---------------------------------------------------------------------

SMB_HOST="192.168.1.210"
SMB_SHARE="ReliquaryTowerFull"
SMB_USER_DEFAULT="shawn"
CREDS_FILE="/etc/samba/creds-hitoma-truenas"
MOUNT_PATH="/var/mnt/ReliquaryTower"

# systemd requires the unit filename to be the systemd-escaped form of
# the mount path — derive it instead of hand-typing var-mnt-Foo.mount,
# since a typo there silently breaks the mount/automount pairing.
UNIT_BASE="$(systemd-escape --path "$MOUNT_PATH")"

# ---------------------------------------------------------------------
# 1. cifs-utils
# ---------------------------------------------------------------------
#
# Only the CIFS client is needed here — the full `samba` package (server
# + /etc/samba scaffolding) isn't required for mounting a remote share.

sudo pacman -S --needed --noconfirm cifs-utils

# ---------------------------------------------------------------------
# 2. Credentials file
# ---------------------------------------------------------------------

if [[ -f "$CREDS_FILE" ]]; then
  echo "Credentials file already exists at $CREDS_FILE — leaving it alone."
  echo "Delete it first if you need to rotate the password."
else
  read -rp "SMB username [$SMB_USER_DEFAULT]: " SMB_USER
  SMB_USER="${SMB_USER:-$SMB_USER_DEFAULT}"
  read -rsp "SMB password for $SMB_USER: " SMB_PASS
  echo

  # install -D creates /etc/samba if needed and sets mode 600 up front,
  # so the file is never briefly world/group-readable before a
  # trailing chmod (unlike a plain tee + chmod after).
  sudo install -D -m 600 /dev/null "$CREDS_FILE"
  sudo tee "$CREDS_FILE" >/dev/null <<EOF
username=$SMB_USER
password=$SMB_PASS
EOF
  unset SMB_PASS
  echo "Wrote credentials to $CREDS_FILE"
fi

# ---------------------------------------------------------------------
# 3. Mount point
# ---------------------------------------------------------------------

sudo mkdir -pv "$MOUNT_PATH"

# ---------------------------------------------------------------------
# 4. systemd .mount + .automount units
# ---------------------------------------------------------------------
#
# Automount-on-access pattern: only the .automount unit gets enabled.
# The .mount unit is pulled in automatically the first time something
# touches $MOUNT_PATH — enabling both would have systemd try to mount
# it unconditionally at boot too, racing (and duplicating) the
# automount trigger for no benefit.

sudo tee "/etc/systemd/system/${UNIT_BASE}.mount" >/dev/null <<EOF
[Unit]
Description=Hitoma TrueNAS Mount (${SMB_SHARE})
After=network-online.target
Wants=network-online.target

[Mount]
What=//${SMB_HOST}/${SMB_SHARE}
Where=${MOUNT_PATH}
Type=cifs
Options=credentials=${CREDS_FILE},uid=$(id -u),gid=$(id -g),iocharset=utf8
EOF

sudo tee "/etc/systemd/system/${UNIT_BASE}.automount" >/dev/null <<EOF
[Unit]
Description=Automount Hitoma TrueNAS (${SMB_SHARE})
After=network-online.target
Wants=network-online.target

[Automount]
Where=${MOUNT_PATH}
TimeoutIdleSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now "${UNIT_BASE}.automount"

cat <<EOF
>>> Automount unit enabled. It won't actually mount ${SMB_SHARE} until
    something accesses $MOUNT_PATH. Verify with:
      stat $MOUNT_PATH        # triggers the mount
      findmnt $MOUNT_PATH
      systemctl status ${UNIT_BASE}.automount ${UNIT_BASE}.mount
    If the mount fails, check:
      journalctl -u ${UNIT_BASE}.mount -b
EOF

echo ""
echo "=== Done. ==="
