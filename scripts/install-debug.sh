#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
BUILT_APP="$PROJECT_DIR/dist/ContextInput.app"
DEBUG_APP="$PROJECT_DIR/.build/ContextInputDebug.app"
DESTINATION="/Applications/ContextInputDebug.app"

SIGNING_IDENTITY=- "$SCRIPT_DIR/build-app.sh"

rm -rf "$DEBUG_APP"
ditto "$BUILT_APP" "$DEBUG_APP"
plutil -replace CFBundleIdentifier -string com.contextinput.mac.debug \
    "$DEBUG_APP/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "ContextInput Debug" \
    "$DEBUG_APP/Contents/Info.plist"
plutil -replace CFBundleName -string "ContextInput Debug" \
    "$DEBUG_APP/Contents/Info.plist"
for update_key in \
    SUFeedURL \
    SUEnableAutomaticChecks \
    SUAllowsAutomaticUpdates \
    SUAutomaticallyUpdate; do
    plutil -remove "$update_key" "$DEBUG_APP/Contents/Info.plist" 2>/dev/null || true
done
codesign --force --deep --sign - "$DEBUG_APP"
codesign --verify --deep --strict "$DEBUG_APP"

pkill -x ContextInput 2>/dev/null || true
rm -rf "$DESTINATION"
ditto "$DEBUG_APP" "$DESTINATION"
open "$DESTINATION"

echo "Installed ContextInput Debug separately from the signed beta."
echo "Enable it in System Settings > Privacy & Security > Accessibility."
