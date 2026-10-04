# Downloads manifest

Every binary used in this project, with its **official source** and **SHA-256**.
None are committed to the repo (copyright + size). Verify every download against
the checksum here before flashing or installing.

> Russian bank/official sites serve certificates chained to the **Russian Trusted
> Root CA** (Ministry of Digital Development, a GOST root absent from stock trust
> stores). Fetch their pages with that root (`--cacert russian-trusted-root.pem`)
> and with proxies unset. See [docs/04-root-and-banking.md](../docs/04-root-and-banking.md).

## ROM / firmware

| File | Source | SHA-256 |
|---|---|---|
| `lineage-23.2-20260910_055551-UNOFFICIAL-blossom.zip` | SourceForge `blossom-uploads/LineageOS/23.2/` (links via Telegram `@Jayedupdate`) | `cfcae6dc4e5ff248cd30fa5f591e48b45ca02cca724c438fba49299a0f737b3a` |
| `NikGapps-core-arm64-16-20260222-signed.zip` | SourceForge `nikgapps/Releases/Android-16/22-Feb-2026/` | `db4ee632ce0d2a1df864bdbccccd38ddd1b018ce9f4b525e9a60aff009e4fec5` |
| `angelican_fastboot_12.5.3_RU.tgz` (MIUI 12.5.3 base, fastboot) | `bigota.d.miui.com/V12.5.3.0.RCSRUXM/` (md5 `de265064995db1e171cf7d1791d2d66a`) | `8421343dcfa265b48b25020b54bb106a97ce096ab95505b5074ece2db973008c` |

`recovery.img` and `boot.img` are extracted from the LineageOS zip itself
(`unzip <zip> recovery.img boot.img`) — no separate download.

SourceForge blocks data-center/VPN IPs with HTTP 403 on file pages but serves its
RSS/file-feed; the actual `.zip` must be fetched from a residential connection
(or a phone browser), then verified against the SHA-256 above.

## Root

| File | Source | SHA-256 |
|---|---|---|
| `Magisk-v30.7.apk` | GitHub `topjohnwu/Magisk` releases | `e0d32d2123532860f97123d927b1bb86c4e08e6fd8a48bfc6b5bee0afae9ebd5` |

Magisk APK signer: `CN=John Wu, L=Taipei, C=TW`.

## Apps (verified APKs)

All pulled from official sources; signer verified with `apksigner`.

| App | Package | Source | Signer | SHA-256 |
|---|---|---|---|---|
| Sberbank | `ru.sberbankmobile` | `cdnweb.sberbank.ru/appdistr/SberbankOnline.apk` (via `apps.sber.ru`) | `O=Sberbank of Russia` | `790c82132b80adbb572b1e8914bd94b4b0bdbec8d9d6772256ae240daf4fb9dc` |
| T-Bank | `com.idamob.tinkoff.android` | `acdn.t-bank-app.ru` (via `tbank.ru/apps/android-bank/`) | `CN=TCSBank.Ru` | `00e0555edb41263b892b604db77172e40bbec53cbdcabe4c341a03f776c31a81` |
| T-Business | `ru.tinkoff.sme` | `acdn.t-bank-app.ru` (via `tbank.ru/apps/android-business/`) | `CN=TCSBank.Ru` | `a50253e01536216c96cb01c335a25c1bf41f1e5036a3e7a97f8d40adf23e97f7` |
| Telegram | `org.telegram.messenger.web` | `telegram.org/dl/android/apk` | `CN=Nikolay Kudashov, O=VK` | `7827ea506d297644b1d350266bdfbd8d5d38a7869fa3fc1a0fbcb1ebc81f45ad` |
| AmneziaVPN (arm64) | `org.amnezia.vpn` | GitHub `amnezia-vpn/amnezia-client` 5.0.3.0 | `CN=AmneziaVPN` | `2e47063f52dad3fc4c527f7def9d0f21ef75e45021e0c3f30bd4623cc0c83eac` |
| Termux | `com.termux` | GitHub `termux/termux-app` v0.118.3 | `CN=APK Signer, OU=Earth` | `72fdb596045116bf5ba1b5bdf5b26fddb9acc0bd074ad9f2da9eb0ae85e83a4e` |

Alfa-Bank (`ru.alfabank.mobile.android`) — official site `alfabank.ru` is behind
ServicePipe bot protection (not fetchable via curl); install from **RuStore**.

T-Bank note: the CDN occasionally truncates the download at HTTP 200 with a short
body; resume the missing tail with a `Range` request and re-verify the ZIP EOCD.
