#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
CONFIGURATION=${CONFIGURATION:-release}
VERSION=${VERSION:-0.2.4}
BUILD_NUMBER=${BUILD_NUMBER:-25}
SIGNING_IDENTITY=${SIGNING_IDENTITY:--}
ARCHS=${ARCHS:-arm64}
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/ContextInput.app"
SPARKLE_DIR=$("$SCRIPT_DIR/fetch-sparkle.sh")
SPARKLE_FRAMEWORK="$SPARKLE_DIR/Sparkle.framework"

mkdir -p "$PROJECT_DIR/.build/module-cache" "$DIST_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

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
    -F "$SPARKLE_DIR" \
    "$PROJECT_DIR"/Sources/ContextInput/*.m \
    -framework AppKit \
    -framework ApplicationServices \
    -framework Carbon \
    -framework NaturalLanguage \
    -framework ServiceManagement \
    -framework Sparkle \
    -Wl,-rpath,@executable_path/../Frameworks \
    -o "$APP_DIR/Contents/MacOS/ContextInput"

install -m 644 "$PROJECT_DIR/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
ditto "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
install -m 644 "$SPARKLE_DIR/LICENSE" "$APP_DIR/Contents/Resources/Sparkle-LICENSE.txt"
if [[ -f "$PROJECT_DIR/Assets/AppIcon.icns" ]]; then
    install -m 644 "$PROJECT_DIR/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

SPARKLE_B="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B"

if [[ "$ARCHS" == "arm64" ]]; then
    for executable in \
        "$SPARKLE_B/Autoupdate" \
        "$SPARKLE_B/Sparkle" \
        "$SPARKLE_B/Updater.app/Contents/MacOS/Updater" \
        "$SPARKLE_B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
        "$SPARKLE_B/XPCServices/Installer.xpc/Contents/MacOS/Installer"; do
        lipo "$executable" -thin arm64 -output "$executable"
    done
fi

RESOLVED_SIGNING_IDENTITY="$SIGNING_IDENTITY"
if [[ "$SIGNING_IDENTITY" != "-" && ! "$SIGNING_IDENTITY" =~ '^[[:xdigit:]]{40}$' ]]; then
    identity_line=$(security find-identity -v -p codesigning | grep -F "\"$SIGNING_IDENTITY\"" | head -n 1 || true)
    if [[ -z "$identity_line" ]]; then
        echo "No valid code-signing identity found: $SIGNING_IDENTITY" >&2
        exit 1
    fi
    RESOLVED_SIGNING_IDENTITY=$(echo "$identity_line" | awk '{print $2}')
fi

SIGNING_ARGS=(--force --sign "$RESOLVED_SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" == Developer\ ID\ Application:* ]]; then
    SIGNING_ARGS+=(--options runtime --timestamp)
else
    SIGNING_ARGS+=(--timestamp=none)
fi

codesign "${SIGNING_ARGS[@]}" "$SPARKLE_B/XPCServices/Downloader.xpc"
codesign "${SIGNING_ARGS[@]}" "$SPARKLE_B/XPCServices/Installer.xpc"
codesign "${SIGNING_ARGS[@]}" "$SPARKLE_B/Updater.app"
codesign "${SIGNING_ARGS[@]}" "$SPARKLE_B/Autoupdate"
codesign "${SIGNING_ARGS[@]}" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
codesign "${SIGNING_ARGS[@]}" "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "$APP_DIR"
