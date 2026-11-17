#!/bin/zsh
#
# Package an installed engine tree for the signed manifest channel.
#
# Usage:
#   scripts/package-engine.sh <engine-root> <output.tar.xz>
#
# The archive contains the engine root's contents (Wine/, DXVK/, ...),
# so EngineInstallLayout.wineRoot can extract it directly. It does not
# contain the parent directory. The script prints the SHA-256 and size
# needed by scripts/add-engine-release.py.
#
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <engine-root> <output.tar.xz>" >&2
    exit 2
fi

ENGINE_ROOT="$1"
OUTPUT="$2"

if [[ ! -d "$ENGINE_ROOT" ]]; then
    echo "error: engine root not found: $ENGINE_ROOT" >&2
    exit 1
fi
if [[ ! -x "$ENGINE_ROOT/Wine/bin/wine64" && ! -x "$ENGINE_ROOT/Wine/bin/wine" ]]; then
    echo "error: $ENGINE_ROOT does not contain Wine/bin/wine64 or Wine/bin/wine" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"

# Apple's D3DMetal (Game Porting Toolkit) is closed source and may not be
# redistributed. Stage a copy of the engine tree and strip any D3DMetal
# payload before archiving; the app detects a local GPTK install at run
# time instead. The source engine tree is left untouched.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
COPYFILE_DISABLE=1 cp -R "$ENGINE_ROOT/" "$STAGE/"
find "$STAGE" -iname "*d3dmetal*" -prune -exec rm -rf {} + 2>/dev/null || true
find "$STAGE" -iname "*gptk*" -prune -exec rm -rf {} + 2>/dev/null || true
# Drop AppleDouble (._) sidecars so no closed-source payload metadata or
# other resource-fork junk survives into the archive.
find "$STAGE" -name "._*" -type f -delete 2>/dev/null || true

# COPYFILE_DISABLE keeps AppleDouble ._ files out of the archive; Wine
# does not care about them, but they waste space and confuse reviewers.
COPYFILE_DISABLE=1 tar --no-mac-metadata -cJf "$OUTPUT" -C "$STAGE" .

SHA="$(shasum -a 256 "$OUTPUT" | awk '{print $1}')"
SIZE="$(stat -f%z "$OUTPUT")"

echo "archive=$OUTPUT"
echo "sha256=$SHA"
echo "size=$SIZE"
echo ""
echo "Next: upload the archive, then run scripts/add-engine-release.py with these values."
