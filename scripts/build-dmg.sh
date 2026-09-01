#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/ContextInput.app"
DMG_PATH="$DIST_DIR/ContextInput.dmg"
STAGING_DIR="$DIST_DIR/dmg-staging"

"$SCRIPT_DIR/build-app.sh"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/ContextInput.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname ContextInput -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING_DIR"

echo "$DMG_PATH"
