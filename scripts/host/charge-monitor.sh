#!/usr/bin/env bash
# charge-monitor.sh — live charging monitor over Wi-Fi ADB (current / level / temp).
#
# Built for a flaky charging port: watch the current — the line turns RED and the
# terminal beeps the moment charging drops to zero/negative, so you can reseat the
# cable and watch it go GREEN again. Ctrl-C to stop (prints a min/max summary).
#
# Usage:  scripts/host/charge-monitor.sh [ip:port] [interval_sec]
#   e.g.  scripts/host/charge-monitor.sh 192.168.3.21:5555 1
#
# Note: current_now sign on this device (MT6765/bq2560x): +charging / -discharging.
set -u
PHONE="${1:-192.168.3.21:5555}"
INT="${2:-1}"
ADB="adb -s $PHONE"
B=/sys/class/power_supply/battery

R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; DIM=$'\e[2m'; N=$'\e[0m'; BEL=$'\a'

conn(){ adb connect "$PHONE" >/dev/null 2>&1; }

min=1000000; max=-1000000; drops=0; start=$(date +%s)
summary(){ el=$(( $(date +%s)-start ))
  printf "\n%s— стоп. за %dм%02dс: ток min=%+d мА, max=%+d мА, срывов заряда: %d%s\n" \
    "$DIM" $((el/60)) $((el%60)) "$min" "$max" "$drops" "$N"; exit 0; }
trap summary INT TERM

conn
printf "%sзарядка %s — Ctrl-C для выхода%s\n" "$DIM" "$PHONE" "$N"
printf "%-8s %4s %-12s %8s %5s  %s\n" "время" "%" "статус" "ток,мА" "t°C" "оценка"

prev_ok=1
while :; do
  raw=$($ADB shell "echo \"\$(cat $B/capacity)|\$(cat $B/status)|\$(cat $B/current_now)|\$(cat $B/temp)\"" 2>/dev/null | tr -d '\r')
  now=$(date +%H:%M:%S)
  if [ -z "$raw" ] || [ "${raw#*|}" = "$raw" ]; then
    printf "%s %sADB обрыв — переподключаюсь...%s\n" "$now" "$R" "$N"; conn; sleep "$INT"; continue
  fi
  IFS='|' read -r cap st cur tmp <<<"$raw"
  mA=$(( ${cur:-0} / 1000 )); tC=$(( ${tmp:-0} / 10 ))
  [ "$mA" -lt "$min" ] && min=$mA; [ "$mA" -gt "$max" ] && max=$mA
  if   [ "$mA" -ge 300 ]; then col=$G; tag="✓ заряд"; ok=1
  elif [ "$mA" -gt 0 ];   then col=$Y; tag="~ слабо/трикл"; ok=1
  else                         col=$R; tag="✗ НЕ ЗАРЯЖАЕТ — поправь кабель"; ok=0; fi
  bell=""; if [ "$ok" = 0 ] && [ "$prev_ok" = 1 ]; then bell="$BEL"; drops=$((drops+1)); fi
  prev_ok=$ok
  printf "%s %s%3s%%%s %-12s %s%+7d%s %4d°C  %s%s%s%b\n" \
    "$now" "$C" "${cap:-?}" "$N" "${st:-?}" "$col" "$mA" "$N" "$tC" "$col" "$tag" "$N" "$bell"
  sleep "$INT"
done
