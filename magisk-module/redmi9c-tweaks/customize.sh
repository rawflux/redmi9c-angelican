#!/system/bin/sh
# guard: this module tunes a specific device — refuse elsewhere
if [ "$(getprop ro.product.device)" != "angelican" ]; then
  ui_print "! This module is built for Redmi 9C NFC (angelican) only."
  ui_print "! Current device: $(getprop ro.product.device) — aborting."
  abort
fi
ui_print "- Redmi 9C tweaks: memtune + Wi-Fi ADB :5555"
set_perm_recursive "$MODPATH" 0 0 0755 0644
