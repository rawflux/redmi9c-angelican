# 09 — The GPU-memory abort: root cause & fix (detailed)

> **TL;DR** — The hourly `system_server` soft-reboot is a self-inflicted `abort()`
> in `libmeminfo`. The framework periodically accounts per-process GPU memory via an
> eBPF map (`/sys/fs/bpf/map_gpuMem_gpu_mem_total_map`). This MediaTek build never
> creates that map (the kernel lacks the AOSP `gpu_mem/gpu_mem_total` tracepoint), so
> `libmeminfo` gets a negative fd and **aborts instead of degrading gracefully**.
> bionic's `abort()` here is delivered via `rt_tgsigqueueinfo`, which is why the
> crash looks like an external `SIGABRT (SI_QUEUE)` with no abort message. The fix is
> a **2-byte binary patch** of `libmeminfo.so` that routes the `fd<0` path to the
> function's own graceful return, shipped as the systemless `gpumem-abort-fix`
> Magisk module. This is the detailed reference; the *investigation* (how it was
> hunted and caught) is in [08](08-hourly-reboot-investigation.md).

## 1. Symptom

`system_server` dies with `SIGABRT (signal 6), code -1 (SI_QUEUE)` in a binder
thread roughly once an hour. Zygote respawns the framework (a **soft** reboot — the
kernel never reboots, `/proc/uptime` keeps climbing). RAM is not the issue (~118 MB
free at the time); this is independent of the OOM work in
[05](05-memory-tuning.md).

## 2. Background: how Android accounts per-process GPU memory

Modern Android reports GPU memory per process through an **eBPF** pipeline:

- the kernel emits a **`gpu_mem/gpu_mem_total` tracepoint** on GPU allocations;
- an eBPF program (`gpuMem`, shipped in the system image) attaches to it and
  maintains a **hash map** keyed by `(gpu_id, pid)` with the byte total as the value
  (key size 8, value size 8);
- `bpfloader` creates that map at boot and **pins** it at
  `/sys/fs/bpf/map_gpuMem_gpu_mem_total_map`;
- **`libmeminfo`** (`android::meminfo::ReadPerProcessGpuMem`) opens the pinned map
  and iterates it;
- the framework calls that through JNI (`libandroid_runtime`,
  `KernelAllocationStats`/GPU allocations) from a **periodic stats collector**.

So once per collection cycle, `system_server` opens and reads that eBPF map.

## 3. Why this build has no such map

On `blossom` (MT6765) this ROM runs a **MediaTek 4.19 kernel** that does **not**
implement the upstream `gpu_mem/gpu_mem_total` tracepoint. Its symbols show MTK's own
accounting instead:

```
# /proc/kallsyms
... T mtk_get_gpu_memory_usage
... T mtk_dump_gpu_memory_usage
```

Because the tracepoint the `gpuMem` eBPF program attaches to does not exist, the
program never loads and the map is never created. Confirmed on-device:

```
$ ls /sys/fs/bpf/map_gpuMem_gpu_mem_total_map
No such file or directory          # and no gpu_* map anywhere in /sys/fs/bpf
```

## 4. The exact failure, disassembled

`ReadPerProcessGpuMem` calls an inner bpf-map helper with a pointer to a small struct
whose first field is the map fd. The helper's **very first action** is to reject a
negative fd by aborting:

```asm
; libmeminfo.so  (inside the ReadPerProcessGpuMem bpf helper)
  ldr   w8, [x0]                 ; w8 = map fd  (negative: map is absent)
  tbnz  w8, #31, <abort>         ; if fd < 0  -> bl abort()      ← the bug
  ...                            ; (otherwise: bpf OBJ_GET_INFO_BY_FD, size checks, iterate)
```

`<abort>` is a bare `abort()`. On this bionic, `abort()` does **not** go through the
usual `tgkill` path; it self-sends the signal with `rt_tgsigqueueinfo`:

```asm
; libc.so  abort()
  mov   w2, #6                   ; SIGABRT
  mov   w8, #0xf0                ; __NR_rt_tgsigqueueinfo (240)
  svc   #0                       ; rt_tgsigqueueinfo(getpid(), gettid(), SIGABRT, &si)
```

This single detail explains every confusing property of the crash:

| Observation | Explanation |
|---|---|
| `si_code = SI_QUEUE` | the kernel stamps `SI_QUEUE` for a queued signal sent via `rt_tgsigqueueinfo` |
| sender `si_pid` == `system_server`'s own pid | it is a **self**-send, not an external killer |
| no `"Abort message"` | it is a **bare `abort()`** — unlike `CHECK`/`LOG_ALWAYS_FATAL`, it sets no message |
| the "crashing" thread is always an idle binder thread | `abort()` targets the **process**; the kernel delivers to whatever thread is parked in a syscall |

The captured backtrace (frame-pointer unwind against the crash-time `maps`):

```
#0  libc.so           abort()                      → rt_tgsigqueueinfo(SIGABRT)
#1  libmeminfo.so     <bpf-map helper>             fd<0 → tbnz w8,#31 → bl abort
#2  libmeminfo.so     android::meminfo::ReadPerProcessGpuMem(...)
#3  libandroid_runtime.so   JNI (KernelAllocationStats / GPU allocations)
#4  boot-framework.oat      a scheduled Java stats collector
```

Note the irony: the **caller already handles `fd<0` gracefully** — right after the
helper returns it does `ldr w8,[fd]; tbnz w8,#31, <graceful cleanup>`. The inner
helper simply aborts before it can get there.

## 5. Why it was invisible for so long

This build's crash tooling is broken: `crash_dump64` fails
(`failed to waitpid on child`) and `tombstoned` logs
`kDebuggerdAnyIntercept`, so **no tombstone is ever written and no abort-reason line
is printed** — the normal ways to read an abort are gone. Combined with the bare
`abort()` (no message) and the `SI_QUEUE`/self-send masquerade, the crash looked
like an unknowable external kill. It was caught by catching the live signal with a
custom `PTRACE_SEIZE` tool — see [08](08-hourly-reboot-investigation.md).

## 6. The fix

**Idea:** do not disable GPU accounting; just stop the inner helper from aborting on
a missing map, so the caller's own `fd<0` handling runs and the pull returns an empty
result — exactly how upstream AOSP degrades where GPU-mem eBPF is unavailable.

The helper already contains a clean early-return path (the branch it takes when the
kernel is too old for the newer bpf-info call). The patch points the `fd<0` test at
**that existing graceful path** instead of at `abort()`:

```
# libmeminfo.so @ file offset 0x17f64 — change ONLY the branch target
-  tbnz w8, #31, 0x18118   ; -> abort()            bytes:  a8 0d f8 37
+  tbnz w8, #31, 0x180f4   ; -> graceful return    bytes:  88 0c f8 37
```

Two bytes change, inside one instruction. The ELF is otherwise byte-identical and
the same size; no symbols, hashes or layout are touched.

### Delivery — the `gpumem-abort-fix` Magisk module

`magisk-module/gpumem-abort-fix/` is a **systemless** module. Its `customize.sh`, at
install time, copies the device's own `/system/lib64/libmeminfo.so` into the module,
applies the 2-byte patch, and labels it `u:object_r:system_lib_file:s0`. Magisk then
magic-mounts it over `/system/lib64/` on every boot. **No binary is shipped in git**
(the patch is derived on-device), the real partition is never written (dm-verity/AVB
stay intact), and removing the module reverts everything.

```bash
# build the flashable zip from the repo and install it in the Magisk app:
cd magisk-module/gpumem-abort-fix && zip -qr ../gpumem-abort-fix.zip .
#   Magisk app → Modules → Install from storage → pick the zip → reboot
```

A guard in `customize.sh` aborts the install unless `ro.product.device == angelican`
**and** the bytes at the patch offset match exactly — so it can never misapply to a
different build (see §8).

### Verify

```bash
adb shell su -c 'sha256sum /system/lib64/libmeminfo.so'      # == the patched hash
adb shell su -c 'od -An -tx1 -j 0x17f64 -N4 /system/lib64/libmeminfo.so'
#   -> 88 0c f8 37   (patched;  original was a8 0d f8 37)
```

## 7. Result (verified against the symptom)

After installing the module and rebooting, the live `/system/lib64/libmeminfo.so` is
the patched one, and `system_server` runs **continuously for hours** across the
window where it previously aborted every ~60–65 min, with the `dropbox`
`SYSTEM_RESTART` count unchanged. The hourly soft-reboot is gone.

## 8. Scope & caveats

- **64-bit only.** The patch targets `/system/lib64/libmeminfo.so` (`system_server`
  and all 64-bit system processes). A 32-bit `/system/lib/libmeminfo.so` exists; it
  was left untouched because the observed crash is `system_server` (64-bit).
- **Build-specific offset.** `0x17f64` and the branch encoding are specific to this
  exact `libmeminfo.so`. On a **fresh install** the module's byte-guard refuses to
  patch anything whose bytes differ, so it can never corrupt a different build (the
  install just says so). But an **already-installed** module carries a patched
  `libmeminfo.so` built for the current system image — after a ROM update that
  replaces the real library, Magisk would overlay the stale copy, so you must
  **remove and reinstall** the module (its `customize.sh` re-patches the new lib, or
  the guard refuses if the layout moved — then re-derive per §9). See
  [06](06-maintenance.md).
- **The real bug is upstream of us:** this ROM's `libmeminfo` should degrade when the
  GPU-mem map is absent (as the caller is prepared for). The clean long-term fix is a
  build that either ships that graceful path or wires up the `gpu_mem` tracepoint;
  worth reporting to the maintainer.

## 9. Re-deriving the patch on a different build

1. Catch a live abort with `tools/sigcatch.c` (PTRACE_SEIZE) to confirm it is still
   `libmeminfo`/`ReadPerProcessGpuMem`; capture `maps` + stack and unwind.
2. In the new `libmeminfo.so`, find `android::meminfo::ReadPerProcessGpuMem`, follow
   it into the bpf-map helper, and locate the `ldr w8,[x0]; tbnz w8,#31,<abort>` at
   the helper's entry.
3. Identify the helper's existing graceful early-return target (the "old kernel /
   bpf-info unavailable" branch).
4. Re-point the `tbnz` from `<abort>` to that graceful target (change only the branch
   offset), update the offset/bytes/guard in `customize.sh`, rebuild the module.

---

**← [08 — Hourly reboot: the investigation](08-hourly-reboot-investigation.md)**  ·  _(end)_  ·  [↑ README](../README.md)
