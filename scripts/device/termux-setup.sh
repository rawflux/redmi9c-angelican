#!/data/data/com.termux/files/usr/bin/bash
#
# termux-setup.sh — minimal on-device dev environment in Termux.
#
# Run this INSIDE the Termux app (not via adb shell), after Termux has finished
# its first-run bootstrap:
#
#   pkg install -y curl && \
#   curl -sL <raw-url>/scripts/device/termux-setup.sh | bash
#
# Keep it lean — this is a 3 GB phone. Installs a practical toolchain, not the
# kitchen sink.
set -e

echo ">> updating package lists"
pkg update -y && pkg upgrade -y

echo ">> core dev tools"
pkg install -y git python nodejs-lts openssh rsync jq ripgrep fd nano tmux

echo ">> termux-api (battery, clipboard, notifications from scripts)"
pkg install -y termux-api

echo ">> storage access (~/storage -> shared storage)"
termux-setup-storage || true

echo ">> git identity (edit to taste)"
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main

echo ">> done. Toolchain: git, python, node LTS, ssh, rsync, jq, rg, fd, tmux."
echo "   sshd:  'sshd' then connect to port 8022 (passwordless -> add your key to ~/.ssh/authorized_keys)"
