#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
SPARKLE_VERSION=2.9.6
SPARKLE_SHA256=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
DEPENDENCY_DIR="$PROJECT_DIR/.build/dependencies"
ARCHIVE_PATH="$DEPENDENCY_DIR/Sparkle-$SPARKLE_VERSION.tar.xz"
EXTRACTED_DIR="$DEPENDENCY_DIR/Sparkle-$SPARKLE_VERSION"
DOWNLOAD_URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"

mkdir -p "$DEPENDENCY_DIR"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
    curl -L --fail --silent --show-error "$DOWNLOAD_URL" -o "$ARCHIVE_PATH"
fi

actual_sha=$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')
if [[ "$actual_sha" != "$SPARKLE_SHA256" ]]; then
    echo "Sparkle archive checksum mismatch." >&2
    echo "Expected: $SPARKLE_SHA256" >&2
    echo "Actual:   $actual_sha" >&2
    exit 1
fi

if [[ ! -d "$EXTRACTED_DIR/Sparkle.framework" ]]; then
    rm -rf "$EXTRACTED_DIR"
    mkdir -p "$EXTRACTED_DIR"
    tar -xf "$ARCHIVE_PATH" -C "$EXTRACTED_DIR"
fi

echo "$EXTRACTED_DIR"
