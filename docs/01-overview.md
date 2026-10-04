# 01 — Overview

> **TL;DR** — A 3 GB Redmi 9C NFC turned into a lean 64-bit Android 16 phone for
> dev + banking. The hard part was memory stability, not flashing. Read the docs
> in order; `05` is the one worth reading even if you own a different device.

## Goal

A lean phone for development and banking: a modern Android for current app/API
testing, root for full control, and reliable banking apps — all on 3 GB of RAM.

## Device facts (verified on-device)

| Property | Value | How checked |
|---|---|---|
| Model | Redmi 9C NFC, `M2006C3MNG` | `getprop ro.product.model` |
| Codename | `angelican` (family `blossom`) | `getprop ro.product.device` |
| SoC | MediaTek Helio G35 / MT6765 | `getprop ro.board.platform` |
| RAM | 3 GB (2770 MB usable) | `/proc/meminfo` |
| Partitions | **A-only** (no A/B slots) | `fastboot getvar current-slot` → not found |
| Boot | dynamic partitions (`super`) | `getprop ro.boot.dynamic_partitions` |

The A-only layout has one lasting consequence: **every system update overwrites
`boot`, so root is lost on each OTA** and must be re-applied ([06](06-maintenance.md)).

## Why LineageOS over stock MIUI

Stock MIUI here is Android 10, **32-bit**, ad-laden, and EOL (no security patches
past June 2022). LineageOS 23.2 gives Android 16, **64-bit**, a clean AOSP base,
and — confirmed in daily use — faster UI and boot. The trade-offs: the `blossom`
builds are **unofficial** (community-maintained, no warranty) and **NFC does not
work** on them.

## Final architecture

```
┌─ LineageOS 23.2 (Android 16, 64-bit, kernel 4.19 "sashimi") ───────────┐
│                                                                        │
│  Apps: Sber, Alfa, T-Bank, T-Business, Ozon, Telegram, AmneziaVPN, …   │
│         └─ banking integrity passes via Magisk DenyList (Zygisk)       │
│                                                                        │
│  Root: Magisk 30.7  (patched boot.img — A-only, re-root on each OTA)   │
│                                                                        │
│  Stability: Magisk `redmi9c-tweaks` (memory tuning — lmkd PSI ·        │
│    kernel reserves · max_cached) + `gpumem-abort-fix` (libmeminfo       │
│    2-byte patch — stops the hourly GPU-mem abort, docs/09)             │
└────────────────────────────────────────────────────────────────────────┘
          ▲ ADB over Wi-Fi 192.168.1.100:5555  (USB is unreliable here)
```

## What works / what does not

| Subsystem | Status |
|---|---|
| Calls, SMS, mobile data, dual SIM | ✅ |
| Wi-Fi, Bluetooth, camera, fingerprint | ✅ |
| 64-bit apps, Play Services (NikGapps core) | ✅ |
| Banking apps (integrity via DenyList) | ✅ |
| **NFC** | ❌ service hangs `turning_on`; removed |
| Stability | ~1 soft-reboot per couple of hours at the 3 GB floor ([05](05-memory-tuning.md)); the separate hourly reboot is **fixed** ([09](09-gpu-mem-reboot.md)) |

## Conventions used in these docs

- **ADB is over Wi-Fi.** `192.168.1.100:5555` is a **placeholder — replace it with
  your phone's Wi-Fi IP** (scripts accept it as an argument or the `PHONE` env var).
  This unit's USB drops constantly, so wireless debugging is the stable path;
  `scripts/host/adb-connect.sh` connects and restores `adb root`.
- Placeholders in commands (`<dev>`, `<file>`) are yours to fill in.
- Binaries are never in the repo; every one is listed with source + checksum in
  [data/downloads.md](../data/downloads.md).

---

**Next:** [02 — Unlock the bootloader →](02-unlock-bootloader.md)  ·  [↑ README](../README.md)
