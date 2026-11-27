#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$REPO_ROOT/.env"
DERIVED_DATA="$REPO_ROOT/build/iphone"

if [[ $# -gt 0 ]]; then
  echo "Usage: $(basename "$0")" >&2
  exit 1
fi

source "$SCRIPT_DIR/load_env.sh"
load_device_env "$CONFIG_PATH"

if [[ ! "$DEVICE_ID" =~ ^[[:xdigit:]-]+$ ]]; then
  echo "Set DEVICE_ID in .env or on the command line using 'make devices'. Copy .env.example to .env if needed." >&2
  exit 1
fi

for tool in xcodebuild xcrun; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required but not found in PATH." >&2
    exit 1
  fi
done

echo "Building iPhone app..."
xcodebuild \
  -project "$REPO_ROOT/rssreader.xcodeproj" \
  -scheme rssreader \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/SDC RSS.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found: $APP_PATH" >&2
  exit 1
fi

echo "Installing iPhone app..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "Launching iPhone app..."
xcrun devicectl device process launch --device "$DEVICE_ID" com.seferdesign.rssreader
