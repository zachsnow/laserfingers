#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/DerivedData"

if [[ -d "$DERIVED_DATA_PATH" ]]; then
  rm -rf "$DERIVED_DATA_PATH"
  echo "Removed DerivedData at $DERIVED_DATA_PATH."
else
  echo "No DerivedData directory found at $DERIVED_DATA_PATH."
fi
