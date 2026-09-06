#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
VERSION=${VERSION:-0.2.2}
BUILD_NUMBER=${BUILD_NUMBER:-18}
BETA_NUMBER=${BETA_NUMBER:-3}
RELEASE_TAG=${RELEASE_TAG:-v$VERSION-beta.$BETA_NUMBER}
REPOSITORY=nel-ofir/context-input
ARCHIVE_PATH="$PROJECT_DIR/dist/releases/ContextInput-$VERSION-arm64.zip"
DMG_PATH="$PROJECT_DIR/dist/releases/ContextInput-$VERSION-arm64.dmg"
RELEASE_NOTES="$PROJECT_DIR/packaging/release-notes/$VERSION.md"

if ! command -v gh >/dev/null; then
    echo "GitHub CLI is required. Install it with: brew install gh" >&2
    exit 1
fi

github_user=$(gh api user --jq .login)
if [[ "$github_user" != "nel-ofir" ]]; then
    echo "GitHub CLI is authenticated as $github_user, not nel-ofir." >&2
    exit 1
fi

if [[ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]]; then
    echo "Commit or stash existing changes before publishing a beta." >&2
    exit 1
fi

VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" BETA_NUMBER="$BETA_NUMBER" \
    "$SCRIPT_DIR/package-beta.sh"

unexpected_changes=$(git -C "$PROJECT_DIR" status --porcelain | grep -v '^ M appcast.xml$' || true)
if [[ -n "$unexpected_changes" ]]; then
    echo "Unexpected tracked changes after packaging:" >&2
    echo "$unexpected_changes" >&2
    exit 1
fi

gh release create "$RELEASE_TAG" "$ARCHIVE_PATH" "$DMG_PATH" \
    --repo "$REPOSITORY" \
    --target main \
    --draft \
    --prerelease \
    --title "ContextInput $VERSION beta $BETA_NUMBER" \
    --notes-file "$RELEASE_NOTES"

git -C "$PROJECT_DIR" add appcast.xml
git -C "$PROJECT_DIR" commit -m "Publish ContextInput $VERSION beta $BETA_NUMBER update feed"
git -C "$PROJECT_DIR" push origin main

gh release edit "$RELEASE_TAG" --repo "$REPOSITORY" --draft=false --prerelease
echo "Published https://github.com/$REPOSITORY/releases/tag/$RELEASE_TAG"
