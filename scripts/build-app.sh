#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
CONFIGURATION=${CONFIGURATION:-release}
BUILD_NUMBER=${BUILD_NUMBER:-10}
SIGNING_IDENTITY=${SIGNING_IDENTITY:--}
ARCHS=${ARCHS:-arm64}
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/ContextInput.app"

mkdir -p "$PROJECT_DIR/.build/module-cache" "$DIST_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

ARCH_FLAGS=()
for architecture in ${(z)ARCHS}; do
    ARCH_FLAGS+=(-arch "$architecture")
done

OPTIMIZATION_FLAGS=(-O2)
if [[ "$CONFIGURATION" == "debug" ]]; then
    OPTIMIZATION_FLAGS=(-O0 -g)
fi

clang \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$PROJECT_DIR/.build/module-cache" \
    -mmacosx-version-min=13.0 \
    -Wall -Wextra -Wpedantic -Werror \
    "${ARCH_FLAGS[@]}" \
    "${OPTIMIZATION_FLAGS[@]}" \
    -I "$PROJECT_DIR/Sources/ContextInput" \
    "$PROJECT_DIR"/Sources/ContextInput/*.m \
    -framework AppKit \
    -framework ApplicationServices \
    -framework Carbon \
    -framework NaturalLanguage \
    -framework ServiceManagement \
    -o "$APP_DIR/Contents/MacOS/ContextInput"

install -m 644 "$PROJECT_DIR/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -f "$PROJECT_DIR/Assets/AppIcon.icns" ]]; then
    install -m 644 "$PROJECT_DIR/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "$APP_DIR"
