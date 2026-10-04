#!/usr/bin/env bash
#
# adb-connect.sh — reliable ADB connection to the device over Wi-Fi + root.
#
# The USB link on this unit drops constantly; wireless debugging (port 5555,
# pinned in LineageOS Developer options) is far more stable. This helper
# (re)connects and restores `adb root` (LineageOS "rooted debugging" makes
# `adb root` work; it reverts to shell user on every reboot).
#
# Usage:  ./adb-connect.sh [HOST:PORT]        (default 192.168.1.100:5555)
#         eval "$(./adb-connect.sh --export)"  # sets $DEV for other scripts
set -euo pipefail

DEV="${1:-192.168.1.100:5555}"
[ "$DEV" = "--export" ] && DEV="192.168.1.100:5555"

adb connect "$DEV" >/dev/null 2>&1 || true

# wait until the device is actually responsive
for _ in $(seq 1 15); do
  [ "$(adb -s "$DEV" get-state 2>/dev/null || true)" = "device" ] && break
  adb connect "$DEV" >/dev/null 2>&1 || true
  sleep 2
done

# restore root (no-op if already root)
if ! adb -s "$DEV" shell id 2>/dev/null | grep -q 'uid=0'; then
  adb -s "$DEV" root >/dev/null 2>&1 || true
  sleep 3
  adb connect "$DEV" >/dev/null 2>&1 || true
fi

STATE="$(adb -s "$DEV" get-state 2>/dev/null || echo offline)"
ROOT="$(adb -s "$DEV" shell id 2>/dev/null | grep -oE 'uid=[0-9]+\([a-z]+\)' || echo 'unknown')"

if [ "${1:-}" = "--export" ]; then
  echo "export DEV='$DEV'"
else
  echo "device: $DEV  state: $STATE  root: $ROOT"
fi
