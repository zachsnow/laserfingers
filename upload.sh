#!/usr/bin/env bash

# Simple helper to validate and upload an .ipa/.pkg to App Store Connect via altool.
# Usage:
#   ./upload.sh --file path/to/app.ipa --username apple-id@example.com [--password app-specific-password] [--platform ios] [--skip-validate]
#
# Password can also be supplied via the ASC_PASSWORD (preferred), ALTOOL_PASSWORD environment variable, or macOS keychain.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/DerivedData"
ARCHIVE_PATH="$DERIVED_DATA_PATH/Laserfingers.xcarchive"
DEFAULT_FILE="$DERIVED_DATA_PATH/Laserfingers.ipa"
LOG_FILE="$ROOT_DIR/upload.log"

: > "$LOG_FILE"

usage() {
    cat <<EOF
Usage: $0 [--file <ipa|pkg>] [--username <apple-id>] [--password <app-password>] [--platform ios|macos] [--skip-validate] [--skip-build]

Options:
  --file           Path to the IPA/PKG produced by Xcode (default: $DEFAULT_FILE)
  --username       Apple ID used for App Store Connect (default: z@zachsnow.com)
  --password       App-specific password. If omitted, ASC_PASSWORD/ALTOOL_PASSWORD env vars are used, or the keychain entry 'Gernal Upload Password'.
  --platform       Platform passed to altool (default: ios)
  --skip-validate  Skip the validation step and upload directly
  --skip-build     Assume the IPA already exists; do not run xcodebuild
  -h, --help       Show this message
EOF
}

IPA_PATH="$DEFAULT_FILE"
USERNAME="z@zachsnow.com"
PASSWORD="${ASC_PASSWORD:-${ALTOOL_PASSWORD:-}}"
PLATFORM="ios"
SKIP_VALIDATE=0
SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)
            IPA_PATH="${2:-}"
            shift 2
            ;;
        --username)
            USERNAME="${2:-}"
            shift 2
            ;;
        --password)
            PASSWORD="${2:-}"
            shift 2
            ;;
        --platform)
            PLATFORM="${2:-}"
            shift 2
            ;;
        --skip-validate)
            SKIP_VALIDATE=1
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ $SKIP_BUILD -eq 0 ]]; then
    echo "Building..."
    rm -rf "$ARCHIVE_PATH" "$IPA_PATH"
    mkdir -p "$DERIVED_DATA_PATH"

    if ! xcodebuild \
        -project "$ROOT_DIR/app/Laserfingers.xcodeproj" \
        -scheme "Laserfingers" \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -archivePath "$ARCHIVE_PATH" \
        IPHONEOS_DEPLOYMENT_TARGET=18.0 \
        -allowProvisioningUpdates \
        clean archive >>"$LOG_FILE" 2>&1; then
        echo "Build failed."
        exit 1
    fi

    EXPORT_PLIST="$DERIVED_DATA_PATH/ExportOptions.plist"
    cat >"$EXPORT_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>compileBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST

    echo "Exporting..."
    if ! xcodebuild \
        -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$EXPORT_PLIST" \
        -allowProvisioningUpdates \
        -exportPath "$DERIVED_DATA_PATH" >>"$LOG_FILE" 2>&1; then
        echo "Export failed."
        exit 1
    fi
fi

if [[ ! -f "$IPA_PATH" ]]; then
    echo "Error: File not found at $IPA_PATH" >&2
    if [[ $SKIP_BUILD -eq 1 ]]; then
        echo "Specify the correct artifact with --file or remove --skip-build to rebuild automatically."
    else
        echo "Build export did not produce $IPA_PATH; check xcodebuild output."
    fi
    exit 1
fi

if [[ -z "$PASSWORD" ]]; then
    KEYCHAIN_SERVICE="Gernal Upload Password"
    KEYCHAIN_ACCOUNT="$USERNAME"
    if PASSWORD=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>>"$LOG_FILE"); then
        :
    else
        echo "Error: Provide an App Store Connect app-specific password via --password, ASC_PASSWORD/ALTOOL_PASSWORD env vars, or store it in the keychain (service: '$KEYCHAIN_SERVICE', account: '$KEYCHAIN_ACCOUNT')." >&2
        exit 1
    fi
fi

ALTOOL_ARGS=(
    "--file" "$IPA_PATH"
    "--type" "$PLATFORM"
    "--username" "$USERNAME"
    "--password" "$PASSWORD"
    "--output-format" "xml"
)

if [[ $SKIP_VALIDATE -eq 0 ]]; then
    echo "Validating..."
    if ! xcrun altool --validate-app "${ALTOOL_ARGS[@]}" >>"$LOG_FILE" 2>&1; then
        echo "Validate failed."
        exit 1
    fi
fi

echo "Uploading..."
if ! xcrun altool --upload-app "${ALTOOL_ARGS[@]}" >>"$LOG_FILE" 2>&1; then
    echo "Upload failed."
    exit 1
fi

echo "Upload succeeded."
