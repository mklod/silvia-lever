# Status

## Current milestone
**Alpha — thermoblock PID tuned.** First successful autotune complete (Kp/Ki/Kd = 46.94/0.516/3155.89, TL rule). Derivative-on-measurement + low-pass filter added. Boiler still disabled for single-heater focus; S9.7b measured (1.51 A avg maintenance) → Stage 9 concurrent heating unblocked on measurement side, pending implementation.

## Session 2026-05-29 (01:26) — Stage 9 boiler implemented (branch boiler-stage9, pre-hot-test)
- **Fallback locked first:** tag `brew-only-stable` (master HEAD) + fallback hex saved locally and on Pi 1 at `/home/gram/silvia_fw_BREWONLY_FALLBACK.hex`. Boiler work is on branch `boiler-stage9`; master stays brew-only for morning coffee. To restore brew-only: `git checkout brew-only-stable`, or reflash the fallback hex.
- **Boiler enabled, task-switch model (brew XOR steam), firmware only — no current-monitor hardware** (user deferred the CT-clamp idea indefinitely).
  - Dry-fire prime gate: `boilerPrimed` (RAM). `arbitrateHeaters()` blocks all heating until primed. Prime = cold-fill (PRIME_BOILER → overflow → PRIME_DONE).
  - `arbitrateHeaters()`: steaming → thermoblock HARD CUT, boiler active; cold-start → boiler first, thermoblock inhibited until boiler at target; brew/idle → thermoblock active, boiler maintenance only on ticks thermoblock didn't fire (1-tick mutex → ≤8.3 A always).
  - Steam target = steamTemp + 5 °C overshoot. Telemetry +2 fields (boilerPrimed, boilerPreheatComplete). New PRIME_BOILER cmd; BEGIN_STEAM requires primed.
- **UI home reorg:** removed logo + CONNECTED text; two gauges side by side (THERMOBLOCK left w/ BREW+FLUSH, STEAM BOILER right w/ STEAM+PRIME); PRIME glows amber until primed; STEAM disabled until primed.
- **Validated:** firmware compiles (52504 B, hex at L:/tmp-pi-flash/build-boiler/); QML loads headless offscreen+mock, no parse errors, braces balanced.
- **NOT done:** hot test, Teensy flash, Pi deploy — all deferred to a supervised session so morning-coffee fallback stays intact. Next: flash boiler-stage9 + deploy UI + supervised hot test (prime → preheat → steam → brew, clamp-meter ≤8.3 A).

## Session 2026-05-22 (13:19) — light-roast profiles + debug-row cleanup
- Added 3 profiles (5 total): Blooming Allongé (4-seg: fill→bloom→percolate→declining taper — the fruity-light-roast profile), Blooming Espresso (3-seg), Allongé (2-seg). All from PROFILES.md §3.3/§3.4. Compiled, flashed, GET_PROFILES confirms all 5.
- Debug row: removed V1/V2 valve cells (water flow + valves verified working). Row now: heat, brew mode, profile, scale, pressure, pump.
- Gentle & Sweet first brew-test (build 0139): profile engine works — dead-flat 6 bar hold 49 s, zero overshoot. Shot ran slow (~0.59 g/s) — grind too fine for a 6-bar profile (lower pressure needs coarser grind), NOT a profile fault. Channeling visibly improved on bottomless PF.
- Portafilter debug: headspace/channeling root cause = Ascaso group is an E61-*variant*; Silvia PF is Rancilio-pattern → seats wrong. User ordered a couple aftermarket PFs to test. Gasket confirmed preinstalled (non-issue).
- Flash gotcha recurred: backgrounded teensy_loader_cli got SIGHUP'd when the SSH session closed → Teensy left in HalfKay. Re-ran loader directly (already in bootloader) → flashed. Going forward: nohup the loader, or run it foreground.
- Next: brew-test the new profiles, especially Blooming Allongé on a very light roast.

## Session 2026-05-22 (01:39) — Stage 1: brew profile engine + Gentle & Sweet
- Built the segment-table profile engine (PROFILES.md §3.2). A profile = ordered list of `(targetBar, slewRate, gains, exit)` segments; `runBrewSegmentEngine()` plays them through the Stage-0 slew-rate controller. The hardcoded preinfuse/ramp/hold state machine is gone.
- Two profiles: Profile 0 "Standard 9-bar" (faithful Stage-0 re-expression, regression baseline), Profile 1 "Gentle & Sweet" (light-roast starter — flat 6 bar hold).
- `SET_PROFILE`/`GET_PROFILES` serial commands. UI `PROF:` button in the debug row cycles profiles; qml_backend learns the list from firmware (no hardcoded names).
- Compiled clean, flashed, GET_PROFILES verified. **Not yet brew-tested** — Profile 0 regression + Profile 1 6-bar hold need a real shot.
- Flash gotcha: Teensy re-enumeration browned out Pi 1 mid-flash (it had prior "Undervoltage detected!" in dmesg). Power-cycle + re-flash recovered. Pi PSU is marginal — recommend a beefier 5V supply.
- Next light-roast profiles per §3.4: Blooming Allongé, Blooming Espresso, Allongé/Turbo, Adaptive Bloom.

## Session 2026-05-22 (00:36) — Stage 0 brew control finalized (slew-rate), manual takeover, AUTO/MAN toggle
- Brew-overshoot fight resolved. Three control designs tried on the real machine with a fine restrictive grind:
  1. Open-loop PWM ramp → 14 bar.
  2. Closed-loop linear RAMP-sweep + separate HOLD → ~11.5 bar overshoot at RAMP→HOLD boundary. Bumpless transfer / integrator reset / D-term all failed — root cause is pump→pressure transport lag (~200 ms), not tuning.
  3. **Final, working:** single PI(D) loop, one gain set, setpoint *slews* 1.0→9.0 bar at 0.8 bar/sec. Controller always keeps up, integrator self-adapts to puck. Verified zero overshoot, rock-steady 8.9 bar HOLD.
- RAMP + HOLD are now one loop (phase label telemetry-only). Removed `RAMP_MS`, `HOLD_MS`, per-phase `RAMP_*`/`HOLD_*` macros, and `rebaseIntegratorForTransition()`.
- Manual takeover: rotate pot >10% during RAMP/HOLD → bumpless handoff to pot (`handoverOffset` captured, no pressure step).
- AUTO/MANUAL: `autoBrewMode` firmware flag + `SET_AUTO_MODE` serial command + `BREW: AUTO/MAN` UI button (debug row, green/grey). Firmware defaults MANUAL.
- PREINFUSE retuned: 1.0 bar target, exit on 1 g OR 10 s hard cap (`PREINFUSE_MAX_MS`).
- Chart big-numbers freeze on brew stop (final weight/pressure readable after the shot).
- Firmware build/flash workflow established: arduino-cli (bundled w/ Arduino IDE 2.x) → pscp .hex to Pi 1 → teensy_loader_cli + 134-baud reboot. Gotcha: if 134-baud races an in-progress flash, Teensy sticks in HalfKay — just re-run the loader.
- All committed; docs (PROFILES.md §0/§1, CHANGELOG, this file) updated.
- **User flagged more changes coming next.**

## Session 2026-04-24 (20:17) — Pi 2 brought to parity; HDMI artifact narrowed to Silvia hardware

- Pi 2 setup needed several fixes that exposed gaps in `setup_rpi.sh` for Pi OS Lite:
  1. **labwc + kanshi + wlr-randr + seatd not installed by default on Lite** (they ship with the labwc-pi metapackage on Pi OS Full). Added to setup_rpi.sh package list.
  2. **bash_profile `exec /usr/bin/labwc`** caused getty start-rate-limit loop on headless boot (no display → labwc fails → bash exits → getty restarts → fail). Dropped the `exec` so bash falls through to interactive shell when no display is present. With display attached, labwc never returns until shutdown.
  3. **`pscp -r` from Windows strips +x bit** on `run_silvia.sh` and `run_silvia.py` → labwc autostart silently fails. Added defensive `chmod +x` early in setup_rpi.sh.
  4. **`quiet splash plymouth.ignore-serial-consoles` not in Pi OS Lite cmdline.txt** (Pi OS Full had them by default). Without `splash`, plymouth-start runs but draws nothing → kernel/systemd messages flood tty1 visibly. Added to cmdline patch loop.
  5. **`~/.config/kanshi/config` only auto-created by labwc-pi wrapper** (Pi OS Full). On Lite using plain labwc, no kanshi config = panel renders landscape instead of portrait. Bake the rotation profile into setup_rpi.sh.
  6. **`~/.config/labwc/rc.xml` not present on Pi OS Lite** (no labwc-pi installation). Without rc.xml's `<touch deviceName=... mapToOutput=...>`, touch coordinates stay in raw (un-rotated) space while display is rotated 90° → touch appears mirrored. Added `ui/rpi/labwc-rc.xml` to the repo and setup_rpi.sh installs it.
- Pi 2 now boots cleanly to either silvia kiosk (default) or pcmanfm desktop (debug mode), with touch correctly rotated and labwc + kanshi + silvia all autostarting.

### HDMI cold-boot artifact diagnostic

Pi 2 was used as an A/B reference for the pre-firmware HDMI panel artifact that the Silvia hardware shows on cold boot (bright/jarring "garbage" before kernel KMS comes up).

| Setup | Touch FW | Artifact |
|---|---|---|
| Silvia panel + Silvia driver board | yes | **YES** |
| Bench panel + bench driver board   | yes (working) | **NO** |

So the artifact is NOT a generic "any touch firmware" issue — both setups have working touch FW now. **Variable causing the artifact is specific to the Silvia hardware combination** (panel, driver board, or board FW version).

Next decisive tests (require physical swap):
- Connect **Silvia panel** to **bench driver board**: if artifact disappears, the driver board is the cause. If it persists, panel is.
- Connect **Silvia driver board** to **bench panel**: if artifact appears there, board is cause. If not, panel is.

Either swap isolates root cause. Until done, GPIO/MOSFET hardware delay fix is on hold — the cause may be firmware-side on the driver board, in which case a FW config bit (e.g. "show test pattern on boot" debug flag) might be the entire fix with no electronics added.

## Session 2026-04-24 (15:55) — Stage 0 brew control, chart freeze, Pi 2 ready, Teensy flashed
- First hot test brew log analysed: PREINFUSE worked (2.53 bar at exit), but open-loop RAMP slammed fine grind to 13.97 bar peak; HOLD's P-only couldn't recover in 3 s; pot-controlled EXTRACT was too weak. Root cause: only PREINFUSE was closed-loop on pressure.
- **Stage 0 firmware shipped**: shared `pumpClosedLoop()` PI helper with anti-windup. RAMP rewritten as closed-loop pressure-target sweep (2.5→9.0 bar over RAMP_MS, no more PWM blast). HOLD made indefinite (removed HOLD_MS gate; user STOPs the brew). EXTRACT now manual-override only. I-term added everywhere.
- **Compiled** with arduino-cli (bundled with Arduino IDE 2.x at C:\Users\mklod\AppData\Local\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe), `--fqbn teensy:avr:teensy40`. Output to L:\tmp-pi-flash\build\silvia_lever_main.ino.hex (191 KB).
- **Flashed** via `teensy_loader_cli` on Pi 1 (already installed). Soft-reboot trick: `python3 -c "import serial; serial.Serial('/dev/ttyACM0', 134); ..."` — Teensy USB Serial special baud 134 enters bootloader without physical button press. Booting confirmed.
- **UI freeze**: main.qml chart big-numbers freeze on BREWING→IDLE transition, clear on next BREWING. Live debug row keeps flowing. Pushed to Pi 1, rebooted, verified.
- **Pi 2 (silvia-pi-2 / 192.168.1.30)** is a complete drop-in replacement card. Setup via WSL-less workflow: dd-stream xz decompression → \\.\PhysicalDrive raw write via PowerShell-launched dd-for-Windows, cloud-init for first boot. Latest local working tree pscp'd, setup_rpi.sh ran clean. bash_profile updated to drop `exec` on labwc so headless boot doesn't trigger getty rate-limit loop. Boot 10.7 s headless. Will run full kiosk with HDMI + Teensy attached.
- Workflow established: edit firmware locally → arduino-cli compile → pscp .hex to Pi 1 → teensy_loader_cli + 134-baud reboot → flash. End-to-end ~30 sec from edit to running on the espresso machine.
- Next: brew test the new firmware. RAMP should sweep cleanly with no overshoot. If still high, drop RAMP_KP / RAMP_BASE_PWM. Then move to Stage 1 (named profile menu).

## Session 2026-04-24 (03:13) — plymouth black splash + invisible cursor, 8.04 s boot
- Plymouth re-enabled with custom all-black theme. Covers ~one of the two terminal text flashes during boot. Attempted to stretch coverage by masking plymouth-quit.service, but that deadlocks boot (plymouth-quit-wait blocks multi-user.target). Reverted. One residual flash remains in the plymouth-quit → getty → labwc window.
- Invisible cursor: `XCURSOR_THEME=empty` pointing at a user-local theme where every cursor file is a 1×1 transparent PNG (xcursorgen from python-generated PNG). Wired via `~/.config/labwc/environment`. Touch+mouseEmulation still works from labwc rc.xml.
- Pre-firmware display artifact is hardware-only: HDMI OLED panel powered off USB 5V which is live from moment-zero. Pi 4B can't cut USB power in software (VL805 hub). Discussed A/B/C options; user considering Pi 5 (2 GB is plenty for this workload — current usage is ~450 MiB on 4 GB Pi 4B).
- Boot best: 8.04 s (2.44 kernel + 5.61 userspace). 1× labwc, 1× kanshi, 1× silvia. Pending visual confirmation of cursor + flash-count from user.
- Next potential work if user cares enough: convert labwc startup from getty/bash_profile path to a systemd service so `plymouth-quit.service` can be ordered `After=labwc.service` — would close the last flash.

## Session 2026-04-24 (02:46) — kill desktop flash (labwc --config-dir isolation)
- Desktop/wallpaper/panel briefly visible before silvia = labwc-pi running `/etc/xdg/labwc/autostart` (pcmanfm-pi + wf-panel-pi + lxsession-xdg-autostart) unconditionally. A user-level `~/.config/labwc/autostart` did NOT override it — both ran, producing duplicate kanshi + duplicate silvia instances.
- Fix: skip `labwc-pi` wrapper entirely, bash_profile now `exec /usr/bin/labwc --config-dir ~/.config/labwc -m`. `--config-dir` pins labwc to one config dir — system autostart is never read.
- Post-reboot: 1× labwc, 1× kanshi, 1× silvia. No pcmanfm-pi, no wf-panel-pi, no lxsession-xdg-autostart. Duplicate silvia eliminated. Boot 9.22 s (2.50 kernel + 6.71 userspace).
- Baked into `setup_rpi.sh`. Pi env still inherited via `. /usr/bin/setup_env` (labwc-pi sourced it too).
- Two terminal flashes may still remain — plymouth black splash is the final option if user wants to fully eliminate them (~0.5 s cost).

## Session 2026-04-24 (02:36) — kill boot terminal flashes
- Cold boot still flashed a couple of terminal-text screens between firmware and labwc. Root cause: kernel + systemd + getty were spraying text onto tty1 — the same VT labwc takes over.
- Three-part fix:
  1. `console=tty1` → `console=tty3` in `/boot/firmware/cmdline.txt` (kernel/systemd output → invisible VT)
  2. agetty `--noissue --nohostname` + `TTYVTDisallocate=no` on the override (kills banner, smoother VT handoff)
  3. `~/.hushlogin` (silences pam_motd + last-login message during autologin)
- Boot 9.94 s (similar to 8.8 s, within noise). labwc + silvia confirmed autostarting via SSH — visual confirmation pending user cold-boot test.
- All baked into `setup_rpi.sh`. Pi backup at `/boot/firmware/cmdline.txt.pre-tty3-bak`.

## Session 2026-04-24 (02:28) — getty autologin race fixed (Type=idle), 8.8 s boot
- First reboot after the L2→L1 revert landed at the bare login prompt: agetty stuck in `(agetty)` state, autologin never fired, labwc/silvia never launched. `After=systemd-user-sessions.service` alone was not sufficient to beat the pam_nologin race.
- Added `Type=idle` to `/etc/systemd/system/getty@tty1.service.d/autologin.conf`. `Type=idle` holds the unit until systemd reports no other units are starting — enough extra slack for pam to clear pam_nologin consistently.
- Next reboot: labwc (pid 735) + silvia (pid 858) both came up automatically. Also boot time dropped: **10.6 s → 8.8 s** (systemd-analyze: 2.856 s kernel + 5.967 s userspace). Total reduction from baseline: 26.3 → 8.8 s (67%).
- Baked into `setup_rpi.sh` so fresh deploys get it. Comment block updated to explain the two-part fix (After= **and** Type=idle — neither alone is reliable).

## Session 2026-04-24 (02:10) — L2 reverted to L1, KIOSK.md created
- L2 (cage) tried — boot was 10.0 s but broke touch (libinput matrix not auto-rotated), showed persistent mouse cursor, and added two extra boot-screen flashes. Reverted to L1 (labwc-pi via getty autologin), boot now 10.6 s — within noise of L2.
- L2 leftover packages (cage, wlr-randr) kept installed; harmless when bash_profile points at labwc-pi.
- All other L2-era changes are orthogonal and stayed: NM→networkd swap, `systemd-networkd-wait-online` disable, static /etc/resolv.conf, getty autologin with `After=systemd-user-sessions`.
- New `KIOSK.md` at project root: boot-time journey (26.3 → 10.6 s, 60% reduction), things-tried-that-didn't-help log, L3 (Qt eglfs) and L4 (Alpine / Buildroot / Yocto / no-systemd) options with realistic estimates, deep dives on Buildroot + Yocto, honest "stop here" recommendation.
- `setup_rpi.sh` updated to write the L1 bash_profile (was L2 cage version) so a fresh deploy reproduces the working end state.

## Session 2026-04-24 (01:53) — L2 kiosk via cage (boot 11.7 s → 10.0 s)
- Replaced lightdm + labwc + pcmanfm-pi + wf-panel-pi with `cage -s -- silvia` directly. tty1 autologin fires `~/.bash_profile` which exec's cage. cage spawns wlr-randr (rotation fix for the portrait-native 1080×1920 panel) then silvia.
- Boot history: **26.3 → 10.0 s** total wall-clock from baseline (62% reduction). Multi-user.target at 6.59 s userspace.
- Two boot-race / DNS gotchas fixed and baked into `setup_rpi.sh`:
  - `getty@tty1.service` needs `After=systemd-user-sessions.service` or pam_nologin rejects the autologin
  - `/etc/resolv.conf` goes blank when NM is disabled (no auto-regen by networkd unless systemd-resolved is running) → write static fallback
- L1 (just removing lightdm) was a near-no-op (~0.3 s). L2 (skip the whole desktop stack) was the real win — pcmanfm-pi + wf-panel-pi spawning was the actual cost.
- Snapshots pre+post-L2: `silvia-rpi-snapshot-2026-04-24-0130.tar.gz` (L1) and `silvia-rpi-snapshot-2026-04-24-0153.tar.gz` (L2 current).
- Rollback: `cp ~/.bash_profile.l1.bak ~/.bash_profile && sudo reboot` reverts to L1 in 30 sec.

## Session 2026-04-24 (01:18) — NM → systemd-networkd swap (boot 15 s → 11.7 s)
- Swapped NetworkManager for `systemd-networkd` + `wpa_supplicant@wlan0`. WiFi association moved off the boot critical path. **graphical.target now at 7.45 s userspace** (was 11.07), total cold-boot to interactive ≈ 11.7 s (was 15.0).
- Done under `silvia-deadman` protection (10-min auto-revert). Confirmed clean within 30 s of reboot.
- NM kept on disk for one-command rollback (see `RPI_RESTORE.md`).
- `setup_rpi.sh` made idempotent for the swap (only fires if `wpa_supplicant-wlan0.conf` exists; protects WiFi creds from being baked into repo).
- Snapshots taken pre+post: `silvia-rpi-snapshot-2026-04-24-0041.tar.gz` (NM) and `silvia-rpi-snapshot-2026-04-24-0118.tar.gz` (networkd).

## Session 2026-04-24 (00:40) — Pi backup/restore + deadman + boot-trim post-mortem
- **Pi state snapshot**: `tools/rpi_snapshot.sh` tarballs every changed config + audit lists. First baseline saved to NAS.
- **`silvia-deadman` installed** on Pi (`/usr/local/bin/`). Generic auto-rollback timer for risky changes — arms a `systemd-run --on-active=Nm` transient that runs a revert command if user can't `confirm` in time. Smoke-tested arm/confirm cycle clean.
- **`RPI_RESTORE.md`** captures: snapshot contents + Path A (from tarball) and Path B (from scratch) restore recipes, per-change reversion commands, deadman usage with NM-swap example.
- **Boot-time post-mortem**: pushed from 26 → 15 s. Hit a structural floor at 15 s; documented in `setup_rpi.sh` header what was tried and abandoned (fastboot, IPv6 disable, BT disable, drop-in After/Before= resets, direct unit edits) so we don't re-explore. Real next steps for sub-15: A2 SD card (drop-in), systemd-networkd swap (config rewrite + deadman armed), USB SSD (hardware).

## Session 2026-04-23 (23:28) — HOLD phase + RPi boot trim + UI autostart
- **HOLD phase added** between RAMP and EXTRACT — closed-loop 9 bar for 3 s lets pump speed settle before user takes manual control. brewPhase enum now 0-3, backend + PROFILES.md updated.
- **RPi boot-time wins**: disabled `NetworkManager-wait-online` (5.9 s), masked entire `cloud-init` chain (~13 s), disabled `cups`/`bluetooth`/`ModemManager`/`rpi-eeprom-update`/`rpi-resize-swap`. Baseline 26 s → expected 13-15 s post-reboot.
- **UI autostart on boot**: `setup_rpi.sh` installs `~/.config/autostart/silvia.desktop`. Exec points to `run_silvia.sh` which always reads live `ui/source/` files, so scp'd updates take effect on next boot with no rebuild step.

## Session 2026-04-23 (21:09) — Auto preinfuse + brew recorder + PROFILES.md
- **Auto preinfuse landed** (firmware sub-state machine in STATE_BREWING): closed-loop P at 2.5 bar until 5 g in cup → 4 s linear PWM ramp to full → manual pot control. Tunables in `config.h`.
- **Per-brew JSON recorder** (`ui/source/brew_recorder.py`): every shot dumps to `brew_logs/brew_YYYY-MM-DD_HH-MM-SS.json` with metadata + 10 Hz samples. Substrate for Stage 8 profile derivation.
- **DATA telemetry** now 14 fields (added `brewPhase`).
- **`PROFILES.md`** created: documents current preinfuse + brew JSON schema + sketches Stage 8 named-profile system (schema, control modes, player loop, profile derivation from recordings).

## Session 2026-04-24 (02:24) — Thermoblock cold-start ramp measured
- **~58 s at 8.3 A continuous** to climb 25 °C → 88 °C (bang-bang handoff to PID). Captured via WiFi plug CSV (85 samples).
- Refines Stage 9 cold-start budget: boiler 6 min sequential + thermoblock ~1 min concurrent with boiler maintenance = **~7 min total cold → ready-to-brew + steam-available**.
- HEATING.md §1 / §5 updated with measurement + budget table; workplan S9.7c marked done.

## Session 2026-04-23 (17:19) — First successful PID autotune
- **Autotune ran end-to-end on hot thermoblock**: `Ku=142.9, Tu=139 s, a=1.14 °C → TL Kp=46.94, Ki=0.516, Kd=3155.89`. Auto-applied; persisted in `settings.json`; backend re-sends on every reconnect.
- **Three autotune bugs fixed:**
  - Asymmetric-period bug — was summing only heating halves ×2, so Tu underestimated ~3× → Kd came out wrong. Now sums every half-period.
  - Sanity bounds mismatch between autotune and `SET_PID` — autotune accepted new Kd, then restore rejected it. Bounds now identical (Kp<500, Ki<50, Kd<5000).
  - Hysteresis + timeout too tight — widened 0.5 → 1.0 °C, 10 → 25 min timeout.
- **Derivative-on-measurement + first-order low-pass filter** (`PID_D_FILTER_TAU = 2 s`) added to PID. Needed because TL's `Ku·Tu/6.3` = 3156 would noise-amplify raw PT1000 jitter. Filter lets real thermal slopes through, kills sensor noise.
- **`HEATING.md` updated** with asymmetric-period handling, widened bounds, derivative filter math, first-autotune result in revision log.

## Session 2026-04-23 (02:34) — PID autotune + bang-bang warmup + HEATING.md
- **Layered thermoblock control**: bang-bang full duty when `error > 5 °C`, PID when within band. Fixes first-hot-test overshoot.
- **Relay-feedback autotune** (`AUTOTUNE_START/STOP`) lands in firmware. UI Settings → PID → AUTOTUNE opens a live-log modal. Auto-applies Tyreus-Luyben gains on success; Python persists to `settings.json` + re-sends `SET_PID` on every reconnect.
- **Runtime PID gains** — `sys.kp/ki/kd` now mutable, seeded from `config.h`. New `SET_PID` command.
- **Test-mode config**: `heatersEnabled` default TRUE, boiler `controlSteamHeater()` calls removed. Flip both back before shipping.
- **New `HEATING.md`** — dedicated reference doc for thermal control, PID tuning procedure, Stage 9 dual-heater staggering design, SSR wiring notes.
- SSR wiring confirmed: L → SSR T1 → T2 → thermal fuse → element → N (SSR on hot side so element is isolated when off).

## Session 2026-04-22 (13:35) — Heater master switch + priming popup rewire

## Session 2026-04-22 (13:35) — Heater master switch + priming popup rewire
- **Firmware**: added `SystemData.heatersEnabled` (default OFF) gating both SSRs; `SET_HEATERS_ENABLE <0|1>` command; 13th field `heatersEnabled` in DATA packet. Compile-verified on Teensy 4.0.
- **Backend**: parses new field, `heatersEnabledChanged` signal + `setHeatersEnabled(bool)` slot. Removed the `_auto_primed_brew` auto-skip.
- **QML**: tap-to-toggle `HEAT: ON/OFF` cell in the persistent debug row (red bold when ON). Priming overlays rewired — window-level `brewPrimingOpen` / `steamPrimingOpen` properties decouple overlay visibility from firmware state; single START/STOP toggle (green↔red, based on `currentState == "PRIMING_*"`); `×` dismisses with optional abort; overlay auto-dismisses on STOP.
- **Flash pending**: user runs `tools/flash_and_run.ps1` when ready. RPi unreachable at push time (192.168.1.33 host unreachable), so QML/backend not yet copied to Pi.

## Session 2026-04-17 (00:52) — Tap-to-launch + disconnected navigation

## Session 2026-04-17 (01:00) — Tap-exit, Teensy hotplug hardening, pcmanfm UX
- **Exit tap zone** (`main.qml`): invisible 144×144 top-right MouseArea fires `Qt.quit()` — mirror of bottom-right E-stop. Lets the user leave fullscreen on the RPi without a keyboard.
- **pcmanfm `quick_exec=1`**: added to `~/.config/libfm/libfm.conf` so tapping a `.desktop` icon executes directly instead of popping the "Execute / Execute in Terminal" dialog. Together with `single_click=1` → true one-tap launch.
- **Teensy udev rule** (`ui/rpi/99-teensy.rules` → `/etc/udev/rules.d/`): `SUBSYSTEM=="tty", ATTRS{idVendor}=="16c0", ENV{ID_MM_DEVICE_IGNORE}="1", GROUP="dialout", MODE="0660"`. Prevents ModemManager from AT-probing the Teensy for ~5 s on hotplug (would block first UI connection). Also pins group/perms.
- **`setup_rpi.sh`** now idempotently: upserts libfm `[config]` keys, installs the udev rule + reloads, renders + trusts the desktop shortcut, runs `gdk-pixbuf-query-loaders --update-cache`.
- Verified: after all fixes, tapping the shortcut single-tap launches fullscreen with 0 dialogs.

## Session 2026-04-17 (00:52) — Tap-to-launch + disconnected navigation
- **UI runs cleanly without Teensy** — `safety_manager.py` now arm-on-first-telemetry (flag stays False until first packet), so no "EMERGENCY STOP: Communication timeout" spam when no hardware connected. Fires exactly once per disconnect event when previously armed.
- **Fixed `--mock` bug**: `qml_backend.py` now picks Mock vs Real SerialManager inside `__init__` via `_get_serial_manager_class()` helper. Previously bound at module load before CLI args parsed.
- **pcmanfm single-click**: `~/.config/libfm/libfm.conf` `single_click=1`. Touchscreen tap now launches instead of selecting/renaming.
- **Verified**: home screen rendered cleanly with RANCILIO logo visible, 0 error dialogs over 15s.

## Session 2026-04-17 (00:43) — Desktop shortcut on RPi
- Added `ui/rpi/silvia.desktop.in` template; `setup_rpi.sh` renders it to `~/Desktop/silvia.desktop` with correct paths, chmods +x, marks trusted via `gio`.
- Installed `qt6-svg-plugins` + `librsvg2-common` + ran `gdk-pixbuf-query-loaders --update-cache` → fixes both Qt's QML SVG rendering (for logo inside the app) AND pcmanfm's desktop-icon SVG rendering. Added to `setup_rpi.sh`.
- Desktop now shows "Silvia Lever" icon with logo; `dex` test confirmed shortcut launches the UI.

## Session 2026-04-17 (00:20) — RPi live deployment
- **Deployed to RPi 4B at 192.168.1.33** (user `gram`, Pi OS Bookworm, aarch64, labwc/Wayland).
- `scp`'d `ui/source/` and `ui/rpi/` to `/home/gram/silvia-lever/ui/`, ran `setup_rpi.sh`.
- **Additional packages discovered needed** (added to `setup_rpi.sh`): `qt6-wayland`, `libxcb-cursor0`, `libqt6svg6`, and the full set of `qml6-module-qtquick-*` runtime modules. `python3-pyqt6` alone is insufficient on Bookworm.
- `run_silvia.sh` updated to export Wayland env vars (XDG_RUNTIME_DIR, WAYLAND_DISPLAY, QT_QPA_PLATFORM) with fallbacks so SSH launches work.
- **Verified fullscreen 1080p rendering**: screenshot via `grim` shows BREW/STEAM/FLUSH buttons, 25°C gauge arc, DISCONNECTED indicator top-right, full debug row (SCALE/PRESS/PUMP/V1/V2) at bottom — all at correct 2× font scale. Platform shim reports `raspberry-pi`, scale 2.0, fullscreen True.
- **Pre-existing bug surfaced**: `--mock` flag ineffective because `qml_backend.py` imports `SerialManager` at module load before argparse runs. Not blocking real deployment (Teensy will be plugged in). Fix deferred.
- **SVG logo**: `libqt6svg6` installed but main.qml:339 still logs "Unsupported image format" on `logo.svg` — deferred (cosmetic only).

## Session 2026-04-16 (late) — RPi port via platform shim
- **Shared source tree**: `ui/windows/source/` → `ui/source/`. Same Python/QML runs on Windows dev and RPi.
- **`platform_shim.py`**: detects RPi via `/proc/device-tree/model`, sets `QT_SCALE_FACTOR=2.00` (1080p target = 2× the 960×540 Windows dev layout) and enables fullscreen by default. Qt renders natively at scaled size so fonts stay crisp — no QML edits required.
- **Wired into both entry points**: `main.py` (flash-and-run) and `run_silvia.py` (CLI with `--mock`/`--port`/`--fullscreen`). `apply_qt_env()` runs before `QGuiApplication` is constructed.
- **RPi launchers**: `ui/rpi/setup_rpi.sh` (apt deps, dialout group) + `ui/rpi/run_silvia.sh`.
- **Serial already cross-platform**: `serialcom/real_serial_manager.py` uses Teensy VID (0x16C0) via `pyserial`; auto-detects `COM*` on Win, `/dev/ttyACM*` on Linux. Zero code change.
- **Stale tree removed**: `ui/rpi/pyqt6/` (diverged pre-alpha), plus old `.txt`/`.rar` build notes.
- **Tooling**: `tools/flash_and_run.ps1` paths updated to `ui/source/`; `.gitignore` updated.
- **Docs**: workplan Stage 7 → DONE (80% total); key file table updated; CHANGELOG entry.
- **Verified on Windows**: `python main.py` loads QML, backend imports, Teensy auto-connects on COM9 — confirmed rename + shim didn't break anything.

## Last session (2026-04-16)
- **Scale subsystem solved end-to-end**:
  - Old load cell had silently failed (replaced with new mechanical assembly)
  - Switched to `getWeight(true, 32)` for 32-sample averaging → ±0.1g stability with cal factor 2050.65
  - Cal factor persists in `settings.json`; restored automatically on UI startup
  - Tare must still be done after each session (not persisted in firmware)
  - Scale stats writeup: `SCALE DRIFT, REPEATABILITY, UNCERTAINTY CALCULATIONS.md`
- **Plumbing finalized**:
  - Inverted V1 polarity so de-energised default = pump→thermoblock (heaviest duty)
  - V2 wiring: portafilter manifold on V2 IN; OUT2=drain (de-energised default → instant pressure relief)
  - Flush state corrected: V2 ON during flush (water through portafilter); V2 OFF on stop (drains pressure)
  - Plumbing notes + safety analysis: `PLUMBING_NOTES.md`
- **UI overhaul**:
  - Black background, white text, white-outline buttons throughout
  - Auto-save settings on each ±°C tap (no SAVE button)
  - Persistent debug row (SCALE / PRESS / PUMP / V1 / V2) at bottom of all screens with monospace, fixed-width values
  - Cal dialog: single modal, auto-tares on open, 1-second cal averaging (was 6.4 s at low SPS)
  - Brew screen: tap-anywhere-in-middle to start/stop brew, no play/pause buttons
  - Flush + Steam buttons converted to single-toggle with active "depressed" state
  - E-stop: invisible 144×144 bottom-right tap area, fires ABORT + red toast banner
- **Firmware cleanup**:
  - SPI hard-reset at top of `setup()` (Teensy 4.0 LPSPI4 stale-state fix)
  - Pump ENA on D3 (optoisolator gate, prevents boot glitch)
  - PUMP_PWM_FULL = 254 (255 outputs constant HIGH on Teensy 4.0)
  - NAU7802 init order: I2C → ADS1115 → pressure cal → PT1000 SPI → NAU7802 last
- **Tooling**:
  - `tools/flash_and_run.ps1` — one-shot compile/upload/launch via arduino-cli with `-NoCompile -NoUpload` flags for UI-only iteration
- **Doc cleanup**: removed stray `.txt` duplicates and root `settings.json`; `.gitignore` updated for `logs/`

## Next immediate task
- Plug Teensy into RPi → verify `/dev/ttyACM0` enumerates, UI flips to CONNECTED, telemetry streams
- Extended brew + steam + flush sessions on real hardware; collect logs for drift / regressions
- Tune PID after warming the thermoblock to setpoint a few times
- Autostart silvia on RPi boot (labwc-pi autostart entry or systemd --user unit)
- Decide on profile system (Stage 8) after a few weeks of real-world use

## Blockers
- None

## Key decisions
- SPI hard-reset at top of `setup()` is mandatory for SPI+I2C on Teensy 4.0
- NAU7802 init must include `setSampleRate` + `calibrateAFE`; init last in setup()
- Use `getWeight(true, 32)` for the scale read — single-call averaging gives ±0.1 g
- Both 3-way valves wired so the de-energised default is the most-used state (saves coil power and heat)
- V2 IN = portafilter manifold (NOT thermoblock outlet) — puts pressure sensor and relief path on the same physical port
- Cal factor lives in UI `settings.json` (not EEPROM); restored via SET_SCALE_CAL on connect
- Zero offset is firmware-RAM only; user re-tares each session (deliberate, simple)
- Pump ENA gate on D3 + PUMP_PWM_FULL = 254 are both required for the FG300 motor driver
- RPi port uses single shared `ui/source/` tree + `platform_shim.py` (not a separate RPi fork). Qt's native `QT_SCALE_FACTOR=2` handles 1080p scaling — no per-widget font edits needed.
- RPi Teensy access: udev rule `/etc/udev/rules.d/99-teensy.rules` is mandatory on Bookworm to stop ModemManager from hijacking the port on hotplug.
- Safety manager watchdog is arm-on-first-telemetry: never fires until a real packet has been received, so navigation-without-hardware is silent.
