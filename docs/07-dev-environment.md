# 07 — Dev environment & tooling

> **TL;DR** — The tuning + persistent Wi-Fi ADB ship as the `redmi9c-tweaks`
> Magisk module. Add scrcpy (screen mirroring) and Termux (on-device shell) for a
> complete dev setup over the wireless link.

The phone doubles as a development/testing target. These are the pieces that make
that ergonomic, all built around the stable **Wi-Fi ADB** link (USB is unreliable).

## Magisk module: `redmi9c-tweaks`

The memory tuning and persistent Wi-Fi ADB are packaged as a proper Magisk module
(`magisk-module/redmi9c-tweaks/`) instead of a loose `service.d` script — it is
versioned, cleanly removable, and guarded to this device (`customize.sh` aborts if
`ro.product.device != angelican`).

| File | Runs | Does |
|---|---|---|
| `post-fs-data.sh` | early (before lmkd/adbd) | lmkd PSI props + `lmkd.reinit`, `persist.adb.tcp.port 5555` |
| `service.sh` | late (post-boot) | vm reserves (`min_free`, `watermark`, `swappiness`), `max_cached_processes`, Wi-Fi scan-churn reduction, enable adbd TCP |
| `customize.sh` | install time | device guard + perms |

Build & install:

```bash
cd magisk-module/redmi9c-tweaks && zip -qr ../redmi9c-tweaks.zip .
# flash the zip in the Magisk app (Modules -> Install from storage), then reboot.
```

> Note: `magisk --install-module` from the CLI extracted only `module.prop` on this
> build; installing the zip from the **Magisk app** copies all files correctly. If
> you must use the CLI, verify `post-fs-data.sh`/`service.sh` landed in
> `/data/adb/modules/redmi9c_tweaks/` and copy them in manually if not.

After this module, `memtune.sh` in `service.d` is redundant — remove it.

### Second module: `gpumem-abort-fix`

A separate systemless module (`magisk-module/gpumem-abort-fix/`) carries the 2-byte
`libmeminfo` patch that stops the hourly `system_server` soft-reboot. It patches at
install from the device's own library (no binary shipped), is guarded to this device
and build, and must be **reinstalled after a ROM update**. Build/install and the full
rationale are in [09 — GPU-memory abort](09-gpu-mem-reboot.md).

## Persistent Wi-Fi ADB

The module sets `persist.adb.tcp.port 5555`, so adbd listens on TCP at every boot —
no manual `adb tcpip` needed. From the host:

```bash
scripts/host/adb-connect.sh      # connect + restore `adb root`
```

## Screen mirroring — scrcpy

`scripts/host/screen.sh` wraps scrcpy with settings tuned for this device and a
wireless link (capped resolution/bitrate, phone panel off while mirroring):

```bash
scripts/host/screen.sh              # mirror + control
scripts/host/screen.sh --record demo.mp4
```

Host needs `scrcpy >= 2.0` (`pacman -S scrcpy` on Manjaro — this repo was built
with 4.1).

## On-device shell — Termux

Termux (`com.termux`, v0.118.3, official GitHub build) gives a real Linux shell on
the phone for on-device scripting/testing. After first-run bootstrap, provision a
lean toolchain:

```bash
# inside the Termux app:
pkg install -y curl
curl -sL <repo-raw>/scripts/device/termux-setup.sh | bash
```

Installs git, python, node LTS, openssh, rsync, jq, ripgrep, fd, tmux, termux-api.
`sshd` (port 8022) lets you SSH into the phone from the host over Wi-Fi.

> Installing large APKs / heavy `pkg` compiles can spike memory enough to trigger a
> soft-reboot on 3 GB (we saw it during Termux's own install). If an install
> destabilizes the phone, close background apps first to free headroom — same
> ceiling discussed in [05-memory-tuning.md](05-memory-tuning.md).

## Handy references

```bash
scripts/host/stability-monitor.sh 120     # memory/reboot health sample
scripts/host/reroot-after-ota.sh ...       # re-root after a ROM update
```

---

**← [06 — Maintenance](06-maintenance.md)**  ·  **[08 — Hourly reboot investigation →](08-hourly-reboot-investigation.md)**  ·  [↑ README](../README.md)
