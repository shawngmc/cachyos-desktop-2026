# cachyos-desktop-2026

Setup scripts for Shawn's CachyOS desktop. Each script is meant to be reviewed
and can be run section by section; see its header for details and options.

## Before you start

- A working CachyOS install with KDE Plasma, logged in as your normal user.
- An AUR helper (`paru` or `yay`). CachyOS ships `paru`.
- The `[multilib]` repo enabled in `/etc/pacman.conf`, which `gaming-software.sh`
  needs for Steam.

## Run order

Run these as your normal user, not root. The scripts call `sudo` themselves
where needed.

| # | Script | Needs | Afterwards |
|---|--------|-------|------------|
| 1 | `switch-to-bash.sh` | | Log out and back in |
| 2 | `desktop-software.sh` | | |
| 3 | `hardware.sh` | 2 | Reboot |
| 4 | `cli-software.sh` | 3 | Open a new shell |
| 5 | `container-software.sh` | | Log out and back in if it says so |
| 6 | `gaming-software.sh` | 2 | |
| 7 | Any of the scripts below | See below | |

Why this order:

1. **`switch-to-bash.sh`** goes first because CachyOS defaults to fish. Steps 4
   and 5 add their setup to `~/.bashrc`, and that only takes effect once bash
   is your login shell.
2. **`desktop-software.sh`** sets up Flatpak and Flathub and installs Gear Lever.
   `gaming-software.sh` (RomMix) and `devices/creality-k2-setup.sh` both use Gear
   Lever to install their AppImages. It also installs Bitwarden desktop, which
   `bitwarden-ssh-agent.sh` needs.
3. **`hardware.sh`** installs drivers and system services (CUPS/SANE, ddcutil,
   Input Remapper), then runs every executable script in `devices/` in name
   order. A device script that fails, for example because the device is
   unplugged, is reported but doesn't stop the run. Rerun that one script
   later.
4. **`cli-software.sh`** installs Homebrew and the tools in `packages.yaml`. It
   leaves out `mpv` because `hardware.sh` already installs it.
5. **`container-software.sh`** sets up rootless Podman. It has no dependencies
   on the other scripts.
6. **`gaming-software.sh`** installs Steam, Battle.net/WoW, Heroic, RomMix,
   GeForce NOW and related tools. If Gear Lever is missing, it skips RomMix.

### Optional, after their prerequisites

| Script | Needs |
|--------|-------|
| `smb-mounts.sh` | Nothing; edit the config section first |
| `krunner.sh` | Nothing; it installs `bitwarden-cli` itself |
| `bitwarden-ssh-agent.sh` | Step 2, plus Bitwarden desktop logged in with Settings > SSH agent turned on |
| `kvm-switch-setup.sh` | Step 3 (`devices/elgato-stream-deck-setup.sh` provides StreamController) |
| `krdp-setup.sh` | Nothing; read section 7 (autologin) before running |

## Re-running

The scripts are safe to run again. Package installs use `--needed`, and config
edits check for an existing entry before adding one. The AppImage installs
(RomMix, Creality Print) fetch the latest release and replace the copy Gear
Lever already has, so running them again is also how you update those apps.
