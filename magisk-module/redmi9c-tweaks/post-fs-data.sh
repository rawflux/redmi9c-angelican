#!/system/bin/sh
# post-fs-data: runs EARLY, before lmkd and adbd start — the right place to set
# properties they read once at startup.
MODDIR=${0%/*}

# --- lmkd PSI thresholds: react to memory pressure ~2x sooner (stock 135/540) ---
resetprop -n ro.lmk.psi_partial_stall_ms  70
resetprop -n ro.lmk.psi_complete_stall_ms 200
resetprop -n ro.lmk.thrashing_limit       40
resetprop -n ro.lmk.thrashing_limit_decay 20
resetprop -n ro.lmk.swap_free_low_percentage 20
resetprop -n ro.lmk.kill_timeout_ms       50
resetprop -n persist.device_config.activity_manager.max_cached_processes 12

# Ask lmkd to re-read its config (gentle reload — no kill window, unlike a
# stop/start of lmkd, which would briefly leave the system with no OOM killer).
setprop lmkd.reinit 1

# --- persistent Wi-Fi ADB on :5555 (read by init to start adbd over TCP) ---
resetprop -n persist.adb.tcp.port 5555
