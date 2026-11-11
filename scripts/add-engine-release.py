#!/usr/bin/env python3
"""Add or update one engine release in the signed manifest.

The archive is hashed locally, so the signed manifest and the uploaded
bytes cannot disagree. After writing the entry the script re-signs the
manifest with the same Ed25519 key the app trusts.

Example:
    python3 scripts/add-engine-release.py \
        --engine-id macbottle-arm64 \
        --version 11.21 \
        --url https://github.com/OWNER/REPO/releases/download/engine-11.21/wine-arm64.tar.xz \
        --archive dist/wine-arm64.tar.xz \
        --display-name "MacBottle Wine (ARM64)" \
        --kind wine \
        --layout wine-root \
        --arch arm64 \
        --min-macos 14.0 \
        --capabilities wine,arm64,msync \
        --license "Wine is LGPL-2.1" \
        --notes "Native Apple Silicon build; no D3DMetal payload."
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KINDS = {"wine", "crossover", "gptk", "custom"}
LAYOUTS = {"wine-root", "gcenx-app-bundle"}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--archive", help="local archive to hash")
    parser.add_argument("--sha256")
    parser.add_argument("--size", type=int)
    parser.add_argument("--display-name", required=True)
    parser.add_argument("--kind", choices=sorted(KINDS), default="wine")
    parser.add_argument("--layout", choices=sorted(LAYOUTS), default="wine-root")
    parser.add_argument("--arch", choices=["arm64", "x86_64"], required=True)
    parser.add_argument("--min-macos", default="14.0")
    parser.add_argument("--capabilities", default="")
    parser.add_argument("--channel", default="stable")
    parser.add_argument("--license", default="")
    parser.add_argument("--notes", default="")
    parser.add_argument(
        "--manifest",
        default=os.path.join(ROOT, "engine-manifest.json"),
    )
    parser.add_argument(
        "--no-sign",
        action="store_true",
        help="write the entry without re-signing (tests only)",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    if not re.fullmatch(r"\d+(\.\d+){1,2}", args.version):
        sys.exit("error: --version must be one to three numeric parts")
    if not args.url.startswith("https://"):
        sys.exit("error: --url must be HTTPS")

    if args.archive:
        if not os.path.isfile(args.archive):
            sys.exit(f"error: archive not found: {args.archive}")
        digest = sha256(args.archive)
        size = os.path.getsize(args.archive)
        if args.sha256 and args.sha256.lower() != digest:
            sys.exit("error: --sha256 does not match the archive")
        if args.size and args.size != size:
            sys.exit("error: --size does not match the archive")
    else:
        digest = (args.sha256 or "").lower()
        size = args.size
        if not re.fullmatch(r"[0-9a-f]{64}", digest):
            sys.exit("error: pass --archive or a 64-character --sha256")
        if size is None:
            sys.exit("error: --size is required without --archive")

    capabilities = sorted({
        value.strip() for value in args.capabilities.split(",") if value.strip()
    })

    with open(args.manifest, encoding="utf-8") as handle:
        manifest = json.load(handle)

    manifest["schema"] = 2
    manifest["generated_at"] = datetime.datetime.now(
        datetime.timezone.utc
    ).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    lower_url = args.url.split("?")[0].lower()
    if lower_url.endswith((".tar.xz", ".txz")):
        package_format = "tar.xz"
    elif lower_url.endswith((".tar.gz", ".tgz")):
        package_format = "tar.gz"
    elif lower_url.endswith(".tar"):
        package_format = "tar"
    else:
        package_format = os.path.splitext(lower_url)[1].lstrip(".") or "tar"

    release = {
        "engine_id": args.engine_id,
        "version": args.version,
        "url": args.url,
        "sha256": digest,
        "size": size,
        "min_macos": args.min_macos,
        "arch": args.arch,
        "display_name": args.display_name,
        "kind": args.kind,
        "capabilities": capabilities,
        "package_format": package_format,
        "install_layout": args.layout,
        "channel": args.channel,
        "license": args.license,
        "notes": args.notes,
    }

    releases = [
        item for item in manifest.get("releases", [])
        if not (item.get("engine_id") == args.engine_id and item.get("arch") == args.arch)
    ]
    releases.append(release)
    releases.sort(key=lambda item: (item["engine_id"], item["arch"]))
    manifest["releases"] = releases

    with open(args.manifest, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")

    if not args.no_sign:
        subprocess.run(
            ["swift", os.path.join(ROOT, "scripts", "sign-engine-manifest.swift"), args.manifest],
            check=True,
        )

    print(
        f"engine={args.engine_id} arch={args.arch} version={args.version} "
        f"sha256={digest} size={size}"
    )


if __name__ == "__main__":
    main()
