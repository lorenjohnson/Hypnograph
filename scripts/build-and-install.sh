#!/bin/bash
# Build and install Hypnograph and Divine to /Applications

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/Hypnograph.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build"
APPS_DIR="/Applications"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Building and installing Hypnograph apps...${NC}"
echo ""

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

build_and_install() {
    local scheme="$1"
    echo -e "${YELLOW}Building $scheme...${NC}"

    xcodebuild -project "$PROJECT" \
        -scheme "$scheme" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        -destination 'platform=macOS' \
        build \
        ONLY_ACTIVE_ARCH=NO \
        2>&1 | grep -E '(error:|warning:|Build Succeeded|BUILD FAILED)' || true

    # Find the built app
    APP_PATH=$(find "$BUILD_DIR/Build/Products/Release" -name "$scheme.app" -type d 2>/dev/null | head -1)

    if [ -z "$APP_PATH" ]; then
        echo -e "${RED}Failed to find $scheme.app${NC}"
        return 1
    fi

    echo -e "${GREEN}Built: $APP_PATH${NC}"

    # Remove old version if exists
    if [ -d "$APPS_DIR/$scheme.app" ]; then
        echo "Removing old $scheme.app from Applications..."
        rm -rf "$APPS_DIR/$scheme.app"
    fi

    # Copy to Applications
    echo "Installing $scheme.app to $APPS_DIR..."
    cp -R "$APP_PATH" "$APPS_DIR/"

    echo -e "${GREEN}✓ $scheme installed successfully${NC}"
    echo ""
}

# Build and install both apps
build_and_install "Hypnograph"
build_and_install "Divine"

echo -e "${GREEN}Done! Both apps installed to $APPS_DIR${NC}"
