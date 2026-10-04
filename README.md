# Redmi 9C NFC (angelican) → LineageOS 23.2 / Android 16

Reproducible setup, hardening and **memory-stability engineering** for a Xiaomi
Redmi 9C NFC turned into a lean development-and-banking phone on Android 16.

The hard part of this project was not flashing — it was making a **3 GB MediaTek
device survive Android 16 without OOM soft-reboots**. That investigation and its
fix are documented in full in [docs/05-memory-tuning.md](docs/05-memory-tuning.md).

## Device

| | |
|---|---|
| Model | Redmi 9C NFC — `M2006C3MNG`, codename **`angelican`**, family `blossom` |
| SoC / RAM | MediaTek Helio G35 (MT6765), **3 GB** |
| From | MIUI 12.0.14 (Android 10, 32-bit) |
| To | **LineageOS 23.2 UNOFFICIAL, Android 16, 64-bit** |
| Root | Magisk 30.7 (A-only device — no A/B slots) |
| ADB | **Wi-Fi `192.168.1.100:5555`** — USB drops constantly, use wireless |

## Final state

- Clean 64-bit Android 16; snappier and lighter than stock MIUI.
- Root via Magisk; **banking apps work with stock Zygisk + DenyList** (no
  TrickyStore/Shamiko needed): Sber, Alfa, T-Bank, T-Business.
- Memory tuned and made durable via a Magisk module (`redmi9c-tweaks`) — OOM soft-reboots cut
  from **6–30/hour to ~1 per 2 hours** (the 3 GB physical floor).
- A separate hourly soft-reboot was **root-caused and fixed**: `libmeminfo`'s
  per-process GPU-memory accounting `abort()`ed because this MTK build has no
  `gpu_mem` eBPF map; the 2-byte `gpumem-abort-fix` module makes it degrade
  gracefully — see [docs/09](docs/09-gpu-mem-reboot.md).
- **NFC does not work** on this build (service hangs in `turning_on`) — removed.

## Quickstart

```bash
# connect over Wi-Fi and restore root (USB is unreliable on this unit)
scripts/host/adb-connect.sh

# check the memory-stability numbers for yourself (2 h sample)
scripts/host/stability-monitor.sh 120
```

The durable memory fix ships as the **`redmi9c-tweaks` Magisk module**
(`magisk-module/redmi9c-tweaks/`). It applies at every boot and survives OTA
updates (it lives in `/data`). See [docs/07](docs/07-dev-environment.md).

## Documentation

Read in order to reproduce the build; jump straight to **05** for the engineering.

| # | Doc | What it covers |
|---|---|---|
| 01 | [Overview](docs/01-overview.md) | device facts, architecture, what works, conventions |
| 02 | [Unlock the bootloader](docs/02-unlock-bootloader.md) | Mi-Unlock: phone-number gate, 168 h timer, safe timer check |
| 03 | [Flash LineageOS](docs/03-flash-lineageos.md) | MIUI base → recovery → format → sideload ROM + GApps |
| 04 | [Root & banking](docs/04-root-and-banking.md) | Magisk root (A-only); bank integrity via Zygisk + DenyList |
| 05 | [**Memory tuning**](docs/05-memory-tuning.md) | the OOM soft-reboot investigation and fix — core of this repo |
| 06 | [Maintenance](docs/06-maintenance.md) | firmware sources, OTA behavior, re-rooting, troubleshooting, rollback |
| 07 | [Dev environment](docs/07-dev-environment.md) | the Magisk module, scrcpy mirroring, Termux |
| 08 | [Hourly reboot: the investigation](docs/08-hourly-reboot-investigation.md) | the detective story — dead ends, and the `PTRACE_SEIZE` catcher that cracked it |
| 09 | [GPU-mem abort: root cause & fix](docs/09-gpu-mem-reboot.md) | **solved** — a GPU-mem eBPF abort in `libmeminfo`, fixed with a 2-byte patch (`gpumem-abort-fix`) |

## Repository map

```
docs/                     01–09, the guide above
data/
  downloads.md            every binary: official source URL + SHA-256
  packages/               keep/remove app lists (debloat reference)
magisk-module/
  redmi9c-tweaks/         memory tuning + persistent Wi-Fi ADB
  gpumem-abort-fix/       2-byte libmeminfo patch (stops the hourly reboot, docs/09)
scripts/
  device/                 on-device: memtune.sh (standalone), termux-setup.sh
  host/                   PC-side: adb-connect, check-unlock, screen (scrcpy),
                          stability-monitor, reroot-after-ota
  miui/                   MIUI debloat/restore (fallback path only)
tools/
  sigcatch.c              PTRACE_SEIZE signal catcher (root-caused docs/08–09)
```

Large binaries (ROM images, GApps, APKs) are **not** committed — they are
copyrighted and multi-GB. [data/downloads.md](data/downloads.md) lists every one
with its official source and checksum so the setup is fully reproducible.

## Credit & caveats

The LineageOS 23.2 / crDroid / Axion builds for `blossom` are **unofficial**,
maintained by the community — primary hub is the Telegram channel
https://t.me/Jayedupdate (see [docs/06-maintenance.md](docs/06-maintenance.md) for the
full list of firmware sources). They carry no warranty.
Everything here is for a device the author owns. Re-flashing voids the warranty
and wipes the device.

## License

MIT — see [LICENSE](LICENSE). Provided as-is, no warranty. Flashing an unofficial
ROM voids the manufacturer warranty and wipes the device; proceed at your own risk.
