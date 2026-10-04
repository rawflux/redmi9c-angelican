#!/usr/bin/env bash
#
# restore.sh — reinstall MIUI system packages removed by debloat.sh.
#
# Reverses `pm uninstall --user 0` via `cmd package install-existing`. Third-party
# apps (fully uninstalled) are NOT restored here — reinstall them from a store.
#
# Usage:  ./restore.sh [HOST:PORT|SERIAL]        (default: first adb device)
set -uo pipefail

DEV="${1:-$(adb devices | awk 'NR==2{print $1}')}"
A="adb -s $DEV"

SYSTEM_BLOAT="
com.miui.msa.global com.miui.analytics com.xiaomi.discover com.xiaomi.mipicks
android.autoinstalls.config.Xiaomi.model com.facebook.appmanager
com.facebook.services com.facebook.system com.mi.android.globalminusscreen
com.miui.hybrid com.miui.hybrid.accessory com.mipay.wallet.in com.xiaomi.payment
com.xiaomi.glgm com.google.android.projection.gearhead com.google.ar.lens
com.android.egg com.mi.globalbrowser com.miui.player com.miui.videoplayer
com.miui.fm com.miui.fmservice com.miui.weather2 com.miui.notes com.xiaomi.midrop
com.miui.cleanmaster com.miui.yellowpage com.miui.touchassistant"

echo "device: $DEV — restoring MIUI system packages"
for p in $SYSTEM_BLOAT; do
  printf '  %-45s ' "$p"; $A shell cmd package install-existing "$p" 2>&1 | tr -d '\r' | tail -1
done
