# 05 — Memory stability: the OOM soft-reboot investigation

> **TL;DR** — Android 16 on 3 GB soft-rebooted every few minutes. Root cause:
> `system_server` aborting under **memory exhaustion** (not modem/kernel — those
> were ruled out). Fix: make reclaim faster/earlier (lmkd PSI + kernel reserves),
> **not** add swap (zram was 93 % idle). Result: **6–30/h → ~1 per 2 h.**

This is the core engineering of the project. It documents the diagnosis —
including the hypotheses that were **wrong** and why — and the fix, with
measurements. Worth reading even if you own a different low-RAM device.

## Symptom

The UI restarted ("boot animation, then home screen") every 2–14 minutes — a
**soft reboot**: `system_server` dies and Zygote respawns the framework, without a
kernel reboot. Confirmed via `dropbox`: **33 `SYSTEM_RESTART` records** accumulated.

## Method

Root-level evidence, ground-truth metrics, no guessing:

- `dumpsys dropbox` / `/data/system/dropbox/SYSTEM_RESTART*` — restart count & time.
- `/sys/fs/pstore/` — would hold a kernel panic log (it was **empty** → not a panic).
- `logcat -b crash,events,all` — the death signal and the event just before it.
- `/proc/meminfo`, `free`, `am_meminfo` events — memory state at the moment of death.

## Hypotheses — and why the first ones were wrong

1. **Kernel panic in a driver.** ❌ `pstore` empty, no tombstone, last reboot
   reason was `reboot,shell` (manual). Not a kernel crash.
2. **MediaTek modem / CCCI driver.** Plausible at first: logcat was full of
   `ccci_rpcd: Failed to read ... errno=4 (EINTR)` and `VoLTE IMSM: Interrupted
   system call`, and kernel threads `ccci_fsm1/ccci_poll1` sat in **D state**,
   inflating load average to ~10. ❌ But `top` showed the CPU **~87 % idle** — the
   D-state threads are normal MTK idle behavior, cosmetic to load average, and the
   modem spam was bursty, not correlated with the deaths. Load ≠ the problem.
3. **A Java Watchdog kill.** ❌ No `WATCHDOG KILLING SYSTEM PROCESS` line, and the
   `SYSTEM_RESTART` reports had **no Java stack** — so not the framework Watchdog.

Tempting but discarded: disabling VoLTE. Waiting for hard evidence avoided a
pointless change to calling behavior.

## Root cause (proven)

The crash buffer caught the actual death:

```
F libc : Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid NNNN
         (binder:2776_4), pid 2776 (system_server)
```

`system_server` aborts (SIGABRT) **in a binder thread** — a native abort while
handling an IPC call, no Java stack. And the line immediately before it, in the
same thread:

```
I am_meminfo: [268038144, 26705920, 0, 333717504, 376741888]
```

`am_meminfo` is ActivityManager logging memory thresholds under pressure; the
`~26 MB` free figure is the tell. **The soft-reboots were driven by memory
exhaustion**: on 3 GB, the heavy apps (the Google app alone held ~240 MB across 4
processes, plus Sber/Alfa/T-Bank/Yandex) drove free RAM toward zero, and on a fast
spike a binder allocation in `system_server` aborted, taking the framework down.

### Confirmation

Freeing ~1 GB (disabling the Google app + restricting heavy apps' background) made
`system_server` survive 17+ minutes immediately, vs 2–14 before. The cause was
memory, full stop.

## Why more swap is NOT the fix (a measured dead end)

A natural instinct is "add swap." The data says no:

- `zram` was **93 % empty** (120 MB used of 1662 MB) **at the moment of the
  crashes**, with 200+ MB free RAM on the later ones.
- So the bottleneck was never **swap capacity** — it was **reclaim latency**: a
  heavy app grabbed hundreds of MB faster than lmkd/swap could react, hitting the
  wall before reclaim engaged.
- A **disk swapfile** would therefore not help either, and would add eMMC wear and
  jank on this slow flash (`/data` is f2fs). **Rejected.**

The correct lever is **faster, earlier reclaim**, so a spike never reaches zero.

## The fix — `scripts/device/memtune.sh`

Three independent levers, applied at boot (persisted via Magisk `service.d`):

### 1. lmkd reacts to pressure sooner (PSI-based)

lmkd here is **PSI-driven** (`ro.lmk.use_psi=true`), so the legacy `minfree_levels`
are ignored — the real knobs are the PSI stall thresholds. Halving them makes lmkd
kill cached apps at the first sign of pressure:

```
ro.lmk.psi_partial_stall_ms   135 -> 70
ro.lmk.psi_complete_stall_ms  540 -> 200
ro.lmk.thrashing_limit         55 -> 40
```

These are read when lmkd starts, so the script sets them with `resetprop` and then
`stop lmkd; start lmkd` to reload.

### 2. Bigger kernel reserve + earlier kswapd

Give background reclaim a head start before a spike reaches true zero:

```
vm.min_free_kbytes         ~6500 -> 24576   (~24 MB emergency reserve)
vm.watermark_scale_factor     10 -> 200     (kswapd wakes much earlier)
```

### 3. Bias the VM toward using swap, and hold fewer processes

```
vm.swappiness         80 -> 100     (prefer zram over dropping file cache)
vm.page-cluster        3 -> 0        (swap one page at a time, no read-ahead)
max_cached_processes  32 -> 12      (60 app processes → ~16–32)
```

> **Revised after testing — zram is left at stock.** An earlier version of the
> boot script rebuilt zram as zstd 2 GB. It measurably helped under steady load
> (zram went from 120 MB idle to 776 MB used), but rebuilding zram at boot needs a
> `swapoff` → `reset` → `mkswap` → `swapon` sequence, which **removes swap entirely
> for a window right after boot** — exactly when apps are launching and pressure is
> highest. That window caused a soft-reboot ~65 s into boot. Since zram **capacity
> was never the bottleneck** (it sat 93 % idle during the original crashes), the
> denser zram bought nothing that justified the risk. Stock lz4 zram is kept; the
> swappiness/page-cluster bias above is enough to make it absorb spikes.

### A note on *how* lmkd is reloaded

The PSI params are set in `post-fs-data` (before lmkd starts) and applied with
`setprop lmkd.reinit 1` — a **gentle reload**. An earlier version did
`stop lmkd; start lmkd` in the late service script; that briefly leaves the system
with **no low-memory killer at all**, and during the post-boot pressure window it
could itself trigger the very abort we were fixing. Never restart lmkd under load —
use `lmkd.reinit`, or set the props before lmkd first starts.

## Results (measured)

| Stage | Soft-reboots | Free-RAM floor | zram peak |
|---|---|---|---|
| Baseline | every 2–14 min (6–30/h) | 23–39 MB | 120 MB (idle) |
| Debloat only (freed ~1 GB) | ~1 / hour | ~1 GB, falling | — |
| **Full tuning (clean boot)** | **~1 per 2 h** | **97 MB** | **776 MB (working)** |

A **~20–60× reduction**. zram went from idle to doing real work (776 MB absorbed),
and the free-RAM floor tripled. The single remaining reboot per ~2 h is a rare
spike that no userspace tuning catches on 3 GB — the physical ceiling of the device.

## Durability & reversibility

`memtune.sh` lives in `/data/adb/service.d/`, runs at every boot, and survives OTA
(it is in `/data`, not the system image). It is wiped only by a data format.
`max_cached_processes` is also persisted independently via `device_config`.
To revert everything: delete the script and reboot — all values return to stock.

## If you need it even more stable

Not a tuning problem — a capacity one. The only real moves: run fewer heavy apps
concurrently (the dominant variable), accept the rare soft reboot, or use a device
with more RAM. Everything tunable has been tuned.

The tuning is packaged as the `redmi9c-tweaks` Magisk module — see
[07 — Dev environment](07-dev-environment.md) for how it is installed and why the
early-vs-late split (`post-fs-data` vs `service`) matters.

A **separate**, non-memory soft-reboot (hourly) was found later, root-caused (a
GPU-mem eBPF `abort()` in `libmeminfo`) and fixed. The hunt is in
[08 — the investigation](08-hourly-reboot-investigation.md); the mechanism and the
2-byte fix are in [09 — GPU-memory abort](09-gpu-mem-reboot.md).

---

**← [04 — Root & banking](04-root-and-banking.md)**  ·  **[06 — Maintenance →](06-maintenance.md)**  ·  [↑ README](../README.md)
