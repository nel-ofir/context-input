#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_DIR/.build/tests"
MODULE_CACHE="$PROJECT_DIR/.build/module-cache"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"
clang \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$MODULE_CACHE" \
    -mmacosx-version-min=13.0 \
    -Wall -Wextra -Wpedantic -Werror \
    -I "$PROJECT_DIR/Sources/ContextInput" \
    "$PROJECT_DIR/Tests/ClassifierTests.m" \
    "$PROJECT_DIR/Sources/ContextInput/CIContextTextSanitizer.m" \
    "$PROJECT_DIR/Sources/ContextInput/CIModels.m" \
    "$PROJECT_DIR/Sources/ContextInput/CIDraftSanitizer.m" \
    "$PROJECT_DIR/Sources/ContextInput/CILanguageClassifier.m" \
    -framework Foundation \
    -framework NaturalLanguage \
    -o "$BUILD_DIR/ClassifierTests"

"$BUILD_DIR/ClassifierTests"

clang \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$MODULE_CACHE" \
    -mmacosx-version-min=13.0 \
    -Wall -Wextra -Wpedantic -Werror \
    -I "$PROJECT_DIR/Sources/ContextInput" \
    "$PROJECT_DIR/Tests/SystemSmokeTests.m" \
    "$PROJECT_DIR/Sources/ContextInput/CIModels.m" \
    "$PROJECT_DIR/Sources/ContextInput/CIInputSourceManager.m" \
    -framework Foundation \
    -framework Carbon \
    -o "$BUILD_DIR/SystemSmokeTests"

"$BUILD_DIR/SystemSmokeTests"
