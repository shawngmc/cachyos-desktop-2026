#!/usr/bin/env bash
#
# container-software.sh
#
# Container support for Shawn's desktop on CachyOS: rootless Podman +
# Buildah + Skopeo, a Docker-CLI compat shim, and the rootless socket
# wiring that tools like lazydocker/dive expect.
#
# Review before running. Designed to be run section-by-section rather
# than blindly executed — comment out anything you don't want.
#
# Usage: chmod +x container-software.sh && ./container-software.sh

set -euo pipefail

# ---------------------------------------------------------------------
# 0. Preflight
# ---------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
  echo "Do not run this script as root — rootless Podman setup needs to" >&2
  echo "run as your normal user (it will sudo when needed)." >&2
  exit 1
fi

# ---------------------------------------------------------------------
# 1. Podman, Buildah, Skopeo
# ---------------------------------------------------------------------
#
# All three are official-repo packages — no AUR needed. Buildah builds
# images, Skopeo copies/inspects images across registries without
# needing a running daemon, Podman runs/manages containers and pods.

sudo pacman -S --needed --noconfirm podman podman-compose buildah skopeo

# ---------------------------------------------------------------------
# 2. Docker CLI compatibility shim
# ---------------------------------------------------------------------
#
# podman-docker provides a `docker` command (and docker.service/
# docker.socket unit aliases) that forward to Podman, for tooling/
# scripts that shell out to `docker` directly. Skip this section if
# you'd rather keep `docker` unambiguous, or if the real Docker Engine
# is ever installed alongside this (they conflict).

sudo pacman -S --needed --noconfirm podman-docker

# ---------------------------------------------------------------------
# 3. Rootless setup — subuid/subgid ranges
# ---------------------------------------------------------------------
#
# Rootless Podman maps container UIDs/GIDs into a range delegated to
# your user via /etc/subuid and /etc/subgid. Arch's useradd has
# auto-assigned these for new users since 2022, but accounts created
# before that (or otherwise missing entries) need it done by hand.

if ! grep -q "^${USER}:" /etc/subuid 2>/dev/null || ! grep -q "^${USER}:" /etc/subgid 2>/dev/null; then
  echo "No subuid/subgid range found for $USER — assigning one." >&2
  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"
  echo "Assigned. Log out and back in (or reboot) before using rootless containers." >&2
else
  echo "subuid/subgid range already present for $USER."
fi

# ---------------------------------------------------------------------
# 4. Rootless socket — Docker-API compatibility for tooling
# ---------------------------------------------------------------------
#
# lazydocker, docker-compose-style tooling, and IDE Docker integrations
# talk to a Docker-API socket. Podman's user-level socket at
# $XDG_RUNTIME_DIR/podman/podman.sock serves that API.

systemctl --user enable --now podman.socket

# Keeps the rootless socket (and any containers set to run persistently)
# alive after you log out, not just while a session is active.
sudo loginctl enable-linger "$USER"

for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$RC" ]] || continue
  if ! grep -qF 'DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/podman/podman.sock' "$RC" 2>/dev/null; then
    echo 'export DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/podman/podman.sock' >>"$RC"
    echo "Added DOCKER_HOST to $RC"
  fi
done

cat <<'EOF'
>>> Podman is set up rootless. Quick sanity check once you've opened a
    new shell (to pick up DOCKER_HOST):
      podman info
      docker ps          # via the podman-docker shim
      lazydocker         # should pick up the rootless socket
EOF

echo ""
echo "=== Done. ==="
