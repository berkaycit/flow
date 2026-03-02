#!/usr/bin/env python3
"""Extract Chrome cookies for NotebookLM authentication.

Reads Google cookies from the user's Chrome browser and saves them
in the storage_state.json format that notebooklm-py expects.
No Playwright or separate browser window needed.
"""

import json
import sys
from pathlib import Path

from pycookiecheat import chrome_cookies

from notebooklm.paths import get_storage_path

GOOGLE_DOMAINS = [
    "https://notebooklm.google.com",
    "https://www.google.com",
    "https://accounts.google.com",
]


def main() -> None:
    all_cookies = []
    for domain in GOOGLE_DOMAINS:
        cookies = chrome_cookies(domain, as_cookies=True)
        for c in cookies:
            all_cookies.append({
                "name": c.name,
                "value": c.value,
                "domain": c.host_key,
                "path": c.path,
                "expires": c.expires_utc,
                "httpOnly": False,
                "secure": bool(c.is_secure),
                "sameSite": "Lax",
            })

    if not all_cookies:
        print(
            "Chrome'da Google cookie bulunamadi. "
            "notebooklm.google.com adresine giris yapin.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Check for SID cookie (minimum required by notebooklm-py)
    cookie_names = {c["name"] for c in all_cookies}
    if "SID" not in cookie_names:
        print(
            "SID cookie bulunamadi. "
            "Chrome'da notebooklm.google.com adresine giris yapin.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Deduplicate by (name, domain)
    seen = set()
    unique_cookies = []
    for c in all_cookies:
        key = (c["name"], c["domain"])
        if key not in seen:
            seen.add(key)
            unique_cookies.append(c)

    storage_state = {"cookies": unique_cookies, "origins": []}

    storage_path = get_storage_path()
    storage_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    storage_path.write_text(json.dumps(storage_state, indent=2), encoding="utf-8")
    storage_path.chmod(0o600)

    print("ok")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Cookie okuma hatasi: {e}", file=sys.stderr)
        sys.exit(1)
