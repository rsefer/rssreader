#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$REPO_ROOT/.env.iphone"
DERIVED_DATA="$REPO_ROOT/build/iphone"

if [[ $# -gt 0 ]]; then
  echo "Usage: $(basename "$0")" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Copy .env.iphone.example to .env.iphone and set DEVICE_ID from 'xcrun devicectl list devices'." >&2
  exit 1
fi

DEVICE_ID=""
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
    continue
  fi
  if [[ "$line" =~ ^DEVICE_ID=([[:xdigit:]-]+)$ && -z "$DEVICE_ID" ]]; then
    DEVICE_ID="${BASH_REMATCH[1]}"
  else
    echo ".env.iphone must contain one unquoted DEVICE_ID=<identifier> assignment and optional comments." >&2
    exit 1
  fi
done < "$CONFIG_PATH"

if [[ -z "$DEVICE_ID" ]]; then
  echo "Set DEVICE_ID in .env.iphone using 'xcrun devicectl list devices'." >&2
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
