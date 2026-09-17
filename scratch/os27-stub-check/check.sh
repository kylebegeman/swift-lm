#!/usr/bin/env bash
# Copies the current SwiftLLM sources, activates the OS 27 gate via SWIFTLLM_ASSUME_OS27, and builds.
set -euo pipefail
REPO="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$HERE/Sources/SwiftLLM" "$HERE/Sources/SwiftLLMFoundationModels"
cp -R "$REPO/Sources/SwiftLLM" "$HERE/Sources/SwiftLLM"
cp -R "$REPO/Sources/SwiftLLMFoundationModels" "$HERE/Sources/SwiftLLMFoundationModels"
rm -rf "$HERE/Sources/SwiftLLM/"*.docc "$HERE/Sources/SwiftLLMFoundationModels/"*.docc
perl -pi -e 's/compiler\(>=6\.4\) && !SWIFTLLM_OS26_SDK_ONLY/SWIFTLLM_ASSUME_OS27/g' "$HERE"/Sources/SwiftLLMFoundationModels/*.swift
grep -c "SWIFTLLM_ASSUME_OS27" "$HERE"/Sources/SwiftLLMFoundationModels/*.swift
cd "$HERE" && swift build 2>&1 | grep -E "error:|warning:|Build complete" | sort -u
