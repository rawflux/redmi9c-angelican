#!/system/bin/sh
#
# memtune.sh — durable memory tuning for Redmi 9C NFC (angelican, 3 GB RAM)
# on LineageOS 23.2 / Android 16. STANDALONE variant for /data/adb/service.d/.
# (The packaged Magisk module in magisk-module/redmi9c-tweaks/ is preferred —
#  it splits early vs late work correctly across post-fs-data and service.)
#
# This single-file version runs late (service.d). It sets lmkd PSI params and
# asks lmkd to reload via `lmkd.reinit` (a gentle reload — NOT stop/start, which
# would briefly leave the system with no OOM killer and could itself cause an
# abort). It does NOT rebuild zram at boot (a swapoff window removes swap exactly
# when it is most needed); stock zram is kept. See docs/05-memory-tuning.md.
#
# Rationale and measurements: docs/05-memory-tuning.md. Reversible: delete + reboot.

LOG=/data/local/tmp/memtune.log

# lmkd PSI thresholds — react to pressure ~2x sooner (stock 135/540).
resetprop -n ro.lmk.psi_partial_stall_ms  70
resetprop -n ro.lmk.psi_complete_stall_ms 200
resetprop -n ro.lmk.thrashing_limit       40
resetprop -n ro.lmk.thrashing_limit_decay 20
resetprop -n ro.lmk.swap_free_low_percentage 20
resetprop -n ro.lmk.kill_timeout_ms       50
setprop   lmkd.reinit 1                       # gentle reload, no kill window

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 25
echo "[$(date)] memtune start" > "$LOG"

# Kernel reserves — head-start for reclaim before a fast spike hits zero.
echo 24576 > /proc/sys/vm/min_free_kbytes
echo 200   > /proc/sys/vm/watermark_scale_factor
echo 100   > /proc/sys/vm/swappiness
echo 0     > /proc/sys/vm/page-cluster

# Fewer cached app processes held in RAM.
device_config put activity_manager max_cached_processes 12

echo "[$(date)] done: $(free -m | awk '/Mem/{print $4" MB free"}'), lmkd psi=$(getprop ro.lmk.psi_partial_stall_ms)" >> "$LOG"
