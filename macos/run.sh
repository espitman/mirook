#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

xcodebuild \
  -project Mirook.xcodeproj \
  -scheme Mirook \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

app_path="$(xcodebuild \
  -project Mirook.xcodeproj \
  -scheme Mirook \
  -showBuildSettings \
  | awk -F' = ' '/TARGET_BUILD_DIR/ { build_dir=$2 } /FULL_PRODUCT_NAME/ { product=$2 } END { print build_dir "/" product }')"

if pgrep -x Mirook >/dev/null; then
  osascript -e 'tell application "Mirook" to quit' >/dev/null 2>&1 || true
  sleep 0.5
fi

open -n "$app_path"
