#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_PATH=""
SCHEME=""
CONFIGURATION="Release"
DESTINATION_DIR="/Applications"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Archives the macOS app and installs the resulting .app into /Applications.

Options:
  --project <path>        Path to .xcodeproj (default: auto-detect top-level project)
  --scheme <name>         Xcode scheme name (default: rssreader)
  --configuration <name>  Build configuration (default: Release)
  --destination <path>    Install directory for .app (default: /Applications)
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_PATH="${2:-}"
      shift 2
      ;;
    --scheme)
      SCHEME="${2:-}"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --destination)
      DESTINATION_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required but not found in PATH." >&2
  exit 1
fi

cd "$REPO_ROOT"

if [[ -z "$PROJECT_PATH" ]]; then
  shopt -s nullglob
  projects=("$REPO_ROOT"/*.xcodeproj)
  shopt -u nullglob

  if [[ ${#projects[@]} -eq 0 ]]; then
    echo "No .xcodeproj found in $REPO_ROOT" >&2
    exit 1
  fi

  if [[ ${#projects[@]} -gt 1 ]]; then
    echo "Multiple .xcodeproj files found. Specify one with --project." >&2
    printf '  %s\n' "${projects[@]}" >&2
    exit 1
  fi

  PROJECT_PATH="${projects[0]}"
elif [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Project not found: $PROJECT_PATH" >&2
  exit 1
fi

if [[ -z "$SCHEME" ]]; then
  SCHEME="rssreader"
fi

if [[ ! -d "$DESTINATION_DIR" ]]; then
  echo "Destination directory does not exist: $DESTINATION_DIR" >&2
  exit 1
fi

echo "Project: $PROJECT_PATH"
echo "Scheme: $SCHEME"
echo "Configuration: $CONFIGURATION"
echo "Destination: $DESTINATION_DIR"

FULL_PRODUCT_NAME="$({
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null |
    awk -F ' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / {print $2; exit}'
} || true)"

if [[ -z "$FULL_PRODUCT_NAME" ]]; then
  echo "Could not resolve FULL_PRODUCT_NAME for scheme '$SCHEME'." >&2
  exit 1
fi

ARCHIVE_ROOT="$REPO_ROOT/build/archives"
mkdir -p "$ARCHIVE_ROOT"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="$ARCHIVE_ROOT/${SCHEME}-${TIMESTAMP}.xcarchive"

echo "Creating archive at: $ARCHIVE_PATH"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive

SOURCE_APP="$ARCHIVE_PATH/Products/Applications/$FULL_PRODUCT_NAME"
if [[ ! -d "$SOURCE_APP" ]]; then
  SOURCE_APP="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -type d -name '*.app' | head -n 1 || true)"
fi

if [[ -z "$SOURCE_APP" || ! -d "$SOURCE_APP" ]]; then
  echo "Could not find archived .app in $ARCHIVE_PATH/Products/Applications" >&2
  exit 1
fi

APP_BASENAME="$(basename "$SOURCE_APP")"
DEST_APP="$DESTINATION_DIR/$APP_BASENAME"

echo "Installing $APP_BASENAME to $DESTINATION_DIR"
if [[ -w "$DESTINATION_DIR" ]]; then
  rm -rf "$DEST_APP"
  ditto "$SOURCE_APP" "$DEST_APP"
else
  sudo rm -rf "$DEST_APP"
  sudo ditto "$SOURCE_APP" "$DEST_APP"
fi

echo "Installed: $DEST_APP"
