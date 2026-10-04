# 06 — Maintenance & troubleshooting

> **TL;DR** — Nothing updates by itself. New builds come from the Telegram channel
> https://t.me/Jayedupdate (flash by hand). A ROM update keeps your data, tuning
> and DenyList but **wipes root** (A-only) — re-root after. USB flaky → Wi-Fi ADB.

## Where new firmware comes from

These builds are **unofficial**, maintained by the community (not the LineageOS
project). There is no built-in OTA — you follow these sources and flash new zips
by hand. Primary hub for the `blossom` family (Redmi 9A/9C/10A/Poco C3):

| Source | What | Link |
|---|---|---|
| Telegram channel | release announcements: LineageOS 23.2, crDroid 12.x, Axion, AICP, OrangeFox | https://t.me/Jayedupdate |
| Telegram group | support / "What is blossom" device list | https://t.me/jayedupdatecommunity |
| Telegram cloud | build files mirror | https://t.me/mycloudblossom |
| SourceForge | the actual zips | https://sourceforge.net/projects/blossom-uploads/files/ |
| crDroid (official) | crDroid 12.x for blossom + install guide | https://crdroid.net/blossom |
| crDroid OTA (GitHub) | machine-readable latest build + md5 | https://github.com/crdroidandroid/android_vendor_crDroidOTA/blob/16.0/blossom.json |
| Device tree (GitHub) | sources (confirms `angelican` support) | https://github.com/crdroidandroid/android_device_xiaomi_blossom |
| XDA thread | crDroid 12.11 discussion | https://xdaforums.com/t/rom-official-16-0-crdroidandroid-12-11-for-blossom.4794608/ |

To update to a newer build: download its zip (verify checksum), reboot to LineageOS
recovery, Apply from ADB → sideload. For a same-ROM upgrade you can skip the data
format; re-root afterward (A-only device — see below). Alternatives if you want to
try another ROM for working NFC: **crDroid 12.12** (newer) or **Axion** (claims
working IMS/VoLTE) — both from the same hub.

## Will anything break automatically? No.

- This is an **unofficial** build: no OTA server is configured
  (`settings get global ota_url` → empty), and `ota_disable_automatic_update=1`.
  The LineageOS Updater app has nothing to pull. **The system never updates by
  itself.** New versions arrive only as zips you flash by hand in recovery.
- **App auto-updates** (Play Store / RuStore) do **not** affect root, the memory
  tuning, or DenyList. Update apps freely.

## What survives a system (ROM) update, what doesn't

| Item | Location | Survives OTA/dirty-flash? |
|---|---|---|
| Memory tuning (`redmi9c-tweaks`) | `/data/adb/modules/` | ✅ |
| Magisk settings + DenyList | `/data/adb/magisk.db` | ✅ |
| Apps and their data | `/data` | ✅ |
| `gpumem-abort-fix` module | `/data/adb/modules/` | ⚠️ survives, but its patch is build-specific — **reinstall after a ROM update** |
| **Root (Magisk boot patch)** | `boot` partition | ❌ — rewritten by the update |

A-only device ⇒ a system update overwrites `boot` ⇒ **root is lost and must be
re-applied**. Everything else persists — **except** that `gpumem-abort-fix` carries a
patched `libmeminfo.so` built for the *previous* system image; a ROM update replaces
the real `libmeminfo`, so **remove and reinstall the module** after updating (its
`customize.sh` re-derives the patch, and its byte-guard refuses if the build differs
— see [09 §8](09-gpu-mem-reboot.md)).

## Re-rooting after a ROM update

```bash
# extract boot.img from the new ROM zip you just flashed
unzip -o lineage-23.2-NEW.zip boot.img -d new-boot/

scripts/host/reroot-after-ota.sh new-boot/boot.img     # pushes to phone
#   -> in Magisk app: Install -> Select and Patch a File -> Download/boot.img
scripts/host/reroot-after-ota.sh --pull-flash          # pulls patched + flashes
```

Then re-apply `adb root` convenience (Developer options → Root access → ADB is
usually retained; `scripts/host/adb-connect.sh` restores the live `adb root`).

## Everyday connection

USB on this unit drops constantly — use **Wi-Fi ADB** (`:5555`, pinned in
Developer options):

```bash
scripts/host/adb-connect.sh         # connect + restore root
```

If it goes `offline`/`unauthorized`: `adb kill-server && adb start-server`, then
reconnect. After a reboot, re-run `adb-connect.sh` (root reverts to shell on boot).

## Checking stability

```bash
scripts/host/stability-monitor.sh 120     # 2-hour sample
# reports: new soft-reboots (dropbox ground truth), min free RAM, peak zram
```

Healthy numbers: free-RAM floor well above 0 (we see ~97 MB), zram actively used
(hundreds of MB), soft-reboots ≈0–1 per couple of hours.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Hourly soft-reboot at a fixed minute | **Fixed.** A GPU-mem eBPF `abort()` in `libmeminfo` — install the `gpumem-abort-fix` module. Full analysis: [09](09-gpu-mem-reboot.md). |
| Frequent soft-reboots return | Memory pressure. Check `memtune.sh` applied: `adb shell 'getprop ro.lmk.psi_partial_stall_ms'`→70, `cat /proc/sys/vm/min_free_kbytes`→24576. Close heavy apps; consider disabling more background apps. |
| `memtune.sh` not applied after boot | Magisk disabled, or script lost its +x / wrong path. Check the module ran: `/data/adb/modules/redmi9c_tweaks/` has `post-fs-data.sh` + `service.sh` (mode 755) and no `disable` file. Log: `/data/local/tmp/redmi9c-tweaks.log`. |
| Bank app says "device not secure" | Re-tick it in Magisk DenyList; ensure Zygisk on. Last resort: TrickyStore + keybox. |
| `su`/root gone after reboot | Expected for `adb root`; re-run `adb-connect.sh`. If Magisk `su` itself is gone, the boot patch was overwritten (OTA) — re-root. |
| adb `offline`/drops on USB | Use Wi-Fi `:5555`. For big transfers prefer Wi-Fi or `adb sideload` (resumes). |
| High `load average` (~10) but phone fine | Cosmetic — MTK idle D-state kernel threads (display/modem/charger). Not a problem. |
| NFC won't turn on | Known-broken on this build; it was removed. No userspace fix. |

## Rolling back to MIUI (if ever needed)

The MIUI 12.5.3 fastboot package reflashes a clean stock system:

```bash
cd angelican_ru_global_images_V12.5.3.0.RCSRUXM_*/
./flash_all.sh                 # keeps bootloader unlocked
# ./flash_all_lock.sh          # ALSO re-locks bootloader (stock + locked)
```

Re-locking is only safe on a fully stock, same-region image — which this is.
MIUI debloat afterwards: `scripts/miui/debloat.sh` (see [data/packages/](../data/packages/)).

---

**← [05 — Memory tuning](05-memory-tuning.md)**  ·  **[07 — Dev environment →](07-dev-environment.md)**  ·  [↑ README](../README.md)
