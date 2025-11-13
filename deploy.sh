#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID=${DEVICE_ID:-"00008130-001E6D6A3821401C"}
CONFIGURATION=${CONFIGURATION:-Debug}
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/DerivedData"
LOG_FILE="$ROOT_DIR/deploy.log"

: > "$LOG_FILE"

deploy() {
  if [[ -z "${DEVICE_ID}" ]]; then
    echo "Error: DEVICE_ID not set." >&2
    return 1
  fi

  mkdir -p "$DERIVED_DATA_PATH"

  echo "Building Laserfingers ($CONFIGURATION) for device $DEVICE_ID with incremental settings…"
  xcodebuild \
    -project "$ROOT_DIR/app/laserfingers.xcodeproj" \
    -scheme Laserfingers \
    -configuration "$CONFIGURATION" \
    -destination "id=$DEVICE_ID" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -allowProvisioningUpdates \
    build

  local app_path="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/Laserfingers.app"

  if [[ ! -d "$app_path" ]]; then
    echo "Error: built app not found at $app_path" >&2
    return 1
  fi

  echo "Installing build to device $DEVICE_ID via devicectl…"
  echo "Deploying..."
  xcrun devicectl device install app --device "$DEVICE_ID" "$app_path"
  echo "Deployed Laserfingers to device $DEVICE_ID using incremental build."
}

echo "Deploying..."
if deploy >>"$LOG_FILE" 2>&1; then
  echo "Deploy succeeded."
else
  echo "Deploy failed." >&2
  exit 1
fi
