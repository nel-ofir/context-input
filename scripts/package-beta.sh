#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
VERSION=${VERSION:-0.2.4}
BUILD_NUMBER=${BUILD_NUMBER:-25}
BETA_NUMBER=${BETA_NUMBER:-5}
SIGNING_IDENTITY=${SIGNING_IDENTITY:-ContextInput Beta Code Signing}
RELEASE_TAG=${RELEASE_TAG:-v$VERSION-beta.$BETA_NUMBER}
RELEASES_DIR="$PROJECT_DIR/dist/releases"
STAGING_DIR="$PROJECT_DIR/.build/beta-release"
APP_DIR="$PROJECT_DIR/dist/ContextInput.app"
ARCHIVE_NAME="ContextInput-$VERSION-arm64.zip"
DMG_NAME="ContextInput-$VERSION-arm64.dmg"
ARCHIVE_PATH="$RELEASES_DIR/$ARCHIVE_NAME"
DMG_PATH="$RELEASES_DIR/$DMG_NAME"
RELEASE_NOTES="$PROJECT_DIR/packaging/release-notes/$VERSION.md"

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "Missing code-signing identity: $SIGNING_IDENTITY" >&2
    echo "Run ./scripts/setup-beta-signing.sh once, then retry." >&2
    exit 1
fi

if [[ ! -f "$RELEASE_NOTES" ]]; then
    echo "Missing release notes: $RELEASE_NOTES" >&2
    exit 1
fi

mkdir -p "$RELEASES_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/dmg"

VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
    SIGNING_IDENTITY="$SIGNING_IDENTITY" ARCHS=arm64 \
    "$SCRIPT_DIR/build-app.sh"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE_PATH"
ditto "$APP_DIR" "$STAGING_DIR/dmg/ContextInput.app"
ln -s /Applications "$STAGING_DIR/dmg/Applications"
hdiutil create -volname ContextInput -srcfolder "$STAGING_DIR/dmg" \
    -ov -format UDZO "$DMG_PATH"

cp "$ARCHIVE_PATH" "$STAGING_DIR/$ARCHIVE_NAME"
cp "$RELEASE_NOTES" "$STAGING_DIR/${ARCHIVE_NAME:r}.md"
cp "$PROJECT_DIR/appcast.xml" "$STAGING_DIR/appcast.xml"

SPARKLE_DIR=$("$SCRIPT_DIR/fetch-sparkle.sh")
"$SPARKLE_DIR/bin/generate_appcast" \
    --account contextinput-beta \
    --download-url-prefix "https://github.com/nel-ofir/context-input/releases/download/$RELEASE_TAG/" \
    --embed-release-notes \
    "$STAGING_DIR"

cp "$STAGING_DIR/appcast.xml" "$PROJECT_DIR/appcast.xml"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "Beta package ready:"
echo "  Tag:     $RELEASE_TAG"
echo "  ZIP:     $ARCHIVE_PATH"
echo "  DMG:     $DMG_PATH"
echo "  Appcast: $PROJECT_DIR/appcast.xml"
