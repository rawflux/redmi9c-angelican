#!/usr/bin/env bash
#
# stability-monitor.sh — measure memory-related stability of the device.
#
# Polls once a minute for a given number of minutes and reports:
#   - new soft-reboots (growth of the dropbox SYSTEM_RESTART count — ground truth,
#     not inferred from pid changes which give false positives on adb drops)
#   - the lowest free-RAM seen (the floor that OOM aborts used to hit near 0)
#   - the peak zram usage (confirms swap is actually absorbing pressure)
#
# Usage:  ./stability-monitor.sh [MINUTES] [HOST:PORT]   (defaults 120, wifi)
set -uo pipefail

MIN="${1:-120}"
DEV="${2:-192.168.1.100:5555}"
A="adb -s $DEV"

adb connect "$DEV" >/dev/null 2>&1 || true
base=$($A shell 'ls /data/system/dropbox/SYSTEM_RESTART* 2>/dev/null | wc -l' | tr -d '\r')
echo "monitoring ${MIN} min on $DEV — baseline reboots=$base"

minfree=999999; swapmax=0
for i in $(seq 1 "$MIN"); do
  adb connect "$DEV" >/dev/null 2>&1 || true
  fr=$($A shell 'free -m 2>/dev/null | awk "/Mem/{print \$4}"' | tr -d '\r')
  sw=$($A shell 'free -m 2>/dev/null | awk "/Swap/{print \$3}"' | tr -d '\r')
  [ -n "$fr" ] && [ "$fr" -lt "$minfree" ] 2>/dev/null && minfree=$fr
  [ -n "$sw" ] && [ "$sw" -gt "$swapmax"  ] 2>/dev/null && swapmax=$sw
  sleep 60
done

now=$($A shell 'ls /data/system/dropbox/SYSTEM_RESTART* 2>/dev/null | wc -l' | tr -d '\r')
echo "== result over ${MIN} min =="
echo "  new soft-reboots : $((now - base))   (dropbox $base -> $now)"
echo "  min free RAM     : ${minfree} MB"
echo "  peak zram used   : ${swapmax} MB"
$A shell 'uptime | grep -oE "up [^,]+"'
