#!/bin/sh
#
# Guard the Whisky -> MacBottle source rename.
#
# The GPL notice body and a small set of compatibility identifiers still
# say "Whisky" on purpose (see MIGRATION.md). Everything else is
# MacBottle. This script fails when a source header or a target name
# regresses to the upstream name.
#
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

status=0

if grep -rnE '^//  (Whisky|WhiskyKit|WhiskyKitTests|WhiskyCmd|WhiskyThumbnail)$' \
    --include='*.swift' . >/dev/null 2>&1; then
    echo "error: Swift source headers still use the upstream project name:"
    grep -rnE '^//  (Whisky|WhiskyKit|WhiskyKitTests|WhiskyCmd|WhiskyThumbnail)$' \
        --include='*.swift' .
    status=1
fi

if grep -n 'name: "Whisky\|name = Whisky\|productName = Whisky\|PRODUCT_NAME = Whisky' \
    MacBottleKit/Package.swift MacBottle.xcodeproj/project.pbxproj >/dev/null 2>&1; then
    echo "error: package or target names still use the upstream project name:"
    grep -n 'name: "Whisky\|name = Whisky\|productName = Whisky\|PRODUCT_NAME = Whisky' \
        MacBottleKit/Package.swift MacBottle.xcodeproj/project.pbxproj
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "branding: source headers and target names are MacBottle"
fi
exit "$status"
