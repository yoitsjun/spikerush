"""Upload images, sounds and FBX models to Roblox through Open Cloud, as the group that owns the
key, and swap the new ids into src/shared/Assets.lua.

    python tools/opencloud_upload.py tools/reupload_manifest.json            # upload what's missing
    python tools/opencloud_upload.py tools/reupload_manifest.json --swap     # then swap the ids

The manifest is a list of {"old": "<id>", "file": "<path from the repo root>", "type": "Decal" |
"Audio" | "Model", "name": "<display name>"}. Results go to <manifest>.results.json (old -> new),
so a rerun only uploads what hasn't gone up yet. The key is read from the file in
VOLLEYBALL_KEY_FILE (default Documents/NewVolleyball/.roblox_api_key) and never printed; the group
id comes from VOLLEYBALL_GROUP (default 805769952, Jun Games Production).
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KEY_FILE = Path(os.environ.get("VOLLEYBALL_KEY_FILE", Path.home() / "Documents" / "NewVolleyball" / ".roblox_api_key"))
GROUP = os.environ.get("VOLLEYBALL_GROUP", "805769952")
MIME = {".png": "image/png", ".jpg": "image/jpeg", ".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".wav": "audio/wav", ".fbx": "model/fbx"}


def key():
    return KEY_FILE.read_text(encoding="utf-8").strip()


def call(method, url, body=None, headers=None):
    req = urllib.request.Request(url, data=body, method=method, headers={"x-api-key": key(), **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {url} -> {e.code}: {e.read()[:400].decode('utf-8', 'replace')}")


def upload(entry):
    path = ROOT / entry["file"]
    request = {
        "assetType": entry["type"],
        "displayName": entry["name"][:50],
        "description": "Volleyball Rush",
        "creationContext": {"creator": {"groupId": GROUP}},
    }
    boundary = uuid.uuid4().hex
    parts = [
        f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\nContent-Type: application/json\r\n\r\n'.encode()
        + json.dumps(request).encode() + b"\r\n",
        f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="{path.name}"\r\n'
        f"Content-Type: {MIME[path.suffix.lower()]}\r\n\r\n".encode() + path.read_bytes() + b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ]
    op = call("POST", "https://apis.roblox.com/assets/v1/assets", b"".join(parts),
              {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    for _ in range(60):
        if op.get("done"):
            if "error" in op:
                raise RuntimeError(f"{entry['name']}: {op['error']}")
            return str(op["response"]["assetId"])
        time.sleep(2)
        op = call("GET", f"https://apis.roblox.com/assets/v1/{op['path']}")
    raise RuntimeError(f"{entry['name']}: still processing after 2 minutes ({op.get('path')})")


def main():
    manifest_path = Path(sys.argv[1])
    entries = json.loads(manifest_path.read_text(encoding="utf-8"))
    results_path = manifest_path.with_suffix(".results.json")
    results = json.loads(results_path.read_text(encoding="utf-8")) if results_path.exists() else {}

    if "--swap" in sys.argv:
        assets = ROOT / "src" / "shared" / "Assets.lua"
        text = assets.read_bytes().decode("utf-8")
        for old, new in results.items():
            n = text.count(f'"{old}"')
            text = text.replace(f'"{old}"', f'"{new}"')
            print(f"{old} -> {new} ({n} place{'s' if n != 1 else ''})")
        assets.write_bytes(text.encode("utf-8"))
        return

    for entry in entries:
        if entry["old"] in results:
            continue
        try:
            new = upload(entry)
        except RuntimeError as e:
            print("FAILED", e)
            continue
        results[entry["old"]] = new
        results_path.write_text(json.dumps(results, indent=1), encoding="utf-8")
        print(f"{entry['name']}: {entry['old']} -> {new}")
    print(f"{len(results)} of {len(entries)} uploaded")


if __name__ == "__main__":
    main()
