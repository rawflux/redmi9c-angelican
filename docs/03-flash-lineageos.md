# 03 — Flash LineageOS 23.2

> **TL;DR** — Order matters: **MIUI 12.5 (Android 11) base → LineageOS recovery →
> format data → sideload ROM + GApps → reboot.** The ROM ships no modem/vendor
> firmware, so the R-based MIUI base must be flashed first.

The OrangeFox maintainer states the vendor is **"R-based — do not flash in Q"**:
Q = Android 10 (stock MIUI 12.0.14), R = Android 11. Hence the base must be
**MIUI 12.5 (Android 11)** before the custom ROM.

## 0. Prerequisites

- Bootloader unlocked ([02](02-unlock-bootloader.md)), `fastboot getvar unlocked` → yes.
- Files downloaded and checksum-verified ([data/downloads.md](../data/downloads.md)):
  LineageOS zip, NikGapps core, MIUI 12.5.3 fastboot tarball.
- **Remove all Google accounts** before wiping, or FRP (Factory Reset Protection)
  locks setup afterwards.
- Back up everything — this wipes the device twice.
- `adb sideload` tolerates this unit's flaky USB better than a raw `fastboot flash
  super`; still, have the most reliable cable/port ready.

## 1. Base firmware — MIUI 12.5.3 (Android 11)

Flash with the stock script, **without re-locking** (`flash_all.sh`, not
`flash_all_lock.sh`):

```bash
tar xzf angelican_fastboot_12.5.3_RU.tgz
cd angelican_ru_global_images_V12.5.3.0.RCSRUXM_*/
./flash_all.sh            # checks product==angelican, anti-rollback, then flashes
```

`flash_all.sh` contains **no `oem lock`** — the bootloader stays open. It flashes
preloader, modem (`md1img`), tee, `super`, etc., then reboots. First boot ≤10 min.
Confirm: Settings → About → MIUI **12.5.3.0.RCSRUXM**, Android 11.

## 2. Recovery — LineageOS recovery (bundled in the ROM zip)

No separate download — it is inside the ROM zip:

```bash
unzip -o -j lineage-23.2-*-blossom.zip recovery.img boot.img -d lineage-imgs/
adb reboot bootloader
fastboot flash recovery lineage-imgs/recovery.img
```

**Critical:** boot straight into recovery, not the OS — MIUI overwrites custom
recovery on its next boot. From fastboot, hold **Volume-Up + Power** until the MI
logo, then release. You should land in LineageOS recovery (`adb get-state` →
`recovery`/`sideload`, model `lineage_blossom`).

## 3. Format, then sideload ROM + GApps (one recovery session)

In recovery:

1. **Factory reset → Format data / factory reset.** Removes MIUI encryption;
   without it LineageOS won't boot or see storage. Use **Format**, not just *Wipe*.
   You do **not** need to wipe `system`/`cache` (the ROM remaps `super` itself and
   `ota-required-cache=0`).
2. **Apply update → Apply from ADB**, then on the PC:

```bash
adb sideload lineage-23.2-*-blossom.zip
# then, WITHOUT rebooting, re-select "Apply from ADB" on the phone and:
adb sideload NikGapps-core-arm64-16-20260222-signed.zip
```

NikGapps is signed by its own key, so recovery warns *"Signature verification
failed — install anyway?"* → **Yes** (expected for any third-party zip).

3. **Reboot to system.** First boot of Android 16 takes several minutes.

## 4. First boot

- Skip Wi-Fi/accounts during setup if you may re-flash again (saves redoing it).
- Re-enable **Developer options → USB debugging**, and turn on **Wireless
  debugging** (this unit's USB is unreliable — Wi-Fi ADB is the stable path; the
  Magisk module later pins it to `:5555`, see [07](07-dev-environment.md)).

Verify:

```bash
adb shell getprop ro.build.version.release   # 16
adb shell getprop ro.product.cpu.abilist     # arm64-v8a,...  (now 64-bit)
adb shell getprop ro.boot.flash.locked       # 0  (unlocked)
```

## Gotchas seen

- **NFC** never initializes (`dumpsys nfc` stuck `turning_on`); removed with
  `pm uninstall -k --user 0 com.android.nfc`. If you need tap-to-pay, this build
  isn't for you — see the NFC note in [06](06-maintenance.md).
- The vibrator HAL returns `NaN`, Wi-Fi scan and VoLTE spam `EINTR` — all cosmetic
  log noise, **not** the cause of any instability ([05](05-memory-tuning.md) ruled
  the modem out).
- Sideload drops mid-transfer on bad USB → `adb kill-server && adb start-server`,
  re-select *Apply from ADB*, retry. The block transfer resumes cleanly.

---

**← [02 — Unlock the bootloader](02-unlock-bootloader.md)**  ·  **[04 — Root & banking →](04-root-and-banking.md)**  ·  [↑ README](../README.md)
