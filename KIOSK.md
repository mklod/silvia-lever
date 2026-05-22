# Kiosk / boot-time optimization

Reference doc for the dedicated-appliance side of the Silvia Lever Pi setup.
Documents the boot-time work already done, what was tried and abandoned, and
realistic options for going further if 10 s isn't fast enough one day.

Last updated: 2026-04-24--0205

Companion docs: `RPI_RESTORE.md` (snapshots + rollback), `setup_rpi.sh`
(reproducible setup script with header documenting boot history).

---

## Current state — L1 kiosk via labwc-pi (10.6 s cold boot)

Boot chain:
```
firmware bootloader  (~0.2 s)
  ↓
kernel              (~3.5 s)
  ↓
systemd init + sysinit + dbus + basic.target  (~5 s)
  ↓
multi-user.target   (~7.1 s)
  ↓
getty@tty1 → autologin gram → ~/.bash_profile
  ↓
exec labwc-pi (compositor + lwrespawn pcmanfm-pi + wf-panel-pi)
  ↓
XDG autostart fires ~/.config/autostart/silvia.desktop
  ↓
silvia (Qt + QML)   (UI on screen ~9-10 s)
```

Stack:
- **No display manager** (lightdm disabled)
- **labwc-pi** as the compositor (Pi-OS-blessed wrapper around labwc)
- pcmanfm-pi + wf-panel-pi run respawned by lwrespawn but don't block the chain
- **kanshi** (auto-started by labwc-pi) handles display rotation + touch matrix
- **systemd-networkd + wpa_supplicant** for WiFi (NM disabled)
- **No splash, no rainbow, no logo** (firmware + kernel + Plymouth all silenced)

Total wall-clock from cold-power-on to interactive UI: **~10-11 seconds**.

### Why L1 over L2 (cage)

L2 (cage) was attempted (boot ≈ 10.0 s, basically identical to L1) but
broke three things that labwc-pi handled for free:
- **Touchscreen rotation** — cage's `wlr-randr --transform 90` rotates the
  display but not the touch input matrix; touch coords are still in the
  unrotated frame. Would need a libinput udev rule for `LIBINPUT_CALIBRATION_MATRIX`.
- **Persistent mouse cursor** — cage shows the system cursor with no
  `--hide-cursor` flag.
- **Boot visuals** — two extra black-terminal flashes (kernel KMS init +
  agetty handoff) before cage takes over.

The "saved seconds" from L2 vs L1 turned out to be within noise (~0.5 s),
not the 1-2 s I'd estimated. labwc-pi's overhead is small once it's
running; the desktop chrome (pcmanfm-pi + wf-panel-pi) spawns in parallel
with silvia, not on the critical chain. L1 keeps all the things that work.

---

## Boot history

| Stage | Total | UI-ready target |
|-------|-------|-----------------|
| Original Pi OS Bookworm | 26.3 s | 22.0 s userspace |
| Service trims + visuals | 15.0 s | 11.07 s `graphical.target` |
| + NM → systemd-networkd | 11.7 s | 7.45 s `graphical.target` |
| + L1 (no lightdm, getty → labwc-pi) | 10.7 s | 7.16 s `graphical.target` |
| + L2 (cage kiosk) — *abandoned* | 10.0 s | 6.59 s `multi-user.target` |
| **+ L1 (labwc-pi via getty)** — *current* | **10.6 s** | **7.11 s `multi-user.target`** |

Total reduction from original: **60 %**.

L2 saved ~0.5 s on top of L1 but broke touch + cursor + boot visuals.
Reverted to L1 as the end state. See "Why L1 over L2" above.

---

## Things tried that didn't help (kept in `setup_rpi.sh` header for the record)

These are documented to save future time:

- **`fastboot` in cmdline.txt** — fsck was already a no-op on clean fs, no change
- **`dtoverlay=disable-bt`** — kernel time didn't change (BT module wasn't slow)
- **IPv6 disable on NM connections** — NM bottleneck is WPA handshake, not DAD
- **Empty `Before=` / `After=` in systemd drop-in overrides** — systemd treats
  these as additive even though docs imply they should reset
- **Direct edit of `NetworkManager.service` to remove `Before=network.target`** —
  shifted NM into a direct dep of `multi-user.target.wants/`, made boot WORSE
- **L1 alone (skip lightdm, keep labwc)** — only saved ~0.3 s. The cost was
  always the labwc + pcmanfm-pi + wf-panel-pi spawning, not lightdm itself.
  L2 (cage) is what actually moved the needle.

---

## Going below 10 s — realistic options

### Hardware-only (composable with everything)

| Move | Saving | Cost | Risk |
|------|--------|------|------|
| **A2-rated SD card** (e.g. SanDisk Extreme Pro) | 1.5-2.5 s | ~$20 + 30 min | none |
| **USB SSD boot** | 3-5 s | ~$30 SSD + USB enclosure + 1 h | none |
| **Faster RAM/CPU** | n/a | already maxed for Pi 4 | n/a |

### L3 — Qt `eglfs` platform plugin (skip cage)

Render Qt directly to DRM/KMS via EGL, no Wayland compositor at all.

```
Now:    getty → cage → silvia (Qt on Wayland)
L3:     getty → silvia (Qt on EGL/DRM)
```

- **Saving**: ~0.5-1 s (cage startup time)
- **Effort**: ~2 h. Set `QT_QPA_PLATFORM=eglfs`, `QT_QPA_EGLFS_ROTATION=90`,
  configure touchscreen via `QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS`.
- **Risks**:
  - Touch input via `evdev` directly (different code path than libinput/Wayland)
  - Display rotation handled differently
  - No compositor → if the app crashes, black screen instead of cage's empty state
  - HiDPI scaling may behave subtly differently
- **Verdict**: borderline. ~1 s saved for new failure modes.

### L4 — replace Pi OS entirely

Five different paths, each progressively more involved.

#### L4a — Strip Pi OS down (lowest-effort L4)

`apt purge` everything we don't use: GUI stack, Bluetooth, sound, snapd,
remaining browser/office detritus.

- **Saving**: 1-2 s
- **Effort**: 3-5 h iterative
- **Risk**: low (revertible via `apt install`)
- **Estimated total boot**: ~8 s
- **Verdict**: highest ROI of the L4 options if you want to stay in the Pi OS
  / Debian world.

#### L4b — Alpine Linux

musl libc + BusyBox + apk. Native Pi 4 support, much smaller base than Debian.

- **Saving**: 2-3 s on top of L4a
- **Effort**: weekend project. Re-port silvia to Alpine (Python + Qt build
  issues are common with musl). Network config rewrite. Lose `apt`,
  `raspi-config`, the rest of the Pi OS tooling.
- **Risk**: medium. Smaller ecosystem, fewer answers on Stack Overflow.
- **Estimated total boot**: ~6-8 s

#### L4c — Buildroot (custom image)

See deep dive below.

- **Saving**: 4-6 s
- **Effort**: VERY high
- **Estimated total boot**: ~4-6 s

#### L4d — Yocto / OpenEmbedded

See deep dive below.

- **Saving**: similar to Buildroot
- **Effort**: VERY high
- **Estimated total boot**: ~4-6 s

#### L4e — Bypass systemd

Replace systemd init with `s6` / `runit` / shell scripts.

- **Saving**: 3-5 s (systemd is ~5 s of our boot)
- **Effort**: extreme. Re-implement service management, log handling,
  dependency ordering.
- **Risk**: high. Fragile across distro updates.
- **Verdict**: only sensible inside L4c / L4d, not on top of Pi OS.

### Custom kernel (composable)

- Strip drivers we don't use (USB modules, BT, sound, IPv6, etc.)
- Use LZ4 compression instead of GZIP (faster decompression)
- Saves ~1-2 s of kernel boot
- Effort: high (kernel build chain, maintenance burden across kernel updates)

### Realistic combined estimates

| Stack | Boot | Effort | Risk |
|-------|------|--------|------|
| **L2 (current)** | **10 s** | done | done |
| L2 + L3 (eglfs) | ~9 s | 2 h | medium |
| L2 + L4a (apt strip) | ~8 s | 3-5 h | low |
| L2 + L4a + L3 | ~7 s | 5-7 h | medium |
| L2 + A2 SD card | ~8 s | 30 min + $20 | none |
| L2 + USB SSD | ~6-7 s | 1 h + $30 | none |
| L4b (Alpine) + L3 | ~5-6 s | weekend | medium |
| L4c (Buildroot) + L3 + custom kernel | ~3-4 s | week+ | medium-high |
| L4e (no systemd) + Buildroot + USB SSD | ~2-3 s | weeks | high |

---

## Buildroot deep dive

**What it is**: a Make-based build system that produces a small Linux image
from source. Started ~2001 by the uClibc team. Single-purpose: take a kernel
+ packages + filesystem layout config, output a bootable image.

### How it works

```bash
git clone git://git.buildroot.net/buildroot
cd buildroot
make raspberrypi4_64_defconfig    # official Pi 4 config
make menuconfig                    # adjust packages
make                               # cross-compile everything
ls output/images/                  # → sdcard.img + zImage + rootfs
```

`make menuconfig` is the same kernel-style menu interface you may know from
custom kernel builds. Pick packages, enable kernel options, choose libc
(uClibc / musl / glibc), select init system (BusyBox / systemd / OpenRC).

### Strengths

- **Simple**: one Makefile-driven build. Output is a flashable image.
- **Fast iteration**: clean rebuild ~30-60 min. Incremental rebuild much faster.
- **Easy to learn**: 1-2 days to first booting image.
- **~3000 packages** in the official tree (vs Debian's 60k+, but covers
  what you'd actually need for embedded).
- **Pi 4 supported out of the box** with `raspberrypi4_64_defconfig`.
- **Cross-compile by default**: build on x86 desktop, target ARM Pi.

### Weaknesses

- **Update model is reflash-the-image**: no `apt update`. To change one
  package version: rebuild image, flash to SD card, swap.
- **Not great for products with field updates**: needs SWUpdate or similar
  bolted on.
- **Smaller package selection** than Debian — most things you need are there
  but specialty stuff may need a custom recipe.

### For Silvia specifically

Packages needed:
- Qt6 (`qt6base`, `qt6declarative`, `qt6wayland` if Wayland — or skip if eglfs)
- Python 3 (`python3` + pip-installable PyQt6 — or build PyQt6 from source)
- wpa_supplicant (already in Buildroot)
- Cage (`cage` package exists in Buildroot since ~2023)
- Optionally: networkd or just static config + iproute2 + wpa_supplicant
- Custom kernel config trimming USB-storage we don't need, BT, etc.

**Realistic boot estimate**: **3-4 s** is achievable for a well-tuned Buildroot
Pi 4 image with custom kernel + BusyBox init + skipped services. The Pi
firmware floor is ~0.2 s; kernel boot ~1-2 s with stripped config; userspace
~1-2 s with no systemd. The Qt+Python+QML app load is ~1-2 s — that's a
floor we can't easily beat without rewriting in C++.

So for *our* Python+Qt app: realistic Buildroot best-case is **4-5 s** total
to UI on screen. To go lower, we'd need to drop Python (write the UI in
C++/Qt directly) and possibly use `eglfs` to skip Wayland.

---

## Yocto / OpenEmbedded deep dive

**What it is**: A "build system for building Linux distributions". Originated
2010, sponsored by the Linux Foundation. Industry-standard for commercial
embedded Linux products (TVs, automotive, IoT gateways).

### How it works

```bash
git clone git://git.yoctoproject.org/poky
git clone https://github.com/agherzan/meta-raspberrypi
cd poky
. oe-init-build-env
# add meta-raspberrypi to bblayers.conf, set MACHINE = "raspberrypi4-64"
bitbake core-image-minimal     # ~2-4 hours for first build
ls tmp/deploy/images/raspberrypi4-64/   # → flashable image
```

Yocto uses **BitBake** (a Python-and-bash recipe interpreter) to assemble
images from layers (`meta-*` directories). Each layer contains recipes
(`.bb` files) for packages, `.bbappend` files for customizations, and
machine configs.

### Strengths

- **Reproducible**: recipe versions pinned, build is deterministic.
- **Layered**: separate concerns (BSP, app, custom configs) into layers.
- **Cross-architecture**: same recipes target ARM, x86, RISC-V.
- **Includes an SDK build target**: developers get a cross-toolchain that
  matches the deployed image exactly.
- **OTA story** with SWUpdate, RAUC, mender, etc.
- **Industry vetting**: shipped in millions of consumer devices.

### Weaknesses

- **Steep learning curve**: 1-2 weeks to proficiency. BitBake recipes have
  their own DSL (Python + shell + variable-flag syntax).
- **Build times are long**: 2-4 h for clean. Disk-hungry (50+ GB). Memory-
  hungry (16+ GB recommended).
- **Overkill for hobby projects**: the level of indirection makes simple
  changes feel heavy.

### Compared to Buildroot

| Aspect | Buildroot | Yocto |
|--------|-----------|-------|
| First image | 1-2 days learning | 1-2 weeks learning |
| Build time | 30-60 min | 2-4 h |
| Disk space | ~10 GB | ~50+ GB |
| Update model | reflash | swupdate / RAUC / OTA |
| Best for | hobbyists, single-target embedded | products, multi-target SKUs |
| Boot time potential | 3-4 s | 3-4 s (similar) |

### For Silvia specifically

Both can produce equivalently fast images. **Buildroot is the right choice
for this project** — single Pi 4 target, no need for OTA infrastructure,
hobby-scale maintenance, simpler tooling.

Yocto only makes sense if you ever decide to ship the Silvia controller as
a product (multiple units, field updates, version pinning, security
auditing).

---

## Sub-second floor: where the Python+Qt app load fits in

Even a perfectly-tuned Buildroot+kernel image can't get faster than the
**app's own startup time**. PyQt6 + QML loads at ~1-2 s on a Pi 4:

- Python interpreter + standard library imports: ~300 ms
- PyQt6 binding load: ~400 ms
- Qt6 + QtQuick runtime init: ~500 ms
- QML engine + compile main.qml: ~300-500 ms
- First frame render: ~100 ms

To get below ~3 s total boot, you'd need to either:
- **Rewrite the UI in C++** (Qt/QML can run as compiled C++; Python overhead vanishes; ~500 ms app start instead of 1.5 s)
- **Pre-load** the Python interpreter as part of init (a "warm" init that
  has Python imports ready before userspace fully starts)
- **Or accept the floor**.

### Honest recommendation

**Stop at L2.** The Pi cold-boots in 10 s, the UI is interactive in ~8 s
of that. A real human won't notice the difference between 10 s and 6 s for
a machine they turn on once a day. The engineering cost (and ongoing
maintenance burden) of going further is much higher than the win.

If you ever decide to ship this as a product or build a second one, then
Buildroot becomes worth the effort — reproducible, deterministic, tightly
controlled. Until then, the current 10 s setup is "good enough" for a
purpose-built espresso machine.

---

## Revision log

- **2026-04-24 (02:05)**: Initial KIOSK.md. Captures L1 + L2 history,
  documents all five L4 paths, deep dives on Buildroot + Yocto, honest
  recommendation to stop at L2.
