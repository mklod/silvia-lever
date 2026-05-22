# Silvia Lever — Changelog

## TODO
> [!tip] Queued for next build
> - Plug Teensy into RPi (via udev rule, should auto-detect as `/dev/ttyACM0` with no ModemManager interference) and verify end-to-end telemetry on the touchscreen
> - **Scale drift-compensation EMA** (Decent OpenScale trick #3): `f_driftCompensation += diff * 0.3` to absorb thermal baseline creep. Gate on "no recent brew" so it doesn't eat real slow loads. See `workplan.md` Scale FW Audit section.
> - **Scale stable-output threshold** (Decent OpenScale trick #5): only push weight value to telemetry when `|delta| > threshold`. Cheap UI redraw saver, low priority.
> - Extended brew + steam + flush sessions on real hardware
> - PID tuning once thermoblock has reached setpoint a few times
> - Profile system (Stage 8) after a few weeks of real-world use
> - Autostart silvia on RPi boot (systemd user unit or labwc-pi autostart) so no tap needed at power-on

## Build 2026-05-22--0139 — Stage 1: brew profile engine + Gentle & Sweet

First step of the light-roast profile plan (PROFILES.md §3).

### Firmware — profile engine

- A **profile** is an ordered list of segments; each slews the pressure
  setpoint toward `targetBar` at `slewRate`, runs the shared
  `pumpClosedLoop()` PI(D) with a chosen gain set, and advances when any
  non-zero exit criterion fires (`weight` / `duration` / `pressure`, first
  to trigger). The final segment runs until user STOP.
- `runBrewSegmentEngine()` replaces the hardcoded preinfuse/ramp/hold
  state machine. The Stage-0 slew-rate controller is the substrate —
  unchanged.
- Two built-in profiles (`const` arrays in the .ino):
  - **Profile 0 "Standard 9-bar"** — faithful re-expression of the Stage-0
    sequence (1 bar preinfuse, exit 1 g / 10 s → slew to 9 bar, hold).
    Regression baseline.
  - **Profile 1 "Gentle & Sweet"** — light-roast starter: same preinfuse,
    then flat 6 bar hold (lower pressure = less channeling on light roasts).
- New serial commands: `SET_PROFILE <n>`, `GET_PROFILES`.
- Manual pot-rotation takeover preserved — works from any segment.

### UI — profile picker

- `PROF: <name>` button in the debug row; tap cycles to the next profile.
- `qml_backend`: `setProfile()` / `cycleProfile()` slots, `GET_PROFILES`
  on connect, parses `PROFILE:`/`OK:PROFILE_COUNT:` into a learned list
  (no hardcoded names — UI stays in sync with firmware).

### Verified
- Compiles clean (Teensy 4.0, 52184 B flash). Flashed; `GET_PROFILES`
  returns both profiles; silvia picks up the list.

### Not yet verified (needs a brew)
- Profile 0 regression (should match Stage 0, no overshoot); Profile 1
  6-bar flat hold; `PROF:` button cycling.

### Flash gotcha
- A Teensy re-enumeration during flash browned out Pi 1 (dmesg had prior
  "Undervoltage detected!"). Pi dropped off-network mid-flash; power-cycle
  recovered it; re-flash completed. Pi PSU / USB load is marginal — worth
  a beefier supply.

> [!warning] Testing Checklist
> - [ ] Profile 0 "Standard 9-bar" — pull a brew, confirm same clean curve as Stage 0 (no overshoot)
>   - Notes:
> - [ ] `PROF:` button cycles Standard ↔ Gentle & Sweet, name displays
>   - Notes:
> - [ ] Profile 1 "Gentle & Sweet" — pull a brew, confirm flat 6-bar hold
>   - Notes:
> - [ ] Manual pot takeover still works under the profile engine
>   - Notes:

## Build 2026-05-22--0036 — Stage 0 final: slew-rate control, manual takeover, AUTO/MAN toggle

### Brew control — the design that finally killed the overshoot

Iterated through three control designs on real hardware (fine restrictive
grind). Open-loop PWM ramp → 14 bar. Closed-loop *linear* RAMP-sweep + separate
HOLD phase → still ~11.5 bar overshoot at the RAMP→HOLD boundary. Tried
bumpless transfer, integrator reset, D-term — none fixed it because the root
cause is **pump→pressure transport lag** (~200 ms): any setpoint moving faster
than the lag window commits the system to overshoot regardless of tuning.

**Final design (works, zero overshoot):**
- ONE PI(D) loop runs the entire post-preinfuse brew. ONE gain set.
- Setpoint *slews* from `PREINFUSE_TARGET_BAR` to `BREW_TARGET_BAR` at
  `BREW_SLEW_RATE` (0.8 bar/sec). Controller always keeps up; integrator
  self-adapts to whatever PWM the puck restriction needs.
- RAMP and HOLD are the same loop — phase label is telemetry-only.
- Removed `RAMP_MS`, `HOLD_MS`, all per-phase `RAMP_*`/`HOLD_*` constants,
  and the `rebaseIntegratorForTransition()` bumpless helper. Net simpler.
- Verified: PREINFUSE → smooth ramp → rock-steady 8.9 bar HOLD on a fine grind.

### Manual takeover (bumpless auto→pot handoff)

- Rotate the pump pot >`MANUAL_TAKEOVER_DELTA` (~10%) from its brew-start
  position during RAMP/HOLD → control hands to the pot.
- `handoverOffset = lastAutoPwm − potValue` captured at the transition;
  output is then `pot + offset` so there's no pressure step. User adjusts
  relative to the auto baseline (turn down to taper).

### AUTO / MANUAL toggle

- New `autoBrewMode` flag in firmware + `SET_AUTO_MODE 0|1` serial command.
- New `BREW: AUTO/MAN` button in the UI debug row (green=AUTO, grey=MANUAL),
  `setAutoBrewMode()` slot in qml_backend. No more SSH/reflash to switch.
- Firmware defaults to MANUAL at boot.

### PREINFUSE tuning

- Target 2.5 → **1.0 bar** (gentler wetting).
- Exit: 5 g → **1 g** weight, OR new **10 s hard time cap** (`PREINFUSE_MAX_MS`)
  so a choked puck can't hold preinfuse forever. First of the two wins.

### Toolchain

- Established firmware build/flash workflow: arduino-cli (bundled with
  Arduino IDE 2.x) → pscp .hex to Pi → `teensy_loader_cli` + 134-baud reboot
  magic. ~30 s edit-to-running. One gotcha logged: if the 134-baud reboot
  races a flash already in progress, Teensy can stick in HalfKay bootloader
  — re-run the loader (no 134-baud needed, it's already in bootloader).

### Files
- `firmware/silvia_lever_main/config.h` — slew-rate constants, PREINFUSE
  retune, removed obsolete per-phase macros.
- `firmware/silvia_lever_main/silvia_lever_main.ino` — single-loop state
  machine, `pumpClosedLoop()` PI(D), manual takeover, `SET_AUTO_MODE`.
- `ui/source/main.qml` — `BREW: AUTO/MAN` toggle button.
- `ui/source/qml_backend.py` — `setAutoBrewMode()` slot, `autoBrewModeChanged`.
- `PROFILES.md` — §0/§1 rewritten for the slew-rate design.

> [!warning] Testing Checklist
> - [ ] AUTO brew: PREINFUSE 1 bar → ramp → 9 bar hold, no overshoot
>   - Notes:
> - [ ] Manual takeover: rotate pot mid-HOLD, confirm bumpless (no pressure jump)
>   - Notes:
> - [ ] BREW: AUTO/MAN toggle button works, survives silvia restart
>   - Notes:
> - [ ] PREINFUSE 10 s time cap fires on a choked puck (deliberately over-dose)
>   - Notes:

## Build 2026-04-24--1555 — Stage 0 brew control + chart freeze + Pi 2 ready

### Firmware (Teensy 4.0) — Stage 0: closed-loop pressure throughout

The first hot test (`brew_logs/brew_2026-04-24_19-08-16.json`) revealed the
open-loop PWM RAMP slammed a fine-grind puck to **13.97 bar peak**. P-only
HOLD couldn't recover in 3 s (ended at 11.13 bar). EXTRACT (pot=36% = 91 PWM)
was too weak for 9 bar maintenance.

Root cause: only PREINFUSE controlled the variable that matters (pressure).
Open-loop PWM is meaningless on espresso because puck restriction varies
massively shot-to-shot.

Fix shipped:
- New `pumpClosedLoop()` PI helper with anti-windup, shared by all three
  managed brew phases.
- **RAMP redesigned**: pressure target sweeps linearly `2.5 → 9.0 bar` over
  `RAMP_MS`, PI controller tracks the moving setpoint. No more PWM blast.
- **HOLD made indefinite**: removed the 3-second `HOLD_MS` gate that auto-
  dumped to pot-controlled EXTRACT. User STOPs the brew when cup weight is
  right. EXTRACT is now manual-override only.
- I-term added to all three pressure phases. Resolves HOLD's steady-state
  error and the slow recovery from a RAMP overshoot.
- New tunables in `config.h`: `PREINFUSE_KI`, `RAMP_BASE_PWM/KP/KI/MIN/MAX`,
  `HOLD_KI`, `PUMP_PI_INTEGRAL_MAX`. Removed `HOLD_MS`.

Compiled clean (Teensy 4.0, 51288 B flash, 10528 B RAM1) via Arduino-CLI
bundled with Arduino IDE 2.x. Flashed to live Teensy via `teensy_loader_cli`
on Pi 1 (134-baud reboot magic for soft enter-bootloader). No physical
button press needed.

### UI — chart values freeze on brew stop

`main.qml` adds `frozenWeight`, `frozenPressure`, `brewDisplayFrozen`
properties. On `BREWING → IDLE` state transition, current values are
snapshotted; chart big-numbers display the frozen values until the next
`BREWING` state. Bottom debug row keeps showing live telemetry regardless.

### Pi 2 setup

Fresh Pi OS Lite Trixie 64-bit flashed to a 64 GB SD via dd-stream from
xz-decompress through PowerShell raw IO + dd-for-Windows. Cloud-init
network-config + NetworkManager `nmcli connection add` got it on WiFi
at 192.168.1.30, hostname `silvia-pi-2`, user `gram`/`gram`.
- Repo cloned to `/home/gram/silvia-lever/`, latest local working tree
  pushed via pscp -r.
- `setup_rpi.sh` ran clean: plymouth black theme, invisible cursor, getty
  autologin (`Type=idle`), labwc autostart, boot-trim, all installed.
- `bash_profile` updated to drop the `exec` on labwc — without HDMI
  attached, labwc fails immediately, and `exec` would cause getty restart-
  loop until `start-limit-hit`. Without `exec`, falls through to
  interactive bash. With HDMI attached the kiosk runs normally.
- Boot 10.7 s headless. Drop-in replacement card.

### Files
- `firmware/silvia_lever_main/silvia_lever_main.ino` — `pumpClosedLoop()`,
  state machine rewrite, integrator state.
- `firmware/silvia_lever_main/config.h` — Stage 0 tunables.
- `ui/source/main.qml` — chart freeze.
- `ui/rpi/setup_rpi.sh` — bash_profile no-exec change.
- `PROFILES.md` — new section 0 with Stage 0–4 progression; section 1
  rewritten to reflect Stage 0 implementation.

> [!warning] Testing Checklist
> - [ ] Pull a brew with the new firmware. RAMP should sweep cleanly to 9 bar with no overshoot. Compare new brew_log JSON to the 0419 one.
>   - Notes:
> - [ ] Chart big-numbers (weight + pressure) freeze on stop, show last value until next brew. Live debug row keeps flowing.
>   - Notes:
> - [ ] HOLD continues indefinitely — verify user STOP ends the brew properly (no auto-transition timeout).
>   - Notes:
> - [ ] If overshoot persists, drop `RAMP_KP` (currently 25) and/or `RAMP_BASE_PWM` (currently 120). PI integrator should pull steady-state to zero given a few sec.
>   - Notes:

## Build 2026-04-24--0313 — plymouth black, invisible cursor, 8.04 s boot

Two improvements layered on:

### Plymouth black splash
Re-enabled plymouth with a custom all-black theme (`/usr/share/plymouth/themes/black/`, `ModuleName=script`, draws nothing over black background). Covers one of the two terminal flashes. Initial attempt also masked `plymouth-quit.service` to stretch coverage across the whole getty→labwc window, but that hangs boot (`plymouth-quit-wait.service` never completes and `multi-user.target` is blocked). Reverted. **One flash remains** — the plymouth-quit → getty → labwc gap. Closing it cleanly requires moving labwc to a systemd service so plymouth-quit can be ordered `After=labwc`; deferred for now.

### Invisible cursor
labwc has no hide-always option. Solution: transparent `XCURSOR_THEME=empty` generated from a 1×1 transparent PNG via `xcursorgen`, with symlinks for every common cursor name. Wired via `~/.config/labwc/environment`. Touch events still work (rc.xml maps `wch.cn USB2IIC_CTP_CONTROL` to HDMI-A-1 with `mouseEmulation="yes"`).

### Pre-firmware display artifact (discussion, not fixed)
Root cause: HDMI OLED panel is USB-powered off the Pi 4B's USB port. Pi supplies 5V to USB the instant power hits — before firmware even runs — so the panel powers up and shows its cold-init garbage for several seconds until the Pi's HDMI PHY comes online. Pi 4B VL805 hub has no per-port power control in software, so no software fix is possible.

Options discussed with user:
- A: Inline USB switch module with manual button
- B: GPIO-controlled P-MOSFET on the +5V rail, toggled on by a systemd unit after labwc draws
- C: Pi 5 (has per-port USB power control)

User noted the display case is tight — adding electronics is hard. Pi 5 being considered (2 GB is plenty for this workload — current Pi 4B 4 GB is using ~450 MiB total).

### Measured
- Boot 8.04 s (2.44 s kernel + 5.61 s userspace) — best number to date.
- Processes: 1× labwc, 1× kanshi, 1× silvia. No pcmanfm, no panel.

### Files
- `ui/rpi/setup_rpi.sh` — plymouth mask replaced with theme install; cursor-theme install + labwc environment.
- `ui/rpi/setup_rpi.sh` — note added: plymouth-quit MUST stay unmasked.

> [!warning] Testing Checklist
> - [ ] Cold boot: mouse cursor should NOT be visible on silvia UI
>   - Notes:
> - [ ] Cold boot: at most one terminal flash expected (between plymouth quit and labwc draw)
>   - Notes:
> - [ ] Touch still works (rc.xml mapping)
>   - Notes:

## Build 2026-04-24--0246 — kill desktop flash (labwc --config-dir isolation)

After the tty3 fix, cold boot sequence still showed the pcmanfm-pi desktop
wallpaper + wf-panel-pi briefly before silvia covered them. Root cause:
labwc-pi always ran `/etc/xdg/labwc/autostart` (which spawns pcmanfm-pi +
wf-panel-pi + kanshi + lxsession-xdg-autostart) — and even when a
user-level `~/.config/labwc/autostart` existed, both ran in parallel.
Result: duplicate silvia instances and visible desktop for ~1 s.

### Fix
Stop calling `labwc-pi` wrapper. bash_profile now execs:

    /usr/bin/labwc --config-dir "$HOME/.config/labwc" -m

`--config-dir` pins labwc to a single config directory, so
`/etc/xdg/labwc/autostart` is never read. Kept the Pi env setup that
labwc-pi did via `. /usr/bin/setup_env`.

### Artifacts
- `~/.config/labwc/autostart` (minimal): just `kanshi &` + silvia. No
  desktop, no panel, no lxsession.
- XDG `~/.config/autostart/silvia.desktop` deleted on the live Pi — unused
  now that lxsession-xdg-autostart isn't in the chain.
- `setup_rpi.sh` updated: bash_profile now calls labwc directly with
  --config-dir, and the user autostart install is documented as the
  single source.

### Measured
- Processes after boot: 1× labwc, 1× kanshi, 1× silvia. No pcmanfm-pi,
  no wf-panel-pi, no lxsession. (Was 2× kanshi + 2× silvia before.)
- Boot 9.22 s (2.50 s kernel + 6.71 s userspace).

> [!warning] Testing Checklist
> - [ ] Cold boot: confirm no desktop/wallpaper/panel flash between terminal flashes and silvia UI
>   - Notes:
> - [ ] Touchscreen still works (rc.xml mapping survives without lxsession)
>   - Notes:
> - [ ] Display rotation still correct (kanshi config intact)
>   - Notes:
> - [ ] Terminal flashes — still present? Decide if plymouth re-enable is worth the ~0.5 s cost
>   - Notes:

## Build 2026-04-24--0236 — kill boot-time terminal flashes

Cold boot still flashed one or two terminal-text screens between firmware
and labwc. Kernel + systemd + getty were all spraying text onto tty1 —
the same VT labwc takes over — so their output was visible during the
handoff.

### Changes
1. **cmdline.txt: `console=tty1` → `console=tty3`.** Moves all kernel +
   systemd console output to an invisible VT. tty1 stays black until
   labwc grabs the framebuffer.
2. **agetty silenced**: added `--noissue --nohostname` (strips
   "Debian GNU/Linux tty1" banner) and `TTYVTDisallocate=no` (keeps VT
   alive across the getty→labwc handoff, avoids a brief reset flash).
3. **`~/.hushlogin`** touched to silence pam_motd + last-login message
   that would otherwise print during autologin.

All three baked into `setup_rpi.sh` so a fresh deploy reproduces the
cleaner boot. Original `cmdline.txt` backed up to
`/boot/firmware/cmdline.txt.pre-tty3-bak` on the Pi.

### Measured
- Boot 9.94 s (3.09 s kernel + 6.84 s userspace) — within noise of 8.8 s;
  the main win here is visual, not time.
- labwc + silvia autostart cleanly confirmed via SSH.

> [!warning] Testing Checklist
> - [ ] Cold boot Pi and confirm no terminal text flashes between firmware logo and silvia UI
>   - Notes:
> - [ ] Autologin still fires reliably after the tty3 move (verify over 3 cold boots)
>   - Notes:

## Build 2026-04-24--0228 — getty autologin race fixed (Type=idle)

After the L2→L1 revert, first-boot autologin started failing intermittently:
agetty would hang in `(agetty)` waiting state instead of autologging `gram`,
leaving the Pi at a bare login prompt with labwc/silvia never starting.

### Root cause
`After=systemd-user-sessions.service` alone was not enough to beat the
pam_nologin race — pam was still occasionally rejecting the autologin
attempt a few ms before user-sessions finished its handshake.

### Fix
Add `Type=idle` to `/etc/systemd/system/getty@tty1.service.d/autologin.conf`.
`Type=idle` holds agetty until the manager reports no other units are
starting — enough extra slack for pam to clear pam_nologin.

### Measured
- Boot 10.6 s → **8.8 s** (systemd-analyze: 2.856s kernel + 5.967s userspace)
- labwc fires on first boot, silvia UI launches automatically via XDG
  autostart, no SSH intervention needed.

### Files
- `ui/rpi/setup_rpi.sh` — added `Type=idle` to the getty override stanza,
  updated comment block to explain the two-part fix
  (After=user-sessions + Type=idle together, not either alone).

> [!warning] Testing Checklist
> - [ ] Power-cycle Pi three times in a row, confirm labwc + silvia come up every time without needing SSH
>   - Notes:
> - [ ] Touchscreen still rotated correctly, no cursor, no black-terminal flashes
>   - Notes:
> - [ ] Teensy telemetry flows after Pi boots (udev auto-detects)
>   - Notes:

## Build 2026-04-24--0210 — L2 reverted, L1 confirmed end state, KIOSK.md added

L2 (cage compositor) was tested and reverted — same boot time as L1 (~10.5 s)
but broke three things labwc-pi handles for free: touchscreen rotation
(cage doesn't propagate display transform to libinput), persistent mouse
cursor (no `--hide-cursor` flag), and two extra boot-visual flashes.

### Reverts
- `~/.bash_profile` restored from `.l1.bak` (back to `exec labwc-pi`).
- `setup_rpi.sh` updated to write the L1 bash_profile (not the cage one).
- All other L2-era changes kept (they're orthogonal): cage + wlr-randr stay
  installed (harmless), NM-→-networkd stays, `systemd-networkd-wait-online`
  stays disabled, static `/etc/resolv.conf`, getty autologin override with
  `After=systemd-user-sessions`.

### New doc — `KIOSK.md`
Reference for the boot-time optimization journey:
- Current L1 stack + boot chain
- Boot history table (26.3 → 10.6 s, 60 % reduction)
- "Things tried that didn't help" log
- L3 / L4 discussion if anyone ever wants to chase below 10 s
- Buildroot deep dive (~3-4 s achievable but week+ effort)
- Yocto deep dive (similar boot, much higher complexity, only worth it for
  product ship)
- Honest "stop here at L2/L1" recommendation

### Boot history (final)
| Stage | Total | UI-ready target |
|-------|-------|-----------------|
| Original Pi OS Bookworm | 26.3 s | 22.0 s userspace |
| Service trims + visuals | 15.0 s | 11.07 s graphical.target |
| + NM → networkd | 11.7 s | 7.45 s graphical.target |
| L2 (cage) — abandoned | 10.0 s | 6.59 s multi-user.target |
| **L1 (labwc-pi via getty) — current** | **10.6 s** | **7.11 s multi-user.target** |

## Build 2026-04-24--0153 — L2 kiosk: cage compositor (boot 11.7 s → 10.0 s)

Replaces the lightdm + labwc + pcmanfm-pi + wf-panel-pi desktop stack with
a single-app kiosk path: tty1 autologin → bash_profile → `cage -s -- silvia`.

### Changes
- Installed `cage` (single-app Wayland compositor) + `wlr-randr`.
- `~/.bash_profile`: on tty1 autologin, exec cage with silvia as the only
  child. wlr-randr sets `--transform 90` to rotate the native 1080×1920
  portrait panel to 1920×1080 landscape (kanshi was doing this under labwc;
  cage doesn't run kanshi).
- `getty@tty1` override gains `After=systemd-user-sessions.service` to fix
  the boot race where `pam_nologin` would reject the autologin attempt
  before user-sessions removes `/run/nologin`.
- Disabled `lightdm.service` (no display manager).
- Disabled `systemd-networkd-wait-online.service` (was adding 15.7 s to the
  total boot time even though it's not on the critical chain).
- Wrote static `/etc/resolv.conf` (`nameserver 192.168.1.1`) — was empty
  after NM disable, killing DNS for `apt`.
- `~/.bash_profile.l1.bak` preserved for one-command rollback to L1.
- `setup_rpi.sh` extended to install + wire all of the above idempotently.
- `RPI_RESTORE.md` gains rollback recipes for L2 → L1 and L2 → original
  lightdm desktop.

### Boot history
| Stage | Total | UI-ready target |
|-------|-------|-----------------|
| Original Pi OS Bookworm | 26.3 s | 22.0 s userspace |
| Service trims + visuals | 15.0 s | 11.07 s graphical.target |
| + NM → networkd | 11.7 s | 7.45 s graphical.target |
| + L1 (no lightdm, getty→labwc) | 10.7 s | 7.16 s graphical.target |
| **+ L2 (cage)** | **10.0 s** | **6.59 s multi-user.target** |

Total: **26.3 → 10.0 s, 62 % reduction.**

### Dead ends documented (in setup_rpi.sh header)
- `fastboot`, `dtoverlay=disable-bt`, IPv6-disable, drop-in After/Before=
  resets — measured no-ops or regressions.
- L1 alone vs L2: L1 only saved ~0.3 s on graphical.target time. The big
  win was actually L2 (skipping pcmanfm-pi + wf-panel-pi spawn).

### Snapshots taken
- `silvia-rpi-snapshot-2026-04-24-0130.tar.gz` (pre-L1)
- `silvia-rpi-snapshot-2026-04-24-0153.tar.gz` (post-L2, current)

## Build 2026-04-24--0118 — NetworkManager → systemd-networkd swap

Performed under deadman protection (10-min auto-rollback to NM if SSH didn't
return). Swap succeeded; deadman cancelled.

### Changes
- Installed `wpasupplicant` package (already present at v2.10).
- New `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` — WiFi creds (chmod 600).
- New `/etc/systemd/network/25-wlan0.network` — IP config (static 192.168.1.33).
- Disabled `NetworkManager.service` + `NetworkManager-dispatcher.service`.
- Enabled `systemd-networkd.service` + `wpa_supplicant@wlan0.service`.
- NM connection profile (`/etc/NetworkManager/system-connections/poopnet.nmconnection`)
  retained on disk as fallback for easy rollback.

### Boot impact
| State | userspace to graphical.target | total |
|-------|-------------------------------|-------|
| With NM (4.4 s WiFi assoc) | 11.07 s | 15.0 s |
| With networkd + wpa_supplicant | **7.45 s** | **11.7 s** |
| Saving | **3.6 s** | **3.3 s** |

`wpa_supplicant@wlan0.service` activates almost instantly — actual WiFi
association continues in the background but no longer gates lightdm.

### Tooling updated
- `tools/rpi_snapshot.sh` now also captures `/etc/systemd/network/` and
  `/etc/wpa_supplicant/`.
- `setup_rpi.sh` gains a network-manager swap section: idempotent, only
  fires the swap if a `wpa_supplicant-wlan0.conf` is present (won't auto-write
  WiFi creds — user creates that file or restores from snapshot).
- `RPI_RESTORE.md` updated with rollback recipe and snapshot history.

### Snapshot taken before + after the swap
- `silvia-rpi-snapshot-2026-04-24-0041.tar.gz` (pre-swap, NM active)
- `silvia-rpi-snapshot-2026-04-24-0118.tar.gz` (post-swap, networkd active)

## Build 2026-04-24--0040 — Pi state backup, deadman switch, restore doc

### Backup + restore infrastructure
- **`tools/rpi_snapshot.sh`** — pulls a tarball of every config we've manually
  changed on the Pi (`/boot/firmware/{config,cmdline}.txt`, `/etc/systemd/system/`,
  NM connection profiles incl. WiFi PSK, plymouth config, libfm, autostart
  entries, desktop shortcut, audit lists of disabled/masked services + apt
  packages). Output: `tools/rpi-state-snapshots/silvia-rpi-snapshot-<ts>.tar.gz`
  (~25 KB). Folder gitignored — snapshots include WiFi creds.
- **First baseline snapshot taken**: `silvia-rpi-snapshot-2026-04-24-0032.tar.gz`.

### Deadman switch — `silvia-deadman`
- New `ui/rpi/silvia-deadman` script, installed by `setup_rpi.sh` to
  `/usr/local/bin/silvia-deadman`. Generic auto-rollback timer for risky
  changes (network swap, etc.).
- API: `arm <minutes> "<revert cmd>"`, `confirm`, `cancel`, `status`.
- Implementation: `systemd-run --on-active=Nm` schedules a transient
  one-shot. If user runs `confirm` before deadline, timer cancelled.
  If user can't reach the Pi (e.g. WiFi config broke after a swap), the
  timer fires and runs the revert command (typically a backup-restore +
  reboot).
- Smoke test verified: `arm 5 "..."` → `status` shows pending timer →
  `cancel` removes it.

### `RPI_RESTORE.md`
- New top-level doc covering: snapshot contents, Path A (restore from
  snapshot) and Path B (restore from scratch via `setup_rpi.sh` + manual
  WiFi reconnect), per-change reversion recipes (re-enable each disabled
  service, restore the rainbow + Plymouth splash, etc.), and deadman
  switch usage with a worked NM-swap example.

### Notes / dead ends documented
- `setup_rpi.sh` header now contains a "things tried that didn't help"
  block so we don't re-investigate fastboot, IPv6 disable, BT-disable,
  Before/After= drop-in resets, or direct unit-file `Before=network.target`
  removal — all measured no-ops or regressions during this session.
- Practical 15 s boot is a structural floor without bigger surgery
  (NM → systemd-networkd, A2 SD card, USB SSD).

## Build 2026-04-23--2328 — HOLD phase + RPi boot trim + autostart

### Brew sub-state machine: HOLD phase added
- New `BREW_PHASE_HOLD = 2` between `RAMP` and `EXTRACT` (now `= 3`).
- After RAMP hits PUMP_PWM_FULL, firmware holds **closed-loop 9 bar for 3 s**
  before handing off to manual control. Lets pump-vs-puck system find its
  steady-state pump speed so the user doesn't inherit a moving target.
- New tunables in `config.h`: `HOLD_TARGET_BAR` (9.0), `HOLD_MS` (3000),
  `HOLD_KP` (30), `HOLD_BASE_PWM` (200), `HOLD_MIN_PWM` (100), `HOLD_MAX_PWM` (254).
- `brewPhase` enum now 0-3; backend `phase_names` tuple updated to 4 entries.
- Phase transitions emit `INFO:BREW_HOLD_START` / `INFO:BREW_EXTRACT_START`.
- PROFILES.md §1 expanded for HOLD; ASCII diagram + tables refreshed.

### RPi boot-time optimization
Boot baseline before changes: 26.3 s total (4.3 s kernel + 22.0 s userspace),
critical chain dominated by `NetworkManager-wait-online` (5.9 s) + cloud-init
chain (13 s combined). Espresso machine doesn't need any of this.

Disabled / masked:
- `NetworkManager-wait-online` (was 5.9 s)
- `cloud-init` + `cloud-init-local` + `cloud-init-main` + `cloud-init-network`
  + `cloud-config` + `cloud-final` (masked → /dev/null) — was ~13 s combined
- `cups`, `cups-browsed`, `cups.socket`, `cups.path` — printer service
- `bluetooth` — unused on espresso machine
- `ModemManager` — already neutered for Teensy via udev; no longer loaded at boot
- `rpi-eeprom-update` (1.6 s) — runs on demand when there's an actual update
- `rpi-resize-swap-file` — one-shot first-boot only

Expected post-reboot boot: ~13-15 s total (still dominated by lightdm /
labwc startup + autostart of UI). User to reboot to confirm.

### XDG autostart entry for UI
- `setup_rpi.sh` now installs `~/.config/autostart/silvia.desktop` rendered
  from `silvia.desktop.in`. labwc/wayfire-pi parse this on session start
  and fire the launcher.
- `Exec=` points to `run_silvia.sh` which always `cd`s to `ui/source/` and
  runs the live files — so any `scp`'d updates take effect on next boot
  with no rebuild / re-package step.

### Testing checklist
> [!warning] Testing Checklist
> - [ ] Reboot Pi → desktop session reaches autostart faster (target ≤ 15 s)
>   - Notes:
> - [ ] UI auto-launches on boot, no tap needed
>   - Notes:
> - [ ] Pull a shot → preinfuse → ramp → **HOLD** (3 s steady ~9 bar) → extract (pot)
>   - Notes:
> - [ ] During HOLD, pressure visibly stable at 9 bar (not climbing/falling)
>   - Notes:
> - [ ] Brew JSON now contains `"phase": "hold"` samples
>   - Notes:

## Build 2026-04-23--2109 — Auto preinfuse + per-brew JSON + PROFILES.md

Two pieces of substrate before tackling Stage 8 (named profile system):

### Auto preinfuse (firmware sub-state machine inside STATE_BREWING)
- New `BrewPhase` enum: `PREINFUSE = 0`, `RAMP = 1`, `EXTRACT = 2`. Phase
  initialised in `BEGIN_BREW` handler; advances on its own based on
  weight + elapsed time.
- **PREINFUSE**: closed-loop P-controller targeting `PREINFUSE_TARGET_BAR`
  (2.5 bar default). PWM = `PREINFUSE_BASE_PWM + PREINFUSE_KP·err`,
  clamped `[MIN_PWM, MAX_PWM]`. Exits when scale ≥ `PREINFUSE_END_WEIGHT_G`
  (5 g default). No time cap — user can manually STOP a choked puck.
- **RAMP**: 4 s linear PWM ramp from preinfuse PWM → `PUMP_PWM_FULL`.
  OPV caps physical pressure. Exits on elapsed ≥ `RAMP_MS`.
- **EXTRACT**: pump = `sys.pumpPower` (pot reading), as before.
- Phase transitions emit `INFO:BREW_RAMP_START` / `INFO:BREW_EXTRACT_START`
  on serial.
- Tunables added to `config.h`.

### Per-brew JSON recorder
- New `ui/source/brew_recorder.py` (`BrewRecorder` class) — captures every
  brew to `ui/source/brew_logs/brew_YYYY-MM-DD_HH-MM-SS.json`.
- Hooked into `qml_backend._handle_serial_data` state transitions:
  IDLE→BREWING starts, BREWING→anything finishes.
- Schema v1: setpoints, PID gains, scale_cal, samples (10 Hz: t_s,
  weight, pressure, brew_temp, pump%, v_pump, v_tb, phase). ~50 KB per
  30 s shot.
- `brew_logs/` added to `.gitignore`.

### Telemetry
- DATA packet gains 14th field `brewPhase` (0=preinfuse, 1=ramp, 2=extract).
- Backend parses to string (`"preinfuse"|"ramp"|"extract"`); samples in
  brew_logs are tagged with the live phase.

### Docs
- **New `PROFILES.md`** — reference doc covering the current hard-coded
  preinfuse, brew JSON schema, and the planned Stage 8 named-profile
  system (schema, control modes, player-loop sketch, derivation from
  recordings).
- `workplan.md` Key File Reference gains the PROFILES.md row.

### Testing checklist
> [!warning] Testing Checklist
> - [ ] Pull a shot — pump runs gentle for ~2.5 bar until 5 g in cup
>   - Notes:
> - [ ] Pump ramps over 4 s after 5 g threshold; serial log shows `INFO:BREW_RAMP_START`
>   - Notes:
> - [ ] After ramp, pot input takes over; serial shows `INFO:BREW_EXTRACT_START`
>   - Notes:
> - [ ] STOP at any time → state → IDLE, pump off, brew JSON saved
>   - Notes:
> - [ ] `brew_logs/` contains a JSON for the shot with `phase` tagged on every sample
>   - Notes:
> - [ ] Choked-puck case (no flow): preinfuse holds at MAX_PWM until user STOPs; saved JSON has `completed_normally=false` if STOP hit during preinfuse? (currently true if state ends at IDLE — confirm this is the desired semantic)
>   - Notes:

## Build 2026-04-24--0224 — Thermoblock cold-start measurement

- **Thermoblock 25 °C → 88 °C (bang-bang handoff): ~58 s at 8.3 A continuous.**
  Measured via WiFi plug capture (`thermoblock heating from room temp.csv`,
  85 samples). After the warmup burst, plug shows ~0.13 A — PID's pulses
  are shorter than the 6 s plug cadence so they're not captured cleanly,
  but functionally the heater is now under PID at/near setpoint.
- **HEATING.md** updated:
  - §1 measured-currents table gets the thermoblock warmup row.
  - §5 Stage 9 strategy refined with concrete net cold-start budget table:
    boiler 6 min sequential → thermoblock ~1 min concurrent with boiler
    maintenance → **~7 min total cold → ready-to-brew + steam-available**.
- **workplan.md** S9.7c added (closes the thermoblock-side of the Stage 9
  current measurement set).

## Build 2026-04-23--1719 — Autotune fixes + derivative-on-measurement + filter

Second round on PID autotune after first hot-machine attempts. First attempt
timed out after 4/7 cycles; second attempt completed but gains got
rejected as "out of range" by the restore-on-reconnect path. Three real
bugs + one noise-handling upgrade:

### Firmware (`silvia_lever_main.ino`, `config.h`)
- **Fixed asymmetric-period bug in `autotuneStep()`**: was summing only the
  heating half-period and doubling it (assumes symmetry). Thermal plants are
  highly asymmetric — 8.3 A heating is fast, ambient-loss cooling is slow —
  so Tu was underestimated by ~3×, and Kd (TL = Ku·Tu/6.3) came out
  proportionally wrong. New code sums every half-period after warmup via a
  new `nHalfPeriods` counter, computes `Tu = sumPeriod / (nHalfPeriods/2)`.
- **Widened sanity bounds** on both autotune result and runtime `SET_PID`:
  `Kp < 500`, `Ki < 50`, `Kd < 5000`. Bounds now match between the two, so
  gains accepted by autotune are always accepted on reconnect.
- **Hysteresis 0.5 → 1.0 °C, timeout 600 → 1500 s (25 min)**. 0.5 °C gave
  2.5 min/cycle → 17+ min for 7 cycles, exceeded the 10 min cap.
- **Derivative on measurement** instead of derivative on error. Uses
  `-Kd · d(measurement)/dt` so there's no derivative kick on setpoint
  changes. `sys.pidLastMeasurement` added to state.
- **First-order low-pass on derivative** with `PID_D_FILTER_TAU = 2 s`.
  `α = dt/(τ+dt) ≈ 0.048` at dt=0.1s → rejects 95 % of PT1000 jitter while
  letting real thermal trends (tens of seconds) pass through. Makes Kd=3156
  (from autotune) tolerable without clicky SSR jitter. `sys.pidDerivativeFiltered`
  added to state.
- Both new state vars reset to zero during bang-bang warmup so the first PID
  tick after handoff sees a clean derivative.

### Docs
- **`HEATING.md`** §3 expanded: sanity bounds documented, derivative-on-
  measurement + filter math explained, known-limits updated.
- First successful autotune result logged in revision log:
  `Ku=142.9, Tu=139s, a=1.14 → TL Kp=46.94, Ki=0.516, Kd=3155.89`.

### Testing checklist
> [!warning] Testing Checklist
> - [ ] Power cycle → firmware applies persisted gains on reconnect (watch for `OK:PID_SET:46.940,0.516,3155.890` in log)
>   - Notes:
> - [ ] Let thermoblock stabilise at 93 °C → temperature holds cleanly within ~0.3 °C for a minute
>   - Notes:
> - [ ] No audible / visible SSR click jitter at setpoint (derivative filter doing its job)
>   - Notes:
> - [ ] Pull a test brew → cold-water disturbance recovers without excessive oscillation
>   - Notes:

## Build 2026-04-23--0234 — PID autotune + bang-bang warmup + HEATING.md

### Heater control
- **Bang-bang warmup layer** in `controlBrewHeater()`: when `error > 5 °C`, drives
  `HEATER_PWM_FULL` with integrator reset — no PID wind-up during the cold climb.
  Below 5 °C error, handoff to PID. Solves the cold-start overshoot that no single
  PID tune can fix.
- **`controlSteamHeater()` disabled** for current single-heater testing — boiler SSR stays at 0.
- **Unconditional thermoblock heating**: `controlBrewHeater()` called at end of
  `updateSystemLogic()` regardless of state, so thermoblock always seeks setpoint.
- **`heatersEnabled` default flipped to `true`** for test convenience (was `false`).
  Flip back before ship.
- **`PID_KP`: 30 → 8** (interim, before first autotune).

### PID tuning — relay-feedback autotune (Åström-Hägglund)
- `sys.kp/ki/kd` are now RAM-mutable (seeded from `config.h` defaults).
- New firmware commands: `AUTOTUNE_START`, `AUTOTUNE_STOP`, `SET_PID <kp> <ki> <kd>`.
- `autotuneStep()` runs a ±0.5 °C hysteresis relay around setpoint, skips the
  first 2 cycles as warmup, averages the next 5, computes
  `Ku = 4h/(π·a)` + both Ziegler-Nichols and Tyreus-Luyben gain tables.
- **Auto-applies TL gains** on success (sanity-bounded: Ku/Tu/a all finite + in
  range; kp<100, ki<20, kd<200). Emits `AUTOTUNE_RESULT:…,applied=TL` or `NONE`.
- Progress: `AUTOTUNE:RUNNING,cycle=N/7,temp=X.X,relay=HIGH/LOW` (1 Hz).

### UI
- **Settings → PID → AUTOTUNE** button opens modal with:
  - Live log of `AUTOTUNE:…` lines (auto-scrolling)
  - Result display on completion
  - Close/Cancel (cancel sends `AUTOTUNE_STOP`)

### Persistence
- `settings_manager.py` extended: `save_settings(pid=(kp,ki,kd))` persists to
  `pid_kp/pid_ki/pid_kd`.
- Backend parses `AUTOTUNE_RESULT:…,applied=TL` → persists TL gains.
- On every reconnect, backend re-sends `SET_PID kp ki kd` (firmware RAM gains reset at Teensy boot).

### Docs
- **New `HEATING.md`** — reference doc for heating control strategy, PID tuning,
  Stage 9 dual-heater design. Linked from workplan's Key File Reference table.

### Testing checklist
> [!warning] Testing Checklist
> - [ ] Power on from cold → thermoblock climbs with bang-bang → handoff to PID at 88 °C → settles at 93 ± 1 °C with ≤ 2 °C overshoot
>   - Notes:
> - [ ] Settings → AUTOTUNE starts successfully; modal logs oscillation cycles
>   - Notes:
> - [ ] Autotune completes in ~3-5 min with `applied=TL`; gains visible in result
>   - Notes:
> - [ ] `settings.json` now contains `pid_kp/pid_ki/pid_kd`
>   - Notes:
> - [ ] Reboot Teensy + UI → PID gains re-applied automatically (watch for `OK:PID_SET:` in log)
>   - Notes:
> - [ ] Post-autotune warmup shows less overshoot than Kp=8 interim
>   - Notes:

## Build 2026-04-22--1335 — Heater master switch + rewired priming popups

Pre-hot-test UX. Runtime heater kill-switch added; priming confirmation flow
reworked from auto-start + confirm/cancel to user-controlled start/stop.

### Firmware
- **`SystemData.heatersEnabled`** (default `false`) — runtime master switch for
  both SSRs. `controlBrewHeater()` gates PID output; `controlSteamHeater()`
  gates the thermostat. Defaults OFF so power-on never starts heating.
- **`SET_HEATERS_ENABLE <0|1>`** serial command — on disable, both SSRs are
  immediately killed (doesn't wait for next control tick).
- **DATA packet gains a 13th field** `heatersEnabled`. Existing python parser
  handles older firmware via `len(parts) > 12` guard.

### Python backend (`qml_backend.py`)
- **Removed `_auto_primed_brew` short-circuit** that was auto-sending
  `PRIME_DONE` on `PRIMING_BREW` entry — priming overlays are wanted again.
- **New `heatersEnabledChanged` signal + `setHeatersEnabled(bool)` slot** +
  `heatersEnabled()` accessor. Parses field 12 from DATA packet.

### QML (`main.qml`)
- **`HEAT: ON/OFF` field in the persistent debug row** — tap to toggle via
  `controller.setHeatersEnabled(...)`. Red bold when ON, dim grey when OFF.
- **Priming popup rewired** (both brew + steam):
  - `window.brewPrimingOpen` / `steamPrimingOpen` window-level properties
    control visibility; decoupled from firmware state so the overlay can
    appear before priming starts.
  - Single toggle button cycles green `START PRIMING` ↔ red `STOP — OVERFLOW
    SEEN` based on live firmware state (`currentState === "PRIMING_*"`).
  - `×` close button in the overlay's top-right: aborts firmware priming if
    running and dismisses the overlay (pops back to home for the brew case).
  - Pulsing indicator now only animates while priming is actually running.
- Home-screen BREW button pushes the brew screen + opens the overlay (no
  longer directly sends `START_BREW`).
- Home-screen STEAM button toggles between opening the overlay and stopping
  an active steam session.

### Testing checklist
> [!warning] Testing Checklist
> - [ ] Teensy boot → `heatersEnabled=0` in telemetry; debug row shows `HEAT: OFF` in dim grey
>   - Notes:
> - [ ] Tap `HEAT: OFF` → firmware responds `OK:HEATERS_ENABLED`, debug row flips to red bold `HEAT: ON`
>   - Notes:
> - [ ] Tap `HEAT: ON` → SSRs kill immediately (check with multimeter), debug row → grey
>   - Notes:
> - [ ] Home → tap BREW → priming overlay appears on brew screen, button says `START PRIMING` (green)
>   - Notes:
> - [ ] Tap START → pump runs, V1 LOW, V2 LOW, button flips to red `STOP — OVERFLOW SEEN`
>   - Notes:
> - [ ] Tap STOP → pump stops, firmware → `HEATING_BREW`, overlay auto-dismisses, brew screen visible
>   - Notes:
> - [ ] Home → STEAM → overlay, X → dismiss without priming, no firmware action
>   - Notes:
> - [ ] Home → STEAM → START → (priming) → X → `STOP` sent, overlay dismisses
>   - Notes:

## Build 2026-04-21--1318 — Scale FW: line-noise rejection + trimmed mean + zero deadband

Following the audit of `decentespresso/openscale` (see `workplan.md` Scale FW
Audit section). Three of the five tricks implemented; two parked in TODO.

- **#1 Mains-aligned ADC sample rate**: `setSampleRate(NAU7802_SPS_320)` →
  `NAU7802_SPS_20`. Each conversion is now sinc-filtered over 50 ms = 3
  cycles of 60 Hz / 2.5 cycles of 50 Hz mains. The ADC's hardware sinc
  filter is far sharper than the previous boxcar's `sinc(x)` sidelobes (~13 dB)
  at the line frequency.
- **#2 Trimmed-mean boxcar**: replaced the naive `getWeight(true, 32)` with a
  non-blocking 6-sample accumulator that sorts each window, drops the high
  and the low, and averages the middle 4. Implemented via `scale.available()`
  poll in the main loop so the 300 ms output cycle doesn't stall telemetry
  or the state machine. Applies cal/zero manually:
  `w = (avg - getZeroOffset()) / getCalibrationFactor()`.
- **#4 Zero deadband**: `if (fabsf(w) < 0.15) w = 0.0` — kills last-digit
  twitch on an empty cup tray.
- **Tare/cal**: `calculateZeroOffset(16)` (was 32) and
  `calculateCalibrationFactor(_, 32)` (was 64) — sample counts halved because
  each sample now takes 5× longer at 20 SPS; resulting durations 800 ms / 1.6 s.
  Both reset `scaleBufN = 0` so a stale partial window doesn't leak past.
- **`config.h`**: removed `SCALE_READ_INTERVAL` (no longer needed; pacing is
  now driven by ADC ready flag).
- **Compile-verified** on `teensy:avr:teensy40`. Not flashed — user runs
  `tools/flash_and_run.ps1` when ready.

### Testing checklist
> [!warning] Testing Checklist
> - [ ] Tare with empty tray → reads 0.0 g (within deadband, no twitch)
>   - Notes:
> - [ ] Place 100 g reference → reads ~100 g, jitter visibly reduced vs prior build
>   - Notes:
> - [ ] Run a brew cycle → mass curve still tracks smoothly (no obvious lag from 300 ms output cycle)
>   - Notes:
> - [ ] Telemetry stream stays at ~10 Hz (no stalls during scale read window)
>   - Notes:
> - [ ] Cal dialog completes in ~1.6 s, factor saved correctly
>   - Notes:

## Build 2026-04-17--0100 — Invisible exit tap zone

- **Top-right 144×144 invisible tap area** (`exitAppBtn` in main.qml) — mirror of the bottom-right E-stop zone; tap calls `Qt.quit()` to leave fullscreen on the RPi touchscreen.

## Build 2026-04-17--0056 — Teensy hotplug hardening + pcmanfm `quick_exec=1`

- **No more "Execute / Execute in Terminal" prompt** on tap: added `quick_exec=1` to `~/.config/libfm/libfm.conf`. Both `single_click=1` and `quick_exec=1` are now upserted into `[config]` by `setup_rpi.sh` (idempotent).
- **Teensy udev rule `ui/rpi/99-teensy.rules`** → installed to `/etc/udev/rules.d/`: `SUBSYSTEM=="tty", ATTRS{idVendor}=="16c0", ENV{ID_MM_DEVICE_IGNORE}="1", GROUP="dialout", MODE="0660"`. Stops ModemManager from probing the Teensy as a cellular modem on hotplug (it would AT-command the port for several seconds and block the first UI connection). Also ensures dialout access + 0660 perms.
- `setup_rpi.sh` installs the rule and runs `udevadm control --reload-rules` + `udevadm trigger --subsystem-match=tty`.

## Build 2026-04-17--0050 — Tap-to-launch UX + disconnected navigation

- **`SafetyManager` arm-on-first-telemetry**: previously `_safety_check()` fired `emergencyStop("Communication timeout")` every tick from startup when no data had arrived — now a new `armed` flag stays False until the first telemetry packet bumps `last_data_time`, then stays armed until one timeout fires (so exactly one alert per disconnect instead of 60/min). Lets the UI launch cleanly without a Teensy attached for navigation / dev
- **`qml_backend.py` lazy SerialManager import**: introduced `_get_serial_manager_class()` helper called inside `__init__` and `_attempt_reconnection()`. Fixes pre-existing bug where `--mock` was parsed after `from qml_backend import CoffeeController` had already bound the real SerialManager
- **pcmanfm single-click launch**: `~/.config/libfm/libfm.conf` `single_click=1` — one tap on the desktop icon now launches instead of selecting-then-renaming on second tap. Touchscreen-friendly
- **Verified on RPi**: UI launched without Teensy, 0 emergency-stop dialogs in 15s, home screen rendered with RANCILIO logo (SVG now decoding after `qt6-svg-plugins`)

## Build 2026-04-17--0033 — Desktop shortcut

- **Tap-to-launch on RPi desktop**: installed `/home/gram/Desktop/silvia.desktop` that pcmanfm-pi renders as "Silvia Lever" with the logo.svg icon
- **`ui/rpi/silvia.desktop.in`** — template with `@PROJECT_DIR@` placeholder
- **`setup_rpi.sh`** now: (a) renders the template into `$HOME/Desktop/silvia.desktop`, `chmod +x`, and `gio set metadata::trusted true`; (b) installs `qt6-svg-plugins` + `librsvg2-common` and runs `gdk-pixbuf-query-loaders --update-cache` so both Qt's QML `Image` and pcmanfm's desktop icon can render SVGs
- **Verified on RPi**: desktop now shows the "Silvia Lever" label with rendered logo; `dex ~/Desktop/silvia.desktop` launches `run_silvia.py` (confirms tap will work)

## Build 2026-04-17--0020 — RPi live deployment

### Deployed + verified on RPi 4B (192.168.1.33, `gram`)
- **apt install bookworm defaults weren't sufficient** — `setup_rpi.sh` extended to include the Qt/QML runtime modules that don't come with `python3-pyqt6` alone:
  - `qt6-wayland` (Qt Wayland platform plugin — Pi OS Bookworm uses labwc/Wayland by default)
  - `libxcb-cursor0` (XWayland fallback dep)
  - `libqt6svg6` (SVG image decode for `logo.svg`)
  - `qml6-module-qtqml`, `-qtquick`, `-qtquick-window`, `-qtquick-controls`, `-qtquick-layouts`, `-qtquick-shapes`, `-qtquick-templates`, `-qtquick-effects`, `-qtquick-nativestyle`
- **`run_silvia.sh`**: exports `XDG_RUNTIME_DIR` / `WAYLAND_DISPLAY` / `QT_QPA_PLATFORM=wayland` with fallbacks so launches from SSH (without the desktop session env) still reach the compositor
- **Verified fullscreen 1920×1080 on actual touchscreen**: shim reported `raspberry-pi` / scale 2.0 / fullscreen True; QML loaded cleanly after the extra modules; debug row + buttons + gauge all rendered at correct 2× scale
- **Known limitation**: `--mock` flag on `run_silvia.py` is ineffective due to pre-existing import-order bug in `qml_backend.py` (`SerialManager` chosen at module-import time, before args parse). Not blocking — real deployment has Teensy connected

## Build 2026-04-16--2346 — Cross-platform (RPi port via shim)

### Structure
- **Single shared source tree**: renamed `ui/windows/source/` → `ui/source/` — both Windows dev and RPi deployment now run the same Python/QML code
- **Removed stale RPi tree**: `ui/rpi/pyqt6/` (pre-current-architecture — had separate `safety_manager.py`, `temperature_controller.py`, `controls/`, and an outdated `main.qml`) + the old `.txt`/`.rar` build notes
- **`ui/rpi/` now contains only launcher scripts**: `setup_rpi.sh`, `run_silvia.sh`

### Platform shim (`ui/source/platform_shim.py`)
- Detects RPi via `/proc/device-tree/model` (contains "Raspberry Pi")
- Exposes `ui_scale_factor()` → 2.0 on RPi, 1.0 on Windows
- Exposes `default_fullscreen()` → True on RPi
- `apply_qt_env()` sets `QT_SCALE_FACTOR` + `QT_ENABLE_HIGHDPI_SCALING` **before** `QGuiApplication` is constructed — Qt renders the UI at 1920×1080 with crisp fonts instead of scaling a 960×540 bitmap
- Wired into both `main.py` (flash-and-run entry) and `run_silvia.py` (CLI entry with `--mock` / `--port` / `--fullscreen` flags)

### Serial cross-platform (already was, documented)
- `serialcom/real_serial_manager.py` uses Teensy VID (0x16C0) via `pyserial` — same auto-detection works for `COM*` on Windows and `/dev/ttyACM*` on Linux. No code change needed

### RPi deployment scripts
- **`ui/rpi/setup_rpi.sh`** — one-time: `apt install python3-pyqt6 python3-pyqt6.qtquick python3-pyqt6.qtqml python3-serial`, adds user to `dialout` group
- **`ui/rpi/run_silvia.sh`** — launcher that `cd`s to `ui/source/` and execs `python3 run_silvia.py`; shim auto-applies fullscreen + 2× scale

### Tooling
- **`tools/flash_and_run.ps1`**: updated `$UiScript` / `$UiCwd` to `ui/source/`

### Docs
- **workplan.md**: Stage 7 marked DONE; key file reference table updated from `ui/windows/source/` → `ui/source/`
- **`.gitignore`**: `ui/windows/source/logs/` → `ui/source/logs/`; removed dead `ui/rpi/pyqt6/logs/` entry

### Testing checklist
> [!warning] Testing Checklist
> - [ ] Windows: `python main.py` in `ui/source/` → UI launches at 960×540 exactly as before
>   - Notes:
> - [ ] Windows: `tools/flash_and_run.ps1 -NoUpload -NoCompile` launches UI
>   - Notes:
> - [ ] RPi: `setup_rpi.sh` installs deps without error on fresh Bookworm
>   - Notes:
> - [ ] RPi: `run_silvia.sh` launches fullscreen 1920×1080 with 2× font scaling
>   - Notes:
> - [ ] RPi: Teensy auto-detected on `/dev/ttyACM0` via VID 0x16C0
>   - Notes:
> - [ ] RPi touchscreen: all tap targets hittable (brew tap area, E-stop corner, settings ±°C)
>   - Notes:

---

## Build 2026-04-16--2255 — Alpha release

### Scale subsystem
- **Hardware failure resolved**: previous load cell had silently failed; new mechanical assembly installed and verified via `NAU7802_complete_scale` standalone test
- **±0.1 g stability achieved**: switched main firmware to `scale.getWeight(true, 32)` — 32-sample averaging at 320 SPS (~100 ms internal block per read). Stats: range 0.20 g, std dev 0.05 g, mean 99.991 g vs 100 g reference (0.009 % accuracy)
- **Cal factor persists**: stored in `settings.json` as `scale_cal`, restored via `SET_SCALE_CAL` on UI connect. Python guards reject invalid cal results (negative, near-zero, or > 100000) and auto-restore previous good value
- **Cal dialog rewrite**: single modal, auto-tares on open, 1-second cal averaging (32 samples for tare / 64 for cal at 320 SPS)
- **Detailed writeup**: new `SCALE DRIFT, REPEATABILITY, UNCERTAINTY CALCULATIONS.md`

### Plumbing
- **V1 polarity inverted**: de-energised default = pump→thermoblock (heaviest duty); energised = pump→boiler. Saves coil power and heat over time
- **V2 wiring corrected**: IN = portafilter manifold; OUT2 = drain. De-energised default = manifold→drain (instant pressure relief). Energised = manifold↔thermoblock (brewing/flushing)
- **Flush state fixed**: V2 ON during flush (water through portafilter for group rinse / backflush), V2 OFF on stop (immediate pressure release to drain)
- **New docs**: `PLUMBING_NOTES.md` (full water circuit topology, valve port wiring, standing-pressure safety analysis), `silvia VALVES.md`, `silvia PINOUT.md`

### UI overhaul
- **Theme**: black background, white text, white-outline buttons (radius 12) throughout
- **Persistent debug row**: SCALE / PRESS / PUMP / V1 / V2 fields at bottom of every screen, evenly justified, monospace Consolas with fixed-width values (no twitching as digits change)
- **Settings auto-save**: each ±°C tap immediately writes to settings.json + sends `SET_TEMP` to firmware. SAVE button removed
- **Settings UI**: black bg, white outline buttons, back arrow top-left, SCALE section header, ±1°C step (was 0.5)
- **Brew screen**: huge middle tap area starts brew (when ready) or stops brew (when active); no play/stop buttons in header. Mass / Time / Thermoblock at top — Mass left-anchored, Time exactly window-centered, Thermoblock right-anchored, all monospace 48pt with leading-space sign for Mass to keep position constant
- **Charts**: dark grey background, cyan extraction line, purple pressure line, current value top-right of chart, title top-left
- **Cal dialog**: single modal, custom +/− weight selector (visible on black), CALIBRATE button, X close top-right, auto-tares on open
- **Flush + Steam buttons**: single-toggle with depressed/active visual state ("FLUSH" → "FLUSHING" / "STEAM" → "STEAMING")
- **E-stop**: invisible 144×144 tap area at bottom-right corner; fires ABORT + red toast banner top-center for 2.5 s
- **Connection status**: top-right of home screen only (hidden on other screens — assumed stable)
- **Auto-prime on connect removed**: app starts in IDLE; priming only fires when user enters brew screen
- **Cal dialog typo fix**: previously labelled `RECVIEVED` in `data_logger.py` and `visualize_log.py` → `RECEIVED`

### Firmware cleanup
- **SPI hard-reset at top of `setup()`** — required for Teensy 4.0 LPSPI4 + I2C coexistence (the 363 °C bug fix)
- **Init order locked**: SPI reset → actuator safe-state → I2C bus → ADS1115 → pressure zero → PT1000 SPI → NAU7802 last
- **Pump ENA pin D3** — optoisolator gates PWM to motor driver, LOW at boot prevents the brief startup glitch where the motor would twitch before Teensy initialized
- **PUMP_PWM_FULL = 254** — `analogWrite(pin, 255)` outputs constant HIGH (no PWM edges) on Teensy 4.0; motor driver ignores constant HIGH
- **`SCALE_ONLY_DEBUG` flag** in config.h — disables all non-scale sensors at compile time for noise isolation testing (left as a #define for future use)

### Tooling
- **`tools/flash_and_run.ps1`** — one-shot script: kills running UI/Arduino IDE → finds Teensy port via arduino-cli → compiles → uploads → relaunches UI with correct cwd
  - `-NoCompile` skips compile (uses last build)
  - `-NoUpload` skips Teensy upload (UI-only iteration)
  - `-NoUi` skips launching UI (debug via Serial Monitor)

### Test sketches added during the session
- `flow_test/`, `flow_test_v2/`, `flow_test_v3/` — pump + valve + pressure interactive tests with serial commands
- `pump_enable_test/` — ENA polarity + PWM combinations
- `scale_noise_debug/` — toggleable subsystem isolation for NAU7802 noise hunting

### Cleanup
- Removed stray `settings.json` at root (real one in `ui/windows/source/`)
- Removed obsolete `SCALE DRIFT, REPEATABILITY, UNCERTAINTY CALCULATIONS.txt` (superseded by `.md`)
- Replaced `silvia VALVES.txt` and `silvia PINOUT.txt` with `.md` versions
- `.gitignore`: added `/logs/`, `/settings.json`

### Testing checklist
> [!warning] Testing Checklist
> - [x] Scale tare → 0.0 g instantly
>   - Notes: confirmed
> - [x] Scale cal with 100 g → reads 100 g ± 0.1 g
>   - Notes: range 0.20 g, std dev 0.05 g over 776 samples
> - [x] Cal factor persists across UI restart
>   - Notes: restored on connect via SET_SCALE_CAL
> - [x] Pump runs at full speed during prime/flush; stops cleanly on stop
>   - Notes: ENA + PWM 254 working
> - [x] V1/V2 valve states correct in all firmware states
>   - Notes: debug row shows correct labels
> - [x] Flush starts water through portafilter; stop drops pressure to drain
>   - Notes: V2 ON during flush, OFF on stop
> - [x] E-stop invisible tap area triggers ABORT + toast
>   - Notes: 144×144 hit area
> - [x] Settings auto-save on each ±°C tap
>   - Notes: confirmed in settings.json after each tap
> - [ ] PID tuning verified after thermoblock reaches setpoint several times
>   - Notes: pending warm-up cycles
> - [ ] Extended session — no regressions over 30+ minute use
>   - Notes: pending

## Build 2026-04-09--0100

### Changes
- **Pump enable signal (pin D3)** added to firmware:
  - New `PUMP_ENA_PIN 3` in config.h — optoisolator gates PWM to motor driver
  - `LOW` at boot prevents pump startup glitch before Teensy initializes
  - `HIGH` in PRIMING_BREW, PRIMING_STEAM, BREWING, FLUSHING states; `LOW` everywhere else
  - Added to `safeOff()`, `PRIME_DONE` handler, and all state machine cases
- **Pump PWM full speed changed from 255 to 254**: `analogWrite(pin, 255)` on Teensy 4.0 produces constant HIGH (no PWM edges), which motor driver ignores. New `PUMP_PWM_FULL 254` in config.h ensures actual PWM output.
- **Auto-prime on startup removed**: `_auto_start_heating()` no longer fires on connect. App starts in IDLE. Priming begins when user taps Brew button and enters brew screen, where the priming overlay with CONFIRM/CANCEL is visible.
- **Mock serial disabled**: `USE_MOCK_SERIAL = False` in config.py for real hardware testing
- **Typo fixed**: RECVIEVED → RECEIVED in data_logger.py and visualize_log.py
- **Actuator safe-state restored to analogWrite**: Reverted pump/heater pins from `digitalWrite(LOW)` back to `analogWrite(pin, 0)` — FlexPWM timer needs to be configured in setup for later analogWrite calls to work
- **Pinout.txt updated**: Added pin 3 pump enable, corrected brew CS to pin 10
- **Test sketch created**: `pump_enable_test/` — cycles through ENA polarity and PWM combinations with priming valve state

### Testing Checklist
> [!warning] Testing Checklist
> - [x] PT1000 brew reads ~26°C with all I2C enabled
>   - Notes: Confirmed 26.4°C
> - [x] PT1000 steam reads ~26°C
>   - Notes: Confirmed 26.2°C
> - [x] NAU7802 scale reports weight values
>   - Notes: Working
> - [x] ADS1115 pressure sensor reports voltage
>   - Notes: Zero calibrated at 0.548V
> - [x] Pump runs during brew priming (ENA HIGH + PWM 254)
>   - Notes: Working after PWM 255→254 fix
> - [x] Valve clicks heard on priming start
>   - Notes: Working
> - [x] App starts in IDLE (no auto-prime)
>   - Notes: Confirmed
> - [ ] Priming overlay visible on brew screen with CONFIRM/CANCEL
>   - Notes:
> - [ ] CONFIRM stops pump, transitions to HEATING_BREW
>   - Notes:
> - [ ] Communication watchdog doesn't abort priming prematurely
>   - Notes:

## Build 2026-04-07--2100

### Changes
- **Two PT1000 bugs found and fixed:**
  - **Bug 1 (363°C)**: Stale SPI peripheral state on Teensy 4.0's LPSPI4 when I2C libraries linked alongside SPI. Fix: SPI hard-reset at top of `setup()`, I2C init before PT1000 init.
  - **Bug 2 (988.8°C)**: `config.h` had `PT1000_BREW_CS 8` from earlier debug — physical wiring is pin 10. Fix: restored to pin 10.
- **Init order changed in main firmware**: SPI reset → actuator safe-state (digitalWrite, not analogWrite) → I2C/NAU7802 → PT1000 last
- **NAU7802 init sequence fixed**: Added `setSampleRate(NAU7802_SPS_320)` + `calibrateAFE()` — required for stable analog front-end
- **I2C re-enabled in main firmware**: Wire.begin, ADS1115 pressure, NAU7802 scale all restored (were disabled during debug)
- **Pressure and scale loop reads re-enabled**: Uncommented ADS1115 and NAU7802 read blocks in `updateSensors()`
- **Added `#include <SPI.h>`** to main firmware for explicit SPI peripheral control
- **Added `Wire.setClock(400000)`** to I2C init (matches working standalone scale code)
- **All sensors verified working**: brew 26.4°C, steam 26.2°C, pressure 0.548V zero, scale reading
- **Comprehensive debug log written**: `firmware/PT1000_DEBUG.md` — full session narrative, what was tried, what was learned
- **Test sketches created during debug** (in `firmware/test_sketches/`):
  - `pt1000_plus_scale/` — confirmed NAU7802 as culprit
  - `pt1000_plus_relays/` — confirmed relays innocent
  - `pt1000_plus_scale_v2/` — working combined test with SPI reset fix
  - `pt1000_incremental_debug/` — multi-level compile-flag test
  - `pt1000_scale_bisect/` — I2C subsystem bisect test
  - `pt1000_cs_swap/` — CS pin swap diagnostic

### Testing Checklist
> [!warning] Testing Checklist
> - [ ] pt1000_plus_scale_v2 survives 3+ consecutive reflashes without blink between
>   - Notes:
> - [ ] Main firmware compiles and flashes cleanly
>   - Notes:
> - [ ] Brew PT1000 reads ~26°C on main firmware (with all I2C enabled)
>   - Notes:
> - [ ] Steam PT1000 reads ~26°C on main firmware
>   - Notes:
> - [ ] NAU7802 scale reports weight values (scale.begin OK, no INIT_FAILED)
>   - Notes:
> - [ ] ADS1115 pressure sensor reports voltage (adc.init OK, no INIT_FAILED)
>   - Notes:
> - [ ] Telemetry DATA: lines show non-zero pressure and weight fields
>   - Notes:
> - [ ] No PT1000_BREW_FAULT or PT1000_STEAM_FAULT errors in serial output
>   - Notes:

## Build 2026-04-06--1747

### Changes
- **QML syntax fix**: Removed extra closing brace at line 493 of `main.qml` that prevented the app from loading
- **Mock serial enabled**: Set `USE_MOCK_SERIAL = True` in config.py for desktop testing
- **Dependencies installed**: PyQt6 6.11.0 + pyserial 3.5 on Python 3.12
- **TESTING.md created**: Full preliminary testing setup guide and cold test checklist
- **App verified running**: Launches successfully in mock mode, telemetry streaming, QML renders

### Testing Checklist
> [!warning] Testing Checklist
> - [ ] App launches with `python main.py` from `ui/windows/source/`
>   - Notes: Confirmed working. Window opens, mock telemetry streams.
> - [ ] All 4 screens accessible (home, brew, steam, settings)
>   - Notes:
> - [ ] Priming overlay appears on home screen (mock auto-enters PRIMING_BREW)
>   - Notes:
> - [ ] CONFIRM and CANCEL buttons work on priming overlay
>   - Notes:
> - [ ] Temperature display shows mock values (~25°C)
>   - Notes:
> - [ ] Settings screen temp buttons (±0.5°C) adjust values
>   - Notes:

## Build 2026-03-12--1535

### Changes
- **Project restructure**: Separated firmware and UI into top-level directories
  - `firmware/silvia_lever_main/` — main Teensy firmware (was nested inside `UI/rpi/pyqt6/`)
  - `firmware/test_sketches/` — component test sketches (was `teensy test code snippets/`)
  - `ui/` — contains `windows/`, `rpi/`, `Documentation/` (was `UI/`)
- **Pin fixes in config.h** (matched to silvia PINOUT.txt):
  - `HEATER_STEAM_PIN`: 14 → 16
  - `VALVE_PUMP_PIN`: 7 → 21
  - `VALVE_THERMOBLOCK_PIN`: 8 → 20
- **PINOUT.txt updated**: Added missing steam PT1000 CS pin 6, corrected PT100→PT1000 label
- **Firmware compile fix**: Corrected NAU7802 library include from `SparkFun_NAU7802_Scale_Arduino_Library.h` to `SparkFun_Qwiic_Scale_NAU7802_Arduino_Library.h`
- **Windows executable built**: `ui/windows/dist/SilviaLever/SilviaLever.exe` via PyInstaller
  - Bundles main.qml, controls/, svgs/, settings.json
  - Build script at `ui/windows/build_exe.py` for rebuilds
- **workplan.md updated**: All file path references updated to new structure, valve pin numbers corrected

### Testing Checklist
- [ ] Firmware compiles in Arduino IDE for Teensy 4.0 without errors
  - Notes:
- [ ] Pin assignments in config.h match physical wiring on the board
  - Notes:
- [ ] `SilviaLever.exe` launches and shows the home screen
  - Notes:
- [ ] QML UI renders correctly (no missing assets/SVGs)
  - Notes:
- [ ] Mock serial mode works in exe (set `USE_MOCK_SERIAL = True` in config.py and rebuild)
  - Notes:
- [ ] Valve logic verified: priming brew energizes VALVE_PUMP only, brewing energizes both, priming steam de-energizes both, flushing energizes VALVE_PUMP only
  - Notes:
