#!/usr/bin/env bash
#
# cli-software.sh
#
# CLI tooling installer for Shawn's desktop on CachyOS.
#
# Review before running. Designed to be run section-by-section rather
# than blindly executed — comment out anything you don't want.
#
# Usage: chmod +x cli-software.sh && ./cli-software.sh

set -euo pipefail

# Keep brew from stopping to ask for confirmation (e.g. the analytics
# prompt on first run) — applies to the installer and every `brew`
# command below, not just install.sh.
export NONINTERACTIVE=1

# ---------------------------------------------------------------------
# 0. Preflight
# ---------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
  echo "Do not run this script as root — Homebrew's installer refuses to" >&2
  echo "run as root. Run it as your normal user (it will sudo when needed)." >&2
  exit 1
fi

# ---------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------
#
# Homebrew on Linux (Linuxbrew) needs base-devel + a few libs to build
# bottled/source formulae, plus curl/git for the installer itself.

sudo pacman -S --needed --noconfirm \
  base-devel \
  procps-ng \
  curl \
  git \
  file

if command -v brew >/dev/null 2>&1; then
  echo "Homebrew already installed: $(command -v brew)"
else
  /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Homebrew installs to /home/linuxbrew/.linuxbrew for a multi-user
# setup, or ~/.linuxbrew if it can't get sudo. Detect whichever it
# used and wire up the shell env.
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  BREW_BIN=/home/linuxbrew/.linuxbrew/bin/brew
elif [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
  BREW_BIN="$HOME/.linuxbrew/bin/brew"
else
  echo "Could not locate brew after install — check output above." >&2
  exit 1
fi

eval "$("$BREW_BIN" shellenv)"

for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$RC" ]] || continue
  if ! grep -qF "$BREW_BIN shellenv" "$RC" 2>/dev/null; then
    echo "eval \"\$($BREW_BIN shellenv)\"" >>"$RC"
    echo "Added brew shellenv to $RC"
  fi
done

echo "Homebrew version: $(brew --version | head -n1)"

# ---------------------------------------------------------------------
# 2. Package wishlist (packages.yaml)
# ---------------------------------------------------------------------
#
# packages.yaml holds the CLI tool wishlist from "Better Linux Commands
# Cheatsheet.xlsx", grouped by category. Comment out a line there (and
# rerun) to skip a package — nothing to edit here.
#
# `brew` itself and `mpv` (already installed via pacman in hardware.sh)
# are intentionally left out of packages.yaml.

PACKAGES_YAML="$(dirname "${BASH_SOURCE[0]}")/packages.yaml"

# yq (mikefarah/yq) drives the parsing below, so make sure it's present
# even if it's been commented out of the wishlist itself.
brew install --quiet yq

mapfile -t BREW_PKGS < <(yq -r '.brew[][]' "$PACKAGES_YAML")
mapfile -t PACMAN_PKGS < <(yq -r '.pacman[]' "$PACKAGES_YAML")
mapfile -t PIP_PKGS < <(yq -r '.pip[]' "$PACKAGES_YAML")

[[ ${#BREW_PKGS[@]} -gt 0 ]] && brew install "${BREW_PKGS[@]}"
[[ ${#PACMAN_PKGS[@]} -gt 0 ]] && sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

# CachyOS's system Python is externally managed (PEP 668), so a plain
# `pip install` is refused. Use pipx instead — it installs each package
# into its own isolated venv and exposes its CLI entry points on PATH.
#
# python-pillow is pulled in explicitly and pipx is told to reuse system
# site-packages: CachyOS tracks Python closely, so C-extension deps like
# Pillow often lack prebuilt wheels for it yet and pip falls back to
# compiling from source, which can fail against the system's newer
# libwebp/etc. headers. Pacman's build is precompiled correctly, so
# reusing it sidesteps that entirely.
if [[ ${#PIP_PKGS[@]} -gt 0 ]]; then
  sudo pacman -S --needed --noconfirm python-pipx python-pillow
  for PKG in "${PIP_PKGS[@]}"; do
    pipx install --system-site-packages "$PKG"
  done
fi

echo ""
echo "=== Done. Open a new shell (or 'source ~/.bashrc') to pick up brew on PATH. ==="
