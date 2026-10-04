# 02 — Unlock the bootloader

> **TL;DR** — Bind a phone number to your Mi account, link the device in
> *Mi Unlock status*, wait out a ~168 h server timer (don't sign out or you reset
> it), then unlock. **Unlocking wipes the device.**

Unlocking is required before flashing anything. On Xiaomi it is gated by a
server-side wait timer tied to your Mi account.

## Prerequisites (the ones that actually bit us)

1. **A Mi account with a phone number bound to it.** Without a bound number the
   unlock server refuses with `code 20041: your MI ID is not associated with a
   phone number`. Bind the number on `account.xiaomi.com` (the verification SMS to
   Xiaomi's short code can fail on RU carriers — retry, or use the website flow).
2. **OEM unlocking enabled**: Settings → Developer options → *OEM unlocking*.
3. **Device linked in Mi Unlock**: Settings → Developer options → *Mi Unlock
   status* → **Bind account and device** (needs a SIM, mobile data **on**,
   Wi-Fi **off**).

## The 168-hour timer

After binding, Xiaomi enforces a **~168 h (7-day)** wait. During the wait, **do
not sign out of the Mi account or re-bind** — either resets the timer to zero (we
lost the first week that way).

### Check remaining time safely (no wipe)

`scripts/host/check-unlock.py` asks the Xiaomi server how long is left **without
performing the unlock** — it deliberately omits the `fastboot oem unlock` step, so
nothing is wiped. It uses the `migate`/`miunlock` Python packages.

```bash
adb reboot bootloader           # device must be in fastboot
env -u http_proxy -u https_proxy -u ftp_proxy -u HTTP_PROXY -u HTTPS_PROXY \
    -u ALL_PROXY -u all_proxy python3 scripts/host/check-unlock.py
# -> "Please unlock NNN hours later"  (still waiting)
# -> "Время ожидания ИСТЕКЛО"          (ready — this script still won't unlock)
```

All requests must go **direct, with every proxy variable unset** (the account API
misbehaves through a proxy). The login session caches in
`~/.migatesession/unlockApi/session.json` and is reused; choose "log out" at the
prompt to force re-login.

## Perform the unlock (point of no return)

When the timer reads expired:

```bash
adb reboot bootloader
env -u http_proxy -u https_proxy -u ALL_PROXY python3 -m miunlock
# logs in, prints the server notice, then pauses:
#   "Press 'Enter' to continue — unlock(encryptData)"   <-- THIS wipes the device
```

Verify:

```bash
fastboot getvar unlocked        # -> unlocked: yes
```

After unlock the phone wipes and may land in stock recovery — normal; the next
step reflashes everything anyway. To reach fastboot from there: power off fully,
then hold **Volume-Down + Power**.

> Tooling: `offici5l/MiUnlockTool` → PyPI `miunlock` (pulls `migate`). Works
> headless on Linux; login is via a browser URL it prints.

---

**← [01 — Overview](01-overview.md)**  ·  **[03 — Flash LineageOS →](03-flash-lineageos.md)**  ·  [↑ README](../README.md)
