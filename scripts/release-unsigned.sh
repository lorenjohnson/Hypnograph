#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_SCRIPT="${BUILD_SCRIPT:-$SCRIPT_DIR/build-unsigned.sh}"
SCHEME="${SCHEME:-Hypnograph}"
TARGET_NAME="${TARGET_NAME:-Hypnograph}"
CONFIGURATION="${CONFIGURATION:-Release}"
PROJECT_PATH="${PROJECT_PATH:-$REPO_ROOT/Hypnograph.xcodeproj}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
REPO_SLUG="${REPO_SLUG:-${GITHUB_REPOSITORY:-lorenjohnson/Hypnograph}}"

DRAFT=0
SKIP_BUILD=0
NOTES_FILE=""
TAG=""
TITLE=""
PREVIOUS_TAG=""

usage() {
  cat <<'EOF'
Usage: ./scripts/release-unsigned.sh [options]

Builds the unsigned release artifacts and publishes them to a GitHub prerelease.

Options:
  --skip-build           Publish existing artifacts from dist/ without rebuilding
  --draft                Create or update the GitHub release as a draft
  --notes-file PATH      Use the given release notes file
  --previous-tag TAG     Override the previous tag used for default notes
  --tag TAG              Override the GitHub release tag
  --title TITLE          Override the GitHub release title
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --draft)
      DRAFT=1
      shift
      ;;
    --notes-file)
      NOTES_FILE="${2:-}"
      shift 2
      ;;
    --previous-tag)
      PREVIOUS_TAG="${2:-}"
      shift 2
      ;;
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ $SKIP_BUILD -eq 0 ]]; then
  "$BUILD_SCRIPT"
fi

for required_command in gh git xcodebuild; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "error: Required command not found: $required_command" >&2
    exit 1
  fi
done

if ! gh auth status >/dev/null 2>&1; then
  echo "error: gh is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

BUILD_SETTINGS="$(xcodebuild -project "$PROJECT_PATH" -target "$TARGET_NAME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null)"
VERSION="$(awk -F' = ' '/MARKETING_VERSION = / { print $2; exit }' <<<"$BUILD_SETTINGS")"
BUILD="$(awk -F' = ' '/CURRENT_PROJECT_VERSION = / { print $2; exit }' <<<"$BUILD_SETTINGS")"

if [[ -z "$VERSION" || -z "$BUILD" ]]; then
  echo "error: Could not determine MARKETING_VERSION/CURRENT_PROJECT_VERSION from Xcode build settings." >&2
  exit 1
fi

ARTIFACT_BASENAME="Hypnograph-${VERSION}-${BUILD}-macOS-unsigned"
DMG_PATH="$DIST_DIR/$ARTIFACT_BASENAME.dmg"
ZIP_PATH="$DIST_DIR/$ARTIFACT_BASENAME.zip"
CHECKSUM_PATH="$DIST_DIR/$ARTIFACT_BASENAME.sha256"

for artifact in "$DMG_PATH" "$ZIP_PATH" "$CHECKSUM_PATH"; do
  if [[ ! -f "$artifact" ]]; then
    echo "error: Expected artifact not found: $artifact" >&2
    exit 1
  fi
done

TAG="${TAG:-v${VERSION}-beta.${BUILD}}"
TITLE="${TITLE:-Hypnograph ${VERSION} beta ${BUILD}}"
TARGET_SHA="$(git rev-parse HEAD)"

TEMP_NOTES_FILE=""
if [[ -z "$NOTES_FILE" ]]; then
  if [[ -z "$PREVIOUS_TAG" ]]; then
    PREVIOUS_TAG="$(git tag --sort=-creatordate --list 'v*' | grep -Fvx "$TAG" | head -n1 || true)"
  fi
  TEMP_NOTES_FILE="$(mktemp)"
  NOTES_FILE="$TEMP_NOTES_FILE"
  {
    echo "Unsigned macOS beta release."
    echo
    echo "Version: $VERSION"
    echo "Build: $BUILD"
    echo
    if [[ -n "$PREVIOUS_TAG" ]]; then
      echo "Changes since $PREVIOUS_TAG:"
      if ! git log --format='- %s' "${PREVIOUS_TAG}..HEAD"; then
        echo "- Unable to generate commit summary from ${PREVIOUS_TAG}..HEAD"
      fi
      echo
    else
      echo "Changes in this release:"
      if ! git log --format='- %s'; then
        echo "- Unable to generate commit summary from git history"
      fi
      echo
    fi
    echo "Install:"
    echo "1. Download the DMG."
    echo "2. Drag Hypnograph.app into Applications."
    echo "3. On first launch, right-click the app and choose Open."
  } >"$NOTES_FILE"
fi

cleanup() {
  if [[ -n "$TEMP_NOTES_FILE" && -f "$TEMP_NOTES_FILE" ]]; then
    rm -f "$TEMP_NOTES_FILE"
  fi
}
trap cleanup EXIT

if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  echo "Updating existing GitHub release $TAG..."
  gh release upload "$TAG" "$DMG_PATH" "$ZIP_PATH" "$CHECKSUM_PATH" --repo "$REPO_SLUG" --clobber
  gh release edit "$TAG" --repo "$REPO_SLUG" --title "$TITLE" --notes-file "$NOTES_FILE" --prerelease
  if [[ $DRAFT -eq 1 ]]; then
    gh release edit "$TAG" --repo "$REPO_SLUG" --draft
  fi
else
  echo "Creating GitHub release $TAG..."
  CREATE_ARGS=(
    release create "$TAG"
    "$DMG_PATH"
    "$ZIP_PATH"
    "$CHECKSUM_PATH"
    --repo "$REPO_SLUG"
    --target "$TARGET_SHA"
    --title "$TITLE"
    --notes-file "$NOTES_FILE"
    --prerelease
  )
  if [[ $DRAFT -eq 1 ]]; then
    CREATE_ARGS+=(--draft)
  fi
  gh "${CREATE_ARGS[@]}"
fi

RELEASE_URL="https://github.com/$REPO_SLUG/releases/tag/$TAG"

cat <<EOF
Done.

GitHub release:
- $RELEASE_URL

Artifacts:
- $DMG_PATH
- $ZIP_PATH
- $CHECKSUM_PATH
EOF
