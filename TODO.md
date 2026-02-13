# Multi-Customer Build Pipeline — Step-by-Step Plan

## Overview

Build platform-specific apps (iOS + Android) for 20+ customers using a single template repo.
Each customer differs only by **app name** and **bundle ID**. VIP customers get isolated read
access to their own builds. Bundles (`main.lynx.bundle`) are produced by a separate CI pipeline.

**Architecture**: Reusable GH Actions workflow in template repo + lightweight per-customer repos.

```
┌─────────────────────────────────┐
│  lynxjs-template (template)     │
│  - iOS/Android native code      │
│  - Reusable GH Actions workflow │
│  - Build scripts                │
│  - Provisioning script          │
└──────────────┬──────────────────┘
               │  workflow_call
    ┌──────────┼──────────┐
    ▼          ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐
│ app-   │ │ app-   │ │ app-   │   Per-customer repos
│ acme   │ │ globex │ │ ...    │   (config + workflow ref only)
└────────┘ └────────┘ └────────┘
```

---

## Phase 1: Create Reusable Workflow in Template Repo

The core idea: refactor the existing `build.yml` into a reusable workflow that accepts
customer parameters via `workflow_call` inputs.

### Step 1.1: Create `.github/workflows/build-reusable.yml`

Create a new reusable workflow file. This is the current `build.yml` adapted to use
`workflow_call` instead of `workflow_dispatch`:

```yaml
name: Build App (Reusable)

on:
  workflow_call:
    inputs:
      app_name:
        description: 'App name (e.g. AcmeApp)'
        required: true
        type: string
      bundle_id:
        description: 'Bundle/Package ID (e.g. com.acme.app)'
        required: true
        type: string
      lynx_bundle_url:
        description: 'URL to download main.lynx.bundle'
        required: true
        type: string
      ios_team_id:
        description: 'Apple Developer Team ID'
        required: false
        type: string
        default: ''
      build_android:
        description: 'Build Android'
        required: false
        type: boolean
        default: true
      build_ios:
        description: 'Build iOS'
        required: false
        type: boolean
        default: true
    secrets:
      # iOS signing
      APPLE_TEAM_ID:
        required: false
      MATCH_GIT_URL:
        required: false
      MATCH_PASSWORD:
        required: false
      MATCH_GIT_BASIC_AUTHORIZATION:
        required: false
      APPLE_ID:
        required: false
      ITC_TEAM_ID:
        required: false
      # Android signing
      ANDROID_KEYSTORE_BASE64:
        required: false
      ANDROID_KEYSTORE_PASSWORD:
        required: false
      ANDROID_KEY_ALIAS:
        required: false
      ANDROID_KEY_PASSWORD:
        required: false

jobs:
  build-android:
    if: ${{ inputs.build_android }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # ... (same steps as current build.yml android job)
      # Replace github.event.inputs.* with inputs.*

  build-ios:
    if: ${{ inputs.build_ios }}
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      # ... (same steps as current build.yml ios job)
      # Replace github.event.inputs.* with inputs.*
```

Key differences from current `build.yml`:
- Trigger: `workflow_call` instead of `workflow_dispatch`
- Parameters: `inputs.*` instead of `github.event.inputs.*`
- Secrets: explicitly declared and passed through
- Conditional platform builds via `build_android`/`build_ios` flags

### Step 1.2: Update existing `build.yml` to call the reusable workflow

Simplify `build.yml` to be a thin wrapper that calls `build-reusable.yml`.
This lets you still trigger builds directly on the template repo for testing:

```yaml
name: Build (Direct)

on:
  workflow_dispatch:
    inputs:
      app_name:
        description: 'App name'
        required: true
        default: 'MyApp'
      bundle_id:
        description: 'Bundle/Package ID'
        required: true
        default: 'com.example.myapp'
      lynx_bundle_url:
        description: 'URL to download main.lynx.bundle'
        required: true

jobs:
  build:
    uses: ./.github/workflows/build-reusable.yml
    with:
      app_name: ${{ github.event.inputs.app_name }}
      bundle_id: ${{ github.event.inputs.bundle_id }}
      lynx_bundle_url: ${{ github.event.inputs.lynx_bundle_url }}
    secrets: inherit
```

### Step 1.3: Test reusable workflow locally

- [ ] Push the new workflow files to the template repo
- [ ] Trigger `build.yml` via `workflow_dispatch` in GitHub UI
- [ ] Verify both iOS and Android jobs run with the correct parameters
- [ ] Verify artifacts are uploaded

---

## Phase 2: Create Customer Repo Templates

Files that will be stamped into each customer's repo by the provisioning script.

### Step 2.1: Create `templates/customer-repo/` directory

```
templates/customer-repo/
├── .github/
│   └── workflows/
│       └── build.yml.tmpl
└── config.yml.tmpl
```

### Step 2.2: Create workflow template

File: `templates/customer-repo/.github/workflows/build.yml.tmpl`

```yaml
name: Build __APP_NAME__

on:
  repository_dispatch:
    types: [build]
  workflow_dispatch:
    inputs:
      lynx_bundle_url:
        description: 'URL to download main.lynx.bundle'
        required: true

jobs:
  read-config:
    runs-on: ubuntu-latest
    outputs:
      app_name: ${{ steps.config.outputs.app_name }}
      bundle_id: ${{ steps.config.outputs.bundle_id }}
    steps:
      - uses: actions/checkout@v4
      - name: Read customer config
        id: config
        run: |
          echo "app_name=$(yq '.app_name' config.yml)" >> "$GITHUB_OUTPUT"
          echo "bundle_id=$(yq '.bundle_id' config.yml)" >> "$GITHUB_OUTPUT"

  build:
    needs: read-config
    uses: __ORG__/lynxjs-template/.github/workflows/build-reusable.yml@master
    with:
      app_name: ${{ needs.read-config.outputs.app_name }}
      bundle_id: ${{ needs.read-config.outputs.bundle_id }}
      lynx_bundle_url: ${{ github.event.client_payload.bundle_url || github.event.inputs.lynx_bundle_url }}
    secrets: inherit
```

### Step 2.3: Create config template

File: `templates/customer-repo/config.yml.tmpl`

```yaml
app_name: __APP_NAME__
bundle_id: __BUNDLE_ID__
```

---

## Phase 3: Create Customer Provisioning Script

### Step 3.1: Create `scripts/create-customer-repo.sh`

This script automates creating a new customer repo:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/create-customer-repo.sh \
#     --org my-org \
#     --customer acme \
#     --app-name AcmeApp \
#     --bundle-id com.acme.app

# Script should:
# 1. Parse arguments (org, customer slug, app name, bundle ID)
# 2. Create private repo: gh repo create <org>/app-<customer> --private
# 3. Clone the new repo into a temp directory
# 4. Copy templates from templates/customer-repo/ into it
# 5. Replace placeholders: __ORG__, __APP_NAME__, __BUNDLE_ID__
# 6. Rename .tmpl files (remove .tmpl extension)
# 7. Commit and push
# 8. (Optional) Set secrets via gh secret set
```

### Step 3.2: Test provisioning

- [ ] Run the script to create a test customer repo
- [ ] Verify repo structure looks correct
- [ ] Verify the workflow file references the correct template repo

---

## Phase 4: End-to-End Test

### Step 4.1: Create a test customer

```bash
./scripts/create-customer-repo.sh \
  --org <your-org> \
  --customer test-app \
  --app-name TestApp \
  --bundle-id com.example.testapp
```

### Step 4.2: Test manual trigger (workflow_dispatch)

- [ ] Go to the customer repo on GitHub
- [ ] Actions > Build TestApp > Run workflow
- [ ] Provide a test bundle URL (or a dummy file URL)
- [ ] Verify the workflow calls the reusable workflow from template repo
- [ ] Verify iOS + Android jobs run (or at least start and fail gracefully if no signing)

### Step 4.3: Test automated trigger (repository_dispatch)

Simulate what the bundle CI would do:

```bash
curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token <GITHUB_TOKEN>" \
  https://api.github.com/repos/<org>/app-test-app/dispatches \
  -d '{"event_type":"build","client_payload":{"bundle_url":"https://example.com/main.lynx.bundle"}}'
```

- [ ] Verify the workflow triggers
- [ ] Verify the bundle URL is passed through correctly

### Step 4.4: Verify customer isolation

- [ ] Create a second test customer repo
- [ ] Verify a user with read access to repo A cannot see repo B's workflow runs
- [ ] Verify artifacts are scoped to each repo

---

## Phase 5: Production Rollout

### Step 5.1: Template repo finalization

- [ ] Merge `build-reusable.yml` into the template repo's main branch
- [ ] Tag a release (e.g. `v1.0.0`) for stable workflow references
- [ ] Update customer workflow templates to reference `@v1.0.0` instead of `@master`

### Step 5.2: Provision real customers

- [ ] Run the provisioning script for each customer
- [ ] Configure signing secrets per customer repo:
  - iOS: `APPLE_TEAM_ID`, `MATCH_GIT_URL`, `MATCH_PASSWORD`, etc.
  - Android: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, etc.

### Step 5.3: Integrate with bundle CI

- [ ] Add a step to the bundle CI that fires `repository_dispatch` to the correct customer repo
- [ ] The dispatch payload must include `bundle_url` pointing to the downloadable bundle artifact

### Step 5.4: Set up VIP customer access

- [ ] Add VIP customers as collaborators with `read` permission to their specific repo
- [ ] They can view source, workflow runs, and download artifacts

---

## Important Notes

- **Cross-repo workflow access**: Reusable workflows from a private repo can only be called
  by repos in the **same organization**. If the template repo is public, any repo can call it.
- **GitHub Actions cost**: macOS runners are 10x the cost of Linux. Consider building iOS only
  when explicitly needed, or use self-hosted runners for scale.
- **Template versioning**: Use tags (`@v1.0.0`) instead of `@master` for stability. Update
  customer workflows when ready to adopt template changes.
- **Secrets inheritance**: `secrets: inherit` passes all of the calling repo's secrets to the
  reusable workflow. Customer-specific signing certs are stored in the customer repo.
- **Config in repo vs hardcoded**: The `read-config` job reads `config.yml` so changes can be
  made in one place. Alternatively, hardcode values directly in the workflow for simplicity.
