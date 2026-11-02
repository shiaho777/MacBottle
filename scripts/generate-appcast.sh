#!/bin/zsh
#
# Generate a signed Sparkle appcast from a directory of release zips.
#
# Requires Sparkle's `generate_appcast` tool and the EdDSA private key:
#   SPARKLE_BIN=/path/to/Sparkle/bin
#   SPARKLE_ED_PRIVATE_KEY_FILE=~/.macbottle-sparkle-key
#
# Usage:
#   scripts/generate-appcast.sh dist/appcast
#
set -euo pipefail

DIR="${1:-dist/appcast}"
SPARKLE_BIN="${SPARKLE_BIN:-/Applications/Sparkle/bin}"
KEY_FILE="${SPARKLE_ED_PRIVATE_KEY_FILE:-$HOME/.macbottle-sparkle-key}"

if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
    echo "generate_appcast not found at $SPARKLE_BIN" >&2
    exit 1
fi
if [[ ! -f "$KEY_FILE" ]]; then
    echo "Sparkle private key not found at $KEY_FILE" >&2
    exit 1
fi
if ! ls "$DIR"/*.zip >/dev/null 2>&1; then
    echo "no .zip release artifacts in $DIR" >&2
    exit 1
fi

"$SPARKLE_BIN/generate_appcast" \
    --ed-key-file "$KEY_FILE" \
    --download-url-prefix "https://github.com/shiaho777/MacBottle/releases/download/" \
    "$DIR"

echo "appcast written to $DIR/appcast.xml"
echo "commit it to the repository root (or upload it to the feed host)."
