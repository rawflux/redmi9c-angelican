# Changelog

Chronological record of the project (Sep 22 – Oct 4, 2026).

## Phase 1 — MIUI debloat (Sep 22–23)
- Connected the stock device (MIUI 12.0.14, Android 10, 32-bit) over ADB.
- Removed MIUI ads/telemetry/auto-installers and unused preinstalls across three
  passes: 297 → 197 packages. Scripts: `scripts/miui/`, lists: `data/packages/`.
- Installed Telegram from telegram.org (signature verified).

## Phase 2 — Bootloader unlock (Sep 23 – Oct 1)
- Hit `code 20041` (no phone number on Mi account); bound a number.
- Bound device to Mi-Unlock; waited out the 168 h timer (lost the first week to an
  accidental account sign-out that reset it). Tracked remaining time safely with
  `scripts/host/check-unlock.py`.
- Unlocked on Oct 1 (`fastboot getvar unlocked` → yes).

## Phase 3 — Flash LineageOS 23.2 / Android 16 (Oct 1)
- Flashed MIUI 12.5.3 (Android 11) as the required R-based firmware base.
- Flashed LineageOS recovery (bundled in ROM zip); sideloaded the ROM + NikGapps
  core in one recovery session; formatted data.
- Verified: Android 16, 64-bit, unlocked. NFC found broken (service hangs) → removed.

## Phase 4 — Root + banking (Oct 1–3)
- Magisk 30.7: patched boot.img, flashed (A-only device).
- Restored apps; installed Sber/Alfa/T-Bank/T-Business from official sources
  (signatures verified). AmneziaVPN swapped to arm64 build.
- Banking integrity passed with **stock Zygisk + DenyList** — no TrickyStore needed.

## Phase 5 — Memory stability engineering (Oct 3)
- Diagnosed frequent soft-reboots as `system_server` SIGABRT under **memory
  exhaustion** (not modem/VoLTE/kernel, which were ruled out with evidence).
- Rejected disk-swap / more-zram (zram was 93 % idle — reclaim latency, not
  capacity, was the bottleneck).
- Applied durable tuning (`scripts/device/memtune.sh`, via Magisk service.d):
  lmkd PSI 70/200, min_free 24 MB, watermark 200, zram zstd 2 GB, swappiness 100,
  max_cached_processes 12.
- **Result: soft-reboots 6–30/h → ~1 per 2 h; free-RAM floor 23–39 MB → 97 MB;
  zram 120 MB idle → 776 MB working.** Full writeup: `docs/05-memory-tuning.md`.

## Phase 6 — Dev tooling (Oct 3)
- Packaged the memory tuning as the `redmi9c-tweaks` Magisk module (replaces the
  loose service.d script); made Wi-Fi ADB persistent (`persist.adb.tcp.port 5555`).
- Hardened the module (v1.1.0): removed boot-time risk windows — no `stop/start
  lmkd` (use `lmkd.reinit`), no zram rebuild at boot (swapoff window). Found while
  a scrcpy launch exposed a ~65 s post-boot soft-reboot caused by the module itself.
- Added scrcpy launcher (screen.sh) and Termux + on-device toolchain (termux-setup.sh).

## Phase 7 — Repository & docs (Oct 3)
- Organized the whole project into this documented, reproducible repo.
- Reworked all docs for clarity: per-doc TL;DR, consistent prev/next navigation,
  a guided reading table in the README, and a consolidated firmware-sources section.

## Phase 8 — Hourly soft-reboot investigation (Oct 3)
- Found a second, non-memory soft-reboot: system_server SIGABRT (SI_QUEUE) ~hourly,
  ~118 MB free. Ruled out (with evidence) memory, kernel panic, scrcpy, and a loud
  Wi-Fi secondary-STA loop (disabling Adaptive Connectivity stopped the loop but NOT
  the reboot — corrected a premature "fixed" claim).
- Blocked by broken crash tooling (debuggerd can't dump system_server → no
  tombstone/abort message). Full record: docs/08-hourly-reboot-investigation.md.

## Phase 9 — Hourly soft-reboot: root cause & fix (Oct 4)
- Built a `PTRACE_SEIZE` catcher (tools/sigcatch.c, static aarch64) that catches the
  live SIGABRT without freezing the process; read exact siginfo + registers + stack.
- Root-caused it: `libmeminfo::ReadPerProcessGpuMem` opens the eBPF map
  `/sys/fs/bpf/map_gpuMem_gpu_mem_total_map`, which this MTK build never creates (no
  `gpu_mem/gpu_mem_total` tracepoint — the kernel has `mtk_get_gpu_memory_usage`).
  The fd is negative and an inner helper `abort()`s instead of degrading. bionic's
  `abort()` here uses `rt_tgsigqueueinfo` → the SIGABRT/SI_QUEUE/self-pid/no-message
  masquerade; the broken crash_dump hid it.
- Fixed with a **2-byte binary patch** of `libmeminfo.so` (route fd<0 to the
  function's own graceful return), shipped as the systemless `gpumem-abort-fix`
  Magisk module (patches on-device at install; no binary in git).
- **Verified against the symptom:** system_server ran continuously for hours across
  the old crash window with the dropbox SYSTEM_RESTART count unchanged. Full write-up:
  docs/09-gpu-mem-reboot.md.
