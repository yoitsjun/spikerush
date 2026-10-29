"""Create the game passes and developer products in a universe through Open Cloud, and swap the
new ids into src/shared/Config.lua (by the old id each one replaces).

    python tools/opencloud_monetization.py tools/monetization_manifest.json          # create what's missing
    python tools/opencloud_monetization.py tools/monetization_manifest.json --swap   # then swap the ids

Manifest entries: {"old": <old id>, "kind": "pass" | "product", "name", "description", "price",
"image": <path from the repo root, optional>}. Results go to <manifest>.results.json (old -> new),
so a rerun only creates what's missing. Key and universe as in tools/opencloud_upload.py
(VOLLEYBALL_KEY_FILE, VOLLEYBALL_UNIVERSE, default 10773415799).
"""

import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KEY_FILE = Path(os.environ.get("VOLLEYBALL_KEY_FILE", Path.home() / "Documents" / "NewVolleyball" / ".roblox_api_key"))
UNIVERSE = os.environ.get("VOLLEYBALL_UNIVERSE", "10773415799")
URL = {
    "pass": f"https://apis.roblox.com/game-passes/v1/universes/{UNIVERSE}/game-passes",
    "product": f"https://apis.roblox.com/developer-products/v2/universes/{UNIVERSE}/developer-products",
}


def create(entry):
    boundary = uuid.uuid4().hex
    fields = {
        "name": entry["name"],
        "description": entry.get("description", ""),
        "price": str(entry["price"]),
        "isForSale": "true",
        "isRegionalPricingEnabled": "true",
    }
    body = b""
    for k, v in fields.items():
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
    if entry.get("image"):
        path = ROOT / entry["image"]
        body += (f'--{boundary}\r\nContent-Disposition: form-data; name="imageFile"; filename="{path.name}"\r\n'
                 f"Content-Type: image/png\r\n\r\n").encode() + path.read_bytes() + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    key = KEY_FILE.read_text(encoding="utf-8").strip()
    req = urllib.request.Request(URL[entry["kind"]], data=body, method="POST",
                                 headers={"x-api-key": key, "Content-Type": f"multipart/form-data; boundary={boundary}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{entry['name']}: {e.code} {e.read()[:300].decode('utf-8', 'replace')}")
    new = data.get("gamePassId") or data.get("productId") or data.get("id")
    if not new:
        raise RuntimeError(f"{entry['name']}: no id in {data}")
    return str(new)


def main():
    manifest = Path(sys.argv[1])
    entries = json.loads(manifest.read_text(encoding="utf-8"))
    results_path = manifest.with_suffix(".results.json")
    results = json.loads(results_path.read_text(encoding="utf-8")) if results_path.exists() else {}
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None

    if "--swap" in sys.argv:
        config = ROOT / "src" / "shared" / "Config.lua"
        text = config.read_bytes().decode("utf-8")
        for old, new in results.items():
            n = text.count(old)
            if n != 1:
                print(f"skip {old}: found {n} times")
                continue
            text = text.replace(old, new)
            print(f"{old} -> {new}")
        config.write_bytes(text.encode("utf-8"))
        return

    for entry in entries:
        old = str(entry["old"])
        if old in results or (only and old != only):
            continue
        try:
            results[old] = create(entry)
        except RuntimeError as e:
            print("FAILED", e)
            continue
        results_path.write_text(json.dumps(results, indent=1), encoding="utf-8")
        print(f"{entry['kind']} {entry['name']} ({entry['price']}): {old} -> {results[old]}")
    print(f"{len(results)} of {len(entries)} made")


if __name__ == "__main__":
    main()
