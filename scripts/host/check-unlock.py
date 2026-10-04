#!/usr/bin/env python3
"""Узнать остаток времени до разблокировки загрузчика, НИЧЕГО не разблокируя.

Повторяет шаги miunlock.unlock.unlock_device, но НЕ выполняет
`fastboot stage` / `fastboot oem unlock`. Телефон остаётся заблокированным,
данные не стираются.
"""
import random

from migate import get_passtoken, get_service, get_region, get_dataCenterZone
import migate.login.browser_qr as _bq

# Показать ссылку для входа в терминале, а не только открыть браузер
_orig_system = _bq.os.system


def _system_and_print(cmd):
    if "xdg-open" in cmd:
        url = cmd.split("'")[1] if "'" in cmd else cmd
        print(f"\n>>> Ссылка для входа в Mi-аккаунт:\n{url}\n", flush=True)
    return _orig_system(cmd)


_bq.os.system = _system_and_print
from miunlock.commands import get_device_token, get_product
from miunlock.fastboot import get_fastboot
from miunlock.utils import _send

DOMAINS = {
    "Singapore": "https://unlock.update.intl.miui.com",
    "China": "https://unlock.update.miui.com",
    "India": "https://in-unlock.update.intl.miui.com",
    "Russia": "https://ru-unlock.update.intl.miui.com",
    "Europe": "https://eu-unlock.update.intl.miui.com",
}
ZONES = {"CN": "China", "IN": "India", "RU": "Russia"}
EU = {"AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "EL",
      "HU", "IS", "IE", "IT", "LV", "LI", "LT", "LU", "MT", "NL", "NO", "PL",
      "PT", "RO", "SK", "SI", "ES", "SE", "UK"}


def main():
    fastboot_cmd = get_fastboot()

    param = {"sid": "unlockApi", "checkSafeAddress": True}
    passToken = get_passtoken(param)
    if passToken is None:
        raise SystemExit("Не удалось войти в Mi-аккаунт")

    service = get_service(passToken, param)
    if service is None:
        raise SystemExit("Не удалось получить сессию unlockApi")

    region = get_region(passToken)
    if region is None:
        zone = get_dataCenterZone(passToken["userId"])
    else:
        print(f"Регион аккаунта: {region}")
        zone = ZONES.get(region) or ("Europe" if region in EU else "Singapore")
    print(f"dataCenterZone: {zone}")
    domain = DOMAINS.get(zone)

    cookies = service["cookies"]
    ssecurity = service["servicedata"]["ssecurity"]
    deviceId = service["servicedata"]["deviceId"]

    r = "".join(random.choices("abcdefghijklmnopqrstuvwxyz", k=16))
    nonce_resp = _send("/api/v2/nonce", {"r": r}, domain, ssecurity, cookies)
    if "error" in nonce_resp or nonce_resp.get("code") != 0:
        raise SystemExit(f"nonce: {nonce_resp}")
    nonce = nonce_resp["nonce"]

    print("\nТелефон должен быть в режиме fastboot...")
    product = get_product(fastboot_cmd)
    if isinstance(product, dict) and "error" in product:
        raise SystemExit(f"fastboot: {product['error']}")
    print(f"Кодовое имя устройства: {product}")

    clear = _send("/api/v2/unlock/device/clear",
                  {"appId": "1", "data": {"product": product}, "nonce": nonce},
                  domain, ssecurity, cookies)
    if "error" in clear or clear.get("code") != 0:
        raise SystemExit(f"clear: {clear}")
    print(f"\nСообщение сервера: {clear.get('notice')}")
    print("Данные при разблокировке будут стёрты"
          if clear.get("cleanOrNot") == 1 else
          "Разблокировка не сотрёт данные")

    device_token = get_device_token(fastboot_cmd)
    if isinstance(device_token, dict) and "error" in device_token:
        raise SystemExit(f"device token: {device_token['error']}")

    import hashlib
    data = {
        "clientId": "2",
        "clientVersion": "7.6.727.43",
        "deviceInfo": {"boardVersion": "", "deviceName": "",
                       "product": product, "socId": ""},
        "deviceToken": device_token,
        "language": "en",
        "operate": "unlock",
        "pcId": hashlib.md5(deviceId.encode()).hexdigest(),
        "region": "",
        "uid": cookies.get("userId"),
    }
    res = _send("/api/v3/ahaUnlock",
                {"appId": "1", "data": data, "nonce": nonce},
                domain, ssecurity, cookies)

    print("\n--- ОТВЕТ СЕРВЕРА XIAOMI ---")
    if "error" in res:
        print(res["error"])
    elif res.get("code") != 0:
        print(f"code: {res.get('code')}")
        print(f"описание: {res.get('descEN') or res}")
    else:
        print("Время ожидания ИСТЕКЛО: сервер выдал разрешение на разблокировку.")
        print("Разблокировка НЕ выполнена — этот скрипт её не делает.")
    print("\nЗагрузчик не тронут, данные на месте.")


if __name__ == "__main__":
    main()
