#!/usr/bin/env python3
"""Package multi-manager-debug and optionally publish it to GitHub and the mod portal.

    scripts/release.py                 # build the zip only
    scripts/release.py --tag v1.0.0    # publish to GitHub and the portal
    scripts/release.py --tag v1.0.0 --create-page

The GitHub release is the manager's fallback download. The portal release is what
a player's client installs. Both are required unless --no-portal is explicit.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_REPO = "NovaProtocol/multi-manager-debug"
SHIPPED = ["info.json", "control.lua", "changelog.txt", "LICENSE", "README.md"]
SHIPPED_DIRS = ["debug"]
MOD_PORTAL = "https://mods.factorio.com"


def read_info():
    with open(ROOT / "info.json", encoding="utf-8") as handle:
        return json.load(handle)


def shipped_files():
    files = []
    for name in SHIPPED:
        if not (ROOT / name).exists():
            raise SystemExit(f"missing {name}; the mod would be incomplete")
        files.append(name)
    for directory in SHIPPED_DIRS:
        root = ROOT / directory
        if not root.is_dir():
            raise SystemExit(f"missing {directory}/; the mod would be incomplete")
        for path in sorted(root.rglob("*.lua")):
            files.append(path.relative_to(ROOT).as_posix())
    return files


def check_lua():
    parser = next(
        (shutil.which(name) for name in ("luac5.4", "luac", "lua", "luajit") if shutil.which(name)),
        None,
    )
    if not parser:
        print("no Lua parser on PATH, syntax not checked")
        return
    kind = os.path.basename(parser)
    for name in [path for path in shipped_files() if path.endswith(".lua")]:
        source = str(ROOT / name)
        if kind == "lua":
            command = [parser, "-e", f"assert(loadfile('{source}'))"]
        elif kind == "luajit":
            command = [parser, "-b", source, os.devnull]
        else:
            command = [parser, "-p", source]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            raise SystemExit(f"{name} does not parse: {result.stderr.strip()}")
    print(f"Lua parses ({parser})")


def build(info):
    check_lua()
    files = shipped_files()
    stem = f"{info['name']}_{info['version']}"
    out = ROOT / f"{stem}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in files:
            archive.write(ROOT / name, f"{stem}/{name}")
    print(f"built {out.name} ({out.stat().st_size} bytes, {len(files)} files)")
    return out, stem


def api(repo, path, token, method="GET", payload=None):
    body = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}{path}", data=body, method=method)
    request.add_header("Authorization", f"Bearer {token}")
    request.add_header("Accept", "application/vnd.github+json")
    if body is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"GitHub {method} {path} failed: {error.code} {detail}") from None


def publish(zip_path, stem, repo, tag, token):
    try:
        release = api(repo, f"/releases/tags/{tag}", token)
        print(f"release {tag} already exists, reusing it")
    except SystemExit:
        release = api(repo, "/releases", token, "POST", {
            "tag_name": tag,
            "name": tag,
            "body": f"multi-manager-debug {stem.split('_')[-1]}",
        })
        print(f"created release {tag}")
    for asset in release.get("assets", []):
        if asset["name"] == zip_path.name:
            api(repo, f"/releases/assets/{asset['id']}", token, "DELETE")
            print(f"replaced existing asset {asset['name']}")
    upload = (
        f"https://uploads.github.com/repos/{repo}/releases/{release['id']}/assets"
        f"?name={zip_path.name}"
    )
    data = zip_path.read_bytes()
    request = urllib.request.Request(upload, data=data, method="POST")
    request.add_header("Authorization", f"Bearer {token}")
    request.add_header("Content-Type", "application/zip")
    try:
        with urllib.request.urlopen(request) as response:
            asset = json.loads(response.read())
    except urllib.error.HTTPError as error:
        raise SystemExit(f"asset upload failed: {error.code} {error.read().decode(errors='replace')}") from None
    print(f"uploaded {asset['name']} to {release['html_url']}")
    return asset["browser_download_url"]


def portal_init(name, key, create):
    endpoint = "/api/v2/mods/init_publish" if create else "/api/v2/mods/releases/init_upload"
    body = urllib.parse.urlencode({"mod": name}).encode()
    request = urllib.request.Request(MOD_PORTAL + endpoint, data=body, method="POST")
    request.add_header("Authorization", f"Bearer {key}")
    request.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read())["upload_url"]
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"portal {endpoint} failed: {error.code} {detail}") from None


def portal_send(upload_url, zip_path, key):
    boundary = "----multi-manager-debug" + uuid.uuid4().hex
    body = b"".join([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="file"; filename="{zip_path.name}"\r\n'.encode(),
        b"Content-Type: application/zip\r\n\r\n",
        zip_path.read_bytes(),
        b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ])
    if not upload_url.startswith("http"):
        upload_url = MOD_PORTAL + upload_url
    request = urllib.request.Request(upload_url, data=body, method="POST")
    request.add_header("Authorization", f"Bearer {key}")
    request.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"portal upload failed: {error.code} {detail}") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tag")
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--no-portal", action="store_true")
    parser.add_argument("--create-page", action="store_true")
    parser.add_argument("--commit", action="store_true")
    args = parser.parse_args()

    info = read_info()
    zip_path, stem = build(info)

    if args.commit:
        subprocess.run(["git", "add", "-A"], cwd=ROOT, check=True)
        subprocess.run(["git", "commit", "-m", f"release: {info['name']} {info['version']}"], cwd=ROOT, check=True)

    if not args.tag:
        print("no --tag given, zip built only")
        return 0

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not token:
        print("GITHUB_TOKEN (or GH_TOKEN) is required to publish", file=sys.stderr)
        return 2

    key = None
    if not args.no_portal:
        key = os.environ.get("MOD_PORTAL_KEY")
        if not key:
            print("MOD_PORTAL_KEY is required; pass --no-portal to publish GitHub only", file=sys.stderr)
            return 2

    if key:
        upload_url = portal_init(info["name"], key, args.create_page)
        result = portal_send(upload_url, zip_path, key)
        print(f"portal: uploaded {info['name']} {info['version']} -> {result.get('url', result)}")

    url = publish(zip_path, stem, args.repo, args.tag, token)
    print(f"manager can fetch it from {url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
