#!/bin/zsh
# Build a native aarch64 Wine for macOS and package it for the
# "Import ARM64 Wine" channel in MacBottle Settings.
#
# Source: github.com/citi94/wine-macos-arm64 (Wine 11.10 + ARM64 port, LGPL-2.1)
# Toolchain: mstorsjo/llvm-mingw (macOS universal)
#
# Usage: scripts/build-wine-arm64.sh [workspace-dir]
# Produces <workspace>/dist/wine-arm64.tar.gz

set -euo pipefail

WORK="${1:-$HOME/wine-arm64-build}"
THISDIR="$(cd "$(dirname "$0")/.." && pwd)"
JOBS=$(( $(sysctl -n hw.ncpu) - 2 ))
PORT_REPO="https://github.com/citi94/wine-macos-arm64.git"
PORT_BRANCH="macos-arm64-port"
LLVM_MINGW_VERSION="20260826"
LLVM_MINGW_ASSET="llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-macos-universal.tar.xz"

mkdir -p "$WORK"
cd "$WORK"

if [[ ! -d llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-macos-universal ]]; then
    curl -LO "https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/${LLVM_MINGW_ASSET}"
    tar -xJf "$LLVM_MINGW_ASSET"
fi
TOOLCHAIN="$WORK/llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-macos-universal"

if [[ ! -d wine-src ]]; then
    git clone --depth 1 --branch "$PORT_BRANCH" "$PORT_REPO" wine-src
fi

# Apply macOS 26 compatibility patches (TSD-backed x18 restore broke when
# Apple moved the pthread direct-TSD array; see scripts/patches/ and issue #97).
if [[ ! -f "$WORK/.patches-applied" ]]; then
    (cd "$WORK/wine-src" && for patch in "$THISDIR"/scripts/patches/*.patch; do patch -p1 < "$patch"; done)
    touch "$WORK/.patches-applied"
fi

if [[ ! -d build-tools/Makefile ]]; then
    mkdir -p build-tools && cd build-tools
    PATH="$TOOLCHAIN/bin:$PATH" "$WORK/wine-src/configure" \
        --without-x --without-freetype --disable-tests >/dev/null
    PATH="$TOOLCHAIN/bin:$PATH" make -j"$JOBS" >/dev/null
    cd "$WORK"
fi

if [[ ! -d build-arm64/Makefile ]]; then
    mkdir -p build-arm64 && cd build-arm64
    PATH="$TOOLCHAIN/bin:$PATH" "$WORK/wine-src/configure" \
        --enable-archs=aarch64 --without-x --without-freetype --disable-tests \
        --with-wine-tools="$WORK/build-tools" \
        CC=clang >/dev/null
    cd "$WORK"
fi

cd build-arm64
PATH="$TOOLCHAIN/bin:$PATH" make -j"$JOBS"
PATH="$TOOLCHAIN/bin:$PATH" make install DESTDIR="$WORK/pkg" >/dev/null
cd "$WORK"

grep -oE "dlls/[a-z0-9_.]+/aarch64-windows" build-arm64/Makefile | sort -u | while read -r d; do
    [[ -d "build-arm64/$d" ]] || mkdir -p "build-arm64/$d"
done

cat > wine-entitlements.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key><true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
EOF

codesign -s - -f --entitlements wine-entitlements.plist pkg/usr/local/bin/wine
find pkg/usr/local/lib/wine -type f \( -name "*.so" -o -name "*.dll" -o -name "*.exe" \) | while read -r f; do
    codesign -s - -f "$f" 2>/dev/null || true
done

cat > pkg/WhiskyWineVersion.plist <<EOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Version</key>
    <string>$(pkg/usr/local/bin/wine --version | sed 's/^wine-//')</string>
</dict>
</plist>
EOF2

mkdir -p dist
tar -czf dist/wine-arm64.tar.gz -C pkg usr
echo "packaged: $WORK/dist/wine-arm64.tar.gz"
