#!/usr/bin/env bash
#
# debloat.sh — remove MIUI bloat / ads / telemetry from stock MIUI 12.x.
#
# Only relevant if you are (or roll back) on stock MIUI. On LineageOS this is
# unnecessary — that build ships clean. Kept for the MIUI fallback path.
#
# Third-party apps are fully uninstalled; system packages are removed for user 0
# only (`pm uninstall -k --user 0`) — reversible, and restored by a factory reset
# or by restore.sh. Nothing here touches the Mi-account / Mi-Unlock stack.
#
# Usage:  ./debloat.sh [HOST:PORT|SERIAL]        (default: first adb device)
#         DRY=1 ./debloat.sh                      (print actions, change nothing)
set -uo pipefail

DEV="${1:-$(adb devices | awk 'NR==2{print $1}')}"
A="adb -s $DEV"
run() { if [ "${DRY:-0}" = "1" ]; then echo "DRY: $*"; else "$@"; fi; }

# Third-party — fully removed.
THIRD_PARTY="
com.zhiliaoapp.musically com.facebook.katana com.ebay.mobile com.ebay.carrier
com.mobile.legends com.opera.browser com.opera.preinstall cn.wps.moffice_eng
cn.wps.xiaomi.abroad.lite com.micredit.in com.drivee.taxi.rides ru.auto.ara
ru.vkusvill com.google.android.play.games"

# System ads / telemetry / auto-installers — removed for user 0 (reversible).
SYSTEM_BLOAT="
com.miui.msa.global com.miui.analytics com.xiaomi.discover com.xiaomi.mipicks
android.autoinstalls.config.Xiaomi.model com.facebook.appmanager
com.facebook.services com.facebook.system com.mi.android.globalminusscreen
com.miui.hybrid com.miui.hybrid.accessory com.mipay.wallet.in com.xiaomi.payment
com.xiaomi.glgm com.google.android.projection.gearhead com.google.ar.lens
com.android.egg com.mi.globalbrowser com.miui.player com.miui.videoplayer
com.miui.fm com.miui.fmservice com.miui.weather2 com.miui.notes com.xiaomi.midrop
com.miui.cleanmaster com.miui.yellowpage com.miui.touchassistant"

echo "device: $DEV   DRY=${DRY:-0}"
echo "== third-party (full uninstall) =="
for p in $THIRD_PARTY; do printf '  %-45s ' "$p"; run $A shell pm uninstall "$p" 2>&1 | tr -d '\r' | tail -1; done
echo "== system bloat (uninstall --user 0, reversible) =="
for p in $SYSTEM_BLOAT; do printf '  %-45s ' "$p"; run $A shell pm uninstall -k --user 0 "$p" 2>&1 | tr -d '\r' | tail -1; done
echo "done. To restore system packages: scripts/miui/restore.sh"
