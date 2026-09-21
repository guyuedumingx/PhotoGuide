#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if command -v xcodegen >/dev/null 2>&1; then
  echo "Generating PhotoGuide.xcodeproj with XcodeGen..."
  xcodegen generate
else
  echo "XcodeGen not found; using the bundled deterministic project generator..."
  python3 scripts/generate-xcodeproj.py
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  open PhotoGuide.xcodeproj
else
  echo "Generated: $PWD/PhotoGuide.xcodeproj"
fi
