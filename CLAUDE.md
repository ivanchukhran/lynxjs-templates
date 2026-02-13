# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LynxJS Native Templates - minimal iOS and Android project templates for running LynxJS applications. Designed for both local development and CI/CD pipelines.

## Common Commands

### Initial Setup (Required Before Building)
```bash
./scripts/setup.sh --name MyApp --bundle-id com.example.myapp [--ios-team-id TEAM_ID] [--skip-git]
```
This renames the template, configures identifiers, and generates platform-specific source trees.

### iOS Development
```bash
cd ios/<AppName>
bundle install                    # Install Ruby dependencies (fastlane, cocoapods)
pod install                       # Install CocoaPods dependencies
open <AppName>.xcworkspace        # Open in Xcode
```

Build iOS:
```bash
./scripts/build-ios.sh --export-method simulator             # No signing required
./scripts/build-ios.sh --export-method dev                   # Automatic signing (no Match)
./scripts/build-ios.sh --export-method build-only            # Just validate compilation
./scripts/build-ios.sh --export-method ad-hoc                # Ad-hoc (requires Match)
./scripts/build-ios.sh --no-fastlane --export-method ad-hoc  # Use xcodebuild directly
```

### Android Development
```bash
cd android
./gradlew assembleDebug           # Debug APK
./gradlew assembleRelease         # Release APK
./gradlew bundleRelease           # AAB for Play Store
./gradlew test                    # Run unit tests
./gradlew connectedAndroidTest    # Run instrumented tests
```

Build Android via script:
```bash
./scripts/build-android.sh --build-type release --output-type apk
./scripts/build-android.sh --no-fastlane --build-type release  # Use Gradle directly
./scripts/build-android.sh --output-type bundle                 # AAB via fastlane
```

Fastlane lanes (from android/):
```bash
bundle exec fastlane build_debug    # Debug APK
bundle exec fastlane build_release  # Release APK
bundle exec fastlane build_bundle   # Release AAB
bundle exec fastlane run_tests      # Run tests
bundle exec fastlane internal       # Deploy to Play Store internal track
bundle exec fastlane beta           # Deploy to Play Store beta track
```

## Architecture

### LynxJS Integration
- **iOS**: `LynxTemplateProvider` (Swift) loads `.lynx.bundle` files from app bundle resources
- **Android**: `TemplateProvider` (Kotlin) loads bundles from assets directory
- Both platforms initialize `LynxEnv` and services (Image, HTTP, Log) at app startup

### Platform Structure
```
ios/<AppName>/
  ├── <AppName>/           # Swift source (AppDelegate, ViewController, SceneDelegate)
  ├── Resources/           # Place main.lynx.bundle here
  ├── fastlane/            # Build lanes (release, adhoc, beta)
  └── Podfile              # Lynx 3.6.0, SDWebImage, XElement

android/
  ├── app/src/main/
  │   ├── java/.../        # Kotlin source (Application, MainActivity, TemplateProvider)
  │   └── assets/          # Place main.lynx.bundle here
  ├── fastlane/            # Build lanes (debug, release, bundle, internal, beta)
  ├── Gemfile              # Ruby dependencies (fastlane)
  └── gradle/libs.versions.toml  # Version catalog (Lynx 3.6.0, Fresco, OkHttp)
```

### Build Configuration
- **iOS**: CocoaPods + Fastlane, iOS 13.0+, manual code signing
- **Android**: Gradle 9.1 with Kotlin DSL + Fastlane, SDK 24-36, Java 11

### CI/CD (GitHub Actions)
Workflow at `.github/workflows/build.yml` runs parallel iOS (macOS) and Android (Ubuntu) builds. Requires secrets for code signing (Match for iOS, keystore for Android).

## Key Files
- `scripts/setup.sh` - Project customization (must run before first build)
- `scripts/build-ios.sh` - iOS build automation with xcodebuild/fastlane
- `scripts/build-android.sh` - Android build automation with Gradle/fastlane
- `android/fastlane/Fastfile` - Android fastlane lanes (debug, release, bundle, deploy)
- `android/fastlane/Appfile` - Android package name and Play Store credentials
- `mise.toml` - Tool versions (Gradle 9.1, Java latest)
