#!/usr/bin/env bash
#
# bitwarden-ssh-agent.sh
#
# Wires SSH_AUTH_SOCK to Bitwarden desktop's built-in SSH agent, so ssh
# (and anything that shells out to it) uses keys stored in the vault
# instead of files under ~/.ssh.
#
# Requires: Bitwarden desktop installed (see desktop-software.sh) with
# Settings > SSH agent turned on, and the app running (or set to start
# on login / minimize to tray instead of quitting) for the socket to
# actually exist.
#
# Review before running. Designed to be run section-by-section rather
# than blindly executed — comment out anything you don't want.
#
# Usage: chmod +x bitwarden-ssh-agent.sh && ./bitwarden-ssh-agent.sh

set -euo pipefail

# ---------------------------------------------------------------------
# 1. Locate the agent socket
# ---------------------------------------------------------------------
#
# The socket path depends on how Bitwarden desktop was installed.
# desktop-software.sh installs the native AUR package (`bitwarden`), so
# that path is the default/preferred match here — the flatpak path
# (com.bitwarden.desktop, .var/app/...) is what Bazzite/atomic setups
# use instead, and is checked as a fallback in case of a different
# install method.

CANDIDATES=(
  "$HOME/.bitwarden-ssh-agent.sock"                                     # native (AUR/pacman)
  "$HOME/.var/app/com.bitwarden.desktop/data/.bitwarden-ssh-agent.sock" # flatpak
  "$HOME/snap/bitwarden/current/.bitwarden-ssh-agent.sock"              # snap
)

SOCK=""
for CANDIDATE in "${CANDIDATES[@]}"; do
  if [[ -S "$CANDIDATE" ]]; then
    SOCK="$CANDIDATE"
    echo "Found live agent socket: $SOCK"
    break
  fi
done

if [[ -z "$SOCK" ]]; then
  SOCK="${CANDIDATES[0]}"
  echo "No live socket found yet — defaulting to the native-install path:" >&2
  echo "  $SOCK" >&2
  echo "It will appear there once SSH agent is enabled in Bitwarden's" >&2
  echo "Settings and the app has been unlocked at least once." >&2
fi

# ---------------------------------------------------------------------
# 2. Wire up SSH_AUTH_SOCK
# ---------------------------------------------------------------------

for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$RC" ]] || continue
  if ! grep -qF 'bitwarden-ssh-agent.sock' "$RC" 2>/dev/null; then
    echo "export SSH_AUTH_SOCK=\"$SOCK\"" >>"$RC"
    echo "Added SSH_AUTH_SOCK to $RC"
  else
    echo "$RC already wires up SSH_AUTH_SOCK — leaving it alone."
  fi
done

cat <<EOF
>>> Done wiring the shell env. Next steps:
    1. In Bitwarden desktop: Settings > SSH agent > enable it.
    2. Keep Bitwarden desktop running (enable "start on login" / close
       to tray rather than quitting) so the socket stays alive for the
       whole session.
    3. Open a new shell (or 'source ~/.bashrc'), then verify:
         ssh-add -l
       Each key use prompts a Bitwarden approval dialog the first time
       per session.
EOF

echo ""
echo "=== Done. ==="
