#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p artifacts
OUT_ZIP="artifacts/TamHoc-review.zip"
rm -f "$OUT_ZIP"

git archive --format=zip --prefix=TamHoc/ -o "$OUT_ZIP" HEAD

# Verify no forbidden secrets or build artifacts are inside the review archive
if unzip -l "$OUT_ZIP" | grep -qE '\.(p12|p8|cer|mobileprovision|provisionprofile|ipa|xcuserstate)$|DerivedData/|ExportOptions\.plist$'; then
  echo "ERROR: Forbidden secret, profile, or build artifact detected inside $OUT_ZIP" >&2
  rm -f "$OUT_ZIP"
  exit 1
fi

echo "Created clean review archive: $OUT_ZIP"
