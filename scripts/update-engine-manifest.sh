#!/bin/zsh
#
# Refresh engine-manifest.json from the pinned Gcenx release, then sign it.
# Requires MACBOTTLE_ENGINE_SIGNING_KEY (base64 Ed25519 private key) or the
# local ~/.macbottle-engine-signing-key file.
#
set -euo pipefail

URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/wine-devel-11.21-osx64.tar.xz"
VERSION="11.21"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/engine-manifest.json"

TMP="$(mktemp -t macbottle-engine)"
trap 'rm -f "$TMP"' EXIT
echo "Downloading $URL"
curl -fL --retry 3 --max-time 900 -o "$TMP" "$URL"
SHA="$(shasum -a 256 "$TMP" | awk '{print $1}')"
SIZE="$(stat -f%z "$TMP")"
echo "sha256=$SHA size=$SIZE"

python3 - "$MANIFEST" "$URL" "$VERSION" "$SHA" "$SIZE" <<'PY'
import datetime
import json
import sys

path, url, version, sha, size = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    manifest = json.load(handle)

manifest["generated_at"] = datetime.datetime.now(
    datetime.timezone.utc
).replace(microsecond=0).isoformat().replace("+00:00", "Z")

release = next(item for item in manifest["releases"] if item["engine_id"] == "gcenx-wine")
release.update({
    "version": version,
    "url": url,
    "sha256": sha,
    "size": int(size),
})

with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

swift "$ROOT/scripts/sign-engine-manifest.swift" "$MANIFEST"
