#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA="$REPO_ROOT/build/ios-simulator"
SIMULATOR_ID="${SIMULATOR_ID:-}"
SLIM_SIMULATOR="${SLIM_SIMULATOR:-0}"
CONFIG_PATH="$REPO_ROOT/.env"

if [[ $# -gt 0 ]]; then
  echo "Usage: SIMULATOR_ID=<UDID> [SLIM_SIMULATOR=1] $(basename "$0")" >&2
  exit 1
fi

source "$SCRIPT_DIR/load_env.sh"
load_device_env "$CONFIG_PATH"

if [[ ! "$SIMULATOR_ID" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
  echo "Set SIMULATOR_ID in .env or on the command line using a UDID from 'make simulators'. Copy .env.example to .env if needed." >&2
  exit 1
fi

if [[ "$SLIM_SIMULATOR" != 0 && "$SLIM_SIMULATOR" != 1 ]]; then
  echo "SLIM_SIMULATOR must be 0 or 1." >&2
  exit 1
fi

for tool in xcodebuild xcrun xcode-select open; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required but not found in PATH." >&2
    exit 1
  fi
done

DEVELOPER_DIRECTORY="${DEVELOPER_DIR:-$(xcode-select -p)}"
FRONTEND_APP=""
for candidate in \
  "$DEVELOPER_DIRECTORY/Applications/Simulator.app" \
  "$DEVELOPER_DIRECTORY/../Applications/Simulator.app" \
  "$DEVELOPER_DIRECTORY/../Applications/DeviceHub.app"; do
  if [[ -d "$candidate" ]]; then
    FRONTEND_APP="$candidate"
    break
  fi
done
if [[ -z "$FRONTEND_APP" ]]; then
  echo "Neither Simulator.app nor DeviceHub.app was found in the selected Xcode." >&2
  exit 1
fi

if [[ "$SLIM_SIMULATOR" == 1 ]] && ! command -v simslim >/dev/null 2>&1; then
  echo "simslim is required for slimming. Install it with 'brew install mobai-app/tap/simslim'." >&2
  exit 1
fi

echo "Building for simulator $SIMULATOR_ID..."
xcodebuild \
  -project "$REPO_ROOT/rssreader.xcodeproj" \
  -scheme rssreader \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/SDC RSS.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found: $APP_PATH" >&2
  exit 1
fi

echo "Opening simulator frontend..."
if [[ "$FRONTEND_APP" == */Simulator.app ]]; then
  open -a "$FRONTEND_APP" --args -CurrentDeviceUDID "$SIMULATOR_ID"
else
  open -a "$FRONTEND_APP"
fi

echo "Booting simulator..."
xcrun simctl bootstatus "$SIMULATOR_ID" -b

if [[ "$SLIM_SIMULATOR" == 1 ]]; then
  echo "Slimming this simulator, keeping iCloud/Keychain and web services enabled..."
  simslim on "$SIMULATOR_ID" --no-reboot --except icloud,web
  simslim verify "$SIMULATOR_ID" --except icloud,web
  simslim doctor "$SIMULATOR_ID" --requires icloud,keychain-sync,universal-links
fi

echo "Installing simulator app..."
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

echo "Launching simulator app..."
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" com.seferdesign.rssreader
