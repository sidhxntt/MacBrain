#!/usr/bin/env bash
set -euo pipefail
APP_BUNDLE="${1:-dist/MacBrain.app}"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/MacBrain"
if [[ ! -d "$APP_BUNDLE" || ! -x "$APP_BINARY" || ! -f "$INFO_PLIST" ]]; then
  echo "Release check requires a complete MacBrain.app bundle at $APP_BUNDLE" >&2; exit 1
fi
for key in CFBundleIdentifier LSMinimumSystemVersion NSAppleEventsUsageDescription NSCalendarsFullAccessUsageDescription NSRemindersFullAccessUsageDescription NSContactsUsageDescription NSPhotoLibraryUsageDescription; do
  /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" >/dev/null
done
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE" 2>&1 | grep -q 'com.apple.security.app-sandbox'
if [[ "${REQUIRE_NOTARIZATION:-0}" == "1" ]]; then
  [[ -n "${NOTARY_PROFILE:-}" ]] || { echo "REQUIRE_NOTARIZATION=1 needs NOTARY_PROFILE; its value is never printed." >&2; exit 1; }
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
fi
echo "Release checks passed for $APP_BUNDLE"
