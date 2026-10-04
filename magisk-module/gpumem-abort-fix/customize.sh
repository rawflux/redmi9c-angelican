#!/sbin/sh
# gpumem-abort-fix — install-time patcher.
#
# libmeminfo::ReadPerProcessGpuMem opens the eBPF map
# /sys/fs/bpf/map_gpuMem_gpu_mem_total_map. On this build that map does not exist
# (the MTK kernel has no gpu_mem/gpu_mem_total tracepoint), the fd is negative, and
# an inner helper does `tbnz w8,#31,<abort>` — it abort()s on a negative fd. This
# flips only the branch TARGET to the helper's own graceful-return path, so the
# caller's existing fd<0 handling runs and the pull returns empty (as upstream AOSP
# degrades). Full write-up: docs/09-gpu-mem-reboot.md.
#
# We build the overlay here from the device's own libmeminfo.so, so no binary is
# shipped in the zip. Guarded to this exact device + exact bytes.
SKIPUNZIP=1

ui_print "- GPU-mem abort fix for libmeminfo"

DEV=$(getprop ro.product.device)
[ "$DEV" = "angelican" ] || abort "! only for 'angelican' (this is '$DEV')"

LIB=/system/lib64/libmeminfo.so
OFF=98148                  # 0x17f64 — the fd<0 -> abort branch site (this build)
ORIG=a80df837              # tbnz w8,#31, -> abort         (little-endian word)
NEWB='\x88\x0c\xf8\x37'    # tbnz w8,#31, -> graceful return

[ -f "$LIB" ] || abort "! $LIB not found"
cur=$(dd if="$LIB" bs=1 skip=$OFF count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$cur" = "$ORIG" ] || abort "! bytes at $OFF are '$cur', expected '$ORIG' — build mismatch (re-derive per docs/09 §9)"
ui_print "- verified patch site ($cur)"

mkdir -p "$MODPATH/system/lib64"
cp -f "$LIB" "$MODPATH/system/lib64/libmeminfo.so"
printf "$NEWB" | dd of="$MODPATH/system/lib64/libmeminfo.so" bs=1 seek=$OFF count=4 conv=notrunc 2>/dev/null
new=$(dd if="$MODPATH/system/lib64/libmeminfo.so" bs=1 skip=$OFF count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$new" = "880cf837" ] || abort "! patch verification failed ($new)"

set_perm "$MODPATH/system/lib64/libmeminfo.so" 0 0 0644 u:object_r:system_lib_file:s0
ui_print "- libmeminfo patched ($new); reboot to apply"
ui_print "- verify after reboot: od -An -tx1 -j 0x17f64 -N4 /system/lib64/libmeminfo.so"
