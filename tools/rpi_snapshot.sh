#!/bin/bash
# Pull a config snapshot of the RPi to the NAS. Run from Windows / WSL / Git Bash.
# Captures everything we've manually changed so it can be restored after reflash.
#
# Snapshot includes:
#   - /boot/firmware/{config,cmdline}.txt
#   - /etc/udev/rules.d/99-teensy.rules
#   - /etc/systemd/system/* (overrides + mask symlinks + service edges)
#   - /etc/NetworkManager/system-connections/* (WiFi creds — keep snapshots private!)
#   - /etc/plymouth/
#   - ~/.config/{libfm,autostart}/
#   - ~/Desktop/silvia.desktop
#   - List of disabled + masked services
#   - List of installed apt packages
#
# Output: tools/rpi-state-snapshots/silvia-rpi-snapshot-YYYY-MM-DD-HHMM.tar.gz
#
# Usage: ./rpi_snapshot.sh [pi-host] [pi-user]
#        defaults: 192.168.1.33  gram

set -euo pipefail

PI_HOST="${1:-192.168.1.33}"
PI_USER="${2:-gram}"
PI_PW="${SILVIA_RPI_PW:-gram}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT_DIR="$PROJECT_ROOT/tools/rpi-state-snapshots"

PLINK="/c/Program Files/PuTTY/plink.exe"
PSCP="/c/Program Files/PuTTY/pscp.exe"

mkdir -p "$SNAPSHOT_DIR"
TS=$(date +%Y-%m-%d-%H%M)
TARBALL_NAME="silvia-rpi-snapshot-$TS.tar.gz"
PI_TMP="/tmp/$TARBALL_NAME"

echo "==> Building snapshot on $PI_HOST..."
"$PLINK" -ssh -batch -pw "$PI_PW" "$PI_USER@$PI_HOST" "
sudo systemctl list-unit-files --state=disabled,masked --no-pager > /tmp/disabled-masked-services.txt
sudo apt list --installed 2>/dev/null > /tmp/installed-packages.txt
sudo tar -czf $PI_TMP \
  --absolute-names \
  /boot/firmware/config.txt \
  /boot/firmware/cmdline.txt \
  /etc/udev/rules.d/99-teensy.rules \
  /etc/systemd/system/ \
  /etc/NetworkManager/system-connections/ \
  /etc/NetworkManager/conf.d/ \
  /etc/systemd/network/ \
  /etc/wpa_supplicant/ \
  /etc/plymouth/ \
  /home/$PI_USER/.config/libfm/ \
  /home/$PI_USER/.config/autostart/ \
  /home/$PI_USER/Desktop/silvia.desktop \
  /tmp/disabled-masked-services.txt \
  /tmp/installed-packages.txt \
  2>/dev/null
ls -la $PI_TMP
"

echo "==> Pulling to $SNAPSHOT_DIR/..."
"$PSCP" -pw "$PI_PW" -batch "$PI_USER@$PI_HOST:$PI_TMP" "$SNAPSHOT_DIR/"

echo
echo "Snapshot saved: $SNAPSHOT_DIR/$TARBALL_NAME"
ls -la "$SNAPSHOT_DIR/$TARBALL_NAME"
