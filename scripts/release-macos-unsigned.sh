#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCHEME="${SCHEME:-Hypnograph}"
CONFIGURATION="${CONFIGURATION:-Release}"
PROJECT_PATH="${PROJECT_PATH:-$REPO_ROOT/Hypnograph.xcodeproj}"
APP_NAME="${APP_NAME:-Hypnograph.app}"
VOLUME_NAME="${VOLUME_NAME:-Hypnograph}"

BUILD_ROOT="${BUILD_ROOT:-$REPO_ROOT/.build/release-unsigned}"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
ARCHIVE_PATH="$BUILD_ROOT/Hypnograph-unsigned.xcarchive"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"

for required_command in xcodebuild ditto hdiutil shasum codesign; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "error: Required command not found: $required_command" >&2
    exit 1
  fi
done

echo "Preparing build directories..."
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$DIST_DIR"

echo "Archiving $SCHEME ($CONFIGURATION) without code signing..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  clean archive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM=""

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: Expected app not found at $APP_PATH" >&2
  exit 1
fi

echo "Applying ad-hoc code signature for stable local identity..."
codesign --force --deep --sign - --timestamp=none "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

INFO_PLIST_PATH="$APP_PATH/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST_PATH" 2>/dev/null || true)"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST_PATH" 2>/dev/null || true)"

if [[ -z "$VERSION" ]]; then
  VERSION="0.0.0"
fi
if [[ -z "$BUILD" ]]; then
  BUILD="0"
fi

ARTIFACT_BASENAME="Hypnograph-${VERSION}-${BUILD}-macOS-unsigned"
DMG_PATH="$DIST_DIR/$ARTIFACT_BASENAME.dmg"
ZIP_PATH="$DIST_DIR/$ARTIFACT_BASENAME.zip"
CHECKSUM_PATH="$DIST_DIR/$ARTIFACT_BASENAME.sha256"

DMG_STAGING_ROOT="$BUILD_ROOT/dmg-staging"
rm -rf "$DMG_STAGING_ROOT"
mkdir -p "$DMG_STAGING_ROOT"

echo "Preparing DMG staging content..."
ditto "$APP_PATH" "$DMG_STAGING_ROOT/$APP_NAME"
ln -s /Applications "$DMG_STAGING_ROOT/Applications"

rm -f "$DMG_PATH" "$ZIP_PATH" "$CHECKSUM_PATH"

echo "Creating DMG..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_STAGING_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Creating ZIP..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Writing checksums..."
(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" >"$CHECKSUM_PATH"
  shasum -a 256 "$(basename "$ZIP_PATH")" >>"$CHECKSUM_PATH"
)

cat <<EOF
Done.

Artifacts:
- $DMG_PATH
- $ZIP_PATH
- $CHECKSUM_PATH

Install path for users:
1. Open DMG
2. Drag $APP_NAME into /Applications
3. First launch with right-click -> Open
EOF
