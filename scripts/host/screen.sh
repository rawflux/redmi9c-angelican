#!/usr/bin/env bash
#
# screen.sh — mirror / control the phone screen over Wi-Fi ADB with scrcpy.
#
# Tuned for this low-RAM device and a wireless link: capped resolution and
# bitrate for a smooth stream, screen-off on the phone to save battery while
# mirroring. Requires scrcpy (>=2.0) on the host.
#
# Usage:  ./screen.sh            # mirror + control
#         ./screen.sh --record out.mp4
set -euo pipefail

DEV="${DEV:-192.168.1.100:5555}"
"$(dirname "$0")/adb-connect.sh" "$DEV" >/dev/null 2>&1 || true

ARGS=(
  --serial "$DEV"
  --max-size 1024          # cap long edge — lighter encode on Helio G35
  --video-bit-rate 4M      # plenty for 720p-class panel over Wi-Fi
  --max-fps 30
  --turn-screen-off        # blank the phone panel while mirroring (saves battery)
  --stay-awake
  --window-title "Redmi 9C (angelican)"
)

if [ "${1:-}" = "--record" ]; then
  shift
  exec scrcpy "${ARGS[@]}" --record "${1:?usage: --record FILE.mp4}"
fi
exec scrcpy "${ARGS[@]}"
