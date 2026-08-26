#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MacBrain"
BUNDLE_ID="com.macbrain.app"
LOCAL_SIGNING_IDENTITY="${MACBRAIN_SIGNING_IDENTITY:-MacBrain Local Code Signing}"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
CLANG_CACHE_DIR="/tmp/macbrain-clang-cache"
SWIFTPM_CACHE_DIR="/tmp/macbrain-swiftpm-cache"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
mkdir -p "$CLANG_CACHE_DIR" "$SWIFTPM_CACHE_DIR"
env CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" SWIFTPM_CACHE_PATH="$SWIFTPM_CACHE_DIR" swift build --disable-sandbox
BUILD_BINARY="$(env CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" SWIFTPM_CACHE_PATH="$SWIFTPM_CACHE_DIR" swift build --disable-sandbox --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/top.svg" "$APP_RESOURCES/top.svg"
cp "$ROOT_DIR/center.svg" "$APP_RESOURCES/center.svg"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>MacBrain</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>NSAppleEventsUsageDescription</key><string>MacBrain uses Automation to sync Apple Notes and Apple Mail locally on this Mac.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>MacBrain reads your Calendar locally to recall work context.</string>
  <key>NSRemindersFullAccessUsageDescription</key><string>MacBrain reads your Reminders locally to recall work context.</string>
  <key>NSContactsUsageDescription</key><string>MacBrain reads Contacts locally to identify people in your work context.</string>
  <key>NSPhotoLibraryUsageDescription</key><string>MacBrain reads Photos metadata locally to recall work context; it does not import original media.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Bind the executable and Info.plist into a single, stable app identity. Prefer
# a persistent local signing identity when present; retain ad-hoc signing as a
# fallback for contributors who have not created one yet.
if /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$LOCAL_SIGNING_IDENTITY\""; then
  /usr/bin/codesign --force --deep --sign "$LOCAL_SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
else
  /usr/bin/codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --bundle|bundle)
    echo "Built $APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME launched successfully"
    ;;
  *)
    echo "usage: $0 [run|--bundle|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
