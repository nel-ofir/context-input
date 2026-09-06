#!/bin/zsh
set -euo pipefail
SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
SPARKLE_DIR=$("$SCRIPT_DIR/fetch-sparkle.sh")
mkdir -p "$PROJECT_DIR/.build/tests" "$PROJECT_DIR/.build/module-cache"
APP_SOURCES=("$PROJECT_DIR"/Sources/ContextInput/CI*.m)
clang -fobjc-arc -fmodules \
    -fmodules-cache-path="$PROJECT_DIR/.build/module-cache" \
    -mmacosx-version-min=13.0 -Wall -Wextra -Wpedantic -Werror \
    -I "$PROJECT_DIR/Sources/ContextInput" \
    -F "$SPARKLE_DIR" \
    "$PROJECT_DIR/Tests/SettingsSmokeTests.m" "${APP_SOURCES[@]}" \
    -framework AppKit -framework ApplicationServices -framework Carbon \
    -framework Foundation -framework NaturalLanguage -framework ServiceManagement \
    -framework Sparkle -Wl,-rpath,"$SPARKLE_DIR" \
    -o "$PROJECT_DIR/.build/tests/SettingsSmokeTests"
"$PROJECT_DIR/.build/tests/SettingsSmokeTests"
