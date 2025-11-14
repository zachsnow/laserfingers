#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION=${CONFIGURATION:-Debug}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/DerivedData"
LOG_FILE="$ROOT_DIR/build.log"

mkdir -p "$DERIVED_DATA_PATH"
: > "$LOG_FILE"

BUILD_TIMESTAMP="$(
python3 - <<'PY'
import datetime
now = datetime.datetime.now(datetime.timezone.utc)
print(now.isoformat(timespec='milliseconds').replace('+00:00', 'Z'))
PY
)"

export BUILD_TIMESTAMP

echo "Building for device..."
echo "Using build timestamp: $BUILD_TIMESTAMP" | tee -a "$LOG_FILE"

if xcodebuild \
  -project "$ROOT_DIR/app/laserfingers.xcodeproj" \
  -scheme Laserfingers \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  BUILD_TIMESTAMP="$BUILD_TIMESTAMP" \
  -allowProvisioningUpdates \
  build >>"$LOG_FILE" 2>&1; then
  echo "Build succeeded."
else
  echo "Build failed." >&2
  grep "error:" build.log
  exit 1
fi
