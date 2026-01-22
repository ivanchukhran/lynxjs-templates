#!/bin/bash
set -e

# Build iOS app for distribution
# Usage: ./scripts/build-ios.sh [options]
#
# Options:
#   --scheme          Xcode scheme name (required)
#   --export-method   Export method: app-store, ad-hoc, development (default: app-store)
#   --output          Output directory (default: ./build)
#   --use-fastlane    Use fastlane instead of xcodebuild
#   --help, -h        Show this help

SCHEME=""
EXPORT_METHOD="app-store"
OUTPUT_DIR="./build"
USE_FASTLANE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --scheme)
            SCHEME="$2"
            shift 2
            ;;
        --export-method)
            EXPORT_METHOD="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --use-fastlane)
            USE_FASTLANE=true
            shift
            ;;
        --help|-h)
            head -15 "$0" | tail -12
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Auto-detect scheme if not provided
if [ -z "$SCHEME" ]; then
    SCHEME=$(find "$ROOT_DIR/ios" -name "*.xcworkspace" -maxdepth 2 | head -1 | xargs basename | sed 's/.xcworkspace//')
    if [ -z "$SCHEME" ]; then
        SCHEME=$(find "$ROOT_DIR/ios" -name "*.xcodeproj" -maxdepth 2 | head -1 | xargs basename | sed 's/.xcodeproj//')
    fi
fi

if [ -z "$SCHEME" ]; then
    echo "Error: Could not detect scheme. Use --scheme to specify."
    exit 1
fi

echo "Building iOS app: $SCHEME"
echo "Export method: $EXPORT_METHOD"

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"

# Find workspace or project
WORKSPACE=$(find "ios" -name "*.xcworkspace" -maxdepth 2 | head -1)
PROJECT=$(find "ios" -name "*.xcodeproj" -maxdepth 2 | head -1)

if [ -z "$WORKSPACE" ] && [ -z "$PROJECT" ]; then
    echo "Error: No Xcode workspace or project found"
    exit 1
fi

# Install pods if needed
if [ -f "ios/$SCHEME/Podfile" ] && [ ! -d "ios/$SCHEME/Pods" ]; then
    echo "Installing CocoaPods..."
    cd "ios/$SCHEME"
    pod install
    cd "$ROOT_DIR"
    WORKSPACE="ios/$SCHEME/$SCHEME.xcworkspace"
fi

if [ "$USE_FASTLANE" = true ]; then
    echo "Building with fastlane..."
    cd "ios/$SCHEME"

    case $EXPORT_METHOD in
        app-store)
            bundle exec fastlane release
            ;;
        ad-hoc)
            bundle exec fastlane adhoc
            ;;
        *)
            bundle exec fastlane build
            ;;
    esac

    # Copy artifacts
    cp -r fastlane/output/* "$ROOT_DIR/$OUTPUT_DIR/" 2>/dev/null || true
else
    echo "Building with xcodebuild..."

    ARCHIVE_PATH="$OUTPUT_DIR/$SCHEME.xcarchive"

    # Determine build target
    if [ -n "$WORKSPACE" ]; then
        BUILD_TARGET="-workspace $WORKSPACE"
    else
        BUILD_TARGET="-project $PROJECT"
    fi

    # Archive
    xcodebuild \
        $BUILD_TARGET \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=iOS" \
        archive \
        CODE_SIGN_STYLE=Manual \
        | xcpretty || xcodebuild \
        $BUILD_TARGET \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=iOS" \
        archive

    # Create export options plist
    EXPORT_OPTIONS="$OUTPUT_DIR/ExportOptions.plist"
    cat > "$EXPORT_OPTIONS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>$EXPORT_METHOD</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
EOF

    # Export IPA
    xcodebuild \
        -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$OUTPUT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS"
fi

echo ""
echo "Build complete! Output: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
