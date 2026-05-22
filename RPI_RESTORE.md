# RPi state — backup + restore

How to capture the current state of the Pi (config files, service trims,
WiFi credentials, etc.) and how to put a freshly-flashed Pi back into the
same state — either from a snapshot tarball, or from scratch.

## What's a snapshot?

`tools/rpi_snapshot.sh` SSHes into the Pi and tarballs the *small* set of
files we've manually changed. ~25 KB. Saved to
`tools/rpi-state-snapshots/silvia-rpi-snapshot-YYYY-MM-DD-HHMM.tar.gz`.

**Important**: snapshot includes `/etc/NetworkManager/system-connections/`
which contains the WiFi PSK in plaintext-ish form. Snapshots are gitignored
but treat them like passwords — they live on the NAS only.

### Take a snapshot

```bash
bash "L:/PROJECTS/silvia lever/tools/rpi_snapshot.sh"
# Or with overrides:
bash "L:/PROJECTS/silvia lever/tools/rpi_snapshot.sh" 192.168.1.33 gram
```

### Files included in a snapshot

| Path | Why |
|------|-----|
| `/boot/firmware/config.txt` | `disable_splash`, `dtoverlay=disable-bt`, etc. |
| `/boot/firmware/cmdline.txt` | kernel-quiet flags + `fastboot` |
| `/etc/udev/rules.d/99-teensy.rules` | Teensy serial perms + ModemManager-ignore |
| `/etc/systemd/system/` | Masked services (cloud-init, plymouth, etc.) + drop-in overrides |
| `/etc/NetworkManager/system-connections/` | NM connection profile (kept as fallback even though NM is disabled) |
| `/etc/NetworkManager/conf.d/` | NM tweaks (none currently) |
| `/etc/systemd/network/25-wlan0.network` | networkd IP config (DHCP) |
| `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` | WiFi PSK for networkd path |
| `/etc/plymouth/` | Plymouth theme config |
| `~/.config/libfm/` | pcmanfm `single_click=1`, `quick_exec=1` |
| `~/.config/autostart/silvia.desktop` | UI auto-launch entry |
| `~/Desktop/silvia.desktop` | Tap-to-launch icon |
| `disabled-masked-services.txt` | Audit list of every disabled/masked unit |
| `installed-packages.txt` | Audit list of `apt list --installed` |

---

## Path A — Restore from snapshot (fast)

Assumes a fresh Pi OS Bookworm with SSH enabled and on the network. Replace
`<TS>` with the snapshot timestamp.

```bash
# 1. Push snapshot to the new Pi
PSCP="/c/Program Files/PuTTY/pscp.exe"
"$PSCP" -pw gram \
    "L:/PROJECTS/silvia lever/tools/rpi-state-snapshots/silvia-rpi-snapshot-<TS>.tar.gz" \
    gram@<NEW_PI_IP>:/tmp/

# 2. Push the project tree (so silvia + setup_rpi.sh land in place)
"$PSCP" -r -pw gram "L:/PROJECTS/silvia lever/ui" gram@<NEW_PI_IP>:/home/gram/silvia-lever/

# 3. SSH to Pi, restore the snapshot, run the standard setup script
ssh gram@<NEW_PI_IP>
cd /
sudo tar -xzf /tmp/silvia-rpi-snapshot-<TS>.tar.gz
# Restores all the absolute paths inside the tarball.

# Apply systemd state changes captured in the audit list. setup_rpi.sh
# replays the same disable/mask commands, so running it brings the new
# Pi into the right state:
bash /home/gram/silvia-lever/ui/rpi/setup_rpi.sh

sudo reboot
```

After reboot, `systemd-analyze` should show ~15 s and the UI should
auto-launch.

---

## Path B — Restore from scratch (no snapshot, manual)

If a snapshot is missing or corrupt, the Pi can be rebuilt from the project
tree alone. The complete sequence is encoded in `setup_rpi.sh` — running
it on a freshly-flashed Pi reproduces the entire state EXCEPT WiFi
credentials (which can't be derived from the repo). For WiFi:

```bash
sudo nmcli c add type wifi con-name "<your-ssid>" ifname wlan0 ssid "<your-ssid>"
sudo nmcli c modify "<your-ssid>" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "<password>"
sudo nmcli c up "<your-ssid>"
```

Then run `bash /home/gram/silvia-lever/ui/rpi/setup_rpi.sh` and reboot.

---

## Reverting a SINGLE change

Common rollbacks — every change has an inverse:

### Re-enable a service we disabled

```bash
sudo systemctl unmask <name>     # if it was masked
sudo systemctl enable --now <name>
```

Common candidates: `bluetooth`, `cups`, `ModemManager`,
`NetworkManager-wait-online`, `cloud-init*`.

### Restore the rainbow + Plymouth splash

```bash
sudo sed -i 's|^disable_splash=1|#disable_splash=1|' /boot/firmware/config.txt
sudo sed -i 's| loglevel=3||; s| vt.global_cursor_default=0||; s| logo.nologo||; s| fastboot||' /boot/firmware/cmdline.txt
sudo systemctl unmask plymouth-start.service plymouth-quit.service plymouth-quit-wait.service plymouth-read-write.service
sudo plymouth-set-default-theme pix    # the Pi-branded splash
sudo update-initramfs -u
sudo reboot
```

### Re-enable Bluetooth

```bash
sudo sed -i '/^dtoverlay=disable-bt/d' /boot/firmware/config.txt
sudo systemctl unmask bluetooth
sudo systemctl enable --now bluetooth
```

### Stop UI auto-launching at boot

```bash
rm ~/.config/autostart/silvia.desktop
```

### Stop the desktop tap-icon launching the UI

```bash
rm ~/Desktop/silvia.desktop
```

### Restore IPv6 on NM connections

```bash
for conn in $(sudo nmcli -t -f NAME c show); do
    sudo nmcli c modify "$conn" ipv6.method auto 2>/dev/null
done
```

### Fully wipe pcmanfm UX changes

```bash
rm ~/.config/libfm/libfm.conf    # pcmanfm regenerates default on next start
```

---

## Deadman switch — `silvia-deadman`

Installed to `/usr/local/bin/silvia-deadman` by `setup_rpi.sh`. Generic
auto-rollback timer for risky changes. Pattern:

```bash
# Take a backup
sudo cp -a /etc/NetworkManager /var/backups/NetworkManager.bak

# Arm the deadman: if I'm not back in 10 min, restore + reboot
sudo silvia-deadman arm 10 \
    "rsync -a --delete /var/backups/NetworkManager.bak/ /etc/NetworkManager/ && systemctl restart NetworkManager && reboot"

# Make the change, reboot, log back in...
sudo systemctl mask NetworkManager
sudo systemctl enable systemd-networkd
sudo reboot

# After reboot, if I can SSH in:
sudo silvia-deadman confirm    # all good, cancel the timer

# If I can't SSH in within 10 minutes:
# → timer fires → restore script runs → Pi reboots back to known-good NM
```

Inspect / manage:

```bash
silvia-deadman status     # what's pending and when does it fire
sudo silvia-deadman cancel    # alias of confirm
```

### When to use it

Risky changes that could lock you out of the Pi:
- Network manager swap (NM ↔ systemd-networkd)
- WiFi credential rotation
- Direct edits to `NetworkManager.service`, `networking.service`
- Firewall rules
- udev rules that touch the network interface

**Not needed for**:
- Service disables (revertible from console / next-boot grub menu)
- UI / Python / firmware changes (no SSH dependency)
- Desktop config (`~/.config/*`)

---

## Snapshot history

| Snapshot file | Date | Notes |
|---------------|------|-------|
| `silvia-rpi-snapshot-2026-04-24-0032.tar.gz` | 2026-04-24 00:32 | NM-managed network. Boot to `graphical.target` ≈ 11.07 s userspace (15.0 s total). All trims applied. |
| `silvia-rpi-snapshot-2026-04-24-0118.tar.gz` | 2026-04-24 01:18 | systemd-networkd + wpa_supplicant. Boot to `graphical.target` ≈ 7.45 s userspace (11.7 s total). NM kept on disk as fallback. |
| `silvia-rpi-snapshot-2026-04-24-0153.tar.gz` | 2026-04-24 01:53 | **Current**: L2 kiosk (cage compositor). multi-user.target ≈ 6.59 s userspace (10.0 s total). lightdm + labwc + pcmanfm-pi + wf-panel-pi all bypassed. |

## Roll back L2 (cage) → L1 (labwc)

```bash
cp /home/gram/.bash_profile.l1.bak /home/gram/.bash_profile
sudo reboot
```

(L1's `~/.bash_profile` is preserved in the home directory as `.l1.bak`.)

## Roll back L2 → original lightdm + labwc-pi desktop

```bash
sudo systemctl enable lightdm.service
sudo rm /etc/systemd/system/getty@tty1.service.d/autologin.conf
sudo rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null
rm ~/.bash_profile          # so login shells don't trigger cage anyway
sudo systemctl daemon-reload
sudo reboot
```

## Roll back NM swap

If networkd misbehaves and you want NM back:

```bash
sudo systemctl disable wpa_supplicant@wlan0.service systemd-networkd.service
sudo systemctl enable NetworkManager.service
sudo reboot
```

NM will re-read its existing connection profile in `/etc/NetworkManager/system-connections/poopnet.nmconnection` and reconnect.
