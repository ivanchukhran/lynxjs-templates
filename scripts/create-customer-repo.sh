#!/bin/bash
set -e

# Customer Repo Provisioning Script
# Creates a new per-customer repo that calls the template's reusable workflow.
#
# Usage: ./scripts/create-customer-repo.sh [options]
#
# Options:
#   --org, -o           GitHub organization or username (required)
#   --customer, -c      Customer name (required)
#   --app-name, -n      App name — used for builds (required)
#   --bundle-id, -b     Bundle/Package ID (required)
#   --template-ref      Template repo branch/tag to reference (default: master)
#   --help, -h          Show this help message
#
# The repo will be created as <org>/<customer>-<app-name> (lowercased).
# Example: --org mycompany --customer acme --app-name ShopApp → mycompany/acme-shopapp

# Default values
ORG=""
CUSTOMER=""
APP_NAME=""
BUNDLE_ID=""
TEMPLATE_REF="master"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --org|-o)
            ORG="$2"
            shift 2
            ;;
        --customer|-c)
            CUSTOMER="$2"
            shift 2
            ;;
        --app-name|-n)
            APP_NAME="$2"
            shift 2
            ;;
        --bundle-id|-b)
            BUNDLE_ID="$2"
            shift 2
            ;;
        --template-ref)
            TEMPLATE_REF="$2"
            shift 2
            ;;
        --help|-h)
            head -17 "$0" | tail -14
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$ORG" ] || [ -z "$CUSTOMER" ] || [ -z "$APP_NAME" ] || [ -z "$BUNDLE_ID" ]; then
    echo "Error: Missing required arguments"
    echo "Usage: ./scripts/create-customer-repo.sh --org <org> --customer <name> --app-name <name> --bundle-id <id>"
    exit 1
fi

# Validate customer name (lowercase alphanumeric + hyphens)
if [[ ! "$CUSTOMER" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "Error: Customer name must be lowercase alphanumeric with hyphens (e.g. acme-corp)"
    exit 1
fi

# Validate app name (alphanumeric, starting with letter)
if [[ ! "$APP_NAME" =~ ^[a-zA-Z][a-zA-Z0-9]*$ ]]; then
    echo "Error: App name must be alphanumeric and start with a letter"
    exit 1
fi

# Validate bundle ID
if [[ ! "$BUNDLE_ID" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$ ]]; then
    echo "Error: Bundle ID must be in reverse domain format (e.g. com.example.myapp)"
    exit 1
fi

# Check gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is required. Install it from https://cli.github.com"
    exit 1
fi

# Check gh is authenticated
if ! gh auth status &> /dev/null; then
    echo "Error: GitHub CLI is not authenticated. Run 'gh auth login' first."
    exit 1
fi

# Derive repo name: <customer>-<appname> (lowercased)
APP_NAME_LOWER=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')
REPO_NAME="${CUSTOMER}-${APP_NAME_LOWER}"
REPO_FULL="${ORG}/${REPO_NAME}"

echo "Provisioning customer repo"
echo "  Organization: $ORG"
echo "  Customer:     $CUSTOMER"
echo "  Repo:         $REPO_FULL"
echo "  App name:     $APP_NAME"
echo "  Bundle ID:    $BUNDLE_ID"
echo "  Template ref: $TEMPLATE_REF"
echo ""

# Get script directory for template access
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="$ROOT_DIR/templates/customer-repo"

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "Error: Template directory not found at $TEMPLATE_DIR"
    exit 1
fi

# Create the repo
echo "Creating private repo ${REPO_FULL}..."
gh repo create "$REPO_FULL" --private --description "Build pipeline for ${APP_NAME}" || {
    echo "Error: Failed to create repo. It may already exist."
    exit 1
}

# Clone into temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Cloning repo..."
gh repo clone "$REPO_FULL" "$TMPDIR/repo"

# Copy native code from template
echo "Copying native project files..."
cp -R "$ROOT_DIR/ios" "$TMPDIR/repo/ios"
cp -R "$ROOT_DIR/android" "$TMPDIR/repo/android"
cp -R "$ROOT_DIR/scripts" "$TMPDIR/repo/scripts"

# Run setup.sh inside the customer repo
echo "Configuring project for ${APP_NAME}..."
cd "$TMPDIR/repo"
./scripts/setup.sh \
    --name "$APP_NAME" \
    --bundle-id "$BUNDLE_ID" \
    --skip-git

# Generate workflow and config from templates
echo "Generating CI files..."
find "$TEMPLATE_DIR" -name "*.tmpl" | while read -r tmpl_file; do
    # Get relative path and strip .tmpl suffix
    rel_path="${tmpl_file#$TEMPLATE_DIR/}"
    target_path="${rel_path%.tmpl}"

    # Create parent directory
    mkdir -p "$(dirname "$target_path")"

    # Copy and replace placeholders
    sed -e "s/__ORG__/$ORG/g" \
        -e "s/__APP_NAME__/$APP_NAME/g" \
        -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
        -e "s/__TEMPLATE_REF__/$TEMPLATE_REF/g" \
        "$tmpl_file" > "$target_path"

    echo "  Created: $target_path"
done

# Commit and push
echo "Pushing initial commit..."
git add .
git commit -m "Initial setup: ${APP_NAME} (${BUNDLE_ID})"
git push

echo ""
echo "============================================"
echo "Customer repo created: ${REPO_FULL}"
echo "============================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Configure signing secrets:"
echo "   gh secret set ANDROID_KEYSTORE_BASE64 --repo ${REPO_FULL} < keystore.b64"
echo "   gh secret set ANDROID_KEYSTORE_PASSWORD --repo ${REPO_FULL}"
echo "   gh secret set ANDROID_KEY_ALIAS --repo ${REPO_FULL}"
echo "   gh secret set ANDROID_KEY_PASSWORD --repo ${REPO_FULL}"
echo "   gh secret set APPLE_TEAM_ID --repo ${REPO_FULL}"
echo "   gh secret set MATCH_GIT_URL --repo ${REPO_FULL}"
echo "   gh secret set MATCH_PASSWORD --repo ${REPO_FULL}"
echo ""
echo "2. Trigger a build:"
echo "   gh workflow run build.yml --repo ${REPO_FULL} -f lynx_bundle_url=<URL>"
echo ""
echo "3. Or dispatch from bundle CI:"
echo "   gh api repos/${REPO_FULL}/dispatches \\"
echo "     -f event_type=build \\"
echo "     -f 'client_payload[bundle_url]=<URL>'"
echo ""
