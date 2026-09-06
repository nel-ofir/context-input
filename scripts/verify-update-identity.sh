#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
SIGNING_IDENTITY=${SIGNING_IDENTITY:-ContextInput Beta Code Signing}
TEMPORARY_DIR=$(mktemp -d)
trap 'rm -rf "$TEMPORARY_DIR"' EXIT

VERSION=0.2.0 BUILD_NUMBER=1501 SIGNING_IDENTITY="$SIGNING_IDENTITY" \
    "$SCRIPT_DIR/build-app.sh" >/dev/null
ditto "$PROJECT_DIR/dist/ContextInput.app" "$TEMPORARY_DIR/ContextInput-v1.app"

VERSION=0.2.1 BUILD_NUMBER=1502 SIGNING_IDENTITY="$SIGNING_IDENTITY" \
    "$SCRIPT_DIR/build-app.sh" >/dev/null
ditto "$PROJECT_DIR/dist/ContextInput.app" "$TEMPORARY_DIR/ContextInput-v2.app"

requirement_v1=$(codesign -d -r- "$TEMPORARY_DIR/ContextInput-v1.app" 2>&1 | sed -n 's/^designated => //p')
requirement_v2=$(codesign -d -r- "$TEMPORARY_DIR/ContextInput-v2.app" 2>&1 | sed -n 's/^designated => //p')

if [[ -z "$requirement_v1" || "$requirement_v1" != "$requirement_v2" ]]; then
    echo "FAIL: release builds do not have the same designated requirement." >&2
    exit 1
fi

codesign --verify --deep --strict "$TEMPORARY_DIR/ContextInput-v1.app"
codesign --verify --deep --strict "$TEMPORARY_DIR/ContextInput-v2.app"
echo "PASS: both versions share one stable designated requirement."
echo "$requirement_v1"
