#!/usr/bin/env bash
#
# krunner.sh
#
# KRunner plugin setup for Shawn's desktop on CachyOS. Installs:
#
#   - KrunnerBitwarden (martininsulander/KrunnerBitwarden): search the
#     Bitwarden vault via `bw` and copy a password to the clipboard.
#     Not in the AUR — deployed from source as a per-user install
#     under ~/.local/share.
#
# Review before running. Designed to be run section-by-section rather
# than blindly executed — comment out anything you don't want.
#
# Usage: chmod +x krunner.sh && ./krunner.sh

set -euo pipefail

# ---------------------------------------------------------------------
# 0. Config
# ---------------------------------------------------------------------

XDG_DATA_HOME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
PLUGIN_SRC_DIR="$XDG_DATA_HOME_DIR/krunner-plugins"

BITWARDEN_RUNNER_REPO="https://github.com/martininsulander/KrunnerBitwarden.git"
BITWARDEN_RUNNER_DIR="$PLUGIN_SRC_DIR/bitwarden-runner"

clone_or_update() {
  local repo_url="$1" dest="$2"
  if [[ -d "$dest/.git" ]]; then
    echo "Updating existing clone at $dest"
    git -C "$dest" pull --ff-only
  else
    echo "Cloning $repo_url to $dest"
    mkdir -p "$(dirname "$dest")"
    git clone --depth 1 "$repo_url" "$dest"
  fi
}

# ---------------------------------------------------------------------
# 1. Dependencies
# ---------------------------------------------------------------------
#
# git for cloning the Bitwarden runner below; python-dbus +
# python-gobject for its D-Bus/GLib main loop; kdialog for its
# unlock/password prompts; bitwarden-cli for the `bw` binary it
# shells out to.

sudo pacman -S --needed --noconfirm git python-dbus python-gobject kdialog bitwarden-cli

# ---------------------------------------------------------------------
# 2. KrunnerBitwarden (search the vault, copy a password to clipboard)
# ---------------------------------------------------------------------
#
# Its own install.sh is correct for a per-user install — it copies
# itself under ~/.local/share/krunner, registers a KRunner dbusplugin,
# adds an autostart entry, and (re)launches the backend process — so
# it's used as-is rather than reimplemented here. Requires the repo's
# working directory as cwd (it copies files relative to $PWD).

clone_or_update "$BITWARDEN_RUNNER_REPO" "$BITWARDEN_RUNNER_DIR"
( cd "$BITWARDEN_RUNNER_DIR" && bash install.sh )

# ---------------------------------------------------------------------
# 3. Restart KRunner
# ---------------------------------------------------------------------
#
# Picks up the newly registered plugins; KRunner relaunches
# automatically the next time it's invoked (Alt+Space / Alt+F2).

kquitapp6 krunner 2>/dev/null || true

cat <<EOF
>>> Done. Next steps:
    1. Open System Settings > Search > KRunner Plugins and confirm
       "Bitwarden passwords" is enabled (ships enabled by default,
       but worth a check on first install).
    2. Log into the vault once so 'bw' has a session:
         bw login
    3. Open KRunner (Alt+Space) and try:
         pass <search term>     — lists matching vault entries;
                                   selecting one copies the password
                                   to the clipboard
    Re-run this script anytime to pull updates for the Bitwarden
    runner (git pull under $PLUGIN_SRC_DIR).
EOF

echo ""
echo "=== Done. ==="
