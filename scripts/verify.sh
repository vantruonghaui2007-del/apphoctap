#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "BLOCKED: verify.sh requires macOS with Xcode installed." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "BLOCKED: xcodebuild not found. Install Xcode and select active developer directory." >&2
  exit 1
fi

echo "==> Checking toolchain versions"
xcodebuild -version
xcrun swift --version

echo "==> Checking project config constraints"
grep -q "IPHONEOS_DEPLOYMENT_TARGET = 15.7" Config/Debug.xcconfig
grep -q "IPHONEOS_DEPLOYMENT_TARGET = 15.7" Config/Release.xcconfig
grep -q "SWIFT_VERSION = 5.0" Config/Debug.xcconfig
grep -q "SWIFT_VERSION = 5.0" Config/Release.xcconfig

echo "==> Checking for forbidden private APIs or unused entitlements"
if grep -rnE "requestGuidedAccessSession|App-Prefs:|prefs:root|FamilyControls|com\.apple\.developer\.family-controls" TamHoc/ Config/ TamHoc.xcodeproj/; then
  echo "ERROR: Found forbidden API or unused capability in default target." >&2
  exit 1
fi

echo "==> Checking available destinations"
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -showdestinations

echo "==> Running StudyCore Swift Package tests"
swift test --package-path Packages/StudyCore

echo "==> Building TamHoc Debug (iOS Simulator, unsigned compile check)"
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

echo "==> Building TamHoc Release (iOS Device, unsigned compile check)"
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

RELEASE_APP_PLIST="$(xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -showBuildSettings | awk -F ' = ' '$1 ~ /^ *TARGET_BUILD_DIR$/{dir=$2} $1 ~ /^ *INFOPLIST_PATH$/{plist=$2} END{print dir "/" plist}')"
if [[ -f "$RELEASE_APP_PLIST" ]]; then
  MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$RELEASE_APP_PLIST")"
  echo "Release MinimumOSVersion = $MIN_OS"
  if [[ "$MIN_OS" != "15.7" ]]; then
    echo "ERROR: Expected MinimumOSVersion 15.7, got $MIN_OS" >&2
    exit 1
  fi
fi

if [[ -z "${TAMHOC_SIMULATOR_ID:-}" ]]; then
  echo "ERROR: TAMHOC_SIMULATOR_ID is not set. Pick a simulator UDID from -showdestinations above and re-run." >&2
  exit 1
fi

mkdir -p artifacts
rm -rf artifacts/Tests.xcresult

echo "==> Running TamHocTests and TamHocUITests on Simulator $TAMHOC_SIMULATOR_ID"
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc \
  -destination "platform=iOS Simulator,id=$TAMHOC_SIMULATOR_ID" \
  -resultBundlePath artifacts/Tests.xcresult \
  test

echo "==> verify.sh SUCCEEDED"
