#!/usr/bin/env bash
# Copies the current SwiftLM sources, activates the OS 27 gate via SWIFTLM_ASSUME_OS27, and builds.
set -euo pipefail
REPO="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$HERE/Sources/SwiftLM" "$HERE/Sources/SwiftLMFoundationModels"
cp -R "$REPO/Sources/SwiftLM" "$HERE/Sources/SwiftLM"
cp -R "$REPO/Sources/SwiftLMFoundationModels" "$HERE/Sources/SwiftLMFoundationModels"
rm -rf "$HERE/Sources/SwiftLM/"*.docc "$HERE/Sources/SwiftLMFoundationModels/"*.docc
perl -pi -e 's/compiler\(>=6\.4\) && !SWIFTLM_OS26_SDK_ONLY/SWIFTLM_ASSUME_OS27/g' "$HERE"/Sources/SwiftLMFoundationModels/*.swift
grep -c "SWIFTLM_ASSUME_OS27" "$HERE"/Sources/SwiftLMFoundationModels/*.swift
cd "$HERE" && swift build 2>&1 | grep -E "error:|warning:|Build complete" | sort -u
