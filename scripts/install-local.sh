#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_DIR="$PROJECT_DIR/dist/ContextInput.app"
DESTINATION="/Applications/ContextInput.app"

"$SCRIPT_DIR/build-app.sh"
pkill -x ContextInput 2>/dev/null || true
for attempt in {1..20}; do
    if ! pgrep -x ContextInput >/dev/null; then
        break
    fi
    sleep 0.1
done
rm -rf "$DESTINATION"
ditto "$APP_DIR" "$DESTINATION"
open "$DESTINATION"
