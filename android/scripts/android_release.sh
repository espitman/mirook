#!/bin/bash

set -euo pipefail

PROJECT_ROOT="/Users/espitman/Documents/Projects/Mirook"
ANDROID_PROJECT_ROOT="$PROJECT_ROOT/android"
DESKTOP_DIR="$HOME/Desktop"

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
JAVA_HOME="${JAVA_HOME:-/Users/espitman/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

if [ ! -x "$ANDROID_PROJECT_ROOT/gradlew" ]; then
  echo "Error: gradlew not found at $ANDROID_PROJECT_ROOT/gradlew"
  echo "Create the Android project at $ANDROID_PROJECT_ROOT before running this script."
  exit 1
fi

echo "Building Mirook Android reader release APK..."
cd "$ANDROID_PROJECT_ROOT"
./gradlew :app:assembleRelease

APK_PATH="$ANDROID_PROJECT_ROOT/app/build/outputs/apk/release/app-release.apk"

if [ ! -f "$APK_PATH" ]; then
  echo "Error: Release APK not found in $ANDROID_PROJECT_ROOT/app/build/outputs/apk/release"
  exit 1
fi

OUT_APK="$DESKTOP_DIR/mirook-reader-release.apk"
cp "$APK_PATH" "$OUT_APK"

echo "Release APK copied to:"
echo "$OUT_APK"
