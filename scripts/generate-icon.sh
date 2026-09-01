#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_DIR/.build/icon"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

rm -rf "$BUILD_DIR"
mkdir -p "$ICONSET_DIR" "$PROJECT_DIR/Assets" "$PROJECT_DIR/.build/module-cache"
clang \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$PROJECT_DIR/.build/module-cache" \
    -Wall -Wextra -Wpedantic -Werror \
    "$SCRIPT_DIR/generate-icon.m" \
    -framework AppKit \
    -o "$BUILD_DIR/generate-icon"
clang \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$PROJECT_DIR/.build/module-cache" \
    -Wall -Wextra -Wpedantic -Werror \
    "$SCRIPT_DIR/package-icns.m" \
    -framework Foundation \
    -o "$BUILD_DIR/package-icns"

"$BUILD_DIR/generate-icon" "$BUILD_DIR/AppIcon-1024.png"

for icon_spec in \
    '16 icon_16x16.png' \
    '32 icon_16x16@2x.png' \
    '32 icon_32x32.png' \
    '64 icon_32x32@2x.png' \
    '128 icon_128x128.png' \
    '256 icon_128x128@2x.png' \
    '256 icon_256x256.png' \
    '512 icon_256x256@2x.png' \
    '512 icon_512x512.png' \
    '1024 icon_512x512@2x.png'; do
    set -- ${=icon_spec}
    sips -z "$1" "$1" "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/$2" >/dev/null
done

"$BUILD_DIR/package-icns" "$ICONSET_DIR" "$PROJECT_DIR/Assets/AppIcon.icns"
echo "$PROJECT_DIR/Assets/AppIcon.icns"
