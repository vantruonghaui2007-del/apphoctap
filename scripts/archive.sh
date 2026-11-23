#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "BLOCKED: archive.sh requires macOS with Xcode installed." >&2
  exit 1
fi

mkdir -p artifacts
ARCHIVE_PATH="artifacts/TamHoc.xcarchive"
EXPORT_DIR="artifacts/export"
BUNDLE_ID="${TAMHOC_BUNDLE_ID:-vn.tamhoc.app}"

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

if [[ "${TAMHOC_UNSIGNED:-0}" == "1" ]]; then
  echo "==> Creating UNSIGNED compile-only archive (cannot be installed as an IPA)"
  xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    archive
  echo "UNSIGNED ARTIFACT ONLY: $ARCHIVE_PATH (do NOT rename .app to .ipa)"
  exit 0
fi

if [[ -z "${TAMHOC_TEAM_ID:-}" ]]; then
  echo "BLOCKED: TAMHOC_TEAM_ID is required for signed archive/export (or pass TAMHOC_UNSIGNED=1 for compile check)." >&2
  exit 1
fi

if [[ -z "${TAMHOC_EXPORT_OPTIONS_PLIST:-}" || ! -f "${TAMHOC_EXPORT_OPTIONS_PLIST:-}" ]]; then
  echo "BLOCKED: Set TAMHOC_EXPORT_OPTIONS_PLIST to a host-generated ExportOptions.plist (see Config/ExportOptions.template.plist)." >&2
  exit 1
fi

echo "==> Archiving TamHoc for iOS device (Bundle ID: $BUNDLE_ID)"
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TAMHOC_TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  archive

echo "==> Exporting signed IPA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$TAMHOC_EXPORT_OPTIONS_PLIST"

IPA_FILE="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -n 1)"
if [[ -z "$IPA_FILE" ]]; then
  echo "ERROR: Export finished without producing an .ipa (Personal Team may require direct Xcode USB install instead)." >&2
  exit 1
fi

echo "==> Inspecting exported IPA: $IPA_FILE"
INSPECT_DIR="$(mktemp -d)"
trap 'rm -rf "$INSPECT_DIR"' EXIT
unzip -q "$IPA_FILE" -d "$INSPECT_DIR"

APP_DIR="$(find "$INSPECT_DIR/Payload" -maxdepth 1 -name '*.app' | head -n 1)"
if [[ -z "$APP_DIR" ]]; then
  echo "ERROR: Invalid IPA — missing Payload/*.app" >&2
  exit 1
fi

MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP_DIR/Info.plist")"
APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Info.plist")"
EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_DIR/Info.plist")"
ARCH_INFO="$(lipo -info "$APP_DIR/$EXEC_NAME")"

echo "Bundle ID: $APP_BUNDLE_ID"
echo "MinimumOSVersion: $MIN_OS"
echo "Architectures: $ARCH_INFO"

if [[ "$MIN_OS" != "15.7" ]]; then
  echo "ERROR: Expected MinimumOSVersion 15.7, got $MIN_OS" >&2
  exit 1
fi

if [[ "$ARCH_INFO" != *"arm64"* ]]; then
  echo "ERROR: Missing arm64 architecture in $EXEC_NAME" >&2
  exit 1
fi

if [[ ! -f "$APP_DIR/embedded.mobileprovision" ]]; then
  echo "ERROR: Missing embedded.mobileprovision in exported IPA" >&2
  exit 1
fi

echo "==> Checking entitlements (sensitive UDID list omitted)"
if ! codesign -d --entitlements :- "$APP_DIR"; then
  echo "ERROR: codesign failed to read entitlements from $APP_DIR" >&2
  exit 1
fi

echo "==> Checking provisioning expiration (UDIDs excluded)"
PROFILE_PLIST="$INSPECT_DIR/profile.plist"
security cms -D -i "$APP_DIR/embedded.mobileprovision" > "$PROFILE_PLIST"
/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$PROFILE_PLIST"
/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$PROFILE_PLIST"

echo "==> Signed IPA verified: $IPA_FILE"
