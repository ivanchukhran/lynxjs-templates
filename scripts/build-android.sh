#!/bin/bash
set -e

# Build Android app for distribution
# Usage: ./scripts/build-android.sh [options]
#
# Options:
#   --build-type      Build type: debug, release (default: release)
#   --output-type     Output type: apk, bundle (default: apk)
#   --output          Output directory (default: ./build)
#   --no-fastlane     Use direct Gradle instead of fastlane
#   --keystore        Path to keystore file (for release builds, requires --no-fastlane)
#   --keystore-pass   Keystore password (or use KEYSTORE_PASSWORD env var)
#   --key-alias       Key alias (or use KEY_ALIAS env var)
#   --key-pass        Key password (or use KEY_PASSWORD env var)
#   --help, -h        Show this help

BUILD_TYPE="release"
OUTPUT_TYPE="apk"
OUTPUT_DIR="./build"
KEYSTORE_PATH=""
KEYSTORE_PASS="${KEYSTORE_PASSWORD:-}"
KEY_ALIAS="${KEY_ALIAS:-}"
KEY_PASS="${KEY_PASSWORD:-}"
USE_FASTLANE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --build-type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        --output-type)
            OUTPUT_TYPE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --keystore)
            KEYSTORE_PATH="$2"
            shift 2
            ;;
        --keystore-pass)
            KEYSTORE_PASS="$2"
            shift 2
            ;;
        --key-alias)
            KEY_ALIAS="$2"
            shift 2
            ;;
        --key-pass)
            KEY_PASS="$2"
            shift 2
            ;;
        --no-fastlane)
            USE_FASTLANE=false
            shift
            ;;
        --help|-h)
            head -20 "$0" | tail -17
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Building Android app"
echo "Build type: $BUILD_TYPE"
echo "Output type: $OUTPUT_TYPE"
[ "$USE_FASTLANE" = true ] && echo "Using: fastlane"

cd "$ROOT_DIR/android"
mkdir -p "$ROOT_DIR/$OUTPUT_DIR"

# Check for Android SDK
if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
    # Try common locations
    for sdk_path in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk" "/usr/local/share/android-sdk"; do
        if [ -d "$sdk_path" ]; then
            export ANDROID_HOME="$sdk_path"
            echo "Auto-detected Android SDK: $ANDROID_HOME"
            break
        fi
    done
fi

# Create local.properties if SDK found but file missing
if [ -n "$ANDROID_HOME" ] && [ ! -f "local.properties" ]; then
    echo "sdk.dir=$ANDROID_HOME" > local.properties
    echo "Created local.properties with SDK path"
fi

# Fail with helpful message if SDK not found
if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ] && [ ! -f "local.properties" ]; then
    echo "Error: Android SDK not found."
    echo ""
    echo "Please do one of the following:"
    echo "  1. Set ANDROID_HOME environment variable:"
    echo "     export ANDROID_HOME=~/Library/Android/sdk"
    echo ""
    echo "  2. Install Android Studio (SDK installs to ~/Library/Android/sdk)"
    echo ""
    echo "  3. Create android/local.properties with:"
    echo "     sdk.dir=/path/to/your/android/sdk"
    exit 1
fi

# Determine output extension
if [ "$OUTPUT_TYPE" = "bundle" ]; then
    OUTPUT_EXT="aab"
else
    OUTPUT_EXT="apk"
fi

# Build using fastlane or direct Gradle
# if [ "$USE_FASTLANE" = true ]; then
# Ensure bundle is installed
if [ -f "Gemfile" ]; then
    bundle check || bundle install
fi

# Determine fastlane lane
if [ "$OUTPUT_TYPE" = "bundle" ]; then
    FASTLANE_LANE="build_bundle"
elif [ "$BUILD_TYPE" = "release" ]; then
    FASTLANE_LANE="build_release"
else
    FASTLANE_LANE="build_debug"
fi

echo "Running fastlane $FASTLANE_LANE..."
bundle exec fastlane "$FASTLANE_LANE"
# else
#     # Determine gradle task
#     if [ "$OUTPUT_TYPE" = "bundle" ]; then
#         if [ "$BUILD_TYPE" = "release" ]; then
#             GRADLE_TASK="bundleRelease"
#         else
#             GRADLE_TASK="bundleDebug"
#         fi
#     else
#         if [ "$BUILD_TYPE" = "release" ]; then
#             GRADLE_TASK="assembleRelease"
#         else
#             GRADLE_TASK="assembleDebug"
#         fi
#     fi

#     # Build with signing if keystore provided
#     if [ -n "$KEYSTORE_PATH" ] && [ "$BUILD_TYPE" = "release" ]; then
#         echo "Building with signing..."
#         ./gradlew "$GRADLE_TASK" \
#             -Pandroid.injected.signing.store.file="$KEYSTORE_PATH" \
#             -Pandroid.injected.signing.store.password="$KEYSTORE_PASS" \
#             -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
#             -Pandroid.injected.signing.key.password="$KEY_PASS"
#     else
#         ./gradlew "$GRADLE_TASK"
#     fi
# fi

# Copy output
if [ "$OUTPUT_TYPE" = "bundle" ]; then
    OUTPUT_FILE=$(find app/build/outputs/bundle -name "*.$OUTPUT_EXT" | head -1)
else
    OUTPUT_FILE=$(find app/build/outputs/apk -name "*.$OUTPUT_EXT" | head -1)
fi

if [ -n "$OUTPUT_FILE" ]; then
    cp "$OUTPUT_FILE" "$ROOT_DIR/$OUTPUT_DIR/"
    echo ""
    echo "Build complete! Output: $ROOT_DIR/$OUTPUT_DIR/$(basename $OUTPUT_FILE)"
else
    echo "Warning: Could not find output file"
fi

ls -la "$ROOT_DIR/$OUTPUT_DIR"
