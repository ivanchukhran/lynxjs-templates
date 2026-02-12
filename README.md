# LynxJS Native Templates

Minimal native iOS and Android project templates for running LynxJS applications. Designed for both local development and CI/CD pipelines.

## Prerequisites

- For iOS:
  - macOS with Xcode 15+
  - CocoaPods (`gem install cocoapods`)
  - Fastlane (for CI/CD builds)
- For Android:
  - Android Studio with SDK (or just JDK 17+ for CI)
  - Gradle 8.x
  - Android SDK with `ANDROID_HOME` environment variable set:
    ```bash
    # macOS (add to ~/.zshrc or ~/.bashrc)
    export ANDROID_HOME="$HOME/Library/Android/sdk"
    export PATH="$ANDROID_HOME/platform-tools:$PATH"

    # Linux
    export ANDROID_HOME="$HOME/Android/Sdk"
    export PATH="$ANDROID_HOME/platform-tools:$PATH"
    ```
    Or the build script will auto-detect common SDK locations and create `local.properties`.

## Quick Start (Local)

```bash
# Clone template
git clone https://github.com/user/lynxjs-template.git MyApp
cd MyApp

# Configure project
./scripts/setup.sh --name MyApp --bundle-id com.example.myapp

# Copy your LynxJS bundle
cp /path/to/main.lynx.bundle ios/MyApp/Resources/
cp /path/to/main.lynx.bundle android/app/src/main/assets/

# Build iOS
cd ios/MyApp && pod install && cd ../..
./scripts/build-ios.sh --scheme MyApp

# Build Android
./scripts/build-android.sh --build-type release
```

## CLI Reference

### Setup Script

```bash
./scripts/setup.sh [options]

Options:
  --name, -n          App name (default: MyApp)
  --bundle-id, -b     Bundle/Package ID (default: com.example.myapp)
  --ios-team-id       Apple Developer Team ID
  --skip-git          Skip git initialization (for CI)
  --help, -h          Show help
```

### iOS Build Script

```bash
./scripts/build-ios.sh [options]

Options:
  --scheme            Xcode scheme name (auto-detected if not provided)
  --export-method     Export method:
                        app-store   - App Store release (requires Match)
                        ad-hoc      - Ad-hoc distribution (requires Match)
                        development - Development build (requires Match)
                        dev         - Automatic signing (no Match needed)
                        simulator   - Simulator build (no signing)
                        build-only  - Compile validation only
  --output            Output directory (default: ./build)
  --no-fastlane       Use xcodebuild instead of fastlane (fastlane is default)
```

### Android Build Script

```bash
./scripts/build-android.sh [options]

Options:
  --build-type        debug or release (default: release)
  --output-type       apk or bundle (default: apk)
  --output            Output directory (default: ./build)
  --no-fastlane       Use direct Gradle instead of fastlane (fastlane is default)
  --keystore          Path to keystore file (requires --no-fastlane)
  --keystore-pass     Keystore password
  --key-alias         Key alias
  --key-pass          Key password
```

## CI/CD Setup

### GitHub Actions

A sample workflow is included at `.github/workflows/build.yml`.

**Required Secrets:**

| Secret | Description |
|--------|-------------|
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_ID` | Apple ID email |
| `ITC_TEAM_ID` | App Store Connect Team ID |
| `MATCH_GIT_URL` | Git URL for Match certificates repo |
| `MATCH_PASSWORD` | Match encryption password |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Base64 encoded `username:token` |
| `ANDROID_KEYSTORE_BASE64` | Base64 encoded keystore file |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

**Trigger the workflow:**

```bash
gh workflow run build.yml \
  -f app_name=MyApp \
  -f bundle_id=com.example.myapp \
  -f lynx_bundle_url=https://example.com/main.lynx.bundle
```

### Fastlane (iOS)

The template includes fastlane configuration using Match for code signing.

**First-time setup (run locally once):**

```bash
cd ios/MyApp
bundle install

# Initialize Match (creates certificates in your git repo)
bundle exec fastlane match init
bundle exec fastlane match appstore
bundle exec fastlane match adhoc
```

**Build commands:**

```bash
# With Match certificates
bundle exec fastlane release    # App Store build
bundle exec fastlane adhoc      # Ad-hoc build
bundle exec fastlane build      # Development build
bundle exec fastlane beta       # Build and upload to TestFlight

# Without certificates
bundle exec fastlane simulator  # Simulator build (no signing)
bundle exec fastlane dev        # Automatic signing (no Match)
bundle exec fastlane build_only # Just validate compilation
```

### Fastlane (Android)

The template includes fastlane configuration for Android builds and Play Store deployment.

**Setup:**

```bash
cd android
bundle install
```

**Build commands:**

```bash
bundle exec fastlane build_debug    # Debug APK
bundle exec fastlane build_release  # Release APK
bundle exec fastlane build_bundle   # Release AAB
bundle exec fastlane run_tests      # Run unit tests
```

**Deploy to Play Store:**

```bash
# First, add your Google Play JSON key to android/fastlane/google-play-key.json
# Or set GOOGLE_PLAY_JSON_KEY environment variable

bundle exec fastlane internal       # Deploy to internal track
bundle exec fastlane beta           # Deploy to beta track
bundle exec fastlane production     # Deploy to production
```

## Project Structure

```
├── ios/
│   └── LynxTemplate/
│       ├── LynxTemplate/           # Swift source files
│       ├── Resources/              # Put main.lynx.bundle here
│       ├── fastlane/
│       │   ├── Fastfile            # Fastlane lanes
│       │   ├── Matchfile           # Match configuration
│       │   └── Appfile             # App identifiers
│       ├── Gemfile
│       └── Podfile
│
├── android/
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── java/com/lynxtemplate/
│   │   │   └── assets/             # Put main.lynx.bundle here
│   │   └── build.gradle.kts
│   ├── fastlane/
│   │   ├── Fastfile                # Fastlane lanes
│   │   └── Appfile                 # Package name config
│   ├── Gemfile
│   └── gradle/
│
├── scripts/
│   ├── setup.sh                    # Project configuration
│   ├── build-ios.sh                # iOS build script
│   └── build-android.sh            # Android build script
│
├── .github/
│   └── workflows/
│       └── build.yml               # GitHub Actions workflow
│
└── README.md
```

## Example: Full CI/CD Pipeline

```yaml
# In your LynxJS app repository
name: Build and Deploy

on:
  push:
    branches: [main]

jobs:
  build-lynx:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - run: pnpm install && pnpm build
      - uses: actions/upload-artifact@v4
        with:
          name: lynx-bundle
          path: dist/main.lynx.bundle

  build-native:
    needs: build-lynx
    uses: user/lynxjs-template/.github/workflows/build.yml@main
    with:
      app_name: MyApp
      bundle_id: com.example.myapp
    secrets: inherit
```

## License

MIT
