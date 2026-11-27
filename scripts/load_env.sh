#!/usr/bin/env bash

load_device_env() {
  local config_path="$1"
  local line=""
  local line_number=0
  local seen_device=0
  local seen_simulator=0
  DEVICE_ID="${DEVICE_ID:-}"
  SIMULATOR_ID="${SIMULATOR_ID:-}"

  [[ -f "$config_path" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    if [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    if [[ "$line" =~ ^DEVICE_ID=([[:xdigit:]-]*)$ && "$seen_device" == 0 ]]; then
      seen_device=1
      if [[ -z "$DEVICE_ID" ]]; then
        DEVICE_ID="${BASH_REMATCH[1]}"
      fi
    elif [[ "$line" =~ ^SIMULATOR_ID=([[:xdigit:]-]*)$ && "$seen_simulator" == 0 ]]; then
      seen_simulator=1
      if [[ -z "$SIMULATOR_ID" ]]; then
        SIMULATOR_ID="${BASH_REMATCH[1]}"
      fi
    else
      echo "Invalid .env line $line_number. Use one unquoted DEVICE_ID and/or SIMULATOR_ID assignment, with optional comments." >&2
      return 1
    fi
  done < "$config_path"
}
