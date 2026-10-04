#!/system/bin/sh
# service.sh: runs late_start — after /data is decrypted and the framework is up.
# Applies only SAFE runtime writes. The lmkd PSI params are set in post-fs-data
# (before lmkd starts), so lmkd already runs tuned — we deliberately do NOT
# restart lmkd here: that would open a window with no low-memory killer during
# the high-pressure post-boot period and could itself trigger an OOM abort.
# For the same reason we do NOT tear down/rebuild zram at boot (the swapoff window
# removes swap exactly when it is most needed); stock zram is left as-is.
MODDIR=${0%/*}
LOG=/data/local/tmp/redmi9c-tweaks.log
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 25
echo "[$(date)] redmi9c-tweaks service start" > "$LOG"

# --- kernel reserves: head-start for reclaim before a fast spike hits zero ---
# (plain sysctl writes — no protection window is ever removed)
echo 24576 > /proc/sys/vm/min_free_kbytes
echo 200   > /proc/sys/vm/watermark_scale_factor
echo 100   > /proc/sys/vm/swappiness
echo 0     > /proc/sys/vm/page-cluster

# --- fewer cached processes held in RAM ---
device_config put activity_manager max_cached_processes 12

# Wi-Fi: cut scan churn on this single-STA (STA+AP/STA+P2P only) MT6765 — efficiency
# and far quieter logs. (Not related to the reboots: OOM is docs/05, the hourly one
# is docs/09.)
#  - Adaptive Connectivity off: it endlessly requests a secondary STA the chip can't
#    create (HalDevMgr "bestIfaceCreationProposal is null, requestIface=STA").
#  - Background location scanning off + scan throttle on: HIGH_ACCURACY all-band
#    scans (location/NLP) hammered the radio and flooded wificond (incl. the benign
#    "MAX_NUM_AKM_SUITES" kernel-gap error). Connectivity and active location still work.
settings put secure adaptive_connectivity_enabled 0
settings put global  wifi_scan_always_available 0
settings put global  wifi_scan_throttle_enabled 1

# --- Wi-Fi ADB on :5555 (persist.adb.tcp.port in post-fs-data also covers this;
#     adbd restart is network-only, no memory impact) ---
setprop service.adb.tcp.port 5555
stop adbd; start adbd

echo "[$(date)] done: $(free -m | awk '/Mem/{print $4" MB free"}'), lmkd psi=$(getprop ro.lmk.psi_partial_stall_ms), adb tcp:$(getprop service.adb.tcp.port)" >> "$LOG"
