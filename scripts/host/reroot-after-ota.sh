#!/usr/bin/env bash
#
# reroot-after-ota.sh — re-root after a LineageOS update wipes the boot patch.
#
# This device is A-only (single boot partition, no A/B slots), so any system
# update overwrites the Magisk-patched boot image and root is lost. The memtune
# tuning and Magisk DenyList live in /data and survive — only boot needs redoing.
#
# This script automates the mechanical half. The actual patching still happens
# inside the Magisk app (there is no headless Magisk patcher):
#
#   1. Extract boot.img from the new LineageOS zip you flashed:
#        unzip -o <lineage-xx.zip> boot.img -d ./new-boot/
#   2. Run this script with that boot.img — it pushes it to the phone.
#   3. On the phone: Magisk app -> Install -> Select and Patch a File ->
#      pick /sdcard/Download/boot.img -> Let's Go.
#   4. Re-run this script with --pull-flash — it pulls the patched image back
#      and flashes it via fastboot.
#
# Usage:
#   ./reroot-after-ota.sh ./new-boot/boot.img      # step 2: push
#   ./reroot-after-ota.sh --pull-flash              # step 4: pull + flash
set -euo pipefail

DEV="${PHONE:-192.168.1.100:5555}"
A="adb -s $DEV"

if [ "${1:-}" = "--pull-flash" ]; then
  adb connect "$DEV" >/dev/null 2>&1 || true
  patched=$($A shell 'ls -t /sdcard/Download/magisk_patched*.img 2>/dev/null | head -1' | tr -d '\r')
  [ -z "$patched" ] && { echo "ERROR: no magisk_patched*.img found — patch it in the Magisk app first"; exit 1; }
  echo "pulling $patched"
  $A pull "$patched" ./magisk_patched_boot.img
  # sanity: must differ from a stock boot and be a valid Android boot image
  head -c4 ./magisk_patched_boot.img | grep -q 'ANDROID' || { echo "ERROR: not an Android boot image"; exit 1; }
  echo "rebooting to fastboot and flashing boot..."
  $A reboot bootloader; sleep 12
  fastboot flash boot ./magisk_patched_boot.img
  fastboot reboot
  echo "done — verify root after boot with: adb-connect.sh && adb shell su -c id"
  exit 0
fi

BOOT="${1:?usage: reroot-after-ota.sh <boot.img> | --pull-flash}"
[ -f "$BOOT" ] || { echo "ERROR: $BOOT not found"; exit 1; }
adb connect "$DEV" >/dev/null 2>&1 || true
echo "pushing $BOOT to /sdcard/Download/boot.img"
$A push "$BOOT" /sdcard/Download/boot.img
echo "now: Magisk app -> Install -> Select and Patch a File -> Download/boot.img -> Let's Go"
echo "then: $0 --pull-flash"
