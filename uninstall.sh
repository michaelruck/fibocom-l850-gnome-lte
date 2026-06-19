#!/bin/bash
# uninstall.sh — remove fibocom-l850-gnome-lte from this machine.
#
#   sudo ./uninstall.sh [--purge]
#
#   --purge  Also remove /etc/fibocom-l850-lte (your APN config) and the
#            iosm blacklist / module-load drop-ins.
#
# Does NOT touch your xmm7360-pci checkout or the installed kernel module.
#
# Part of fibocom-l850-gnome-lte. SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root:  sudo $0 $*" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || true)"
UUID="fibocom-l850-lte@michaelruck.github.io"

echo "==> Disabling + removing service"
systemctl disable --now fibocom-l850-up.service 2>/dev/null || true
rm -f /etc/systemd/system/fibocom-l850-up.service
systemctl daemon-reload

echo "==> Removing helper scripts"
rm -f /usr/local/bin/fibocom-l850-up \
      /usr/local/bin/fibocom-l850-ctl \
      /usr/local/bin/fibocom-l850-status \
      /usr/local/bin/fibocom-l850-apn

echo "==> Removing sudoers + polkit"
rm -f /etc/sudoers.d/fibocom-l850-lte
rm -f /usr/share/polkit-1/actions/org.fibocom.l850.policy

if [ -n "$USER_HOME" ]; then
    echo "==> Removing GNOME extension"
    rm -rf "$USER_HOME/.local/share/gnome-shell/extensions/$UUID"
fi

if [ "$PURGE" -eq 1 ]; then
    echo "==> Purging config + module drop-ins"
    rm -rf /etc/fibocom-l850-lte
    rm -f /etc/modprobe.d/blacklist-iosm.conf
    rm -f /etc/modules-load.d/xmm7360.conf
else
    echo "    Keeping /etc/fibocom-l850-lte and module drop-ins (use --purge to remove)."
fi

echo "Done."
