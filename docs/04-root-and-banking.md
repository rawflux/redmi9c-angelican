# 04 — Root (Magisk) and banking-app integrity

> **TL;DR** — Patch `boot.img` in the Magisk app, flash it (A-only device).
> Banking apps pass with **stock Zygisk + DenyList** — no TrickyStore/Shamiko.

## Root with Magisk

A-only device, so rooting = patch `boot.img` and flash it. There is no headless
Magisk patcher — the patch happens inside the Magisk app.

```bash
# 1. install Magisk (verify signer: CN=John Wu, L=Taipei)
adb install Magisk-v30.7.apk

# 2. push the ROM's boot.img to the phone
adb push lineage-imgs/boot.img /sdcard/Download/boot.img

# 3. on the phone: Magisk -> Install -> Select and Patch a File ->
#    Download/boot.img -> Let's Go   (produces magisk_patched-*.img)

# 4. pull it back and flash
adb pull /sdcard/Download/magisk_patched-*.img magisk_patched_boot.img
adb reboot bootloader
fastboot flash boot magisk_patched_boot.img
fastboot reboot
```

Sanity before flashing: the patched image must be a valid Android boot image
(`head -c4` = `ANDROID`), identical size to stock, differing by ~1–2 MB.
`scripts/host/reroot-after-ota.sh` automates the push/pull/flash halves.

Verify after boot:

```bash
adb shell 'magisk -V'      # 30700 — daemon alive even before `su` is granted
adb shell su -c id         # uid=0  (first call shows an on-screen grant prompt)
```

### Root over ADB without the su prompt

LineageOS has *rooted debugging* (Developer options → Root access → ADB): `adb
root` restarts adbd as root — no prompt, convenient for scripting. It reverts to
shell user on every reboot; `scripts/host/adb-connect.sh` re-applies it.

## Banking-app integrity

Banks call the **Play Integrity API**; an unlocked bootloader + root fails the
`DEVICE` verdict and root detection, so apps may refuse to run.

**On this device, stock Magisk hiding was enough** — no TrickyStore, no Shamiko,
no keybox. Fewer moving parts = less to re-fix when banks update.

Setup:

1. Magisk → Settings → enable **Zygisk** (reboot once).
2. Magisk → Settings → **Configure DenyList** → tick the bank apps (and allow it
   to include their *isolated* processes).

Verified config (`magisk --sqlite "SELECT * FROM settings"` → `zygisk=1`,
`denylist=1`; `magisk --denylist ls`):

```
com.idamob.tinkoff.android     (T-Bank)
ru.tinkoff.sme                 (T-Business)
ru.sberbankmobile              (Sberbank)
ru.alfabank.mobile.android     (Alfa-Bank)
isolated
```

Ozon (`ru.ozon.app.android`) runs fine **without** hiding — not added.

DenyList + Zygisk state lives in `/data/adb/magisk.db` and **survives OTA and app
updates**. If a bank update starts complaining, re-tick it in DenyList; only if
that fails escalate to TrickyStore + a valid keybox (a maintenance treadmill —
avoid unless forced).

## Fetching Russian bank APKs (TLS note)

`sberbank.ru`, `tbank.ru`, `alfabank.ru` serve certs chained to the **Russian
Trusted Root CA** (GOST root, absent from stock trust stores). Fetch with that
root, proxies unset:

```bash
# grab the chain's root once:
openssl s_client -connect sberbank.ru:443 -servername sberbank.ru -showcerts \
  </dev/null 2>/dev/null | ...  > russian-trusted-root.pem
curl --cacert russian-trusted-root.pem -A '<mobile UA>' <page>
```

Always verify the downloaded APK's signer with `apksigner verify --print-certs`
against [data/downloads.md](../data/downloads.md) before installing. Alfa's site
is behind ServicePipe bot protection — use **RuStore** for it instead.

---

**← [03 — Flash LineageOS](03-flash-lineageos.md)**  ·  **[05 — Memory tuning →](05-memory-tuning.md)**  ·  [↑ README](../README.md)
