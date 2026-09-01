#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_DIR="$PROJECT_DIR/dist/ContextInput.app"
DESTINATION="/Applications/ContextInput.app"

"$SCRIPT_DIR/build-app.sh"
ditto "$APP_DIR" "$DESTINATION"
open "$DESTINATION"
