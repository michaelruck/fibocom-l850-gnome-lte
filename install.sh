#!/bin/bash
# install.sh — set up fibocom-l850-gnome-lte on this machine.
#
# Installs the helper scripts, system configuration, polkit policy and the
# GNOME Shell extension, then enables the bring-up service. Run with sudo.
#
#   sudo ./install.sh [--xmm7360-dir DIR] [--build] [--no-enable]
#
#   --xmm7360-dir DIR  Path to your xmm7360-pci checkout (default /opt/xmm7360-pci)
#   --build            Build + install the xmm7360 kernel module for this kernel
#   --no-enable        Install files but do not enable/start the service
#
# Part of fibocom-l850-gnome-lte. SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

XMM7360_DIR=/opt/xmm7360-pci
DO_BUILD=0
DO_ENABLE=1

while [ "$#" -gt 0 ]; do
    case "$1" in
        --xmm7360-dir) XMM7360_DIR="$2"; shift 2 ;;
        --build)       DO_BUILD=1; shift ;;
        --no-enable)   DO_ENABLE=0; shift ;;
        -h|--help)     sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root:  sudo $0 $*" >&2
    exit 1
fi

# The login user who will own the extension + use the toggle.
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = root ]; then
    echo "Could not determine your login user. Run via 'sudo', not as root directly." >&2
    exit 1
fi
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
SRC="$(cd "$(dirname "$0")" && pwd)"

echo "==> Installing for user: $TARGET_USER"
echo "==> xmm7360-pci dir:     $XMM7360_DIR"

if [ ! -f "$XMM7360_DIR/rpc/open_xdatachannel.py" ]; then
    echo "WARNING: $XMM7360_DIR/rpc/open_xdatachannel.py not found."
    echo "         Clone the driver first, e.g.:"
    echo "         sudo git clone https://github.com/xmm7360/xmm7360-pci $XMM7360_DIR"
fi

# --- helper scripts ----------------------------------------------------------
echo "==> Installing helper scripts to /usr/local/bin"
install -m 0755 "$SRC/bin/fibocom-l850-up"     /usr/local/bin/
install -m 0755 "$SRC/bin/fibocom-l850-ctl"    /usr/local/bin/
install -m 0755 "$SRC/bin/fibocom-l850-status" /usr/local/bin/
install -m 0755 "$SRC/bin/fibocom-l850-apn"    /usr/local/bin/

# --- configuration -----------------------------------------------------------
echo "==> Installing configuration to /etc/fibocom-l850-lte"
install -d -m 0755 /etc/fibocom-l850-lte
if [ -f /etc/fibocom-l850-lte/modem.conf ]; then
    echo "    Keeping existing modem.conf"
else
    install -m 0644 "$SRC/etc/fibocom-l850-lte/modem.conf" /etc/fibocom-l850-lte/modem.conf
fi
# Always refresh the operators list (user edits are expected in their own rows,
# but the shipped table is informational and safe to update).
install -m 0644 "$SRC/etc/fibocom-l850-lte/operators.csv" /etc/fibocom-l850-lte/operators.csv
# Point the config at the chosen driver dir.
sed -i -E "s|^XMM7360_DIR=.*|XMM7360_DIR=${XMM7360_DIR}|" /etc/fibocom-l850-lte/modem.conf

install -m 0644 "$SRC/etc/modprobe.d/blacklist-iosm.conf" /etc/modprobe.d/blacklist-iosm.conf
install -m 0644 "$SRC/etc/modules-load.d/xmm7360.conf"    /etc/modules-load.d/xmm7360.conf
install -m 0644 "$SRC/etc/systemd/system/fibocom-l850-up.service" /etc/systemd/system/fibocom-l850-up.service

# Stop ModemManager from grabbing the modem and showing a phantom toggle.
echo "==> Installing udev rule to keep ModemManager off the modem"
install -m 0644 "$SRC/etc/udev/rules.d/99-fibocom-l850-mm-ignore.rules" /etc/udev/rules.d/99-fibocom-l850-mm-ignore.rules
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=tty --subsystem-match=net 2>/dev/null || true
systemctl restart ModemManager 2>/dev/null || true

# --- sudoers (passwordless toggle) ------------------------------------------
echo "==> Installing sudoers rule for $TARGET_USER"
SUDO_TMP="$(mktemp)"
sed "s/__USER__/$TARGET_USER/" "$SRC/etc/sudoers.d/fibocom-l850-lte" > "$SUDO_TMP"
if visudo -cf "$SUDO_TMP" >/dev/null; then
    install -m 0440 "$SUDO_TMP" /etc/sudoers.d/fibocom-l850-lte
else
    echo "ERROR: generated sudoers file failed validation, not installing." >&2
    rm -f "$SUDO_TMP"; exit 1
fi
rm -f "$SUDO_TMP"

# --- polkit ------------------------------------------------------------------
echo "==> Installing polkit policy"
install -d -m 0755 /usr/share/polkit-1/actions
install -m 0644 "$SRC/polkit/org.fibocom.l850.policy" /usr/share/polkit-1/actions/org.fibocom.l850.policy

# --- GNOME extension (installed for the login user) --------------------------
UUID="fibocom-l850-lte@michaelruck.github.io"
EXT_SRC="$SRC/gnome-extension/$UUID"
EXT_DEST="$USER_HOME/.local/share/gnome-shell/extensions/$UUID"
echo "==> Installing GNOME extension to $EXT_DEST"
sudo -u "$TARGET_USER" mkdir -p "$EXT_DEST"
cp -r "$EXT_SRC/." "$EXT_DEST/"
if command -v glib-compile-schemas >/dev/null; then
    glib-compile-schemas "$EXT_DEST/schemas"
fi
chown -R "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$EXT_DEST"

# --- optional: build the kernel module --------------------------------------
if [ "$DO_BUILD" -eq 1 ]; then
    echo "==> Building xmm7360 kernel module for $(uname -r)"
    if [ ! -f "$XMM7360_DIR/Makefile" ]; then
        echo "ERROR: no Makefile in $XMM7360_DIR — cannot build." >&2; exit 1
    fi
    make -C "$XMM7360_DIR" clean
    make -C "$XMM7360_DIR"
    install -D "$XMM7360_DIR/xmm7360.ko" "/lib/modules/$(uname -r)/extra/xmm7360.ko"
    depmod -a
    modprobe xmm7360 || true
fi

# --- enable + start ----------------------------------------------------------
systemctl daemon-reload
if [ "$DO_ENABLE" -eq 1 ]; then
    echo "==> Enabling fibocom-l850-up.service"
    systemctl enable fibocom-l850-up.service
    echo "    (start it now with: sudo systemctl start fibocom-l850-up.service)"
fi

cat <<EOF

Done.

Next steps:
  1. Make sure the xmm7360 module is loaded (built for your current kernel).
     If you did not pass --build, build it per the README.
  2. Set your APN: edit /etc/fibocom-l850-lte/modem.conf, OR use the extension
     preferences (it will ask for your password).
  3. Log out and back in so GNOME Shell loads the extension, then enable it:
       gnome-extensions enable $UUID
  4. The "Mobile Data" toggle appears in the Quick Settings panel.

EOF
