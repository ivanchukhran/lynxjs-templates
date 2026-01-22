#!/bin/bash
set -e

# LynxJS Native Template Setup Script
# Usage: ./scripts/setup.sh [options]
#
# Options:
#   --name, -n          App name (default: MyApp)
#   --bundle-id, -b     Bundle/Package ID (default: com.example.myapp)
#   --ios-team-id       Apple Developer Team ID
#   --skip-git          Skip git initialization (useful for CI)
#   --help, -h          Show this help message

# Default values
APP_NAME="MyApp"
PACKAGE_ID="com.example.myapp"
TEAM_ID=""
SKIP_GIT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name|-n)
            APP_NAME="$2"
            shift 2
            ;;
        --bundle-id|-b)
            PACKAGE_ID="$2"
            shift 2
            ;;
        --ios-team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        --skip-git)
            SKIP_GIT=true
            shift
            ;;
        --help|-h)
            head -20 "$0" | tail -15
            exit 0
            ;;
        *)
            # Support positional args for backwards compatibility
            if [ -z "$APP_NAME" ] || [ "$APP_NAME" = "MyApp" ]; then
                APP_NAME="$1"
            elif [ -z "$PACKAGE_ID" ] || [ "$PACKAGE_ID" = "com.example.myapp" ]; then
                PACKAGE_ID="$1"
            elif [ -z "$TEAM_ID" ]; then
                TEAM_ID="$1"
            fi
            shift
            ;;
    esac
done

# Validate app name (alphanumeric, starting with letter)
if [[ ! "$APP_NAME" =~ ^[a-zA-Z][a-zA-Z0-9]*$ ]]; then
    echo "Error: App name must be alphanumeric and start with a letter"
    exit 1
fi

# Validate package ID
if [[ ! "$PACKAGE_ID" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$ ]]; then
    echo "Error: Package ID must be in reverse domain format (e.g., com.example.myapp)"
    exit 1
fi

echo "Setting up LynxJS native templates"
echo "  App name:   $APP_NAME"
echo "  Package ID: $PACKAGE_ID"
[ -n "$TEAM_ID" ] && echo "  Team ID:    $TEAM_ID"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

# Convert package ID to path (com.example.myapp -> com/example/myapp)
PACKAGE_PATH=$(echo "$PACKAGE_ID" | tr '.' '/')

# ============== iOS Setup ==============
echo ""
echo "Configuring iOS project..."

if [ -d "ios/LynxTemplate" ]; then
    mv ios/LynxTemplate/LynxTemplate.xcodeproj "ios/LynxTemplate/$APP_NAME.xcodeproj"
    mv ios/LynxTemplate/LynxTemplate "ios/LynxTemplate/$APP_NAME"
    mv "ios/LynxTemplate/$APP_NAME/LynxTemplate-Bridging-Header.h" "ios/LynxTemplate/$APP_NAME/$APP_NAME-Bridging-Header.h"
    mv "ios/LynxTemplate/$APP_NAME/LynxTemplateProvider.swift" "ios/LynxTemplate/$APP_NAME/${APP_NAME}Provider.swift"
    mv ios/LynxTemplate "ios/$APP_NAME"
fi

# Update iOS files
find ios -type f \( -name "*.pbxproj" -o -name "*.swift" -o -name "*.h" -o -name "Podfile" \) \
    -exec sed -i '' "s/LynxTemplate/$APP_NAME/g" {} \;

find ios -type f -name "*.pbxproj" \
    -exec sed -i '' "s/com\.lynxtemplate/$PACKAGE_ID/g" {} \;

if [ -n "$TEAM_ID" ]; then
    find ios -type f -name "*.pbxproj" \
        -exec sed -i '' "s/DEVELOPMENT_TEAM = \"\"/DEVELOPMENT_TEAM = $TEAM_ID/g" {} \;
fi

# Update fastlane files if they exist
if [ -d "ios/fastlane" ]; then
    sed -i '' "s/LynxTemplate/$APP_NAME/g" ios/fastlane/Fastfile 2>/dev/null || true
    sed -i '' "s/com\.lynxtemplate/$PACKAGE_ID/g" ios/fastlane/Fastfile 2>/dev/null || true
    sed -i '' "s/com\.lynxtemplate/$PACKAGE_ID/g" ios/fastlane/Matchfile 2>/dev/null || true
    [ -n "$TEAM_ID" ] && sed -i '' "s/TEAM_ID_PLACEHOLDER/$TEAM_ID/g" ios/fastlane/Matchfile 2>/dev/null || true
fi

echo "  iOS project configured: ios/$APP_NAME"

# ============== Android Setup ==============
echo ""
echo "Configuring Android project..."

mkdir -p "android/app/src/main/java/$PACKAGE_PATH"

for file in android/app/src/main/java/com/lynxtemplate/*.kt; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        if [ "$filename" = "LynxTemplateApp.kt" ]; then
            new_filename="${APP_NAME}App.kt"
        else
            new_filename="$filename"
        fi
        sed -e "s/package com\.lynxtemplate/package $PACKAGE_ID/g" \
            -e "s/LynxTemplateApp/${APP_NAME}App/g" \
            "$file" > "android/app/src/main/java/$PACKAGE_PATH/$new_filename"
    fi
done

rm -rf android/app/src/main/java/com/lynxtemplate

sed -i '' -e "s/com\.lynxtemplate/$PACKAGE_ID/g" \
    -e "s/LynxTemplateApp/${APP_NAME}App/g" \
    android/app/src/main/AndroidManifest.xml

sed -i '' "s/com\.lynxtemplate/$PACKAGE_ID/g" android/app/build.gradle.kts
sed -i '' "s/LynxTemplate/$APP_NAME/g" android/settings.gradle.kts
sed -i '' "s/LynxTemplate/$APP_NAME/g" android/app/src/main/res/values/strings.xml

sed -i '' "s/Theme\.LynxTemplate/Theme.$APP_NAME/g" android/app/src/main/AndroidManifest.xml
sed -i '' "s/Theme\.LynxTemplate/Theme.$APP_NAME/g" android/app/src/main/res/values/themes.xml
sed -i '' "s/Theme\.LynxTemplate/Theme.$APP_NAME/g" android/app/src/main/res/values-night/themes.xml

echo "  Android project configured: android/"

# ============== Git ==============
if [ "$SKIP_GIT" = false ]; then
    echo ""
    echo "Reinitializing git repository..."
    rm -rf .git
    git init
    git add .
    git commit -m "Initial commit: $APP_NAME"
fi

echo ""
echo "============================================"
echo "Setup complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Copy your LynxJS bundle:"
echo "   iOS:     ios/$APP_NAME/Resources/main.lynx.bundle"
echo "   Android: android/app/src/main/assets/main.lynx.bundle"
echo ""
echo "2. Build:"
echo "   iOS:     ./scripts/build-ios.sh --scheme $APP_NAME"
echo "   Android: ./scripts/build-android.sh"
echo ""
