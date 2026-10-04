# 08 — The hourly soft-reboot: the investigation (SOLVED)

> **TL;DR** — A second, non-memory soft-reboot hit `system_server` roughly once an
> hour (`SIGABRT`, `SI_QUEUE`, RAM to spare). It was hard because this build's crash
> tooling is broken (no tombstone, no abort message) and the signal masqueraded as
> an external kill. It was cracked by catching the live signal with a custom
> `PTRACE_SEIZE` tool. **Root cause and fix are documented in
> [09](09-gpu-mem-reboot.md); this page is the detective story** — the dead ends, the
> method that worked, and the lessons.

## Symptom

- `system_server` dies with **SIGABRT (signal 6), `SI_QUEUE`**, always in a **binder
  thread**; Zygote respawns the framework (soft reboot — `/proc/uptime` keeps
  climbing). ~118 MB free, so not OOM.
- Cadence ~hourly. It first looked phase-locked to `:20`, but it is actually tied to
  a **periodic framework stats pull**, not the wall clock.

## Dead ends (and why each was wrong)

Keeping these honest — the wrong turns cost the most time.

| Hypothesis | Why it was discarded |
|---|---|
| Memory exhaustion | ~118 MB free at crash; the memory fix ([05](05-memory-tuning.md)) didn't change it |
| Kernel panic | `/sys/fs/pstore/` empty; `/proc/uptime` keeps climbing (soft-reboot only) |
| Wi-Fi secondary-STA loop | Disabling Adaptive Connectivity silenced the noisy 3 s loop but the crash continued — loud noise, not the cause. (A premature "fixed" claim here was corrected.) |
| GMS FCM retry | A `c2dm` event often landed tens of ms before the abort, which looked causal; the real trigger is a periodic stats pull that merely runs near the FCM activity |
| External watchdog / MTK AEE | No `hang_detect`/`monitor_hang`/`aed`/`mrdump` process-killer is compiled into this kernel; the `SI_QUEUE` is a **self**-send, not external |

## Why ordinary tooling failed

- **debuggerd/`crash_dump64` is broken on this build** (`failed to waitpid on
  child` → `tombstoned: kDebuggerdAnyIntercept`): **no tombstone, no abort-reason
  line** is ever produced.
- **No `"Abort message"`** either — the crash is a bare `abort()` (sets no message),
  and that line would have been printed by the same broken `crash_dump`.
- **`SI_QUEUE` was a red herring**: it is produced because this bionic implements
  `abort()` via `rt_tgsigqueueinfo`, and the signal lands on whatever binder thread
  is parked in the driver — so the "crashing" thread always looked idle and innocent.
- **On-device logging doesn't survive** the soft-reboot; host-side `adb logcat -b
  all` streaming caught the pre-crash context but not the fatal frame itself.

## The method that worked: a PTRACE_SEIZE catcher

`strace` is unusable here — tracing 200+ threads perturbs timing and, in practice,
**froze `system_server` for 32 minutes** on one attempt. `PTRACE_SEIZE` is the right
tool: it **does not stop** the target, only traps on signal delivery.

[`tools/sigcatch.c`](../tools/sigcatch.c) (cross-compiled static aarch64,
`aarch64-linux-gnu-gcc -static`) seizes every thread of `system_server`, reinjects
the frequent ART null-`SIGSEGV` noise, and on `SIGABRT`:

- reads the exact `siginfo` via `PTRACE_GETSIGINFO` → `si_code`, **`si_pid`**,
  `si_uid`;
- dumps the faulting thread's registers, `/proc/<pid>/maps` and a 32 KiB stack slice;
- cleanly detaches (delivering the signal) so the process dies normally — no freeze.

What it caught:

```
CAUGHT SIGABRT  si_code=-1 (SI_QUEUE)  si_pid == target  si_uid=1000
regs:  x8=0xf0 (__NR_rt_tgsigqueueinfo)  x2=0x6 (SIGABRT)  x1 == own tid
```

`si_pid == target` ⇒ **self-send** (not kernel, which would be `si_pid=0`; not a
third party, which bionic's handler would have logged as `from pid N`). A
frame-pointer unwind against the captured `maps` pinned the call chain to
`libmeminfo::ReadPerProcessGpuMem` → `abort()`. The full mechanism and the fix are in
**[09 — The GPU-memory abort](09-gpu-mem-reboot.md)**.

## Lessons

- A fixed-cadence `SIGABRT` with no tombstone and no abort message is **not**
  unknowable. `SI_QUEUE` + an absent sender-pid narrows the origin to kernel-vs-self;
  `PTRACE_GETSIGINFO` settles it; a frame-pointer unwind against a captured `maps`
  pins the faulting function to the instruction.
- `PTRACE_SEIZE` > `strace` for catching a rare async signal on a live, critical,
  many-threaded process: no syscall-stop storm, no freeze, no timing distortion.
- Verify a fix **against the symptom** before claiming it — the Adaptive-Connectivity
  misfire on this very bug is the cautionary tale. The real fix in
  [09](09-gpu-mem-reboot.md) was only called a fix after `system_server` survived the
  crash window for hours with the `SYSTEM_RESTART` count unchanged.

---

**← [07 — Dev environment](07-dev-environment.md)**  ·  **[09 — GPU-memory abort: root cause & fix →](09-gpu-mem-reboot.md)**  ·  [↑ README](../README.md)
