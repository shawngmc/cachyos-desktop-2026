#!/usr/bin/env bash
#
# krdp-setup.sh
#
# Installs and configures KRDP (KDE Plasma's built-in RDP server) for
# remote desktop access to Shawn's desktop on CachyOS. Logs in with the
# current Linux account via PAM (no separate KRDP-only credentials to
# manage), pins a long-lived self-signed TLS cert so it doesn't
# regenerate (and re-trigger "unknown certificate" warnings) on every
# restart, opens the RDP port on ufw if it's active, and — since KRDP
# has nothing to attach to unless a Plasma session is already
# running — optionally configures SDDM autologin so a session always
# exists, immediately locked (kscreenlocker's LockOnStart) so autologin
# doesn't mean an unattended, unlocked desktop. Read section 7 before
# enabling it.
#
# Review before running. Designed to be run section-by-section rather
# than blindly executed — comment out anything you don't want.
#
# Usage: chmod +x krdp-setup.sh && ./krdp-setup.sh

set -euo pipefail

# ---------------------------------------------------------------------
# 0. Config — adjust as needed
# ---------------------------------------------------------------------

KRDP_PORT="3389"
CERT_DIR="$HOME/.local/share/krdpserver"
CERT_PATH="$CERT_DIR/krdp.crt"
CERT_KEY_PATH="$CERT_DIR/krdp.key"
CERT_DAYS="3650"   # self-signed either way, so may as well make it long-lived

# Auto-logs the account below into SDDM so a Plasma session (and thus
# KRDP) is always running, even right after boot with nobody at the
# keyboard — immediately locked on start (see section 7), so this
# doesn't mean an open desktop, just one that exists for KRDP to attach
# to. Flip to false to skip both and leave login manual.
ENABLE_SDDM_AUTOLOGIN="true"
AUTOLOGIN_USER="$(whoami)"

# ---------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------
#
# KRDP is a KDE Plasma component (System Settings > Networking > Remote
# Desktop) — warn rather than bail if Plasma isn't detected, since the
# check isn't airtight (e.g. this could be run headless/over SSH into a
# Plasma session that just isn't the active seat).

if [[ "${XDG_CURRENT_DESKTOP:-}" != *KDE* ]]; then
  echo "Warning: XDG_CURRENT_DESKTOP is '${XDG_CURRENT_DESKTOP:-unset}', not KDE."
  echo "KRDP is a Plasma component — this may not do anything useful outside Plasma."
fi

# ---------------------------------------------------------------------
# 2. Packages
# ---------------------------------------------------------------------
#
# krdp: the RDP server binary + System Settings KCM. xdg-desktop-portal-kde
# backs the screen-capture/remote-desktop portal krdp uses under Wayland —
# already pulled in by plasma-desktop on most setups, but --needed makes
# this a no-op either way.

sudo pacman -S --needed --noconfirm krdp xdg-desktop-portal-kde openssl

# ---------------------------------------------------------------------
# 3. TLS certificate
# ---------------------------------------------------------------------
#
# krdp can autogenerate a certificate on every start instead, but that
# means a new, unpinned cert each time the service restarts. Generating
# one fixed self-signed cert here keeps it stable across restarts.

mkdir -p "$CERT_DIR"
if [[ -f "$CERT_PATH" && -f "$CERT_KEY_PATH" ]]; then
  echo "Certificate already exists at $CERT_PATH — leaving it alone."
else
  openssl req -nodes -new -x509 \
    -keyout "$CERT_KEY_PATH" -out "$CERT_PATH" \
    -days "$CERT_DAYS" -batch
  chmod 600 "$CERT_KEY_PATH"
  echo "Generated self-signed certificate at $CERT_PATH (valid $CERT_DAYS days)."
fi

# ---------------------------------------------------------------------
# 4. krdpserverrc
# ---------------------------------------------------------------------
#
# SystemUserEnabled authenticates against the current Linux account via
# PAM, so there's no separate KRDP username/password to manage — log in
# from the RDP client with the normal system username and password.
# (The alternative — per-user KRDP credentials stored in KWallet, the
# `Users` key — is only really practical to set up from the GUI KCM.)
#
# Keys match server/krdpserversettings.kcfg in the krdp source; kwriteconfig6
# resolves a bare --file name under ~/.config, same as the KCM does.

kwriteconfig6 --file krdpserverrc --group General --key Certificate "$CERT_PATH"
kwriteconfig6 --file krdpserverrc --group General --key CertificateKey "$CERT_KEY_PATH"
kwriteconfig6 --file krdpserverrc --group General --key AutogenerateCertificates false
kwriteconfig6 --file krdpserverrc --group General --key SystemUserEnabled true
kwriteconfig6 --file krdpserverrc --group General --key ListenPort "$KRDP_PORT"
kwriteconfig6 --file krdpserverrc --group General --key Autostart true

# ---------------------------------------------------------------------
# 5. Enable the service
# ---------------------------------------------------------------------
#
# krdp runs as a per-session systemd user unit, not a system service.
# `enable --now` starts it immediately and brings it back on future
# logins (belt-and-suspenders with the Autostart config key above,
# which is what the GUI toggle reads). Restarted, not just started, so
# an already-running instance picks up the config from step 4.

systemctl --user enable --now app-org.kde.krdpserver.service
systemctl --user restart app-org.kde.krdpserver.service

# ---------------------------------------------------------------------
# 6. Firewall
# ---------------------------------------------------------------------
#
# ufw skips rules that already exist, so this is safe to re-run. Only
# touched if ufw is installed and enabled; otherwise there's nothing to open.

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "^Status: active"; then
  sudo ufw allow "$KRDP_PORT"/tcp comment 'KRDP'
fi

# ---------------------------------------------------------------------
# 7. SDDM autologin (locked on start)
# ---------------------------------------------------------------------
#
# KRDP captures whatever graphical session is already running — it
# doesn't start one, so with nobody physically at the keyboard past the
# SDDM login screen, there's no session for it to attach to. Autologin
# fixes that, but on its own would mean this machine's session starts
# unlocked to anyone who can power it on. `LockOnStart` (kscreenlocker)
# closes that gap: the session comes up immediately locked, same as if
# you'd hit Meta+L yourself, so both a physical viewer and an RDP client
# connecting via KRDP land on the lock screen and need this account's
# password — a second factor on top of the NLA login the RDP connection
# itself already requires (SystemUserEnabled in step 4).
#
# `Relogin=true` re-triggers autologin if the session ever ends
# (logout, crash) instead of dropping back to a login screen KRDP can't
# get past remotely. Neither of these restarts SDDM or the session —
# doing that would kill whatever's running right now. They take effect
# on the next natural login/reboot; restart manually when ready (see
# the notes below).

if [[ "$ENABLE_SDDM_AUTOLOGIN" == "true" ]]; then
  sudo mkdir -p /etc/sddm.conf.d
  sudo kwriteconfig6 --file /etc/sddm.conf.d/kde_settings.conf --group Autologin --key User "$AUTOLOGIN_USER"
  sudo kwriteconfig6 --file /etc/sddm.conf.d/kde_settings.conf --group Autologin --key Relogin true
  kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnStart true
  echo "SDDM autologin + lock-on-start configured for '$AUTOLOGIN_USER' (takes effect on next login/reboot)."
else
  echo "SDDM autologin skipped (ENABLE_SDDM_AUTOLOGIN=false)."
fi

cat <<EOF

>>> KRDP should now be listening on 0.0.0.0:$KRDP_PORT. Verify with:
      systemctl --user status app-org.kde.krdpserver.service
      ss -tlnp | grep ":$KRDP_PORT"
    Connect with the normal Linux username/password for this machine, e.g.:
      xfreerdp /u:$(whoami) /v:<this-machine-ip>:$KRDP_PORT -clipboard
    GUI settings live at System Settings > Networking > Remote Desktop.

    Notes:
    - krdp listens on 0.0.0.0 by default with no IP allowlisting, so
      anything reaching $KRDP_PORT on the LAN can attempt to log in as
      any account on this machine (NLA is still enforced).
$(if [[ "$ENABLE_SDDM_AUTOLOGIN" == "true" ]]; then cat <<EOF2
    - SDDM autologin + lock-on-start are now configured but not yet
      active for this boot. They won't apply until the next reboot, or
      until you deliberately restart SDDM yourself (this will kill your
      current session):
        sudo systemctl restart sddm.service
      Until then, KRDP still needs someone to log in locally at least once.
      After that takes effect, the session comes up locked on every
      login — connecting over KRDP lands on the lock screen, and this
      account's normal password unlocks it, same as at the keyboard.
EOF2
else cat <<EOF2
    - No SDDM autologin was configured. KRDP has nothing to attach to
      until someone logs into Plasma locally (set
      ENABLE_SDDM_AUTOLOGIN=true above to automate that, with the
      unlocked-session trade-off that comes with it).
EOF2
fi)
EOF

echo ""
echo "=== Done. ==="
