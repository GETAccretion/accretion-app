#!/usr/bin/env bash
# Run the Core unit tests: copies the app's Feather/Backend/Core/*.swift, unchanged, into the test
# package and runs `swift test` (the tests use @testable import, so internal code is visible).
# Needs macOS with Swift (Xcode or a toolchain).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/Sources/AccretionCore"
rm -rf "$src"
mkdir -p "$src"
cp "$here"/../Feather/Backend/Core/*.swift "$src/"
cd "$here"
swift test "$@"
