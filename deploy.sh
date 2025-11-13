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

  local app_path="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/Laserfingers.app"

  # Check if app already exists
  if [[ ! -d "$app_path" ]]; then
    echo "No existing build found at $app_path"
    echo "Running build.sh to create device build..."

    # Run build.sh with device mode enabled
    if ! BUILD_FOR_DEVICE=true CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/build.sh"; then
      echo "Error: build.sh failed" >&2
      return 1
    fi

    # Verify build was created
    if [[ ! -d "$app_path" ]]; then
      echo "Error: Build completed but app not found at $app_path" >&2
      return 1
    fi
  else
    echo "Using existing build at $app_path"
  fi

  echo "Installing build to device $DEVICE_ID via devicectl…"
  echo "Deploying..."
  xcrun devicectl device install app --device "$DEVICE_ID" "$app_path"
  echo "Deployed Laserfingers to device $DEVICE_ID."
}

echo "Deploying..."
if deploy >>"$LOG_FILE" 2>&1; then
  echo "Deploy succeeded."
else
  echo "Deploy failed." >&2
  exit 1
fi
