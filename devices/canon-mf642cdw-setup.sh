#!/usr/bin/env bash
# Set up the Canon imageCLASS MF642Cdw printer/scanner on CachyOS / Arch.
#
# Stub: nothing is automated yet; this only prints the manual steps.
# Canon's official "UFR II/UFRII LT Printer Driver for Linux" lists the
# MF642Cdw as supported, but it's a manual download from Canon's support site.
# CUPS, SANE (+ sane-airscan) and system-config-printer come from hardware.sh
# section 1.
#
# TODO: automate the driver install and queue setup (lpadmin) once the
# download URL / AUR options are checked.
set -euo pipefail

cat <<'EOF'
>>> Canon imageCLASS MF642Cdw (stub): download the "UFR II/UFRII LT
    Printer Driver for Linux" from Canon's support site (search
    "imageCLASS MF642Cdw Linux driver"), then:
      tar xf linux-UFRII*.tar.gz
      cd linux-UFRII*/
      sudo ./install.sh
    It installs as a CUPS backend. Add the printer with
    system-config-printer or the CUPS web UI (http://localhost:631).
    It's on Ethernet, so use the IPP/socket queue with its LAN IP, or
    mDNS/Bonjour discovery if avahi is running.
EOF
