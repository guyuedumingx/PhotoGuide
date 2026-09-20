#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "xcodegen not found; installing with Homebrew..."
    brew install xcodegen
  else
    echo "xcodegen is required. Install it first: https://github.com/yonaskolb/XcodeGen"
    exit 1
  fi
fi

xcodegen generate
open PhotoGuide.xcodeproj
