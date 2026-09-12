#!/bin/zsh
set -euo pipefail
SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
mkdir -p "$PROJECT_DIR/.build/tests" "$PROJECT_DIR/.build/module-cache"
clang -fobjc-arc -fmodules \
    -fmodules-cache-path="$PROJECT_DIR/.build/module-cache" \
    -mmacosx-version-min=13.0 -Wall -Wextra -Wpedantic -Werror \
    -I "$PROJECT_DIR/Sources/ContextInput" \
    "$PROJECT_DIR/Tests/ContextReaderTests.m" \
    "$PROJECT_DIR/Sources/ContextInput/CIApplicationCapabilities.m" \
    "$PROJECT_DIR/Sources/ContextInput/CIContextGeometry.m" \
    "$PROJECT_DIR/Sources/ContextInput/CIContextTextSanitizer.m" \
    "$PROJECT_DIR/Sources/ContextInput/CIDraftSanitizer.m" \
    "$PROJECT_DIR/Sources/ContextInput/CIModels.m" \
    "$PROJECT_DIR/Sources/ContextInput/CILanguageClassifier.m" \
    -framework AppKit -framework ApplicationServices -framework NaturalLanguage \
    -o "$PROJECT_DIR/.build/tests/ContextReaderTests"
"$PROJECT_DIR/.build/tests/ContextReaderTests"
